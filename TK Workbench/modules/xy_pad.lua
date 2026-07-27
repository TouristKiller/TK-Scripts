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
  pad_mode = "xy", -- "xy" = a parameter per axis, "corners" = one per corner
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
-- Corner slots are stored alongside the axes rather than replacing them, so
-- switching modes never disturbs an assignment you already made.
local AXES = { "x", "y", "c1", "c2", "c3", "c4" }
local XY_SLOTS = { { key = "x", label = "X" }, { key = "y", label = "Y" } }
local CORNER_SLOTS = {
  { key = "c1", label = "TL" },
  { key = "c2", label = "TR" },
  { key = "c3", label = "BL" },
  { key = "c4", label = "BR" },
}

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
  pos = { x = 0.5, y = 0.5 }, -- the puck, for when the parameters cannot tell us
  auto = { touched = {}, last_pos = -1, last_x = -1, last_y = -1, active = false, was_rolling = false, needs_envelope = nil },
}

local function ensure_settings(app)
  app.settings.xy_pad = app.settings.xy_pad or {}
  local settings = app.settings.xy_pad
  for key, value in pairs(defaults) do
    if settings[key] == nil then settings[key] = value end
  end
  if settings.pad_mode ~= "corners" then settings.pad_mode = "xy" end
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

-- REAPER hands back names like "VST3: Diva (u-he)" or "VSTi: Massive (NI) (16 out)":
-- the format tag in front, the vendor and any channel count behind. None of that
-- says which plugin it is, and the row has little room. The tag is matched
-- against a known list rather than "everything up to a colon", so a plugin
-- called "Delay: Tape" keeps its name.
local FX_PREFIXES = {
  "VST3i", "VST3", "VSTi", "VST", "CLAPi", "CLAP", "AUi", "AU",
  "LV2i", "LV2", "DXi", "DX", "JSFX", "JS", "ReWire",
}

