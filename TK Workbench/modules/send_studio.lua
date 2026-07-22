local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")

local M = {
  id = "send_studio",
  title = "Send Studio",
  icon = "SND",
  version = "0.1.0"
}

local defaults = {
  min_db = -60,
  max_db = 12,
  view_mode = "cards",        -- "cards" | "list"
  card_flow = "columns",      -- "columns" (fill height first) | "rows" (fill width first)
  pinned_guid = "",
  show_sends = true,
  show_receives = true,
  default_send_mode = 0,      -- 0 = Post, 1 = Pre-FX, 3 = Pre-Fader
  meter_smoothing = 0.35
}

local state = {
  meters = {},
  drag = nil,                 -- { id = lane_id, kind = "vol" | "pan" }
  picker_open = false,
  picker_mode = nil,          -- "send" | "receive"
  picker_filter = "",
  bus_open = false,
  bus_name = "FX Bus",
  clipboard = nil             -- copied sends: list of routing snapshots
}

-- I_SENDMODE: 0 = Post-Fader (Post-Pan), 1 = Pre-FX, 3 = Post-FX (Pre-Fader)
local SEND_MODES = { 0, 1, 3 }
local SEND_MODE_LABELS = { [0] = "Post", [1] = "Pre-FX", [3] = "Pre-Fader" }

local function send_mode_label(mode)
  return SEND_MODE_LABELS[tonumber(mode) or 0] or "Post"
end

local function next_send_mode(mode)
  mode = tonumber(mode) or 0
  for index, value in ipairs(SEND_MODES) do
    if value == mode then return SEND_MODES[(index % #SEND_MODES) + 1] end
  end
  return SEND_MODES[1]
end

-- ---------------------------------------------------------------------------
-- Small utilities (mirrors Control Room conventions)
-- ---------------------------------------------------------------------------

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function linear_to_db(value, minimum_db)
  value = tonumber(value) or 0
  if value <= 0.000001 then return minimum_db end
  return math.max(minimum_db, math.log(value) / math.log(10) * 20)
end

local function db_to_linear(value, minimum_db, maximum_db)
  value = clamp(value, minimum_db, maximum_db)
  if value <= minimum_db then return 0 end
  return 10 ^ (value / 20)
end

local function format_db(value, settings)
  local db = linear_to_db(value, settings.min_db or defaults.min_db)
  if db <= (settings.min_db or defaults.min_db) + 0.05 then return "-inf" end
  return string.format("%+.1f dB", db)
end

local function format_pan(pan)
  pan = tonumber(pan) or 0
  if math.abs(pan) < 0.005 then return "C" end
  local pct = math.floor(math.abs(pan) * 100 + 0.5)
  return (pan < 0 and "L" or "R") .. tostring(pct)
end

local function calc_text_width(ctx, value)
  if r.ImGui_CalcTextSize then
    local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
    return tonumber(width) or 0
  end
  return #(tostring(value or "")) * 7
end

local function ellipsize_text(ctx, value, max_width)
  value = tostring(value or "")
  if value == "" or calc_text_width(ctx, value) <= max_width then return value end
  while #value > 1 and calc_text_width(ctx, value .. "...") > max_width do value = value:sub(1, -2) end
  return value .. "..."
end

local function color_with_alpha(color, alpha)
  color = tonumber(color) or 0xFFFFFFFF
  return (color & 0xFFFFFF00) | ((tonumber(alpha) or 0xFF) & 0xFF)
end

local function valid_track(track)
  return track and r.ValidatePtr2(0, track, "MediaTrack*") == true
end

local function track_guid(track)
  if not valid_track(track) or not r.GetTrackGUID then return nil end
  local ok, guid = pcall(r.GetTrackGUID, track)
  return ok and guid and guid ~= "" and guid or nil
end

local function track_by_guid(guid)
  if not guid or guid == "" or not r.CountTracks or not r.GetTrackGUID then return nil end
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if valid_track(track) and track_guid(track) == guid then return track end
  end
  return nil
end

local function track_name(track)
  if not valid_track(track) then return "Track" end
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  local number = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0)
  return "Track " .. tostring(number)
end

local function track_index_label(track)
  if not valid_track(track) then return "" end
  local number = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0)
  if number <= 0 then return "" end
  return tostring(number)
end

local function native_color_to_u32(native, alpha)
  native = tonumber(native) or 0
  if native == 0 then return nil end
  alpha = alpha or 0xFF
  if r.ColorFromNative then
    local ok, red, green, blue = pcall(r.ColorFromNative, native & 0xFFFFFF)
    if ok and red and green and blue then return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | (alpha & 0xFF) end
  end
  local red = native & 0xFF
  local green = (native >> 8) & 0xFF
  local blue = (native >> 16) & 0xFF
  return (red << 24) | (green << 16) | (blue << 8) | (alpha & 0xFF)
end

local function track_color(track)
  if not valid_track(track) or not r.GetTrackColor then return nil end
  return native_color_to_u32(r.GetTrackColor(track), 0xFF)
end

local function write_with_undo(label, callback)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, result = pcall(callback)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock(label, -1)
  return ok and result ~= false
end

local function read_track_peak(track)
  if not valid_track(track) or not r.Track_GetPeakInfo then return 0 end
  local left_ok, left_peak = pcall(r.Track_GetPeakInfo, track, 0)
  local right_ok, right_peak = pcall(r.Track_GetPeakInfo, track, 1)
  left_peak = left_ok and tonumber(left_peak) or 0
  right_peak = right_ok and tonumber(right_peak) or 0
  return math.max(math.abs(left_peak or 0), math.abs(right_peak or 0))
end

local function smoothed_meter(id, raw_value, settings)
  local previous = state.meters[id] or 0
  local smoothing = clamp(settings.meter_smoothing or defaults.meter_smoothing, 0.05, 0.95)
  local next_value = raw_value > previous and raw_value or previous + (raw_value - previous) * smoothing
  if next_value < 0.0001 then next_value = 0 end
  state.meters[id] = next_value
  return next_value
end

local function meter_color(value)
  if value >= 0.98 then return Theme.colors.danger end
  if value >= 0.75 then return Theme.colors.warning end
  return Theme.colors.accent
end

local function mouse_wheel_delta(ctx)
  if not r.ImGui_GetMouseWheel then return 0 end
  local ok, value = pcall(r.ImGui_GetMouseWheel, ctx)
  return ok and tonumber(value) or 0
end

local function shift_key_down(ctx)
  if r.ImGui_IsKeyDown and r.ImGui_Key_LeftShift and r.ImGui_Key_RightShift then
    return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
  end
  return false
end

local function ctrl_down(ctx)
  if not r.ImGui_IsKeyDown then return false end
  local down = false
  if r.ImGui_Key_LeftCtrl then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) end
  if r.ImGui_Key_RightCtrl then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl()) end
  if r.ImGui_Key_LeftSuper then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftSuper()) end
  if r.ImGui_Key_RightSuper then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightSuper()) end
  return down
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function ensure_settings(app)
  app.settings.send_studio = app.settings.send_studio or {}
  local settings = app.settings.send_studio
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  settings.min_db = tonumber(settings.min_db) or defaults.min_db
  settings.max_db = tonumber(settings.max_db) or defaults.max_db
  if settings.max_db <= settings.min_db then settings.max_db = settings.min_db + 12 end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

-- ---------------------------------------------------------------------------
-- Target track (selection + pin)
-- ---------------------------------------------------------------------------

local function selected_track(app)
  local track = app.selection and app.selection.track and app.selection.track.pointer
  if valid_track(track) then return track end
  track = r.GetSelectedTrack(0, 0)
  if valid_track(track) then return track end
  return nil
end

local function target_track(app, settings)
  local guid = settings.pinned_guid
  if guid and guid ~= "" then
    local track = track_by_guid(guid)
    if valid_track(track) then return track, true end
    settings.pinned_guid = ""
    if app.save_settings then app.save_settings() end
  end
  return selected_track(app), false
end

local function set_pin(app, settings, track)
  local guid = track and track_guid(track) or nil
  settings.pinned_guid = guid or ""
  if app.save_settings then app.save_settings() end
end

-- ---------------------------------------------------------------------------
-- Send / receive read + write helpers
-- ---------------------------------------------------------------------------

local function send_value(track, category, index, param)
  if not valid_track(track) or not index or not r.GetTrackSendInfo_Value then return nil end
  local ok, value = pcall(r.GetTrackSendInfo_Value, track, category, index, param)
  if ok and type(value) == "number" then return value end
  return nil
end

local function send_other_track(track, category, index)
  local param = category == -1 and "P_SRCTRACK" or "P_DESTTRACK"
  if not valid_track(track) or not r.GetTrackSendInfo_Value then return nil end
  local ok, other = pcall(r.GetTrackSendInfo_Value, track, category, index, param)
  if ok and valid_track(other) then return other end
  return nil
end

local function write_send_volume(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  value = clamp(value, 0, 4)
  return write_with_undo("Send Studio: Volume", function()
    return r.SetTrackSendInfo_Value(track, category, index, "D_VOL", value)
  end)
end

local function write_send_pan(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  value = clamp(value, -1, 1)
  return write_with_undo("Send Studio: Pan", function()
    return r.SetTrackSendInfo_Value(track, category, index, "D_PAN", value)
  end)
end

local function write_send_mute(track, category, index, muted)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Mute", function()
    return r.SetTrackSendInfo_Value(track, category, index, "B_MUTE", muted and 1 or 0)
  end)
end

local function write_send_mode(track, category, index, mode)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Send mode", function()
    return r.SetTrackSendInfo_Value(track, category, index, "I_SENDMODE", tonumber(mode) or 0)
  end)
end

local function write_send_phase(track, category, index, inverted)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Phase", function()
    return r.SetTrackSendInfo_Value(track, category, index, "B_PHASE", inverted and 1 or 0)
  end)
end

local function write_send_mono(track, category, index, mono)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Mono", function()
    return r.SetTrackSendInfo_Value(track, category, index, "B_MONO", mono and 1 or 0)
  end)
end

-- Audio channel routing (I_SRCCHAN / I_DSTCHAN). Encoding: channel index in the
-- low bits, bit 1024 = mono, -1 (source only) = MIDI / no audio.
local function chan_parse(raw)
  raw = math.floor(tonumber(raw) or 0)
  if raw < 0 then return { none = true } end
  return { channel = raw & 0x1FF, mono = (raw & 1024) ~= 0 }
end

local function chan_label(raw)
  local parsed = chan_parse(raw)
  if parsed.none then return "MIDI" end
  if parsed.mono then return tostring(parsed.channel + 1) end
  return tostring(parsed.channel + 1) .. "/" .. tostring(parsed.channel + 2)
end

local function track_channel_count(track)
  if not valid_track(track) or not r.GetMediaTrackInfo_Value then return 2 end
  local ok, value = pcall(r.GetMediaTrackInfo_Value, track, "I_NCHAN")
  return ok and math.max(2, math.floor(tonumber(value) or 2)) or 2
end

-- Grow a track's channel count (even, min 2) so a chosen channel pair exists.
local function ensure_track_channels(track, needed)
  if not valid_track(track) or not r.SetMediaTrackInfo_Value then return false end
  needed = math.max(2, math.floor(tonumber(needed) or 2))
  if needed % 2 == 1 then needed = needed + 1 end
  if track_channel_count(track) >= needed then return false end
  return write_with_undo("Send Studio: Set track channels", function()
    return r.SetMediaTrackInfo_Value(track, "I_NCHAN", needed)
  end)
end

