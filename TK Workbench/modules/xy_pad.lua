local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local M = {
  id = "xy_pad",
  title = "XY Pad",
  icon = "XY",
  version = "0.1.0"
}

local defaults = {
  momentary = false, -- restore the values held before the drag when you let go
  show_grid = true,
  count_in_beats = 4,
  loop = true,
  trigger_mode = "off", -- "off" | "note" | "gate" | "hold"
  trigger_retrigger = true,
  trigger_index = 1,
}

-- A movement is a list of { seconds, x, y } samples plus the tempo it was
-- recorded at, and nothing else -- no track, no plugin. That makes it portable,
-- so movements live in global ext state and can be reused in any project, while
-- the axis assignments stay per project.
local MOVE_MAX_SAMPLES = 2000
local MOVE_MAX_SECONDS = 120
local MOVE_DEAD_BAND = 0.002 -- below this a sample says nothing new
local MOVE_MIN_INTERVAL = 0.1 -- ... but keep a heartbeat so pauses are preserved
-- Starting the clock needs a deliberate move, not encoder jitter, so the
-- threshold that begins a take is wider than the one that stores a sample.
local MOVE_START_BAND = 0.005

-- Assignments point at a track, an FX in its chain and a parameter, so they only
-- mean something inside the project they were made in and live in its ext state.
-- The track is stored by GUID: an index would follow the wrong track as soon as
-- the project is reordered.
local EXT_SECTION = "TK_WORKBENCH_XY_PAD"
local AXES = { "x", "y" }

local state = {
  axes = {},
  read_at = -1,
  drag = nil,
  rec = nil, -- { phase = "countin"|"armed"|"recording"|"full", until_time, started, samples, tempo }
  play = nil, -- { index, started, gate }
  moves = nil, -- lazily loaded preset list
  midi = { seq = 0, held = {}, count = 0 },
  menu = nil, -- { index } while the right-click menu is up
  menu_open = false,
  rename_text = "",
  rename_focus = false,
}

local function ensure_settings(app)
  app.settings.xy_pad = app.settings.xy_pad or {}
  local settings = app.settings.xy_pad
  for key, value in pairs(defaults) do
    if settings[key] == nil then settings[key] = value end
  end
  settings.momentary = settings.momentary == true
  settings.show_grid = settings.show_grid ~= false
  settings.loop = settings.loop ~= false
  settings.trigger_retrigger = settings.trigger_retrigger ~= false
  local known = { off = true, note = true, gate = true, hold = true }
  if not known[settings.trigger_mode] then settings.trigger_mode = "off" end
  settings.count_in_beats = math.max(0, math.min(8, math.floor(tonumber(settings.count_in_beats) or 4)))
  settings.trigger_index = math.max(1, math.floor(tonumber(settings.trigger_index) or 1))
  return settings
end

local function save(app) if app.save_settings then app.save_settings() end end

local function clamp(value, lo, hi)
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function fit(ctx, text, max_w)
  text = tostring(text or "")
  if max_w <= 0 then return "" end
  if r.ImGui_CalcTextSize(ctx, text) <= max_w then return text end
  while #text > 1 and r.ImGui_CalcTextSize(ctx, text .. "..") > max_w do
    local cut = #text
    while cut > 1 and text:byte(cut) >= 0x80 and text:byte(cut) < 0xC0 do cut = cut - 1 end
    text = text:sub(1, cut - 1)
  end
  return text .. ".."
end

-- ---------------------------------------------------------------------------
-- Assignments
-- ---------------------------------------------------------------------------
local function track_by_guid(guid)
  if not guid or guid == "" or not r.GetTrackGUID then return nil end
  local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
  if master and r.GetTrackGUID(master) == guid then return master end
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if track and r.GetTrackGUID(track) == guid then return track end
  end
  return nil
end

local function track_label(track)
  if not track then return "?" end
  local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
  if master and track == master then return "Master" end
  local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if name and name ~= "" then return index .. " " .. name end
  return "Track " .. index
end

local function read_axis(axis)
  if not r.GetProjExtState then return nil end
  local _, blob = r.GetProjExtState(0, EXT_SECTION, axis)
  if not blob or blob == "" then return nil end
  local guid, fx, param = blob:match("^(.-)|(%-?%d+)|(%-?%d+)$")
  fx, param = tonumber(fx), tonumber(param)
  if not guid or not fx or not param then return nil end
  local track = track_by_guid(guid)
  if not track then return { missing = true } end
  local entry = { track = track, fx = fx, param = param }
  if r.TrackFX_GetFXName then
    local ok, name = pcall(r.TrackFX_GetFXName, track, fx, "")
    entry.fx_name = (ok and type(name) == "string" and name ~= "") and name or "FX " .. fx
  end
  if r.TrackFX_GetParamName then
    local ok, name = pcall(r.TrackFX_GetParamName, track, fx, param, "")
    entry.param_name = (ok and type(name) == "string" and name ~= "") and name or "Param " .. param
  end
  entry.track_name = track_label(track)
  return entry