local function clean_fx_name(name)
  name = tostring(name or "")
  for _, prefix in ipairs(FX_PREFIXES) do
    if name:sub(1, #prefix + 1):upper() == prefix:upper() .. ":" then
      name = name:sub(#prefix + 2)
      break
    end
  end
  -- Trailing bracketed groups, however many: the vendor first, then things like
  -- "(16 out)" that REAPER adds for instruments.
  while true do
    local stripped = name:gsub("%s*%b()%s*$", "")
    if stripped == name then break end
    name = stripped
  end
  name = name:match("^%s*(.-)%s*$")
  return name ~= "" and name or nil
end

-- Note: TrackFX_GetFXName and friends return a boolean first and the text
-- second, so behind a pcall the string is the third value. Reading it as the
-- second silently yields a boolean and every name falls back to "FX 0".
-- Levels are held as a fraction of a dB range rather than REAPER's raw 0..4
-- volume, where unity sits at a quarter of the travel and the top half is all
-- boost. The same range the Levels card uses.
local VOL_MIN_DB, VOL_MAX_DB = -60, 12

local function volume_to_unit(volume)
  if not volume or volume <= 0.0000001 then return 0 end
  local db = 20 * math.log(volume, 10)
  return clamp((db - VOL_MIN_DB) / (VOL_MAX_DB - VOL_MIN_DB), 0, 1)
end

local function unit_to_volume(unit)
  local db = VOL_MIN_DB + clamp(unit, 0, 1) * (VOL_MAX_DB - VOL_MIN_DB)
  if db <= VOL_MIN_DB + 0.05 then return 0 end
  return 10 ^ (db / 20)
end

local function send_label(track, index)
  local dest = r.GetTrackSendInfo_Value and r.GetTrackSendInfo_Value(track, 0, index, "P_DESTTRACK")
  if dest and dest ~= 0 then
    local ok, name = r.GetSetMediaTrackInfo_String(dest, "P_NAME", "", false)
    if ok and name and name ~= "" then return name end
    local number = math.floor(r.GetMediaTrackInfo_Value(dest, "IP_TRACKNUMBER") or 0)
    return "Track " .. number
  end
  return "Send " .. (index + 1)
end

-- Stored forms, oldest first so existing assignments keep working:
--   GUID|<fx>|<param>      an FX parameter, the original three-field layout
--   GUID|vol              track volume
--   GUID|pan              track pan
--   GUID|send|<index>     the level of one of the track's sends
local function read_axis(axis)
  if not r.GetProjExtState then return nil end
  local _, blob = r.GetProjExtState(0, EXT_SECTION, axis)
  if not blob or blob == "" then return nil end

  local guid, fx, param = blob:match("^(.-)|(%-?%d+)|(%-?%d+)$")
  if not guid then
    local rest
    guid, rest = blob:match("^(.-)|(.+)$")
    if not guid then return nil end
    local kind, index = rest:match("^(%a+)|?(%d*)$")
    local track = track_by_guid(guid)
    if not track then return { missing = true } end
    if kind == "vol" or kind == "pan" then
      return {
        track = track, kind = kind, track_name = track_label(track),
        fx_name = "Track", param_name = kind == "vol" and "Volume" or "Pan",
      }
    elseif kind == "send" then
      index = tonumber(index)
      if not index then return nil end
      return {
        track = track, kind = "send", send = index, track_name = track_label(track),
        fx_name = "Send", param_name = send_label(track, index),
      }
    end
    return nil
  end

  fx, param = tonumber(fx), tonumber(param)
  if not fx or not param then return nil end
  local track = track_by_guid(guid)
  if not track then return { missing = true } end
  local entry = { track = track, kind = "fx", fx = fx, param = param }
  if r.TrackFX_GetFXName then
    local ok, _, name = pcall(r.TrackFX_GetFXName, track, fx, "")
    if ok and type(name) == "string" and name ~= "" then
      entry.fx_full = name
      entry.fx_name = clean_fx_name(name) or name
    else
      entry.fx_name = "FX " .. fx
    end
  end
  if r.TrackFX_GetParamName then
    local ok, _, name = pcall(r.TrackFX_GetParamName, track, fx, param, "")
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

-- Track volume, pan and send levels have no equivalent of GetTouchedOrFocusedFX
-- -- REAPER remembers no "last touched track control" -- so these are picked
-- from the selected track instead of learned.
local function assign_track_target(app, axis, kind, index)
  local track = r.GetSelectedTrack and r.GetSelectedTrack(0, 0) or nil
  if not track then
    app.status = "XY Pad: select a track first"
    return
  end
  local guid = r.GetTrackGUID and r.GetTrackGUID(track) or nil
  if not guid or not r.SetProjExtState then return end
  local blob = guid .. "|" .. kind
  if kind == "send" then blob = blob .. "|" .. index end
  r.SetProjExtState(0, EXT_SECTION, axis, blob)
  axes(true)
  local entry = state.axes[axis]
  app.status = "XY Pad: " .. axis:upper() .. " = " ..
    ((entry and entry.param_name) and (entry.track_name .. " / " .. entry.param_name) or "assigned")
end

-- Send morphing in one go: the track's first four sends onto the four corners.
-- Doing it by hand means four right-clicks and remembering which send went
-- where, which is enough friction to stop anyone trying it.
local function assign_send_morph(app, settings, track)
  if not track or not r.GetTrackNumSends or not r.SetProjExtState then return end
  local sends = r.GetTrackNumSends(track, 0) or 0
  if sends < 2 then
    app.status = "XY Pad: that track needs at least two sends"
    return
  end
  local guid = r.GetTrackGUID and r.GetTrackGUID(track) or nil
  if not guid then return end
  local placed = 0
  for index, slot in ipairs(CORNER_SLOTS) do
    local send = index - 1
    if send < sends then
      r.SetProjExtState(0, EXT_SECTION, slot.key, guid .. "|send|" .. send)
      placed = placed + 1
    else
      -- Fewer than four sends: the spare corners are emptied rather than left
      -- pointing at whatever was there before.
      r.SetProjExtState(0, EXT_SECTION, slot.key, "")
    end
  end
  settings.pad_mode = "corners"
  save(app)
  axes(true)
  app.status = "XY Pad: morphing " .. placed .. " sends of " .. track_label(track)
end

local function clear(app, axis)
  if r.SetProjExtState then r.SetProjExtState(0, EXT_SECTION, axis, "") end
  axes(true)
  app.status = "XY Pad: " .. axis:upper() .. " cleared"
end

-- Every target speaks the same 0..1 whatever it really is, so the pad, the
-- movements and the corner weights need to know nothing about the difference.
local function param_value(entry)
  if not entry or entry.missing then return nil end
  if entry.kind == "vol" then
    return volume_to_unit(r.GetMediaTrackInfo_Value(entry.track, "D_VOL"))
  elseif entry.kind == "pan" then
    return clamp(((r.GetMediaTrackInfo_Value(entry.track, "D_PAN") or 0) + 1) * 0.5, 0, 1)
  elseif entry.kind == "send" then
    if not r.GetTrackSendInfo_Value then return nil end
    local ok, value = pcall(r.GetTrackSendInfo_Value, entry.track, 0, entry.send, "D_VOL")
    return ok and volume_to_unit(value) or nil
  end
  if not r.TrackFX_GetParamNormalized then return nil end
  local ok, value = pcall(r.TrackFX_GetParamNormalized, entry.track, entry.fx, entry.param)
  if ok and type(value) == "number" then return clamp(value, 0, 1) end
  return nil
end

local function set_param_value(entry, value)
  if not entry or entry.missing then return end
  value = clamp(value, 0, 1)
  if entry.kind == "vol" then
    r.SetMediaTrackInfo_Value(entry.track, "D_VOL", unit_to_volume(value))
  elseif entry.kind == "pan" then
    r.SetMediaTrackInfo_Value(entry.track, "D_PAN", value * 2 - 1)
  elseif entry.kind == "send" then
    if r.SetTrackSendInfo_Value then
      pcall(r.SetTrackSendInfo_Value, entry.track, 0, entry.send, "D_VOL", unit_to_volume(value))
    end
  elseif r.TrackFX_SetParamNormalized then
    pcall(r.TrackFX_SetParamNormalized, entry.track, entry.fx, entry.param, value)
  end
end

-- ---------------------------------------------------------------------------
-- The pad surface
-- ---------------------------------------------------------------------------
-- Corner mode is classic vector mixing: the puck hands each corner a weight from
-- how near it is, and the four always add up to exactly 1. Sit in a corner and
-- that parameter is at full while the rest are at zero; sit in the middle and
-- everyone gets a quarter.
local function corner_weights(x, y)
  return (1 - x) * y, x * y, (1 - x) * (1 - y), x * (1 - y) -- TL, TR, BL, BR
end

local function slots_for(settings)
  return settings.pad_mode == "corners" and CORNER_SLOTS or XY_SLOTS
end

local function pad_assigned(settings)
  for _, slot in ipairs(slots_for(settings)) do
    local entry = state.axes[slot.key]
    if entry and not entry.missing then return true end
  end
  return false
end

-- Read the puck back from the parameters, so a move made anywhere else shows up
-- here too. The weights invert cleanly: the two right-hand ones add up to x and
-- the two top ones to y. If a corner is missing there is nothing to invert, and
-- the remembered position stands in.
local function pad_position(settings)
  if settings.pad_mode == "corners" then
    local tl = param_value(state.axes.c1)
    local tr = param_value(state.axes.c2)
    local bl = param_value(state.axes.c3)
    local br = param_value(state.axes.c4)
    if tl and tr and bl and br then
      return clamp(tr + br, 0, 1), clamp(tl + tr, 0, 1)
    end
    return state.pos.x, state.pos.y
  end
  local vx, vy = param_value(state.axes.x), param_value(state.axes.y)
  return vx or state.pos.x, vy or state.pos.y
end

-- Setting a parameter through the API moves it but writes no automation: it does
-- not go past REAPER's automation writer. Points are therefore laid down here,
-- and only when the track is in a mode that asked for them -- touch, write or
-- latch, or a global override saying the same. Read and trim modes never get an
-- envelope they did not ask for.
local AUTOMATION_WRITING = { [2] = true, [3] = true, [4] = true }

local function automation_mode(track)
  local override = r.GetGlobalAutomationOverride and r.GetGlobalAutomationOverride() or -1
  if override and override >= 0 then return override end
  return r.GetTrackAutomationMode and r.GetTrackAutomationMode(track) or 0
end

local AUTOMATION_MODES = {
  { mode = 0, label = "Trim/Read" },
  { mode = 1, label = "Read" },
  { mode = 2, label = "Touch" },
  { mode = 3, label = "Write" },
  { mode = 4, label = "Latch" },
}

local function automation_label(mode)
  for _, entry in ipairs(AUTOMATION_MODES) do
    if entry.mode == mode then return entry.label end
  end
  return "?"
end

-- Every distinct track the active slots write to. In corner mode those four
-- parameters can sit on four different tracks, so arming "the" track is not a
-- thing -- all of them get the mode.
local function automation_tracks(settings)
  local tracks, seen = {}, {}
  for _, slot in ipairs(slots_for(settings)) do
    local entry = state.axes[slot.key]
    if entry and not entry.missing and entry.track and not seen[tostring(entry.track)] then
      seen[tostring(entry.track)] = true
      tracks[#tracks + 1] = entry.track
    end
  end
  return tracks
end

-- Once an envelope exists it drives the parameter, so the pad can no longer move
-- it in read mode. REAPER's own answer is the envelope's active flag, which lives
-- in its state chunk as "ACT 1"; bypassing keeps the automation but hands control
-- back. Setting the track to touch, write or latch is the other way round: the
-- pad takes over and overwrites as it goes.

-- REAPER hands out a pointer for a send envelope that the track does not own:
-- it takes points and reads back fine, but it has no lane, never reaches the
-- arrange and is dropped on save. Only an envelope on the track's own list is
-- real, so that is what counts as existing.
local function track_owns_envelope(track, envelope)
  if not track or not envelope or not r.CountTrackEnvelopes or not r.GetTrackEnvelope then
    return false
  end
  local key = tostring(envelope)
  for index = 0, (r.CountTrackEnvelopes(track) or 0) - 1 do
    if tostring(r.GetTrackEnvelope(track, index)) == key then return true end
  end
  return false
end

local function envelope_of(entry, create)
  if not entry or entry.missing then return nil end
  if entry.kind == "fx" then
    if not r.GetFXEnvelope then return nil end
    local ok, envelope = pcall(r.GetFXEnvelope, entry.track, entry.fx, entry.param, create and true or false)
    return ok and envelope or nil
  end
  -- Track and send envelopes have no create flag: REAPER hands them out only
  -- once they exist, so these are found rather than made.
  if entry.kind == "vol" or entry.kind == "pan" then
    if not r.GetTrackEnvelopeByName then return nil end
    local ok, envelope = pcall(r.GetTrackEnvelopeByName, entry.track,
      entry.kind == "vol" and "Volume" or "Pan")
    return ok and envelope or nil
  end
  if entry.kind == "send" and r.GetTrackSendInfo_Value then
    local ok, envelope = pcall(r.GetTrackSendInfo_Value, entry.track, 0, entry.send, "P_ENV:<VOLENV")
    -- A send without an envelope answers with the number 0, and 0 is true in
    -- Lua: taken at face value every send looks like it already has one and
    -- nothing is ever created.
    if not ok or not envelope or envelope == 0 then return nil end
    if not track_owns_envelope(entry.track, envelope) then return nil end
    return envelope
  end
  return nil
end

-- Track volume and pan envelopes have no create flag, so the only way to bring
-- one into being is REAPER's own "toggle envelope visible" action. Command ids
-- are checked against the action's name before being fired -- guessing an id and
-- hoping is how you end up toggling something else entirely.
local ENVELOPE_ACTIONS = {
  vol = { id = 40406, name = "toggle track volume envelope" },
  pan = { id = 40407, name = "toggle track pan envelope" },
}
local envelope_action_cache = {}

local function envelope_action(kind)
  local spec = ENVELOPE_ACTIONS[kind]
  if not spec then return 0 end
  if envelope_action_cache[kind] ~= nil then return envelope_action_cache[kind] end
  local function carries_name(command)
    if command == 0 or not r.CF_GetCommandText then return false end
    local ok, text = pcall(r.CF_GetCommandText, 0, command)
    return ok and type(text) == "string" and text:lower():find(spec.name, 1, true) ~= nil
  end
  local found = 0
  if carries_name(spec.id) then
    found = spec.id
  elseif r.CF_EnumerateActions then
    local index = 0
    while index < 30000 do
      local command, text = r.CF_EnumerateActions(0, index, "")
      if not command or command == 0 then break end
      if type(text) == "string" and text:lower():find(spec.name, 1, true) then
        found = command
        break
      end
      index = index + 1
    end
  end
  envelope_action_cache[kind] = found
  return found
end

-- Actions read the track selection, so borrow it and hand it straight back:
-- quietly changing what someone has selected is a rude thing for a script to do.
local function run_for_track(track, command)
  if not track or not command or command == 0 or not r.SetTrackSelected then return false end
  local selection = {}
  for index = 0, (r.CountSelectedTracks(0) or 0) - 1 do
    selection[#selection + 1] = r.GetSelectedTrack(0, index)
  end
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    r.SetTrackSelected(r.GetTrack(0, index), false)
  end
  r.SetTrackSelected(track, true)
  r.Main_OnCommand(command, 0)
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    r.SetTrackSelected(r.GetTrack(0, index), false)
  end
  for _, other in ipairs(selection) do r.SetTrackSelected(other, true) end
  return true
end

-- No REAPER action targets a send envelope, and writing one into the receiving
-- track's chunk by hand only yields an envelope the track does not own. SWS is
-- the working route: it shows the send volume envelopes of the selected track,
-- REAPER creates them properly and the lanes land on screen.
local SEND_ENVELOPE_COMMAND = "_BR_SHOW_SEND_ENV_VOL_SEL_TRACK"

local function create_send_envelope(entry)
  local command = r.NamedCommandLookup and r.NamedCommandLookup(SEND_ENVELOPE_COMMAND) or 0
  if command == 0 or not run_for_track(entry.track, command) then return nil end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  return envelope_of(entry, false)
end

local function ensure_track_envelope(entry)
  if not entry or entry.missing then return nil end
  local existing = envelope_of(entry, false)
  if existing then return existing end
  if entry.kind == "send" then return create_send_envelope(entry) end
  if entry.kind ~= "vol" and entry.kind ~= "pan" then return nil end
  if not run_for_track(entry.track, envelope_action(entry.kind)) then return nil end
  return envelope_of(entry, false)
end

-- What a point on this envelope has to hold. FX parameters are normalised
-- already; volume and pan are not, and a volume envelope stores its points in
-- fader scaling, which ScaleToEnvelopeMode converts to.
local function envelope_value(entry, envelope, unit)
  local raw
  if entry.kind == "pan" then
    raw = clamp(unit, 0, 1) * 2 - 1
  elseif entry.kind == "vol" or entry.kind == "send" then
    raw = unit_to_volume(unit)
  else
    return clamp(unit, 0, 1)
  end
  if r.GetEnvelopeScalingMode and r.ScaleToEnvelopeMode then
    local ok, mode = pcall(r.GetEnvelopeScalingMode, envelope)
    if ok and type(mode) == "number" then
      local scaled_ok, scaled = pcall(r.ScaleToEnvelopeMode, mode, raw)
      if scaled_ok and type(scaled) == "number" then return scaled end
    end
  end
  return raw
end

local function envelope_active(envelope)
  if not envelope or not r.GetEnvelopeStateChunk then return true end
  -- Mind the two returns: the chunk is the value after the success flag.
  local ok, got, chunk = pcall(r.GetEnvelopeStateChunk, envelope, "", false)
  if not ok or not got or type(chunk) ~= "string" then return true end
  return chunk:match("ACT%s+(%d+)") ~= "0"
end

local function envelope_set_active(envelope, on)
  if not envelope or not r.GetEnvelopeStateChunk or not r.SetEnvelopeStateChunk then return false end
  local ok, got, chunk = pcall(r.GetEnvelopeStateChunk, envelope, "", false)
  if not ok or not got or type(chunk) ~= "string" then return false end
  local updated, count = chunk:gsub("ACT%s+%d+", "ACT " .. (on and 1 or 0), 1)
  if count == 0 then return false end
  return (pcall(r.SetEnvelopeStateChunk, envelope, updated, false))
end

-- An envelope that exists but is not on screen is worse than none at all: you
-- record a take you cannot see. REAPER hands out envelopes hidden often enough
-- -- written straight into the chunk, or made by its own write pass -- so the
-- visible flag and its lane are set rather than assumed.
local function envelope_show(envelope)
  if not envelope or not r.GetEnvelopeStateChunk or not r.SetEnvelopeStateChunk then return false end
  local ok, got, chunk = pcall(r.GetEnvelopeStateChunk, envelope, "", false)
  if not ok or not got or type(chunk) ~= "string" then return false end
  local updated, count = chunk:gsub("VIS%s+%d+%s+%d+", "VIS 1 1", 1)
  if count == 0 or updated == chunk then return count > 0 end
  return (pcall(r.SetEnvelopeStateChunk, envelope, updated, false))
end

-- Reading the state must never create an envelope; arming record must, or the
-- first envelope is born active halfway through the take and fights the pad.
local function pad_envelopes(settings, create)
  local list = {}
  for _, slot in ipairs(slots_for(settings)) do
    local entry = state.axes[slot.key]
    local envelope = envelope_of(entry, create and true or false)
    if not envelope and create then envelope = ensure_track_envelope(entry) end
    if envelope then list[#list + 1] = envelope end
  end
  return list
end

-- Recording and listening each need two things set, and in opposite directions:
-- to record, the envelope must be out of the way and the track writing; to hear
-- it back, the envelope must play and the track must not be writing, or the take
-- is overwritten as you listen to it. Getting one of the two wrong costs a take,
-- so they are driven together as three named states instead of four switches.
local PAD_STATES = { "free", "record", "play" }

local function pad_state(settings)
  local active = false
  for _, envelope in ipairs(pad_envelopes(settings)) do
    if envelope_active(envelope) then active = true end
  end
  local writing = false
  for _, track in ipairs(automation_tracks(settings)) do
    if AUTOMATION_WRITING[automation_mode(track)] then writing = true end
  end
  if writing and not active then return "record" end
  if not writing and active then return "play" end
  if not writing and not active then return "free" end
  return "custom" -- writing while the envelope plays: someone set that by hand
end

local function pad_set_state(app, settings, want)
  local envelopes = pad_envelopes(settings, want == "record")
  for _, envelope in ipairs(envelopes) do
    envelope_set_active(envelope, want == "play")
    if want ~= "free" then envelope_show(envelope) end
  end
  if r.SetTrackAutomationMode then
    -- Write while recording, Read otherwise. Read still plays the envelope; it
    -- is the envelope's own active flag that decides whether you hear it.
    local mode = want == "record" and 3 or 1
    for _, track in ipairs(automation_tracks(settings)) do
      r.SetTrackAutomationMode(track, mode)
    end
  end
  -- A global override would sit on top of all of that, so it steps aside.
  if r.GetGlobalAutomationOverride and r.SetGlobalAutomationOverride
    and r.GetGlobalAutomationOverride() >= 0 then
    r.SetGlobalAutomationOverride(-1)
  end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  if r.UpdateArrange then r.UpdateArrange() end
  app.status = "XY Pad: " .. (want == "record" and "recording - the pad is free and writing automation"
    or want == "play" and "playing back the recorded automation"
    or "free - the pad moves, nothing is recorded or played back")
end

local function automation_point(entry, value, position)
  if not entry or entry.missing or not r.InsertEnvelopePoint then return false end
  if not AUTOMATION_WRITING[automation_mode(entry.track)] then return false end
  local existed = envelope_of(entry, false) ~= nil
  local envelope = envelope_of(entry, true)
  if not envelope then envelope = ensure_track_envelope(entry) end
  -- Fresh envelopes arrive active, which hands the parameter straight back to
  -- them: bypass it so the pad keeps the wheel while it writes.
  if envelope and not existed then
    envelope_set_active(envelope, false)
    envelope_show(envelope)
  end
  if not envelope then
    state.auto.needs_envelope = entry.param_name or "that parameter"
    return false
  end
  -- Unsorted on the way in: the play cursor only moves forwards, so the points
  -- arrive in order anyway and one sort on stop is enough.
  r.InsertEnvelopePoint(envelope, position, envelope_value(entry, envelope, value), 0, 0, false, true)
  state.auto.touched[tostring(envelope)] = envelope
  return true
end

-- Called from the one place every value change goes through, so a drag, a
-- movement and a MIDI trigger all write the same way.
local function automation_write(settings, x, y)
  local playing = r.GetPlayState and r.GetPlayState() or 0
  if (playing & 1) ~= 1 and (playing & 4) ~= 4 then return end
  local position = r.GetPlayPosition and r.GetPlayPosition() or 0
  local auto = state.auto
  -- Thin the same way movements are thinned: a point per pixel of mouse travel
  -- would bloat the envelope for nothing.
  if position - auto.last_pos < 0.02
    and math.abs(x - auto.last_x) < MOVE_DEAD_BAND
    and math.abs(y - auto.last_y) < MOVE_DEAD_BAND then
    return
  end
  auto.last_pos, auto.last_x, auto.last_y = position, x, y
  local wrote = false
  if settings.pad_mode == "corners" then
    local tl, tr, bl, br = corner_weights(x, y)
    wrote = automation_point(state.axes.c1, tl, position) or wrote
    wrote = automation_point(state.axes.c2, tr, position) or wrote
    wrote = automation_point(state.axes.c3, bl, position) or wrote
    wrote = automation_point(state.axes.c4, br, position) or wrote
  else
    wrote = automation_point(state.axes.x, x, position) or wrote
    wrote = automation_point(state.axes.y, y, position) or wrote
  end
  auto.active = wrote
end

-- Tidy up once the transport stops: sort what was written and let the arrange
-- redraw. Doing this per point would be needless work while rolling.
local function automation_flush(app)
  local auto = state.auto
  if auto.needs_envelope and app then
    app.status = "XY Pad: could not create an envelope for " .. auto.needs_envelope ..
      " - show it by hand and record again (send envelopes need SWS)"
    auto.needs_envelope = nil
  end
  local any = false
  for key, envelope in pairs(auto.touched) do
    if r.Envelope_SortPoints then pcall(r.Envelope_SortPoints, envelope) end
    auto.touched[key] = nil
    any = true
  end
  auto.active = false
  auto.last_pos, auto.last_x, auto.last_y = -1, -1, -1
  if any and r.UpdateArrange then r.UpdateArrange() end
end

local function pad_apply(settings, x, y)
  state.pos.x, state.pos.y = clamp(x, 0, 1), clamp(y, 0, 1)
  if settings.pad_mode == "corners" then
    local tl, tr, bl, br = corner_weights(state.pos.x, state.pos.y)
    set_param_value(state.axes.c1, tl)
    set_param_value(state.axes.c2, tr)
    set_param_value(state.axes.c3, bl)
    set_param_value(state.axes.c4, br)
  else
    set_param_value(state.axes.x, state.pos.x)
    set_param_value(state.axes.y, state.pos.y)
  end
  automation_write(settings, state.pos.x, state.pos.y)
end

local function track_colour(track, fallback)
  if not track or not r.GetTrackColor or not r.ColorFromNative then return fallback end
  local native = r.GetTrackColor(track)
  if not native or native == 0 then return fallback end
  local ok, red, green, blue = pcall(r.ColorFromNative, native)
  if not ok or not red then return fallback end
  return (red << 24) | (green << 16) | (blue << 8) | 0xFF
end

-- A send morph puts all four corners on one track, so the source colour would
-- paint the whole pad the same. The bus each send feeds is what tells them
-- apart, and it is the colour you already look for in the mixer.
local function entry_colour(entry, fallback)
  if not entry or entry.missing then return fallback end
  local track = entry.track
  if entry.kind == "send" and r.GetTrackSendInfo_Value then
    local ok, dest = pcall(r.GetTrackSendInfo_Value, entry.track, 0, entry.send, "P_DESTTRACK")
    if ok and dest and dest ~= 0 then track = dest end
  end
  return track_colour(track, fallback)
end

local function formatted_value(entry)
  if not entry or entry.missing then return "" end
  if entry.kind == "vol" or entry.kind == "send" then
    local unit = param_value(entry) or 0
    if unit <= 0.0001 then return "-inf dB" end
    return string.format("%+.1f dB", VOL_MIN_DB + unit * (VOL_MAX_DB - VOL_MIN_DB))
  elseif entry.kind == "pan" then
    local pan = (param_value(entry) or 0.5) * 2 - 1
    if math.abs(pan) < 0.005 then return "center" end
    return string.format("%d%% %s", math.floor(math.abs(pan) * 100 + 0.5), pan < 0 and "L" or "R")
  end
  if r.TrackFX_GetFormattedParamValue then
    local ok, _, text = pcall(r.TrackFX_GetFormattedParamValue, entry.track, entry.fx, entry.param, "")
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
local function record_sample(settings)
  local rec = state.rec
  if not rec or (rec.phase ~= "recording" and rec.phase ~= "armed") then return end
  -- The puck is what gets stored, not the parameter values, so a movement means
  -- the same thing in either mode and old recordings keep working.
  local x, y = pad_position(settings)
  x, y = x or 0.5, y or 0.5
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
local function playback_step(settings)
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
      pad_apply(settings,
        previous.x + (sample.x - previous.x) * mix,
        previous.y + (sample.y - previous.y) * mix)
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
  for _, key in ipairs(AXES) do
    local entry = state.axes[key]
    if entry and not entry.missing then return entry.track end
  end
  return nil
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

local function draw_slot(ctx, app, settings, axis, label, entry, width)
  local gap = UIScale.gap(4)
  local row_h = r.ImGui_GetFrameHeight(ctx)
  local learn_w = UIScale.text_button_w(ctx, "Learn", 56)
  local clear_w = UIScale.round(24)
  local label_w = UIScale.round(22)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local lh = r.ImGui_GetTextLineHeight(ctx)

  r.ImGui_DrawList_AddText(dl, ox, oy + (row_h - lh) * 0.5, Theme.colors.accent, label)

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

  -- The row is the part that gets truncated, so hovering it spells everything
  -- out. The names are already read and cached with the assignment, so this
  -- costs nothing; only the formatted value is fetched, and only while hovered.
  r.ImGui_SetCursorScreenPos(ctx, ox + label_w, oy)
  r.ImGui_InvisibleButton(ctx, "##xy_slot_" .. axis, math.max(UIScale.round(10), text_w), row_h)
  if r.ImGui_IsItemHovered(ctx) then
    local tip
    if not entry then
      tip = label .. " is not assigned yet\nTouch a parameter in an FX window, then press Learn"
    elseif entry.missing then
      tip = label .. " points at a track that is no longer in this project"
    else
      tip = "Track:  " .. (entry.track_name or "?") ..
        "\nFX:  " .. (entry.fx_full or entry.fx_name or "?") ..
        "\nParameter:  " .. (entry.param_name or "?")
      local value = formatted_value(entry)
      if value ~= "" then tip = tip .. "\nValue:  " .. value end
    end
    r.ImGui_SetTooltip(ctx, tip .. "\nRight-click for track volume, pan or a send")
  end
  if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1) then
    r.ImGui_OpenPopup(ctx, "##xy_target_" .. axis)
  end
  if r.ImGui_BeginPopup(ctx, "##xy_target_" .. axis) then
    local selected = r.GetSelectedTrack and r.GetSelectedTrack(0, 0) or nil
    if not selected then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select a track first")
    else
      r.ImGui_TextColored(ctx, Theme.colors.accent, track_label(selected))
      r.ImGui_Separator(ctx)
      if r.ImGui_Selectable(ctx, "Volume") then assign_track_target(app, axis, "vol") end
      if r.ImGui_Selectable(ctx, "Pan") then assign_track_target(app, axis, "pan") end
      local sends = r.GetTrackNumSends and r.GetTrackNumSends(selected, 0) or 0
      if sends > 0 then
        r.ImGui_Separator(ctx)
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Send level")
        for index = 0, sends - 1 do
          if r.ImGui_Selectable(ctx, send_label(selected, index) .. "##xy_send" .. index) then
            assign_track_target(app, axis, "send", index)
          end
        end
        if sends >= 2 then
          r.ImGui_Separator(ctx)
          if r.ImGui_Selectable(ctx, "Morph the first 4 sends onto the corners") then
            assign_send_morph(app, settings, selected)
          end
          if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Fills all four corners at once and switches the pad to corner mode")
          end
        end
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  r.ImGui_SetCursorScreenPos(ctx, ox + label_w + text_w + gap, oy)
  if r.ImGui_Button(ctx, "Learn##xy_learn_" .. axis, learn_w, row_h) then assign(app, axis) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Assign the parameter you last moved in an FX window to " .. label)
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "x##xy_clear_" .. axis, clear_w, row_h) then clear(app, axis) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear " .. label) end
end

function M.init(app)
  ensure_settings(app)
end

-- Runs every frame for every loaded module, so a recording or a playing movement
-- carries on while you are looking at something else entirely.
function M.update(app)
  local settings = ensure_settings(app)
  local playing = r.GetPlayState and r.GetPlayState() or 0
  local rolling = (playing & 1) == 1 or (playing & 4) == 4
  if state.auto.was_rolling and not rolling then automation_flush(app) end
  state.auto.was_rolling = rolling
  local armed = settings.trigger_mode ~= "off"
  if not state.rec and not state.play and not armed then return end
  local resolved = axes(false)
  if armed then midi_poll(app, settings) end
  if state.rec then
    if state.rec.phase == "countin" and now_time() >= state.rec.until_time then
      state.rec.phase = "armed"
    end
    record_sample(settings)
  end
  playback_step(settings)
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
  local spacing_x, spacing_y = UIScale.gap(8), UIScale.gap(4)
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local ok, sx, sy = pcall(r.ImGui_GetStyleVar, ctx, r.ImGui_StyleVar_ItemSpacing())
    if ok and type(sy) == "number" then
      spacing_x, spacing_y = sx or spacing_x, sy
    end
  end

  local resolved = axes(false)
  local corners = settings.pad_mode == "corners"

  -- Mode row: only the slots of the active mode are shown, so the two-parameter
  -- pad stays exactly as simple as it was.
  -- One row of four equal buttons across the full width: the two pad modes, the
  -- envelope switch and the automation mode. Placed by hand rather than with
  -- SameLine so they stay evenly divided whatever the module is scaled to.
  local mode_origin_x, mode_y = r.ImGui_GetCursorScreenPos(ctx)
  mode_origin_x, mode_y = math.floor(mode_origin_x), math.floor(mode_y)
  local mode_w = math.max(UIScale.round(40), (width - 2 * gap) / 3)
  local function row_slot(index) return mode_origin_x + (index - 1) * (mode_w + gap) end

  for index, mode in ipairs({ { id = "xy", label = "2 axes" }, { id = "corners", label = "4 corners" } }) do
    local on = settings.pad_mode == mode.id
    local pushed = 0
    if on and r.ImGui_Col_Button then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft)
      pushed = 1
    end
    r.ImGui_SetCursorScreenPos(ctx, row_slot(index), mode_y)
    if r.ImGui_Button(ctx, mode.label .. "##xy_mode_" .. mode.id, mode_w, row_h) then
      settings.pad_mode = mode.id
      save(app)
    end
    if pushed > 0 then r.ImGui_PopStyleColor(ctx, pushed) end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, mode.id == "xy"
        and "One parameter per axis"
        or "One parameter per corner, blended by how near the puck is - the four always add up to 1")
    end
  end
  -- Automation arming, right-aligned on the same row: the point of it is to get
  -- the pad writing without leaving the module.
  local override = r.GetGlobalAutomationOverride and r.GetGlobalAutomationOverride() or -1
  local auto_tracks = automation_tracks(settings)
  local effective = override >= 0 and override
    or (auto_tracks[1] and r.GetTrackAutomationMode and r.GetTrackAutomationMode(auto_tracks[1]) or 0)
  local envelopes = pad_envelopes(settings)
  local current = pad_state(settings)
  local STATE_LOOK = {
    free = { label = "Free", lit = false },
    record = { label = "Record", lit = true },
    play = { label = "Play", lit = true },
    custom = { label = "Custom", lit = false },
  }
  local look = STATE_LOOK[current] or STATE_LOOK.custom
  r.ImGui_SetCursorScreenPos(ctx, row_slot(3), mode_y)
  local pushed_state = 0
  if look.lit and r.ImGui_Col_Button then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),
      current == "record" and (Theme.colors.danger or 0xFF3B3BFF) or Theme.colors.accent_soft)
    pushed_state = 1
  end
  if r.ImGui_Button(ctx, look.label .. "##xy_state", mode_w, row_h) then
    -- Free -> Record -> Play -> Free, so one button walks the whole cycle.
    local next_state = "free"
    for index, name in ipairs(PAD_STATES) do
      if name == current then next_state = PAD_STATES[(index % #PAD_STATES) + 1] end
    end
    pad_set_state(app, settings, next_state)
  end
  if pushed_state > 0 then r.ImGui_PopStyleColor(ctx, pushed_state) end
  if r.ImGui_IsItemHovered(ctx) then
    local tip = "Free: the pad moves, nothing recorded or played back" ..
      "\nRecord: the pad is free and writes automation" ..
      "\nPlay: the recorded automation plays and the pad stands back" ..
      "\nClick to cycle, right-click for the individual modes"
    if override >= 0 then
      tip = "A global override is in force, so track modes are ignored\n" .. tip
    end
    r.ImGui_SetTooltip(ctx, #auto_tracks == 0 and "Assign a parameter first" or tip)
  end
  if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1) then
    r.ImGui_OpenPopup(ctx, "##xy_auto_menu")
  end
  if r.ImGui_BeginPopup(ctx, "##xy_auto_menu") then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "This pad's track(s)")
    for _, entry in ipairs(AUTOMATION_MODES) do
      if r.ImGui_Selectable(ctx, entry.label .. "##xy_auto_t" .. entry.mode,
        override < 0 and effective == entry.mode) then
        if r.SetTrackAutomationMode then
          for _, track in ipairs(auto_tracks) do r.SetTrackAutomationMode(track, entry.mode) end
        end
        if r.SetGlobalAutomationOverride and override >= 0 then r.SetGlobalAutomationOverride(-1) end
        app.status = "XY Pad: " .. entry.label .. " on " .. #auto_tracks .. " track(s)"
      end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Global override")
    if r.ImGui_Selectable(ctx, "Off##xy_auto_g_off", override < 0) then
      if r.SetGlobalAutomationOverride then r.SetGlobalAutomationOverride(-1) end
      app.status = "XY Pad: global override off"
    end
    for _, entry in ipairs(AUTOMATION_MODES) do
      if r.ImGui_Selectable(ctx, entry.label .. "##xy_auto_g" .. entry.mode, override == entry.mode) then
        if r.SetGlobalAutomationOverride then r.SetGlobalAutomationOverride(entry.mode) end
        app.status = "XY Pad: global override " .. entry.label
      end
    end
    if #envelopes > 0 then
      r.ImGui_Separator(ctx)
      if r.ImGui_Selectable(ctx, "Clear recorded points") then
        for _, envelope in ipairs(envelopes) do
          if r.DeleteEnvelopePointRange then
            pcall(r.DeleteEnvelopePointRange, envelope, -1, 1e9)
          end
          if r.Envelope_SortPoints then pcall(r.Envelope_SortPoints, envelope) end
        end
        if r.UpdateArrange then r.UpdateArrange() end
        app.status = "XY Pad: cleared " .. #envelopes .. " envelope(s)"
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  -- Every button in that row was placed by hand, so the cursor already sits
  -- below it: no NewLine needed, which would only add an empty one.
  r.ImGui_SetCursorScreenPos(ctx, mode_origin_x, mode_y + row_h + vgap)

  -- The assignment rows sit right under each other: ImGui's own item spacing is
  -- what pushed them apart, so it is squeezed for this stretch instead of being
  -- padded further with spacers.
  local tightened = false
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_ItemSpacing then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), spacing_x, UIScale.gap(1))
    tightened = true
  end
  for _, slot in ipairs(slots_for(settings)) do
    draw_slot(ctx, app, settings, slot.key, slot.label, resolved[slot.key], width)
  end
  if tightened then r.ImGui_PopStyleVar(ctx) end
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
  local vx, vy = pad_position(settings)
  local live = pad_assigned(settings)

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
    pad_apply(settings, nx, ny)
    vx, vy = nx, ny
  end
  if r.ImGui_IsItemDeactivated and r.ImGui_IsItemDeactivated(ctx) then
    if settings.momentary and state.drag and state.drag.x and state.drag.y then
      pad_apply(settings, state.drag.x, state.drag.y)
      vx, vy = state.drag.x, state.drag.y
    end
    state.drag = nil
  end

  r.ImGui_DrawList_AddRectFilled(dl, px, py, px + size, py + size, Theme.colors.window_bg, UIScale.px(5))
  if corners and live then
    -- Each quadrant glows in its track's colour, at the strength of that corner's
    -- weight, so the blend is visible rather than a number you have to read.
    local weights = { corner_weights(vx or 0.5, vy or 0.5) }
    local half = size * 0.5
    local places = {
      { key = "c1", x = 0, y = 0 }, { key = "c2", x = 1, y = 0 },
      { key = "c3", x = 0, y = 1 }, { key = "c4", x = 1, y = 1 },
    }
    for index, place in ipairs(places) do
      local entry = state.axes[place.key]
      local weight = weights[index] or 0
      local qx = px + place.x * half
      local qy = py + place.y * half
      local colour = entry_colour(entry, Theme.colors.accent)
      local alpha = math.floor(0x10 + weight * 0x70)
      r.ImGui_DrawList_AddRectFilled(dl, qx, qy, qx + half, qy + half,
        (colour & 0xFFFFFF00) | alpha, UIScale.px(4))
      if entry and not entry.missing then
        local name = fit(ctx, entry.param_name or "?", half - UIScale.round(10))
        local tw = r.ImGui_CalcTextSize(ctx, name)
        local tx = place.x == 0 and (qx + UIScale.round(5)) or (qx + half - tw - UIScale.round(5))
        local ty = place.y == 0 and (qy + UIScale.round(5)) or (qy + half - lh * 2 - UIScale.round(5))
        local text_col = Theme.text_for_background(Theme.colors.window_bg, colour, Theme.colors.text, 3)
        r.ImGui_DrawList_AddText(dl, tx, ty, text_col, name)
        local pct = string.format("%d%%", math.floor(weight * 100 + 0.5))
        local pw = r.ImGui_CalcTextSize(ctx, pct)
        r.ImGui_DrawList_AddText(dl, place.x == 0 and tx or (qx + half - pw - UIScale.round(5)),
          ty + lh, Theme.colors.text_dim, pct)
      end
    end
  end
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
  -- Corner mode labels itself inside the pad, so this line is only for the axes.
  local ax, ay = state.axes.x, state.axes.y
  local left = (not corners) and ax and not ax.missing
    and ((ax.param_name or "X") .. "  " .. formatted_value(ax)) or ""
  local right = (not corners) and ay and not ay.missing
    and ((ay.param_name or "Y") .. "  " .. formatted_value(ay)) or ""
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

  local slots = slots_for(settings)
  local status = 0
  for _, slot in ipairs(slots) do
    local entry = state.axes[slot.key]
    if entry and not entry.missing then status = status + 1 end
  end
  UI.draw_info_line(ctx, "XY Pad | " .. status .. " of " .. #slots .. " assigned | " ..
    (corners and "4 corners" or "2 axes") .. (settings.momentary and " | momentary" or "") ..
    (state.auto.active and " | writing automation" or ""))
end

return M