-- Channel options up to at least 16 channels, so higher pairs (3/4, 5/6 ...) can
-- be picked even when the track does not have them yet (needs = channels required).
local function channel_options(track, include_midi)
  local options = {}
  if include_midi then options[#options + 1] = { value = -1, label = "MIDI (no audio)", needs = 0 } end
  local count = math.max(track_channel_count(track), 16)
  for channel = 0, count - 2, 2 do
    options[#options + 1] = { value = channel, label = tostring(channel + 1) .. "/" .. tostring(channel + 2), needs = channel + 2 }
  end
  for channel = 0, count - 1 do
    options[#options + 1] = { value = channel | 1024, label = "Mono " .. tostring(channel + 1), needs = channel + 1 }
  end
  return options
end

local function write_send_srcchan(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Source channel", function()
    return r.SetTrackSendInfo_Value(track, category, index, "I_SRCCHAN", math.floor(tonumber(value) or 0))
  end)
end

local function write_send_dstchan(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Destination channel", function()
    return r.SetTrackSendInfo_Value(track, category, index, "I_DSTCHAN", math.floor(tonumber(value) or 0))
  end)
end

-- MIDI routing (I_MIDIFLAGS): low 5 bits = source channel (0 = all, 1-16),
-- next 5 bits = destination channel (0 = same as source, 1-16). Other bits kept.
local function midi_src_channel(flags) return math.floor(flags) & 0x1F end
local function midi_dst_channel(flags) return (math.floor(flags) >> 5) & 0x1F end

local function write_send_midi_src(track, category, index, channel)
  if not valid_track(track) or not r.SetTrackSendInfo_Value or not r.GetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: MIDI source channel", function()
    local flags = math.floor(r.GetTrackSendInfo_Value(track, category, index, "I_MIDIFLAGS") or 0)
    return r.SetTrackSendInfo_Value(track, category, index, "I_MIDIFLAGS", (flags & ~0x1F) | (channel & 0x1F))
  end)
end

local function write_send_midi_dst(track, category, index, channel)
  if not valid_track(track) or not r.SetTrackSendInfo_Value or not r.GetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: MIDI destination channel", function()
    local flags = math.floor(r.GetTrackSendInfo_Value(track, category, index, "I_MIDIFLAGS") or 0)
    return r.SetTrackSendInfo_Value(track, category, index, "I_MIDIFLAGS", (flags & ~0x3E0) | ((channel & 0x1F) << 5))
  end)
end

local function remove_send(track, category, index)
  if not valid_track(track) or not r.RemoveTrackSend then return false end
  return write_with_undo("Send Studio: Remove", function()
    return r.RemoveTrackSend(track, category, index)
  end)
end

local function select_track(track)
  if valid_track(track) and r.SetOnlyTrackSelected then
    r.SetOnlyTrackSelected(track)
    if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
    if r.SetMixerScroll then pcall(r.SetMixerScroll, track) end
    r.UpdateArrange()
    return true
  end
  return false
end

-- The target track's own fader / mute (D_VOL / B_MUTE), not a send.
local function read_track_own_volume(track)
  if not valid_track(track) or not r.GetMediaTrackInfo_Value then return 1 end
  return r.GetMediaTrackInfo_Value(track, "D_VOL") or 1
end

local function write_track_own_volume(track, value)
  if not valid_track(track) or not r.SetMediaTrackInfo_Value then return false end
  value = clamp(value, 0, 4)
  return write_with_undo("Send Studio: Track volume", function()
    return r.SetMediaTrackInfo_Value(track, "D_VOL", value)
  end)
end

local function read_track_own_mute(track)
  if not valid_track(track) or not r.GetMediaTrackInfo_Value then return false end
  return (r.GetMediaTrackInfo_Value(track, "B_MUTE") or 0) == 1
end

local function write_track_own_mute(track, muted)
  if not valid_track(track) or not r.SetMediaTrackInfo_Value then return false end
  return write_with_undo("Send Studio: Track mute", function()
    return r.SetMediaTrackInfo_Value(track, "B_MUTE", muted and 1 or 0)
  end)
end

local function read_track_own_pan(track)
  if not valid_track(track) or not r.GetMediaTrackInfo_Value then return 0 end
  return r.GetMediaTrackInfo_Value(track, "D_PAN") or 0
end

local function write_track_own_pan(track, value)
  if not valid_track(track) or not r.SetMediaTrackInfo_Value then return false end
  value = clamp(value, -1, 1)
  return write_with_undo("Send Studio: Track pan", function()
    return r.SetMediaTrackInfo_Value(track, "D_PAN", value)
  end)
end

-- ---------------------------------------------------------------------------
-- Solo model: a per-track, project-persistent "solo map" that drives send
-- mutes. Each send/receive gets a state (none/solo/defeat). A solo mutes every
-- other non-defeat send/receive of the track; a defeat keeps its send audible
-- whenever a solo is active. Stored in track ext-state so it survives sessions
-- and can be fully reverted (original mutes are remembered before soloing).
-- ---------------------------------------------------------------------------
local SOLO_MAP_EXT = "TK_SEND_STUDIO_SOLO"
local ORIG_MUTE_EXT = "TK_SEND_STUDIO_ORIGMUTE"
local SOLO_NONE, SOLO_ON, SOLO_DEFEAT = 0, 1, 2

local function send_route_key(category, other)
  return tostring(category) .. ":" .. tostring(track_guid(other) or "")
end

local function read_track_map(track, ext_name)
  local map = {}
  if not valid_track(track) or not r.GetSetMediaTrackInfo_String then return map end
  local ok, _, value = pcall(r.GetSetMediaTrackInfo_String, track, "P_EXT:" .. ext_name, "", false)
  if ok and type(value) == "string" and value ~= "" then
    for pair in value:gmatch("[^|]+") do
      local key, val = pair:match("^(.-)=(.*)$")
      if key then map[key] = val end
    end
  end
  return map
end

local function write_track_map(track, ext_name, map)
  if not valid_track(track) or not r.GetSetMediaTrackInfo_String then return end
  local parts = {}
  for key, val in pairs(map) do parts[#parts + 1] = key .. "=" .. tostring(val) end
  r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. ext_name, table.concat(parts, "|"), true)
end

local function read_solo_map(track)
  local map = {}
  for key, val in pairs(read_track_map(track, SOLO_MAP_EXT)) do map[key] = tonumber(val) or SOLO_NONE end
  return map
end

local function solo_state(solo_map, category, other)
  return solo_map[send_route_key(category, other)] or SOLO_NONE
end

local function count_solos(solo_map)
  local n = 0
  for _, value in pairs(solo_map) do if value == SOLO_ON then n = n + 1 end end
  return n
end

local function track_has_solo(track)
  for _, value in pairs(read_solo_map(track)) do
    if value == SOLO_ON or value == SOLO_DEFEAT then return true end
  end
  return false
end

-- Push the solo map into actual send mutes (or restore originals when cleared).
local function apply_solo_map(track)
  local solo_map = read_solo_map(track)
  if count_solos(solo_map) > 0 then
    for _, cat in ipairs({ 0, -1 }) do
      for i = 0, (r.GetTrackNumSends(track, cat) or 0) - 1 do
        local st = solo_map[send_route_key(cat, send_other_track(track, cat, i))] or SOLO_NONE
        r.SetTrackSendInfo_Value(track, cat, i, "B_MUTE", (st == SOLO_ON or st == SOLO_DEFEAT) and 0 or 1)
      end
    end
  else
    local orig = read_track_map(track, ORIG_MUTE_EXT)
    for _, cat in ipairs({ 0, -1 }) do
      for i = 0, (r.GetTrackNumSends(track, cat) or 0) - 1 do
        local prev = orig[send_route_key(cat, send_other_track(track, cat, i))]
        if prev ~= nil then r.SetTrackSendInfo_Value(track, cat, i, "B_MUTE", prev == "1" and 1 or 0) end
      end
    end
    write_track_map(track, ORIG_MUTE_EXT, {})
  end
end

local function save_orig_mutes(track)
  local orig = {}
  for _, cat in ipairs({ 0, -1 }) do
    for i = 0, (r.GetTrackNumSends(track, cat) or 0) - 1 do
      orig[send_route_key(cat, send_other_track(track, cat, i))] = ((send_value(track, cat, i, "B_MUTE") or 0) == 1) and "1" or "0"
    end
  end
  write_track_map(track, ORIG_MUTE_EXT, orig)
end

-- Toggle solo (want_defeat=false) or solo defeat (true) for one route.
local function toggle_solo(track, category, other, want_defeat, exclusive)
  if not valid_track(track) or not r.GetTrackNumSends or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Solo", function()
    local solo_map = read_solo_map(track)
    if count_solos(solo_map) == 0 and not state.audition then save_orig_mutes(track) end
    local key = send_route_key(category, other)
    local current = solo_map[key] or SOLO_NONE
    local target_state
    if want_defeat then
      target_state = (current == SOLO_DEFEAT) and SOLO_NONE or SOLO_DEFEAT
    else
      target_state = (current == SOLO_ON) and SOLO_NONE or SOLO_ON
      if target_state == SOLO_ON and exclusive then
        for k, v in pairs(solo_map) do if v == SOLO_ON then solo_map[k] = nil end end
      end
    end
    solo_map[key] = target_state ~= SOLO_NONE and target_state or nil
    write_track_map(track, SOLO_MAP_EXT, solo_map)
    apply_solo_map(track)
    return true
  end)
end

local function clear_solos(track)
  if not valid_track(track) then return false end
  return write_with_undo("Send Studio: Clear solo", function()
    write_track_map(track, SOLO_MAP_EXT, {})
    apply_solo_map(track)
    return true
  end)
end

