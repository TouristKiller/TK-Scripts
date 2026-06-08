local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")
local MeterEngine = require("core.meter_engine")

local M = {
  id = "control_room",
  title = "Control Room",
  icon = "CTL",
  version = "0.1.0"
}

local defaults = {
  min_db = -60,
  max_db = 12,
  show_master = true,
  show_metronome = true,
  show_selected_track = true,
  show_monitor = true,
  show_cues = true,
  monitor_send_index = -1,
  meter_smoothing = 0.35,
  dim_db = -12,
  monitor_aliases = {},
  monitor_modes = {},
  meter_open = false,
  meter_compact = true,
  meter_adaptive_height = true,
  meter_source = "master",
  meter_fx_auto_install = true,
  meter_read_hz = 20,
  meter_display_items = MeterEngine.default_display_items,
  meter_target_lufs = MeterEngine.default_target_lufs,
  cue_outputs = {},
  cue_mix_active_guid = "",
  cue_send_prefader = true,
  cue_send_modes = {},
  setup_window = {}
}

local state = {
  meters = {},
  dragging_lane = nil,
  metronome_checked = false,
  metronome_key = nil,
  metronome_status = nil,
  setup_open = false,
  meter_open = false,
  meter_peaks = {},
  pending_meter_reset = nil,
  meter_settings_open = false,
  meter_value_fonts = {},
  dim_enabled = false,
  dim_volumes = {},
  speaker_select_index = nil,
  speaker_mutes = {},
  cue_listen = {},
  cue_cleanup_status = nil,
  cue_names_synced = false,
  apply_send_mode_cue_guid = nil
}

local metronome_keys = {
  "projmetrovol",
  "projmetrovol1",
  "projmetrovol2",
  "projmetrov1",
  "projmetrov2",
  "metronomevol"
}

local METRONOME_TOGGLE_ACTION = 40364
local REAROUTE_CHANNELS = 16
local CUE_TRACK_EXT_KEY = "P_EXT:TK_CONTROL_ROOM_CUE"
local MONITOR_MODES = { "stereo", "mono", "left_source", "right_source", "left_speaker", "right_speaker" }
local MONITOR_MODE_LABELS = { stereo = "Stereo", mono = "Mono Sum", left_source = "L Source", right_source = "R Source", left_speaker = "L Speaker", right_speaker = "R Speaker" }
local CUE_OUTPUT_MODES = { "stereo", "mono" }
local CUE_OUTPUT_MODE_LABELS = { stereo = "Stereo", mono = "Mono Sum" }

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy_default(child) end
  return result
end

local function ensure_settings(app)
  app.settings.control_room = app.settings.control_room or {}
  local settings = app.settings.control_room
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

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

local function selected_track(app)
  local track = app.selection and app.selection.track and app.selection.track.pointer
  if valid_track(track) then return track end
  track = r.GetSelectedTrack(0, 0)
  if valid_track(track) then return track end
  return nil
end

local function track_name(track)
  if not valid_track(track) then return "No track selected" end
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  return "Track"
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

local function write_with_undo(label, callback)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, result = pcall(callback)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock(label, -1)
  return ok and result ~= false
end

local function read_track_volume(track)
  if not valid_track(track) then return nil end
  return r.GetMediaTrackInfo_Value(track, "D_VOL") or 1
end

local function write_track_volume(track, value, label)
  if not valid_track(track) then return false end
  value = clamp(value, 0, 4)
  return write_with_undo(label, function()
    return r.SetMediaTrackInfo_Value(track, "D_VOL", value)
  end)
end

local function read_track_mute(track)
  if not valid_track(track) then return nil end
  return (r.GetMediaTrackInfo_Value(track, "B_MUTE") or 0) == 1
end

local function write_track_mute(track, muted, label)
  if not valid_track(track) then return false end
  return write_with_undo(label, function()
    return r.SetMediaTrackInfo_Value(track, "B_MUTE", muted and 1 or 0)
  end)
end

local function read_track_peak(track)
  if not valid_track(track) or not r.Track_GetPeakInfo then return 0 end
  local left_ok, left_peak = pcall(r.Track_GetPeakInfo, track, 0)
  local right_ok, right_peak = pcall(r.Track_GetPeakInfo, track, 1)
  left_peak = left_ok and tonumber(left_peak) or 0
  right_peak = right_ok and tonumber(right_peak) or 0
  return math.max(math.abs(left_peak or 0), math.abs(right_peak or 0))
end

local function read_track_peaks(track)
  if not valid_track(track) or not r.Track_GetPeakInfo then return 0, 0 end
  local left_ok, left_peak = pcall(r.Track_GetPeakInfo, track, 0)
  local right_ok, right_peak = pcall(r.Track_GetPeakInfo, track, 1)
  left_peak = left_ok and tonumber(left_peak) or 0
  right_peak = right_ok and tonumber(right_peak) or 0
  return math.abs(left_peak or 0), math.abs(right_peak or 0)
end

local function smoothed_meter(id, raw_value, settings)
  local previous = state.meters[id] or 0
  local smoothing = clamp(settings.meter_smoothing or defaults.meter_smoothing, 0.05, 0.95)
  local next_value = raw_value > previous and raw_value or previous + (raw_value - previous) * smoothing
  if next_value < 0.0001 then next_value = 0 end
  state.meters[id] = next_value
  return next_value
end

local function detect_metronome_key()
  if state.metronome_checked then return state.metronome_key end
  state.metronome_checked = true
  if not r.SNM_GetDoubleConfigVar or not r.SNM_SetDoubleConfigVar then
    state.metronome_status = "SWS config API not available"
    return nil
  end
  local sentinel = -987654.321
  for _, key in ipairs(metronome_keys) do
    local ok, value = pcall(r.SNM_GetDoubleConfigVar, key, sentinel)
    if ok and type(value) == "number" and value ~= sentinel then
      state.metronome_key = key
      state.metronome_status = nil
      return key
    end
  end
  state.metronome_status = "Metronome volume API not found"
  return nil
end

local function read_metronome_volume()
  local key = detect_metronome_key()
  if not key then return nil end
  local ok, value = pcall(r.SNM_GetDoubleConfigVar, key, 1)
  if ok and type(value) == "number" then return clamp(value, 0, 4) end
  return nil
end

local function write_metronome_volume(value)
  local key = detect_metronome_key()
  if not key then return false end
  value = clamp(value, 0, 4)
  return write_with_undo("Control Room: Metronome volume", function()
    return r.SNM_SetDoubleConfigVar(key, value)
  end)
end

local function metronome_enabled()
  if r.GetToggleCommandStateEx then
    local ok, state_value = pcall(r.GetToggleCommandStateEx, 0, METRONOME_TOGGLE_ACTION)
    if ok then return tonumber(state_value) == 1 end
  end
  if r.GetToggleCommandState then
    local ok, state_value = pcall(r.GetToggleCommandState, METRONOME_TOGGLE_ACTION)
    if ok then return tonumber(state_value) == 1 end
  end
  return false
end

local function toggle_metronome()
  r.Main_OnCommand(METRONOME_TOGGLE_ACTION, 0)
  return true
end

local function output_channel_name(channel)
  channel = math.max(0, math.floor(tonumber(channel) or 0))
  if r.GetOutputChannelName then
    local ok, retval, name = pcall(r.GetOutputChannelName, channel)
    if ok and type(name) == "string" and name ~= "" then return name end
    if ok and type(retval) == "string" and retval ~= "" then return retval end
  end
  return "Out " .. tostring(channel + 1)
end

local function output_target_name(channel, mono, rearoute)
  channel = math.max(0, math.floor(tonumber(channel) or 0))
  if rearoute then
    local name = mono and tostring(channel + 1) or (tostring(channel + 1) .. " / " .. tostring(channel + 2))
    return "ReaRoute " .. name
  end
  if mono then return output_channel_name(channel) end
  return output_channel_name(channel) .. " / " .. output_channel_name(channel + 1)
end

local function add_output_target(targets, channel, mono, rearoute)
  targets[#targets + 1] = {
    channel = channel,
    mono = mono == true,
    rearoute = rearoute == true,
    name = output_target_name(channel, mono == true, rearoute == true)
  }
end

local function available_output_targets(outputs)
  local targets = {}
  local count = 0
  if r.GetNumAudioOutputs then
    local ok, value = pcall(r.GetNumAudioOutputs)
    count = ok and math.floor(tonumber(value) or 0) or 0
  end
  for channel = 0, count - 2, 2 do
    add_output_target(targets, channel, false, false)
  end
  for channel = 0, count - 1 do
    add_output_target(targets, channel, true, false)
  end
  if #targets == 0 then add_output_target(targets, 0, true, false) end
  local rearoute_count = 0
  for _, output in ipairs(outputs or {}) do
    local target = output and output.target or nil
    if target and target.rearoute then rearoute_count = math.max(rearoute_count, target.channel + (target.mono and 1 or 2)) end
  end
  rearoute_count = math.max(rearoute_count, REAROUTE_CHANNELS)
  for channel = 0, rearoute_count - 2, 2 do
    add_output_target(targets, channel, false, true)
  end
  for channel = 0, rearoute_count - 1 do
    add_output_target(targets, channel, true, true)
  end
  return targets
end

local function source_target_name(channel, mono)
  channel = math.max(0, math.floor(tonumber(channel) or 0))
  if mono then return "Master " .. tostring(channel + 1) end
  return "Master " .. tostring(channel + 1) .. " / " .. tostring(channel + 2)
end

local function add_source_target(targets, channel, mono)
  targets[#targets + 1] = {
    channel = channel,
    mono = mono == true,
    name = source_target_name(channel, mono == true)
  }
end

local function available_source_targets(master)
  local targets = {}
  local count = 2
  if valid_track(master) and r.GetMediaTrackInfo_Value then
    local ok, value = pcall(r.GetMediaTrackInfo_Value, master, "I_NCHAN")
    if ok then count = math.max(2, math.floor(tonumber(value) or 2)) end
  end
  for channel = 0, count - 2 do
    add_source_target(targets, channel, false)
  end
  for channel = 0, count - 1 do
    add_source_target(targets, channel, true)
  end
  return targets
end

local function monitor_send_source(master, index)
  if valid_track(master) and index and r.GetTrackSendInfo_Value then
    local ok, raw_channel = pcall(r.GetTrackSendInfo_Value, master, 1, index, "I_SRCCHAN")
    if ok and type(raw_channel) == "number" then
      raw_channel = math.floor(raw_channel)
      if raw_channel < 0 then return { raw = raw_channel, channel = -1, mono = false, name = "None" } end
      local channel = raw_channel & 0x1FF
      local mono = (raw_channel & 1024) == 1024
      return { raw = raw_channel, channel = channel, mono = mono, name = source_target_name(channel, mono) }
    end
  end
  return { raw = 0, channel = 0, mono = false, name = source_target_name(0, false) }
end

local function monitor_send_target(master, index)
  if valid_track(master) and index and r.GetTrackSendInfo_Value then
    local ok, raw_channel = pcall(r.GetTrackSendInfo_Value, master, 1, index, "I_DSTCHAN")
    if ok and type(raw_channel) == "number" then
      raw_channel = math.floor(raw_channel)
      local channel = raw_channel & 0x1FF
      local mono = (raw_channel & 1024) == 1024
      local rearoute = (raw_channel & 512) == 512
      local name = output_target_name(channel, mono, rearoute)
      return { raw = raw_channel, channel = channel, mono = mono, rearoute = rearoute, name = name }
    end
  end
  return nil
end

local function monitor_send_name(master, index)
  local target = monitor_send_target(master, index)
  if target and target.name then return target.name end
  if r.GetTrackSendName then
    local ok, retval, name = pcall(r.GetTrackSendName, master, 1, index, "")
    if ok and retval and name and name ~= "" then return name end
  end
  return "Hardware Out " .. tostring((index or 0) + 1)
end

local function monitor_outputs(master)
  local outputs = {}
  if not valid_track(master) or not r.GetTrackNumSends then return outputs end
  local count = r.GetTrackNumSends(master, 1) or 0
  for index = 0, count - 1 do
    local target = monitor_send_target(master, index)
    outputs[#outputs + 1] = { index = index, target = target, name = target and target.name or monitor_send_name(master, index) }
  end
  return outputs
end

local function read_monitor_volume(master, index)
  if not valid_track(master) or not index or not r.GetTrackSendInfo_Value then return nil end
  local ok, value = pcall(r.GetTrackSendInfo_Value, master, 1, index, "D_VOL")
  if ok and type(value) == "number" then return clamp(value, 0, 4) end
  return nil
end

local function read_monitor_mute(master, index)
  if not valid_track(master) or not index or not r.GetTrackSendInfo_Value then return nil end
  local ok, value = pcall(r.GetTrackSendInfo_Value, master, 1, index, "B_MUTE")
  if ok and type(value) == "number" then return value == 1 end
  return nil
end

local function write_monitor_volume(master, index, value)
  if not valid_track(master) or not index or not r.SetTrackSendInfo_Value then return false end
  value = clamp(value, 0, 4)
  return write_with_undo("Control Room: Monitor volume", function()
    return r.SetTrackSendInfo_Value(master, 1, index, "D_VOL", value)
  end)
end

local function write_monitor_mute(master, index, muted)
  if not valid_track(master) or not index or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Control Room: Monitor mute", function()
    return r.SetTrackSendInfo_Value(master, 1, index, "B_MUTE", muted and 1 or 0)
  end)
end

local function monitor_destination_value(target)
  local value = math.max(0, math.floor(tonumber(target.channel) or 0))
  if target.mono then value = value | 1024 end
  if target.rearoute then value = value | 512 end
  return value
end

local function targets_match(left, right)
  if not left or not right then return false end
  return left.channel == right.channel and left.mono == right.mono and left.rearoute == right.rearoute
end

local function source_targets_match(left, right)
  if not left or not right then return false end
  return left.channel == right.channel and left.mono == right.mono
end

local function monitor_target_key(target)
  if not target then return nil end
  return table.concat({ target.rearoute and "rearoute" or "hardware", target.mono and "mono" or "stereo", tostring(target.channel or 0) }, ":")
