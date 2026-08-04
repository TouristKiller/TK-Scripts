local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")
local MeterEngine = require("core.meter_engine")
local Layouts = require("core.channel_layouts")

local M = {
  id = "control_room",
  title = "Control Room",
  icon = "CTL",
  version = "0.2.0"
}

local defaults = {
  min_db = -60,
  max_db = 12,
  show_master = true,
  show_metronome = true,
  show_selected_track = true,
  show_monitor = true,
  show_cues = true,
  show_media_browser = true,
  show_lane_groups = true,
  meter_show_target = true,
  meter_target_tolerance = 1,
  meter_bar_scale = 1,
  meter_info_scale = 1,
  meter_bar_source = "peak",
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
  setup_window = {},
  master_layout = "stereo",
  monitor_formats = {},
  fold_center_db = -3,
  fold_surround_db = -3,
  fold_lfe = false,
  fold_lfe_db = 0,
  fold_trim_db = 0,
  monitor_crossover_hz = 120,
  mono_restore = {},
  settings_version = 4
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
  apply_send_mode_cue_guid = nil,
  fold_status = nil,
  fold_sync_time = 0
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
local MONITOR_MODE_LABELS = {
  full = "Full", mono = "Mono Sum", fold_stereo = "Fold to Stereo",
  left_speaker = "L Speaker", right_speaker = "R Speaker",
  mid = "Mid (M)", side = "Side (S)", low = "Low Band", high = "High Band"
}
-- Modes fed by the downmix JSFX, in the order their output pairs are laid out
-- past the bed. One instance serves all of them, a pair each, so two monitors
-- can check two different things without a second plugin.
local MONITOR_BUS_MODES = { "fold_stereo", "mid", "side", "low", "high" }
-- Modes stored by earlier versions, mapped onto the layout aware names.
local LEGACY_MONITOR_MODES = {
  stereo = "full", ["mono sum"] = "mono", sum = "mono",
  left = "speaker:0", l = "speaker:0", left_source = "speaker:0", ["l source"] = "speaker:0",
  right = "speaker:1", r = "speaker:1", right_source = "speaker:1", ["r source"] = "speaker:1",
  ["left speaker"] = "left_speaker", ["l speaker"] = "left_speaker",
  ["right speaker"] = "right_speaker", ["r speaker"] = "right_speaker"
}
local FOLD_PLUGIN_MATCH = "TK Control Room Downmix"
-- Paths first, desc last, mirroring MeterEngine.plugin_names. The first entry is
-- the ReaPack install path once this effect is added to index.xml; until then
-- only the desc entries resolve.
local FOLD_PLUGIN_NAMES = {
  "JS: TK Scripts/TK Workbench/TK Scripts/Mixer/TK_Control_Room_Downmix.jsfx",
  "JS: TK Scripts/Mixer/TK_Control_Room_Downmix.jsfx",
  "JS: TK Control Room Downmix",
  "JS: TK_Control_Room_Downmix"
}
-- enable is the first of five on/off sliders, one per mode in MONITOR_BUS_MODES.
local FOLD_PARAMS = { layout = 0, source = 1, fold = 2, center = 3, surround = 4, lfe_on = 5, lfe = 6, trim = 7, run = 8, enable = 9, crossover = 14 }
local MAX_TRACK_CHANNELS = 128

function cr_bus_index(mode)
  for index, id in ipairs(MONITOR_BUS_MODES) do
    if id == mode then return index - 1 end
  end
  return nil
end

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy_default(child) end
  return result
end

-- Monitor keys used to encode the send width ("hardware:stereo:0"). Width is
-- now read from I_SRCCHAN, so the key only identifies the destination and stays
-- stable when the format changes.
local function migrate_monitor_keys(settings)
  local changed = false
  for _, field in ipairs({ "monitor_aliases", "monitor_modes" }) do
    local table_value = settings[field]
    if type(table_value) == "table" then
      -- Collect first: adding keys during a pairs() walk skips entries.
      local renames = {}
      for key, value in pairs(table_value) do
        local kind, channel = tostring(key):match("^(%a+):%a+:(%d+)$")
        if kind and channel then renames[#renames + 1] = { old = key, new = kind .. ":" .. channel, value = value } end
      end
      for _, rename in ipairs(renames) do
        if table_value[rename.new] == nil then table_value[rename.new] = rename.value end
        table_value[rename.old] = nil
        changed = true
      end
    end
  end
  return changed
end

local function ensure_settings(app)
  app.settings.control_room = app.settings.control_room or {}
  local settings = app.settings.control_room
  local changed = false
  local prior_version = tonumber(settings.settings_version) or 1
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  if prior_version < 3 then
    if migrate_monitor_keys(settings) then changed = true end
    changed = true
  end
  if prior_version < 4 then
    -- The old default attenuated LFE by 10 dB on fold-down, on a slider that
    -- could not reach the +10 dB the channel is actually reproduced at. Only
    -- lift values still sitting on that default, never a deliberate choice.
    if tonumber(settings.fold_lfe_db) == -10 then settings.fold_lfe_db = 0 end
    changed = true
  end
  if changed then settings.settings_version = 4 end
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

local function track_channel_count(track)
  if not valid_track(track) or not r.GetMediaTrackInfo_Value then return 2 end
  local ok, value = pcall(r.GetMediaTrackInfo_Value, track, "I_NCHAN")
  if not ok then return 2 end
  return math.max(2, math.min(MAX_TRACK_CHANNELS, math.floor(tonumber(value) or 2)))
end

-- Widens a track when a layout needs more channels. Never narrows: the user may
-- be using the extra channels for something the Control Room knows nothing of.
local function grow_track_channel_count(track, channels, label)
  if not valid_track(track) or not r.SetMediaTrackInfo_Value then return false end
  channels = math.max(2, math.min(MAX_TRACK_CHANNELS, math.floor(tonumber(channels) or 2)))
  if channels % 2 == 1 then channels = channels + 1 end
  if track_channel_count(track) >= channels then return true end
  return write_with_undo(label or "Control Room: Set track channels", function()
    return r.SetMediaTrackInfo_Value(track, "I_NCHAN", channels)
  end)
end

local function read_channel_peak(track, channel)
  if not valid_track(track) or not r.Track_GetPeakInfo then return 0 end
  local ok, value = pcall(r.Track_GetPeakInfo, track, math.max(0, math.floor(tonumber(channel) or 0)))
  return ok and math.abs(tonumber(value) or 0) or 0
end

local function read_channel_peaks(track, base, count)
  local peaks = {}
  base = math.max(0, math.floor(tonumber(base) or 0))
  count = math.max(1, math.floor(tonumber(count) or 2))
  for index = 1, count do peaks[index] = read_channel_peak(track, base + index - 1) end
  return peaks
end

local function read_track_peak(track, base, count)
  if not valid_track(track) then return 0 end
  count = count or math.min(track_channel_count(track), 8)
  local highest = 0
  for _, value in ipairs(read_channel_peaks(track, base or 0, count)) do
    if value > highest then highest = value end
  end
  return highest
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

local function output_target_name(channel, width, mono, rearoute)
  channel = math.max(0, math.floor(tonumber(channel) or 0))
  width = mono and 1 or math.max(1, math.floor(tonumber(width) or 2))
  if rearoute then
    return "ReaRoute " .. Layouts.channel_span(channel, { channels = width })
  end
  if width <= 1 then return output_channel_name(channel) end
  if width == 2 then return output_channel_name(channel) .. " / " .. output_channel_name(channel + 1) end
  return output_channel_name(channel) .. " - " .. output_channel_name(channel + width - 1)
end

local function add_output_target(targets, channel, width, mono, rearoute)
  width = mono and 1 or math.max(1, math.floor(tonumber(width) or 2))
  targets[#targets + 1] = {
    channel = channel,
    width = width,
    mono = mono == true,
    rearoute = rearoute == true,
    name = output_target_name(channel, width, mono == true, rearoute == true)
  }
end

-- REAPER takes the destination width from I_SRCCHAN, so the usable destination
-- base channels depend on how wide the send is. The mono entries set the
-- I_DSTCHAN mono bit, which collapses the send onto a single hardware channel.
local function available_output_targets(outputs, layout)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  local width = layout.channels
  local step = width == 1 and 1 or 2
  local targets = {}
  local count = 0
  if r.GetNumAudioOutputs then
    local ok, value = pcall(r.GetNumAudioOutputs)
    count = ok and math.floor(tonumber(value) or 0) or 0
  end
  for channel = 0, count - width, step do
    add_output_target(targets, channel, width, false, false)
  end
  if width > 1 then
    for channel = 0, count - 1 do
      add_output_target(targets, channel, 1, true, false)
    end
  end
  if #targets == 0 then add_output_target(targets, 0, 1, true, false) end
  local rearoute_count = 0
  for _, output in ipairs(outputs or {}) do
    local target = output and output.target or nil
    if target and target.rearoute then rearoute_count = math.max(rearoute_count, target.channel + (target.width or 2)) end
  end
  rearoute_count = math.max(rearoute_count, REAROUTE_CHANNELS)
  for channel = 0, rearoute_count - width, step do
    add_output_target(targets, channel, width, false, true)
  end
  if width > 1 then
    for channel = 0, rearoute_count - 1 do
      add_output_target(targets, channel, 1, true, true)
    end
  end
  return targets
end

local function source_target_name(channel, layout)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  local name = "Master " .. Layouts.channel_span(channel, layout)
  if layout.channels > 2 then name = name .. " (" .. layout.label .. ")" end
  return name
end

local function add_source_target(targets, channel, layout)
  targets[#targets + 1] = {
    channel = channel,
    layout = layout.id,
    width = layout.channels,
    mono = layout.channels == 1,
    name = source_target_name(channel, layout)
  }
end

-- Pass a layout to list only the base channels valid for that format, or omit
-- it to list every format that fits inside the master track.
local function available_source_targets(master, layout)
  local targets = {}
  local count = track_channel_count(master)
  local list
  if layout then
    layout = type(layout) == "string" and Layouts.by_id(layout) or layout
    list = layout and { layout } or {}
  else
    list = Layouts.fitting(count)
  end
  for _, item in ipairs(list) do
    for _, channel in ipairs(Layouts.offsets(count, item)) do
      add_source_target(targets, channel, item)
    end
  end
  return targets
end

-- I_SRCCHAN packs the width above the channel offset, so a 6 channel send
-- reads back as 3072 + offset. Masking only the mono bit reported those as
-- mono and 4 channel sends as stereo.
local function monitor_send_source(master, index)
  if valid_track(master) and index and r.GetTrackSendInfo_Value then
    local ok, raw_channel = pcall(r.GetTrackSendInfo_Value, master, 1, index, "I_SRCCHAN")
    if ok and type(raw_channel) == "number" then
      raw_channel = math.floor(raw_channel)
      if raw_channel < 0 then return { raw = raw_channel, channel = -1, layout = nil, width = 0, mono = false, name = "None" } end
      local channel, layout = Layouts.decode_src(raw_channel)
      return {
        raw = raw_channel,
        channel = channel,
        layout = layout.id,
        width = layout.channels,
        mono = layout.channels == 1,
        name = source_target_name(channel, layout)
      }
    end
  end
  local layout = Layouts.by_id("stereo")
  return { raw = 0, channel = 0, layout = layout.id, width = layout.channels, mono = false, name = source_target_name(0, layout) }
end

local function monitor_send_target(master, index, width)
  if valid_track(master) and index and r.GetTrackSendInfo_Value then
    local ok, raw_channel = pcall(r.GetTrackSendInfo_Value, master, 1, index, "I_DSTCHAN")
    if ok and type(raw_channel) == "number" then
      raw_channel = math.floor(raw_channel)
      local channel = raw_channel & 0x1FF
      local mono = (raw_channel & 1024) == 1024
      local rearoute = (raw_channel & 512) == 512
      local dest_width = mono and 1 or math.max(1, math.floor(tonumber(width) or 2))
      local name = output_target_name(channel, dest_width, mono, rearoute)
      return { raw = raw_channel, channel = channel, width = dest_width, mono = mono, rearoute = rearoute, name = name }
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
    local source = monitor_send_source(master, index)
    local target = monitor_send_target(master, index, source.width)
    outputs[#outputs + 1] = { index = index, source = source, target = target, name = target and target.name or monitor_send_name(master, index) }
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
  return left.channel == right.channel and left.mono == right.mono and left.rearoute == right.rearoute and (left.width or 2) == (right.width or 2)
end

-- Identifies the destination only. Width used to be part of this key, which
-- meant aliases and modes were lost whenever the format changed.
local function monitor_target_key(target)
  if not target then return nil end
  return (target.rearoute and "rearoute" or "hardware") .. ":" .. tostring(target.channel or 0)
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

-- Cue output formats are stored as layout ids. Older configs hold "stereo" or
-- "mono", which are layout ids too, so they load unchanged.
local function cue_output_layout_id(mode)
  mode = tostring(mode or ""):lower()
  if mode == "mono sum" or mode == "sum" then return "mono" end
  return Layouts.by_id(mode) and mode or "stereo"
end

local function cue_output_layout(cue)
  return Layouts.by_id(cue_output_layout_id(cue and cue.record and cue.record.output_mode)) or Layouts.by_id("stereo")
end

local function cue_output_mode_label(mode)
  local layout = Layouts.by_id(cue_output_layout_id(mode)) or Layouts.by_id("stereo")
  if layout.channels == 1 then return "Mono Sum" end
  return layout.label
end

local function cue_output_mode_options()
  local options = {}
  for _, layout in ipairs(Layouts.layouts) do options[#options + 1] = layout.id end
  return options
end

local function cue_outputs(settings)
  local cues = {}
  local records = type(settings.cue_outputs) == "table" and settings.cue_outputs or {}
  for index, record in ipairs(records) do
    local track = track_by_guid(record.guid)
    local layout = Layouts.by_id(cue_output_layout_id(record.output_mode)) or Layouts.by_id("stereo")
    local target = valid_track(track) and monitor_send_target(track, 0, layout.channels) or nil
    cues[#cues + 1] = {
      index = index,
      record = record,
      track = track,
      layout = layout.id,
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

local function cue_output_mode(cue)
  return cue_output_layout(cue).id
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
  local layout = Layouts.by_id(cue_output_layout_id(mode)) or Layouts.by_id("stereo")
  grow_track_channel_count(cue.track, layout.channels, "Control Room: Widen cue track")
  local ok = write_with_undo("Control Room: Cue output mode", function()
    local index = ensure_cue_send(cue.track, nil)
    if not index then return false end
    -- Mono is a sum of the stereo feed rather than a one channel source.
    local src_layout = layout.channels == 1 and Layouts.by_id("stereo") or layout
    local src_ok = r.SetTrackSendInfo_Value(cue.track, 1, index, "I_SRCCHAN", Layouts.encode_src(0, src_layout))
    local mono_ok = r.SetTrackSendInfo_Value(cue.track, 1, index, "B_MONO", layout.channels == 1 and 1 or 0)
    return src_ok ~= false and mono_ok ~= false
  end)
  if not ok then return false end
  cue.record.output_mode = layout.id
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

-- A monitor's format is remembered rather than inferred, because a soloed
-- speaker leaves a mono send behind that no longer reveals the group it
-- belongs to. Falls back to whatever the send currently says.
local function monitor_format(settings, target, source)
  local key = monitor_target_key(target)
  local formats = type(settings and settings.monitor_formats) == "table" and settings.monitor_formats or {}
  local record = key and formats[key] or nil
  local layout = record and Layouts.by_id(record.layout) or nil
  if not layout and source and source.layout then layout = Layouts.by_id(source.layout) end
  layout = layout or Layouts.by_id(settings and settings.master_layout) or Layouts.by_id("stereo")
  local base = record and tonumber(record.base) or (source and tonumber(source.channel)) or 0
  base = math.max(0, math.floor(base))
  if layout.channels > 1 and base % 2 == 1 then base = base - 1 end
  return layout, base
end

local function set_monitor_format(app, settings, target, layout, base)
  local key = monitor_target_key(target)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  if not key or not layout then return false end
  settings.monitor_formats = type(settings.monitor_formats) == "table" and settings.monitor_formats or {}
  settings.monitor_formats[key] = { layout = layout.id, base = math.max(0, math.floor(tonumber(base) or 0)) }
  if app and app.save_settings then app.save_settings() end
  return true
end

-- The five pair switches arrived in JSFX 0.3. An instance still running an
-- older build only has the fold-down, and says so here.
function cr_bus_fx_supports_pairs(track, index)
  if not r.TrackFX_GetParamName then return false end
  local named, name = r.TrackFX_GetParamName(track, index, FOLD_PARAMS.crossover, "")
  return named == true and tostring(name):find("Crossover", 1, true) ~= nil
end

function cr_bus_enable_param(mode)
  return FOLD_PARAMS.enable + (cr_bus_index(mode) or 0)
end

local function find_fold_fx(track)
  if not valid_track(track) or not r.TrackFX_GetCount or not r.TrackFX_GetFXName then return nil end
  for index = 0, (r.TrackFX_GetCount(track) or 0) - 1 do
    local ok, name = r.TrackFX_GetFXName(track, index, "")
    if ok and tostring(name or ""):find(FOLD_PLUGIN_MATCH, 1, true) then
      return index
    end
  end
  return nil
end

-- The master needs one downmix, not one per check picked.
function cr_drop_extra_bus_fx(track, keep)
  if not r.TrackFX_Delete or not keep then return keep end
  for index = (r.TrackFX_GetCount(track) or 0) - 1, 0, -1 do
    if index ~= keep then
      local ok, name = r.TrackFX_GetFXName(track, index, "")
      if ok and tostring(name or ""):find(FOLD_PLUGIN_MATCH, 1, true) then
        r.TrackFX_Delete(track, index)
        if index < keep then keep = keep - 1 end
      end
    end
  end
  return keep
end

-- Each mode gets its own pair, laid out on the first even channel past the bed,
-- so the feed to the main outputs is left untouched and two modes can run at
-- once without writing over each other.
local function fold_offset_for(layout, base, mode)
  local offset = math.max(0, math.floor(tonumber(base) or 0)) + (layout and layout.channels or 2)
  if offset % 2 == 1 then offset = offset + 1 end
  return offset + 2 * (cr_bus_index(mode or "fold_stereo") or 0)
end

local function set_fold_param(track, fx_index, param, value)
  if not r.TrackFX_GetParam or not r.TrackFX_SetParam then return end
  -- Only the first return value: TrackFX_GetParam also yields min and max, and
  -- passing those on turns tonumber into its two argument base form.
  local raw = r.TrackFX_GetParam(track, fx_index, param)
  local current = tonumber(raw)
  if current and math.abs(current - value) < 0.001 then return end
  r.TrackFX_SetParam(track, fx_index, param, value)
end

-- Returns the mode's output pair base channel, or nil plus a status message.
local function ensure_fold_bus(app, settings, master, layout, base, install, mode)
  if not valid_track(master) then return nil, "No master track" end
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  mode = mode or "fold_stereo"
  if mode == "fold_stereo" and layout.channels <= 2 then return nil, "Fold-down needs a multichannel format" end
  local index = find_fold_fx(master)
  if not index then
    if not install or not r.TrackFX_AddByName then return nil, "The downmix JSFX is not on the master" end
    for _, name in ipairs(FOLD_PLUGIN_NAMES) do
      local added = r.TrackFX_AddByName(master, name, false, -1)
      if added and added >= 0 then index = added; break end
    end
    if not index then return nil, "TK_Control_Room_Downmix.jsfx not found - reinstall TK Workbench in ReaPack and restart REAPER" end
  end
  index = cr_drop_extra_bus_fx(master, index)
  local pairs_ok = cr_bus_fx_supports_pairs(master, index)
  if mode ~= "fold_stereo" and not pairs_ok then
    return nil, "The downmix JSFX on the master is an older build - remove it and pick the mode again"
  end
  local offset = fold_offset_for(layout, base, mode)
  grow_track_channel_count(master, offset + 2, "Control Room: Widen master for monitoring")
  set_fold_param(master, index, FOLD_PARAMS.layout, Layouts.jsfx_layout_index[layout.id] or 3)
  set_fold_param(master, index, FOLD_PARAMS.source, base)
  set_fold_param(master, index, FOLD_PARAMS.fold, fold_offset_for(layout, base, "fold_stereo"))
  set_fold_param(master, index, FOLD_PARAMS.center, tonumber(settings.fold_center_db) or defaults.fold_center_db)
  set_fold_param(master, index, FOLD_PARAMS.surround, tonumber(settings.fold_surround_db) or defaults.fold_surround_db)
  set_fold_param(master, index, FOLD_PARAMS.lfe_on, settings.fold_lfe == true and 1 or 0)
  set_fold_param(master, index, FOLD_PARAMS.lfe, tonumber(settings.fold_lfe_db) or defaults.fold_lfe_db)
  set_fold_param(master, index, FOLD_PARAMS.trim, tonumber(settings.fold_trim_db) or defaults.fold_trim_db)
  if pairs_ok then
    set_fold_param(master, index, cr_bus_enable_param(mode), 1)
    set_fold_param(master, index, FOLD_PARAMS.crossover, tonumber(settings.monitor_crossover_hz) or defaults.monitor_crossover_hz)
  end
  set_fold_param(master, index, FOLD_PARAMS.run, 1)
  return offset, nil
end

local function remove_fold_bus(master)
  local index = find_fold_fx(master)
  if not index or not r.TrackFX_Delete then return false end
  return write_with_undo("Control Room: Remove monitor processing", function()
    return r.TrackFX_Delete(master, index)
  end)
end

-- Fold-down is a property of the main mix, not of the monitor listening to it:
-- a stereo monitor is exactly the one that wants it.
local function bed_layout(settings, fallback)
  fallback = type(fallback) == "string" and Layouts.by_id(fallback) or fallback
  return Layouts.by_id(settings and settings.master_layout) or fallback or Layouts.by_id("stereo")
end

local function monitor_mode_key(mode, layout, bed)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  bed = type(bed) == "string" and Layouts.by_id(bed) or bed
  bed = bed or layout
  mode = tostring(mode or ""):lower()
  mode = LEGACY_MONITOR_MODES[mode] or mode
  local speaker = mode:match("^speaker:(%d+)$")
  if speaker then
    local index = tonumber(speaker) or 0
    if index >= layout.channels then return "full" end
    return "speaker:" .. tostring(index)
  end
  if mode == "mono" then return layout.channels > 1 and "mono" or "full" end
  if mode == "fold_stereo" then return (bed.channels > 2 and layout.channels >= 2) and "fold_stereo" or "full" end
  -- The processed modes read a stereo pair, so the monitor has to be able to
  -- play one. The bed can be anything: it is folded down first if it is wider.
  if cr_bus_index(mode) then return layout.channels >= 2 and mode or "full" end
  if mode == "left_speaker" or mode == "right_speaker" then
    return layout.channels == 2 and mode or "full"
  end
  return "full"
end

local function monitor_mode_label(mode, layout, bed)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  local key = monitor_mode_key(mode, layout, bed)
  local speaker = key:match("^speaker:(%d+)$")
  if speaker then return Layouts.speaker(layout, tonumber(speaker)) .. " Only" end
  if key == "full" then return layout.label end
  return MONITOR_MODE_LABELS[key] or layout.label
end

local function monitor_mode_options(layout, bed)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  bed = type(bed) == "string" and Layouts.by_id(bed) or bed
  bed = bed or layout
  local options = { "full" }
  if layout.channels > 1 then options[#options + 1] = "mono" end
  if bed.channels > 2 and layout.channels >= 2 then options[#options + 1] = "fold_stereo" end
  if layout.channels >= 2 then
    for _, mode in ipairs(MONITOR_BUS_MODES) do
      if mode ~= "fold_stereo" then options[#options + 1] = mode end
    end
  end
  if layout.channels > 1 then
    for index = 0, layout.channels - 1 do options[#options + 1] = "speaker:" .. tostring(index) end
  end
  if layout.channels == 2 then
    options[#options + 1] = "left_speaker"
    options[#options + 1] = "right_speaker"
  end
  return options
end

local function get_monitor_mode(settings, target, layout)
  local key = monitor_target_key(target)
  local modes = settings and settings.monitor_modes or nil
  return monitor_mode_key(key and type(modes) == "table" and modes[key] or nil, layout, bed_layout(settings, layout))
end

local function set_monitor_mode(app, settings, target, mode, layout)
  local key = monitor_target_key(target)
  if not key then return false end
  settings.monitor_modes = type(settings.monitor_modes) == "table" and settings.monitor_modes or {}
  settings.monitor_modes[key] = monitor_mode_key(mode, layout, bed_layout(settings, layout))
  if app and app.save_settings then app.save_settings() end
  return true
end

local function monitor_mode_pan(mode)
  if mode == "left_speaker" then return -1 end
  if mode == "right_speaker" then return 1 end
  return 0
end

local function apply_monitor_mode(app, settings, master, index, mode, layout, base)
  if not valid_track(master) or not index or not r.SetTrackSendInfo_Value then return false, nil end
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  base = math.max(0, math.floor(tonumber(base) or 0))
  mode = monitor_mode_key(mode, layout, bed_layout(settings, layout))
  local src_channel, src_layout = base, layout
  local speaker = mode:match("^speaker:(%d+)$")
  if speaker then
    src_channel = base + (tonumber(speaker) or 0)
    src_layout = Layouts.by_id("mono")
  elseif cr_bus_index(mode) then
    -- One bus per mode, derived from the master bed, so every monitor set to
    -- the same check listens to the same pair.
    local bed = bed_layout(settings, layout)
    local offset, status = ensure_fold_bus(app, settings, master, bed, 0, true, mode)
    if not offset then return false, status end
    src_channel = offset
    src_layout = Layouts.by_id("stereo")
  end
  local ok = write_with_undo("Control Room: Monitor mode", function()
    local source_ok = r.SetTrackSendInfo_Value(master, 1, index, "I_SRCCHAN", Layouts.encode_src(src_channel, src_layout))
    local mono_ok = r.SetTrackSendInfo_Value(master, 1, index, "B_MONO", mode == "mono" and 1 or 0)
    local pan_ok = r.SetTrackSendInfo_Value(master, 1, index, "D_PAN", monitor_mode_pan(mode))
    return source_ok ~= false and mono_ok ~= false and pan_ok ~= false
  end)
  return ok, nil
end

local function write_monitor_mode(app, settings, master, index, target, mode, layout, base)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  mode = monitor_mode_key(mode, layout, bed_layout(settings, layout))
  local ok, status = apply_monitor_mode(app, settings, master, index, mode, layout, base)
  state.fold_status = status
  if not ok then return false end
  -- Persist the format alongside the mode: a soloed speaker leaves a mono send
  -- behind, and without the record the monitor would collapse to mono for good.
  set_monitor_format(app, settings, target, layout, base)
  return set_monitor_mode(app, settings, target, mode, layout)
end

-- Applies a format to a monitor: widens the master if needed, rewrites the
-- send and re-applies the current mode against the new layout.
local function write_monitor_layout(app, settings, master, index, target, layout, base)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  if not layout then return false end
  base = math.max(0, math.floor(tonumber(base) or 0))
  grow_track_channel_count(master, base + layout.channels, "Control Room: Widen master")
  if not set_monitor_format(app, settings, target, layout, base) then return false end
  local mode = get_monitor_mode(settings, target, layout)
  return write_monitor_mode(app, settings, master, index, target, mode, layout, base)
end

local function fold_bus_in_use(settings, master, mode)
  if not valid_track(master) then return false end
  mode = mode or "fold_stereo"
  for _, output in ipairs(monitor_outputs(master)) do
    local layout = monitor_format(settings, output.target, output.source)
    if get_monitor_mode(settings, output.target, layout) == mode then return true end
  end
  return false
end

-- Switching the last monitor away from a processed mode leaves the instance in
-- place, where its pair would keep overwriting channels on the master. Switch
-- that pair off instead of deleting the plugin: the user may have tuned the
-- levels, and Setup has an explicit Remove button for real cleanup.
local function sync_fold_bus_run(settings, master)
  if not valid_track(master) then return end
  local index = find_fold_fx(master)
  if not index then return end
  local any = false
  local pairs_ok = cr_bus_fx_supports_pairs(master, index)
  for _, mode in ipairs(MONITOR_BUS_MODES) do
    local used = fold_bus_in_use(settings, master, mode)
    if used then any = true end
    if pairs_ok then set_fold_param(master, index, cr_bus_enable_param(mode), used and 1 or 0) end
  end
  set_fold_param(master, index, FOLD_PARAMS.run, any and 1 or 0)
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

-- Read back rather than remembered: the mode is on the send, so a monitor put
-- back to stereo by hand leaves the button telling the truth.
function cr_monitor_mono_state(settings, master)
  local total, mono = 0, 0
  for _, output in ipairs(monitor_outputs(master)) do
    local layout = monitor_format(settings, output.target, output.source)
    if layout.channels > 1 then
      total = total + 1
      if get_monitor_mode(settings, output.target, layout) == "mono" then mono = mono + 1 end
    end
  end
  return total > 0 and mono == total, total
end

-- Mono is a check on the whole room, not a property of one output, so the
-- button sums every monitor at once and hands each its own mode back after.
local function toggle_monitor_mono(app, settings)
  local master = r.GetMasterTrack(0)
  local active, total = cr_monitor_mono_state(settings, master)
  if total == 0 then return false end
  settings.mono_restore = type(settings.mono_restore) == "table" and settings.mono_restore or {}
  for _, output in ipairs(monitor_outputs(master)) do
    local layout, base = monitor_format(settings, output.target, output.source)
    if layout.channels > 1 then
      local key = monitor_target_key(output.target)
      if active then
        local restore = key and settings.mono_restore[key] or nil
        write_monitor_mode(app, settings, master, output.index, output.target, restore or "full", layout, base)
        if key then settings.mono_restore[key] = nil end
      else
        local mode = get_monitor_mode(settings, output.target, layout)
        if key then settings.mono_restore[key] = mode ~= "mono" and mode or nil end
        write_monitor_mode(app, settings, master, output.index, output.target, "mono", layout, base)
      end
    end
  end
  if app and app.save_settings then app.save_settings() end
  return true
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
      group = "project",
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
    local master_layout = Layouts.by_id(settings.master_layout) or Layouts.by_id("stereo")
    lanes[#lanes + 1] = {
      id = "master",
      label = "Master",
      group = "project",
      subtitle = master_layout.channels > 2 and ("Main output | " .. master_layout.label) or "Main output",
      value = master_value or 1,
      meter = smoothed_meter("master", read_track_peak(master, 0, master_layout.channels), settings),
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
        group = "output",
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
        local layout, base = monitor_format(settings, output.target, output.source)
        local bed = bed_layout(settings, layout)
        local mode = get_monitor_mode(settings, output.target, layout)
        local mode_label = monitor_mode_label(mode, layout, bed)
        local lane_id = "monitor_" .. tostring(send_index)
        -- Meter what this monitor is actually feeding: the whole bed, or the
        -- single channel when a speaker is soloed.
        local meter_base, meter_count = base, layout.channels
        local soloed = mode:match("^speaker:(%d+)$")
        if soloed then
          meter_base, meter_count = base + (tonumber(soloed) or 0), 1
        elseif cr_bus_index(mode) then
          meter_base = fold_offset_for(bed, 0, mode)
          meter_count = 2
        end
        lanes[#lanes + 1] = {
          id = lane_id,
          label = alias or (#outputs > 1 and ("Monitor " .. tostring(send_index + 1)) or "Monitor"),
          group = "output",
          subtitle = tostring(output.name or "Hardware Out") .. " | " .. mode_label,
          value = monitor_value or 1,
          meter = smoothed_meter(lane_id, read_track_peak(master, meter_base, meter_count), settings),
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
          mode_options = monitor_mode_options(layout, bed),
          mode_label = function(next_mode) return monitor_mode_label(next_mode, layout, bed) end,
          set_mode = function(next_mode) return write_monitor_mode(app, settings, master, send_index, output.target, next_mode, layout, base) end,
          write = function(value) return write_monitor_volume(master, send_index, value) end
        }
      end
    end
  end
  if settings.show_cues then
    local cues = cue_outputs(settings)
    for _, cue in ipairs(cues) do
      local track = cue.track
      local cue_value = valid_track(track) and read_track_volume(track) or nil
      if cue_value then
        local cue_muted = read_track_mute(track)
        local lane_id = "cue_" .. tostring(cue.index)
        local output_mode = cue_output_mode(cue)
        local cue_layout = cue_output_layout(cue)
        lanes[#lanes + 1] = {
          id = lane_id,
          label = cue_label(cue),
          group = "output",
          subtitle = tostring(cue.name or "Cue Output") .. " | " .. cue_output_mode_label(output_mode),
          value = cue_value,
          meter = smoothed_meter(lane_id, read_track_peak(track, 0, cue_layout.channels), settings),
          enabled = true,
          led_state = cue_muted == false,
          led_toggle = function() return write_track_mute(track, cue_muted == false, "Control Room: Cue mute") end,
          led_off_color = Theme.colors.warning,
          led_on_tooltip = "Mute cue",
          led_off_tooltip = "Unmute cue",
          mode = output_mode,
          mode_menu_title = "Cue Output Mode",
          mode_options = cue_output_mode_options(),
          mode_label = cue_output_mode_label,
          set_mode = function(next_mode) return write_cue_output_mode(app, cue, next_mode) end,
          handle_color = native_color_to_u32(r.GetTrackColor(track), 0xFF) or Theme.colors.warning,
          write = function(value) return write_track_volume(track, value, "Control Room: Cue volume") end
        }
      end
    end
  end
  local media_browser = app.modules_by_id and app.modules_by_id.media_browser
  if settings.show_media_browser ~= false and media_browser and media_browser.preview_level then
    local media_value = media_browser.preview_level(app)
    lanes[#lanes + 1] = {
      id = "media_browser",
      label = "Media",
      group = "output",
      subtitle = "Browser preview",
      value = media_value or 1,
      meter = 0,
      enabled = media_value ~= nil,
      handle_color = Theme.colors.accent,
      write = function(value) return media_browser.set_preview_level(app, value) end
    }
  end
  if settings.show_metronome then
    local metro_value = read_metronome_volume()
    lanes[#lanes + 1] = {
      id = "metronome",
      label = "Metronome",
      group = "utility",
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

local function meter_source_entry(id, label, track, layout)
  layout = type(layout) == "string" and Layouts.by_id(layout) or layout
  layout = layout or Layouts.by_id("stereo")
  return {
    id = id,
    label = label,
    track = track,
    layout = layout.id,
    layout_index = Layouts.jsfx_layout_index[layout.id] or MeterEngine.default_layout_index
  }
end

local function meter_sources(app, settings)
  local sources = {}
  sources[#sources + 1] = meter_source_entry("master", "Master", r.GetMasterTrack(0), settings.master_layout)
  local track = selected_track(app)
  local track_layout = valid_track(track) and Layouts.by_channels(math.min(track_channel_count(track), 8)) or Layouts.by_id("stereo")
  sources[#sources + 1] = meter_source_entry("selected", "Selected", track, track_layout)
  for _, cue in ipairs(cue_outputs(settings)) do
    if valid_track(cue.track) then
      sources[#sources + 1] = meter_source_entry("cue:" .. tostring(cue_guid_value(cue) or cue.index), cue_label(cue), cue.track, cue_output_layout(cue))
    end
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

function cr_draw_meter_target(ctx, draw_list, left_x, right_x, top_y, bottom_y, settings)
  if settings.meter_show_target == false then return end
  local min_db = settings.min_db or defaults.min_db
  local max_db = settings.max_db or defaults.max_db
  local target_db = tonumber(settings.meter_target_lufs) or MeterEngine.default_target_lufs
  if target_db >= max_db or target_db <= min_db then return end
  local tolerance = math.max(0, tonumber(settings.meter_target_tolerance) or defaults.meter_target_tolerance)
  local y = meter_value_y(db_to_linear(target_db, min_db, max_db), top_y, bottom_y, settings)
  if tolerance > 0 then
    local upper = meter_value_y(db_to_linear(math.min(max_db, target_db + tolerance), min_db, max_db), top_y, bottom_y, settings)
    local lower = meter_value_y(db_to_linear(math.max(min_db, target_db - tolerance), min_db, max_db), top_y, bottom_y, settings)
    r.ImGui_DrawList_AddRectFilled(draw_list, left_x, upper, right_x, lower, color_with_alpha(Theme.colors.accent, 0x26), 0)
  end
  r.ImGui_DrawList_AddLine(draw_list, left_x, y, right_x, y, color_with_alpha(Theme.colors.accent, 0xCC), UIScale.px(1.6))
  local text = string.format("%.0f", target_db)
  local text_w = calc_text_width(ctx, text)
  local text_x = left_x + math.max(0, (right_x - left_x - text_w) * 0.5)
  r.ImGui_DrawList_AddText(draw_list, text_x, y - UIScale.round(14), color_with_alpha(Theme.colors.accent, 0xEE), text)
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

local function draw_meter_info_box(ctx, draw_list, x, y, width, height, label, value, unit, value_color, scale)
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
  local value_font_size = math.max(19, math.floor(current_font_size * 1.55 * (tonumber(scale) or 1) + 0.5))
  local value_font = get_meter_value_font(ctx, value_font_size)
  local text_scale = value_font_size / math.max(1, current_font_size)
  local value_w = calc_text_width(ctx, value_text) * text_scale
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
  local bar_mode = MeterEngine.bar_source(settings.meter_bar_source or defaults.meter_bar_source)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Bars show")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  if r.ImGui_BeginCombo(ctx, "##control_room_meter_bar_source", bar_mode.label) then
    for _, item in ipairs(MeterEngine.bar_sources or {}) do
      if r.ImGui_Selectable(ctx, item.label, item.id == bar_mode.id) then
        settings.meter_bar_source = item.id
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Peak and RMS are per channel. The LUFS readings are one weighted value for the whole bed and draw as a single bar") end
  r.ImGui_Separator(ctx)
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
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  local bar_changed, bar_value = r.ImGui_SliderDouble(ctx, "Bar width##control_room_meter_bar_scale", clamp(tonumber(settings.meter_bar_scale) or defaults.meter_bar_scale, 0.4, 1), 0.4, 1, "%.2f")
  if bar_changed then
    settings.meter_bar_scale = bar_value
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Width of the channel bars, centred in the panel") end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  local info_changed, info_value = r.ImGui_SliderDouble(ctx, "Info size##control_room_meter_info_scale", clamp(tonumber(settings.meter_info_scale) or defaults.meter_info_scale, 0.6, 1.8), 0.6, 1.8, "%.2f")
  if info_changed then
    settings.meter_info_scale = info_value
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Height and text size of the value boxes. What is left over goes to the meter") end
  r.ImGui_Separator(ctx)
  local target_show_changed, target_show_value = r.ImGui_Checkbox(ctx, "Show target on meter", settings.meter_show_target ~= false)
  if target_show_changed then
    settings.meter_show_target = target_show_value == true
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Draw the target level as a line across the bars") end
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
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  local tolerance_changed, tolerance_value = r.ImGui_SliderDouble(ctx, "Tolerance##control_room_meter_tolerance", math.max(0, tonumber(settings.meter_target_tolerance) or defaults.meter_target_tolerance), 0, 6, "%.1f dB")
  if tolerance_changed then
    settings.meter_target_tolerance = tolerance_value
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Band around the target. Set to zero for a single line") end
  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Default##control_room_meter_display_default", UIScale.text_button_w(ctx, "Default", 84, 8), 0) then
    settings.meter_display_items = copy_default(MeterEngine.default_display_items)
    settings.meter_target_lufs = MeterEngine.default_target_lufs
    settings.meter_show_target = defaults.meter_show_target
    settings.meter_target_tolerance = defaults.meter_target_tolerance
    settings.meter_bar_scale = defaults.meter_bar_scale
    settings.meter_info_scale = defaults.meter_info_scale
    settings.meter_bar_source = defaults.meter_bar_source
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Close##control_room_meter_display_close", UIScale.text_button_w(ctx, "Close", 72, 8), 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

function cr_lane_group_color(group)
  if group == "output" then return Theme.colors.warning end
  if group == "utility" then return Theme.colors.text_dim end
  return Theme.colors.accent
end

function cr_lane_group_label(group)
  if group == "output" then return "Physical outputs" end
  if group == "utility" then return "Utility" end
  return "Project busses"
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
    local mode_label = lane.mode_label or tostring
    for _, mode in ipairs(lane.mode_options) do
      local selected = lane.mode == mode
      if r.ImGui_Selectable(ctx, mode_label(mode), selected) then lane.set_mode(mode) end
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
  if lane.group then
    r.ImGui_DrawList_AddRectFilled(draw_list, left_x + UIScale.px(1), top_y + corner, left_x + UIScale.px(4), bottom_y - corner, color_with_alpha(cr_lane_group_color(lane.group), enabled and 0xFF or 0x77), 0)
  end
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
  local key = source.id or "none"
  state.pending_meter_reset = { source_id = source.id, track_guid = track_guid(source.track), layout_index = source.layout_index }
  state.meter_peaks[key] = nil
  for index = 1, 8 do state.meters["meter_" .. tostring(index) .. ":" .. tostring(key)] = 0 end
end

local function draw_header(app, lanes)
  local ctx = app.ctx
  local active_count = 0
  for _, lane in ipairs(lanes) do if lane.enabled then active_count = active_count + 1 end end
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Control Room")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(active_count) .. "/" .. tostring(#lanes) .. " active")
end

function cr_meter_bar_values(source, settings, channel_count)
  local mode = MeterEngine.bar_source(settings.meter_bar_source or defaults.meter_bar_source)
  local track = source and source.track or nil
  local min_db = settings.min_db or defaults.min_db
  local max_db = settings.max_db or defaults.max_db
  if mode.id ~= "peak" and MeterEngine.uses_engine(source) then
    local options = { auto_install = settings.meter_fx_auto_install ~= false }
    if mode.id == "rms" then
      local levels = MeterEngine.read_channel_rms(track, channel_count, options)
      if levels then
        local values = {}
        for index = 1, channel_count do values[index] = db_to_linear(levels[index] or min_db, min_db, max_db) end
        return values, mode
      end
    else
      local level = MeterEngine.read_value(track, mode.id, options)
      if level then return { db_to_linear(level, min_db, max_db) }, mode end
    end
  end
  return read_channel_peaks(track, 0, channel_count), MeterEngine.bar_source("peak")
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
    local layout = Layouts.by_id(source and source.layout) or Layouts.by_id("stereo")
    local channel_count = math.max(1, layout.channels)
    local raw_values, bar_mode = cr_meter_bar_values(source, settings, channel_count)
    local bar_count = math.max(1, #raw_values)
    local peak_key = tostring(source and source.id or "none") .. ":" .. tostring(bar_mode.id)
    state.meter_peaks = type(state.meter_peaks) == "table" and state.meter_peaks or {}
    local peak = state.meter_peaks[peak_key]
    if type(peak) ~= "table" or #peak ~= bar_count then
      peak = {}
      for index = 1, bar_count do peak[index] = 0 end
      state.meter_peaks[peak_key] = peak
    end
    local values = {}
    for index = 1, bar_count do
      local raw = raw_values[index] or 0
      values[index] = smoothed_meter("meter_" .. tostring(index) .. ":" .. tostring(peak_key), raw, settings)
      if raw > (peak[index] or 0) then peak[index] = raw end
    end
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_SetCursorScreenPos(ctx, panel_x, select(2, r.ImGui_GetCursorScreenPos(ctx)))
    local meter_x, meter_y = r.ImGui_GetCursorScreenPos(ctx)
    local _, meter_avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local info_items = MeterEngine.info_items(settings, source, Theme.colors)
    local divider_gap_top = UIScale.round(10)
    local divider_gap_bottom = UIScale.round(10)
    local info_gap = UIScale.round(5)
    local info_scale = clamp(tonumber(settings.meter_info_scale) or defaults.meter_info_scale, 0.6, 1.8)
    local info_box_h = UIScale.round(58 * info_scale)
    local info_h = #info_items * info_box_h + math.max(0, #info_items - 1) * info_gap
    local details_h = #info_items > 0 and (divider_gap_top + UIScale.round(1) + divider_gap_bottom + info_h + UIScale.round(4)) or 0
    local available_meter_h = (meter_avail_h or UIScale.round(220)) - details_h
    local meter_h = settings.meter_adaptive_height ~= false and available_meter_h or math.min(UIScale.round(360), available_meter_h)
    meter_h = math.max(UIScale.round(80), meter_h)
    r.ImGui_Dummy(ctx, panel_w, meter_h)
    local bottom_y = meter_y + meter_h
    draw_meter_scale(ctx, draw_list, meter_x + UIScale.round(2), meter_x + panel_w - UIScale.round(2), meter_y + UIScale.round(6), bottom_y - UIScale.round(4), settings)
    local scale_margin = panel_w >= UIScale.round(180) and UIScale.round(36) or UIScale.round(28)
    local gaps = math.max(1, bar_count - 1)
    local bar_scale = clamp(tonumber(settings.meter_bar_scale) or defaults.meter_bar_scale, 0.4, 1)
    local bar_gap = math.max(UIScale.round(2), math.min(UIScale.round(16), (panel_w * 0.08) / gaps))
    local bar_w = math.max(UIScale.round(6), (panel_w - scale_margin * 2 - bar_gap * gaps) / bar_count) * bar_scale
    local bars_w = bar_w * bar_count + bar_gap * gaps
    local bar_left = meter_x + scale_margin + math.max(0, (panel_w - scale_margin * 2 - bars_w) * 0.5)
    local bar_top = meter_y + UIScale.round(6)
    local bar_bottom = bottom_y - UIScale.round(4)
    for index = 1, bar_count do
      local left_edge = bar_left + (index - 1) * (bar_w + bar_gap)
      local caption = bar_mode.per_channel and Layouts.speaker(layout, index - 1) or bar_mode.label
      -- Narrow bars only get the speaker name; the value badge would not fit.
      local badge = nil
      if bar_w >= UIScale.round(46) then
        local reading = bar_mode.per_channel and format_db(peak[index] or 0, settings) or string.format("%.1f LUFS", linear_to_db(peak[index] or 0, settings.min_db or defaults.min_db))
        badge = caption .. " " .. reading
      elseif bar_w >= UIScale.round(18) then
        badge = caption
      end
      if draw_meter_channel(ctx, draw_list, left_edge, left_edge + bar_w, bar_top, bar_bottom, values[index], peak[index], badge, settings) then
        peak[index] = 0
      end
    end
    cr_draw_meter_target(ctx, draw_list, bar_left, bar_left + bars_w, bar_top, bar_bottom, settings)
    if #info_items > 0 then
      local divider_y = meter_y + meter_h + divider_gap_top
      r.ImGui_DrawList_AddLine(draw_list, panel_x, divider_y, panel_x + panel_w, divider_y, color_with_alpha(Theme.colors.border or Theme.colors.text_dim, 0xAA), UIScale.px(1))
      r.ImGui_SetCursorScreenPos(ctx, panel_x, divider_y + divider_gap_bottom)
      local info_x, info_y = r.ImGui_GetCursorScreenPos(ctx)
      r.ImGui_Dummy(ctx, panel_w, info_h)
      for index, item in ipairs(info_items) do
        draw_meter_info_box(ctx, draw_list, info_x, info_y + (index - 1) * (info_box_h + info_gap), panel_w, info_box_h, item.label, item.value, item.unit, item.color, info_scale)
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
    local mono_active, mono_total = cr_monitor_mono_state(settings, r.GetMasterTrack(0))
    if mono_active then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), active_button_text)
    end
    local mono_clicked = r.ImGui_Button(ctx, "MONO##control_room_mono", UIScale.text_button_w(ctx, "MONO", 56, 6), button_h)
    if mono_active then r.ImGui_PopStyleColor(ctx, 4) end
    if mono_clicked and mono_total > 0 then toggle_monitor_mono(app, settings) end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, mono_total == 0 and "No monitor wide enough to sum" or (mono_active and "Give every monitor its own mode back" or "Sum every monitor to mono"))
    end
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
  local width = math.max(1, math.floor(tonumber(target.width) or 2))
  local mode = target.mono and "Mono" or (width == 2 and "Stereo" or (tostring(width) .. " ch"))
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

local CHANNEL_MAP_COLUMNS = 8

-- One downmix on the master serves every check, a pair each, so what shows here
-- is which of those pairs is being listened to.
function cr_draw_monitor_processing(ctx, app, settings, master, master_layout)
  local index = find_fold_fx(master)
  local names = {}
  if index then
    for _, mode in ipairs(MONITOR_BUS_MODES) do
      if fold_bus_in_use(settings, master, mode) then names[#names + 1] = MONITOR_MODE_LABELS[mode] or mode end
    end
  end
  local theme_count = push_setup_slider_theme(ctx)
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
  local changed, value = r.ImGui_SliderDouble(ctx, "Crossover##control_room_crossover", tonumber(settings.monitor_crossover_hz) or defaults.monitor_crossover_hz, 40, 1000, "%.0f Hz")
  pop_setup_slider_theme(ctx, theme_count)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Split point of the Low Band and High Band monitor modes") end
  if changed then
    settings.monitor_crossover_hz = value
    if index then set_fold_param(master, index, FOLD_PARAMS.crossover, value) end
    if app.save_settings then app.save_settings() end
  end
  if index then
    r.ImGui_SameLine(ctx)
    local idle = #names == 0
    r.ImGui_TextColored(ctx, idle and Theme.colors.text_dim or Theme.colors.text, idle and "Downmix idle" or table.concat(names, ", "))
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, idle and "The downmix is on the master but no monitor is set to a check" or "Checks the downmix is feeding a monitor") end
  end
end

function cr_channel_map_claim(map, channel, name, short)
  map[channel] = map[channel] or {}
  local list = map[channel]
  list[#list + 1] = { name = name, short = short }
end

function cr_channel_map_names(list)
  local names = {}
  for index, entry in ipairs(list or {}) do names[index] = entry.name end
  return table.concat(names, ", ")
end

-- Who occupies which master channel and which hardware output, so an
-- overlapping setup can be seen instead of worked out.
function cr_channel_map_usage(settings, master, outputs, bed)
  local bus_bases = {}
  if find_fold_fx(master) then
    for _, mode in ipairs(MONITOR_BUS_MODES) do bus_bases[mode] = fold_offset_for(bed, 0, mode) end
  end
  local master_channels = track_channel_count(master)
  local source_users, hardware_users, issues = {}, {}, {}
  for _, output in ipairs(outputs or {}) do
    local short = "M" .. tostring(output.index + 1)
    local name = monitor_alias(settings, output.target) or ("Monitor " .. tostring(output.index + 1))
    local layout, base = monitor_format(settings, output.target, output.source)
    local mode = get_monitor_mode(settings, output.target, layout)
    local first, count = base, layout.channels
    local speaker = mode:match("^speaker:(%d+)$")
    if speaker then
      first, count = base + (tonumber(speaker) or 0), 1
    elseif bus_bases[mode] then
      first, count = bus_bases[mode], 2
    end
    for channel = first, first + count - 1 do cr_channel_map_claim(source_users, channel, name, short) end
    if first + count > master_channels then
      issues[#issues + 1] = name .. " reads Master " .. Layouts.channel_span(first, { channels = count }) .. ", past the master's " .. tostring(master_channels) .. " channels"
    end
    local target = output.target
    if target and not target.rearoute then
      local width = math.max(1, math.floor(tonumber(target.width) or 2))
      for channel = target.channel, target.channel + width - 1 do cr_channel_map_claim(hardware_users, channel, name, short) end
    end
  end
  for _, cue in ipairs(cue_outputs(settings)) do
    local target = cue.target
    if target and not target.rearoute then
      local width = math.max(1, math.floor(tonumber(target.width) or 2))
      for channel = target.channel, target.channel + width - 1 do cr_channel_map_claim(hardware_users, channel, cue_label(cue), "C" .. tostring(cue.index)) end
    end
  end
  return source_users, hardware_users, issues, bus_bases
end

function cr_channel_map_cell(ctx, id, label, tooltip, fill, text_color, width)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), fill)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), fill)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), fill)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
  r.ImGui_Button(ctx, label .. "##" .. id, width, UIScale.button_h(ctx, 0))
  r.ImGui_PopStyleColor(ctx, 4)
  if tooltip and tooltip ~= "" and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip) end
end

function cr_draw_channel_map(ctx, settings, master, outputs, bed)
  if not r.ImGui_CollapsingHeader or not r.ImGui_CollapsingHeader(ctx, "Channel map##control_room_channel_map") then return end
  local source_users, hardware_users, issues, bus_bases = cr_channel_map_usage(settings, master, outputs, bed)
  local cell_w = UIScale.round(46)
  local bus_tags = { fold_stereo = "Fd", mid = "M", side = "S", low = "Lo", high = "Hi" }
  local bus_top = 0
  for _, base in pairs(bus_bases) do bus_top = math.max(bus_top, base + 2) end
  local master_channels = math.max(track_channel_count(master), bed.channels, bus_top)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Master channels")
  for channel = 0, master_channels - 1 do
    if channel % CHANNEL_MAP_COLUMNS ~= 0 then r.ImGui_SameLine(ctx) end
    local tag, fill, tooltip
    if channel < bed.channels then
      tag = Layouts.speaker(bed, channel)
      fill = Theme.colors.accent_soft
      tooltip = "Main mix | " .. bed.label .. " " .. tag
    else
      tag = "-"
      fill = Theme.colors.frame_bg
      tooltip = "Free"
      for mode, base in pairs(bus_bases) do
        if channel >= base and channel < base + 2 then
          tag = bus_tags[mode] or "P"
          fill = Theme.colors.accent
          tooltip = (MONITOR_MODE_LABELS[mode] or mode) .. " pair"
          break
        end
      end
    end
    local users = source_users[channel]
    if users then tooltip = tooltip .. "\nRead by: " .. cr_channel_map_names(users) end
    cr_channel_map_cell(ctx, "cr_map_src_" .. tostring(channel), tostring(channel + 1) .. " " .. tag, tooltip, fill, users and Theme.colors.text or Theme.colors.text_dim, cell_w)
  end
  local device_outputs = 0
  if r.GetNumAudioOutputs then
    local ok, value = pcall(r.GetNumAudioOutputs)
    device_outputs = ok and math.floor(tonumber(value) or 0) or 0
  end
  local highest = 0
  for channel in pairs(hardware_users) do highest = math.max(highest, channel + 1) end
  local shown = math.min(device_outputs, math.max(CHANNEL_MAP_COLUMNS, math.ceil(highest / CHANNEL_MAP_COLUMNS) * CHANNEL_MAP_COLUMNS))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Hardware outputs")
  if shown <= 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No audio outputs available")
  else
    local conflicts = {}
    for channel = 0, shown - 1 do
      if channel % CHANNEL_MAP_COLUMNS ~= 0 then r.ImGui_SameLine(ctx) end
      local users = hardware_users[channel]
      local tooltip = output_channel_name(channel)
      local tag, fill, text_color = "-", Theme.colors.frame_bg, Theme.colors.text_dim
      if users and #users > 1 then
        tag, fill, text_color = "!", Theme.colors.warning, Theme.colors.text
        tooltip = tooltip .. "\nShared by: " .. cr_channel_map_names(users)
        conflicts[#conflicts + 1] = output_channel_name(channel)
      elseif users then
        tag, fill, text_color = users[1].short, Theme.colors.accent_soft, Theme.colors.text
        tooltip = tooltip .. "\nFed by: " .. users[1].name
      else
        tooltip = tooltip .. "\nFree"
      end
      cr_channel_map_cell(ctx, "cr_map_hw_" .. tostring(channel), tostring(channel + 1) .. " " .. tag, tooltip, fill, text_color, cell_w)
    end
    if device_outputs > shown then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "+ " .. tostring(device_outputs - shown) .. " unused outputs")
    end
    if #conflicts > 0 then
      issues[#issues + 1] = "Two outputs feed the same hardware channel: " .. table.concat(conflicts, ", ")
    end
  end
  for _, issue in ipairs(issues) do r.ImGui_TextColored(ctx, Theme.colors.warning, issue) end
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
  -- Destination lists depend on send width, so the shared list is the stereo
  -- one and the monitor and cue rows build their own.
  local targets = available_output_targets(outputs, "stereo")
  local cues = cue_outputs(settings)
  local has_cues = false
  for _, cue in ipairs(cues) do if valid_track(cue.track) then has_cues = true end end
  state.setup_tab = state.setup_tab or "monitors"
  if state.setup_tab == "mix" and not has_cues then state.setup_tab = "cues" end
  local tab_avail = r.ImGui_GetContentRegionAvail(ctx)
  local tab_count = has_cues and 4 or 3
  local tab_w = math.max(UIScale.round(82), (tab_avail - UIScale.round(18)) / tab_count)
  if draw_setup_section_button(ctx, "Monitors", "control_room_setup_monitors", state.setup_tab == "monitors", tab_w) then state.setup_tab = "monitors" end
  r.ImGui_SameLine(ctx)
  if draw_setup_section_button(ctx, "Cues", "control_room_setup_cues", state.setup_tab == "cues", tab_w) then state.setup_tab = "cues" end
  r.ImGui_SameLine(ctx)
  if has_cues then
    if draw_setup_section_button(ctx, "Mix", "control_room_setup_mix", state.setup_tab == "mix", tab_w) then state.setup_tab = "mix" end
    r.ImGui_SameLine(ctx)
  end
  if draw_setup_section_button(ctx, "Targets", "control_room_setup_targets", state.setup_tab == "targets", tab_w) then state.setup_tab = "targets" end
  if r.ImGui_Separator then r.ImGui_Separator(ctx) end
  if state.setup_tab == "monitors" then
      local master_layout = Layouts.by_id(settings.master_layout) or Layouts.by_id("stereo")
      local master_channels = track_channel_count(master)
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Master format")
      r.ImGui_SameLine(ctx, UIScale.round(90))
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
      if r.ImGui_BeginCombo(ctx, "##control_room_master_layout", master_layout.label) then
        for _, layout in ipairs(Layouts.layouts) do
          local selected = layout.id == master_layout.id
          if r.ImGui_Selectable(ctx, layout.label .. " (" .. tostring(layout.channels) .. " ch)", selected) then
            settings.master_layout = layout.id
            grow_track_channel_count(master, layout.channels, "Control Room: Widen master")
            if app.save_settings then app.save_settings() end
          end
          if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Format of the main mix. Drives the master meter, the fold-down and the default for new monitors.\nEach monitor keeps its own format below.") end
      r.ImGui_SameLine(ctx)
      r.ImGui_TextColored(ctx, master_channels >= master_layout.channels and Theme.colors.text_dim or Theme.colors.warning, "Master track " .. tostring(master_channels) .. " ch")
      if master_channels < master_layout.channels then
        r.ImGui_SameLine(ctx)
        local widen_label = "Widen to " .. tostring(master_layout.channels)
        if r.ImGui_Button(ctx, widen_label .. "##control_room_widen_master", UIScale.text_button_w(ctx, widen_label, 118, 10), 0) then
          grow_track_channel_count(master, master_layout.channels, "Control Room: Widen master")
        end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "The master track needs at least " .. tostring(master_layout.channels) .. " channels for this format") end
      end
      if master_layout.channels > 2 then
        local fold_index = find_fold_fx(master)
        local fold_base = fold_offset_for(master_layout, 0)
        local fold_active = fold_index and fold_bus_in_use(settings, master) or false
        local fold_text = "Not added yet"
        if fold_index then
          fold_text = "Master " .. Layouts.channel_span(fold_base, { channels = 2 }) .. (fold_active and "" or " (idle)")
        end
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Fold-down")
        r.ImGui_SameLine(ctx, UIScale.round(90))
        r.ImGui_TextColored(ctx, fold_index and (fold_active and Theme.colors.text_dim or Theme.colors.warning) or Theme.colors.text_dim, fold_text)
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, fold_active and "A monitor is listening to the fold pair" or (fold_index and "Added but stopped: no monitor is set to Fold to Stereo.\nIt writes nothing until one is." or "The downmix JSFX is added to the master as soon as a monitor is set to Fold to Stereo.\nAdd it now to set the levels up front."))
        end
        r.ImGui_SameLine(ctx)
        if fold_index then
          if r.ImGui_Button(ctx, "Remove##control_room_fold_remove", UIScale.text_button_w(ctx, "Remove", 78, 8), 0) then remove_fold_bus(master) end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove the downmix JSFX from the master") end
        else
          if r.ImGui_Button(ctx, "Add##control_room_fold_add", UIScale.text_button_w(ctx, "Add", 78, 8), 0) then
            local _, status = ensure_fold_bus(app, settings, master, master_layout, 0, true)
            state.fold_status = status
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add TK Control Room Downmix to the master now") end
        end
        local fold_changed = false
        local fold_slider_theme = push_setup_slider_theme(ctx)
        r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
        local center_changed, center_value = r.ImGui_SliderDouble(ctx, "Center##control_room_fold_center", tonumber(settings.fold_center_db) or defaults.fold_center_db, -12, 0, "%.1f dB")
        if center_changed then settings.fold_center_db = center_value; fold_changed = true end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
        local surround_changed, surround_value = r.ImGui_SliderDouble(ctx, "Surround##control_room_fold_surround", tonumber(settings.fold_surround_db) or defaults.fold_surround_db, -12, 0, "%.1f dB")
        if surround_changed then settings.fold_surround_db = surround_value; fold_changed = true end
        pop_setup_slider_theme(ctx, fold_slider_theme)
        local lfe_changed, lfe_value = r.ImGui_Checkbox(ctx, "Include LFE##control_room_fold_lfe", settings.fold_lfe == true)
        if lfe_changed then settings.fold_lfe = lfe_value == true; fold_changed = true end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Most delivery specs discard LFE on fold-down") end
        if settings.fold_lfe == true then
          r.ImGui_SameLine(ctx)
          local lfe_slider_theme = push_setup_slider_theme(ctx)
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
          local lfe_db_changed, lfe_db_value = r.ImGui_SliderDouble(ctx, "LFE##control_room_fold_lfe_db", tonumber(settings.fold_lfe_db) or defaults.fold_lfe_db, -24, 10, "%.1f dB")
          if lfe_db_changed then settings.fold_lfe_db = lfe_db_value; fold_changed = true end
          pop_setup_slider_theme(ctx, lfe_slider_theme)
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "LFE is reproduced 10 dB above the other channels.\n+10 matches what a surround listener hears; 0 keeps the fold-down safer.") end
        end
        local trim_slider_theme = push_setup_slider_theme(ctx)
        r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
        local trim_changed, trim_value = r.ImGui_SliderDouble(ctx, "Output trim##control_room_fold_trim", tonumber(settings.fold_trim_db) or defaults.fold_trim_db, -12, 12, "%.1f dB")
        if trim_changed then settings.fold_trim_db = trim_value; fold_changed = true end
        pop_setup_slider_theme(ctx, trim_slider_theme)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Level of the folded stereo pair. Pull down if summing pushes it into clipping.") end
        if fold_changed then
          if fold_index then ensure_fold_bus(app, settings, master, master_layout, 0, false) end
          if app.save_settings then app.save_settings() end
        end
      end
      if state.fold_status then r.ImGui_TextColored(ctx, Theme.colors.warning, tostring(state.fold_status)) end
      cr_draw_monitor_processing(ctx, app, settings, master, master_layout)
      if r.ImGui_Separator then r.ImGui_Separator(ctx) end
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
      local groups_changed, groups_value = r.ImGui_Checkbox(ctx, "Group lanes by bus type##control_room_lane_groups", settings.show_lane_groups ~= false)
      if groups_changed then
        settings.show_lane_groups = groups_value
        if app.save_settings then app.save_settings() end
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Separate project busses, physical outputs and utility lanes with headings") end
      cr_draw_channel_map(ctx, settings, master, outputs, master_layout)
      if #outputs == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No master hardware outputs configured.")
      elseif r.ImGui_BeginChild(ctx, "##control_room_setup_outputs", 0, 0, 0) then
        for _, output in ipairs(outputs) do
          r.ImGui_PushID(ctx, "setup_monitor_" .. tostring(output.index))
          local volume = read_monitor_volume(master, output.index)
          local muted = read_monitor_mute(master, output.index)
          local source = output.source or monitor_send_source(master, output.index)
          local layout, base = monitor_format(settings, output.target, source)
          local bed = bed_layout(settings, layout)
          local monitor_targets = available_output_targets(outputs, layout)
          local source_targets = available_source_targets(master, layout)
          local mode = get_monitor_mode(settings, output.target, layout)
          local alias = monitor_alias(settings, output.target) or ""
          r.ImGui_TextColored(ctx, Theme.colors.text, "Monitor " .. tostring(output.index + 1))
          r.ImGui_SameLine(ctx)
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(output.name or "Hardware Out") .. " | " .. monitor_mode_text(output) .. " | " .. monitor_mode_label(mode, layout, bed) .. " | " .. tostring(source.name or "Master 1 / 2") .. " | " .. format_db(volume or 1, settings))
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Alias")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(310))
          local alias_changed, alias_value = r.ImGui_InputText(ctx, "##monitor_alias", alias)
          if alias_changed then write_monitor_alias(app, settings, output.target, alias_value) end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, "Clear##monitor_alias_clear", UIScale.text_button_w(ctx, "Clear", 54, 8), 0) then clear_monitor_alias(app, settings, output.target) end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear monitor alias") end
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Format")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
          if r.ImGui_BeginCombo(ctx, "##monitor_layout", layout.label) then
            for _, next_layout in ipairs(Layouts.layouts) do
              local selected = next_layout.id == layout.id
              if r.ImGui_Selectable(ctx, next_layout.label .. " (" .. tostring(next_layout.channels) .. " ch)", selected) then
                write_monitor_layout(app, settings, master, output.index, output.target, next_layout, base)
              end
              if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Send width. Widens the master track when the format needs more channels.") end
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Output")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
          if #monitor_targets > 0 and r.ImGui_BeginCombo(ctx, "##monitor_destination", tostring(output.name or "Hardware Out")) then
            for _, target in ipairs(monitor_targets) do
              local selected = target_matches_output(target, output)
              if r.ImGui_Selectable(ctx, tostring(target.name or "Output"), selected) then
                if write_monitor_destination(master, output.index, target) then write_monitor_mode(app, settings, master, output.index, target, mode, layout, base) end
              end
              if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
          end
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Source")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
          if #source_targets > 0 and r.ImGui_BeginCombo(ctx, "##monitor_source", source_target_name(base, layout)) then
            for _, target in ipairs(source_targets) do
              local selected = target.channel == base
              if r.ImGui_Selectable(ctx, tostring(target.name or "Source"), selected) then
                write_monitor_layout(app, settings, master, output.index, output.target, layout, target.channel)
              end
              if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Master channels feeding this monitor") end
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Mode")
          r.ImGui_SameLine(ctx, UIScale.round(64))
          r.ImGui_SetNextItemWidth(ctx, UIScale.round(392))
          if r.ImGui_BeginCombo(ctx, "##monitor_mode", monitor_mode_label(mode, layout, bed)) then
            for _, next_mode in ipairs(monitor_mode_options(layout, bed)) do
              local selected = mode == next_mode
              if r.ImGui_Selectable(ctx, monitor_mode_label(next_mode, layout, bed), selected) then write_monitor_mode(app, settings, master, output.index, output.target, next_mode, layout, base) end
              if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Full format, mono sum, fold-down or a single speaker") end
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
          local cue_layout = cue_output_layout(cue)
          local cue_targets = available_output_targets(outputs, cue_layout)
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
            if #cue_targets > 0 and r.ImGui_BeginCombo(ctx, "##cue_destination", tostring(cue.name or "Cue Output")) then
              for _, target in ipairs(cue_targets) do
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
              for _, mode in ipairs(cue_output_mode_options()) do
                local selected = output_mode == mode
                if r.ImGui_Selectable(ctx, cue_output_mode_label(mode), selected) then write_cue_output_mode(app, cue, mode) end
                if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
              end
              r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Cue output format. Widens the cue track when needed.") end
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
      state.targets_layout = state.targets_layout or (Layouts.by_id(settings.master_layout) or Layouts.by_id("stereo")).id
      local preview_layout = Layouts.by_id(state.targets_layout) or Layouts.by_id("stereo")
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Format")
      r.ImGui_SameLine(ctx, UIScale.round(64))
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(180))
      if r.ImGui_BeginCombo(ctx, "##control_room_targets_layout", preview_layout.label) then
        for _, layout in ipairs(Layouts.layouts) do
          local selected = layout.id == preview_layout.id
          if r.ImGui_Selectable(ctx, layout.label .. " (" .. tostring(layout.channels) .. " ch)", selected) then state.targets_layout = layout.id end
          if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Destination options available at this send width") end
      local preview_targets = available_output_targets(outputs, preview_layout)
      if #preview_targets == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No device outputs found.")
      elseif r.ImGui_BeginChild(ctx, "##control_room_setup_targets", 0, 0, 0) then
        for _, target in ipairs(preview_targets) do
          local kind = target.rearoute and "ReaRoute" or "Hardware"
          local width = target.mono and "Mono sum" or (target.width == 2 and "Stereo" or (tostring(target.width) .. " ch"))
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(target.name or "Output") .. " | " .. kind .. " " .. width)
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
  local show_groups = settings.show_lane_groups ~= false
  local group_count = 0
  if show_groups then
    local seen = nil
    for _, lane in ipairs(lanes) do
      if lane.group and lane.group ~= seen then
        group_count = group_count + 1
        seen = lane.group
      end
    end
  end
  local header_height = group_count * (r.ImGui_GetTextLineHeightWithSpacing(ctx) + UIScale.round(2))
  local lane_height = math.max(UIScale.round(190), math.min(UIScale.round(245), (avail_height or UIScale.round(245)) - reserved_height - header_height - UIScale.round(4)))
  if r.ImGui_BeginChild(ctx, "##control_room_lanes", 0, -reserved_height, 0) then
    local current_group = nil
    local column = 0
    for _, lane in ipairs(lanes) do
      if show_groups and lane.group and lane.group ~= current_group then
        current_group = lane.group
        column = 0
        r.ImGui_TextColored(ctx, color_with_alpha(cr_lane_group_color(lane.group), 0xCC), cr_lane_group_label(lane.group))
      elseif column > 0 and column < columns then
        r.ImGui_SameLine(ctx)
      else
        column = 0
      end
      draw_lane(app, lane, settings, lane_width, lane_height)
      column = column + 1
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
  local now = r.time_precise and r.time_precise() or os.clock()
  if now - (state.fold_sync_time or 0) > 0.5 then
    state.fold_sync_time = now
    sync_fold_bus_run(settings, r.GetMasterTrack(0))
  end
  if state.pending_meter_reset then
    local pending = state.pending_meter_reset
    state.pending_meter_reset = nil
    local track = pending.source_id == "master" and r.GetMasterTrack(0) or track_by_guid(pending.track_guid)
    local ok, err = pcall(MeterEngine.reset_source, { id = pending.source_id, track = track, layout_index = pending.layout_index }, settings)
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