-- Audition ("listen"): Solo-In-Place the given tracks. mute_master_track (for
-- return-only) drops that track's master send so only the wet return is heard.
local function audition_key(tracks, mode)
  local guids = {}
  for _, track in ipairs(tracks) do guids[#guids + 1] = track_guid(track) or "" end
  table.sort(guids)
  return table.concat(guids, ">") .. ":" .. tostring(mode or "n")
end

local function restore_audition_raw()
  local entry = state.audition
  if not entry then return true end
  for guid, previous in pairs(entry.solos) do
    local track = track_by_guid(guid)
    if valid_track(track) then r.SetMediaTrackInfo_Value(track, "I_SOLO", previous) end
  end
  for _, mute in ipairs(entry.mutes or {}) do
    local track = track_by_guid(mute.guid)
    if valid_track(track) and r.SetTrackSendInfo_Value then
      r.SetTrackSendInfo_Value(track, mute.category, mute.index, "B_MUTE", mute.previous and 1 or 0)
    end
  end
  if entry.main_send then
    local track = track_by_guid(entry.main_send.guid)
    if valid_track(track) then r.SetMediaTrackInfo_Value(track, "B_MAINSEND", entry.main_send.previous) end
  end
  state.audition = nil
  return true
end

local function restore_audition()
  if not state.audition then return false end
  return write_with_undo("Send Studio: Listen off", restore_audition_raw)
end

local function audition_active(tracks, mode)
  local entry = state.audition
  return entry ~= nil and entry.key == audition_key(tracks, mode)
end

local function toggle_audition(tracks, opts)
  if not r.CountTracks or not r.SetMediaTrackInfo_Value then return false end
  opts = opts or {}
  local mute_master_track = opts.mute_master_track
  local valid = {}
  for _, track in ipairs(tracks) do if valid_track(track) then valid[#valid + 1] = track end end
  if #valid == 0 then return false end
  local mode = mute_master_track and "ro" or "n"
  if audition_active(valid, mode) then return restore_audition() end
  return write_with_undo("Send Studio: Listen", function()
    if state.audition then restore_audition_raw() end
    local wanted = {}
    for _, track in ipairs(valid) do local guid = track_guid(track); if guid then wanted[guid] = true end end
    local solos = {}
    for track_index = 0, (r.CountTracks(0) or 0) - 1 do
      local track = r.GetTrack(0, track_index)
      local guid = track_guid(track)
      if valid_track(track) and guid then
        solos[guid] = r.GetMediaTrackInfo_Value(track, "I_SOLO") or 0
        r.SetMediaTrackInfo_Value(track, "I_SOLO", wanted[guid] and 2 or 0)
      end
    end
    -- Mute the owner's other sends/receives so only the listened routing plays.
    local mutes = {}
    if valid_track(opts.owner) and r.SetTrackSendInfo_Value then
      for _, cat in ipairs({ 0, -1 }) do
        for i = 0, (r.GetTrackNumSends(opts.owner, cat) or 0) - 1 do
          local keep = cat == opts.keep_category and send_other_track(opts.owner, cat, i) == opts.keep_other
          mutes[#mutes + 1] = { guid = track_guid(opts.owner), category = cat, index = i, previous = (send_value(opts.owner, cat, i, "B_MUTE") or 0) == 1 }
          r.SetTrackSendInfo_Value(opts.owner, cat, i, "B_MUTE", keep and 0 or 1)
        end
      end
    end
    local main_send = nil
    if valid_track(mute_master_track) then
      main_send = { guid = track_guid(mute_master_track), previous = r.GetMediaTrackInfo_Value(mute_master_track, "B_MAINSEND") or 1 }
      r.SetMediaTrackInfo_Value(mute_master_track, "B_MAINSEND", 0)
    end
    state.audition = { key = audition_key(valid, mode), solos = solos, mutes = mutes, main_send = main_send }
    return true
  end)
end

-- Build lane descriptors for a given category (0 = sends, -1 = receives).
local function build_rows(track, category, settings)
  local rows = {}
  if not valid_track(track) or not r.GetTrackNumSends then return rows end
  local count = r.GetTrackNumSends(track, category) or 0
  local solo_map = read_solo_map(track)
  for index = 0, count - 1 do
    local other = send_other_track(track, category, index)
    local volume = send_value(track, category, index, "D_VOL") or 1
    local pan = send_value(track, category, index, "D_PAN") or 0
    local muted = (send_value(track, category, index, "B_MUTE") or 0) == 1
    local mode = math.floor(send_value(track, category, index, "I_SENDMODE") or 0)
    local phase = (send_value(track, category, index, "B_PHASE") or 0) == 1
    local src_raw = math.floor(send_value(track, category, index, "I_SRCCHAN") or 0)
    local dst_raw = math.floor(send_value(track, category, index, "I_DSTCHAN") or 0)
    local midi_flags = math.floor(send_value(track, category, index, "I_MIDIFLAGS") or 0)
    local src_track = category == -1 and other or track
    local dst_track = category == -1 and track or other
    local other_name = valid_track(other) and track_name(other) or "Missing track"
    local prefix = category == -1 and "recv" or "send"
    local lane_id = prefix .. "_" .. tostring(index) .. "_" .. tostring(track_guid(other) or index)
    rows[#rows + 1] = {
      id = lane_id,
      category = category,
      index = index,
      label = other_name,
      other = other,
      subtitle = (category == -1 and "Receive" or "Send") .. " | " .. send_mode_label(mode),
      value = volume,
      pan = pan,
      muted = muted,
      mode = mode,
      phase = phase,
      mono = (send_value(track, category, index, "B_MONO") or 0) == 1,
      src_raw = src_raw,
      dst_raw = dst_raw,
      midi_flags = midi_flags,
      src_track = src_track,
      dst_track = dst_track,
      handle_color = track_color(other),
      meter = smoothed_meter(lane_id, read_track_peak(other), settings),
      enabled = valid_track(other),
      solo_on = solo_state(solo_map, category, other) == SOLO_ON,
      solo_defeat = solo_state(solo_map, category, other) == SOLO_DEFEAT,
      audition_active = audition_active({ src_track, dst_track }, "n"),
      audition_return_active = audition_active({ src_track, dst_track }, "ro"),
      write_volume = function(v) return write_send_volume(track, category, index, v) end,
      write_pan = function(v) return write_send_pan(track, category, index, v) end,
      write_mute = function(v) return write_send_mute(track, category, index, v) end,
      write_mode = function(v) return write_send_mode(track, category, index, v) end,
      write_phase = function(v) return write_send_phase(track, category, index, v) end,
      write_mono = function(v) return write_send_mono(track, category, index, v) end,
      write_srcchan = function(v) return write_send_srcchan(track, category, index, v) end,
      write_dstchan = function(v) return write_send_dstchan(track, category, index, v) end,
      write_midi_src = function(ch) return write_send_midi_src(track, category, index, ch) end,
      write_midi_dst = function(ch) return write_send_midi_dst(track, category, index, ch) end,
      toggle_solo = function(exclusive) return toggle_solo(track, category, other, false, exclusive ~= false) end,
      toggle_defeat = function() return toggle_solo(track, category, other, true, false) end,
      toggle_audition = function() return toggle_audition({ src_track, dst_track }, { owner = track, keep_category = category, keep_other = other }) end,
      toggle_audition_return = function() return toggle_audition({ src_track, dst_track }, { mute_master_track = src_track, owner = track, keep_category = category, keep_other = other }) end,
      select_other = function() return select_track(other) end,
      remove = function() return remove_send(track, category, index) end
    }
  end
  return rows
end

-- ---------------------------------------------------------------------------
-- Track picker for adding sends / receives
-- ---------------------------------------------------------------------------

local function guid_set(tracks)
  local set = {}
  for _, track in ipairs(tracks or {}) do
    local guid = track_guid(track)
    if guid then set[guid] = true end
  end
  return set
end

local function candidate_tracks(exclude_guids)
  exclude_guids = exclude_guids or {}
  local list = {}
  if not r.CountTracks or not r.GetTrack then return list end
  local depth = 0
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if valid_track(track) then
      local folder_delta = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")) or 0)
      local guid = track_guid(track)
      if not (guid and exclude_guids[guid]) then
        list[#list + 1] = {
          track = track,
          name = track_name(track),
          number = track_index_label(track),
          depth = depth,
          color = track_color(track)
        }
      end
      depth = math.max(0, depth + folder_delta)
    end
  end
  return list
end

-- All currently selected tracks (used when not pinned, for multi-track actions).
local function selected_track_list(app)
  local list = {}
  local count = r.CountSelectedTracks and r.CountSelectedTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    if valid_track(track) then list[#list + 1] = track end
  end
  return list
end

-- Create sends/receives from a set of source tracks to/from one other track.
local function apply_routes(app, settings, sources, other, mode)
  if not valid_track(other) or not r.CreateTrackSend then return false end
  local is_receive = mode == "receive"
  local created = false
  write_with_undo(is_receive and "Send Studio: Add receive" or "Send Studio: Add send", function()
    for _, track in ipairs(sources or {}) do
      local source = is_receive and other or track
      local destination = is_receive and track or other
      if valid_track(source) and valid_track(destination) and source ~= destination then
        local index = r.CreateTrackSend(source, destination)
        if index and index >= 0 then
          r.SetTrackSendInfo_Value(source, 0, index, "I_SENDMODE", tonumber(settings.default_send_mode) or 0)
          r.SetTrackSendInfo_Value(source, 0, index, "D_VOL", 1)
          r.SetTrackSendInfo_Value(source, 0, index, "B_MUTE", 0)
          created = true
        end
      end
    end
    return true
  end)
  return created
end

-- Copy all sends of a track into the module clipboard.
local function copy_sends(track)
  local clip = {}
  if not valid_track(track) or not r.GetTrackNumSends then return clip end
  for index = 0, (r.GetTrackNumSends(track, 0) or 0) - 1 do
    local dest = send_other_track(track, 0, index)
    if valid_track(dest) then
      clip[#clip + 1] = {
        dest_guid = track_guid(dest),
        vol = send_value(track, 0, index, "D_VOL") or 1,
        pan = send_value(track, 0, index, "D_PAN") or 0,
        mute = (send_value(track, 0, index, "B_MUTE") or 0) == 1,
        mode = math.floor(send_value(track, 0, index, "I_SENDMODE") or 0),
        phase = (send_value(track, 0, index, "B_PHASE") or 0) == 1,
        mono = (send_value(track, 0, index, "B_MONO") or 0) == 1,
        src_raw = math.floor(send_value(track, 0, index, "I_SRCCHAN") or 0),
        dst_raw = math.floor(send_value(track, 0, index, "I_DSTCHAN") or 0)
      }
    end
  end
  return clip
end

-- Paste clipboard sends onto a set of tracks.
local function paste_sends(sources, clip)
  if not clip or #clip == 0 or not r.CreateTrackSend then return false end
  local pasted = false
  write_with_undo("Send Studio: Paste sends", function()
    for _, track in ipairs(sources or {}) do
      if valid_track(track) then
        for _, entry in ipairs(clip) do
          local dest = track_by_guid(entry.dest_guid)
          if valid_track(dest) and dest ~= track then
            local index = r.CreateTrackSend(track, dest)
            if index and index >= 0 then
              r.SetTrackSendInfo_Value(track, 0, index, "D_VOL", entry.vol)
              r.SetTrackSendInfo_Value(track, 0, index, "D_PAN", entry.pan)
              r.SetTrackSendInfo_Value(track, 0, index, "B_MUTE", entry.mute and 1 or 0)
              r.SetTrackSendInfo_Value(track, 0, index, "I_SENDMODE", entry.mode)
              r.SetTrackSendInfo_Value(track, 0, index, "B_PHASE", entry.phase and 1 or 0)
              r.SetTrackSendInfo_Value(track, 0, index, "B_MONO", entry.mono and 1 or 0)
              r.SetTrackSendInfo_Value(track, 0, index, "I_SRCCHAN", entry.src_raw)
              r.SetTrackSendInfo_Value(track, 0, index, "I_DSTCHAN", entry.dst_raw)
              pasted = true
            end
          end
        end
      end
    end
    return true
  end)
  return pasted
end

-- Create a new bus track and send the given source tracks to it.
local function create_bus_and_send(app, settings, sources, name)
  if not r.InsertTrackAtIndex or not r.CountTracks or not r.GetTrack then return false end
  name = (name and name ~= "") and name or "FX Bus"
  return write_with_undo("Send Studio: New bus", function()
    local track_index = r.CountTracks(0) or 0
    r.InsertTrackAtIndex(track_index, true)
    local bus = r.GetTrack(0, track_index)
    if not valid_track(bus) then return false end
    if r.GetSetMediaTrackInfo_String then r.GetSetMediaTrackInfo_String(bus, "P_NAME", name, true) end
    for _, track in ipairs(sources or {}) do
      if valid_track(track) and track ~= bus then
        local index = r.CreateTrackSend(track, bus)
        if index and index >= 0 then
          r.SetTrackSendInfo_Value(track, 0, index, "I_SENDMODE", tonumber(settings.default_send_mode) or 0)
        end
      end
    end
    if r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(bus) end
    return true
  end)
end

-- Clear any active send-solo and audition, restoring saved states.
local function reset_all_listen(target)
  local did = false
  if state.audition then restore_audition(); did = true end
  if valid_track(target) and track_has_solo(target) then clear_solos(target); did = true end
  return did
end

local function open_picker(mode)
  state.picker_open = true
  state.picker_mode = mode
  state.picker_filter = ""
end

-- Favourite destination tracks (by GUID), stored per-project so they travel
-- with the project file instead of polluting the global settings.
local FAVORITES_EXT_SECTION = "TK_SEND_STUDIO"

local function load_favorites()
  local set = {}
  if not r.GetProjExtState then return set end
  local ok, _, value = pcall(r.GetProjExtState, 0, FAVORITES_EXT_SECTION, "favorites")
  if ok and type(value) == "string" and value ~= "" then
    for guid in value:gmatch("[^,]+") do set[guid] = true end
  end
  return set
end

local function save_favorites(set)
  if not r.SetProjExtState then return end
  local list = {}
  for guid in pairs(set) do list[#list + 1] = guid end
  pcall(r.SetProjExtState, 0, FAVORITES_EXT_SECTION, "favorites", table.concat(list, ","))
end

local function is_favorite(favset, guid)
  return guid ~= nil and type(favset) == "table" and favset[guid] == true
end

local function toggle_favorite(guid)
  if not guid then return end
  local set = load_favorites()
  set[guid] = (not set[guid]) or nil
  save_favorites(set)
end

local function draw_picker_popup(app, settings, target)
  local ctx = app.ctx
  local title = "Add Route##send_studio_picker"
  if state.picker_open then
    state.picker_open = false
    r.ImGui_OpenPopup(ctx, title)
  end
  -- Modal so a click on a track can never leak through to the panel behind it.
  local flags = r.ImGui_WindowFlags_AlwaysAutoResize and r.ImGui_WindowFlags_AlwaysAutoResize() or 0
  if not r.ImGui_BeginPopupModal or not r.ImGui_BeginPopupModal(ctx, title, true, flags) then return end
  local is_receive = state.picker_mode == "receive"
  local sources = (state.apply_tracks and #state.apply_tracks > 0) and state.apply_tracks or { target }
  r.ImGui_TextColored(ctx, Theme.colors.accent, is_receive and "Add receive from track" or "Add send to track")
  r.ImGui_SameLine(ctx)
  if #sources > 1 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, (is_receive and "for " or "from ") .. tostring(#sources) .. " selected tracks")
  elseif valid_track(target) then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "-> " .. ellipsize_text(ctx, track_name(target), UIScale.round(200)))
  end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(340))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##send_studio_picker_filter", "Filter tracks...", state.picker_filter or "")
  if changed then state.picker_filter = value end
  local filter = tostring(state.picker_filter or ""):lower()
  if r.ImGui_BeginChild(ctx, "##send_studio_picker_list", UIScale.round(340), UIScale.round(460)) then
    local candidates = candidate_tracks(guid_set(sources))
    local favset = load_favorites()
    -- Split into favourites (shown on top) and the rest, keeping project order.
    local favorites, others, shown = {}, {}, 0
    for _, item in ipairs(candidates) do
      local haystack = (item.number .. " " .. item.name):lower()
      if filter == "" or haystack:find(filter, 1, true) then
        shown = shown + 1
        if is_favorite(favset, track_guid(item.track)) then favorites[#favorites + 1] = item else others[#others + 1] = item end
      end
    end

    local function picker_row(item, indent)
      local guid = track_guid(item.track)
      r.ImGui_PushID(ctx, "pick_" .. tostring(guid or item.name))
      local fav = is_favorite(favset, guid)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), fav and Theme.colors.warning or Theme.colors.text_dim)
      if r.ImGui_SmallButton(ctx, "*##fav") and guid then toggle_favorite(guid); favset = load_favorites() end
      r.ImGui_PopStyleColor(ctx, 1)
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, fav and "Remove from favourites" or "Add to favourites") end
      r.ImGui_SameLine(ctx, 0, UIScale.round(6))
      if item.color then
        local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local h = r.ImGui_GetTextLineHeight(ctx)
        r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy + UIScale.round(2), cx + UIScale.round(4), cy + h - UIScale.round(1), item.color, UIScale.px(2))
      end
      r.ImGui_Dummy(ctx, UIScale.round(8) + (indent or 0), 1)
      r.ImGui_SameLine(ctx, 0, 0)
      local label = (item.number ~= "" and (item.number .. "  ") or "") .. item.name
      if r.ImGui_Selectable(ctx, label .. "##pick") then
        apply_routes(app, settings, sources, item.track, state.picker_mode)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_PopID(ctx)
    end

    if #favorites > 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Favourites")
      for _, item in ipairs(favorites) do picker_row(item, 0) end
      r.ImGui_Separator(ctx)
    end
    for _, item in ipairs(others) do picker_row(item, item.depth * UIScale.round(12)) end
    if shown == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No matching tracks") end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

-- Popup to name a new bus and send the active tracks to it.
local function draw_bus_popup(app, settings)
  local ctx = app.ctx
  local title = "New Bus##send_studio_bus"
  if state.bus_open then
    state.bus_open = false
    r.ImGui_OpenPopup(ctx, title)
  end
  -- Modal so clicking Create can never leak a click through to the panel behind it.
  local flags = r.ImGui_WindowFlags_AlwaysAutoResize and r.ImGui_WindowFlags_AlwaysAutoResize() or 0
  if not r.ImGui_BeginPopupModal or not r.ImGui_BeginPopupModal(ctx, title, true, flags) then return end
  local sources = (state.apply_tracks and #state.apply_tracks > 0) and state.apply_tracks or {}
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Create bus and send")
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, (#sources > 1 and tostring(#sources) .. " tracks" or "1 track") .. " will send to it")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(220))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##send_studio_bus_name", "Bus name", state.bus_name or "FX Bus")
  if changed then state.bus_name = value end
  local create = r.ImGui_Button(ctx, "Create##send_studio_bus_create", UIScale.text_button_w(ctx, "Create", 80, 8), 0)
  if r.ImGui_IsKeyPressed and r.ImGui_Key_Enter and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then create = true end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel##send_studio_bus_cancel", UIScale.text_button_w(ctx, "Cancel", 80, 8), 0) then r.ImGui_CloseCurrentPopup(ctx) end
  if create and #sources > 0 then
    create_bus_and_send(app, settings, sources, state.bus_name)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

-- ---------------------------------------------------------------------------
-- Card lane drawing (Control Room style)
-- ---------------------------------------------------------------------------

-- A compact text button drawn directly into the draw list (mixer-strip style).
local function strip_button(ctx, draw_list, x0, y0, x1, y1, label, active, active_color, mouse_x, mouse_y)
  local hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= y0 and mouse_y <= y1
  local bg = active and (active_color or Theme.colors.accent) or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, hovered and Theme.colors.text or Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  local text_color = Theme.text_for_background(bg, active and Theme.colors.badge_text or Theme.colors.text, Theme.colors.text, 3)
  local shown = ellipsize_text(ctx, label, (x1 - x0) - UIScale.round(3))
  local text_w = calc_text_width(ctx, shown)
  local text_h = r.ImGui_GetTextLineHeight(ctx)
  r.ImGui_DrawList_AddText(draw_list, (x0 + x1 - text_w) * 0.5, (y0 + y1 - text_h) * 0.5, text_color, shown)
  local clicked = hovered and r.ImGui_IsMouseClicked(ctx, 0)
  local right_clicked = hovered and r.ImGui_IsMouseClicked(ctx, 1)
  return clicked, hovered, right_clicked
end

-- A phase-invert icon button (circle with a slash) drawn into the draw list.
local function strip_phase_button(ctx, draw_list, x0, y0, x1, y1, active, mouse_x, mouse_y)
  local hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= y0 and mouse_y <= y1
  local bg = active and Theme.colors.warning or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, hovered and Theme.colors.text or Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  local glyph = Theme.text_for_background(bg, active and Theme.colors.badge_text or Theme.colors.text, Theme.colors.text, 3)
  local cx = (x0 + x1) * 0.5
  local cy = (y0 + y1) * 0.5
  local rad = math.min(x1 - x0, y1 - y0) * 0.28
  r.ImGui_DrawList_AddCircle(draw_list, cx, cy, rad, glyph, 16, UIScale.px(1.4))
  r.ImGui_DrawList_AddLine(draw_list, cx - rad * 0.95, cy + rad * 0.95, cx + rad * 0.95, cy - rad * 0.95, glyph, UIScale.px(1.4))
  local clicked = hovered and r.ImGui_IsMouseClicked(ctx, 0)
  return clicked, hovered
end

-- A mono/stereo icon button: one dot = mono (summed), two dots = stereo.
local function strip_mono_button(ctx, draw_list, x0, y0, x1, y1, mono, mouse_x, mouse_y)
  local hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= y0 and mouse_y <= y1
  local bg = mono and Theme.colors.accent or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, hovered and Theme.colors.text or Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  local glyph = Theme.text_for_background(bg, mono and Theme.colors.badge_text or Theme.colors.text, Theme.colors.text, 3)
  local cy = (y0 + y1) * 0.5
  local dot = UIScale.px(2)
  if mono then
    r.ImGui_DrawList_AddCircleFilled(draw_list, (x0 + x1) * 0.5, cy, dot, glyph, 12)
  else
    local cx = (x0 + x1) * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx - UIScale.round(4), cy, dot, glyph, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx + UIScale.round(4), cy, dot, glyph, 12)
  end
  local clicked = hovered and r.ImGui_IsMouseClicked(ctx, 0)
  return clicked, hovered
end

-- A headphone icon button (Listen): a headband arc + two ear cups.
-- active_color is the highlight colour when active, or nil when inactive.
local function strip_headphone_button(ctx, draw_list, x0, y0, x1, y1, active_color, mouse_x, mouse_y)
  local hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= y0 and mouse_y <= y1
  local active = active_color ~= nil
  local bg = active and active_color or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, hovered and Theme.colors.text or Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  local glyph = Theme.text_for_background(bg, active and Theme.colors.badge_text or Theme.colors.text, Theme.colors.text, 3)
  local cx = (x0 + x1) * 0.5
  local cy = (y0 + y1) * 0.5
  local rad = math.min(x1 - x0, y1 - y0) * 0.30
  local band_y = cy - rad * 0.25
  if r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathStroke then
    r.ImGui_DrawList_PathArcTo(draw_list, cx, band_y, rad, math.pi, 2 * math.pi, 16)
    r.ImGui_DrawList_PathStroke(draw_list, glyph, 0, UIScale.px(1.4))
  else
    r.ImGui_DrawList_AddLine(draw_list, cx - rad, band_y, cx + rad, band_y, glyph, UIScale.px(1.4))
  end
  local ear_w = UIScale.px(1.7)
  local ear_bottom = band_y + rad * 1.05
  r.ImGui_DrawList_AddRectFilled(draw_list, cx - rad - ear_w, band_y, cx - rad + ear_w, ear_bottom, glyph, UIScale.px(1.5))
  r.ImGui_DrawList_AddRectFilled(draw_list, cx + rad - ear_w, band_y, cx + rad + ear_w, ear_bottom, glyph, UIScale.px(1.5))
  local clicked = hovered and r.ImGui_IsMouseClicked(ctx, 0)
  return clicked, hovered
end

-- FX chain of a send/receive's other track: view the plugins and open them.
local function track_fx_count(track)
  if not valid_track(track) or not r.TrackFX_GetCount then return 0 end
  local ok, count = pcall(r.TrackFX_GetCount, track)
  return ok and (count or 0) or 0
end

local function track_fx_name(track, index)
  if not valid_track(track) or not r.TrackFX_GetFXName then return "FX " .. tostring(index + 1) end
  local ok, _, name = pcall(r.TrackFX_GetFXName, track, index, "")
  if ok and type(name) == "string" and name ~= "" then return name end
  return "FX " .. tostring(index + 1)
end

local function open_track_fx_chain(track)
  if valid_track(track) and r.TrackFX_Show then pcall(r.TrackFX_Show, track, 0, 1) end
end

local function open_track_fx(track, index)
  if valid_track(track) and r.TrackFX_Show then pcall(r.TrackFX_Show, track, index, 3) end
end

local function draw_fx_menu(ctx, other)
  if not valid_track(other) then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Track missing"); return end
  local count = track_fx_count(other)
  if count == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No FX on this track"); return end
  if r.ImGui_Selectable(ctx, "Open FX chain") then open_track_fx_chain(other) end
  r.ImGui_Separator(ctx)
  for index = 0, count - 1 do
    if r.ImGui_Selectable(ctx, ellipsize_text(ctx, track_fx_name(other, index), UIScale.round(240)) .. "##fx" .. tostring(index)) then open_track_fx(other, index) end
  end
end

local function draw_lane_fx_popup(ctx, other, popup_id)
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, popup_id) then return end
  draw_fx_menu(ctx, other)
  r.ImGui_EndPopup(ctx)
end

-- Extra ("Alt-click") functions for a lane: return-only listen, solo defeat and
-- the destination (return) track's own volume/pan.
local function draw_lane_extras(ctx, lane, settings)
  local other = lane.other
  if not valid_track(other) then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Track missing"); return end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Return track")
  local min_db, max_db = settings.min_db, settings.max_db
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  local vch, vdb = r.ImGui_SliderDouble(ctx, "Vol##ret_vol", linear_to_db(read_track_own_volume(other), min_db), min_db, max_db, "%.1f dB")
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then write_track_own_volume(other, 1)
  elseif vch then write_track_own_volume(other, db_to_linear(vdb, min_db, max_db)) end
  local rpan = read_track_own_pan(other)
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  local pch, pval = r.ImGui_SliderDouble(ctx, "Pan##ret_pan", rpan, -1, 1, format_pan(rpan))
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then write_track_own_pan(other, 0)
  elseif pch then write_track_own_pan(other, pval) end