end

local function clean_alias(value)
  value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  if value == "" then return nil end
  return value
end

local function monitor_alias(settings, target)
  local key = monitor_target_key(target)
  local aliases = settings and settings.monitor_aliases or nil
  return key and type(aliases) == "table" and clean_alias(aliases[key]) or nil
end

local function write_monitor_alias(app, settings, target, value)
  local key = monitor_target_key(target)
  if not key then return false end
  settings.monitor_aliases = type(settings.monitor_aliases) == "table" and settings.monitor_aliases or {}
  settings.monitor_aliases[key] = clean_alias(value)
  if app.save_settings then app.save_settings() end
  return true
end

local function clear_monitor_alias(app, settings, target)
  local key = monitor_target_key(target)
  if not key then return false end
  settings.monitor_aliases = type(settings.monitor_aliases) == "table" and settings.monitor_aliases or {}
  settings.monitor_aliases[key] = nil
  if app.save_settings then app.save_settings() end
  return true
end

local first_free_output_target

local function track_guid(track)
  if not valid_track(track) or not r.GetTrackGUID then return nil end
  local ok, guid = pcall(r.GetTrackGUID, track)
  return ok and guid and guid ~= "" and guid or nil
end

local function track_by_guid(guid)
  if not guid or guid == "" or not r.CountTracks or not r.GetTrackGUID then return nil end
  local count = r.CountTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    if valid_track(track) and track_guid(track) == guid then return track end
  end
  return nil
end

local function mark_cue_track(track)
  if valid_track(track) and r.GetSetMediaTrackInfo_String then r.GetSetMediaTrackInfo_String(track, CUE_TRACK_EXT_KEY, "1", true) end
end

local function cue_track_marked(track)
  if not valid_track(track) or not r.GetSetMediaTrackInfo_String then return false end
  local ok, _, value = pcall(r.GetSetMediaTrackInfo_String, track, CUE_TRACK_EXT_KEY, "", false)
  return ok and tostring(value or "") == "1"
end

local function default_cue_track_name(cue)
  return "TK CR Cue " .. tostring(cue and cue.index or 1)
end

local function cue_track_name(cue)
  return clean_alias(cue and cue.record and cue.record.alias) or default_cue_track_name(cue)
end

local function write_cue_track_name(cue)
  if not cue or not valid_track(cue.track) or not r.GetSetMediaTrackInfo_String then return false end
  mark_cue_track(cue.track)
  return r.GetSetMediaTrackInfo_String(cue.track, "P_NAME", cue_track_name(cue), true)
end

local function cue_outputs(settings)
  local cues = {}
  local records = type(settings.cue_outputs) == "table" and settings.cue_outputs or {}
  for index, record in ipairs(records) do
    local track = track_by_guid(record.guid)
    local target = valid_track(track) and monitor_send_target(track, 0) or nil
    cues[#cues + 1] = {
      index = index,
      record = record,
      track = track,
      target = target,
      name = target and target.name or "No cue output"
    }
  end
  return cues
end

local function sync_cue_track_names(settings)
  if not r.GetSetMediaTrackInfo_String then return false end
  local changed = false
  for _, cue in ipairs(cue_outputs(settings)) do
    if valid_track(cue.track) then
      local desired = cue_track_name(cue)
      mark_cue_track(cue.track)
      if track_name(cue.track) ~= desired then
        r.GetSetMediaTrackInfo_String(cue.track, "P_NAME", desired, true)
        changed = true
      end
    end
  end
  return changed
end

local function cue_label(cue)
  local alias = clean_alias(cue and cue.record and cue.record.alias)
  if alias then return alias end
  return "Cue " .. tostring(cue and cue.index or 1)
end

local function write_cue_alias(app, settings, cue, value)
  if not cue or not cue.record then return false end
  cue.record.alias = clean_alias(value)
  write_cue_track_name(cue)
  if app.save_settings then app.save_settings() end
  return true
end

local function cue_output_mode_key(mode)
  mode = tostring(mode or ""):lower()
  if mode == "mono" or mode == "mono sum" or mode == "sum" then return "mono" end
  return "stereo"
end

local function cue_output_mode_label(mode)
  return CUE_OUTPUT_MODE_LABELS[cue_output_mode_key(mode)] or CUE_OUTPUT_MODE_LABELS.stereo
end

local function cue_output_mode(cue)
  return cue_output_mode_key(cue and cue.record and cue.record.output_mode)
end

