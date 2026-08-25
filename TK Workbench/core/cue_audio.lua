-- Cue audio: the part that has to be on time.
--
-- Lua cannot make a click. The defer loop wanders by tens of milliseconds,
-- which is fine for drawing a beat and useless for playing one, so nothing here
-- produces sound. It writes a schedule - the next few moments that matter, in
-- seconds - into gmem, and a JSFX sitting in the audio thread compares that
-- against its own sample-accurate playback position and fires.
--
-- The JSFX is written by this file rather than shipped beside it. REAPER only
-- loads effects from its own Effects folder, so a shipped copy has to be copied
-- there, and two copies that drift apart is exactly how TrackFX_AddByName ends
-- up instantiating last month's version. Generated, there is one source.

local r = reaper
local Wav = require("core.cue_wav")

local Audio = {}

Audio.GMEM = "tk_cue"
Audio.JSFX_VERSION = 4
Audio.FX_NAME = "TK Cue Click"

-- gmem slots. Kept small and flat on purpose: this is written every frame from
-- the main thread and read every block from the audio thread, so it is a
-- mailbox, not a structure.
local SLOT_VERSION = 0
local SLOT_HEARTBEAT = 1
local SLOT_ENABLED = 2
local SLOT_VOLUME = 3
local SLOT_FLAGS = 4
local SLOT_CHANGE = 5
local SLOT_WARN = 6
local SLOT_LAST_BAR = 7
-- Which sample each cue plays, as an index into the files baked into the
-- effect. -1 means the tone it synthesises itself.
local SLOT_SOUND_WARN = 8
local SLOT_SOUND_COUNT = 9
local SLOT_SOUND_GO = 10
local SLOT_SOUND_BEAT = 11
local SLOT_SOUND_ACCENT = 12

-- The effect reports back up here: what it is, how many sounds it managed to
-- load, and how long each of them turned out to be. Without this the audio
-- thread is a place things disappear into - a cue that plays a tone could mean
-- a stale effect, a file it could not read, or a mapping that never arrived,
-- and from the outside those look identical.
local SLOT_REPORT_VERSION = 20
local SLOT_REPORT_SLOTS = 21
local SLOT_REPORT_FIRST_LEN = 22

-- The sounds themselves live in gmem now: a small directory, then the audio.
-- Nothing but numbers crosses into the audio thread, so there is no path for
-- JSFX to fail to resolve and no rebuild when a sound changes.
local SLOT_GENERATION = 30
local SLOT_COUNT = 31
local SLOT_DIRECTORY = 32      -- 4 words per sound: frames, rate, offset, spare
local AUDIO_BASE = 4096

Audio.MAX_SOUNDS = 16
-- Only the first few seconds of a sound are loaded. A cue is a tick, and
-- somebody will eventually drop a four-minute bounce in that folder.
Audio.MAX_SECONDS = 2
Audio.SOUND_ROLES = { "warn", "count_in", "go", "beat", "accent" }

Audio.FLAG_BEAT = 1
Audio.FLAG_ACCENT = 2
Audio.FLAG_WARN = 4
Audio.FLAG_COUNT_IN = 8
Audio.FLAG_GO = 16

local attached = false
local heartbeat = 0

local function sep()
  return package.config:sub(1, 1)
end

function Audio.folder()
  local base = r.GetResourcePath and r.GetResourcePath() or ""
  return base .. sep() .. "Effects" .. sep() .. "TK Scripts" .. sep() .. "Cue" .. sep()
end

-- Sounds live outside the script folder so a ReaPack update cannot touch them,
-- and outside the project so they are the user's, not one song's.
function Audio.sounds_folder()
  local base = r.GetResourcePath and r.GetResourcePath() or ""
  return base .. sep() .. "TK Cue Sounds" .. sep()
end