end

local function draw_lane_extras_popup(app, lane, settings, popup_id)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, popup_id) then return end
  draw_lane_extras(ctx, lane, settings)
  r.ImGui_EndPopup(ctx)
end

-- Popup with source + destination audio channel pickers for one send/receive.
local function draw_channel_popup(app, lane, popup_id)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, popup_id) then return end
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Audio routing")
  local label_w = UIScale.round(78)
  local combo_w = UIScale.round(150)

  local function channel_combo(id, current_raw, track, include_midi, writer)
    local track_count = track_channel_count(track)
    if r.ImGui_BeginCombo(ctx, id, chan_label(current_raw)) then
      for _, option in ipairs(channel_options(track, include_midi)) do
        local label = option.label
        if option.needs and option.needs > track_count then label = label .. "  (add)" end
        if r.ImGui_Selectable(ctx, label, option.value == math.floor(current_raw)) then
          ensure_track_channels(track, option.needs)
          writer(option.value)
        end
      end
      r.ImGui_EndCombo(ctx)
    end
  end

  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Source")
  r.ImGui_SameLine(ctx, label_w)
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  channel_combo("##send_studio_srcchan", lane.src_raw, lane.src_track, true, lane.write_srcchan)

  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Destination")
  r.ImGui_SameLine(ctx, label_w)
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  channel_combo("##send_studio_dstchan", lane.dst_raw, lane.dst_track, false, lane.write_dstchan)

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "MIDI routing")
  local function midi_combo(id, current, none_label, writer)
    local label = current == 0 and none_label or ("Ch " .. tostring(current))
    if r.ImGui_BeginCombo(ctx, id, label) then
      if r.ImGui_Selectable(ctx, none_label, current == 0) then writer(0) end
      for ch = 1, 16 do
        if r.ImGui_Selectable(ctx, "Ch " .. tostring(ch), current == ch) then writer(ch) end
      end
      r.ImGui_EndCombo(ctx)
    end
  end
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Source")
  r.ImGui_SameLine(ctx, label_w)
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  midi_combo("##send_studio_midisrc", midi_src_channel(lane.midi_flags), "All channels", lane.write_midi_src)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Destination")
  r.ImGui_SameLine(ctx, label_w)
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  midi_combo("##send_studio_mididst", midi_dst_channel(lane.midi_flags), "Source channel", lane.write_midi_dst)
  r.ImGui_EndPopup(ctx)