end

-- Reading walks the tracks to resolve a GUID, so keep it off the per-frame path.
local function axes(force)
  local now = os.clock()
  if not force and state.read_at >= 0 and (now - state.read_at) < 0.25 then return state.axes end
  for _, axis in ipairs(AXES) do state.axes[axis] = read_axis(axis) end
  state.read_at = now
  return state.axes
end

local function assign(app, axis)
  if not r.GetTouchedOrFocusedFX or not r.SetProjExtState then
    app.status = "XY Pad: needs a newer REAPER"
    return
  end
  local ok, track_idx, item_idx, _, fx_idx, param = r.GetTouchedOrFocusedFX(0)
  if not ok then
    app.status = "XY Pad: touch a parameter in an FX window first"
    return
  end
  if item_idx and item_idx >= 0 then
    app.status = "XY Pad: take FX are not supported, only track FX"
    return
  end
  local track = (track_idx == -1) and (r.GetMasterTrack and r.GetMasterTrack(0))
    or r.GetTrack(0, track_idx)
  if not track then
    app.status = "XY Pad: could not resolve that track"
    return
  end
  local guid = r.GetTrackGUID and r.GetTrackGUID(track) or nil
  if not guid then
    app.status = "XY Pad: could not identify that track"
    return
  end
  r.SetProjExtState(0, EXT_SECTION, axis, string.format("%s|%d|%d", guid, fx_idx, param))
  axes(true)
  local entry = state.axes[axis]
  app.status = "XY Pad: " .. axis:upper() .. " = " ..
    ((entry and entry.param_name) and (entry.track_name .. " / " .. entry.param_name) or "assigned")
end

local function clear(app, axis)
  if r.SetProjExtState then r.SetProjExtState(0, EXT_SECTION, axis, "") end
  axes(true)
  app.status = "XY Pad: " .. axis:upper() .. " cleared"
end

local function param_value(entry)
  if not entry or entry.missing or not r.TrackFX_GetParamNormalized then return nil end
  local ok, value = pcall(r.TrackFX_GetParamNormalized, entry.track, entry.fx, entry.param)
  if ok and type(value) == "number" then return clamp(value, 0, 1) end
  return nil
end

local function set_param_value(entry, value)
  if not entry or entry.missing or not r.TrackFX_SetParamNormalized then return end
  pcall(r.TrackFX_SetParamNormalized, entry.track, entry.fx, entry.param, clamp(value, 0, 1))
end

local function formatted_value(entry)
  if not entry or entry.missing then return "" end
  if r.TrackFX_GetFormattedParamValue then
    local ok, text = pcall(r.TrackFX_GetFormattedParamValue, entry.track, entry.fx, entry.param, "")
    if ok and type(text) == "string" and text ~= "" then return text end
  end
  local value = param_value(entry)
  return value and string.format("%d%%", math.floor(value * 100 + 0.5)) or ""
end

-- ---------------------------------------------------------------------------
-- Movements
-- ---------------------------------------------------------------------------
local function now_time()
  return r.time_precise and r.time_precise() or os.clock()
end

local function project_tempo()
  local tempo = r.Master_GetTempo and r.Master_GetTempo() or 120
  return (tempo and tempo > 0) and tempo or 120
end