-- Only .wav. JSFX reads RIFF and nothing else, and a folder that silently
-- ignores the mp3 someone dropped in it is worse than one that never offered.
function Audio.list_sounds()
  local out = {}
  local root = Audio.sounds_folder()
  if not r.EnumerateFiles then return out end
  r.EnumerateFiles(root, -1)
  local index = 0
  while true do
    local filename = r.EnumerateFiles(root, index)
    if not filename then break end
    if filename:lower():match("%.wav$") then
      out[#out + 1] = { name = filename, path = root .. filename }
    end
    index = index + 1
    if #out >= Audio.MAX_SOUNDS then break end
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

-- The effect is built from the sounds a preset actually uses, not from every
-- wav in the folder. JSFX loads its files into a memory pool with a hard
-- ceiling, and a folder of musical samples - which is what people have lying
-- around - runs past it long before anyone notices, at which point every cue
-- quietly falls back to a tone.
function Audio.used_sounds(preset, files)
  files = files or Audio.sounds()
  local sounds = preset and preset.sounds or {}
  local used, seen = {}, {}
  for _, role in ipairs(Audio.SOUND_ROLES) do
    local name = tostring(sounds[role] or "")
    local key = name:lower()
    if name ~= "" and not seen[key] then
      for _, entry in ipairs(files) do
        if entry.name:lower() == key then
          seen[key] = true
          used[#used + 1] = entry
          break
        end
      end
    end
  end
  return used
end

function Audio.sound_index(files, name)
  name = tostring(name or "")
  if name == "" then return -1 end
  for index, entry in ipairs(files or {}) do
    if entry.name:lower() == name:lower() then return index - 1 end
  end
  return -1
end

function Audio.jsfx_path()
  return Audio.folder() .. "TK_Cue_Click.jsfx"
end

-- The name REAPER knows it by, which for a JSFX is its path relative to the
-- Effects folder.
function Audio.fx_identifier()
  return "TK Scripts/Cue/TK_Cue_Click.jsfx"
end

--------------------------------------------------------------------------------
-- the effect itself
--------------------------------------------------------------------------------

local MARKER = "TK_CUE_GENERATED"

function Audio.jsfx_source()
  return ([[desc:TK Cue Click (TK Workbench)
// %s %d - written by TK Workbench's Cue module.
// Delete the line above to keep your own edits: the module will then leave this
// file alone instead of writing its own version over the top of yours.
options:gmem=tk_cue

@init
  inv = 1 / srate;
  hb_last = -1; hb_age = 99;
  env = 0; env_d = 0; ph = 0; ph_d = 0; amp = 0;
  next_beat = -1; fired = -1;
  s_slot = -1; sp = 0; s_amp = 0;
  gmem[20] = %d;
  gmem[22] = srate;

@block
  ver = gmem[0];
  hb = gmem[1];
  hb != hb_last ? (hb_last = hb; hb_age = 0;) : (hb_age += samplesblock * inv);
  // The heartbeat is the safety catch: if Workbench stops writing it - closed,
  // crashed, module disabled - this goes quiet within a second instead of
  // clicking away at an empty room.
  live = (ver >= 1 && gmem[2] > 0.5 && hb_age < 1 && play_state == 1) ? 1 : 0;
  vol = max(0, min(1, gmem[3]));
  flags = gmem[4] | 0;
  change_t = gmem[5];
  warn_t = gmem[6];
  last_bar_t = gmem[7];
  sounds = gmem[31] | 0;
  gmem[20] = %d;
  gmem[21] = sounds;
  gmem[22] = srate;

  // REAPER counts beat_position in quarter notes; a bar in 6/8 is six eighths,
  // so both are converted into denominator units before anything is counted.
  scale = ts_denom / 4;
  bps = tempo / 60 * scale;
  bstart = beat_position * scale;
  (next_beat < 0 || abs(next_beat - bstart) > 8) ? next_beat = ceil(bstart - 0.0001);
  spl_i = 0;

@sample
  live ? (
    b = bstart + spl_i * bps * inv;
    b >= next_beat ? (
      t = play_position + spl_i * inv;
      bar_beat = next_beat - floor(next_beat / ts_num) * ts_num;

      kind = 0;
      bar_beat == 0 ? kind = 1;
      (warn_t >= 0 && t >= warn_t) ? kind = 2;
      (last_bar_t >= 0 && t >= last_bar_t) ? kind = 3;
      (change_t >= 0 && t >= change_t - 0.02 && fired != change_t) ? (kind = 4; fired = change_t;);

      allow = kind == 0 ? (flags & 1) : (kind == 1 ? (flags & 2) :
              (kind == 2 ? (flags & 4) : (kind == 3 ? (flags & 8) : (flags & 16))));

      allow ? (
        amp = (kind == 4 ? 1.0 : (kind == 1 ? 0.8 : 0.6)) * vol;
        want = kind == 0 ? gmem[11] : (kind == 1 ? gmem[12] : (kind == 2 ? gmem[8] :
               (kind == 3 ? gmem[9] : gmem[10])));
        want = want | 0;
        (want >= 0 && want < sounds && gmem[32 + want * 4] > 0) ? (
          // A sample was uploaded for this cue: play that, and let the
          // synthesised tone stay out of the way.
          s_slot = want; sp = 0; s_amp = amp; env = 0;
        ) : (
          s_slot = -1;
          f = kind == 4 ? 587 : (kind == 3 ? 1319 : (kind == 2 ? 1047 : (kind == 1 ? 880 : 659)));
          ph = 0;
          ph_d = 2 * $pi * f * inv;
          env = 1;
          env_d = exp(-1 / (srate * (kind == 4 ? 0.14 : 0.045)));
        );
      );
      next_beat += 1;
    );

    env > 0.0001 ? (
      s = sin(ph) * env * amp;
      ph += ph_d;
      env *= env_d;
      spl0 += s;
      spl1 += s;
    );

    s_slot >= 0 ? (
      s_len = gmem[32 + s_slot * 4];
      s_rate = gmem[33 + s_slot * 4];
      s_at = gmem[34 + s_slot * 4];
      // Read at the rate it was recorded at, interpolated: a 44.1k tick in a
      // 48k project would otherwise come out sharp and gritty.
      step = s_rate > 0 ? s_rate / srate : 1;
      i0 = floor(sp);
      frac = sp - i0;
      (i0 + 1) < s_len ? (
        a0 = gmem[s_at + i0];
        a1 = gmem[s_at + i0 + 1];
        sm = (a0 + (a1 - a0) * frac) * s_amp;
        spl0 += sm;
        spl1 += sm;
        sp += step;
      ) : s_slot = -1;
    );

    spl_i += 1;
  );
]]):format(MARKER, Audio.JSFX_VERSION, Audio.JSFX_VERSION, Audio.JSFX_VERSION)
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

-- Returns written, path, note. Never overwrites a file that has had the marker
-- taken out of it: that is somebody saying "this one is mine now".
function Audio.ensure_jsfx()
  local path = Audio.jsfx_path()
  local existing = read_file(path)
  if existing then
    local version = tonumber(existing:match(MARKER .. "%s+(%d+)"))
    if not version then return false, path, "left alone: this one has been edited by hand" end
    if version >= Audio.JSFX_VERSION then return false, path, "already up to date" end
  end
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(Audio.folder(), 0) end
  local file = io.open(path, "wb")
  if not file then return false, path, "could not write " .. path end
  file:write(Audio.jsfx_source())
  file:close()
  return true, path, existing and "updated" or "written"
end

--------------------------------------------------------------------------------
-- where it sits
--------------------------------------------------------------------------------

local function master()
  return r.GetMasterTrack and r.GetMasterTrack(0) or nil
end

-- Monitoring FX live in the master track's record chain. That is the default
-- home for the click: it is not part of the project, it is never printed into a
-- render, and taking it out again is one call.
function Audio.monitor_index()
  local track = master()
  if not track or not r.TrackFX_GetRecCount then return nil end
  for index = 0, r.TrackFX_GetRecCount(track) - 1 do
    local _, name = r.TrackFX_GetFXName(track, index | 0x1000000, "")
    if tostring(name or ""):find(Audio.FX_NAME, 1, true) then return index end
  end
  return nil
end

function Audio.track_with_fx()
  if not r.CountTracks then return nil end
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local fx = r.TrackFX_AddByName(track, Audio.fx_identifier(), false, 0)
    if fx and fx >= 0 then return track, fx end
  end
  return nil
end

-- "monitor", "track" or nil.
function Audio.location()
  if Audio.monitor_index() then return "monitor" end
  if Audio.track_with_fx() then return "track" end
  return nil
end

Audio.TRACK_NAME = "TK Cue"

local function track_name(track)
  if not r.GetSetMediaTrackInfo_String then return "" end
  local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  return tostring(name or "")
end

function Audio.find_track()
  if not r.CountTracks then return nil end
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    if track and track_name(track) == Audio.TRACK_NAME then return track end
  end
  return nil
end

-- A track this module made, that holds nothing else and that nobody has wired
-- anything into. Anything else - items on it, another effect, a send the user
-- set up to feed their in-ears - means it is theirs now, and it stays.
local function track_is_disposable(track)
  if not track then return false end
  if track_name(track) ~= Audio.TRACK_NAME then return false end
  if r.CountTrackMediaItems and r.CountTrackMediaItems(track) > 0 then return false end
  if r.TrackFX_GetCount and r.TrackFX_GetCount(track) > 0 then return false end
  if r.GetTrackNumSends then
    for _, category in ipairs({ 0, -1, 1 }) do
      if r.GetTrackNumSends(track, category) > 0 then return false end
    end
  end
  return true
end

-- Installing moves the click rather than adding a second one. Two copies of a
-- metronome are not twice as useful: they are one click you can hear and one
-- you cannot find. And the track that carried it goes with it, or switching
-- back and forth a few times leaves a row of empty tracks behind.
local function remove_track_copy()
  local host, fx = Audio.track_with_fx()
  if not host or not fx or not r.TrackFX_Delete then return false end
  r.TrackFX_Delete(host, fx)
  if track_is_disposable(host) and r.DeleteTrack then r.DeleteTrack(host) end
  return true
end

local function remove_monitor_copy()
  local track = master()
  local index = Audio.monitor_index()
  if track and index and r.TrackFX_Delete then
    r.TrackFX_Delete(track, index | 0x1000000)
    return true
  end
  return false
end

function Audio.install_monitor()
  local written, path, note = Audio.ensure_jsfx()
  local track = master()
  if not track or not r.TrackFX_AddByName then return false, "This REAPER cannot add monitoring FX" end
  local moved = remove_track_copy()
  if Audio.monitor_index() then return true, "The cue click is already in the monitoring FX" end
  local index = r.TrackFX_AddByName(track, Audio.fx_identifier(), true, -1)
  if not index or index < 0 then
    return false, "REAPER would not load " .. path .. " (" .. tostring(note) .. ")"
  end
  return true, moved and "Cue click moved to the monitoring FX"
    or "Cue click added to the monitoring FX"
end

-- The other model: its own track, master send off, so it can be sent to an
-- output of its own. This one does change the project, which is why it is never
-- done without being asked for.
-- The click is written to both channels dead centre, and REAPER's default pan
-- law takes 3 dB off a centred track. Monitoring FX never see a pan law, so the
-- same click sounds markedly quieter once it moves onto a track. Pinning this
-- track's pan law to 0 dB puts the two paths back on the same footing.
local function flatten_pan_law(track)
  if track and r.SetMediaTrackInfo_Value then
    r.SetMediaTrackInfo_Value(track, "D_PANLAW", 1.0)
  end
end

function Audio.install_track()
  Audio.ensure_jsfx()
  if not r.InsertTrackAtIndex then return false, "This REAPER cannot add tracks" end
  local existing = Audio.track_with_fx()
  if existing then
    remove_monitor_copy()
    flatten_pan_law(existing)
    return true, "The cue click already has a track"
  end
  local track = Audio.find_track()
  if not track then
    local count = r.CountTracks(0)
    r.InsertTrackAtIndex(count, true)
    track = r.GetTrack(0, count)
    if not track then return false, "Could not create the cue track" end
    r.GetSetMediaTrackInfo_String(track, "P_NAME", Audio.TRACK_NAME, true)
  end
  flatten_pan_law(track)
  local index = r.TrackFX_AddByName(track, Audio.fx_identifier(), false, -1)
  if not index or index < 0 then
    return false, "REAPER would not load the cue click onto the track"
  end
  -- The master send stays on. Switching it off is what you do once the track
  -- feeds your in-ears through a send of its own, and doing it here would mean
  -- handing someone a cue track that plays into nothing at all.
  local moved = remove_monitor_copy()
  return true, (moved and "Cue click moved to a track called TK Cue. "
    or "Cue click added to a track called TK Cue. ")
    .. "Send it to your in-ear output and switch its master send off to keep it out of the mix. "
    .. "It now runs through your master fader, which monitoring FX did not"
end

function Audio.remove()
  local removed = remove_monitor_copy()
  if remove_track_copy() then removed = true end
  return removed
end

-- Reloading is deleting and re-adding in the same place. It deliberately does
-- not go through remove() and install(): that would take the cue track with it
-- and hand back a fresh one, throwing away whatever the user had routed.
function Audio.reload()
  local track = master()
  local index = Audio.monitor_index()
  if track and index and r.TrackFX_Delete then
    r.TrackFX_Delete(track, index | 0x1000000)
    r.TrackFX_AddByName(track, Audio.fx_identifier(), true, -1)
    return true
  end
  local host, fx = Audio.track_with_fx()
  if host and fx and r.TrackFX_Delete then
    r.TrackFX_Delete(host, fx)
    r.TrackFX_AddByName(host, Audio.fx_identifier(), false, -1)
    return true
  end
  return false
end

local sound_cache = nil

-- The folder is read on demand, not every frame: this walks a directory, and
-- the answer only changes when somebody puts a file in it.
function Audio.sounds(force)
  if force or not sound_cache then sound_cache = Audio.list_sounds() end
  return sound_cache
end

-- Brings everything into line: the effect file itself, which only changes when
-- this module is updated, and the sounds, which change whenever somebody picks
-- a different one. Only the first of those needs the effect reloading.
function Audio.sync(preset, force)
  Audio.sounds(force)
  local written, _, note = Audio.ensure_jsfx()
  if written and Audio.location() then Audio.reload() end
  local changed, sound_note = Audio.upload(preset, force or written)
  return (written or changed), (written and note or sound_note)
end

-- What the running effect says about itself. version 0 means nothing is
-- running, or what is running predates this report and needs reloading.
function Audio.report()
  if not Audio.attach() or not r.gmem_read then return nil end
  local version = tonumber(r.gmem_read(SLOT_REPORT_VERSION)) or 0
  if version <= 0 then return { version = 0, slots = 0, lengths = {} } end
  local slots = math.floor(tonumber(r.gmem_read(SLOT_REPORT_SLOTS)) or 0)
  local rate = math.floor(tonumber(r.gmem_read(SLOT_REPORT_FIRST_LEN)) or 0)
  return { version = version, slots = slots, srate = rate }
end

local function write(slot, value)
  if r.gmem_write then r.gmem_write(slot, value or 0) end
end

local uploaded = { signature = nil, generation = 0, info = {} }

function Audio.upload_info(name)
  return uploaded.info[tostring(name or ""):lower()]
end

-- Reads every sound this preset uses and hands the samples to the audio thread
-- through gmem. Returns changed, note.
--
-- The count is zeroed first and written last: the effect reads the directory
-- every block, and a half-written one is a cue reading somebody else's audio.
function Audio.upload(preset, force)
  if not Audio.attach() or not r.gmem_write then return false, "no shared memory" end
  local used = Audio.used_sounds(preset)
  local names = {}
  for _, entry in ipairs(used) do names[#names + 1] = entry.name end
  local wanted = table.concat(names, "|")
  if not force and uploaded.signature == wanted then return false, "unchanged" end

  write(SLOT_COUNT, 0)
  uploaded.info = {}
  local offset = AUDIO_BASE
  local loaded = 0
  for index, entry in ipairs(used) do
    local slot = index - 1
    local sound, err = Wav.read(entry.path, { max_frames = Audio.MAX_SECONDS * 96000 })
    local frames = 0
    if sound then
      frames = math.min(sound.frames, math.floor(Audio.MAX_SECONDS * sound.rate))
      for i = 1, frames do r.gmem_write(offset + i - 1, sound.samples[i]) end
      write(SLOT_DIRECTORY + slot * 4, frames)
      write(SLOT_DIRECTORY + slot * 4 + 1, sound.rate)
      write(SLOT_DIRECTORY + slot * 4 + 2, offset)
      offset = offset + frames
      loaded = loaded + 1
      uploaded.info[entry.name:lower()] = { frames = frames, rate = sound.rate }
    else
      write(SLOT_DIRECTORY + slot * 4, 0)
      uploaded.info[entry.name:lower()] = { frames = 0, error = tostring(err or "could not be read") }
    end
  end
  write(SLOT_COUNT, #used)
  uploaded.signature = wanted
  uploaded.generation = uploaded.generation + 1
  write(SLOT_GENERATION, uploaded.generation)
  return true, string.format("%d of %d sound%s loaded", loaded, #used, #used == 1 and "" or "s")
end

--------------------------------------------------------------------------------
-- the schedule
--------------------------------------------------------------------------------

function Audio.attach()
  if attached then return true end
  if not r.gmem_attach then return false end
  r.gmem_attach(Audio.GMEM)
  attached = true
  if r.gmem_write then r.gmem_write(SLOT_VERSION, 1) end
  return true
end

function Audio.flags(preset)
  local audio = preset and preset.audio or {}
  local flags = 0
  if audio.beat_click then flags = flags + Audio.FLAG_BEAT end
  if audio.accent ~= false then flags = flags + Audio.FLAG_ACCENT end
  if audio.warn ~= false then flags = flags + Audio.FLAG_WARN end
  if audio.count_in ~= false then flags = flags + Audio.FLAG_COUNT_IN end
  if audio.go ~= false then flags = flags + Audio.FLAG_GO end
  return flags
end

-- The three moments the JSFX needs, in seconds:
--   change   - where the next section starts
--   warn     - the bar line this section's warning window opens on
--   last_bar - the bar line of the final bar before the change
--
-- Both of the latter are bar lines rather than "the change minus n bars in
-- seconds": a tempo change between here and there would make that arithmetic
-- lie, and REAPER can convert a measure number back into a time exactly.
function Audio.schedule(engine, state, warn_bars)
  local change = nil
  if state.next_section then
    change = state.next_section.start
  elseif state.section then
    change = state.section.stop
  end
  if not change then return nil end
  local measure = engine.measure_of(change)
  local at_bar_line = math.abs(measure - math.floor(measure + 0.5)) < 0.001
  local bar = math.floor(measure + 0.5)
  if not at_bar_line then bar = math.floor(measure) end
  return {
    change = change,
    warn = engine.time_of_measure(bar - math.max(1, warn_bars or 2)),
    last_bar = engine.time_of_measure(bar - 1)
  }
end

function Audio.push(engine, state, preset)
  if not Audio.attach() then return false end
  local audio = preset and preset.audio or {}
  heartbeat = (heartbeat + 1) % 1000000
  write(SLOT_VERSION, 1)
  write(SLOT_HEARTBEAT, heartbeat)
  write(SLOT_ENABLED, audio.enabled and 1 or 0)
  write(SLOT_VOLUME, math.max(0, math.min(1, tonumber(audio.volume) or 0.7)))
  write(SLOT_FLAGS, Audio.flags(preset))
  -- Indices are into the list the effect was built from, which is the used set
  -- and not the folder listing.
  local used = Audio.used_sounds(preset)
  local sounds = preset and preset.sounds or {}
  write(SLOT_SOUND_WARN, Audio.sound_index(used, sounds.warn))
  write(SLOT_SOUND_COUNT, Audio.sound_index(used, sounds.count_in))
  write(SLOT_SOUND_GO, Audio.sound_index(used, sounds.go))
  write(SLOT_SOUND_BEAT, Audio.sound_index(used, sounds.beat))
  write(SLOT_SOUND_ACCENT, Audio.sound_index(used, sounds.accent))
  if not audio.enabled then return true end
  local plan = Audio.schedule(engine, state, state.warn_bars)
  write(SLOT_CHANGE, plan and plan.change or -1)
  write(SLOT_WARN, plan and plan.warn or -1)
  write(SLOT_LAST_BAR, plan and plan.last_bar or -1)
  return true
end

-- Called when the module goes away. Writing the heartbeat one last time with
-- enabled off stops it now rather than a second from now.
function Audio.silence()
  if not Audio.attach() then return end
  write(SLOT_ENABLED, 0)
  heartbeat = (heartbeat + 1) % 1000000
  write(SLOT_HEARTBEAT, heartbeat)
end

return Audio