end

local function draw_strip(app, lane, settings, width, height)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local enabled = lane.enabled == true
  r.ImGui_PushID(ctx, lane.id)
  local left_x, top_y = r.ImGui_GetCursorScreenPos(ctx)
  -- One InvisibleButton spans the whole strip so ImGui does the hit-testing and
  -- input capture; we route clicks/drags to the sub-controls by mouse position.
  r.ImGui_InvisibleButton(ctx, "##strip", width, height)
  local strip_hovered = r.ImGui_IsItemHovered(ctx) == true
  local strip_active = r.ImGui_IsItemActive(ctx) == true
  if r.ImGui_BeginPopupContextItem and r.ImGui_BeginPopupContextItem(ctx, "##send_studio_strip_menu") then
    -- Only extras that are not already directly on the strip (mode/phase/mono
    -- buttons, name-click to select the track, etc. stay in the GUI itself).
    draw_lane_extras(ctx, lane, settings)
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginMenu and r.ImGui_BeginMenu(ctx, "FX (" .. tostring(track_fx_count(lane.other)) .. ")") then
      draw_fx_menu(ctx, lane.other)
      r.ImGui_EndMenu(ctx)
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_Selectable(ctx, lane.category == -1 and "Remove receive" or "Remove send") then lane.remove() end
    r.ImGui_EndPopup(ctx)
  end
  local right_x = left_x + width
  local bottom_y = top_y + height
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local hovered = strip_hovered

  -- ImGui owns hit-testing via the InvisibleButton above, so clicks only count
  -- when the strip is genuinely hovered (this respects window focus, open
  -- popups and item overlap) and a drag only continues while that button stays
  -- active. This removes the global-mouse fragility that could freeze the
  -- fader on some ReaImGui/REAPER setups.
  local interact = enabled and strip_hovered

  -- Strip background (darker than the buttons for contrast)
  local corner = UIScale.px(5)
  r.ImGui_DrawList_AddRectFilled(draw_list, left_x, top_y, right_x, bottom_y, Theme.colors.child_bg, corner)
  r.ImGui_DrawList_AddRect(draw_list, left_x, top_y, right_x, bottom_y, enabled and Theme.colors.border or 0xFFFFFF22, corner, 0, hovered and UIScale.px(1.3) or UIScale.px(0.8))

  local pad = UIScale.round(4)
  local gap = UIScale.round(3)
  local x0 = left_x + pad
  local x1 = right_x - pad
  local mid_x = (x0 + x1) * 0.5
  local button_h = UIScale.round(15)

  local third = (x1 - x0) / 3
  local col1a, col1b = x0 + third - UIScale.px(1), x0 + third + UIScale.px(1)
  local col2a, col2b = x0 + 2 * third - UIScale.px(1), x0 + 2 * third + UIScale.px(1)

  -- Row 1: Mute / Solo send / Solo defeat (return track)
  local r1t = top_y + pad
  local r1b = r1t + button_h
  local mute_clicked, mute_hov = strip_button(ctx, draw_list, x0, r1t, col1a, r1b, "M", lane.muted, Theme.colors.warning, mouse_x, mouse_y)
  if mute_clicked and interact then lane.write_mute(not lane.muted) end
  local solo_clicked, solo_hov = strip_button(ctx, draw_list, col1b, r1t, col2a, r1b, "S", lane.solo_on or lane.audition_active or lane.audition_return_active, Theme.colors.accent, mouse_x, mouse_y)
  if solo_clicked and interact then lane.toggle_solo(not ctrl_down(ctx)) end
  local defeat_clicked, defeat_hov = strip_button(ctx, draw_list, col2b, r1t, x1, r1b, "D", lane.solo_defeat, Theme.colors.warning, mouse_x, mouse_y)
  if defeat_clicked and interact then lane.toggle_defeat() end
  if mute_hov then r.ImGui_SetTooltip(ctx, lane.muted and "Unmute send" or "Mute send")
  elseif solo_hov then r.ImGui_SetTooltip(ctx, (lane.category == -1 and "Solo receive" or "Solo send") .. ": isolate this routing (Ctrl-click to add to the solo)")
  elseif defeat_hov then r.ImGui_SetTooltip(ctx, lane.solo_defeat and "Solo defeat on: stays audible while a solo is active" or "Solo defeat: keep this routing audible while another is soloed") end

  -- Row 2: Listen (headphone) / Phase / Mono
  local r2t = r1b + gap
  local r2b = r2t + button_h
  local listen_color = lane.audition_active and Theme.colors.accent or (lane.audition_return_active and Theme.colors.warning or nil)
  local listen_clicked, listen_hov = strip_headphone_button(ctx, draw_list, x0, r2t, col1a, r2b, listen_color, mouse_x, mouse_y)
  if listen_clicked and interact then
    if shift_key_down(ctx) then lane.toggle_audition_return() else lane.toggle_audition() end
  end
  local phase_clicked, phase_hov = strip_phase_button(ctx, draw_list, col1b, r2t, col2a, r2b, lane.phase, mouse_x, mouse_y)
  if phase_clicked and interact then lane.write_phase(not lane.phase) end
  local mono_clicked, mono_hov = strip_mono_button(ctx, draw_list, col2b, r2t, x1, r2b, lane.mono, mouse_x, mouse_y)
  if mono_clicked and interact then lane.write_mono(not lane.mono) end
  if listen_hov then r.ImGui_SetTooltip(ctx, "Listen: solo original + return\nShift-click: return only")
  elseif phase_hov then r.ImGui_SetTooltip(ctx, lane.phase and "Phase inverted" or "Invert phase")
  elseif mono_hov then r.ImGui_SetTooltip(ctx, lane.mono and "Mono sum (on)" or "Sum to mono") end

  -- Row 3: Send mode (full label)
  local r3t = r2b + gap
  local r3b = r3t + button_h
  local mode_clicked, mode_hov = strip_button(ctx, draw_list, x0, r3t, x1, r3b, send_mode_label(lane.mode), false, nil, mouse_x, mouse_y)
  if mode_clicked and interact then lane.write_mode(next_send_mode(lane.mode)) end
  if mode_hov then r.ImGui_SetTooltip(ctx, "Send mode (click to cycle)") end

  -- Row 4: Audio channel routing (source -> destination)
  local r4t = r3b + gap
  local r4b = r4t + button_h
  local chan_text = chan_label(lane.src_raw) .. " > " .. chan_label(lane.dst_raw)
  local chan_clicked, chan_hov = strip_button(ctx, draw_list, x0, r4t, x1, r4b, chan_text, false, nil, mouse_x, mouse_y)
  if chan_clicked and interact then r.ImGui_OpenPopup(ctx, "##send_studio_chan") end
  if chan_hov then r.ImGui_SetTooltip(ctx, "Source > destination audio channel") end

  -- Name label (colour of destination track) at the bottom
  local name_h = UIScale.round(16)
  local name_y1 = bottom_y - pad
  local name_y0 = name_y1 - name_h
  local name_bg = enabled and (lane.handle_color or Theme.colors.accent) or Theme.colors.frame_bg
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, name_y0, x1, name_y1, name_bg, UIScale.px(3))
  local name_text_color = Theme.text_for_background(name_bg, Theme.colors.badge_text, Theme.colors.text, 3)
  local name_label = ellipsize_text(ctx, lane.label, x1 - x0 - UIScale.round(4))
  local name_text_w = calc_text_width(ctx, name_label)
  local name_text_h = r.ImGui_GetTextLineHeight(ctx)
  r.ImGui_DrawList_AddText(draw_list, (x0 + x1 - name_text_w) * 0.5, (name_y0 + name_y1 - name_text_h) * 0.5, name_text_color, name_label)
  local name_hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= name_y0 and mouse_y <= name_y1
  if name_hovered and interact and r.ImGui_IsMouseClicked(ctx, 0) then lane.select_other() end

  -- dB value above the name label, flanked by -1 dB / +1 dB nudge buttons
  local value_text = enabled and format_db(lane.value, settings) or "--"
  local value_h = r.ImGui_GetTextLineHeight(ctx)
  local value_y = name_y0 - UIScale.round(3) - value_h
  local value_w = calc_text_width(ctx, value_text)
  if enabled then
    local step_w = UIScale.round(16)
    local step_y0 = value_y - UIScale.round(1)
    local step_y1 = value_y + value_h + UIScale.round(2)
    local minus_clicked, minus_hov = strip_button(ctx, draw_list, x0, step_y0, x0 + step_w, step_y1, "-", false, nil, mouse_x, mouse_y)
    local plus_clicked, plus_hov = strip_button(ctx, draw_list, x1 - step_w, step_y0, x1, step_y1, "+", false, nil, mouse_x, mouse_y)
    if interact then
      local cur_db = linear_to_db(lane.value, settings.min_db)
      if minus_clicked then lane.write_volume(db_to_linear(clamp(cur_db - 1, settings.min_db, settings.max_db), settings.min_db, settings.max_db)) end
      if plus_clicked then lane.write_volume(db_to_linear(clamp(cur_db + 1, settings.min_db, settings.max_db), settings.min_db, settings.max_db)) end
    end
    if minus_hov then r.ImGui_SetTooltip(ctx, "-1 dB")
    elseif plus_hov then r.ImGui_SetTooltip(ctx, "+1 dB") end
  end
  r.ImGui_DrawList_AddText(draw_list, (x0 + x1 - value_w) * 0.5, value_y, enabled and Theme.colors.text or Theme.colors.text_dim, value_text)

  -- Pan strip below the button cluster
  local pan_y = r4b + gap + UIScale.round(7)
  local pan_left = x0 + UIScale.round(2)
  local pan_right = x1 - UIScale.round(2)
  local pan_range = math.max(1, pan_right - pan_left)
  local pan_mid = (pan_left + pan_right) * 0.5
  r.ImGui_DrawList_AddLine(draw_list, pan_left, pan_y, pan_right, pan_y, 0xFFFFFF22, UIScale.px(2))
  r.ImGui_DrawList_AddLine(draw_list, pan_mid, pan_y - UIScale.round(3), pan_mid, pan_y + UIScale.round(3), Theme.colors.border, UIScale.px(1))
  local pan_dot_x = pan_mid + (tonumber(lane.pan) or 0) * (pan_range * 0.5)
  if enabled then r.ImGui_DrawList_AddLine(draw_list, pan_mid, pan_y, pan_dot_x, pan_y, Theme.colors.accent, UIScale.px(2)) end
  r.ImGui_DrawList_AddCircleFilled(draw_list, pan_dot_x, pan_y, UIScale.px(3.5), enabled and (lane.handle_color or Theme.colors.accent) or Theme.colors.border, 16)
  local pan_hovered = enabled and mouse_x >= pan_left - UIScale.round(4) and mouse_x <= pan_right + UIScale.round(4) and mouse_y >= pan_y - UIScale.round(7) and mouse_y <= pan_y + UIScale.round(7)
  if pan_hovered and interact and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    lane.write_pan(0)
    state.drag = nil
  elseif pan_hovered and interact and r.ImGui_IsMouseClicked(ctx, 0) then
    state.drag = { id = lane.id, kind = "pan" }
  end
  if strip_active and state.drag and state.drag.id == lane.id and state.drag.kind == "pan" then
    lane.write_pan(clamp((mouse_x - pan_mid) / (pan_range * 0.5), -1, 1))
  end

  -- Vertical fader between pan strip and the dB value
  local fader_top = pan_y + UIScale.round(12)
  local fader_bottom = value_y - UIScale.round(6)
  if fader_bottom > fader_top + UIScale.round(20) then
    local groove_w = UIScale.round(6)
    local groove_x = (x0 + x1) * 0.5
    local range = math.max(1, fader_bottom - fader_top)
    local current_db = linear_to_db(lane.value, settings.min_db)
    local normalized = clamp((current_db - settings.min_db) / (settings.max_db - settings.min_db), 0, 1)
    local thumb_y = fader_bottom - normalized * range
    r.ImGui_DrawList_AddRectFilled(draw_list, groove_x - groove_w * 0.5, fader_top, groove_x + groove_w * 0.5, fader_bottom, 0x00000055, UIScale.px(3))
    if enabled then r.ImGui_DrawList_AddRectFilled(draw_list, groove_x - groove_w * 0.5, thumb_y, groove_x + groove_w * 0.5, fader_bottom, Theme.colors.accent_soft, UIScale.px(3)) end
    local zero_normalized = clamp((0 - settings.min_db) / (settings.max_db - settings.min_db), 0, 1)
    local zero_y = fader_bottom - zero_normalized * range
    local handle_half = math.min(UIScale.round(16), (x1 - x0) * 0.5 - UIScale.round(2))
    r.ImGui_DrawList_AddLine(draw_list, groove_x - handle_half, zero_y, groove_x + handle_half, zero_y, Theme.colors.border, UIScale.px(1))
    -- Compact handle centred on the groove (like Control Room)
    local handle_color = enabled and (lane.handle_color or Theme.colors.accent) or Theme.colors.border
    local handle_left = groove_x - handle_half
    local handle_right = groove_x + handle_half
    r.ImGui_DrawList_AddRectFilled(draw_list, handle_left, thumb_y - UIScale.round(5), handle_right, thumb_y + UIScale.round(5), handle_color, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, handle_left, thumb_y - UIScale.round(5), handle_right, thumb_y + UIScale.round(5), 0x00000066, UIScale.px(3), 0, UIScale.px(1))
    local handle_hovered = enabled and mouse_x >= handle_left and mouse_x <= handle_right and mouse_y >= thumb_y - UIScale.round(8) and mouse_y <= thumb_y + UIScale.round(8)
    local fader_hovered = enabled and mouse_x >= x0 and mouse_x <= x1 and mouse_y >= fader_top - UIScale.round(4) and mouse_y <= fader_bottom + UIScale.round(4)
    if handle_hovered and interact and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      lane.write_volume(1)
      state.drag = nil
    elseif fader_hovered and interact and r.ImGui_IsMouseClicked(ctx, 0) and not pan_hovered then
      state.drag = { id = lane.id, kind = "vol" }
    end
    local wheel = fader_hovered and strip_hovered and shift_key_down(ctx) and mouse_wheel_delta(ctx) or 0
    if enabled and math.abs(wheel) > 0.0001 then
      lane.write_volume(db_to_linear(clamp(current_db + wheel * 0.1, settings.min_db, settings.max_db), settings.min_db, settings.max_db))
    end
    if strip_active and state.drag and state.drag.id == lane.id and state.drag.kind == "vol" then
      local next_normalized = clamp((fader_bottom - mouse_y) / range, 0, 1)
      lane.write_volume(db_to_linear(settings.min_db + next_normalized * (settings.max_db - settings.min_db), settings.min_db, settings.max_db))
    end
    if handle_hovered then r.ImGui_SetTooltip(ctx, "Drag: volume | Shift+scroll: fine | Double-click: 0 dB") end
  end

  -- Release drag when ImGui reports the strip is no longer being held
  if not strip_active and state.drag and state.drag.id == lane.id then state.drag = nil end

  if not enabled and hovered then r.ImGui_SetTooltip(ctx, "Destination track missing") end
  draw_channel_popup(app, lane, "##send_studio_chan")
  r.ImGui_PopID(ctx)