local function first_cue_target(settings, targets)
  local used = monitor_outputs(r.GetMasterTrack(0))
  for _, cue in ipairs(cue_outputs(settings)) do
    if cue.target then used[#used + 1] = cue end
  end
  return first_free_output_target(used, targets)
end

local function ensure_cue_send(track, target)
  if not valid_track(track) or not r.GetTrackNumSends or not r.CreateTrackSend or not r.SetTrackSendInfo_Value then return nil end
  local index = 0
  if (r.GetTrackNumSends(track, 1) or 0) == 0 then index = r.CreateTrackSend(track, nil) end
  r.SetTrackSendInfo_Value(track, 1, index, "D_VOL", 1)
  r.SetTrackSendInfo_Value(track, 1, index, "B_MUTE", 0)
  if target then r.SetTrackSendInfo_Value(track, 1, index, "I_DSTCHAN", monitor_destination_value(target)) end
  return index
end

local function cue_guid_lookup(settings)
  local lookup = {}
  for _, record in ipairs(type(settings.cue_outputs) == "table" and settings.cue_outputs or {}) do
    if record.guid then lookup[record.guid] = true end
  end
  return lookup
end

local function looks_like_control_room_cue_track(track)
  if not valid_track(track) then return false end
  local name = track_name(track)
  local main_send = r.GetMediaTrackInfo_Value and (r.GetMediaTrackInfo_Value(track, "B_MAINSEND") or 1) ~= 0
  return main_send == false and (cue_track_marked(track) or name:match("^TK CR Cue ") ~= nil)
end

local function find_track_send_to_cue(track, cue_track)
  if not valid_track(track) or not valid_track(cue_track) or not r.GetTrackNumSends or not r.GetTrackSendInfo_Value then return nil end
  local count = r.GetTrackNumSends(track, 0) or 0
  for index = 0, count - 1 do
    local ok, dest = pcall(r.GetTrackSendInfo_Value, track, 0, index, "P_DESTTRACK")
    if ok and dest == cue_track then return index end
  end
  return nil
end

local function cue_send_prefader_for_guid(settings, cue_guid)
  local modes = type(settings and settings.cue_send_modes) == "table" and settings.cue_send_modes or {}
  local mode = cue_guid and modes[cue_guid] or nil
  if mode == "post" then return false end
  if mode == "pre" then return true end
  return not settings or settings.cue_send_prefader ~= false
end

local function set_cue_send_prefader_for_guid(settings, cue_guid, prefader)
  if not settings or not cue_guid or cue_guid == "" then return false end
  settings.cue_send_modes = type(settings.cue_send_modes) == "table" and settings.cue_send_modes or {}
  settings.cue_send_modes[cue_guid] = prefader and "pre" or "post"
  return true
end

local function ensure_track_send_to_cue(track, cue_track, settings)
  if not valid_track(track) or not valid_track(cue_track) or not r.CreateTrackSend or not r.SetTrackSendInfo_Value then return nil, false end
  local index = find_track_send_to_cue(track, cue_track)
  if index then return index, false end
  index = r.CreateTrackSend(track, cue_track)
  if not index or index < 0 then return nil, false end
  r.SetTrackSendInfo_Value(track, 0, index, "D_VOL", 1)
  r.SetTrackSendInfo_Value(track, 0, index, "B_MUTE", 0)
  r.SetTrackSendInfo_Value(track, 0, index, "I_SENDMODE", cue_send_prefader_for_guid(settings, track_guid(cue_track)) and 3 or 0)
  return index, true
end

local function read_cue_send_volume(track, cue_track)
  local index = find_track_send_to_cue(track, cue_track)
  if not index or not r.GetTrackSendInfo_Value then return nil end
  local ok, value = pcall(r.GetTrackSendInfo_Value, track, 0, index, "D_VOL")
  return ok and type(value) == "number" and clamp(value, 0, 4) or nil
end

local function write_cue_send_volume(track, cue_track, value, settings)
  if not valid_track(track) or not valid_track(cue_track) then return false end
  value = clamp(value, 0, 4)
  return write_with_undo("Control Room: Cue send volume", function()
    local index = ensure_track_send_to_cue(track, cue_track, settings)
    if not index then return false end
    return r.SetTrackSendInfo_Value(track, 0, index, "D_VOL", value)
  end)
end

local function read_cue_send_pan(track, cue_track)
  local index = find_track_send_to_cue(track, cue_track)
  if not index or not r.GetTrackSendInfo_Value then return nil end
  local ok, value = pcall(r.GetTrackSendInfo_Value, track, 0, index, "D_PAN")
  return ok and type(value) == "number" and clamp(value, -1, 1) or nil
end

local function write_cue_send_pan(track, cue_track, value, settings)
  if not valid_track(track) or not valid_track(cue_track) then return false end
  value = clamp(value, -1, 1)
  return write_with_undo("Control Room: Cue send pan", function()
    local index = ensure_track_send_to_cue(track, cue_track, settings)
    if not index then return false end
    return r.SetTrackSendInfo_Value(track, 0, index, "D_PAN", value)
  end)
end

local function read_cue_send_mute(track, cue_track)
  local index = find_track_send_to_cue(track, cue_track)
  if not index or not r.GetTrackSendInfo_Value then return false end
  local ok, value = pcall(r.GetTrackSendInfo_Value, track, 0, index, "B_MUTE")
  return ok and tonumber(value) == 1
end

local function write_cue_send_mute(track, cue_track, muted, settings)
  if not valid_track(track) or not valid_track(cue_track) then return false end
  return write_with_undo("Control Room: Cue send mute", function()
    local index = ensure_track_send_to_cue(track, cue_track, settings)
    if not index then return false end
    return r.SetTrackSendInfo_Value(track, 0, index, "B_MUTE", muted and 1 or 0)
  end)
end

local function cue_source_tracks(settings)
  local tracks = {}
  if not r.CountTracks or not r.GetTrack then return tracks end
  local cue_tracks = cue_guid_lookup(settings)
  local depth = 0
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    local folder_delta = valid_track(track) and math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")) or 0) or 0
    local main_send = valid_track(track) and (r.GetMediaTrackInfo_Value(track, "B_MAINSEND") or 1) ~= 0
    if depth == 0 and valid_track(track) and (not guid or not cue_tracks[guid]) and main_send then
      tracks[#tracks + 1] = {
        track = track,
        guid = guid,
        name = track_name(track),
        volume = read_track_volume(track) or 1,
        pan = r.GetMediaTrackInfo_Value(track, "D_PAN") or 0
      }
    end
    depth = math.max(0, depth + folder_delta)
  end
  return tracks
end

local function cue_listen_entry(cue_guid)
  state.cue_listen = type(state.cue_listen) == "table" and state.cue_listen or {}
  return cue_guid and state.cue_listen[cue_guid] or nil
end

local function clear_cue_listen_state(cue_guid)
  state.cue_listen = type(state.cue_listen) == "table" and state.cue_listen or {}
  if cue_guid then state.cue_listen[cue_guid] = nil else state.cue_listen = {} end
end

local function restore_cue_listen_raw(cue_guid)
  local entry = cue_listen_entry(cue_guid)
  local cue_track = cue_guid and track_by_guid(cue_guid) or nil
  if valid_track(cue_track) and r.SetTrackSendInfo_Value then
    for guid, muted in pairs(type(entry and entry.mutes) == "table" and entry.mutes or {}) do
      local track = track_by_guid(guid)
      local index = valid_track(track) and find_track_send_to_cue(track, cue_track) or nil
      if index and type(muted) == "boolean" then r.SetTrackSendInfo_Value(track, 0, index, "B_MUTE", muted and 1 or 0) end
    end
  end
  clear_cue_listen_state(cue_guid)
  return true
end

local function cue_guid_value(cue)
  return cue and cue.record and cue.record.guid or valid_track(cue and cue.track) and track_guid(cue.track) or nil
end

local function restore_cue_listen(cue)
  local cue_guid = type(cue) == "string" and cue or cue_guid_value(cue)
  if not cue_listen_entry(cue_guid) then return false end
  return write_with_undo("Control Room: Restore cue listen", function() return restore_cue_listen_raw(cue_guid) end)
end

local function cue_listen_matches(cue, source)
  local cue_guid = cue_guid_value(cue)
  local source_guid = source and source.guid or nil
  local entry = cue_listen_entry(cue_guid)
  return cue_guid and source_guid and entry and entry.source_guid == source_guid
end

local function toggle_cue_listen(settings, cue, source)
  if not cue or not valid_track(cue.track) or not source or not valid_track(source.track) then return false end
  local cue_guid = cue_guid_value(cue)
  local source_guid = source.guid or track_guid(source.track)
  if not cue_guid or not source_guid then return false end
  local same = cue_listen_matches(cue, source)
  return write_with_undo(same and "Control Room: Restore cue listen" or "Control Room: Cue listen", function()
    if cue_listen_entry(cue_guid) then restore_cue_listen_raw(cue_guid) end
    if same then return true end
    state.cue_listen[cue_guid] = { source_guid = source_guid, mutes = {} }
    local entry = state.cue_listen[cue_guid]
    for _, item in ipairs(cue_source_tracks(settings)) do
      local item_guid = item.guid or track_guid(item.track)
      local index = item_guid and ensure_track_send_to_cue(item.track, cue.track, settings) or nil
      if index then
        entry.mutes[item_guid] = read_cue_send_mute(item.track, cue.track)
        r.SetTrackSendInfo_Value(item.track, 0, index, "B_MUTE", item_guid == source_guid and 0 or 1)
      end
    end
    return true
  end)
end

local function cue_feed_count(settings, cue_track)
  if not valid_track(cue_track) or not r.CountTracks or not r.GetTrack then return 0 end
  local cue_tracks = cue_guid_lookup(settings)
  local cue_guid = track_guid(cue_track)
  if cue_guid then cue_tracks[cue_guid] = true end
  local count = 0
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    if valid_track(track) and track ~= cue_track and (not guid or not cue_tracks[guid]) and find_track_send_to_cue(track, cue_track) then count = count + 1 end
  end
  return count
end

local function add_main_mix_sends_to_cue(settings, cue_track)
  if not valid_track(cue_track) or not r.CountTracks or not r.GetTrack or not r.CreateTrackSend or not r.SetTrackSendInfo_Value then return false end
  local cue_guid = track_guid(cue_track)
  local cue_tracks = cue_guid_lookup(settings)
  if cue_guid then cue_tracks[cue_guid] = true end
  local depth = 0
  local count = r.CountTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    local folder_delta = valid_track(track) and math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")) or 0) or 0
    local main_send = valid_track(track) and (r.GetMediaTrackInfo_Value(track, "B_MAINSEND") or 1) ~= 0
    if depth == 0 and valid_track(track) and track ~= cue_track and (not guid or not cue_tracks[guid]) and main_send then
      ensure_track_send_to_cue(track, cue_track, settings)
    end
    depth = math.max(0, depth + folder_delta)
  end
  return true
end

local function copy_main_mix_to_cue(settings, cue)
  if not cue or not valid_track(cue.track) then return false end
  return write_with_undo("Control Room: Copy main mix to cue", function()
    for _, source in ipairs(cue_source_tracks(settings)) do
      local track = source.track
      if valid_track(track) and track ~= cue.track then
        local index = ensure_track_send_to_cue(track, cue.track, settings)
        if index then
          r.SetTrackSendInfo_Value(track, 0, index, "D_VOL", read_track_volume(track) or 1)
          r.SetTrackSendInfo_Value(track, 0, index, "D_PAN", r.GetMediaTrackInfo_Value(track, "D_PAN") or 0)
        end
      end
    end
    return true
  end)
end

local function apply_cue_send_mode_to_existing(settings, cue)
  if not cue or not valid_track(cue.track) or not r.CountTracks or not r.GetTrack or not r.SetTrackSendInfo_Value then return false end
  local sendmode = cue_send_prefader_for_guid(settings, cue_guid_value(cue)) and 3 or 0
  return write_with_undo("Control Room: Apply cue send mode", function()
    local cue_tracks = cue_guid_lookup(settings)
    for track_index = 0, (r.CountTracks(0) or 0) - 1 do
      local track = r.GetTrack(0, track_index)
      local guid = track_guid(track)
      if valid_track(track) and track ~= cue.track and (not guid or not cue_tracks[guid]) then
        local send_index = find_track_send_to_cue(track, cue.track)
        if send_index then r.SetTrackSendInfo_Value(track, 0, send_index, "I_SENDMODE", sendmode) end
      end
    end
    return true
  end)
end

local function cleanup_stale_cue_sends(app, settings)
  if not settings or not r.CountTracks or not r.GetTrack or not r.GetTrackNumSends or not r.GetTrackSendInfo_Value or not r.RemoveTrackSend then return false end
  local removed_sends = 0
  local removed_records = 0
  local ok = write_with_undo("Control Room: Clean stale cue sends", function()
    settings.cue_outputs = type(settings.cue_outputs) == "table" and settings.cue_outputs or {}
    local managed_guids = {}
    local settings_changed = false
    for index = #settings.cue_outputs, 1, -1 do
      local record = settings.cue_outputs[index]
      local guid = record and record.guid or nil
      local track = guid and track_by_guid(guid) or nil
      if not guid or guid == "" or not valid_track(track) then
        if guid and guid ~= "" then
          if type(settings.cue_send_modes) == "table" then settings.cue_send_modes[guid] = nil end
          if type(state.cue_listen) == "table" then state.cue_listen[guid] = nil end
          if settings.cue_mix_active_guid == guid then settings.cue_mix_active_guid = "" end
        end
        table.remove(settings.cue_outputs, index)
        removed_records = removed_records + 1
        settings_changed = true
      else
        managed_guids[guid] = true
      end
    end
    if type(settings.cue_send_modes) == "table" then
      for guid in pairs(settings.cue_send_modes) do
        if not managed_guids[guid] then
          settings.cue_send_modes[guid] = nil
          settings_changed = true
        end
      end
    end
    if settings.cue_mix_active_guid ~= "" and not managed_guids[settings.cue_mix_active_guid] then
      settings.cue_mix_active_guid = ""
      settings_changed = true
    end
    for track_index = 0, (r.CountTracks(0) or 0) - 1 do
      local track = r.GetTrack(0, track_index)
      local guid = track_guid(track)
      if valid_track(track) and (not guid or not managed_guids[guid]) then
        for send_index = (r.GetTrackNumSends(track, 0) or 0) - 1, 0, -1 do
          local ok_dest, dest = pcall(r.GetTrackSendInfo_Value, track, 0, send_index, "P_DESTTRACK")
          local dest_guid = ok_dest and valid_track(dest) and track_guid(dest) or nil
          if ok_dest and valid_track(dest) and looks_like_control_room_cue_track(dest) and (not dest_guid or not managed_guids[dest_guid]) then
            if r.RemoveTrackSend(track, 0, send_index) then removed_sends = removed_sends + 1 end
          end
        end
      end
    end
    if app.save_settings and settings_changed then app.save_settings() end
    return true
  end)
  if ok then
    state.cue_cleanup_status = "Cleaned " .. tostring(removed_sends) .. " stale sends, " .. tostring(removed_records) .. " stale cues"
  end
  return ok
end

local function sync_cue_output(settings, cue)
  if not cue or not valid_track(cue.track) then return false end
  return write_with_undo("Control Room: Sync cue", function()
    return add_main_mix_sends_to_cue(settings, cue.track)
  end)
end

local function add_cue_output(app, settings, targets)
  if not r.InsertTrackAtIndex or not r.CountTracks or not r.GetTrack or not r.GetSetMediaTrackInfo_String then return false end
  settings.cue_outputs = type(settings.cue_outputs) == "table" and settings.cue_outputs or {}
  local cue_number = #settings.cue_outputs + 1
  local target = first_cue_target(settings, targets)
  return write_with_undo("Control Room: Add cue output", function()
    local track_index = r.CountTracks(0) or 0
    r.InsertTrackAtIndex(track_index, true)
    local track = r.GetTrack(0, track_index)
    if not valid_track(track) then return false end
    r.GetSetMediaTrackInfo_String(track, "P_NAME", "TK CR Cue " .. tostring(cue_number), true)
    mark_cue_track(track)
    r.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
    r.SetMediaTrackInfo_Value(track, "D_VOL", 1)
    r.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
    ensure_cue_send(track, target)
    local guid = track_guid(track)
    if not guid then
      if r.DeleteTrack then r.DeleteTrack(track) end
      return false
    end
    add_main_mix_sends_to_cue(settings, track)
    settings.cue_send_modes = type(settings.cue_send_modes) == "table" and settings.cue_send_modes or {}
    settings.cue_send_modes[guid] = settings.cue_send_prefader ~= false and "pre" or "post"
    settings.cue_outputs[#settings.cue_outputs + 1] = { guid = guid, alias = "Cue " .. tostring(cue_number), output_mode = "stereo" }
    write_cue_track_name({ index = cue_number, record = settings.cue_outputs[#settings.cue_outputs], track = track })
    settings.cue_mix_active_guid = settings.cue_mix_active_guid ~= "" and settings.cue_mix_active_guid or guid
    if app.save_settings then app.save_settings() end
    return true
  end)
end

local function remove_cue_output(app, settings, cue)
  if not cue or not cue.index then return false end
  settings.cue_outputs = type(settings.cue_outputs) == "table" and settings.cue_outputs or {}
  return write_with_undo("Control Room: Remove cue output", function()
    if cue.record and cue.record.guid then restore_cue_listen_raw(cue.record.guid) end
    if valid_track(cue.track) and r.DeleteTrack then r.DeleteTrack(cue.track) end
    if cue.record and settings.cue_mix_active_guid == cue.record.guid then settings.cue_mix_active_guid = "" end
    if cue.record and cue.record.guid and type(settings.cue_send_modes) == "table" then settings.cue_send_modes[cue.record.guid] = nil end
    table.remove(settings.cue_outputs, cue.index)
    if app.save_settings then app.save_settings() end
    return true
  end)
end

local function write_cue_destination(track, target)
  if not valid_track(track) or not target then return false end
  return write_with_undo("Control Room: Cue output routing", function()
    local index = ensure_cue_send(track, target)
    if not index then return false end
    return r.SetTrackSendInfo_Value(track, 1, index, "I_DSTCHAN", monitor_destination_value(target))
  end)
end

local function write_cue_output_mode(app, cue, mode)
  if not cue or not cue.record or not valid_track(cue.track) or not r.SetTrackSendInfo_Value then return false end
  mode = cue_output_mode_key(mode)
  local ok = write_with_undo("Control Room: Cue output mode", function()
    local index = ensure_cue_send(cue.track, nil)
    if not index then return false end
    return r.SetTrackSendInfo_Value(cue.track, 1, index, "B_MONO", mode == "mono" and 1 or 0)
  end)
  if not ok then return false end
  cue.record.output_mode = mode
  if app and app.save_settings then app.save_settings() end
  return true
end

function first_free_output_target(outputs, targets)
  for _, target in ipairs(targets or {}) do
    if not target.rearoute then
      local used = false
      for _, output in ipairs(outputs or {}) do
        if targets_match(output.target, target) then used = true; break end
      end
      if not used then return target end
    end
  end
  for _, target in ipairs(targets or {}) do if not target.rearoute then return target end end
  return (targets or {})[1]
end

local function write_monitor_destination(master, index, target)
  if not valid_track(master) or not index or not target or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Control Room: Monitor routing", function()
    return r.SetTrackSendInfo_Value(master, 1, index, "I_DSTCHAN", monitor_destination_value(target))
  end)
end

local function monitor_source_value(target)
  local value = math.max(0, math.floor(tonumber(target.channel) or 0))
  if target.mono then value = value | 1024 end
  return value
end

local function write_monitor_source(master, index, target)
  if not valid_track(master) or not index or not target or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Control Room: Monitor source", function()
    return r.SetTrackSendInfo_Value(master, 1, index, "I_SRCCHAN", monitor_source_value(target))
  end)
end

local function monitor_mode_key(mode)
  mode = tostring(mode or ""):lower()
  if mode == "mono sum" or mode == "sum" then return "mono" end
  if mode == "left" or mode == "l" or mode == "left source" or mode == "l source" then return "left_source" end
  if mode == "right" or mode == "r" or mode == "right source" or mode == "r source" then return "right_source" end
  if mode == "left speaker" or mode == "l speaker" then return "left_speaker" end
  if mode == "right speaker" or mode == "r speaker" then return "right_speaker" end
  for _, item in ipairs(MONITOR_MODES) do if mode == item then return item end end
  return "stereo"
end

local function monitor_mode_label(mode)
  return MONITOR_MODE_LABELS[monitor_mode_key(mode)] or MONITOR_MODE_LABELS.stereo
end

local function get_monitor_mode(settings, target)
  local key = monitor_target_key(target)
  local modes = settings and settings.monitor_modes or nil
  return monitor_mode_key(key and type(modes) == "table" and modes[key] or nil)
end

local function set_monitor_mode(app, settings, target, mode)
  local key = monitor_target_key(target)
  if not key then return false end
  settings.monitor_modes = type(settings.monitor_modes) == "table" and settings.monitor_modes or {}
  settings.monitor_modes[key] = monitor_mode_key(mode)
  if app and app.save_settings then app.save_settings() end
  return true
end

local function monitor_source_pair_channel(source)
  local channel = source and tonumber(source.channel) or 0
  if not channel or channel < 0 then return 0 end
  channel = math.floor(channel)
  if source and source.mono then return channel - (channel % 2) end
  return channel
end

local function monitor_mode_source_target(mode, source)
  mode = monitor_mode_key(mode)
  local base = monitor_source_pair_channel(source)
  if mode == "left_source" then return { channel = base, mono = true } end
  if mode == "right_source" then return { channel = base + 1, mono = true } end
  if mode == "mono" then return { channel = base, mono = false } end
  return { channel = base, mono = false }
end

local function monitor_mode_pan(mode)
  mode = monitor_mode_key(mode)
  if mode == "left_speaker" then return -1 end
  if mode == "right_speaker" then return 1 end
  return 0
end

local function apply_monitor_mode(master, index, mode, source)
  if not valid_track(master) or not index or not r.SetTrackSendInfo_Value then return false end
  mode = monitor_mode_key(mode)
  source = source or monitor_send_source(master, index)
  local target = monitor_mode_source_target(mode, source)
  return write_with_undo("Control Room: Monitor mode", function()
    local source_ok = r.SetTrackSendInfo_Value(master, 1, index, "I_SRCCHAN", monitor_source_value(target))
    local mono_ok = r.SetTrackSendInfo_Value(master, 1, index, "B_MONO", mode == "mono" and 1 or 0)
    local pan_ok = r.SetTrackSendInfo_Value(master, 1, index, "D_PAN", monitor_mode_pan(mode))
    return source_ok ~= false and mono_ok ~= false and pan_ok ~= false
  end)
end

local function write_monitor_mode(app, settings, master, index, target, mode, source)
  mode = monitor_mode_key(mode)
  if not apply_monitor_mode(master, index, mode, source) then return false end
  return set_monitor_mode(app, settings, target, mode)
end

local function add_monitor_output(master, outputs, targets)
  if not valid_track(master) or not r.CreateTrackSend or not r.SetTrackSendInfo_Value then return false end
  local target = first_free_output_target(outputs, targets)
  return write_with_undo("Control Room: Add monitor output", function()
    local index = r.CreateTrackSend(master, nil)
    if not index or index < 0 then return false end
    r.SetTrackSendInfo_Value(master, 1, index, "D_VOL", 1)
    r.SetTrackSendInfo_Value(master, 1, index, "B_MUTE", 0)
    if target then r.SetTrackSendInfo_Value(master, 1, index, "I_DSTCHAN", monitor_destination_value(target)) end
    return true
  end)
end

local function remove_monitor_output(master, index)
  if not valid_track(master) or not index or not r.RemoveTrackSend then return false end
  return write_with_undo("Control Room: Remove monitor output", function()
    return r.RemoveTrackSend(master, 1, index)
  end)
end

local function monitor_dim_factor(settings)
  local db = tonumber(settings and settings.dim_db) or defaults.dim_db
  return 10 ^ (db / 20)
end

local function toggle_monitor_dim(settings)
  local master = r.GetMasterTrack(0)
  local outputs = monitor_outputs(master)
  if #outputs == 0 or not r.SetTrackSendInfo_Value then return false end
  local label = state.dim_enabled and "Control Room: Restore monitor dim" or "Control Room: Dim monitors"
  return write_with_undo(label, function()
    if state.dim_enabled then
      for _, output in ipairs(outputs) do
        local saved = state.dim_volumes[tostring(output.index)]
        if type(saved) == "number" then r.SetTrackSendInfo_Value(master, 1, output.index, "D_VOL", saved) end
      end
      state.dim_enabled = false
      state.dim_volumes = {}
      return true
    end
    local factor = monitor_dim_factor(settings)
    state.dim_volumes = {}
    for _, output in ipairs(outputs) do
      local value = read_monitor_volume(master, output.index)
      if type(value) == "number" then
        state.dim_volumes[tostring(output.index)] = value
        r.SetTrackSendInfo_Value(master, 1, output.index, "D_VOL", clamp(value * factor, 0, 4))
      end
    end
    state.dim_enabled = true
    return true
  end)
end

local function restore_speaker_select(master)
  master = master or r.GetMasterTrack(0)
  if not valid_track(master) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Control Room: Restore speaker select", function()
    local outputs = monitor_outputs(master)
    for _, output in ipairs(outputs) do
      local saved = state.speaker_mutes[tostring(output.index)]
      if type(saved) == "boolean" then r.SetTrackSendInfo_Value(master, 1, output.index, "B_MUTE", saved and 1 or 0) end
    end
    state.speaker_select_index = nil
    state.speaker_mutes = {}
    return true
  end)
end

local function toggle_speaker_select(index)
  local master = r.GetMasterTrack(0)
  local outputs = monitor_outputs(master)
  if #outputs == 0 or not index or not r.SetTrackSendInfo_Value then return false end
  if state.speaker_select_index == index then return restore_speaker_select(master) end
  return write_with_undo("Control Room: Speaker select", function()
    if state.speaker_select_index == nil then
      state.speaker_mutes = {}
      for _, output in ipairs(outputs) do
        local muted = read_monitor_mute(master, output.index)
        if type(muted) == "boolean" then state.speaker_mutes[tostring(output.index)] = muted end
      end
    end
    for _, output in ipairs(outputs) do
      r.SetTrackSendInfo_Value(master, 1, output.index, "B_MUTE", output.index == index and 0 or 1)
    end
    state.speaker_select_index = index
    return true
  end)
end

local function build_lanes(app, settings)
  local lanes = {}
  local master = r.GetMasterTrack(0)
  if settings.show_selected_track then
    local track = selected_track(app)
    local track_value = read_track_volume(track)
    lanes[#lanes + 1] = {
      id = "selected_track",
      label = "Track",
      subtitle = track_name(track),
      value = track_value or 1,
      meter = smoothed_meter("selected_track", read_track_peak(track), settings),
      enabled = track_value ~= nil,
      status = track_value and nil or "No selected track",
      handle_color = native_color_to_u32(valid_track(track) and r.GetTrackColor(track) or 0, 0xFF),
      write = function(value) return write_track_volume(track, value, "Control Room: Track volume") end
    }
  end
  if settings.show_master then
    local master_value = read_track_volume(master)
    lanes[#lanes + 1] = {
      id = "master",
      label = "Master",
      subtitle = "Main output",
      value = master_value or 1,
      meter = smoothed_meter("master", read_track_peak(master), settings),
      enabled = master_value ~= nil,
      status = master_value and nil or "Unavailable",
      write = function(value) return write_track_volume(master, value, "Control Room: Master volume") end
    }
  end
  if settings.show_monitor then
    local outputs = monitor_outputs(master)
    if #outputs == 0 then
      lanes[#lanes + 1] = {
        id = "monitor_empty",
        label = "Monitor",
        subtitle = "No hardware out",
        value = 1,
        meter = 0,
        enabled = false,
        status = "No master hardware out",
        write = function() return false end
      }
    else
      for _, output in ipairs(outputs) do
        local send_index = output.index
        local monitor_value = read_monitor_volume(master, send_index)
        local monitor_muted = read_monitor_mute(master, send_index)
        local alias = monitor_alias(settings, output.target)
        local mode = get_monitor_mode(settings, output.target)
        local mode_label = monitor_mode_label(mode)
        local lane_id = "monitor_" .. tostring(send_index)
        lanes[#lanes + 1] = {
          id = lane_id,
          label = alias or (#outputs > 1 and ("Monitor " .. tostring(send_index + 1)) or "Monitor"),
          subtitle = tostring(output.name or "Hardware Out") .. " | " .. mode_label,
          value = monitor_value or 1,
          meter = smoothed_meter(lane_id, read_track_peak(master), settings),
          enabled = monitor_value ~= nil,
          status = monitor_value and nil or "Monitor unavailable",
          led_state = monitor_muted == false,
          led_toggle = function() return write_monitor_mute(master, send_index, monitor_muted == false) end,
          led_off_color = Theme.colors.warning,
          led_on_tooltip = "Mute monitor",
          led_off_tooltip = "Unmute monitor",
          solo_state = state.speaker_select_index == send_index,
          solo_toggle = function() return toggle_speaker_select(send_index) end,
          solo_on_tooltip = "Restore all speakers",
          solo_off_tooltip = "Select this speaker",
          mode = mode,
          mode_menu_title = "Monitor Mode",
          mode_options = MONITOR_MODES,
          set_mode = function(next_mode) return write_monitor_mode(app, settings, master, send_index, output.target, next_mode, monitor_send_source(master, send_index)) end,
          write = function(value) return write_monitor_volume(master, send_index, value) end
        }
      end
    end
  end
  if settings.show_cues then
    local cues = cue_outputs(settings)
    for _, cue in ipairs(cues) do
      local track = cue.track
      local cue_value = read_track_volume(track)
      local cue_muted = read_track_mute(track)
      local cue_enabled = cue_value ~= nil
      local lane_id = "cue_" .. tostring(cue.index)
      local output_mode = cue_output_mode(cue)
      lanes[#lanes + 1] = {
        id = lane_id,
        label = cue_label(cue),
        subtitle = tostring(cue.name or "Cue Output") .. " | " .. cue_output_mode_label(output_mode),
        value = cue_value or 1,
        meter = smoothed_meter(lane_id, read_track_peak(track), settings),
        enabled = cue_enabled,
        status = cue_value and nil or "Cue track missing",
        led_state = cue_enabled and cue_muted == false,
        led_toggle = cue_enabled and function() return write_track_mute(track, cue_muted == false, "Control Room: Cue mute") end or nil,
        led_off_color = Theme.colors.warning,
        led_on_tooltip = "Mute cue",
        led_off_tooltip = "Unmute cue",
        mode = output_mode,
        mode_menu_title = "Cue Output Mode",
        mode_options = CUE_OUTPUT_MODES,
        set_mode = function(next_mode) return write_cue_output_mode(app, cue, next_mode) end,
        handle_color = native_color_to_u32(valid_track(track) and r.GetTrackColor(track) or 0, 0xFF) or Theme.colors.warning,
        write = cue_enabled and function(value) return write_track_volume(track, value, "Control Room: Cue volume") end or function() return false end
      }
    end
  end
  if settings.show_metronome then
    local metro_value = read_metronome_volume()
    lanes[#lanes + 1] = {
      id = "metronome",
      label = "Metronome",
      subtitle = state.metronome_key or "Click level",
      value = metro_value or 1,
      meter = 0,
      enabled = metro_value ~= nil,
      status = metro_value and nil or state.metronome_status,
      led_state = metronome_enabled(),
      led_toggle = toggle_metronome,
      led_on_tooltip = "Metronome off",
      led_off_tooltip = "Metronome on",
      write = write_metronome_volume
    }
  end
  return lanes
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

local function meter_sources(app, settings)
  local sources = {}
  sources[#sources + 1] = { id = "master", label = "Master", track = r.GetMasterTrack(0) }
  local track = selected_track(app)
  sources[#sources + 1] = { id = "selected", label = "Selected", track = track }
  for _, cue in ipairs(cue_outputs(settings)) do
    if valid_track(cue.track) then sources[#sources + 1] = { id = "cue:" .. tostring(cue_guid_value(cue) or cue.index), label = cue_label(cue), track = cue.track } end
  end
  return sources
end

local function active_meter_source(app, settings)
  local sources = meter_sources(app, settings)
  local wanted = settings.meter_source or defaults.meter_source
  for _, source in ipairs(sources) do
    if source.id == wanted and valid_track(source.track) then return source, sources end
  end
  for _, source in ipairs(sources) do
    if valid_track(source.track) then return source, sources end
  end
  return sources[1], sources
end

local function meter_value_y(value, top_y, bottom_y, settings)
  local db = linear_to_db(value, settings.min_db or defaults.min_db)
  local normalized = clamp((db - (settings.min_db or defaults.min_db)) / ((settings.max_db or defaults.max_db) - (settings.min_db or defaults.min_db)), 0, 1)
  return bottom_y - normalized * (bottom_y - top_y)
end

local function draw_meter_channel(ctx, draw_list, left_x, right_x, top_y, bottom_y, value, peak_value, peak_text, settings)
  local reset_clicked = false
  local inset = UIScale.px(2)
  local corner = UIScale.px(2)
  r.ImGui_DrawList_AddRectFilled(draw_list, left_x, top_y, right_x, bottom_y, 0x00000066, corner)
  r.ImGui_DrawList_AddRect(draw_list, left_x, top_y, right_x, bottom_y, Theme.colors.border, corner, 0, UIScale.px(0.8))
  local fill_top = meter_value_y(value, top_y, bottom_y, settings)
  if value > 0.000001 then
    local warning_value = db_to_linear(-18, settings.min_db or defaults.min_db, settings.max_db or defaults.max_db)
    local danger_value = db_to_linear(0, settings.min_db or defaults.min_db, settings.max_db or defaults.max_db)
    local warning_y = meter_value_y(warning_value, top_y, bottom_y, settings)
    local danger_y = meter_value_y(danger_value, top_y, bottom_y, settings)
    if value > danger_value then
      r.ImGui_DrawList_AddRectFilled(draw_list, left_x + inset, warning_y, right_x - inset, bottom_y - inset, Theme.colors.accent, UIScale.px(1))
      r.ImGui_DrawList_AddRectFilled(draw_list, left_x + inset, danger_y, right_x - inset, warning_y, Theme.colors.warning, UIScale.px(1))
      r.ImGui_DrawList_AddRectFilled(draw_list, left_x + inset, fill_top, right_x - inset, danger_y, Theme.colors.danger, UIScale.px(1))
    elseif value > warning_value then
      r.ImGui_DrawList_AddRectFilled(draw_list, left_x + inset, warning_y, right_x - inset, bottom_y - inset, Theme.colors.accent, UIScale.px(1))
      r.ImGui_DrawList_AddRectFilled(draw_list, left_x + inset, fill_top, right_x - inset, warning_y, Theme.colors.warning, UIScale.px(1))
    else
      r.ImGui_DrawList_AddRectFilled(draw_list, left_x + inset, fill_top, right_x - inset, bottom_y - inset, Theme.colors.accent, UIScale.px(1))
    end
  end
  if peak_value and peak_value > 0.000001 then
    local peak_y = meter_value_y(peak_value, top_y, bottom_y, settings)
    local peak_color = peak_value >= 1 and Theme.colors.danger or Theme.colors.warning
    r.ImGui_DrawList_AddLine(draw_list, left_x + UIScale.px(1), peak_y, right_x - UIScale.px(1), peak_y, peak_color, UIScale.px(1.4))
  end
  if peak_text and bottom_y - top_y >= UIScale.round(44) then
    local text = ellipsize_text(ctx, peak_text, math.max(0, right_x - left_x - UIScale.round(6)))
    local text_w = calc_text_width(ctx, text)
    local clipped = peak_value and peak_value >= 1
    local badge_w = math.min(right_x - left_x - UIScale.round(6), text_w + UIScale.round(10))
    local badge_h = UIScale.round(18)
    local badge_x = left_x + ((right_x - left_x) - badge_w) * 0.5
    local badge_y = bottom_y - badge_h - UIScale.round(4)
    local text_x = badge_x + math.max(0, (badge_w - text_w) * 0.5)
    local text_y = badge_y + UIScale.round(2)
    local text_color = clipped and Theme.colors.danger or 0xFFFFFFFF
    local badge_border = clipped and Theme.colors.danger or 0xFFFFFF33
    local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
    local badge_hovered = mouse_x >= badge_x and mouse_x <= badge_x + badge_w and mouse_y >= badge_y and mouse_y <= badge_y + badge_h
    r.ImGui_DrawList_PushClipRect(draw_list, left_x + inset, top_y + inset, right_x - inset, bottom_y - inset, true)
    r.ImGui_DrawList_AddRectFilled(draw_list, badge_x + UIScale.px(1), badge_y + UIScale.px(1), badge_x + badge_w + UIScale.px(1), badge_y + badge_h + UIScale.px(1), 0x00000066, UIScale.px(4))
    r.ImGui_DrawList_AddRectFilled(draw_list, badge_x, badge_y, badge_x + badge_w, badge_y + badge_h, badge_hovered and 0x151515EE or 0x050505CC, UIScale.px(4))
    r.ImGui_DrawList_AddRect(draw_list, badge_x, badge_y, badge_x + badge_w, badge_y + badge_h, badge_hovered and 0xFFFFFFFF or badge_border, UIScale.px(4), 0, badge_hovered and UIScale.px(1.1) or (clipped and UIScale.px(1.2) or UIScale.px(0.8)))
    r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, text)
    r.ImGui_DrawList_PopClipRect(draw_list)
    if badge_hovered then
      r.ImGui_SetTooltip(ctx, "Click to reset peak")
      reset_clicked = r.ImGui_IsMouseClicked(ctx, 0)
    end
  end
  return reset_clicked
end

local function draw_meter_scale(ctx, draw_list, left_x, right_x, top_y, bottom_y, settings)
  local height = math.max(0, bottom_y - top_y)
  local marks = height < UIScale.round(190) and { 12, 6, 0, -6, -12, -24, -60 } or { 12, 9, 6, 3, 0, -3, -6, -9, -12, -18, -24, -36, -60 }
  local grid_color = color_with_alpha(Theme.colors.text_dim or Theme.colors.border, 0x4A)
  local zero_color = color_with_alpha(Theme.colors.text_dim or Theme.colors.border, 0x82)
  local line_inset = UIScale.round(20)
  local label_offset_y = UIScale.round(6)
  for _, db in ipairs(marks) do
    if db <= (settings.max_db or defaults.max_db) and db >= (settings.min_db or defaults.min_db) then
      local value = db_to_linear(db, settings.min_db or defaults.min_db, settings.max_db or defaults.max_db)
      local y = meter_value_y(value, top_y, bottom_y, settings)
      r.ImGui_DrawList_AddLine(draw_list, left_x + line_inset, y, right_x - line_inset, y, db == 0 and zero_color or grid_color, db == 0 and UIScale.px(1.4) or UIScale.px(1))
      local text = tostring(db)
      local left_text = db < 0 and (tostring(math.abs(db)) .. "-") or text
      local width = calc_text_width(ctx, text)
      r.ImGui_DrawList_AddText(draw_list, left_x, y - label_offset_y, Theme.colors.text_dim, left_text)
      r.ImGui_DrawList_AddText(draw_list, right_x - width, y - label_offset_y, Theme.colors.text_dim, text)
    end
  end
end

local function get_meter_value_font(ctx, font_size)
  if not r.ImGui_CreateFont then return nil end
  font_size = math.max(UIScale.round(16), math.floor((tonumber(font_size) or UIScale.round(20)) + 0.5))
  state.meter_value_fonts = type(state.meter_value_fonts) == "table" and state.meter_value_fonts or {}
  local key = tostring(font_size)
  if state.meter_value_fonts[key] then return state.meter_value_fonts[key] end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", font_size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  state.meter_value_fonts[key] = font
  return font
end

local function draw_meter_value_text(ctx, draw_list, x, y, color, text, font_size, font)
  if r.ImGui_DrawList_AddTextEx and font then
    local ok = pcall(r.ImGui_DrawList_AddTextEx, draw_list, font, font_size, x, y, color, text)
    if ok then return end
  end
  r.ImGui_DrawList_AddText(draw_list, x + 1, y, color_with_alpha(color, 0x88), text)
  r.ImGui_DrawList_AddText(draw_list, x, y, color, text)
end

local function draw_meter_info_box(ctx, draw_list, x, y, width, height, label, value, unit, value_color)
  local bg = color_with_alpha(Theme.colors.frame_bg or 0x000000FF, 0xE8)
  local border = color_with_alpha(Theme.colors.border or Theme.colors.text_dim, 0xB0)
  local pad = UIScale.round(5)
  local label_text = ellipsize_text(ctx, label, math.max(0, width - pad * 2))
  local value_text = ellipsize_text(ctx, unit and unit ~= "" and (value .. " " .. unit) or value, math.max(0, width - pad * 2))
  local label_w = calc_text_width(ctx, label_text)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, border, UIScale.px(4), 0, UIScale.px(0.8))
  r.ImGui_DrawList_AddText(draw_list, x + math.max(pad, (width - label_w) * 0.5), y + pad, Theme.colors.text_dim, label_text)
  local current_font_size = r.ImGui_GetFontSize and (r.ImGui_GetFontSize(ctx) or UIScale.round(13)) or UIScale.round(13)
  local value_font_size = math.max(19, math.floor(current_font_size * 1.55 + 0.5))
  local value_font = get_meter_value_font(ctx, value_font_size)
  local scale = value_font_size / math.max(1, current_font_size)
  local value_w = calc_text_width(ctx, value_text) * scale
  local value_x = x + math.max(pad, (width - value_w) * 0.5)
  local value_y = y + height - value_font_size - UIScale.round(14)
  draw_meter_value_text(ctx, draw_list, value_x, value_y, value_color or Theme.colors.text, value_text, value_font_size, value_font)
end

local function selected_meter_item_map(settings)
  local selected = {}
  local items = type(settings.meter_display_items) == "table" and settings.meter_display_items or MeterEngine.default_display_items
  for _, id in ipairs(items) do selected[id] = true end
  return selected
end

local function selected_meter_item_count(settings)
  local count = 0
  local selected = selected_meter_item_map(settings)
  for _, item in ipairs(MeterEngine.available_items or {}) do if selected[item.id] then count = count + 1 end end
  return count
end

local function set_meter_item_selected(settings, id, enabled)
  local selected = selected_meter_item_map(settings)
  local count = selected_meter_item_count(settings)
  if enabled and not selected[id] and count >= (MeterEngine.max_display_items or 6) then return false end
  selected[id] = enabled == true
  local next_items = {}
  for _, item in ipairs(MeterEngine.available_items or {}) do
    if selected[item.id] and #next_items < (MeterEngine.max_display_items or 6) then next_items[#next_items + 1] = item.id end
  end
  settings.meter_display_items = next_items
  return true
end

local function draw_meter_settings_popup(app, settings)
  local ctx = app.ctx
  local title = "Meter Display Settings"
  if state.meter_settings_open then
    state.meter_settings_open = false
    r.ImGui_OpenPopup(ctx, title)
  end
  if not r.ImGui_BeginPopupModal or not r.ImGui_BeginPopupModal(ctx, title, true, r.ImGui_WindowFlags_AlwaysAutoResize and r.ImGui_WindowFlags_AlwaysAutoResize() or 0) then return end
  local selected = selected_meter_item_map(settings)
  local count = selected_meter_item_count(settings)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Visible values")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(count) .. "/" .. tostring(MeterEngine.max_display_items or 6))
  for _, item in ipairs(MeterEngine.available_items or {}) do
    local checked = selected[item.id] == true
    local changed, value = r.ImGui_Checkbox(ctx, tostring(item.label or item.id), checked)
    if changed and set_meter_item_selected(settings, item.id, value) and app.save_settings then app.save_settings() end
    if not checked and count >= (MeterEngine.max_display_items or 6) and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Maximum 6 values") end
  end
  r.ImGui_Separator(ctx)
  local adaptive_changed, adaptive_value = r.ImGui_Checkbox(ctx, "Adaptive height", settings.meter_adaptive_height ~= false)
  if adaptive_changed then
    settings.meter_adaptive_height = adaptive_value == true
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Use all available height for the meter") end
  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Target LUFS")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  local target_changed, target_value = r.ImGui_SliderDouble(ctx, "##control_room_meter_target", tonumber(settings.meter_target_lufs) or MeterEngine.default_target_lufs, -24, -6, "%.1f")
  if target_changed then
    settings.meter_target_lufs = target_value
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_Button(ctx, "-14##control_room_meter_target_14", UIScale.text_button_w(ctx, "-14", 48, 6), 0) then settings.meter_target_lufs = -14; if app.save_settings then app.save_settings() end end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "-16##control_room_meter_target_16", UIScale.text_button_w(ctx, "-16", 48, 6), 0) then settings.meter_target_lufs = -16; if app.save_settings then app.save_settings() end end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "-23##control_room_meter_target_23", UIScale.text_button_w(ctx, "-23", 48, 6), 0) then settings.meter_target_lufs = -23; if app.save_settings then app.save_settings() end end
  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Default##control_room_meter_display_default", UIScale.text_button_w(ctx, "Default", 84, 8), 0) then
    settings.meter_display_items = copy_default(MeterEngine.default_display_items)
    settings.meter_target_lufs = MeterEngine.default_target_lufs
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Close##control_room_meter_display_close", UIScale.text_button_w(ctx, "Close", 72, 8), 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

local function draw_lane(app, lane, settings, width, height)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local enabled = lane.enabled == true
  r.ImGui_PushID(ctx, lane.id)
  local left_x, top_y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_Dummy(ctx, width, height)
  if lane.mode_options and lane.set_mode and r.ImGui_BeginPopupContextItem and r.ImGui_BeginPopupContextItem(ctx, "##control_room_lane_mode") then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(lane.mode_menu_title or "Mode"))
    for _, mode in ipairs(lane.mode_options) do
      local selected = monitor_mode_key(lane.mode) == mode
      if r.ImGui_Selectable(ctx, monitor_mode_label(mode), selected) then lane.set_mode(mode) end
      if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndPopup(ctx)
  end
  local right_x = left_x + width
  local bottom_y = top_y + height
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local hovered = mouse_x >= left_x and mouse_x <= right_x and mouse_y >= top_y and mouse_y <= bottom_y
  local bg = hovered and Theme.colors.frame_hover or Theme.colors.frame_bg
  local border = enabled and Theme.colors.border or 0xFFFFFF22
  local text_color = Theme.text_for_background(bg, enabled and Theme.colors.text or Theme.colors.text_dim, Theme.colors.text, 4.5)
  local title_color = Theme.text_for_background(bg, enabled and Theme.colors.accent or Theme.colors.text_dim, Theme.colors.text, 4.5)
  local subtitle_color = Theme.text_for_background(bg, Theme.colors.text_dim, Theme.colors.text, 4.5)
  local pad = UIScale.round(8)
  local corner = UIScale.px(6)
  r.ImGui_DrawList_AddRectFilled(draw_list, left_x, top_y, right_x, bottom_y, bg, corner)
  r.ImGui_DrawList_AddRect(draw_list, left_x, top_y, right_x, bottom_y, border, corner, 0, hovered and UIScale.px(1.4) or UIScale.px(0.8))
  local led_hovered = false
  local solo_hovered = false
  r.ImGui_DrawList_PushClipRect(draw_list, left_x + pad, top_y + UIScale.round(6), right_x - pad, top_y + UIScale.round(26), true)
  r.ImGui_DrawList_AddText(draw_list, left_x + UIScale.round(9), top_y + UIScale.round(8), title_color, ellipsize_text(ctx, lane.label, right_x - left_x - UIScale.round(17)))
  r.ImGui_DrawList_PopClipRect(draw_list)
  r.ImGui_DrawList_AddLine(draw_list, left_x + pad, top_y + UIScale.round(29), right_x - pad, top_y + UIScale.round(29), 0xFFFFFF20, UIScale.px(1))
  if lane.solo_toggle then
    local solo_right = lane.led_toggle and right_x - UIScale.round(27) or right_x - pad
    local solo_width = calc_text_width(ctx, "S")
    local solo_left = solo_right - solo_width - UIScale.round(4)
    local solo_top = top_y + UIScale.round(31)
    local solo_bottom = top_y + UIScale.round(47)
    solo_hovered = enabled and mouse_x >= solo_left and mouse_x <= solo_right and mouse_y >= solo_top and mouse_y <= solo_bottom
    local solo_text = Theme.text_for_background(bg, lane.solo_state and Theme.colors.accent or (solo_hovered and Theme.colors.text or Theme.colors.text_dim), Theme.colors.text, 4.5)
    r.ImGui_DrawList_AddText(draw_list, solo_left + UIScale.round(2), solo_top + UIScale.round(1), solo_text, "S")
    if solo_hovered and r.ImGui_IsMouseClicked(ctx, 0) then lane.solo_toggle() end
  end
  if lane.led_toggle then
    local led_x = right_x - UIScale.round(15)
    local led_y = top_y + UIScale.round(41)
    led_hovered = mouse_x >= led_x - pad and mouse_x <= led_x + pad and mouse_y >= led_y - pad and mouse_y <= led_y + pad
    local led_color = lane.led_state and (lane.led_on_color or Theme.colors.accent) or (lane.led_off_color or 0x00000055)
    local led_border = led_hovered and Theme.colors.text or Theme.colors.border
    r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, led_y, UIScale.px(5), led_color, 16)
    r.ImGui_DrawList_AddCircle(draw_list, led_x, led_y, UIScale.px(7), led_border, 16, led_hovered and UIScale.px(1.5) or UIScale.px(1))
    if led_hovered and r.ImGui_IsMouseClicked(ctx, 0) then lane.led_toggle() end
  end
  if lane.subtitle then
    local subtitle_right = right_x - (lane.led_toggle and UIScale.round(32) or pad)
    r.ImGui_DrawList_PushClipRect(draw_list, left_x + pad, top_y + UIScale.round(31), subtitle_right, top_y + UIScale.round(52), true)
    r.ImGui_DrawList_AddText(draw_list, left_x + UIScale.round(9), top_y + UIScale.round(34), subtitle_color, ellipsize_text(ctx, lane.subtitle, math.max(0, subtitle_right - left_x - UIScale.round(17))))
    r.ImGui_DrawList_PopClipRect(draw_list)
  end
  local value_text = enabled and format_db(lane.value, settings) or "--"
  local value_width = calc_text_width(ctx, value_text)
  r.ImGui_DrawList_AddText(draw_list, right_x - value_width - UIScale.round(9), bottom_y - UIScale.round(24), text_color, value_text)
  local fader_top = top_y + UIScale.round(64)
  local fader_bottom = bottom_y - UIScale.round(36)
  local fader_x = left_x + width * 0.46
  local fader_width = UIScale.round(8)
  local meter_left = right_x - UIScale.round(20)
  local meter_right = right_x - UIScale.round(12)
  local range = math.max(1, fader_bottom - fader_top)
  local current_db = linear_to_db(lane.value, settings.min_db)
  local normalized = clamp((current_db - settings.min_db) / (settings.max_db - settings.min_db), 0, 1)
  local thumb_y = fader_bottom - normalized * range
  r.ImGui_DrawList_AddRectFilled(draw_list, fader_x - fader_width * 0.5, fader_top, fader_x + fader_width * 0.5, fader_bottom, 0x00000044, UIScale.px(4))
  if enabled then r.ImGui_DrawList_AddRectFilled(draw_list, fader_x - fader_width * 0.5, thumb_y, fader_x + fader_width * 0.5, fader_bottom, Theme.colors.accent_soft, UIScale.px(4)) end
  local zero_normalized = clamp((0 - settings.min_db) / (settings.max_db - settings.min_db), 0, 1)
  local zero_y = fader_bottom - zero_normalized * range
  r.ImGui_DrawList_AddLine(draw_list, fader_x - UIScale.round(15), zero_y, fader_x + UIScale.round(15), zero_y, Theme.colors.border, UIScale.px(1))
  local handle_color = enabled and (lane.handle_color or Theme.colors.accent) or Theme.colors.border
  r.ImGui_DrawList_AddRectFilled(draw_list, fader_x - UIScale.round(16), thumb_y - UIScale.round(5), fader_x + UIScale.round(16), thumb_y + UIScale.round(5), handle_color, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, fader_x - UIScale.round(16), thumb_y - UIScale.round(5), fader_x + UIScale.round(16), thumb_y + UIScale.round(5), 0x00000066, UIScale.px(3), 0, UIScale.px(1))
  local handle_left = fader_x - UIScale.round(19)
  local handle_right = fader_x + UIScale.round(19)
  local handle_top = thumb_y - UIScale.round(8)
  local handle_bottom = thumb_y + UIScale.round(8)
  local handle_hovered = enabled and mouse_x >= handle_left and mouse_x <= handle_right and mouse_y >= handle_top and mouse_y <= handle_bottom
  local fader_hovered = enabled and mouse_x >= fader_x - UIScale.round(24) and mouse_x <= fader_x + UIScale.round(24) and mouse_y >= fader_top - UIScale.round(6) and mouse_y <= fader_bottom + UIScale.round(6)
  r.ImGui_DrawList_AddRectFilled(draw_list, meter_left, fader_top, meter_right, fader_bottom, 0x00000055, UIScale.px(2))
  local meter_db = linear_to_db(lane.meter or 0, settings.min_db)
  local meter_normalized = clamp((meter_db - settings.min_db) / (settings.max_db - settings.min_db), 0, 1)
  local meter_top = fader_bottom - meter_normalized * range
  if enabled and meter_normalized > 0 then r.ImGui_DrawList_AddRectFilled(draw_list, meter_left, meter_top, meter_right, fader_bottom, meter_color(lane.meter or 0), UIScale.px(2)) end
  if handle_hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    lane.write(1)
    state.dragging_lane = nil
  elseif handle_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
    state.dragging_lane = lane.id
  end
  if not r.ImGui_IsMouseDown(ctx, 0) and state.dragging_lane == lane.id then state.dragging_lane = nil end
  local wheel = fader_hovered and shift_key_down(ctx) and mouse_wheel_delta(ctx) or 0
  if enabled and math.abs(wheel) > 0.0001 then
    local next_db = clamp(current_db + wheel * 0.1, settings.min_db, settings.max_db)
    local next_value = db_to_linear(next_db, settings.min_db, settings.max_db)
    if math.abs(next_value - (lane.value or 0)) > 0.0005 then lane.write(next_value) end
  end
  if enabled and state.dragging_lane == lane.id then
    local next_normalized = clamp((fader_bottom - mouse_y) / range, 0, 1)
    local next_db = settings.min_db + next_normalized * (settings.max_db - settings.min_db)
    local next_value = db_to_linear(next_db, settings.min_db, settings.max_db)
    if math.abs(next_value - (lane.value or 0)) > 0.0005 then lane.write(next_value) end
  end
  if solo_hovered then r.ImGui_SetTooltip(ctx, lane.solo_state and (lane.solo_on_tooltip or "Selected") or (lane.solo_off_tooltip or "Select")) elseif led_hovered then r.ImGui_SetTooltip(ctx, lane.led_state and (lane.led_on_tooltip or "On") or (lane.led_off_tooltip or "Off")) elseif handle_hovered then r.ImGui_SetTooltip(ctx, "Drag to adjust, Shift+scroll for fine adjust, double-click for 0 dB") elseif fader_hovered then r.ImGui_SetTooltip(ctx, "Shift+scroll for fine adjust") elseif hovered and not enabled then r.ImGui_SetTooltip(ctx, tostring(lane.status or "Unavailable")) elseif hovered and lane.mode_options and lane.subtitle then r.ImGui_SetTooltip(ctx, tostring(lane.subtitle) .. "\nRight-click for mode") elseif hovered and lane.subtitle then r.ImGui_SetTooltip(ctx, tostring(lane.subtitle)) end
  r.ImGui_PopID(ctx)