local function move_load()
  if state.moves then return state.moves end
  local list = {}
  if r.GetExtState then
    local count = tonumber(r.GetExtState(EXT_SECTION, "move_count")) or 0
    for index = 1, math.min(count, 64) do
      local blob = r.GetExtState(EXT_SECTION, "move_" .. index)
      if blob and blob ~= "" then
        local name, tempo, body = blob:match("^(.-);([%d%.]+);(.*)$")
        if name and body then
          local samples = {}
          for t, x, y in body:gmatch("([%d%.%-]+),([%d%.%-]+),([%d%.%-]+)") do
            samples[#samples + 1] = { t = tonumber(t), x = tonumber(x), y = tonumber(y) }
          end
          if #samples > 1 then
            list[#list + 1] = { name = name, tempo = tonumber(tempo) or 120, samples = samples }
          end
        end
      end
    end
  end
  state.moves = list
  return list
end

local function move_store()
  if not r.SetExtState then return end
  local list = state.moves or {}
  for index, move in ipairs(list) do
    local parts = {}
    for _, sample in ipairs(move.samples) do
      parts[#parts + 1] = string.format("%.3f,%.4f,%.4f", sample.t, sample.x, sample.y)
    end
    r.SetExtState(EXT_SECTION, "move_" .. index,
      string.format("%s;%.3f;%s", move.name, move.tempo, table.concat(parts, "|")), true)
  end
  -- Clear whatever a longer list left behind.
  local index = #list + 1
  while r.GetExtState(EXT_SECTION, "move_" .. index) ~= "" and index < 128 do
    if r.DeleteExtState then r.DeleteExtState(EXT_SECTION, "move_" .. index, true) end
    index = index + 1
  end
  r.SetExtState(EXT_SECTION, "move_count", tostring(#list), true)
end

local function move_length(move)
  return move.samples[#move.samples].t
end

-- Names share a line with the sample data, so the separators have to go, and a
-- long name would only be cut off on the button anyway.
local function clean_name(text)
  text = tostring(text or ""):gsub("[;|\r\n]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
  if #text > 24 then text = text:sub(1, 24) end
  return text
end

local function move_rename(app, index, name)
  local list = move_load()
  local move = list[index]
  name = clean_name(name)
  if not move or name == "" then return false end
  move.name = name
  move_store()
  app.status = "XY Pad: renamed to " .. name
  return true
end

local function record_start(app, settings)
  state.play = nil
  local beats = math.max(0, math.floor(tonumber(settings.count_in_beats) or 4))
  local tempo = project_tempo()
  -- After the count-in the take is only armed: the clock starts on the first real
  -- move, so however long you sit there thinking costs nothing.
  state.rec = {
    phase = beats > 0 and "countin" or "armed",
    tempo = tempo,
    started = 0,
    until_time = now_time() + beats * 60 / tempo,
    samples = {},
  }
  app.status = beats > 0 and ("XY Pad: counting in " .. beats .. " beats")
    or "XY Pad: armed - move to start"
end

-- Drop the still tail: the seconds between letting go and reaching Stop. The
-- sample where movement ended is kept, everything after it goes.
local function trim_tail(samples)
  local last = #samples
  while last > 2 do
    local before, current = samples[last - 1], samples[last]
    if math.abs(current.x - before.x) >= MOVE_DEAD_BAND
      or math.abs(current.y - before.y) >= MOVE_DEAD_BAND then
      break
    end
    last = last - 1
  end
  for index = #samples, last + 1, -1 do table.remove(samples, index) end
end

local function record_stop(app)
  local rec = state.rec
  state.rec = nil
  if not rec or (rec.phase ~= "recording" and rec.phase ~= "full") or #rec.samples < 2 then
    app.status = "XY Pad: nothing recorded"
    return
  end
  trim_tail(rec.samples)
  if #rec.samples < 2 then
    app.status = "XY Pad: nothing recorded"
    return
  end
  local list = move_load()
  list[#list + 1] = { name = "Move " .. (#list + 1), tempo = rec.tempo, samples = rec.samples }
  move_store()
  app.status = string.format("XY Pad: saved %s (%.1fs, %d points)",
    list[#list].name, move_length(list[#list]), #rec.samples)
end

local function move_delete(app, index)
  local list = move_load()
  if not list[index] then return end
  local name = list[index].name
  table.remove(list, index)
  if state.play and state.play.index == index then state.play = nil end
  move_store()
  app.status = "XY Pad: deleted " .. name
end

-- Sampling reads the parameters rather than the mouse, so anything that moves
-- them is captured -- the pad, the FX window, a control surface.
local function record_sample(ax, ay)
  local rec = state.rec
  if not rec or (rec.phase ~= "recording" and rec.phase ~= "armed") then return end
  local x, y = param_value(ax) or 0, param_value(ay) or 0
  if rec.phase == "armed" then
    -- First pass captures where things stood; the take begins once that changes.
    if not rec.ref then
      rec.ref = { x = x, y = y }
      return
    end
    if math.abs(x - rec.ref.x) < MOVE_START_BAND and math.abs(y - rec.ref.y) < MOVE_START_BAND then
      return
    end
    rec.phase = "recording"
    rec.started = now_time()
    -- Anchor the movement at the value it started from, not at the first sample
    -- after it, so playback begins exactly where the gesture did.
    rec.samples[1] = { t = 0, x = rec.ref.x, y = rec.ref.y }
  end
  local t = now_time() - rec.started
  if t > MOVE_MAX_SECONDS or #rec.samples >= MOVE_MAX_SAMPLES then
    rec.phase = "full"
    return
  end
  local last = rec.samples[#rec.samples]
  if last then
    local still = math.abs(x - last.x) < MOVE_DEAD_BAND and math.abs(y - last.y) < MOVE_DEAD_BAND
    if still and (t - last.t) < MOVE_MIN_INTERVAL then return end
  end
  rec.samples[#rec.samples + 1] = { t = t, x = x, y = y }
end

-- Playback walks the samples and interpolates, scaling time by the tempo the
-- movement was recorded at, so a gesture keeps its musical length when the
-- project runs faster or slower than it did on the day.
local function playback_step(settings, ax, ay)
  local play = state.play
  if not play then return end
  -- Frozen by a note release in hold mode: the parameters already sit at that
  -- position, so there is nothing to write until a note picks it up again.
  if play.paused_at then return end
  local move = (move_load())[play.index]
  if not move then
    state.play = nil
    return
  end
  local scale = move.tempo > 0 and (project_tempo() / move.tempo) or 1
  local elapsed = (now_time() - play.started) * scale
  local total = move_length(move)
  if elapsed > total then
    -- A gated movement always repeats: the note release is what ends it.
    if settings.loop or play.gate then
      play.started = now_time()
      elapsed = 0
    else
      state.play = nil
      return
    end
  end
  local samples = move.samples
  local previous = samples[1]
  for index = 2, #samples do
    local sample = samples[index]
    if sample.t >= elapsed then
      local span = sample.t - previous.t
      local mix = span > 0.0000001 and ((elapsed - previous.t) / span) or 0
      local x = previous.x + (sample.x - previous.x) * mix
      local y = previous.y + (sample.y - previous.y) * mix
      if ax and not ax.missing then set_param_value(ax, x) end
      if ay and not ay.missing then set_param_value(ay, y) end
      return
    end
    previous = sample
  end
end

-- ---------------------------------------------------------------------------
-- MIDI trigger
-- ---------------------------------------------------------------------------
-- Notes arriving on the track being modulated can start a movement. Polling is
-- cheap: MIDI_GetRecentInputEvent(0) both refreshes the history and returns a
-- sequence number, so an idle frame costs one call and compares one integer.
-- Only when that number moves does it walk back through the new events.
local MIDI_MAX_DRAIN = 64

-- The track whose record input decides what counts as "our" MIDI: the one the
-- modulated FX sits on.
local function trigger_track()
  local entry = state.axes.x
  if not entry or entry.missing then entry = state.axes.y end
  return (entry and not entry.missing) and entry.track or nil
end

-- I_RECINPUT packs a MIDI input: bit 4096 marks it as MIDI, the low 5 bits are
-- the channel (0 means all) and the next 6 the device (63 means all).
local function trigger_input()
  local track = trigger_track()
  if not track then return nil end
  local input = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
  if input < 0 or (input & 4096) == 0 then return nil end
  return { channel = input & 0x1F, device = (input >> 5) & 0x3F }
end

local function midi_matches(want, device, channel)
  if not want then return false end
  if want.channel ~= 0 and want.channel ~= channel then return false end
  if want.device ~= 63 and want.device ~= (device & 0xFFFF) then return false end
  return true
end

-- How far into a movement a playback is, in movement seconds, wrapped so a
-- looping one reports a position inside its own length.
local function play_position(play)
  local move = (move_load())[play.index]
  if not move then return 0, nil end
  local scale = move.tempo > 0 and (project_tempo() / move.tempo) or 1
  local total = move_length(move)
  local elapsed = (now_time() - play.started) * scale
  if total > 0 then elapsed = elapsed % total end
  return elapsed, scale
end

local function midi_note(app, settings, on, pitch)
  local midi = state.midi
  local mode = settings.trigger_mode
  local gated = mode == "gate" or mode == "hold"
  if on then
    if not midi.held[pitch] then
      midi.held[pitch] = true
      midi.count = midi.count + 1
    end
    local first = midi.count == 1
    if state.play and state.play.paused_at and not settings.trigger_retrigger then
      -- Hold mode, picking up where the last release left it: shift the start
      -- back by the stored position, using the tempo ratio of right now.
      local _, scale = play_position(state.play)
      state.play.started = now_time() - state.play.paused_at / ((scale and scale > 0) and scale or 1)
      state.play.paused_at = nil
      state.play.gate = gated
    elseif settings.trigger_retrigger or not state.play then
      -- Retrigger restarts on every note; without it a movement already running
      -- is left alone and only a fresh start begins one.
      local list = move_load()
      local index = math.min(math.max(1, settings.trigger_index), #list)
      if list[index] then
        state.play = { index = index, started = now_time(), gate = gated }
        state.rec = nil
      end
    end
    if first and app then app.status = "XY Pad: triggered by note " .. pitch end
  else
    if midi.held[pitch] then
      midi.held[pitch] = nil
      midi.count = math.max(0, midi.count - 1)
    end
    if midi.count == 0 and state.play then
      if mode == "gate" then
        state.play = nil
      elseif mode == "hold" then
        -- Freeze rather than stop: the parameters stay where they are and the
        -- next note carries on from this point.
        local elapsed, scale = play_position(state.play)
        if scale then state.play.paused_at = elapsed else state.play = nil end
      end
    end
  end
end

local function midi_poll(app, settings)
  if not r.MIDI_GetRecentInputEvent then return end
  local newest = r.MIDI_GetRecentInputEvent(0)
  if not newest or newest == 0 or newest == state.midi.seq then return end
  local want = trigger_input()
  local pending = {}
  for index = 0, MIDI_MAX_DRAIN - 1 do
    local seq, buf, _, device = r.MIDI_GetRecentInputEvent(index)
    if not seq or seq == 0 or seq <= state.midi.seq then break end
    pending[#pending + 1] = { buf = buf, device = device or 0 }
  end
  state.midi.seq = newest
  if not want then return end
  -- The history runs newest first; notes have to be replayed in the order they
  -- were played or a note off could land before its note on.
  for index = #pending, 1, -1 do
    local event = pending[index]
    local buf = event.buf
    if type(buf) == "string" and #buf >= 3 then
      local status = buf:byte(1)
      local kind = status & 0xF0
      if kind == 0x90 or kind == 0x80 then
        if midi_matches(want, event.device, (status & 0x0F) + 1) then
          local pitch, velocity = buf:byte(2), buf:byte(3)
          midi_note(app, settings, kind == 0x90 and velocity > 0, pitch)
        end
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------
-- Right-click menu for a movement. Deleting used to sit on the right-click
-- itself, which is a lot of consequence for one slip of the mouse.
local function draw_move_menu(ctx, app)
  if state.menu_open then
    r.ImGui_OpenPopup(ctx, "##xy_move_menu")
    state.menu_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "##xy_move_menu") then return end
  local index = state.menu and state.menu.index
  local move = index and (move_load())[index]
  if not move then
    r.ImGui_EndPopup(ctx)
    return
  end
  r.ImGui_TextColored(ctx, Theme.colors.accent, move.name)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim,
    string.format("%.1fs, %d points, %.1f BPM", move_length(move), #move.samples, move.tempo))
  r.ImGui_Separator(ctx)

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
  if state.rename_focus then
    if r.ImGui_SetKeyboardFocusHere then r.ImGui_SetKeyboardFocusHere(ctx) end
    state.rename_focus = false
  end
  local changed, value = r.ImGui_InputText(ctx, "##xy_rename", state.rename_text or "")
  if changed then state.rename_text = value end
  local button_w = UIScale.text_button_w(ctx, "Rename", 74)
  if r.ImGui_Button(ctx, "Rename", button_w, 0) then
    move_rename(app, index, state.rename_text)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_Selectable(ctx, "Delete") then move_delete(app, index) end
  r.ImGui_EndPopup(ctx)
end

local function draw_slot(ctx, app, axis, entry, width)
  local gap = UIScale.gap(4)
  local row_h = r.ImGui_GetFrameHeight(ctx)
  local learn_w = UIScale.text_button_w(ctx, "Learn", 56)
  local clear_w = UIScale.round(24)
  local label_w = UIScale.round(16)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local lh = r.ImGui_GetTextLineHeight(ctx)

  r.ImGui_DrawList_AddText(dl, ox, oy + (row_h - lh) * 0.5, Theme.colors.accent, axis:upper())

  local text, colour
  if not entry then
    text, colour = "not assigned", Theme.colors.text_dim
  elseif entry.missing then
    text, colour = "track is gone", Theme.colors.warning or Theme.colors.text_dim
  else
    text = entry.track_name .. "  /  " .. (entry.fx_name or "FX") .. "  /  " .. (entry.param_name or "?")
    colour = Theme.colors.text
  end
  local text_w = width - label_w - learn_w - clear_w - 3 * gap
  r.ImGui_DrawList_AddText(dl, ox + label_w, oy + (row_h - lh) * 0.5, colour, fit(ctx, text, text_w))

  r.ImGui_SetCursorScreenPos(ctx, ox + label_w + text_w + gap, oy)
  if r.ImGui_Button(ctx, "Learn##xy_learn_" .. axis, learn_w, row_h) then assign(app, axis) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Assign the parameter you last moved in an FX window to " .. axis:upper())
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "x##xy_clear_" .. axis, clear_w, row_h) then clear(app, axis) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear " .. axis:upper()) end
end

function M.init(app)
  ensure_settings(app)
end

-- Runs every frame for every loaded module, so a recording or a playing movement
-- carries on while you are looking at something else entirely.
function M.update(app)
  local settings = ensure_settings(app)
  local armed = settings.trigger_mode ~= "off"
  if not state.rec and not state.play and not armed then return end
  local resolved = axes(false)
  if armed then midi_poll(app, settings) end
  if state.rec then
    if state.rec.phase == "countin" and now_time() >= state.rec.until_time then
      state.rec.phase = "armed"
    end
    record_sample(resolved.x, resolved.y)
  end
  playback_step(settings, resolved.x, resolved.y)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local gap = UIScale.gap(6)
  -- Vertical breathing room is kept tighter than the horizontal spacing: it is
  -- repeated on every row, so it is where the height goes.
  local vgap = UIScale.gap(2)
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(UIScale.round(160), avail_w or UIScale.round(320))
  local lh = r.ImGui_GetTextLineHeight(ctx)
  local row_h = r.ImGui_GetFrameHeight(ctx)
  local spacing_y = UIScale.gap(4)
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local ok, _, sy = pcall(r.ImGui_GetStyleVar, ctx, r.ImGui_StyleVar_ItemSpacing())
    if ok and type(sy) == "number" then spacing_y = sy end
  end

  local resolved = axes(false)
  local ax, ay = resolved.x, resolved.y

  draw_slot(ctx, app, "x", ax, width)
  r.ImGui_Dummy(ctx, 1, vgap)
  draw_slot(ctx, app, "y", ay, width)
  r.ImGui_Dummy(ctx, 1, vgap)

  -- Options row.
  local chip_w = math.max(UIScale.round(70), (width - gap) / 2)
  local changed, value = r.ImGui_Checkbox(ctx, "Momentary", settings.momentary)
  if changed then
    settings.momentary = value
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Put both parameters back where they were when you let go")
  end
  r.ImGui_SameLine(ctx, 0, gap * 2)
  local grid_changed, grid_value = r.ImGui_Checkbox(ctx, "Grid", settings.show_grid)
  if grid_changed then
    settings.show_grid = grid_value
    save(app)
  end
  r.ImGui_SameLine(ctx, 0, gap * 2)
  local loop_changed, loop_value = r.ImGui_Checkbox(ctx, "Loop", settings.loop)
  if loop_changed then
    settings.loop = loop_value
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Repeat a movement until you stop it") end
  r.ImGui_Dummy(ctx, 1, vgap)

  -- Record row: arm, the count-in length, and how long the take is running.
  local recording = state.rec ~= nil
  local rec_w = UIScale.text_button_w(ctx, "Record", 70)
  if r.ImGui_Button(ctx, recording and "Stop##xy_rec" or "Record##xy_rec", rec_w, row_h) then
    if recording then record_stop(app) else record_start(app, settings) end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, recording and "Stop and save this movement"
      or "Count in, then capture everything the two parameters do")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(90))
  local beats_changed, beats = r.ImGui_SliderInt(ctx, "##xy_countin",
    math.floor(settings.count_in_beats or 4), 0, 8, "count %d")
  if beats_changed then
    settings.count_in_beats = beats
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Beats of count-in before recording starts (0 for none)")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  r.ImGui_AlignTextToFramePadding(ctx)
  if recording and state.rec.phase == "armed" then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "armed - move to start")
  elseif recording and state.rec.phase == "recording" then
    r.ImGui_TextColored(ctx, Theme.colors.danger or 0xFF3B3BFF,
      string.format("%.1fs  %d pts", now_time() - state.rec.started, #state.rec.samples))
  elseif recording and state.rec.phase == "full" then
    r.ImGui_TextColored(ctx, Theme.colors.warning or Theme.colors.text_dim, "full - press Stop")
  elseif state.play then
    local move = (move_load())[state.play.index]
    local name = move and move.name or "movement"
    if state.play.paused_at then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim,
        string.format("%s held at %.1fs", name, state.play.paused_at))
    else
      r.ImGui_TextColored(ctx, Theme.colors.accent, "playing " .. name)
    end
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(#move_load()) .. " saved")
  end
  r.ImGui_Dummy(ctx, 1, vgap)

  -- The pad: square, as large as the remaining room allows.
  local px, py = r.ImGui_GetCursorScreenPos(ctx)
  px, py = math.floor(px), math.floor(py)
  local _, room = r.ImGui_GetContentRegionAvail(ctx)
  -- Work out what still has to fit underneath, so a short window shrinks the pad
  -- instead of pushing the readout, the movements and the trigger row off screen.
  local saved = move_load()
  -- ImGui adds its item spacing after every item, so each spacer and each row of
  -- buttons costs its own height plus that: leaving those out is what let the
  -- trigger row slide off the bottom.
  local below = gap + lh + spacing_y -- the readout line
  if #saved > 0 then
    below = below + vgap + spacing_y -- spacer above the movement buttons
    below = below + math.ceil(#saved / 3) * (row_h + spacing_y)
    below = below + vgap + spacing_y -- spacer above the MIDI row
    below = below + row_h + spacing_y -- the mode buttons
    if settings.trigger_mode ~= "off" then below = below + lh + spacing_y end -- its note line
  end
  below = below + spacing_y -- a little slack, so nothing sits flush against the edge
  local size = clamp(math.min(width, (room or width) - below), UIScale.round(90), width)
  local vx = param_value(ax)
  local vy = param_value(ay)
  local live = vx ~= nil or vy ~= nil

  r.ImGui_SetCursorScreenPos(ctx, px, py)
  r.ImGui_InvisibleButton(ctx, "##xy_pad_surface", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx)

  if r.ImGui_IsItemActivated and r.ImGui_IsItemActivated(ctx) then
    state.drag = { x = vx, y = vy }
  end
  if active and live then
    local mx, my = r.ImGui_GetMousePos(ctx)
    local nx = clamp((mx - px) / size, 0, 1)
    -- Screen y grows downwards; the pad reads bottom-up like a fader.
    local ny = 1 - clamp((my - py) / size, 0, 1)
    if vx ~= nil then set_param_value(ax, nx); vx = nx end
    if vy ~= nil then set_param_value(ay, ny); vy = ny end
  end
  if r.ImGui_IsItemDeactivated and r.ImGui_IsItemDeactivated(ctx) then
    if settings.momentary and state.drag then
      if state.drag.x ~= nil then set_param_value(ax, state.drag.x); vx = state.drag.x end
      if state.drag.y ~= nil then set_param_value(ay, state.drag.y); vy = state.drag.y end
    end
    state.drag = nil
  end

  r.ImGui_DrawList_AddRectFilled(dl, px, py, px + size, py + size, Theme.colors.window_bg, UIScale.px(5))
  if settings.show_grid then
    for step = 1, 3 do
      local at = size * step / 4
      local tint = (Theme.colors.border & 0xFFFFFF00) | (step == 2 and 0xAA or 0x55)
      r.ImGui_DrawList_AddLine(dl, px + at, py, px + at, py + size, tint, UIScale.px(1))
      r.ImGui_DrawList_AddLine(dl, px, py + at, px + size, py + at, tint, UIScale.px(1))
    end
  end
  r.ImGui_DrawList_AddRect(dl, px, py, px + size, py + size,
    (hovered or active) and Theme.colors.accent or Theme.colors.border, UIScale.px(5), 0, UIScale.px(1))

  if live then
    local cx = px + (vx or 0.5) * size
    local cy = py + (1 - (vy or 0.5)) * size
    local soft = (Theme.colors.accent & 0xFFFFFF00) | 0x55
    r.ImGui_DrawList_AddLine(dl, px, cy, px + size, cy, soft, UIScale.px(1))
    r.ImGui_DrawList_AddLine(dl, cx, py, cx, py + size, soft, UIScale.px(1))
    local radius = UIScale.round(active and 9 or 7)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius, (Theme.colors.accent & 0xFFFFFF00) | 0x66, 20)
    r.ImGui_DrawList_AddCircle(dl, cx, cy, radius, Theme.colors.accent, 20, UIScale.px(1.6))
  else
    local hint = "Touch a parameter in an FX window, then press Learn"
    local hw = r.ImGui_CalcTextSize(ctx, hint)
    r.ImGui_DrawList_AddText(dl, px + math.max(UIScale.round(6), (size - hw) * 0.5),
      py + (size - lh) * 0.5, Theme.colors.text_dim, fit(ctx, hint, size - UIScale.round(12)))
  end

  -- Count-in: the beats left, big in the middle of the pad.
  if state.rec and state.rec.phase == "countin" then
    local beats_left = math.ceil((state.rec.until_time - now_time()) / (60 / state.rec.tempo))
    local text = tostring(math.max(1, beats_left))
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddRectFilled(dl, px, py, px + size, py + size,
      ((Theme.colors.danger or 0xFF3B3BFF) & 0xFFFFFF00) | 0x22, UIScale.px(5))
    r.ImGui_DrawList_AddText(dl, px + (size - tw) * 0.5, py + (size - th) * 0.5,
      Theme.colors.danger or 0xFF3B3BFF, text)
  elseif state.rec then
    -- Armed reads as a soft outline, rolling as a solid one.
    local armed = state.rec.phase == "armed"
    local danger = Theme.colors.danger or 0xFF3B3BFF
    r.ImGui_DrawList_AddRect(dl, px + UIScale.px(2), py + UIScale.px(2),
      px + size - UIScale.px(2), py + size - UIScale.px(2),
      armed and ((danger & 0xFFFFFF00) | 0x66) or danger,
      UIScale.px(4), 0, armed and UIScale.px(1) or UIScale.px(1.6))
    if armed then
      local hint = "move to start"
      local hw = r.ImGui_CalcTextSize(ctx, hint)
      r.ImGui_DrawList_AddText(dl, px + (size - hw) * 0.5, py + size - lh - UIScale.round(8),
        (danger & 0xFFFFFF00) | 0xAA, hint)
    end
  end

  -- Readout under the pad: the plugin's own formatting where it offers one.
  r.ImGui_SetCursorScreenPos(ctx, px, py + size + gap)
  local left = ax and not ax.missing and ((ax.param_name or "X") .. "  " .. formatted_value(ax)) or ""
  local right = ay and not ay.missing and ((ay.param_name or "Y") .. "  " .. formatted_value(ay)) or ""
  if left ~= "" then
    r.ImGui_DrawList_AddText(dl, px, py + size + gap, Theme.colors.text_dim, fit(ctx, left, size * 0.5 - gap))
  end
  if right ~= "" then
    local fitted = fit(ctx, right, size * 0.5 - gap)
    local rw = r.ImGui_CalcTextSize(ctx, fitted)
    r.ImGui_DrawList_AddText(dl, px + size - rw, py + size + gap, Theme.colors.text_dim, fitted)
  end
  r.ImGui_Dummy(ctx, width, lh)

  -- Saved movements: click to play or stop, right-click to delete.
  local moves = move_load()
  if #moves > 0 then
    r.ImGui_Dummy(ctx, 1, vgap)
    local per_row = 3
    local move_w = (width - (per_row - 1) * gap) / per_row
    for index, move in ipairs(moves) do
      if index > 1 and ((index - 1) % per_row) ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
      local playing = state.play ~= nil and state.play.index == index
      local pushed = 0
      if playing and r.ImGui_Col_Button then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft)
        pushed = 1
      end
      local label = move.name .. "##xy_move_" .. index
      if r.ImGui_Button(ctx, label, move_w, row_h) then
        -- Clicking also arms it: the movement you last reached for is the one a
        -- note triggers, which saves a second list to pick from.
        settings.trigger_index = index
        save(app)
        if playing then
          state.play = nil
        else
          state.play = { index = index, started = now_time(), gate = false }
          state.rec = nil
        end
      end
      if pushed > 0 then r.ImGui_PopStyleColor(ctx, pushed) end
      if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1) then
        state.menu = { index = index }
        state.rename_text = move.name
        state.rename_focus = true
        state.menu_open = true
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, string.format("%s - %.1fs, %d points, recorded at %.1f BPM\n%s",
          move.name, move_length(move), #move.samples, move.tempo,
          playing and "Click to stop, right-click for rename and delete"
            or "Click to play, right-click for rename and delete"))
      end
    end
    draw_move_menu(ctx, app)
  end

  -- MIDI trigger row: mode, retrigger, and what it is pointed at.
  if #moves > 0 then
    r.ImGui_Dummy(ctx, 1, vgap)
    local modes = {
      { id = "off", label = "Off" },
      { id = "note", label = "Note" },
      { id = "gate", label = "Gate" },
      { id = "hold", label = "Hold" },
    }
    local mode_w = UIScale.round(42)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "MIDI")
    for _, mode in ipairs(modes) do
      r.ImGui_SameLine(ctx, 0, gap)
      local on = settings.trigger_mode == mode.id
      local pushed = 0
      if on and r.ImGui_Col_Button then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft)
        pushed = 1
      end
      if r.ImGui_Button(ctx, mode.label .. "##xy_trig_" .. mode.id, mode_w, row_h) then
        settings.trigger_mode = mode.id
        if mode.id == "off" then
          state.midi.held, state.midi.count = {}, 0
          if state.play and state.play.gate then state.play = nil end
        end
        save(app)
      end
      if pushed > 0 then r.ImGui_PopStyleColor(ctx, pushed) end
      if r.ImGui_IsItemHovered(ctx) then
        local tip = mode.id == "off" and "No MIDI triggering"
          or mode.id == "note" and "A note starts the movement; it ends by itself, or loops if Loop is on"
          or mode.id == "gate" and "A note starts it looping and letting go of the last note stops it"
          or "Like Gate, but letting go freezes the movement and the next note carries on from there (turn Retrig off)"
        r.ImGui_SetTooltip(ctx, tip)
      end
    end
    if settings.trigger_mode ~= "off" then
      r.ImGui_SameLine(ctx, 0, gap * 2)
      local retrig_changed, retrig = r.ImGui_Checkbox(ctx, "Retrig", settings.trigger_retrigger)
      if retrig_changed then
        settings.trigger_retrigger = retrig
        save(app)
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Restart from the beginning on every note, instead of letting it run on")
      end

      local armed = moves[math.min(math.max(1, settings.trigger_index), #moves)]
      local input = trigger_input()
      local track = trigger_track()
      local note
      if not track then
        note = "assign an axis first"
      elseif not input then
        note = "that track has no MIDI input"
      else
        note = (armed and armed.name or "?") .. " on " ..
          (input.channel == 0 and "all channels" or ("ch " .. input.channel))
      end
      r.ImGui_TextColored(ctx, input and Theme.colors.text_dim or (Theme.colors.warning or Theme.colors.text_dim),
        fit(ctx, note .. (state.midi.count > 0 and ("  -  " .. state.midi.count .. " held") or ""), width))
    end
  end

  local status = (ax and not ax.missing) and 1 or 0
  status = status + ((ay and not ay.missing) and 1 or 0)
  UI.draw_info_line(ctx, "XY Pad | " .. status .. " of 2 axes assigned" ..
    (settings.momentary and " | momentary" or ""))
end

return M