end

-- ---------------------------------------------------------------------------
-- List row drawing (compact)
-- ---------------------------------------------------------------------------

local function push_slider_theme(ctx)
  -- Use the muted accent for the grab: ImGui draws the value text on top of the
  -- grab, and accent_soft contrasts with the theme text colour in every preset,
  -- so the readout stays legible even when the handle sits over it.
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000044)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.accent_soft)
  return 3
end

-- Shift+wheel fine-adjust for a native slider (call right after the slider,
-- while it is the current item). Returns the new value or nil when unchanged.
local function slider_wheel_delta(ctx, current, step, minimum, maximum)
  if not r.ImGui_IsItemHovered(ctx) or not shift_key_down(ctx) then return nil end
  local wheel = mouse_wheel_delta(ctx)
  if math.abs(wheel) < 0.0001 then return nil end
  return clamp(current + wheel * step, minimum, maximum)
end

local function draw_list_row(app, lane, settings)
  local ctx = app.ctx
  local enabled = lane.enabled == true
  r.ImGui_PushID(ctx, lane.id)

  local gap = UIScale.round(8)
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local ok, sx = pcall(r.ImGui_GetStyleVar, ctx, r.ImGui_StyleVar_ItemSpacing())
    if ok and sx then gap = sx end
  end
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local swatch_w = UIScale.round(10)

  -- Line 1: colour swatch + track name, filling the row width
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local line_h = r.ImGui_GetFrameHeight(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy + UIScale.round(3), cx + UIScale.round(4), cy + line_h - UIScale.round(3), lane.handle_color or Theme.colors.border, UIScale.px(2))
  r.ImGui_Dummy(ctx, swatch_w, line_h)
  r.ImGui_SameLine(ctx, 0, 0)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, enabled and Theme.colors.text or Theme.colors.text_dim, ellipsize_text(ctx, lane.label, math.max(UIScale.round(40), avail - swatch_w - UIScale.round(6))))
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, lane.label) end

  -- Control widths for the wrapping flow below (buttons fixed, sliders capped to the pane)
  local mute_w = UIScale.text_button_w(ctx, "M", 30, 6)
  local toggle_w = UIScale.text_button_w(ctx, "S", 26, 6)
  local mode_w = UIScale.text_button_w(ctx, "Pre-Fader", 74, 6)
  local chan_w = UIScale.text_button_w(ctx, "MIDI > Mono 1", 90, 6)
  local fx_w = UIScale.text_button_w(ctx, "FX", 30, 6)
  local more_w = UIScale.text_button_w(ctx, "...", 26, 6)
  local rm_w = UIScale.text_button_w(ctx, "x", 26, 6)
  local vol_w = math.min(UIScale.round(150), avail)
  local pan_w = math.min(UIScale.round(110), avail)

  local function toggle_button(label, active, action, tip, active_color)
    active_color = active_color or Theme.colors.accent
    if active then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), active_color)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), active_color)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(active_color, nil, nil, 4.5))
    end
    if r.ImGui_Button(ctx, label, toggle_w, 0) and enabled then action() end
    if active then r.ImGui_PopStyleColor(ctx, 3) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tip) end
  end

  local items = {}
  items[#items + 1] = { w = mute_w, draw = function()
    if lane.muted then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.warning, nil, nil, 4.5))
    end
    if r.ImGui_Button(ctx, "M##mute", mute_w, 0) and enabled then lane.write_mute(not lane.muted) end
    if lane.muted then r.ImGui_PopStyleColor(ctx, 3) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, lane.muted and "Unmute" or "Mute") end
  end }
  items[#items + 1] = { w = toggle_w, draw = function() toggle_button("S##solo", lane.solo_on or lane.audition_active or lane.audition_return_active, function() lane.toggle_solo(not ctrl_down(ctx)) end, (lane.category == -1 and "Solo receive" or "Solo send") .. ": isolate this routing (Ctrl-click to add)") end }
  items[#items + 1] = { w = toggle_w, draw = function() toggle_button("L##listen", lane.audition_active or lane.audition_return_active, function() if shift_key_down(ctx) then lane.toggle_audition_return() else lane.toggle_audition() end end, "Listen: solo original + return (Shift-click: return only)", lane.audition_return_active and Theme.colors.warning or Theme.colors.accent) end }
  items[#items + 1] = { w = toggle_w, draw = function() toggle_button("D##defeat", lane.solo_defeat, lane.toggle_defeat, "Solo defeat: keep this routing audible while another is soloed") end }
  local step_w = UIScale.text_button_w(ctx, "-", 22, 6)
  local function nudge_volume(delta)
    local cur = linear_to_db(lane.value, settings.min_db)
    lane.write_volume(db_to_linear(clamp(cur + delta, settings.min_db, settings.max_db), settings.min_db, settings.max_db))
  end
  items[#items + 1] = { w = step_w, draw = function()
    if r.ImGui_Button(ctx, "-##voldn", step_w, 0) and enabled then nudge_volume(-1) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "-1 dB") end
  end }
  items[#items + 1] = { w = vol_w, draw = function()
    local shown_db = linear_to_db(lane.value, settings.min_db)
    r.ImGui_SetNextItemWidth(ctx, vol_w)
    local sc = push_slider_theme(ctx)
    local changed, nd = r.ImGui_SliderDouble(ctx, "##vol", shown_db, settings.min_db, settings.max_db, "%.1f dB")
    r.ImGui_PopStyleColor(ctx, sc)
    local applied = false
    if r.ImGui_IsItemHovered(ctx) then
      if r.ImGui_IsMouseClicked(ctx, 1) then lane.write_volume(1); applied = true
      else
        local wd = slider_wheel_delta(ctx, shown_db, 0.1, settings.min_db, settings.max_db)
        if wd then lane.write_volume(db_to_linear(wd, settings.min_db, settings.max_db)); applied = true end
      end
      r.ImGui_SetTooltip(ctx, "Drag | Shift+wheel: fine | Right-click: 0 dB")
    end
    if not applied and changed then lane.write_volume(db_to_linear(nd, settings.min_db, settings.max_db)) end
  end }
  items[#items + 1] = { w = step_w, draw = function()
    if r.ImGui_Button(ctx, "+##volup", step_w, 0) and enabled then nudge_volume(1) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "+1 dB") end
  end }
  items[#items + 1] = { w = pan_w, draw = function()
    local shown_pan = tonumber(lane.pan) or 0
    r.ImGui_SetNextItemWidth(ctx, pan_w)
    local sc = push_slider_theme(ctx)
    local changed, np = r.ImGui_SliderDouble(ctx, "##pan", shown_pan, -1, 1, format_pan(lane.pan))
    r.ImGui_PopStyleColor(ctx, sc)
    local applied = false
    if r.ImGui_IsItemHovered(ctx) then
      if r.ImGui_IsMouseClicked(ctx, 1) then lane.write_pan(0); applied = true
      else
        local wp = slider_wheel_delta(ctx, shown_pan, 0.02, -1, 1)
        if wp then lane.write_pan(wp); applied = true end
      end
      r.ImGui_SetTooltip(ctx, "Drag | Shift+wheel: fine | Right-click: center")
    end
    if not applied and changed then lane.write_pan(np) end
  end }
  items[#items + 1] = { w = mode_w, draw = function()
    if r.ImGui_Button(ctx, send_mode_label(lane.mode) .. "##mode", mode_w, 0) then lane.write_mode(next_send_mode(lane.mode)) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Send mode (click to cycle)") end
  end }
  items[#items + 1] = { w = chan_w, draw = function()
    local chan_text = chan_label(lane.src_raw) .. " > " .. chan_label(lane.dst_raw)
    if r.ImGui_Button(ctx, chan_text .. "##chan", chan_w, 0) then r.ImGui_OpenPopup(ctx, "##send_studio_chan") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Source > destination audio channel") end
  end }
  items[#items + 1] = { w = fx_w, draw = function()
    if r.ImGui_Button(ctx, "FX##fx", fx_w, 0) then r.ImGui_OpenPopup(ctx, "##send_studio_fx") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "View / open the FX on " .. lane.label) end
  end }
  items[#items + 1] = { w = more_w, draw = function()
    if r.ImGui_Button(ctx, "...##more", more_w, 0) then r.ImGui_OpenPopup(ctx, "##send_studio_more") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Return track volume / pan") end
  end }
  items[#items + 1] = { w = rm_w, draw = function()
    if r.ImGui_Button(ctx, "x##remove", rm_w, 0) then lane.remove() end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, lane.category == -1 and "Remove receive" or "Remove send") end
  end }

  -- Flow the controls and wrap to the next line when the next one won't fit.
  local start_x = r.ImGui_GetCursorScreenPos(ctx)
  local visible_x2 = start_x + r.ImGui_GetContentRegionAvail(ctx)
  for i, item in ipairs(items) do
    item.draw()
    if i < #items then
      local last_x2 = select(1, r.ImGui_GetItemRectMax(ctx))
      if last_x2 + gap + items[i + 1].w < visible_x2 then r.ImGui_SameLine(ctx, 0, gap) end
    end
  end
  draw_channel_popup(app, lane, "##send_studio_chan")
  draw_lane_fx_popup(ctx, lane.other, "##send_studio_fx")
  draw_lane_extras_popup(app, lane, settings, "##send_studio_more")

  r.ImGui_Separator(ctx)
  r.ImGui_PopID(ctx)