end

local function set_meter_open(app, settings, open)
  open = open == true
  state.meter_open = open
  settings.meter_open = open
  if open then state.setup_open = false end
  if app.save_settings then app.save_settings() end
end

local function queue_meter_reset(source)
  if not source then return end
  state.pending_meter_reset = { source_id = source.id, track_guid = track_guid(source.track) }
  state.meter_peaks[source.id or "none"] = { left = 0, right = 0 }
  state.meters["meter_l:" .. tostring(source.id or "none")] = 0
  state.meters["meter_r:" .. tostring(source.id or "none")] = 0
end

local function draw_header(app, lanes)
  local ctx = app.ctx
  local active_count = 0
  for _, lane in ipairs(lanes) do if lane.enabled then active_count = active_count + 1 end end
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Control Room")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(active_count) .. "/" .. tostring(#lanes) .. " active")
end

local function draw_meter_panel(app, settings, footer_height)
  if not state.meter_open then return end
  local ctx = app.ctx
  local reserved_height = math.max(0, tonumber(footer_height) or 0)
  if r.ImGui_BeginChild(ctx, "##control_room_meter_panel", 0, -reserved_height, 0) then
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local side_padding = (avail_w or 0) >= UIScale.round(180) and UIScale.round(18) or UIScale.round(8)
    local panel_w = math.max(UIScale.round(96), math.max(0, (avail_w or UIScale.round(170)) - side_padding * 2))
    local start_x, start_y = r.ImGui_GetCursorScreenPos(ctx)
    local panel_x = start_x + math.max(0, ((avail_w or panel_w) - panel_w) * 0.5)
    r.ImGui_SetCursorScreenPos(ctx, panel_x, start_y)
    local source, sources = active_meter_source(app, settings)
    if source and source.id ~= settings.meter_source and valid_track(source.track) then settings.meter_source = source.id end
    local button_gap = UIScale.gap(6)
    local settings_button_w = UIScale.text_button_w(ctx, "...", 34, 6)
    local main_button_w = math.max(UIScale.round(44), (panel_w - settings_button_w - button_gap * 2) / 2)
    if r.ImGui_Button(ctx, "Reset##control_room_meter_reset", main_button_w, 0) then queue_meter_reset(source) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Reset meter history") end
    r.ImGui_SameLine(ctx, 0, button_gap)
    if r.ImGui_Button(ctx, "Back##control_room_meter_back", main_button_w, 0) then set_meter_open(app, settings, false) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Back to Control Room") end
    r.ImGui_SameLine(ctx, 0, button_gap)
    if r.ImGui_Button(ctx, "...##control_room_meter_settings", settings_button_w, 0) then state.meter_settings_open = true end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Meter settings") end
    r.ImGui_SetCursorScreenPos(ctx, panel_x, select(2, r.ImGui_GetCursorScreenPos(ctx)))
    r.ImGui_SetNextItemWidth(ctx, panel_w)
    if r.ImGui_BeginCombo(ctx, "##control_room_meter_source", source and source.label or "Master") then
      for _, item in ipairs(sources) do
        local valid = valid_track(item.track)
        if valid and r.ImGui_Selectable(ctx, item.label, source and item.id == source.id) then
          settings.meter_source = item.id
          source = item
          if app.save_settings then app.save_settings() end
        end
        if valid and source and item.id == source.id and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    local left_raw, right_raw = read_track_peaks(source and source.track or nil)
    local left_value = smoothed_meter("meter_l:" .. tostring(source and source.id or "none"), left_raw, settings)
    local right_value = smoothed_meter("meter_r:" .. tostring(source and source.id or "none"), right_raw, settings)
    state.meter_peaks = type(state.meter_peaks) == "table" and state.meter_peaks or {}
    local peak_key = source and source.id or "none"
    local peak = state.meter_peaks[peak_key] or { left = 0, right = 0 }
    peak.left = math.max(peak.left or 0, left_raw or 0)
    peak.right = math.max(peak.right or 0, right_raw or 0)
    state.meter_peaks[peak_key] = peak
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_SetCursorScreenPos(ctx, panel_x, select(2, r.ImGui_GetCursorScreenPos(ctx)))
    local meter_x, meter_y = r.ImGui_GetCursorScreenPos(ctx)
    local _, meter_avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local info_items = MeterEngine.info_items(settings, source, Theme.colors)
    local divider_gap_top = UIScale.round(10)
    local divider_gap_bottom = UIScale.round(10)
    local info_gap = UIScale.round(5)
    local info_box_h = UIScale.round(58)
    local info_h = #info_items * info_box_h + math.max(0, #info_items - 1) * info_gap
    local details_h = #info_items > 0 and (divider_gap_top + UIScale.round(1) + divider_gap_bottom + info_h + UIScale.round(4)) or 0
    local available_meter_h = (meter_avail_h or UIScale.round(220)) - details_h
    local meter_h = settings.meter_adaptive_height ~= false and available_meter_h or math.min(UIScale.round(360), available_meter_h)
    meter_h = math.max(UIScale.round(80), meter_h)
    r.ImGui_Dummy(ctx, panel_w, meter_h)
    local bottom_y = meter_y + meter_h
    draw_meter_scale(ctx, draw_list, meter_x + UIScale.round(2), meter_x + panel_w - UIScale.round(2), meter_y + UIScale.round(6), bottom_y - UIScale.round(4), settings)
    local scale_margin = panel_w >= UIScale.round(180) and UIScale.round(36) or UIScale.round(28)
    local bar_gap = math.max(UIScale.round(4), math.min(UIScale.round(16), panel_w * 0.04))
    local bar_w = math.max(UIScale.round(10), (panel_w - scale_margin * 2 - bar_gap) * 0.5)
    local bar_left = meter_x + scale_margin
    local reset_left = draw_meter_channel(ctx, draw_list, bar_left, bar_left + bar_w, meter_y + UIScale.round(6), bottom_y - UIScale.round(4), left_value, peak.left, "L " .. format_db(peak.left or 0, settings), settings)
    local reset_right = draw_meter_channel(ctx, draw_list, bar_left + bar_w + bar_gap, bar_left + bar_w * 2 + bar_gap, meter_y + UIScale.round(6), bottom_y - UIScale.round(4), right_value, peak.right, "R " .. format_db(peak.right or 0, settings), settings)
    if reset_left then peak.left = 0 end
    if reset_right then peak.right = 0 end
    if #info_items > 0 then
      local divider_y = meter_y + meter_h + divider_gap_top
      r.ImGui_DrawList_AddLine(draw_list, panel_x, divider_y, panel_x + panel_w, divider_y, color_with_alpha(Theme.colors.border or Theme.colors.text_dim, 0xAA), UIScale.px(1))
      r.ImGui_SetCursorScreenPos(ctx, panel_x, divider_y + divider_gap_bottom)
      local info_x, info_y = r.ImGui_GetCursorScreenPos(ctx)
      r.ImGui_Dummy(ctx, panel_w, info_h)
      for index, item in ipairs(info_items) do
        draw_meter_info_box(ctx, draw_list, info_x, info_y + (index - 1) * (info_box_h + info_gap), panel_w, info_box_h, item.label, item.value, item.unit, item.color)
      end
    end
    r.ImGui_EndChild(ctx)
  end