end

-- ---------------------------------------------------------------------------
-- Section drawing
-- ---------------------------------------------------------------------------

local STRIP_MIN_WIDTH = 88
local STRIP_MAX_WIDTH = 200
local STRIP_HEIGHT = 242

-- Column-major layout: fill a column top-to-bottom (using the visible body
-- height) before starting the next column, so a tall narrow docker fills
-- vertically first instead of leaving empty space below a single row.
-- Strips grow with the window up to STRIP_MAX_WIDTH, then stop widening.
local function draw_section_strips(app, settings, rows, column_height)
  local ctx = app.ctx
  local avail_width = r.ImGui_GetContentRegionAvail(ctx)
  local spacing = UIScale.round(6)
  local min_w = UIScale.round(STRIP_MIN_WIDTH)
  local max_w = UIScale.round(STRIP_MAX_WIDTH)
  local strip_h = UIScale.round(STRIP_HEIGHT)

  -- Row-major: fill a row left-to-right, then wrap to the next row (classic grid).
  if settings.card_flow == "rows" then
    local columns = math.min(#rows, math.max(1, math.floor((avail_width + spacing) / (min_w + spacing))))
    local strip_w = math.min(max_w, math.max(min_w, (avail_width - spacing * (columns - 1)) / columns))
    for index, lane in ipairs(rows) do
      draw_strip(app, lane, settings, strip_w, strip_h)
      if index % columns ~= 0 and index < #rows then r.ImGui_SameLine(ctx, 0, spacing) end
    end
    return
  end

  -- Column-major: how many strips fit in one column (based on the visible
  -- height), how many columns the width allows, then balance over the columns.
  local usable_h = math.max(strip_h, (tonumber(column_height) or strip_h * 2) - UIScale.round(28))
  local rows_per_col = math.max(1, math.floor((usable_h + spacing) / (strip_h + spacing)))
  local max_cols = math.max(1, math.floor((avail_width + spacing) / (min_w + spacing)))
  local columns = math.max(1, math.min(math.ceil(#rows / rows_per_col), max_cols))
  rows_per_col = math.ceil(#rows / columns)
  local strip_w = math.min(max_w, math.max(min_w, (avail_width - spacing * (columns - 1)) / columns))

  local origin_x, origin_y = r.ImGui_GetCursorPos(ctx)
  for index, lane in ipairs(rows) do
    local col = math.floor((index - 1) / rows_per_col)
    local row = (index - 1) % rows_per_col
    r.ImGui_SetCursorPos(ctx, origin_x + col * (strip_w + spacing), origin_y + row * (strip_h + spacing))
    draw_strip(app, lane, settings, strip_w, strip_h)
  end
  -- Move below the tallest (first) column so the following content lines up.
  r.ImGui_SetCursorPos(ctx, origin_x, origin_y + math.min(rows_per_col, #rows) * (strip_h + spacing))
end

local function draw_section_list(app, settings, rows)
  for _, lane in ipairs(rows) do
    draw_list_row(app, lane, settings)
  end
end

local function draw_section(app, settings, title, rows, add_mode, column_height)
  local ctx = app.ctx
  r.ImGui_TextColored(ctx, Theme.colors.accent, title)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "(" .. tostring(#rows) .. ")")
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "+ Add##add_" .. add_mode) then open_picker(add_mode) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, add_mode == "receive" and "Add a receive from another track" or "Add a send to another track") end
  if #rows == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, add_mode == "receive" and "No receives on this track." or "No sends on this track.")
  elseif settings.view_mode == "list" then
    draw_section_list(app, settings, rows)
  else
    draw_section_strips(app, settings, rows, column_height)
  end
  r.ImGui_Dummy(ctx, 1, UIScale.round(6))
end

-- ---------------------------------------------------------------------------
-- Header + footer
-- ---------------------------------------------------------------------------

-- A small triangle navigation button; returns clicked, hovered.
local function header_arrow(ctx, id, dir, w, h)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if hovered then r.ImGui_DrawList_AddRectFilled(dl, cx, cy, cx + w, cy + h, Theme.colors.frame_hover, UIScale.px(3)) end
  local col = hovered and Theme.colors.text or Theme.colors.text_dim
  local mx, my = cx + w * 0.5, cy + h * 0.5
  local aw, ah = w * 0.24, h * 0.28
  if dir == "left" then
    r.ImGui_DrawList_AddTriangleFilled(dl, mx + aw, my - ah, mx + aw, my + ah, mx - aw, my, col)
  else
    r.ImGui_DrawList_AddTriangleFilled(dl, mx - aw, my - ah, mx - aw, my + ah, mx + aw, my, col)
  end
  return clicked, hovered
end

-- Move the target to another project track (cyclic, or "first"/"last").
local function navigate_track(app, settings, target, pinned, where)
  if not r.CountTracks or not r.GetTrack then return end
  local count = r.CountTracks(0) or 0
  if count == 0 then return end
  local idx = 1
  for i = 0, count - 1 do
    if r.GetTrack(0, i) == target then idx = i + 1; break end
  end
  local new_idx
  if where == "first" then new_idx = 1
  elseif where == "last" then new_idx = count
  else new_idx = ((idx - 1 + where) % count) + 1 end
  local new_track = r.GetTrack(0, new_idx - 1)
  if not valid_track(new_track) then return end
  if pinned then set_pin(app, settings, new_track) end
  select_track(new_track)
end

local function draw_header(app, settings, target, pinned, source_count)
  local ctx = app.ctx
  local gap = UIScale.round(8)
  local pin_label = pinned and "Pinned" or "Pin"
  local pin_w = UIScale.text_button_w(ctx, "Pinned", 64, 8)
  local show_badge = (not pinned) and (source_count or 0) > 1
  local badge_text = show_badge and ("+" .. tostring(source_count - 1)) or nil

  r.ImGui_AlignTextToFramePadding(ctx)
  if valid_track(target) then
    local number = track_index_label(target)
    local label = (number ~= "" and (number .. "  ") or "") .. track_name(target)
    local color = track_color(target)
    local frame_h = r.ImGui_GetFrameHeight(ctx)
    local th = r.ImGui_GetTextLineHeight(ctx)
    local name_pad = UIScale.round(5)
    local arrow_w = UIScale.round(16)
    local bar_w = math.max(UIScale.round(40), r.ImGui_GetContentRegionAvail(ctx) - arrow_w * 2 - pin_w - gap * 4)

    -- Previous track (Shift-click: first)
    local lclick, lhov = header_arrow(ctx, "##send_studio_prev", "left", arrow_w, frame_h)
    if lhov then r.ImGui_SetTooltip(ctx, "Previous track (Shift-click: first)") end
    if lclick then navigate_track(app, settings, target, pinned, shift_key_down(ctx) and "first" or -1) end
    r.ImGui_SameLine(ctx, 0, gap)

    -- Colour bar fills the name area (name left, +N right)
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local badge_inner = badge_text and (calc_text_width(ctx, badge_text) + gap) or 0
    local shown = ellipsize_text(ctx, label, bar_w - name_pad * 2 - badge_inner)
    local text_color = Theme.colors.text
    if color then
      r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy, cx + bar_w, cy + frame_h, color, UIScale.px(3))
      text_color = Theme.text_for_background(color, Theme.colors.text, nil, 4.5)
    end
    r.ImGui_DrawList_AddText(draw_list, cx + name_pad, cy + (frame_h - th) * 0.5, text_color, shown)
    if badge_text then
      r.ImGui_DrawList_AddText(draw_list, cx + bar_w - name_pad - calc_text_width(ctx, badge_text), cy + (frame_h - th) * 0.5, text_color, badge_text)
    end
    r.ImGui_Dummy(ctx, bar_w, frame_h)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, track_name(target) .. (badge_text and ("\n" .. tostring(source_count) .. " tracks selected - new sends apply to all") or ""))
    end
    r.ImGui_SameLine(ctx, 0, gap)

    -- Next track (Shift-click: last)
    local rclick, rhov = header_arrow(ctx, "##send_studio_next", "right", arrow_w, frame_h)
    if rhov then r.ImGui_SetTooltip(ctx, "Next track (Shift-click: last)") end
    if rclick then navigate_track(app, settings, target, pinned, shift_key_down(ctx) and "last" or 1) end
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No track selected")
  end

  -- Pin toggle on the right
  r.ImGui_SameLine(ctx)
  local avail_x = r.ImGui_GetContentRegionAvail(ctx)
  if avail_x > pin_w then r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail_x - pin_w)) end
  if pinned then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.accent, nil, nil, 4.5))
  end
  if r.ImGui_Button(ctx, pin_label .. "##send_studio_pin", pin_w, 0) then
    if pinned then set_pin(app, settings, nil) else set_pin(app, settings, target) end
  end
  if pinned then r.ImGui_PopStyleColor(ctx, 3) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, pinned and "Unpin - follow selection again" or "Pin this track (stop following selection)") end
end

-- Toolbar with global actions: new bus, copy/paste sends, reset solo/listen.
local function draw_toolbar(app, settings, target, sources)
  local ctx = app.ctx
  local has_target = valid_track(target)
  local clip_count = state.clipboard and #state.clipboard or 0

  if r.ImGui_SmallButton(ctx, "+ Bus##send_studio_newbus") and has_target then state.bus_open = true end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Create a new bus track and send the active track(s) to it") end
  r.ImGui_SameLine(ctx)

  if r.ImGui_SmallButton(ctx, "Copy##send_studio_copy") and has_target then
    state.clipboard = copy_sends(target)
    app.status = "Send Studio: copied " .. tostring(#state.clipboard) .. " sends"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy this track's sends to the clipboard") end
  r.ImGui_SameLine(ctx)

  local can_paste = clip_count > 0
  if not can_paste and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_SmallButton(ctx, (can_paste and ("Paste (" .. clip_count .. ")") or "Paste") .. "##send_studio_paste") and can_paste then
    paste_sends(sources, state.clipboard)
  end
  if not can_paste and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  if can_paste and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Paste copied sends onto the active track(s)") end

  if state.audition or (has_target and track_has_solo(target)) then
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.warning, nil, nil, 4.5))
    local reset = r.ImGui_SmallButton(ctx, "Reset Solo##send_studio_reset")
    r.ImGui_PopStyleColor(ctx, 3)
    if reset then reset_all_listen(target) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear active solo/listen and restore the previous state") end
  end
end

-- The target track's own volume fader (handy for aux/return tracks kept at 0).
local function draw_track_fader(app, settings, target)
  local ctx = app.ctx
  if not valid_track(target) then return end
  local gap = UIScale.round(8)
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local ok, sx = pcall(r.ImGui_GetStyleVar, ctx, r.ImGui_StyleVar_ItemSpacing())
    if ok and sx then gap = sx end
  end
  local muted = read_track_own_mute(target)
  local shown_db = linear_to_db(read_track_own_volume(target), settings.min_db)
  local function nudge(delta)
    write_track_own_volume(target, db_to_linear(clamp(shown_db + delta, settings.min_db, settings.max_db), settings.min_db, settings.max_db))
  end

  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Track")
  r.ImGui_SameLine(ctx)

  local mute_w = UIScale.text_button_w(ctx, "M", 30, 6)
  if muted then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.warning, nil, nil, 4.5))
  end
  if r.ImGui_Button(ctx, "M##track_mute", mute_w, 0) then write_track_own_mute(target, not muted) end
  if muted then r.ImGui_PopStyleColor(ctx, 3) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, muted and "Unmute track" or "Mute track") end
  r.ImGui_SameLine(ctx)

  local step_w = UIScale.text_button_w(ctx, "-", 22, 6)
  if r.ImGui_Button(ctx, "-##track_dn", step_w, 0) then nudge(-1) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "-1 dB") end
  r.ImGui_SameLine(ctx)

  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local slider_w = math.max(UIScale.round(70), avail - step_w - gap * 2)
  r.ImGui_SetNextItemWidth(ctx, slider_w)
  local sc = push_slider_theme(ctx)
  local changed, nd = r.ImGui_SliderDouble(ctx, "##track_vol", shown_db, settings.min_db, settings.max_db, "%.1f dB")
  r.ImGui_PopStyleColor(ctx, sc)
  local applied = false
  if r.ImGui_IsItemHovered(ctx) then
    if r.ImGui_IsMouseClicked(ctx, 1) then write_track_own_volume(target, 1); applied = true
    else
      local wd = slider_wheel_delta(ctx, shown_db, 0.1, settings.min_db, settings.max_db)
      if wd then write_track_own_volume(target, db_to_linear(wd, settings.min_db, settings.max_db)); applied = true end
    end
    r.ImGui_SetTooltip(ctx, "This track's own fader | Drag | Shift+wheel: fine | Right-click: 0 dB")
  end
  if not applied and changed then write_track_own_volume(target, db_to_linear(nd, settings.min_db, settings.max_db)) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+##track_up", step_w, 0) then nudge(1) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "+1 dB") end
  r.ImGui_Separator(ctx)
end

local function draw_footer(app, settings)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local left_x, top_y = r.ImGui_GetCursorScreenPos(ctx)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  local footer_h = r.ImGui_GetFrameHeight(ctx) + UIScale.round(14)
  r.ImGui_DrawList_AddRectFilled(draw_list, left_x, top_y, left_x + width, top_y + footer_h, 0x00000033, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, left_x, top_y, left_x + width, top_y + footer_h, Theme.colors.border, UIScale.px(4), 0, UIScale.px(0.8))
  r.ImGui_SetCursorScreenPos(ctx, left_x + UIScale.round(8), top_y + UIScale.round(7))

  -- View toggle
  local function view_button(label, value)
    local active = settings.view_mode == value
    if active then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.accent, nil, nil, 4.5))
    end
    local clicked = r.ImGui_Button(ctx, label .. "##send_studio_view_" .. value, UIScale.text_button_w(ctx, label, 58, 8), 0)
    if active then r.ImGui_PopStyleColor(ctx, 3) end
    if clicked and not active then
      settings.view_mode = value
      if app.save_settings then app.save_settings() end
    end
  end
  view_button("Cards", "cards")
  r.ImGui_SameLine(ctx, 0, UIScale.round(4))
  view_button("List", "list")

  -- Card flow toggle (only relevant for the card view)
  if settings.view_mode == "cards" then
    r.ImGui_SameLine(ctx, 0, UIScale.round(4))
    local is_cols = settings.card_flow ~= "rows"
    if r.ImGui_Button(ctx, (is_cols and "Cols" or "Rows") .. "##send_studio_flow", UIScale.text_button_w(ctx, "Cols", 52, 8), 0) then
      settings.card_flow = is_cols and "rows" or "columns"
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, is_cols and "Card flow: fill columns (down first) - click for rows" or "Card flow: fill rows (across first) - click for columns") end
  end

  -- Default send mode selector
  r.ImGui_SameLine(ctx, 0, UIScale.round(16))
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "New:")
  r.ImGui_SameLine(ctx)
  local combo_avail = r.ImGui_GetContentRegionAvail(ctx)
  -- Fill the remaining footer width, but keep a small minimum and never push
  -- past the edge, so a very narrow docker does not drop the combo off-screen.
  local combo_w = math.max(UIScale.round(24), math.min(math.max(UIScale.round(52), combo_avail - UIScale.round(8)), combo_avail - UIScale.round(4)))
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  if r.ImGui_BeginCombo(ctx, "##send_studio_default_mode", send_mode_label(settings.default_send_mode)) then
    for _, mode in ipairs(SEND_MODES) do
      if r.ImGui_Selectable(ctx, send_mode_label(mode), settings.default_send_mode == mode) then
        settings.default_send_mode = mode
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Send mode applied to newly created sends/receives") end
end

-- ---------------------------------------------------------------------------
-- Module entry points
-- ---------------------------------------------------------------------------

function M.init(app)
  ensure_settings(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local target, pinned = target_track(app, settings)

  -- Resolve which tracks new/pasted routing applies to (multi-track when not pinned).
  local sources
  if pinned then
    sources = valid_track(target) and { target } or {}
  else
    sources = selected_track_list(app)
  end
  if #sources == 0 and valid_track(target) then sources = { target } end
  state.apply_tracks = sources

  draw_header(app, settings, target, pinned, #sources)
  draw_toolbar(app, settings, target, sources)
  draw_track_fader(app, settings, target)
  r.ImGui_Dummy(ctx, 1, UIScale.round(4))

  local footer_h = r.ImGui_GetFrameHeight(ctx) + UIScale.round(22)
  if r.ImGui_BeginChild(ctx, "##send_studio_body", 0, -footer_h) then
    if not valid_track(target) then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select a track to manage its sends and receives.")
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Tip: use Pin to keep a track in view while selecting others.")
    else
      local _, body_h = r.ImGui_GetContentRegionAvail(ctx)
      local sends = build_rows(target, 0, settings)
      local receives = build_rows(target, -1, settings)
      draw_section(app, settings, "Sends", sends, "send", body_h)
      r.ImGui_Separator(ctx)
      r.ImGui_Dummy(ctx, 1, UIScale.round(4))
      draw_section(app, settings, "Receives", receives, "receive", body_h)
    end
    r.ImGui_EndChild(ctx)
  end

  draw_footer(app, settings)
  draw_picker_popup(app, settings, target)
  draw_bus_popup(app, settings)
end

return M