end

local function draw_control_footer(app, settings)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local left_x, top_y = r.ImGui_GetCursorScreenPos(ctx)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  local footer_h = r.ImGui_GetFrameHeight(ctx) + UIScale.round(14)
  local meter_compact = state.meter_open and settings.meter_compact == true
  r.ImGui_DrawList_AddRectFilled(draw_list, left_x, top_y, left_x + width, top_y + footer_h, 0x00000033, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, left_x, top_y, left_x + width, top_y + footer_h, Theme.colors.border, UIScale.px(4), 0, UIScale.px(0.8))
  r.ImGui_SetCursorScreenPos(ctx, left_x + UIScale.round(8), top_y + UIScale.round(7))
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local active_button_text = Theme.text_for_backgrounds({ Theme.colors.accent, Theme.colors.warning }, Theme.colors.text, nil, 4.5)
  if not meter_compact then
    if state.dim_enabled then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), active_button_text)
    end
    local dim_clicked = r.ImGui_Button(ctx, "DIM##control_room_dim", UIScale.text_button_w(ctx, "DIM", 46, 6), button_h)
    if state.dim_enabled then r.ImGui_PopStyleColor(ctx, 4) end
    if dim_clicked then toggle_monitor_dim(settings) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, state.dim_enabled and "Restore monitor levels" or "Dim monitor outputs") end
    r.ImGui_SameLine(ctx)
    if state.speaker_select_index ~= nil then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), active_button_text)
      local all_clicked = r.ImGui_Button(ctx, "ALL##control_room_speaker_all", UIScale.text_button_w(ctx, "ALL", 38, 6), button_h)
      r.ImGui_PopStyleColor(ctx, 4)
      if all_clicked then restore_speaker_select() end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Restore all speaker mutes") end
      r.ImGui_SameLine(ctx)
    end
    if state.setup_open then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), active_button_text)
    end
    local setup_clicked = r.ImGui_Button(ctx, "Setup##control_room_setup", UIScale.text_button_w(ctx, "Setup", 62, 8), button_h)
    if state.setup_open then r.ImGui_PopStyleColor(ctx, 4) end
    if setup_clicked then state.setup_open = not state.setup_open end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Monitor routing setup") end
    r.ImGui_SameLine(ctx)
  end
  if state.meter_open then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), active_button_text)
  end
  local compact_footer = width < UIScale.round(210)
  local meter_label = compact_footer and "Mtr" or "Meter"
  local meter_clicked = r.ImGui_Button(ctx, meter_label .. "##control_room_meter", UIScale.text_button_w(ctx, meter_label, compact_footer and 42 or 58, 8), button_h)
  if state.meter_open then r.ImGui_PopStyleColor(ctx, 4) end
  if meter_clicked then set_meter_open(app, settings, not state.meter_open) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, state.meter_open and "Hide meter" or "Show meter") end
  r.ImGui_SetCursorScreenPos(ctx, left_x, top_y)
  r.ImGui_Dummy(ctx, width, footer_h + UIScale.round(4))
end

local function monitor_mode_text(output)
  local target = output and output.target or nil
  if not target then return "Unknown" end
  local mode = target.mono and "Mono" or "Stereo"
  if target.rearoute then mode = "ReaRoute " .. mode end
  return mode
end

local function target_matches_output(target, output)
  local current = output and output.target or nil
  return targets_match(current, target)
end

local function draw_setup_section_button(ctx, label, id, selected, width)
  if selected then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
  else
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000033)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent_soft)
  end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds(selected and { Theme.colors.accent, Theme.colors.warning } or { Theme.colors.frame_bg, Theme.colors.border, Theme.colors.accent_soft }, Theme.colors.text, nil, 4.5))
  local clicked = r.ImGui_Button(ctx, label .. "##" .. id, width, UIScale.button_h(ctx, 0))
  r.ImGui_PopStyleColor(ctx, 4)
  return clicked
end

local function push_setup_slider_theme(ctx)
  local count = 0
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.colors.frame_bg); count = count + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.colors.frame_hover); count = count + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.colors.accent_soft); count = count + 1 end
  if r.ImGui_Col_SliderGrab then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent); count = count + 1 end
  if r.ImGui_Col_SliderGrabActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.text); count = count + 1 end
  return count
end

local function pop_setup_slider_theme(ctx, count)
  if count and count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

local function cue_mix_item_right_clicked(ctx)
  if r.ImGui_IsItemClicked then return r.ImGui_IsItemClicked(ctx, 1) end
  return r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1)
end

local function draw_apply_send_mode_popup(app, settings)
  local ctx = app.ctx
  local title = "Apply Cue Send Mode"
  if not r.ImGui_BeginPopupModal or not r.ImGui_BeginPopupModal(ctx, title, true, r.ImGui_WindowFlags_AlwaysAutoResize and r.ImGui_WindowFlags_AlwaysAutoResize() or 0) then return end
  local cue_guid = state.apply_send_mode_cue_guid
  local target_cue = nil
  for _, cue in ipairs(cue_outputs(settings)) do
    if cue_guid_value(cue) == cue_guid then target_cue = cue; break end
  end
  local mode_name = cue_send_prefader_for_guid(settings, cue_guid) and "Pre" or "Post"
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Apply " .. mode_name .. " to existing sends?")
  if target_cue and valid_track(target_cue.track) then
    r.ImGui_Text(ctx, "Cue: " .. cue_label(target_cue))
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Existing cue send modes for this cue will be overwritten.")
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "The selected cue is no longer available.")
  end
  r.ImGui_Separator(ctx)
  if target_cue and valid_track(target_cue.track) and r.ImGui_Button(ctx, "Apply##control_room_apply_send_mode_confirm", UIScale.text_button_w(ctx, "Apply", 84, 8), 0) then
    apply_cue_send_mode_to_existing(settings, target_cue)
    state.apply_send_mode_cue_guid = nil
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if target_cue and valid_track(target_cue.track) then r.ImGui_SameLine(ctx) end
  if r.ImGui_Button(ctx, "Cancel##control_room_apply_send_mode_cancel", UIScale.text_button_w(ctx, "Cancel", 84, 8), 0) then
    state.apply_send_mode_cue_guid = nil
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

local function draw_setup_popup(app, settings)
  local ctx = app.ctx
  if not state.setup_open then return end
  local popup_w, popup_h = UIScale.window_size(560, 620)
  local saved_window = type(settings.setup_window) == "table" and settings.setup_window or {}
  if r.ImGui_SetNextWindowSize then r.ImGui_SetNextWindowSize(ctx, popup_w, popup_h, r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0) end
  if r.ImGui_SetNextWindowPos and r.ImGui_Cond_Appearing then
    local saved_x = tonumber(saved_window.x)
    local saved_y = tonumber(saved_window.y)
    if saved_x and saved_y then
      r.ImGui_SetNextWindowPos(ctx, saved_x, saved_y, r.ImGui_Cond_Appearing())
    else
      local window_x = app.cache and app.cache.window_x or nil
      local window_y = app.cache and app.cache.window_y or nil
      local window_w = app.cache and app.cache.window_w or nil
      local window_h = app.cache and app.cache.window_h or nil
      if not window_x or not window_y or not window_w or not window_h then
        window_x, window_y = r.ImGui_GetWindowPos(ctx)
        window_w, window_h = r.ImGui_GetWindowSize(ctx)
      end
      r.ImGui_SetNextWindowPos(ctx, window_x + math.max(0, (window_w - popup_w) * 0.5), window_y + math.max(0, (window_h - popup_h) * 0.5), r.ImGui_Cond_Appearing())
    end
  end
  local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize()
  local visible, open = r.ImGui_Begin(ctx, "Control Room Setup##control_room_setup_window", true, flags)
  if not open then state.setup_open = false end
  if not visible then return end
  if r.ImGui_GetWindowPos and r.ImGui_GetWindowSize then
    local current_x, current_y = r.ImGui_GetWindowPos(ctx)
    local current_w, current_h = r.ImGui_GetWindowSize(ctx)
    settings.setup_window = type(settings.setup_window) == "table" and settings.setup_window or {}
    local setup_window = settings.setup_window
    if math.abs((tonumber(setup_window.x) or -99999) - current_x) > 0.5 or math.abs((tonumber(setup_window.y) or -99999) - current_y) > 0.5 or math.abs((tonumber(setup_window.w) or -99999) - current_w) > 0.5 or math.abs((tonumber(setup_window.h) or -99999) - current_h) > 0.5 then
      setup_window.x, setup_window.y, setup_window.w, setup_window.h = current_x, current_y, current_w, current_h
      if app.save_settings and (not r.ImGui_IsMouseDown or not r.ImGui_IsMouseDown(ctx, 0)) then app.save_settings() end
    end
  end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local header_x, header_y = r.ImGui_GetCursorScreenPos(ctx)
  local header_w = r.ImGui_GetContentRegionAvail(ctx)
  local close_size = UIScale.round(14)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Control Room Setup")
  r.ImGui_SetCursorScreenPos(ctx, header_x + header_w - close_size - UIScale.round(2), header_y + UIScale.round(2))
  if r.ImGui_InvisibleButton(ctx, "##control_room_setup_close", close_size, close_size) then state.setup_open = false end
  local close_hovered = r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddCircleFilled(draw_list, header_x + header_w - close_size * 0.5 - UIScale.round(2), header_y + close_size * 0.5 + UIScale.round(2), close_size * 0.5, close_hovered and Theme.colors.danger or 0xF7768EFF, 16)
  r.ImGui_DrawList_AddCircle(draw_list, header_x + header_w - close_size * 0.5 - UIScale.round(2), header_y + close_size * 0.5 + UIScale.round(2), close_size * 0.5, 0x3A1018FF, 16, UIScale.px(1))
  if close_hovered then r.ImGui_SetTooltip(ctx, "Close setup") end
  r.ImGui_SetCursorScreenPos(ctx, header_x, header_y + r.ImGui_GetFrameHeight(ctx) + UIScale.round(6))
  if r.ImGui_Separator then r.ImGui_Separator(ctx) end
  local master = r.GetMasterTrack(0)
  local outputs = monitor_outputs(master)
  local targets = available_output_targets(outputs)
  local source_targets = available_source_targets(master)
  local cues = cue_outputs(settings)
  state.setup_tab = state.setup_tab or "monitors"
  local tab_avail = r.ImGui_GetContentRegionAvail(ctx)
  local tab_w = math.max(UIScale.round(82), (tab_avail - UIScale.round(18)) / 4)
  if draw_setup_section_button(ctx, "Monitors", "control_room_setup_monitors", state.setup_tab == "monitors", tab_w) then state.setup_tab = "monitors" end
  r.ImGui_SameLine(ctx)
  if draw_setup_section_button(ctx, "Cues", "control_room_setup_cues", state.setup_tab == "cues", tab_w) then state.setup_tab = "cues" end
  r.ImGui_SameLine(ctx)
  if draw_setup_section_button(ctx, "Mix", "control_room_setup_mix", state.setup_tab == "mix", tab_w) then state.setup_tab = "mix" end
  r.ImGui_SameLine(ctx)
  if draw_setup_section_button(ctx, "Targets", "control_room_setup_targets", state.setup_tab == "targets", tab_w) then state.setup_tab = "targets" end
  if r.ImGui_Separator then r.ImGui_Separator(ctx) end
  if state.setup_tab == "monitors" then
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(180))
      local slider_theme_count = push_setup_slider_theme(ctx)
      local dim_changed, dim_value = r.ImGui_SliderDouble(ctx, "Dim dB##control_room_dim_db", tonumber(settings.dim_db) or defaults.dim_db, -30, -3, "%.0f dB")
      pop_setup_slider_theme(ctx, slider_theme_count)
      if dim_changed then
        settings.dim_db = dim_value
        if app.save_settings then app.save_settings() end
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Add Monitor Output", UIScale.text_button_w(ctx, "Add Monitor Output", 150, 10), 0) then add_monitor_output(master, outputs, targets) end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Create a new master hardware output send") end
      if #outputs == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No master hardware outputs configured.")
      elseif r.ImGui_BeginChild(ctx, "##control_room_setup_outputs", 0, 0, 0) then
        for _, output in ipairs(outputs) do
          r.ImGui_PushID(ctx, "setup_monitor_" .. tostring(output.index))
          local volume = read_monitor_volume(master, output.index)
          local muted = read_monitor_mute(master, output.index)
          local source = monitor_send_source(master, output.index)
          local mode = get_monitor_mode(settings, output.target)
          local alias = monitor_alias(settings, output.target) or ""
          r.ImGui_TextColored(ctx, Theme.colors.text, "Monitor " .. tostring(output.index + 1))
          r.ImGui_SameLine(ctx)
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(output.name or "Hardware Out") .. " | " .. monitor_mode_text(output) .. " | " .. monitor_mode_label(mode) .. " | " .. tostring(source.name or "Master 1 / 2") .. " | " .. format_db(volume or 1, settings))
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Alias")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(310))
          local alias_changed, alias_value = r.ImGui_InputText(ctx, "##monitor_alias", alias)
          if alias_changed then write_monitor_alias(app, settings, output.target, alias_value) end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, "Clear##monitor_alias_clear", UIScale.text_button_w(ctx, "Clear", 54, 8), 0) then clear_monitor_alias(app, settings, output.target) end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear monitor alias") end
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Output")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
          if #targets > 0 and r.ImGui_BeginCombo(ctx, "##monitor_destination", tostring(output.name or "Hardware Out")) then
            for _, target in ipairs(targets) do
              local selected = target_matches_output(target, output)
              if r.ImGui_Selectable(ctx, tostring(target.name or "Output"), selected) then
                if write_monitor_destination(master, output.index, target) then write_monitor_mode(app, settings, master, output.index, target, mode, source) end
              end
              if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
          end
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Source")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
          if #source_targets > 0 and r.ImGui_BeginCombo(ctx, "##monitor_source", tostring(source.name or "Master 1 / 2")) then
            for _, target in ipairs(source_targets) do
              local selected = source_targets_match(source, target)
              if r.ImGui_Selectable(ctx, tostring(target.name or "Source"), selected) then
                if write_monitor_source(master, output.index, target) then write_monitor_mode(app, settings, master, output.index, output.target, mode, target) end
              end
              if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Choose the master channel pair feeding this monitor") end
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Mode")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
          if r.ImGui_BeginCombo(ctx, "##monitor_mode", monitor_mode_label(mode)) then
            for _, next_mode in ipairs(MONITOR_MODES) do
              local selected = mode == next_mode
              if r.ImGui_Selectable(ctx, monitor_mode_label(next_mode), selected) then write_monitor_mode(app, settings, master, output.index, output.target, next_mode, source) end
              if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Choose stereo, mono sum, source check or physical speaker side") end
          if r.ImGui_Button(ctx, muted and "Unmute##monitor_setup_mute" or "Mute##monitor_setup_mute", UIScale.text_button_w(ctx, muted and "Unmute" or "Mute", 82, 8), 0) then write_monitor_mute(master, output.index, muted == false) end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, "Remove##monitor_setup_remove", UIScale.text_button_w(ctx, "Remove", 82, 8), 0) then remove_monitor_output(master, output.index) end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove this master hardware output send") end
          if r.ImGui_Separator then r.ImGui_Separator(ctx) end
          r.ImGui_PopID(ctx)
        end
        r.ImGui_EndChild(ctx)
      end
  end
  if state.setup_tab == "cues" then
      if r.ImGui_Button(ctx, "Add Cue", UIScale.text_button_w(ctx, "Add Cue", 86, 8), 0) then add_cue_output(app, settings, targets) end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Create a managed Control Room cue track") end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Clean Stale", UIScale.text_button_w(ctx, "Clean Stale", 104, 8), 0) then cleanup_stale_cue_sends(app, settings) end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove stale cue records and sends to unmanaged cue tracks") end
      if state.cue_cleanup_status then r.ImGui_TextColored(ctx, Theme.colors.text_dim, state.cue_cleanup_status) end
      if #cues == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No cue outputs configured.")
      elseif r.ImGui_BeginChild(ctx, "##control_room_setup_cues", 0, 0, 0) then
        for _, cue in ipairs(cues) do
          r.ImGui_PushID(ctx, "setup_cue_" .. tostring(cue.index))
          local track = cue.track
          local muted = read_track_mute(track)
          local volume = read_track_volume(track)
          local feed_count = cue_feed_count(settings, track)
          local output_mode = cue_output_mode(cue)
          local alias = clean_alias(cue.record and cue.record.alias) or ""
          r.ImGui_TextColored(ctx, Theme.colors.text, cue_label(cue))
          r.ImGui_SameLine(ctx)
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, (valid_track(track) and tostring(cue.name or "Cue Output") or "Cue track missing") .. " | " .. cue_output_mode_label(output_mode) .. " | Feeds: " .. tostring(feed_count) .. " | " .. format_db(volume or 1, settings))
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Alias")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(310))
          local alias_changed, alias_value = r.ImGui_InputText(ctx, "##cue_alias", alias)
          if alias_changed then write_cue_alias(app, settings, cue, alias_value) end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, "Clear##cue_alias_clear", UIScale.text_button_w(ctx, "Clear", 54, 8), 0) then write_cue_alias(app, settings, cue, "") end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear cue alias") end
          if valid_track(track) then
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Output")
            r.ImGui_SameLine(ctx, UIScale.round(64))
            r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
            if #targets > 0 and r.ImGui_BeginCombo(ctx, "##cue_destination", tostring(cue.name or "Cue Output")) then
              for _, target in ipairs(targets) do
                local selected = target_matches_output(target, cue)
                if r.ImGui_Selectable(ctx, tostring(target.name or "Output"), selected) then
                  if write_cue_destination(track, target) then write_cue_output_mode(app, cue, output_mode) end
                end
                if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
              end
              r.ImGui_EndCombo(ctx)
            end
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Mode")
            r.ImGui_SameLine(ctx, UIScale.round(64))
            r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
            if r.ImGui_BeginCombo(ctx, "##cue_output_mode", cue_output_mode_label(output_mode)) then
              for _, mode in ipairs(CUE_OUTPUT_MODES) do
                local selected = output_mode == mode
                if r.ImGui_Selectable(ctx, cue_output_mode_label(mode), selected) then write_cue_output_mode(app, cue, mode) end
                if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
              end
              r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Choose stereo or mono-summed cue output") end
            if r.ImGui_Button(ctx, muted and "Unmute##cue_setup_mute" or "Mute##cue_setup_mute", UIScale.text_button_w(ctx, muted and "Unmute" or "Mute", 82, 8), 0) then write_track_mute(track, muted == false, "Control Room: Cue mute") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Sync##cue_setup_sync", UIScale.text_button_w(ctx, "Sync", 82, 8), 0) then sync_cue_output(settings, cue) end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add missing main mix sends to this cue") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Mix##cue_setup_mix", UIScale.text_button_w(ctx, "Mix", 70, 8), 0) then
              local cue_guid = cue.record and cue.record.guid or ""
              settings.cue_mix_active_guid = cue_guid
              state.setup_tab = "mix"
              if app.save_settings then app.save_settings() end
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Open cue mix controls") end
            r.ImGui_SameLine(ctx)
          end
          if r.ImGui_Button(ctx, "Remove##cue_setup_remove", UIScale.text_button_w(ctx, "Remove", 82, 8), 0) then remove_cue_output(app, settings, cue) end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove this cue output") end
          if r.ImGui_Separator then r.ImGui_Separator(ctx) end
          r.ImGui_PopID(ctx)
        end
        r.ImGui_EndChild(ctx)
      end
  end
  if state.setup_tab == "mix" then
      if #cues == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No cue outputs configured. Add a cue first.")
      else
        local active_guid = settings.cue_mix_active_guid or ""
        local active_cue = nil
        for _, cue in ipairs(cues) do
          local guid = cue.record and cue.record.guid or ""
          if guid ~= "" and guid == active_guid and valid_track(cue.track) then active_cue = cue; break end
        end
        if not active_cue then
          for _, cue in ipairs(cues) do
            if valid_track(cue.track) then active_cue = cue; break end
          end
          if active_cue and active_cue.record and active_guid ~= active_cue.record.guid then
            settings.cue_mix_active_guid = active_cue.record.guid or ""
            if app.save_settings then app.save_settings() end
          end
        end
        if not active_cue then
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No valid cue track available.")
        else
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(190))
          if r.ImGui_BeginCombo(ctx, "Cue##control_room_mix_cue", cue_label(active_cue)) then
            for _, cue in ipairs(cues) do
              if valid_track(cue.track) then
                local guid = cue.record and cue.record.guid or ""
                local selected = guid ~= "" and guid == (settings.cue_mix_active_guid or "")
                if r.ImGui_Selectable(ctx, cue_label(cue), selected) then
                  settings.cue_mix_active_guid = guid
                  if app.save_settings then app.save_settings() end
                end
                if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
              end
            end
            r.ImGui_EndCombo(ctx)
          end
          r.ImGui_SameLine(ctx)
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Mode")
          r.ImGui_SameLine(ctx)
          local active_cue_guid = cue_guid_value(active_cue)
          local prefader = cue_send_prefader_for_guid(settings, active_cue_guid)
          if draw_setup_section_button(ctx, "Pre", "control_room_cue_mode_pre", prefader, UIScale.text_button_w(ctx, "Pre", 48, 6)) then
            set_cue_send_prefader_for_guid(settings, active_cue_guid, true)
            if app.save_settings then app.save_settings() end
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "New cue sends ignore main fader moves") end
          r.ImGui_SameLine(ctx)
          if draw_setup_section_button(ctx, "Post", "control_room_cue_mode_post", not prefader, UIScale.text_button_w(ctx, "Post", 54, 6)) then
            set_cue_send_prefader_for_guid(settings, active_cue_guid, false)
            if app.save_settings then app.save_settings() end
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "New cue sends follow main fader and pan") end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, "Apply##control_room_cue_mode_apply", UIScale.text_button_w(ctx, "Apply", 58, 8), 0) then
            state.apply_send_mode_cue_guid = cue_guid_value(active_cue)
            r.ImGui_OpenPopup(ctx, "Apply Cue Send Mode")
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Apply current mode to existing sends for this cue") end
          if r.ImGui_Button(ctx, "Sync##control_room_mix_sync", UIScale.text_button_w(ctx, "Sync", 82, 8), 0) then sync_cue_output(settings, active_cue) end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add missing sends to this cue") end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, "Copy Main -> Cue##control_room_mix_copy", UIScale.text_button_w(ctx, "Copy Main -> Cue", 148, 10), 0) then copy_main_mix_to_cue(settings, active_cue) end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy track volume and pan to cue sends") end
          if cue_listen_entry(cue_guid_value(active_cue)) then
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds({ Theme.colors.accent, Theme.colors.warning }, Theme.colors.text, nil, 4.5))
            local all_clicked = r.ImGui_Button(ctx, "ALL##control_room_mix_listen_all", UIScale.text_button_w(ctx, "ALL", 48, 6), 0)
            r.ImGui_PopStyleColor(ctx, 4)
            if all_clicked then restore_cue_listen(active_cue) end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Restore all cue sends") end
          end
          local sources = cue_source_tracks(settings)
          if #sources == 0 then
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No source tracks available for cue mix.")
          elseif r.ImGui_BeginChild(ctx, "##control_room_cue_mix_sources", 0, 0, 0) then
            for _, source in ipairs(sources) do
              local track = source.track
              r.ImGui_PushID(ctx, "cue_mix_" .. tostring(source.guid or source.name))
              local send_volume = read_cue_send_volume(track, active_cue.track)
              local send_pan = read_cue_send_pan(track, active_cue.track)
              local send_mute = read_cue_send_mute(track, active_cue.track)
              local shown_volume = send_volume or source.volume or 1
              local shown_db = linear_to_db(shown_volume, settings.min_db or defaults.min_db)
              local shown_pan = send_pan or source.pan or 0
              r.ImGui_TextColored(ctx, Theme.colors.text, ellipsize_text(ctx, source.name, UIScale.round(190)))
              r.ImGui_SameLine(ctx, UIScale.round(205))
              local listen_active = cue_listen_matches(active_cue, source)
              if listen_active then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds({ Theme.colors.accent, Theme.colors.warning }, Theme.colors.text, nil, 4.5))
              end
              local listen_clicked = r.ImGui_Button(ctx, "S##cue_mix_listen", UIScale.text_button_w(ctx, "S", 28, 4), 0)
              if listen_active then r.ImGui_PopStyleColor(ctx, 4) end
              if listen_clicked then toggle_cue_listen(settings, active_cue, source) end
              if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, listen_active and "Restore cue listen" or "Listen to this source in this cue") end
              r.ImGui_SameLine(ctx)
              if r.ImGui_Button(ctx, send_mute and "Muted##cue_mix_mute" or "On##cue_mix_mute", UIScale.text_button_w(ctx, send_mute and "Muted" or "On", 58, 8), 0) then write_cue_send_mute(track, active_cue.track, not send_mute, settings) end
              if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, send_mute and "Unmute cue send" or "Mute cue send") end
              r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Vol")
              r.ImGui_SameLine(ctx, UIScale.round(42))
              r.ImGui_SetNextItemWidth(ctx, UIScale.round(210))
              local slider_theme_count = push_setup_slider_theme(ctx)
              local volume_changed, next_db = r.ImGui_SliderDouble(ctx, "##cue_mix_volume", shown_db, settings.min_db or defaults.min_db, settings.max_db or defaults.max_db, "%.1f dB")
              local volume_reset = cue_mix_item_right_clicked(ctx)
              if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Right-click to reset to 0 dB") end
              pop_setup_slider_theme(ctx, slider_theme_count)
              if volume_reset then write_cue_send_volume(track, active_cue.track, 1, settings) elseif volume_changed then write_cue_send_volume(track, active_cue.track, db_to_linear(next_db, settings.min_db or defaults.min_db, settings.max_db or defaults.max_db), settings) end
              r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Pan")
              r.ImGui_SameLine(ctx, UIScale.round(42))
              r.ImGui_SetNextItemWidth(ctx, UIScale.round(210))
              slider_theme_count = push_setup_slider_theme(ctx)
              local pan_changed, next_pan = r.ImGui_SliderDouble(ctx, "##cue_mix_pan", shown_pan, -1, 1, "%.2f")
              local pan_reset = cue_mix_item_right_clicked(ctx)
              if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Right-click to reset to center") end
              pop_setup_slider_theme(ctx, slider_theme_count)
              if pan_reset then write_cue_send_pan(track, active_cue.track, 0, settings) elseif pan_changed then write_cue_send_pan(track, active_cue.track, next_pan, settings) end
              if r.ImGui_Separator then r.ImGui_Separator(ctx) end
              r.ImGui_PopID(ctx)
            end
            r.ImGui_EndChild(ctx)
          end
        end
      end
  end
  draw_apply_send_mode_popup(app, settings)
  if state.setup_tab == "targets" then
      if #targets == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No device outputs found.")
      elseif r.ImGui_BeginChild(ctx, "##control_room_setup_targets", 0, 0, 0) then
        for _, target in ipairs(targets) do
          local kind = target.rearoute and "ReaRoute" or "Hardware"
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(target.name or "Output") .. " | " .. kind .. " " .. (target.mono and "Mono" or "Stereo"))
        end
        r.ImGui_EndChild(ctx)
      end
  end
  r.ImGui_End(ctx)
end

local function draw_lanes(app, settings, lanes, footer_height)
  local ctx = app.ctx
  local avail_width, avail_height = r.ImGui_GetContentRegionAvail(ctx)
  local spacing = UIScale.round(8)
  local columns = 1
  if avail_width >= UIScale.round(390) then columns = 4 elseif avail_width >= UIScale.round(300) then columns = 3 elseif avail_width >= UIScale.round(190) then columns = 2 end
  columns = math.max(1, math.min(columns, #lanes))
  local lane_width = math.max(UIScale.round(78), ((avail_width or UIScale.round(320)) - spacing * (columns - 1)) / columns)
  local reserved_height = math.max(0, tonumber(footer_height) or 0)
  local lane_height = math.max(UIScale.round(190), math.min(UIScale.round(245), (avail_height or UIScale.round(245)) - reserved_height - UIScale.round(4)))
  if r.ImGui_BeginChild(ctx, "##control_room_lanes", 0, -reserved_height, 0) then
    for index, lane in ipairs(lanes) do
      draw_lane(app, lane, settings, lane_width, lane_height)
      if index % columns ~= 0 and index < #lanes then r.ImGui_SameLine(ctx) end
    end
    r.ImGui_EndChild(ctx)
  end
end

function M.init(app)
  local settings = ensure_settings(app)
  state.meter_open = settings.meter_open == true
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  state.meter_open = settings.meter_open == true
  if not state.cue_names_synced then
    sync_cue_track_names(settings)
    state.cue_names_synced = true
  end
  settings.min_db = tonumber(settings.min_db) or defaults.min_db
  settings.max_db = tonumber(settings.max_db) or defaults.max_db
  if settings.max_db <= settings.min_db then settings.max_db = settings.min_db + 12 end
  if state.pending_meter_reset then
    local pending = state.pending_meter_reset
    state.pending_meter_reset = nil
    local track = pending.source_id == "master" and r.GetMasterTrack(0) or track_by_guid(pending.track_guid)
    local ok, err = pcall(MeterEngine.reset_source, { id = pending.source_id, track = track }, settings)
    if not ok and app then app.status = "Meter reset failed: " .. tostring(err) end
  end
  local lanes = build_lanes(app, settings)
  local footer_height = state.meter_open and 0 or (r.ImGui_GetFrameHeight(ctx) + UIScale.round(22))
  if not state.meter_open then
    draw_header(app, lanes)
    r.ImGui_Dummy(ctx, UIScale.round(1), UIScale.round(4))
  end
  if state.meter_open then
    draw_meter_panel(app, settings, footer_height)
  else
    draw_lanes(app, settings, lanes, footer_height)
  end
  if not state.meter_open then
    draw_control_footer(app, settings)
    draw_setup_popup(app, settings)
    draw_meter_settings_popup(app, settings)
  else
    draw_meter_settings_popup(app, settings)
  end
end

return M