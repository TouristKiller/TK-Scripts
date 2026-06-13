local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local M = {
  id = "instrument_rack",
  title = "Instrument Rack",
  icon = "FX",
  version = "0.1.0"
}

local EXT_SECTION = "TK_WORKBENCH_INSTRUMENT_RACK"
local REC_FX_OFFSET = 0x1000000
local MAX_PARAM_SLOTS = 8
local PARAM_SLOT_COLUMNS = 4
local MACRO_COUNT = 8
local MACRO_MAX = 16

local state = {
  screenshot_path = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/Screenshots/",
  screenshot_index = nil,
  screenshot_cache = {},
  screenshot_missing = {},
  pinned_params = {},
  pinned_project = nil,
  collapsed = {},
  drop_mouse_was_down = false,
  last_external_drag = nil,
  pending_param_action = nil,
  macro_project = nil,
  macros = {},
  macro_assignments = {},
  macro_name_buffers = {},
  macro_cc_learn = nil,
  midi_last_retval = nil,
  macros_dirty = false,
  macro_count = MACRO_COUNT,
  default_pins = nil,
  default_pins_loaded = false,
  auto_pin_checked = {}
}

local defaults = {
  pinned_track_guid = "",
  add_fx_target = "tk_fx_browser",
  show_screenshots = true,
  screenshot_height = 90,
  show_track_fx = true,
  show_pinned_params = true,
  show_input_fx = false,
  show_selected_item_fx = false,
  show_ab = false,
  tile_compact = false,
  body_collapsed = false,
  macro_param_slots = 4,
  macro_count = 8,
  show_macros = true,
  orientation = "vertical",
  horizontal_tile_width = 240,
  hide_horizontal_scrollbar = false,
  invert_horizontal_scroll = false,
  section_order = "default",
  section_track_color = false,
  show_item_name_overlay = true,
  show_info_bar = true,
  auto_apply_default_pins = false
}

local function ensure_settings(app)
  app.settings.instrument_rack = app.settings.instrument_rack or {}
  local settings = app.settings.instrument_rack
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  if settings.macro_param_slots ~= 8 then settings.macro_param_slots = 4 end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function param_slot_count(settings)
  return settings and tonumber(settings.macro_param_slots) == 8 and 8 or 4
end

local function validate_track(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
  if r.ValidatePtr then return r.ValidatePtr(track, "MediaTrack*") end
  return true
end

local function validate_item(item)
  if not item then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, item, "MediaItem*") end
  if r.ValidatePtr then return r.ValidatePtr(item, "MediaItem*") end
  return true
end

local function validate_take(take)
  if not take then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, take, "MediaItem_Take*") end
  if r.ValidatePtr then return r.ValidatePtr(take, "MediaItem_Take*") end
  return true
end

local function track_guid(track)
  if not validate_track(track) then return "" end
  if track == r.GetMasterTrack(0) then return "MASTER" end
  return r.GetTrackGUID(track) or ""
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  if guid == "MASTER" then return r.GetMasterTrack(0) end
  if r.BR_GetMediaTrackByGUID then
    local track = r.BR_GetMediaTrackByGUID(0, guid)
    if validate_track(track) then return track end
  end
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    if track and r.GetTrackGUID(track) == guid then return track end
  end
  return nil
end

local function get_target_track(settings)
  local pinned = find_track_by_guid(settings.pinned_track_guid)
  if pinned then return pinned end
  local master = r.GetMasterTrack(0)
  if master and r.IsTrackSelected and r.IsTrackSelected(master) then return master end
  local selected = r.GetSelectedTrack(0, 0)
  if selected then return selected end
  return r.GetTrack(0, 0)
end

local function get_track_label(track)
  if not validate_track(track) then return "No track" end
  if track == r.GetMasterTrack(0) then return "MASTER" end
  local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  local _, name = r.GetTrackName(track)
  if not name or name == "" then name = "Track " .. tostring(index) end
  return tostring(index) .. " - " .. name
end

local function get_selected_take(target_track)
  local item = r.GetSelectedMediaItem(0, 0)
  if not validate_item(item) then return nil, nil end
  if validate_track(target_track) and r.GetMediaItemTrack(item) ~= target_track then return item, nil, false end
  local take = r.GetActiveTake(item)
  if not validate_take(take) then return item, nil end
  return item, take, true
end

local function get_take_label(take)
  if not validate_take(take) then return "No selected item" end
  local ok, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if ok and name and name ~= "" then return name end
  return r.TakeIsMIDI(take) and "MIDI take" or "Audio take"
end

local function get_item_color(take)
  if not validate_take(take) or not r.GetMediaItemTake_Item then return nil end
  local item = r.GetMediaItemTake_Item(take)
  if not item then return nil end
  local native = r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR") or 0
  if native == 0 or (native & 0x1000000) == 0 then return nil end
  local cr, cg, cb = r.ColorFromNative(native)
  return ((cr & 0xFF) << 24) | ((cg & 0xFF) << 16) | ((cb & 0xFF) << 8) | 0xFF
end

local function get_available_width(ctx)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  return tonumber(width) or 0
end

local function get_centered_item_width(ctx)
  local width = get_available_width(ctx)
  if width <= 0 then return UIScale.round(220) end
  if width < UIScale.round(240) then return math.max(1, width) end
  return math.min(width - UIScale.round(12), UIScale.round(560))
end

local function center_next_item(ctx, item_width)
  local width = get_available_width(ctx)
  if width > item_width then
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.floor((width - item_width) * 0.5))
  end
end

local function strip_x86(value)
  value = tostring(value or "")
  value = value:gsub("%s*%([xX]86%)", "")
  value = value:gsub("%s*%([xX]64%)", "")
  return value
end

local function clean_fx_name(value)
  local name = strip_x86(value)
  name = name:gsub("^[%w%d]+i?:%s*", "")
  name = name:gsub("%(%w+ ?%w*%)$", "")
  name = name:gsub("%s+$", "")
  return name
end

local function normalize_plugin_name(value)
  local name = strip_x86(value):lower()
  name = name:gsub("^vst3i?:%s*", "")
  name = name:gsub("^vsti?:%s*", "")
  name = name:gsub("^vst3:%s*", "")
  name = name:gsub("^vst:%s*", "")
  name = name:gsub("^jsfx:%s*", "")
  name = name:gsub("^js:%s*", "")
  name = name:gsub("^clapi?:%s*", "")
  name = name:gsub("^clap:%s*", "")
  name = name:gsub("^au:%s*", "")
  name = name:gsub("^lv2i?:%s*", "")
  name = name:gsub("%s+$", "")
  name = name:gsub("%s+", " ")
  name = name:gsub("[^%w]+", "")
  return name
end

local function build_screenshot_index(force)
  if state.screenshot_index and not force then return end
  state.screenshot_index = {}
  if not r.file_exists(state.screenshot_path) then return end
  local index = 0
  while true do
    local file_name = r.EnumerateFiles(state.screenshot_path, index)
    if not file_name then break end
    local base = file_name:match("(.+)%.png$") or file_name:match("(.+)%.jpg$") or file_name:match("(.+)%.jpeg$")
    if base then state.screenshot_index[normalize_plugin_name(base)] = file_name end
    index = index + 1
  end
end

local function file_exists(path)
  if r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function current_project()
  local project = r.EnumProjects(-1, "")
  return project or 0
end

local function clean_storage_field(value)
  return tostring(value or ""):gsub("[\t\r\n]", " ")
end

local function split_storage_fields(line)
  local fields = {}
  for field in (tostring(line or "") .. "\t"):gmatch("([^\t]*)\t") do
    fields[#fields + 1] = field
  end
  return fields
end

local function get_fx_guid(track, fx_index)
  local guid = r.TrackFX_GetFXGUID(track, fx_index)
  if guid and guid ~= "" then return guid end
  return "INDEX:" .. tostring(fx_index)
end

local function find_fx_index_by_guid(track, fx_guid)
  if not validate_track(track) or not fx_guid or fx_guid == "" then return nil end
  local normal_count = r.TrackFX_GetCount(track) or 0
  for index = 0, normal_count - 1 do
    if get_fx_guid(track, index) == fx_guid then return index end
  end
  local input_count = r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(track) or 0
  for index = 0, input_count - 1 do
    local fx_index = REC_FX_OFFSET + index
    if get_fx_guid(track, fx_index) == fx_guid then return fx_index end
  end
  local fallback = fx_guid:match("^INDEX:(%-?%d+)$")
  return fallback and tonumber(fallback) or nil
end

local function param_key(fx_guid, param_idx)
  return tostring(fx_guid or "") .. "|" .. tostring(param_idx or -1)
end

local function load_pinned_params()
  local project = current_project()
  state.pinned_project = project
  state.pinned_params = {}
  if not r.GetProjExtState then return end
  local _, content = r.GetProjExtState(project, EXT_SECTION, "pinned_params")
  if not content or content == "" then return end
  for line in content:gmatch("[^\r\n]+") do
    local track_id, fx_guid, param_idx, param_name, fx_name, slot = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
    if not track_id then
      track_id, fx_guid, param_idx, param_name, fx_name = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    end
    param_idx = tonumber(param_idx)
    slot = tonumber(slot)
    if track_id and track_id ~= "" and fx_guid and fx_guid ~= "" and param_idx then
      state.pinned_params[track_id] = state.pinned_params[track_id] or {}
      state.pinned_params[track_id][param_key(fx_guid, param_idx)] = {
        track_guid = track_id,
        fx_guid = fx_guid,
        param_idx = param_idx,
        param_name = param_name or "",
        fx_name = fx_name or "",
        slot = slot
      }
    end
  end
end

local function ensure_pinned_params_loaded()
  local project = current_project()
  if state.pinned_project ~= project then load_pinned_params() end
end

local function save_pinned_params()
  if not r.SetProjExtState then return end
  ensure_pinned_params_loaded()
  local lines = {}
  for track_id, entries in pairs(state.pinned_params) do
    for _, entry in pairs(entries) do
      lines[#lines + 1] = table.concat({
        clean_storage_field(track_id),
        clean_storage_field(entry.fx_guid),
        tostring(entry.param_idx),
        clean_storage_field(entry.param_name),
        clean_storage_field(entry.fx_name),
        tostring(tonumber(entry.slot) or "")
      }, "\t")
    end
  end
  table.sort(lines)
  r.SetProjExtState(current_project(), EXT_SECTION, "pinned_params", table.concat(lines, "\n"))
end

local function default_macro_name(slot)
  return "Macro " .. tostring(slot)
end

local function ensure_macro_entry(track_id, slot)
  state.macros[track_id] = state.macros[track_id] or {}
  if not state.macros[track_id][slot] then
    state.macros[track_id][slot] = { name = default_macro_name(slot), value = 0 }
  end
  return state.macros[track_id][slot]
end

local function load_macros()
  local project = current_project()
  state.macro_project = project
  state.macros = {}
  state.macro_assignments = {}
  state.macro_name_buffers = {}
  if not r.GetProjExtState then return end
  local _, defs = r.GetProjExtState(project, EXT_SECTION, "macro_defs")
  if defs and defs ~= "" then
    for line in defs:gmatch("[^\r\n]+") do
      local fields = split_storage_fields(line)
      local track_id, slot, name, value = fields[1], fields[2], fields[3], fields[4]
      slot = tonumber(slot)
      if track_id and track_id ~= "" and slot and slot >= 1 and slot <= MACRO_MAX then
        state.macros[track_id] = state.macros[track_id] or {}
        state.macros[track_id][slot] = {
          name = name ~= "" and name or default_macro_name(slot),
          value = math.max(0, math.min(1, tonumber(value) or 0)),
          cc_channel = tonumber(fields[5]),
          cc_number = tonumber(fields[6]),
          cc_device = tonumber(fields[7]),
          cc_mode = fields[8] ~= "" and fields[8] or nil,
          cc_invert = fields[9] == "1",
          cc_min = tonumber(fields[10]),
          cc_max = tonumber(fields[11]),
          cc_type = fields[12] ~= "" and fields[12] or "cc",
          cc_sensitivity = tonumber(fields[13])
        }
      end
    end
  end
  local _, assignments = r.GetProjExtState(project, EXT_SECTION, "macro_assignments")
  if assignments and assignments ~= "" then
    for line in assignments:gmatch("[^\r\n]+") do
      local track_id, slot, fx_guid, param_idx, param_name, fx_name, range_min, range_max, inverted = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$")
      slot = tonumber(slot)
      param_idx = tonumber(param_idx)
      if track_id and track_id ~= "" and slot and slot >= 1 and slot <= MACRO_MAX and fx_guid and fx_guid ~= "" and param_idx then
        state.macro_assignments[track_id] = state.macro_assignments[track_id] or {}
        state.macro_assignments[track_id][slot] = state.macro_assignments[track_id][slot] or {}
        state.macro_assignments[track_id][slot][#state.macro_assignments[track_id][slot] + 1] = {
          track_guid = track_id,
          fx_guid = fx_guid,
          param_idx = param_idx,
          param_name = param_name or "",
          fx_name = fx_name or "",
          range_min = math.max(0, math.min(1, tonumber(range_min) or 0)),
          range_max = math.max(0, math.min(1, tonumber(range_max) or 1)),
          inverted = inverted == "1"
        }
      end
    end
  end
end

local function ensure_macros_loaded()
  local project = current_project()
  if state.macro_project ~= project then load_macros() end
end

local function save_macros()
  if not r.SetProjExtState then return end
  ensure_macros_loaded()
  local def_lines = {}
  for track_id, macros in pairs(state.macros) do
    for slot, macro in pairs(macros) do
      def_lines[#def_lines + 1] = table.concat({
        clean_storage_field(track_id),
        tostring(slot),
        clean_storage_field(macro.name or default_macro_name(slot)),
        tostring(math.max(0, math.min(1, tonumber(macro.value) or 0))),
        tostring(tonumber(macro.cc_channel) or ""),
        tostring(tonumber(macro.cc_number) or ""),
        tostring(tonumber(macro.cc_device) or ""),
        clean_storage_field(macro.cc_mode or ""),
        macro.cc_invert and "1" or "0",
        tostring(tonumber(macro.cc_min) or ""),
        tostring(tonumber(macro.cc_max) or ""),
        clean_storage_field(macro.cc_type or "cc"),
        tostring(tonumber(macro.cc_sensitivity) or "")
      }, "\t")
    end
  end
  table.sort(def_lines)
  local assignment_lines = {}
  for track_id, macros in pairs(state.macro_assignments) do
    for slot, assignments in pairs(macros) do
      for _, assignment in ipairs(assignments) do
        assignment_lines[#assignment_lines + 1] = table.concat({
          clean_storage_field(track_id),
          tostring(slot),
          clean_storage_field(assignment.fx_guid),
          tostring(assignment.param_idx),
          clean_storage_field(assignment.param_name),
          clean_storage_field(assignment.fx_name),
          tostring(tonumber(assignment.range_min) or 0),
          tostring(tonumber(assignment.range_max) or 1),
          assignment.inverted and "1" or "0"
        }, "\t")
      end
    end
  end
  table.sort(assignment_lines)
  r.SetProjExtState(current_project(), EXT_SECTION, "macro_defs", table.concat(def_lines, "\n"))
  r.SetProjExtState(current_project(), EXT_SECTION, "macro_assignments", table.concat(assignment_lines, "\n"))
end

local function get_macro_assignments(track_id, slot)
  state.macro_assignments[track_id] = state.macro_assignments[track_id] or {}
  state.macro_assignments[track_id][slot] = state.macro_assignments[track_id][slot] or {}
  return state.macro_assignments[track_id][slot]
end

local function assign_param_to_macro(app, track, fx_index, param_idx, slot)
  if not validate_track(track) or not fx_index or not param_idx then return end
  ensure_macros_loaded()
  local track_id = track_guid(track)
  local fx_guid = get_fx_guid(track, fx_index)
  local assignments = get_macro_assignments(track_id, slot)
  for _, assignment in ipairs(assignments) do
    if assignment.fx_guid == fx_guid and assignment.param_idx == param_idx then
      app.status = "Parameter already assigned to " .. default_macro_name(slot)
      return
    end
  end
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local _, param_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
  ensure_macro_entry(track_id, slot)
  assignments[#assignments + 1] = {
    track_guid = track_id,
    fx_guid = fx_guid,
    param_idx = param_idx,
    param_name = param_name ~= "" and param_name or ("Param " .. tostring(param_idx)),
    fx_name = fx_name or "",
    range_min = 0,
    range_max = 1,
    inverted = false
  }
  save_macros()
  app.status = "Assigned " .. (param_name ~= "" and param_name or ("Param " .. tostring(param_idx))) .. " to " .. default_macro_name(slot)
end

local function format_macro_cc_label(macro)
  local channel = tonumber(macro and macro.cc_channel)
  local number = tonumber(macro and macro.cc_number)
  local event_type = macro and macro.cc_type or "cc"
  if not channel or not number then return "" end
  local label = "CC " .. tostring(number)
  if event_type == "pitch" then label = "Pitch Bend" end
  if event_type == "channel_pressure" then label = "Channel Pressure" end
  if event_type == "poly_pressure" then label = "Poly Pressure " .. tostring(number) end
  label = label .. " Ch " .. tostring(channel)
  if macro.cc_mode == "relative_twos" then label = label .. " Rel 1/127" end
  if macro.cc_mode == "relative_offset" or macro.cc_mode == "relative" then label = label .. " Rel 63/65" end
  if macro.cc_mode == "relative_sign" then label = label .. " Rel 1/65" end
  if (macro.cc_mode == "relative_twos" or macro.cc_mode == "relative_offset" or macro.cc_mode == "relative" or macro.cc_mode == "relative_sign") and tonumber(macro.cc_sensitivity) and tonumber(macro.cc_sensitivity) ~= 1 then label = label .. " " .. tostring(macro.cc_sensitivity) .. "x" end
  if (macro.cc_mode == nil or macro.cc_mode == "absolute") and tonumber(macro.cc_min) and tonumber(macro.cc_max) then label = label .. " Range " .. tostring(math.floor(macro.cc_min)) .. "-" .. tostring(math.floor(macro.cc_max)) end
  if macro.cc_invert then label = label .. " Inverted" end
  return label
end

local function macro_has_cc(macro)
  return tonumber(macro and macro.cc_channel) ~= nil and tonumber(macro and macro.cc_number) ~= nil
end

local function macro_matches_midi_event(macro, event)
  if not macro_has_cc(macro) or not event then return false end
  return (macro.cc_type or "cc") == (event.type or "cc") and tonumber(macro.cc_channel) == event.channel and tonumber(macro.cc_number) == event.number
end

local function read_recent_midi_ccs()
  if not r.MIDI_GetRecentInputEvent then return {} end
  if state.midi_last_retval == nil then
    state.midi_last_retval = r.MIDI_GetRecentInputEvent(0) or 0
    return {}
  end
  local events = {}
  local first_retval = nil
  local index = 0
  while index < 128 do
    local retval, rawmsg, tsval, device = r.MIDI_GetRecentInputEvent(index)
    if index == 0 then first_retval = retval end
    if retval == 0 or retval == state.midi_last_retval then break end
    if rawmsg and #rawmsg >= 2 then
      local status = rawmsg:byte(1)
      local status_type = status & 0xF0
      local channel = (status & 0x0F) + 1
      local data1 = rawmsg:byte(2) or 0
      local data2 = rawmsg:byte(3) or 0
      if status_type == 0xB0 then
        events[#events + 1] = {
          type = "cc",
          channel = channel,
          number = data1,
          raw_value = data2,
          max_raw = 127,
          value = math.max(0, math.min(1, data2 / 127)),
          device = device,
          tsval = tsval
        }
      elseif status_type == 0xE0 then
        local raw_value = data1 + data2 * 128
        events[#events + 1] = {
          type = "pitch",
          channel = channel,
          number = -1,
          raw_value = raw_value,
          max_raw = 16383,
          value = math.max(0, math.min(1, raw_value / 16383)),
          device = device,
          tsval = tsval
        }
      elseif status_type == 0xD0 then
        events[#events + 1] = {
          type = "channel_pressure",
          channel = channel,
          number = -2,
          raw_value = data1,
          max_raw = 127,
          value = math.max(0, math.min(1, data1 / 127)),
          device = device,
          tsval = tsval
        }
      elseif status_type == 0xA0 then
        events[#events + 1] = {
          type = "poly_pressure",
          channel = channel,
          number = data1,
          raw_value = data2,
          max_raw = 127,
          value = math.max(0, math.min(1, data2 / 127)),
          device = device,
          tsval = tsval
        }
      end
    end
    index = index + 1
  end
  if first_retval and first_retval ~= 0 then state.midi_last_retval = first_retval end
  return events
end

local function detect_cc_mode(event)
  return "absolute"
end

local function relative_cc_delta(raw, mode)
  raw = tonumber(raw) or 0
  if mode == "relative_twos" then
    if raw >= 1 and raw <= 63 then return raw end
    if raw >= 65 and raw <= 127 then return raw - 128 end
    return 0
  end
  if mode == "relative_sign" then
    if raw >= 1 and raw <= 63 then return raw end
    if raw >= 65 and raw <= 127 then return -(raw - 64) end
    return 0
  end
  if raw >= 1 and raw <= 63 then return raw - 64 end
  if raw >= 65 and raw <= 127 then return raw - 64 end
  return 0
end

local function is_macro_cc_relative(macro)
  local mode = macro and macro.cc_mode
  return mode == "relative" or mode == "relative_offset" or mode == "relative_twos" or mode == "relative_sign"
end

local function absolute_cc_value(macro, event)
  local raw = tonumber(event and event.raw_value) or 0
  local max_raw = tonumber(event and event.max_raw) or 127
  local min_value = tonumber(macro.cc_min)
  local max_value = tonumber(macro.cc_max)
  local old_min = min_value
  local old_max = max_value
  local changed = false
  if not min_value or raw < min_value then
    min_value = raw
    macro.cc_min = raw
    changed = true
  end
  if not max_value or raw > max_value then
    max_value = raw
    macro.cc_max = raw
    changed = true
  end
  if changed then state.macros_dirty = true end
  local old_span = old_min and old_max and old_max - old_min or 0
  local expanded_range = changed and (raw == min_value or raw == max_value)
  if old_span >= 8 and not expanded_range then return math.max(0, math.min(1, (raw - old_min) / old_span)) end
  local span = (max_value or max_raw) - (min_value or 0)
  if span >= 24 and not expanded_range then return math.max(0, math.min(1, (raw - min_value) / span)) end
  return math.max(0, math.min(1, raw / max_raw))
end

local function macro_value_from_cc_event(macro, event)
  if is_macro_cc_relative(macro) then
    local mode = macro.cc_mode == "relative" and "relative_offset" or macro.cc_mode
    local delta = relative_cc_delta(event.raw_value, mode)
    if macro.cc_invert then delta = -delta end
    local sensitivity = math.max(0.25, math.min(8, tonumber(macro.cc_sensitivity) or 1))
    return math.max(0, math.min(1, (tonumber(macro.value) or 0) + delta * sensitivity / 127))
  end
  local value = macro and absolute_cc_value(macro, event) or event.value
  return macro and macro.cc_invert and (1 - value) or value
end

local function start_macro_cc_learn(app, track, slot)
  if not r.MIDI_GetRecentInputEvent then
    app.status = "MIDI input event API not available"
    return
  end
  state.midi_last_retval = r.MIDI_GetRecentInputEvent(0) or 0
  state.macro_cc_learn = { track_guid = track_guid(track), slot = slot }
  app.status = "Move a MIDI CC for " .. default_macro_name(slot)
end

local function normalize_slots_for_fx(track_id, fx_guid)
  local entries = state.pinned_params[track_id]
  if not entries then return false end
  local bucket = {}
  for _, entry in pairs(entries) do
    if entry.fx_guid == fx_guid then bucket[#bucket + 1] = entry end
  end
  if #bucket == 0 then return false end
  table.sort(bucket, function(left, right)
    local left_slot = tonumber(left.slot)
    local right_slot = tonumber(right.slot)
    local left_valid = left_slot and left_slot >= 1 and left_slot <= MAX_PARAM_SLOTS
    local right_valid = right_slot and right_slot >= 1 and right_slot <= MAX_PARAM_SLOTS
    local left_order = left_valid and left_slot or 999
    local right_order = right_valid and right_slot or 999
    if left_order ~= right_order then return left_order < right_order end
    if left.param_idx ~= right.param_idx then return left.param_idx < right.param_idx end
    return tostring(left.param_name or "") < tostring(right.param_name or "")
  end)
  local used = {}
  local changed = false
  for _, entry in ipairs(bucket) do
    local slot = tonumber(entry.slot)
    if slot and slot >= 1 and slot <= MAX_PARAM_SLOTS and not used[slot] then
      used[slot] = true
    else
      local assigned = nil
      for index = 1, MAX_PARAM_SLOTS do
        if not used[index] then
          assigned = index
          break
        end
      end
      if assigned then
        entry.slot = assigned
        used[assigned] = true
        changed = true
      end
    end
  end
  return changed
end

local function get_pinned_for_fx(track, fx_index)
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local fx_guid = get_fx_guid(track, fx_index)
  local changed_slots = normalize_slots_for_fx(track_id, fx_guid)
  local result = {}
  local entries = state.pinned_params[track_id]
  if not entries then return result end
  local param_count = r.TrackFX_GetNumParams(track, fx_index)
  for _, entry in pairs(entries) do
    if entry.fx_guid == fx_guid and entry.param_idx >= 0 and entry.param_idx < param_count then
      result[#result + 1] = entry
    end
  end
  table.sort(result, function(left, right)
    local left_slot = tonumber(left.slot) or 999
    local right_slot = tonumber(right.slot) or 999
    if left_slot ~= right_slot then return left_slot < right_slot end
    if left.param_idx ~= right.param_idx then return left.param_idx < right.param_idx end
    return tostring(left.param_name or "") < tostring(right.param_name or "")
  end)
  if changed_slots then save_pinned_params() end
  return result
end

local function pin_parameter(app, track, fx_index, param_idx, preferred_slot)
  if not validate_track(track) or not param_idx or param_idx < 0 then return end
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local fx_guid = get_fx_guid(track, fx_index)
  state.pinned_params[track_id] = state.pinned_params[track_id] or {}
  local key = param_key(fx_guid, param_idx)
  if state.pinned_params[track_id][key] then
    app.status = "Parameter already pinned"
    return
  end
  local settings = ensure_settings(app)
  local slot_count = param_slot_count(settings)
  local pinned = get_pinned_for_fx(track, fx_index)
  local used_slots = {}
  for _, entry in ipairs(pinned) do
    local slot = tonumber(entry.slot)
    if slot and slot >= 1 and slot <= slot_count then used_slots[slot] = true end
  end
  local requested_slot = tonumber(preferred_slot)
  if requested_slot and (requested_slot < 1 or requested_slot > slot_count) then
    requested_slot = nil
  end
  if requested_slot and used_slots[requested_slot] then
    app.status = "Selected slot is already in use"
    return
  end
  local assigned_slot = requested_slot
  if not assigned_slot then
    for index = 1, slot_count do
      if not used_slots[index] then
        assigned_slot = index
        break
      end
    end
  end
  if not assigned_slot then
    app.status = "Parameter slots are full"
    return
  end
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local _, param_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
  state.pinned_params[track_id][key] = {
    track_guid = track_id,
    fx_guid = fx_guid,
    param_idx = param_idx,
    param_name = param_name or ("Param " .. tostring(param_idx)),
    fx_name = fx_name or "",
    slot = assigned_slot
  }
  save_pinned_params()
  app.status = "Pinned " .. (param_name ~= "" and param_name or ("Param " .. tostring(param_idx)))
end

local function unpin_parameter(app, track, fx_index, param_idx)
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local entries = state.pinned_params[track_id]
  if not entries then return end
  entries[param_key(get_fx_guid(track, fx_index), param_idx)] = nil
  save_pinned_params()
  app.status = "Parameter unpinned"
end

local function fx_plugin_key(track, fx_index)
  if r.TrackFX_GetNamedConfigParm then
    local ok, ident = r.TrackFX_GetNamedConfigParm(track, fx_index, "fx_ident")
    if ok and ident and ident ~= "" then return ident end
  end
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  return clean_fx_name(fx_name or "")
end

local function load_default_pins()
  state.default_pins = {}
  state.default_pins_loaded = true
  if not r.GetExtState then return end
  local content = r.GetExtState(EXT_SECTION, "default_pins")
  if not content or content == "" then return end
  for line in content:gmatch("[^\r\n]+") do
    local fields = split_storage_fields(line)
    local key, slot, param_idx, param_name = fields[1], tonumber(fields[2]), tonumber(fields[3]), fields[4]
    if key and key ~= "" and param_idx then
      state.default_pins[key] = state.default_pins[key] or {}
      state.default_pins[key][#state.default_pins[key] + 1] = {
        slot = slot,
        param_idx = param_idx,
        param_name = param_name or ""
      }
    end
  end
end

local function ensure_default_pins_loaded()
  if not state.default_pins_loaded then load_default_pins() end
end

local function save_default_pins()
  if not r.SetExtState then return end
  local lines = {}
  for key, list in pairs(state.default_pins or {}) do
    for _, entry in ipairs(list) do
      lines[#lines + 1] = table.concat({
        clean_storage_field(key),
        tostring(tonumber(entry.slot) or ""),
        tostring(entry.param_idx),
        clean_storage_field(entry.param_name or "")
      }, "\t")
    end
  end
  table.sort(lines)
  r.SetExtState(EXT_SECTION, "default_pins", table.concat(lines, "\n"), true)
end

local function has_default_pins(track, fx_index)
  ensure_default_pins_loaded()
  local key = fx_plugin_key(track, fx_index)
  local list = key ~= "" and state.default_pins[key]
  return list and #list > 0
end

local function save_current_pins_as_default(app, track, fx_index)
  ensure_default_pins_loaded()
  local key = fx_plugin_key(track, fx_index)
  if key == "" then app.status = "Could not identify plugin" return end
  local pinned = get_pinned_for_fx(track, fx_index)
  if #pinned == 0 then app.status = "No pinned parameters to save" return end
  local list = {}
  for _, entry in ipairs(pinned) do
    list[#list + 1] = {
      slot = tonumber(entry.slot),
      param_idx = entry.param_idx,
      param_name = entry.param_name or ""
    }
  end
  state.default_pins[key] = list
  save_default_pins()
  app.status = "Saved " .. tostring(#list) .. " default pins for this plugin"
end

local function clear_default_pins(app, track, fx_index)
  ensure_default_pins_loaded()
  local key = fx_plugin_key(track, fx_index)
  if key == "" or not state.default_pins[key] then
    app.status = "No default pins for this plugin"
    return
  end
  state.default_pins[key] = nil
  save_default_pins()
  app.status = "Cleared default pins for this plugin"
end

local function apply_default_pins(app, track, fx_index, silent)
  ensure_default_pins_loaded()
  local key = fx_plugin_key(track, fx_index)
  local defaults_list = key ~= "" and state.default_pins[key]
  if not defaults_list or #defaults_list == 0 then
    if not silent then app.status = "No default pins for this plugin" end
    return false
  end
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local fx_guid = get_fx_guid(track, fx_index)
  state.pinned_params[track_id] = state.pinned_params[track_id] or {}
  local param_count = r.TrackFX_GetNumParams(track, fx_index)
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local applied = 0
  for _, def in ipairs(defaults_list) do
    local param_idx = def.param_idx
    if param_idx and param_idx >= 0 and param_idx < param_count then
      local _, pname = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
      if def.param_name and def.param_name ~= "" and pname ~= def.param_name then
        local found = nil
        local scan = math.min(param_count, 512)
        for i = 0, scan - 1 do
          local _, n = r.TrackFX_GetParamName(track, fx_index, i, "")
          if n == def.param_name then found = i break end
        end
        if found then param_idx = found; pname = def.param_name end
      end
      local pkey = param_key(fx_guid, param_idx)
      if not state.pinned_params[track_id][pkey] then
        state.pinned_params[track_id][pkey] = {
          track_guid = track_id,
          fx_guid = fx_guid,
          param_idx = param_idx,
          param_name = pname ~= "" and pname or ("Param " .. tostring(param_idx)),
          fx_name = fx_name or "",
          slot = def.slot
        }
        applied = applied + 1
      end
    end
  end
  if applied > 0 then save_pinned_params() end
  if not silent then
    app.status = applied > 0 and ("Applied " .. tostring(applied) .. " default pins") or "Default pins already applied"
  end
  return applied > 0
end

local function queue_param_action(action, track, fx_index, param_idx)
  if not validate_track(track) or not action or not param_idx then return end
  state.pending_param_action = {
    action = action,
    track_guid = track_guid(track),
    fx_guid = get_fx_guid(track, fx_index),
    param_idx = param_idx,
    delay = 1,
    defer_frames = action == "modulate" and 6 or 1,
    wait_mouse = action == "modulate"
  }
end

local function mouse_buttons_down()
  if not r.JS_Mouse_GetState then return false end
  return (r.JS_Mouse_GetState(0xFF) & 0xFF) ~= 0
end

local function nudge_param_as_last_touched(track, fx_index, param_idx)
  local _, _, minv, maxv = r.TrackFX_GetParamEx(track, fx_index, param_idx)
  local cur = r.TrackFX_GetParam(track, fx_index, param_idx)
  local range = (maxv or 1) - (minv or 0)
  if range == 0 then range = 1 end
  local eps = range * 1e-6
  local nudged = cur + eps
  if maxv and nudged > maxv then nudged = cur - eps end
  r.TrackFX_SetParam(track, fx_index, param_idx, nudged)
  r.TrackFX_SetParam(track, fx_index, param_idx, cur)
end

local function execute_param_action(app, pending)
  local track = find_track_by_guid(pending.track_guid)
  local fx_index = find_fx_index_by_guid(track, pending.fx_guid)
  if not validate_track(track) or not fx_index then return end
  if pending.action == "learn" then
    nudge_param_as_last_touched(track, fx_index, pending.param_idx)
    r.Main_OnCommand(41144, 0)
    app.status = "Opened MIDI learn"
  end
end

local function defer_param_action(app, pending, frames)
  if frames > 0 or (pending.wait_mouse and mouse_buttons_down()) then
    r.defer(function() defer_param_action(app, pending, frames - 1) end)
    return
  end
  execute_param_action(app, pending)
end

local function run_pending_param_action(app)
  local pending = state.pending_param_action
  if not pending then return end
  if pending.delay and pending.delay > 0 then
    pending.delay = pending.delay - 1
    return
  end
  state.pending_param_action = nil
  r.defer(function() defer_param_action(app, pending, pending.defer_frames or 1) end)
end

local function draw_param_context_menu(app, ctx, track, fx_index, param_idx)
  local request_unpin = false
  local current_value = r.TrackFX_GetParam(track, fx_index, param_idx)
  if r.ImGui_MenuItem(ctx, "Reset") then
    local _, default_value = r.TrackFX_GetParamEx(track, fx_index, param_idx)
    r.TrackFX_SetParam(track, fx_index, param_idx, default_value or 0)
    app.status = "Parameter reset"
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Learn (MIDI CC)") then
    queue_param_action("learn", track, fx_index, param_idx)
    app.status = "Opening MIDI learn"
  end
  if r.ImGui_MenuItem(ctx, "Modulate") then
    r.Main_OnCommand(41143, 0)
    app.status = "Opened parameter modulation"
  end
  if r.ImGui_MenuItem(ctx, "Show Envelope") then
    local envelope = r.GetFXEnvelope(track, fx_index, param_idx, true)
    if envelope then
      r.TrackList_AdjustWindows(false)
      app.status = "Parameter envelope shown"
    end
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_BeginMenu(ctx, "Assign to Macro") then
    for slot = 1, state.macro_count do
      if r.ImGui_MenuItem(ctx, default_macro_name(slot) .. "##ir_assign_macro_" .. tostring(slot)) then
        assign_param_to_macro(app, track, fx_index, param_idx, slot)
      end
    end
    r.ImGui_EndMenu(ctx)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Unpin") then request_unpin = true end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Open FX Chain") then r.TrackFX_Show(track, fx_index, 1) end
  if r.ImGui_MenuItem(ctx, "Open FX Window") then
    local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
    r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
  end
  return request_unpin
end

local function get_screenshot_path(plugin_name)
  if not plugin_name or plugin_name == "" then return nil end
  local now = r.time_precise()
  local missing = state.screenshot_missing[plugin_name]
  if missing and now - missing < 600 then return nil end
  state.screenshot_missing[plugin_name] = nil
  local cached = state.screenshot_cache[plugin_name]
  if cached and cached.path then
    cached.t = now
    return cached.path
  end
  build_screenshot_index(false)
  local indexed = state.screenshot_index and state.screenshot_index[normalize_plugin_name(plugin_name)]
  if indexed then
    local path = state.screenshot_path .. indexed
    state.screenshot_cache[plugin_name] = { path = path, t = now }
    return path
  end
  local cleaned = clean_fx_name(plugin_name)
  local variants = {
    plugin_name,
    plugin_name:gsub("[^%w%s%-]", "_"),
    cleaned,
    cleaned:gsub("[^%w%s%-]", "_"),
    strip_x86(plugin_name),
    clean_fx_name(strip_x86(plugin_name))
  }
  local seen = {}
  for _, base in ipairs(variants) do
    if base and base ~= "" and not seen[base] then
      seen[base] = true
      for _, ext in ipairs({ ".png", ".jpg", ".jpeg" }) do
        local path = state.screenshot_path .. base .. ext
        if file_exists(path) then
          state.screenshot_cache[plugin_name] = { path = path, t = now }
          return path
        end
      end
    end
  end
  state.screenshot_missing[plugin_name] = now
  return nil
end

local function get_screenshot_image(ctx, plugin_name)
  if not r.ImGui_CreateImage then return nil end
  local path = get_screenshot_path(plugin_name)
  if not path then return nil end
  local entry = state.screenshot_cache[plugin_name]
  if entry and entry.img then
    if not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(entry.img, "ImGui_Image*") then
      entry.t = r.time_precise()
      return entry.img
    end
  end
  local ok, img = pcall(r.ImGui_CreateImage, path)
  if ok and img then
    pcall(r.ImGui_Attach, ctx, img)
    entry.img = img
    entry.t = r.time_precise()
    return img
  end
  return nil
end

local function select_only_track(track)
  if not validate_track(track) then return end
  r.Main_OnCommand(40297, 0)
  if track == r.GetMasterTrack(0) then
    if r.SetMasterTrackVisibility then r.SetMasterTrackVisibility(1) end
  else
    r.SetTrackSelected(track, true)
  end
end

local function open_input_fx_chain(track)
  if not validate_track(track) or not r.TrackFX_Show then return false end
  r.TrackFX_Show(track, REC_FX_OFFSET, 1)
  return true
end

local function open_take_fx_chain(take)
  if not validate_take(take) or not r.TakeFX_Show then return false end
  r.TakeFX_Show(take, 0, 1)
  return true
end

local function open_add_fx_browser(app, track, target_type, take)
  local settings = ensure_settings(app)
  if not validate_track(track) then return end
  target_type = target_type or "track"
  select_only_track(track)
  local target = settings.add_fx_target or "tk_fx_browser"
  if target == "native" then
    if target_type == "input" then
      app.status = open_input_fx_chain(track) and "Opened input FX chain" or "Could not open input FX chain"
      return
    elseif target_type == "item" then
      app.status = open_take_fx_chain(take) and "Opened item FX chain" or "Could not open item FX chain"
      return
    end
    r.Main_OnCommand(40271, 0)
    app.status = "Opened native FX browser"
    return
  end
  if target == "plugin_browser" and app.modules_by_id and app.modules_by_id.plugin_browser then
    if app.set_active_view then
      app.set_active_view("plugin_browser")
    else
      app.settings.active_module = "plugin_browser"
      if app.save_settings then app.save_settings() end
    end
    app.status = "Opened Plugin Browser"
    return
  end
  if target == "plugin_browser" then
    local ok, runner = pcall(require, "core.workbench_module_action_runner")
    if ok and runner and runner.open and runner.open("plugin_browser") then
      app.status = "Opened Plugin Browser in Workbench"
    else
      app.status = "Could not open Workbench Plugin Browser"
    end
    return
  end
  local use_mini = target == "tk_fx_browser_mini"
  local section = use_mini and "TK_FX_BROWSER_MINI" or "TK_FX_BROWSER"
  local script_rel = use_mini and "/Scripts/TK Scripts/FX/TK_FX_BROWSER Mini.lua" or "/Scripts/TK Scripts/FX/TK_FX_BROWSER.lua"
  local nice_name = use_mini and "TK FX BROWSER Mini" or "TK FX BROWSER"
  local running = r.GetExtState(section, "running") == "true"
  local heartbeat = tonumber(r.GetExtState(section, "heartbeat")) or 0
  local alive = running and (r.time_precise() - heartbeat < 2.0)
  if alive then
    local visible = r.GetExtState(section, "visibility")
    r.SetExtState(section, "visibility", visible == "hidden" and "visible" or "hidden", true)
    app.status = "Toggled " .. nice_name
    return
  end
  if running and not alive then r.SetExtState(section, "running", "false", true) end
  local script_path = r.GetResourcePath() .. script_rel
  if not file_exists(script_path) then
    app.status = nice_name .. " script not found"
    return
  end
  if r.AddRemoveReaScript then
    local cmd_id = r.AddRemoveReaScript(true, 0, script_path, true)
    if cmd_id and cmd_id ~= 0 then
      r.SetExtState(section, "visibility", "visible", true)
      r.Main_OnCommand(cmd_id, 0)
      app.status = "Opened " .. nice_name
      return
    end
  end
  app.status = "Start " .. nice_name .. " once from the Actions list"
end

local function get_track_header_color(track)
  if not validate_track(track) then return 0x44444488 end
  local native = r.GetTrackColor(track) or 0
  if native == 0 then return 0x44444488 end
  local cr, cg, cb = r.ColorFromNative(native)
  return ((cr & 0xFF) << 24) | ((cg & 0xFF) << 16) | ((cb & 0xFF) << 8) | 0xCC
end

local function luminance(rgba)
  local cr = (rgba >> 24) & 0xFF
  local cg = (rgba >> 16) & 0xFF
  local cb = (rgba >> 8) & 0xFF
  return (0.299 * cr + 0.587 * cg + 0.114 * cb) / 255
end

local function section_accent_color(settings, track)
  if settings and settings.section_track_color and validate_track(track) then
    local native = r.GetTrackColor(track) or 0
    if native ~= 0 then
      local cr, cg, cb = r.ColorFromNative(native)
      return ((cr & 0xFF) << 24) | ((cg & 0xFF) << 16) | ((cb & 0xFF) << 8) | 0xFF
    end
  end
  return Theme.colors.accent
end

local function launch_horizontal_rack(app)
  local script_path = (app.script_path or "") .. "TK_Instrument_Rack_Horizontal.lua"
  if not file_exists(script_path) then
    script_path = r.GetResourcePath() .. "/Scripts/TK Scripts/TK Workbench/TK_Instrument_Rack_Horizontal.lua"
  end
  if not file_exists(script_path) then
    app.status = "Horizontal Instrument Rack script not found"
    return
  end
  if r.AddRemoveReaScript then
    local cmd_id = r.AddRemoveReaScript(true, 0, script_path, true)
    if cmd_id and cmd_id ~= 0 then
      r.Main_OnCommand(cmd_id, 0)
      app.status = "Opened horizontal Instrument Rack"
      return
    end
  end
  app.status = "Start the horizontal Instrument Rack once from the Actions list"
end

local function draw_header(app, ctx, settings, track)
  local label = get_track_label(track)
  local header_color = get_track_header_color(track)
  local text_color = luminance(header_color) > 0.55 and 0x000000FF or 0xFFFFFFFF
  local avail = get_available_width(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
  local start_pos_x = r.ImGui_GetCursorPosX(ctx)
  local start_pos_y = r.ImGui_GetCursorPosY(ctx)
  local pad_x, pad_y = UIScale.round(6), UIScale.round(3)
  local text_w, text_h = r.ImGui_CalcTextSize(ctx, label)
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local bar_h = math.max(text_h + pad_y * 2, button_h)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + avail, cursor_y + bar_h, header_color, UIScale.px(3))
  r.ImGui_DrawList_PushClipRect(draw_list, cursor_x + pad_x, cursor_y, cursor_x + avail - pad_x, cursor_y + bar_h)
  r.ImGui_DrawList_AddText(draw_list, cursor_x + pad_x, cursor_y + (bar_h - text_h) * 0.5, text_color, label)
  r.ImGui_DrawList_PopClipRect(draw_list)
  local pin_label = (settings.pinned_track_guid ~= "" and "Unpin" or "Pin")
  local pin_w = UIScale.text_button_w(ctx, pin_label, 0, 8)
  local gap = UIScale.round(4)
  local buttons_w = pin_w + gap + button_h
  r.ImGui_SetCursorPosX(ctx, start_pos_x + math.max(0, avail - buttons_w))
  r.ImGui_SetCursorPosY(ctx, start_pos_y + math.max(0, (bar_h - button_h) * 0.5))
  if r.ImGui_Button(ctx, pin_label .. "##ir_pin", pin_w, button_h) then
    if settings.pinned_track_guid ~= "" then
      settings.pinned_track_guid = ""
      app.status = "Instrument Rack follows selected track"
    elseif track then
      settings.pinned_track_guid = track_guid(track)
      app.status = "Instrument Rack pinned to " .. label
    end
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx, nil, gap)
  if r.ImGui_Button(ctx, "...##ir_settings", button_h, button_h) then r.ImGui_OpenPopup(ctx, "Instrument Rack Settings") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Instrument Rack settings") end
  r.ImGui_SetCursorPosX(ctx, start_pos_x)
  r.ImGui_SetCursorPosY(ctx, start_pos_y + bar_h)
  if r.ImGui_BeginPopup(ctx, "Instrument Rack Settings") then
    local changed, value
    if settings.orientation ~= "horizontal" then
      if r.ImGui_Button(ctx, "Open horizontal window##ir_open_horizontal") then
        launch_horizontal_rack(app)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_Separator(ctx)
    end
    changed, value = r.ImGui_Checkbox(ctx, "Show screenshots", settings.show_screenshots)
    if changed then settings.show_screenshots = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show parameters", settings.show_pinned_params)
    if changed then settings.show_pinned_params = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show macros", settings.show_macros ~= false)
    if changed then settings.show_macros = value; if app.save_settings then app.save_settings() end end
    local macro_total = settings.macro_count == 16 and 16 or 8
    r.ImGui_Text(ctx, "Macro count")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, tostring(macro_total) .. "##ir_macro_count", UIScale.text_button_w(ctx, tostring(macro_total), 60, 8), 0) then
      settings.macro_count = macro_total == 8 and 16 or 8
      if app.save_settings then app.save_settings() end
    end
    local slot_count = param_slot_count(settings)
    r.ImGui_Text(ctx, "Parameter buttons")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, tostring(slot_count) .. "##ir_macro_param_slots", UIScale.text_button_w(ctx, tostring(slot_count), 60, 8), 0) then
      settings.macro_param_slots = slot_count == 4 and 8 or 4
      if app.save_settings then app.save_settings() end
    end
    changed, value = r.ImGui_Checkbox(ctx, "Show track FX", settings.show_track_fx)
    if changed then settings.show_track_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show input FX", settings.show_input_fx)
    if changed then settings.show_input_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show selected item FX", settings.show_selected_item_fx)
    if changed then settings.show_selected_item_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Compact tiles", settings.tile_compact)
    if changed then settings.tile_compact = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show info bar", settings.show_info_bar ~= false)
    if changed then settings.show_info_bar = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Signal flow order (Input > Take > Track)", settings.section_order == "signal_flow")
    if changed then settings.section_order = value and "signal_flow" or "default"; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Color sections by track color", settings.section_track_color == true)
    if changed then settings.section_track_color = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show item name on item FX tiles", settings.show_item_name_overlay ~= false)
    if changed then settings.show_item_name_overlay = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Auto-apply default pins on load", settings.auto_apply_default_pins == true)
    if changed then
      settings.auto_apply_default_pins = value
      state.auto_pin_checked = {}
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Automatically pin each plugin's saved default parameters when it first appears in the rack") end
    if settings.orientation == "horizontal" then
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
      changed, value = r.ImGui_SliderInt(ctx, "Tile width", settings.horizontal_tile_width or 240, 160, 400, "%d px")
      if changed then settings.horizontal_tile_width = value; if app.save_settings then app.save_settings() end end
      changed, value = r.ImGui_Checkbox(ctx, "Hide horizontal scrollbar", settings.hide_horizontal_scrollbar)
      if changed then settings.hide_horizontal_scrollbar = value; if app.save_settings then app.save_settings() end end
      changed, value = r.ImGui_Checkbox(ctx, "Invert wheel scroll direction", settings.invert_horizontal_scroll)
      if changed then settings.invert_horizontal_scroll = value; if app.save_settings then app.save_settings() end end
    end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Screenshot height", settings.screenshot_height or 90, 48, 400, "%d px")
    if changed then settings.screenshot_height = value; if app.save_settings then app.save_settings() end end
    r.ImGui_Text(ctx, "Add FX target")
    local targets = {
      { id = "tk_fx_browser", label = "TK FX Browser" },
      { id = "tk_fx_browser_mini", label = "TK FX Browser Mini" },
      { id = "plugin_browser", label = "Plugin Browser" },
      { id = "native", label = "Native FX Browser" }
    }
    for _, target in ipairs(targets) do
      local selected = settings.add_fx_target == target.id
      if r.ImGui_MenuItem(ctx, target.label, nil, selected) then
        settings.add_fx_target = target.id
        if app.save_settings then app.save_settings() end
      end
    end
    if r.ImGui_Button(ctx, "Refresh screenshots##ir_refresh_screenshots") then
      state.screenshot_index = nil
      state.screenshot_cache = {}
      state.screenshot_missing = {}
      app.status = "Screenshot index refreshed"
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function get_fx_short_name(fx_name)
  local name = clean_fx_name(fx_name or "")
  if name == "" then name = fx_name or "FX" end
  return name
end

local function get_wet_param_index(track, fx_index)
  local idx = r.TrackFX_GetParamFromIdent(track, fx_index, ":wet")
  if idx and idx >= 0 then return idx end
  return nil
end

local function get_fx_wet(track, fx_index)
  local idx = get_wet_param_index(track, fx_index)
  if not idx then return 1.0 end
  return r.TrackFX_GetParamNormalized(track, fx_index, idx) or 1.0
end

local function set_fx_wet(track, fx_index, value)
  local idx = get_wet_param_index(track, fx_index)
  if not idx then return end
  if value < 0 then value = 0 elseif value > 1 then value = 1 end
  r.TrackFX_SetParamNormalized(track, fx_index, idx, value)
end

local function draw_wet_popup(ctx, track, fx_index, wet_value)
  if r.ImGui_BeginPopup(ctx, "##ir_wet_pop") then
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
    local changed, value = r.ImGui_SliderDouble(ctx, "Wet##ir_wet_slider", wet_value, 0.0, 1.0, "%.2f")
    if changed then set_fx_wet(track, fx_index, value) end
    if r.ImGui_Button(ctx, "Reset##ir_wet_reset") then set_fx_wet(track, fx_index, 1.0) end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_preset_popup(ctx, track, fx_index)
  if r.ImGui_BeginPopup(ctx, "##ir_preset_pop") then
    local _, preset = r.TrackFX_GetPreset(track, fx_index, "")
    r.ImGui_Text(ctx, preset ~= "" and preset or "(no preset)")
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Prev##ir_preset_prev") then r.TrackFX_NavigatePresets(track, fx_index, -1) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Next##ir_preset_next") then r.TrackFX_NavigatePresets(track, fx_index, 1) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Default##ir_preset_default") then r.TrackFX_NavigatePresets(track, fx_index, 0) end
    r.ImGui_EndPopup(ctx)
  end
end

local function delete_fx(app, track, fx_index, fx_name)
  if not validate_track(track) then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.TrackFX_Delete(track, fx_index)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Delete rack FX", -1)
  app.status = "Deleted " .. get_fx_short_name(fx_name)
end

local function add_external_fx(app, track, payload, insert_index)
  if not validate_track(track) or not payload or payload == "" then return end
  local names = {}
  for name in payload:gmatch("[^\n]+") do
    if name ~= "" then names[#names + 1] = name end
  end
  if #names == 0 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for offset, name in ipairs(names) do
    local target_index = insert_index and (-1000 - (insert_index + offset - 1)) or -1
    r.TrackFX_AddByName(track, name, false, target_index)
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to instrument rack", -1)
  r.SetExtState("TKFXB", "drag_consumed", "1", false)
  r.DeleteExtState("TKFXB", "drag_fx", false)
  if r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
  app.status = "Added " .. tostring(#names) .. " FX"
end

local function payload_to_names(payload)
  local names = {}
  if not payload or payload == "" then return names end
  for name in payload:gmatch("[^\n]+") do
    if name ~= "" then names[#names + 1] = name end
  end
  return names
end

local function add_external_input_fx(app, track, payload)
  if not validate_track(track) then return end
  local names = payload_to_names(payload)
  if #names == 0 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, name in ipairs(names) do
    local dest = r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(track) or 0
    r.TrackFX_AddByName(track, name, true, -1000 - dest)
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add input FX to instrument rack", -1)
  r.SetExtState("TKFXB", "drag_consumed", "1", false)
  r.DeleteExtState("TKFXB", "drag_fx", false)
  if r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
  app.status = "Added " .. tostring(#names) .. " input FX"
end

local function add_external_take_fx(app, take, payload)
  if not validate_take(take) or not r.TakeFX_AddByName then return end
  local names = payload_to_names(payload)
  if #names == 0 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, name in ipairs(names) do
    local dest = r.TakeFX_GetCount and r.TakeFX_GetCount(take) or 0
    r.TakeFX_AddByName(take, name, -1000 - dest)
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add item FX to instrument rack", -1)
  r.SetExtState("TKFXB", "drag_consumed", "1", false)
  r.DeleteExtState("TKFXB", "drag_fx", false)
  if r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
  app.status = "Added " .. tostring(#names) .. " item FX"
end

local function draw_fx_screenshot(ctx, settings, fx_name, width, height, enabled)
  if not settings.show_screenshots then return end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x111111FF, UIScale.px(3))
  local img = get_screenshot_image(ctx, fx_name)
  if img then
    local image_w, image_h = r.ImGui_Image_GetSize(img)
    local scale = math.min(width / image_w, height / image_h)
    local draw_w = image_w * scale
    local draw_h = image_h * scale
    local draw_x = x + (width - draw_w) * 0.5
    local draw_y = y + (height - draw_h) * 0.5
    r.ImGui_DrawList_AddImage(draw_list, img, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, enabled and 0xFFFFFFFF or 0xFFFFFF66)
  else
    local text = "no screenshot"
    local text_w = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(draw_list, x + (width - text_w) * 0.5, y + height * 0.5 - UIScale.round(6), Theme.colors.text_dim, text)
  end
  r.ImGui_InvisibleButton(ctx, "##ir_screenshot_hit", width, height)
end

local function draw_small_button(ctx, draw_list, id, x, y, width, height, label, bg, fg, tooltip)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, UIScale.px(2))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, UIScale.px(2), 0, UIScale.px(1))
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddTextEx(draw_list, nil, UIScale.round(10), x + (width - text_w) * 0.5, y + (height - UIScale.round(10)) * 0.5, fg, label)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, width, height)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local right_clicked = r.ImGui_IsItemClicked(ctx, 1)
  if tooltip and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip) end
  return clicked, right_clicked
end

local function draw_pin_menu(app, ctx, track, fx_index, target_slot)
  if r.GetLastTouchedFX then
    local ok, track_index, touched_fx, param_idx = r.GetLastTouchedFX()
    local touched_track = nil
    if ok then
      if track_index == 0 then touched_track = r.GetMasterTrack(0) else touched_track = r.GetTrack(0, track_index - 1) end
    end
    local matches = ok and touched_track == track and touched_fx == fx_index and param_idx and param_idx >= 0
    local label = "Pin last touched parameter"
    if matches then
      local _, param_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
      label = "Pin last touched: " .. (param_name ~= "" and param_name or ("Param " .. tostring(param_idx)))
    end
    if target_slot then label = label .. " to slot " .. tostring(target_slot) end
    if r.ImGui_MenuItem(ctx, label, nil, false, matches) then pin_parameter(app, track, fx_index, param_idx, target_slot) end
  end
  if r.ImGui_BeginMenu(ctx, "Pin parameter...") then
    local param_count = math.min(r.TrackFX_GetNumParams(track, fx_index), 200)
    for param_idx = 0, param_count - 1 do
      local _, param_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
      if param_name == "" then param_name = "Param " .. tostring(param_idx) end
      if r.ImGui_MenuItem(ctx, param_name .. "##ir_pin_param_" .. tostring(param_idx)) then
        pin_parameter(app, track, fx_index, param_idx, target_slot)
      end
    end
    r.ImGui_EndMenu(ctx)
  end
end

local function short_param_label(value)
  local label = tostring(value or "")
  if label == "" then return "Param" end
  if #label > 9 then return label:sub(1, 8) .. "." end
  return label
end

local function param_config_key(param_idx, name)
  return "param." .. tostring(param_idx) .. "." .. name
end

local function get_param_config_number(track, fx_index, param_idx, name)
  local ok, value = r.TrackFX_GetNamedConfigParm(track, fx_index, param_config_key(param_idx, name))
  if ok and value ~= nil and value ~= "" then return tonumber(value) end
  return nil
end

local function is_param_modulated(track, fx_index, param_idx)
  local keys = { "mod.active", "lfo.active", "acs.active", "plink.active" }
  for _, key in ipairs(keys) do
    local value = get_param_config_number(track, fx_index, param_idx, key)
    if value and value ~= 0 then return true end
  end
  return false
end

local function get_rack_param_value(track, fx_index, param_idx)
  if is_param_modulated(track, fx_index, param_idx) then
    local baseline = get_param_config_number(track, fx_index, param_idx, "mod.baseline")
    if baseline then return math.max(0, math.min(1, baseline)), true end
  end
  return r.TrackFX_GetParamNormalized(track, fx_index, param_idx), false
end

local function set_rack_param_value(track, fx_index, param_idx, value, uses_baseline)
  value = math.max(0, math.min(1, value or 0))
  if uses_baseline then
    r.TrackFX_SetNamedConfigParm(track, fx_index, param_config_key(param_idx, "mod.baseline"), tostring(value))
  else
    r.TrackFX_SetParamNormalized(track, fx_index, param_idx, value)
  end
end

local function apply_macro_value(track, slot, value)
  if not validate_track(track) then return end
  ensure_macros_loaded()
  local track_id = track_guid(track)
  local macro = ensure_macro_entry(track_id, slot)
  value = math.max(0, math.min(1, tonumber(value) or 0))
  macro.value = value
  state.macros_dirty = true
  local assignments = get_macro_assignments(track_id, slot)
  for _, assignment in ipairs(assignments) do
    local target_track = find_track_by_guid(assignment.track_guid)
    local fx_index = find_fx_index_by_guid(target_track, assignment.fx_guid)
    if validate_track(target_track) and fx_index then
      local param_count = r.TrackFX_GetNumParams(target_track, fx_index)
      if assignment.param_idx >= 0 and assignment.param_idx < param_count then
        local macro_value = assignment.inverted and (1 - value) or value
        local range_min = math.max(0, math.min(1, tonumber(assignment.range_min) or 0))
        local range_max = math.max(0, math.min(1, tonumber(assignment.range_max) or 1))
        local target_value = range_min + (range_max - range_min) * macro_value
        set_rack_param_value(target_track, fx_index, assignment.param_idx, target_value, is_param_modulated(target_track, fx_index, assignment.param_idx))
      end
    end
  end
end

local function process_macro_cc_event(app, visible_track, event)
  local learn = state.macro_cc_learn
  if learn then
    local learn_track = find_track_by_guid(learn.track_guid)
    local track_id = learn.track_guid
    local macro = ensure_macro_entry(track_id, learn.slot)
    macro.cc_type = event.type or "cc"
    macro.cc_channel = event.channel
    macro.cc_number = event.number
    macro.cc_device = nil
    macro.cc_mode = detect_cc_mode(event)
    macro.cc_invert = false
    macro.cc_min = event.raw_value
    macro.cc_max = event.raw_value
    macro.cc_sensitivity = 1
    save_macros()
    state.macro_cc_learn = nil
    app.status = "Assigned " .. format_macro_cc_label(macro) .. " to " .. (macro.name or default_macro_name(learn.slot))
    return
  end
  if not validate_track(visible_track) then return end
  local track_id = track_guid(visible_track)
  local macros = state.macros[track_id]
  if not macros then return end
  for slot = 1, MACRO_MAX do
    local macro = macros[slot]
    if macro_matches_midi_event(macro, event) then
      apply_macro_value(visible_track, slot, macro_value_from_cc_event(macro, event))
    end
  end
end

local function process_macro_cc_input(app, track)
  local events = read_recent_midi_ccs()
  if #events == 0 then return end
  ensure_macros_loaded()
  for index = #events, 1, -1 do
    process_macro_cc_event(app, track, events[index])
  end
end

local function flush_macro_changes(ctx)
  if not state.macros_dirty then return end
  if r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, 0) then return end
  state.macros_dirty = false
  save_macros()
end

local function macro_bar_height(ctx, settings)
  local count = (settings and settings.macro_count == 16) and 16 or 8
  if settings and settings.orientation == "horizontal" then return UIScale.round(70) end
  local columns = 4
  local rows = math.ceil(count / columns)
  return UIScale.round(18) + rows * UIScale.round(56)
end

local function remove_macro_assignment(track_id, slot, assignment_index)
  local assignments = get_macro_assignments(track_id, slot)
  if assignments[assignment_index] then table.remove(assignments, assignment_index) end
end

local function draw_macro_context_menu(app, ctx, track, slot)
  local track_id = track_guid(track)
  local macro = ensure_macro_entry(track_id, slot)
  local cc_label = format_macro_cc_label(macro)
  state.macro_name_buffers[slot] = state.macro_name_buffers[slot] or macro.name or default_macro_name(slot)
  local changed, name = r.ImGui_InputText(ctx, "Name##ir_macro_name_" .. tostring(slot), state.macro_name_buffers[slot])
  if changed then state.macro_name_buffers[slot] = name end
  if r.ImGui_Button(ctx, "Apply Name##ir_macro_apply_name_" .. tostring(slot)) then
    macro.name = state.macro_name_buffers[slot] ~= "" and state.macro_name_buffers[slot] or default_macro_name(slot)
    save_macros()
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Reset Value") then
    apply_macro_value(track, slot, 0)
    save_macros()
  end
  if r.ImGui_MenuItem(ctx, "Learn MIDI CC", nil, false, r.MIDI_GetRecentInputEvent ~= nil) then
    start_macro_cc_learn(app, track, slot)
  end
  if cc_label ~= "" then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "MIDI: " .. cc_label) end
  if macro_has_cc(macro) then
    if r.ImGui_MenuItem(ctx, "MIDI Mode: Absolute", nil, not is_macro_cc_relative(macro)) then
      macro.cc_mode = "absolute"
      macro.cc_min = nil
      macro.cc_max = nil
      save_macros()
      app.status = "Macro MIDI mode set to absolute"
    end
    if r.ImGui_MenuItem(ctx, "MIDI Mode: Relative 1/127", nil, macro.cc_mode == "relative_twos") then
      macro.cc_mode = "relative_twos"
      save_macros()
      app.status = "Macro MIDI mode set to relative 1/127"
    end
    if r.ImGui_MenuItem(ctx, "MIDI Mode: Relative 63/65", nil, macro.cc_mode == "relative_offset" or macro.cc_mode == "relative") then
      macro.cc_mode = "relative_offset"
      save_macros()
      app.status = "Macro MIDI mode set to relative 63/65"
    end
    if r.ImGui_MenuItem(ctx, "MIDI Mode: Relative 1/65", nil, macro.cc_mode == "relative_sign") then
      macro.cc_mode = "relative_sign"
      save_macros()
      app.status = "Macro MIDI mode set to relative 1/65"
    end
    if r.ImGui_MenuItem(ctx, "Invert MIDI Direction", nil, macro.cc_invert == true) then
      macro.cc_invert = not macro.cc_invert
      save_macros()
      app.status = macro.cc_invert and "Macro MIDI direction inverted" or "Macro MIDI direction normal"
    end
    if is_macro_cc_relative(macro) then
      if r.ImGui_MenuItem(ctx, "MIDI Sensitivity: 1x", nil, (tonumber(macro.cc_sensitivity) or 1) == 1) then
        macro.cc_sensitivity = 1
        save_macros()
        app.status = "Macro MIDI sensitivity set to 1x"
      end
      if r.ImGui_MenuItem(ctx, "MIDI Sensitivity: 2x", nil, tonumber(macro.cc_sensitivity) == 2) then
        macro.cc_sensitivity = 2
        save_macros()
        app.status = "Macro MIDI sensitivity set to 2x"
      end
      if r.ImGui_MenuItem(ctx, "MIDI Sensitivity: 4x", nil, tonumber(macro.cc_sensitivity) == 4) then
        macro.cc_sensitivity = 4
        save_macros()
        app.status = "Macro MIDI sensitivity set to 4x"
      end
      if r.ImGui_MenuItem(ctx, "MIDI Sensitivity: 8x", nil, tonumber(macro.cc_sensitivity) == 8) then
        macro.cc_sensitivity = 8
        save_macros()
        app.status = "Macro MIDI sensitivity set to 8x"
      end
    end
    if r.ImGui_MenuItem(ctx, "Reset MIDI Range", nil, false, not is_macro_cc_relative(macro)) then
      macro.cc_min = nil
      macro.cc_max = nil
      save_macros()
      app.status = "Macro MIDI range reset"
    end
  end
  if state.macro_cc_learn and state.macro_cc_learn.track_guid == track_id and state.macro_cc_learn.slot == slot then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Learning: move a MIDI CC")
    if r.ImGui_MenuItem(ctx, "Cancel MIDI Learn") then
      state.macro_cc_learn = nil
      app.status = "MIDI learn cancelled"
    end
  end
  if r.ImGui_MenuItem(ctx, "Clear MIDI CC", nil, false, macro_has_cc(macro)) then
    macro.cc_channel = nil
    macro.cc_number = nil
    macro.cc_device = nil
    macro.cc_mode = nil
    macro.cc_invert = nil
    macro.cc_min = nil
    macro.cc_max = nil
    macro.cc_type = nil
    macro.cc_sensitivity = nil
    save_macros()
    app.status = "Cleared MIDI CC for " .. (macro.name or default_macro_name(slot))
  end
  if r.ImGui_MenuItem(ctx, "Clear Assignments") then
    state.macro_assignments[track_id] = state.macro_assignments[track_id] or {}
    state.macro_assignments[track_id][slot] = {}
    save_macros()
    app.status = "Cleared " .. (macro.name or default_macro_name(slot))
  end
  r.ImGui_Separator(ctx)
  local assignments = get_macro_assignments(track_id, slot)
  if #assignments == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No assignments")
  else
    for assignment_index, assignment in ipairs(assignments) do
      local label = (assignment.fx_name ~= "" and assignment.fx_name or "FX") .. " / " .. (assignment.param_name ~= "" and assignment.param_name or ("Param " .. tostring(assignment.param_idx)))
      if r.ImGui_BeginMenu(ctx, label .. "##ir_macro_assignment_" .. tostring(slot) .. "_" .. tostring(assignment_index)) then
        local target_track = find_track_by_guid(assignment.track_guid)
        local fx_index = find_fx_index_by_guid(target_track, assignment.fx_guid)
        local can_read = validate_track(target_track) and fx_index ~= nil
        if r.ImGui_MenuItem(ctx, assignment.inverted and "Invert: On" or "Invert: Off") then
          assignment.inverted = not assignment.inverted
          save_macros()
        end
        if r.ImGui_MenuItem(ctx, "Set Current As Min", nil, false, can_read) then
          assignment.range_min = r.TrackFX_GetParamNormalized(target_track, fx_index, assignment.param_idx)
          save_macros()
        end
        if r.ImGui_MenuItem(ctx, "Set Current As Max", nil, false, can_read) then
          assignment.range_max = r.TrackFX_GetParamNormalized(target_track, fx_index, assignment.param_idx)
          save_macros()
        end
        if r.ImGui_MenuItem(ctx, "Remove") then
          remove_macro_assignment(track_id, slot, assignment_index)
          save_macros()
        end
        r.ImGui_EndMenu(ctx)
      end
    end
  end
end

local function draw_macro_control(app, ctx, draw_list, track, slot, x, y, width, height)
  local track_id = track_guid(track)
  local macro = ensure_macro_entry(track_id, slot)
  local value = math.max(0, math.min(1, tonumber(macro.value) or 0))
  local assignments = get_macro_assignments(track_id, slot)
  local name = macro.name and macro.name ~= "" and macro.name or default_macro_name(slot)
  local cx = x + width * 0.5
  local cy = y + UIScale.round(20)
  local radius = math.min(UIScale.round(19), math.max(UIScale.round(12), math.min(width * 0.22, UIScale.round(18))))
  local segments = 28
  local start_angle = math.pi * 0.75
  local end_angle = math.pi * 2.25
  local value_angle = start_angle + value * (end_angle - start_angle)
  local body_col = #assignments > 0 and 0x4B5668FF or 0x383F4DFF
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx + UIScale.px(1), cy + UIScale.px(1), radius, 0x00000066, segments)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, body_col, segments)
  r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius + UIScale.px(2), start_angle, end_angle, segments)
  r.ImGui_DrawList_PathStroke(draw_list, Theme.colors.border, 0, UIScale.px(1.5))
  if value > 0.001 then
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius + UIScale.px(2), start_angle, value_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, Theme.colors.accent, 0, UIScale.px(2.4))
  end
  local line_x = cx + math.cos(value_angle) * radius * 0.72
  local line_y = cy + math.sin(value_angle) * radius * 0.72
  r.ImGui_DrawList_AddLine(draw_list, cx, cy, line_x, line_y, 0xFFFFFFFF, UIScale.px(2))
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius * 0.38, Theme.colors.accent_soft, segments)
  local label = short_param_label(name)
  local label_size = UIScale.round(9)
  local label_w = r.ImGui_CalcTextSize(ctx, label) * (label_size / r.ImGui_GetFontSize(ctx))
  r.ImGui_DrawList_AddTextEx(draw_list, nil, label_size, x + math.max(UIScale.round(2), (width - label_w) * 0.5), y + height - UIScale.round(13), Theme.colors.text, label)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##ir_macro_control_" .. tostring(slot), width, height)
  if r.ImGui_IsItemActive(ctx) then
    local _, drag_y = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(drag_y) > 0 then
      apply_macro_value(track, slot, value - drag_y * 0.005)
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##ir_macro_menu_" .. tostring(slot)) end
  if r.ImGui_BeginPopup(ctx, "##ir_macro_menu_" .. tostring(slot)) then
    draw_macro_context_menu(app, ctx, track, slot)
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then
    local tooltip = name .. " | " .. tostring(#assignments) .. " assignments"
    local macro_cc = format_macro_cc_label(macro)
    if macro_cc ~= "" then tooltip = tooltip .. " | " .. macro_cc end
    r.ImGui_SetTooltip(ctx, tooltip)
  end
end

local function draw_macro_bar(app, ctx, settings, track)
  if settings.show_macros == false or not validate_track(track) then return end
  ensure_macros_loaded()
  local height = macro_bar_height(ctx, settings)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local gap = UIScale.round(6)
  r.ImGui_Dummy(ctx, width, height)
  r.ImGui_DrawList_AddLine(draw_list, x + UIScale.round(4), y + UIScale.round(1), x + width - UIScale.round(4), y + UIScale.round(1), Theme.colors.separator, UIScale.px(1))
  local count = state.macro_count
  if settings.orientation == "horizontal" then
    local control_w = UIScale.round(62)
    local control_h = UIScale.round(50)
    local top_pad = UIScale.round(9)
    local total_w = count * control_w + (count - 1) * gap
    local start_x = x + math.max(gap, (width - total_w) * 0.5)
    for slot = 1, count do
      local control_x = start_x + (slot - 1) * (control_w + gap)
      draw_macro_control(app, ctx, draw_list, track, slot, control_x, y + top_pad, control_w, control_h)
    end
  else
    local columns = 4
    local top_pad = UIScale.round(9)
    local control_h = UIScale.round(50)
    for slot = 1, count do
      local row = math.floor((slot - 1) / columns)
      local column = ((slot - 1) % columns) + 1
      local control_w = math.max(UIScale.round(24), (width - gap * (columns + 1)) / columns)
      local control_x = x + gap + (column - 1) * (control_w + gap)
      local control_y = y + top_pad + row * (control_h + gap)
      draw_macro_control(app, ctx, draw_list, track, slot, control_x, control_y, control_w, control_h)
    end
  end
  flush_macro_changes(ctx)
end

local function draw_param_knob(app, ctx, draw_list, track, fx_index, entry, cx, cy, radius)
  local value, uses_baseline = get_rack_param_value(track, fx_index, entry.param_idx)
  local start_angle = math.pi * 0.75
  local end_angle = math.pi * 2.25
  local value_angle = start_angle + value * (end_angle - start_angle)
  local segments = radius < 8 and 12 or (radius < 14 and 18 or 24)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx + UIScale.px(1), cy + UIScale.px(1), radius, 0x00000066, segments)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, 0x555555FF, segments)
  if value > 0.01 then
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius - UIScale.px(2), start_angle, value_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, 0xCCCCCCFF, 0, UIScale.px(2.5))
  end
  if value < 0.02 then
    local line_x = cx + math.cos(value_angle) * radius * 0.85
    local line_y = cy + math.sin(value_angle) * radius * 0.85
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, line_x, line_y, 0xCCCCCCFF, UIScale.px(2))
  end
  if uses_baseline then
    local mod_value = r.TrackFX_GetParamNormalized(track, fx_index, entry.param_idx)
    mod_value = math.max(0, math.min(1, mod_value or 0))
    local mod_angle = start_angle + mod_value * (end_angle - start_angle)
    local outer_r = radius + UIScale.px(2)
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, outer_r, start_angle, end_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, 0x7AA2F744, 0, UIScale.px(1.5))
    if mod_value > 0.001 then
      r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, outer_r, start_angle, mod_angle, segments)
      r.ImGui_DrawList_PathStroke(draw_list, 0x7AA2F7FF, 0, UIScale.px(1.8))
    end
  end
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius * 0.45, 0xCCCCCCFF, segments)
  local label = short_param_label(entry.param_name)
  local param_label_size = UIScale.round(8)
  local text_w = r.ImGui_CalcTextSize(ctx, label) * (param_label_size / r.ImGui_GetFontSize(ctx))
  r.ImGui_DrawList_AddTextEx(draw_list, nil, param_label_size, cx - text_w * 0.5, cy + radius + UIScale.round(1), 0xAAAAAAFF, label)
  r.ImGui_SetCursorScreenPos(ctx, cx - radius - UIScale.round(4), cy - radius - UIScale.round(4))
  r.ImGui_InvisibleButton(ctx, "##ir_param_knob_" .. tostring(entry.param_idx), (radius + UIScale.round(4)) * 2, (radius + UIScale.round(4)) * 2)
  if r.ImGui_IsItemActive(ctx) then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(dy) > 0 then
      local next_value = math.max(0, math.min(1, value - dy * 0.005))
      set_rack_param_value(track, fx_index, entry.param_idx, next_value, uses_baseline)
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    nudge_param_as_last_touched(track, fx_index, entry.param_idx)
    r.ImGui_OpenPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx))
  end
  if r.ImGui_BeginPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx)) then
    if draw_param_context_menu(app, ctx, track, fx_index, entry.param_idx) then unpin_parameter(app, track, fx_index, entry.param_idx) end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
    local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
    local prefix = uses_baseline and "Baseline: " or ""
    r.ImGui_SetTooltip(ctx, (entry.param_name or "Param") .. ": " .. prefix .. (formatted or string.format("%.0f%%", value * 100)))
  end
end

local function draw_empty_param_slot(app, ctx, draw_list, track, fx_index, cx, cy, radius, slot)
  r.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, 0x4A5360AA, 0, UIScale.px(1))
  local plus_size = UIScale.round(10)
  local plus_w = r.ImGui_CalcTextSize(ctx, "+") * (plus_size / r.ImGui_GetFontSize(ctx))
  r.ImGui_DrawList_AddTextEx(draw_list, nil, plus_size, cx - plus_w * 0.5, cy - UIScale.round(6), 0x66666688, "+")
  r.ImGui_SetCursorScreenPos(ctx, cx - radius - UIScale.round(4), cy - radius - UIScale.round(4))
  r.ImGui_InvisibleButton(ctx, "##ir_empty_param_" .. tostring(slot), (radius + UIScale.round(4)) * 2, (radius + UIScale.round(4)) * 2)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Right-click to pin a parameter") end
  if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##ir_empty_param_menu_" .. tostring(slot)) end
  if r.ImGui_BeginPopup(ctx, "##ir_empty_param_menu_" .. tostring(slot)) then
    draw_pin_menu(app, ctx, track, fx_index, slot)
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_param_slots(app, ctx, track, fx_index, item_width)
  local settings = ensure_settings(app)
  local slot_count = param_slot_count(settings)
  local row_width = math.max(1, item_width - UIScale.round(14))
  local rows = slot_count > PARAM_SLOT_COLUMNS and 2 or 1
  local row_step = UIScale.round(44)
  local row_height = rows == 2 and UIScale.round(96) or UIScale.round(54)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local pinned = get_pinned_for_fx(track, fx_index)
  local pinned_by_slot = {}
  for _, entry in ipairs(pinned) do
    local slot = tonumber(entry.slot)
    if slot and slot >= 1 and slot <= slot_count and not pinned_by_slot[slot] then
      pinned_by_slot[slot] = entry
    end
  end
  r.ImGui_Dummy(ctx, row_width, row_height)
  r.ImGui_DrawList_AddLine(draw_list, x + UIScale.round(4), y + UIScale.round(3), x + row_width - UIScale.round(4), y + UIScale.round(3), 0x3D4450AA, UIScale.px(1))
  if rows == 2 then
    r.ImGui_DrawList_AddLine(draw_list, x + UIScale.round(4), y + row_step + UIScale.round(3), x + row_width - UIScale.round(4), y + row_step + UIScale.round(3), 0x3D4450AA, UIScale.px(1))
  end
  for slot = 1, slot_count do
    local row = math.floor((slot - 1) / PARAM_SLOT_COLUMNS)
    local column = ((slot - 1) % PARAM_SLOT_COLUMNS) + 1
    local cell_width = row_width / PARAM_SLOT_COLUMNS
    local cx = x + (column - 0.5) * cell_width
    local cy = y + UIScale.round(23) + row * row_step
    local entry = pinned_by_slot[slot]
    if entry then
      draw_param_knob(app, ctx, draw_list, track, fx_index, entry, cx, cy, UIScale.round(12))
    else
      draw_empty_param_slot(app, ctx, draw_list, track, fx_index, cx, cy, UIScale.round(12), slot)
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + row_height)
end

local function chain_full_index(chain, idx)
  if chain == "input" then return REC_FX_OFFSET + idx end
  return idx
end

local function chain_count(track, take, chain)
  if chain == "input" then return r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(track) or 0 end
  if chain == "item" then return validate_take(take) and r.TakeFX_GetCount and r.TakeFX_GetCount(take) or 0 end
  return r.TrackFX_GetCount(track)
end

local function move_fx_between(app, track, take, src_chain, src_index, dest_chain, dest_index, short_name, append)
  if not validate_track(track) or not src_chain or not src_index then return end
  if not append and src_chain == dest_chain and src_index == dest_index then return end
  local src_take = src_chain == "item"
  local dest_take = dest_chain == "item"
  if (src_take or dest_take) and not validate_take(take) then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not src_take and not dest_take then
    local src_full = chain_full_index(src_chain, src_index)
    local dest_full
    if append then
      dest_full = chain_full_index(dest_chain, chain_count(track, take, dest_chain))
    else
      local d = (src_chain == dest_chain and src_index < dest_index) and dest_index + 1 or dest_index
      dest_full = chain_full_index(dest_chain, d)
    end
    r.TrackFX_CopyToTrack(track, src_full, track, dest_full, true)
  elseif not src_take and dest_take then
    local d = append and chain_count(track, take, "item") or dest_index
    if r.TrackFX_CopyToTake then r.TrackFX_CopyToTake(track, chain_full_index(src_chain, src_index), take, d, true) end
  elseif src_take and not dest_take then
    local d = append and chain_count(track, take, dest_chain) or dest_index
    if r.TakeFX_CopyToTrack then r.TakeFX_CopyToTrack(take, src_index, track, chain_full_index(dest_chain, d), true) end
  else
    local d
    if append then d = chain_count(track, take, "item")
    else d = (src_index < dest_index) and dest_index + 1 or dest_index end
    if r.TakeFX_CopyToTake then r.TakeFX_CopyToTake(take, src_index, take, d, true) end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Move rack FX", -1)
  app.status = "Moved " .. (short_name or "FX")
end

local function internal_fx_drag_active(ctx)
  if not r.ImGui_GetDragDropPayload then return false end
  local rv, ptype = r.ImGui_GetDragDropPayload(ctx)
  return rv == true and ptype == "TK_WORKBENCH_RACK_FX"
end

local function handle_fx_drag(app, ctx, draw_list, track, take, chain, local_index, short_name, x, y, width, height)
  if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
    r.ImGui_SetDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX", chain .. "|" .. tostring(local_index))
    r.ImGui_Text(ctx, "Move: " .. short_name)
    r.ImGui_EndDragDropSource(ctx)
  end
  if r.ImGui_BeginDragDropTarget(ctx) then
    local ok_payload, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
    r.ImGui_DrawList_AddRect(draw_list, x - UIScale.px(1), y - UIScale.px(1), x + width + UIScale.px(1), y + height + UIScale.px(1), 0x44CC44FF, UIScale.px(3), 0, UIScale.px(2))
    local hint = "Insert here"
    local hint_size = UIScale.round(11)
    local hint_w = r.ImGui_CalcTextSize(ctx, hint) * (hint_size / r.ImGui_GetFontSize(ctx))
    r.ImGui_DrawList_AddRectFilled(draw_list, x + (width - hint_w) * 0.5 - UIScale.round(4), y + height - UIScale.round(16), x + (width + hint_w) * 0.5 + UIScale.round(4), y + height - UIScale.round(2), 0x000000CC, UIScale.px(2))
    r.ImGui_DrawList_AddTextEx(draw_list, nil, hint_size, x + (width - hint_w) * 0.5, y + height - UIScale.round(14), 0x44CC44FF, hint)
    if ok_payload and payload and payload ~= "" then
      local src_chain, src_idx = payload:match("([^|]+)|(%d+)")
      if src_chain and src_idx then move_fx_between(app, track, take, src_chain, tonumber(src_idx), chain, local_index, short_name) end
    end
    r.ImGui_EndDragDropTarget(ctx)
  end
end

local function expanded_tile_height(settings)
  local shot_h = settings.show_screenshots and not settings.tile_compact and UIScale.round(settings.screenshot_height or 90) or 0
  local param_h = settings.show_pinned_params and (param_slot_count(settings) == 8 and UIScale.round(100) or UIScale.round(58)) or 0
  local row1_h = UIScale.round(18)
  local toolbar_h = UIScale.round(16)
  return row1_h + toolbar_h + UIScale.round(2) + shot_h + param_h + UIScale.round(4)
end

local function draw_collapsed_tile_strip(app, ctx, settings, opts)
  local strip_w = UIScale.round(26)
  local th = opts.height
  local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  local visible = r.ImGui_BeginChild(ctx, opts.id, strip_w, th, 0, flags)
  r.ImGui_PopStyleVar(ctx, 1)
  if visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + strip_w, by + th, Theme.colors.frame_bg, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + strip_w, by + th, opts.enabled and Theme.colors.border or Theme.colors.danger, UIScale.px(3), 0, UIScale.px(1))
    local chev_cx = bx + strip_w * 0.5
    local chev_cy = by + UIScale.round(8)
    r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - UIScale.round(3), chev_cy - UIScale.round(4), chev_cx + UIScale.round(4), chev_cy, chev_cx - UIScale.round(3), chev_cy + UIScale.round(4), 0xAAAAAAFF)
    local size = UIScale.round(12)
    local scale = size / r.ImGui_GetFontSize(ctx)
    local line_h = size + UIScale.round(1)
    local color = opts.enabled and Theme.colors.text or Theme.colors.text_dim
    local top = by + UIScale.round(20)
    local avail_h = th - UIScale.round(24)
    local max_chars = math.max(1, math.floor(avail_h / line_h))
    local label = opts.label or ""
    local chars = {}
    for ch in label:gmatch(".") do chars[#chars + 1] = ch; if #chars >= max_chars then break end end
    for i, ch in ipairs(chars) do
      local ch_w = r.ImGui_CalcTextSize(ctx, ch) * scale
      r.ImGui_DrawList_AddTextEx(draw_list, nil, size, bx + (strip_w - ch_w) * 0.5, top + (i - 1) * line_h, color, ch)
    end
    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_InvisibleButton(ctx, "##ir_strip_btn", strip_w, th) then state.collapsed[opts.collapse_key] = false end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, label .. " — click to expand") end
    local d = opts.drag
    handle_fx_drag(app, ctx, draw_list, d.track, d.take, d.chain, d.local_index, label, bx, by, strip_w, th)
  end
  r.ImGui_EndChild(ctx)
end

local function draw_fx_tile(app, ctx, settings, track, fx_index, item_width, chain, take)
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local enabled = r.TrackFX_GetEnabled(track, fx_index)
  local offline = r.TrackFX_GetOffline(track, fx_index)
  local short_name = get_fx_short_name(fx_name)
  chain = chain or "track"
  local local_index = chain == "input" and (fx_index - REC_FX_OFFSET) or fx_index
  r.ImGui_PushID(ctx, "ir_fx_" .. tostring(fx_index))
  local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local shot_h = settings.show_screenshots and not settings.tile_compact and UIScale.round(settings.screenshot_height or 90) or 0
  local param_h = settings.show_pinned_params and (param_slot_count(settings) == 8 and UIScale.round(100) or UIScale.round(58)) or 0
  local row1_h = UIScale.round(18)
  local toolbar_h = UIScale.round(20)
  local collapse_key = track_guid(track) .. "|" .. get_fx_guid(track, fx_index)
  if settings.auto_apply_default_pins and not state.auto_pin_checked[collapse_key] then
    state.auto_pin_checked[collapse_key] = true
    if #get_pinned_for_fx(track, fx_index) == 0 then apply_default_pins(app, track, fx_index, true) end
  end
  local is_collapsed = state.collapsed[collapse_key] == true
  if settings.orientation == "horizontal" and is_collapsed then
    draw_collapsed_tile_strip(app, ctx, settings, {
      id = "##ir_fx_tile",
      label = short_name,
      enabled = enabled,
      collapse_key = collapse_key,
      height = expanded_tile_height(settings),
      drag = { track = track, take = take, chain = chain, local_index = local_index }
    })
    r.ImGui_PopID(ctx)
    return
  end
  local title_h = is_collapsed and row1_h or (row1_h + toolbar_h + UIScale.round(2))
  local tile_h = is_collapsed and title_h or (title_h + shot_h + param_h + UIScale.round(4))
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  local tile_visible = r.ImGui_BeginChild(ctx, "##ir_fx_tile", item_width, tile_h, 0, flags)
  r.ImGui_PopStyleVar(ctx, 1)
  if tile_visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + item_width, by + tile_h, Theme.colors.frame_bg, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + item_width, by + tile_h, enabled and Theme.colors.border or Theme.colors.danger, UIScale.px(3), 0, UIScale.px(1))

    local delete_x = bx + item_width - UIScale.round(10)
    local delete_y = by + row1_h * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, delete_x, delete_y, UIScale.px(4), 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, delete_x - UIScale.round(6), delete_y - UIScale.round(6))
    r.ImGui_InvisibleButton(ctx, "##ir_fx_delete", UIScale.round(12), UIScale.round(12))
    if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "##ir_delete_pop") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete FX") end

    local led_x = delete_x - UIScale.round(14)
    r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, by + row1_h * 0.5, UIScale.px(4), enabled and 0x44CC44FF or 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, led_x - UIScale.round(6), by + UIScale.round(2))
    if r.ImGui_InvisibleButton(ctx, "##ir_fx_led", UIScale.round(12), UIScale.round(12)) then
      r.TrackFX_SetEnabled(track, fx_index, not enabled)
      app.status = (enabled and "Bypassed " or "Enabled ") .. short_name
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, enabled and "Bypass FX" or "Enable FX") end

    local chev_size = UIScale.round(12)
    local chev_x = led_x - UIScale.round(20)
    local chev_y = by + (row1_h - chev_size) * 0.5
    local chev_cx = chev_x + chev_size * 0.5
    local chev_cy = chev_y + chev_size * 0.5
    if is_collapsed then
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - UIScale.round(3), chev_cy - UIScale.round(3), chev_cx + UIScale.round(3), chev_cy, chev_cx - UIScale.round(3), chev_cy + UIScale.round(3), 0xAAAAAAFF)
    else
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - UIScale.round(3), chev_cy - UIScale.round(2), chev_cx + UIScale.round(3), chev_cy - UIScale.round(2), chev_cx, chev_cy + UIScale.round(3), 0xAAAAAAFF)
    end
    r.ImGui_SetCursorScreenPos(ctx, chev_x, chev_y)
    if r.ImGui_InvisibleButton(ctx, "##ir_fx_collapse", chev_size, chev_size) then state.collapsed[collapse_key] = not is_collapsed end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, is_collapsed and "Expand" or "Collapse") end

    local name_max_w = math.max(UIScale.round(20), chev_x - (bx + UIScale.round(6)) - UIScale.round(4))
    r.ImGui_DrawList_PushClipRect(draw_list, bx + UIScale.round(6), by, bx + UIScale.round(6) + name_max_w, by + row1_h, true)
    r.ImGui_DrawList_AddText(draw_list, bx + UIScale.round(6), by + UIScale.round(2), enabled and Theme.colors.text or Theme.colors.text_dim, short_name)
    r.ImGui_DrawList_PopClipRect(draw_list)

    if not is_collapsed then
      local tb_y = by + row1_h
      local button_y = tb_y + UIScale.round(2)
      local tx = bx + UIScale.round(6)
      local wet_value = get_fx_wet(track, fx_index)
      local wet_alpha = math.floor((1 - math.max(0, math.min(1, wet_value))) * 0xCC + 0x44)
      local wet_bg = wet_value < 0.999 and (0x4488CC00 | wet_alpha) or 0x33333388
      local clicked_wet, right_wet = draw_small_button(ctx, draw_list, "##ir_fx_wet", tx, button_y, UIScale.round(18), UIScale.round(14), "W", wet_bg, 0xFFFFFFFF, string.format("Wet: %d%%", math.floor(wet_value * 100 + 0.5)))
      if clicked_wet then r.ImGui_OpenPopup(ctx, "##ir_wet_pop") end
      if right_wet then set_fx_wet(track, fx_index, 1.0) end
      draw_wet_popup(ctx, track, fx_index, wet_value)
      tx = tx + UIScale.round(22)
      if draw_small_button(ctx, draw_list, "##ir_fx_float", tx, button_y, UIScale.round(14), UIScale.round(14), "F", 0x33333388, 0xFFFFFFFF, "Open floating") then
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
        r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
      end
      tx = tx + UIScale.round(18)
      if draw_small_button(ctx, draw_list, "##ir_fx_offline", tx, button_y, UIScale.round(14), UIScale.round(14), "O", offline and 0xAA3333FF or 0x33333388, 0xFFFFFFFF, offline and "Bring FX online" or "Set FX offline") then
        r.TrackFX_SetOffline(track, fx_index, not offline)
        app.status = (offline and "Brought online " or "Set offline ") .. short_name
      end
      tx = tx + UIScale.round(18)
      if draw_small_button(ctx, draw_list, "##ir_fx_preset", tx, button_y, UIScale.round(14), UIScale.round(14), "P", 0x33333388, 0xFFFFFFFF, "Preset") then r.ImGui_OpenPopup(ctx, "##ir_preset_pop") end
      draw_preset_popup(ctx, track, fx_index)
      tx = tx + UIScale.round(18)
      if draw_small_button(ctx, draw_list, "##ir_fx_menu", tx, button_y, UIScale.round(16), UIScale.round(14), "...", 0x33333388, 0xFFFFFFFF, "Settings") then r.ImGui_OpenPopup(ctx, "##ir_fx_menu_pop") end
      local sep_y = by + title_h - 1
      r.ImGui_DrawList_AddLine(draw_list, bx + UIScale.round(4), sep_y, bx + item_width - UIScale.round(4), sep_y, Theme.colors.separator, UIScale.px(1))

      if settings.show_screenshots and not settings.tile_compact then
        r.ImGui_SetCursorScreenPos(ctx, bx + UIScale.round(2), by + title_h)
        draw_fx_screenshot(ctx, settings, fx_name, item_width - UIScale.round(4), shot_h, enabled and not offline)
        if r.ImGui_IsItemClicked(ctx, 0) then
          local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
          r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
        end
        handle_fx_drag(app, ctx, draw_list, track, take, chain, local_index, short_name, bx, by, item_width, tile_h)
      end
      if settings.show_pinned_params then
        r.ImGui_SetCursorScreenPos(ctx, bx + UIScale.round(7), by + title_h + shot_h + UIScale.round(4))
        draw_param_slots(app, ctx, track, fx_index, item_width - UIScale.round(14))
      end
    end

    if r.ImGui_BeginPopup(ctx, "##ir_delete_pop") then
      r.ImGui_Text(ctx, "Delete this FX?")
      r.ImGui_Separator(ctx)
      if r.ImGui_Button(ctx, "Delete##ir_delete_confirm") then
        delete_fx(app, track, fx_index, fx_name)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel##ir_delete_cancel") then r.ImGui_CloseCurrentPopup(ctx) end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_InvisibleButton(ctx, "##ir_fx_title_hit", math.max(1, name_max_w + 8), row1_h) then
      local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
      r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
    end
    handle_fx_drag(app, ctx, draw_list, track, take, chain, local_index, short_name, bx, by, item_width, tile_h)
    local function fx_menu_items()
      if r.ImGui_MenuItem(ctx, enabled and "Bypass" or "Enable") then r.TrackFX_SetEnabled(track, fx_index, not enabled) end
      if r.ImGui_MenuItem(ctx, "Open floating") then
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
        r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
      end
      if r.ImGui_MenuItem(ctx, offline and "Bring online" or "Set offline") then r.TrackFX_SetOffline(track, fx_index, not offline) end
      if r.ImGui_MenuItem(ctx, is_collapsed and "Expand" or "Collapse") then state.collapsed[collapse_key] = not is_collapsed end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Save current pins as plugin default") then save_current_pins_as_default(app, track, fx_index) end
      if r.ImGui_MenuItem(ctx, "Apply plugin default pins", nil, false, has_default_pins(track, fx_index)) then apply_default_pins(app, track, fx_index) end
      if r.ImGui_MenuItem(ctx, "Clear plugin default pins", nil, false, has_default_pins(track, fx_index)) then clear_default_pins(app, track, fx_index) end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Remove") then delete_fx(app, track, fx_index, fx_name) end
    end
    if r.ImGui_BeginPopupContextItem(ctx, "##ir_fx_context") then
      fx_menu_items()
      r.ImGui_EndPopup(ctx)
    end
    if r.ImGui_BeginPopup(ctx, "##ir_fx_menu_pop") then
      fx_menu_items()
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopID(ctx)
end

local function mouse_release_state(ctx)
  local mouse_down
  if r.JS_Mouse_GetState then
    mouse_down = (r.JS_Mouse_GetState(1) & 1) == 1
  else
    mouse_down = r.ImGui_IsMouseDown(ctx, 0)
  end
  local released = state.drop_mouse_was_down and not mouse_down
  state.drop_mouse_was_down = mouse_down
  return mouse_down, released
end

local function update_external_drag(ctx)
  local external_drag = r.GetExtState("TKFXB", "drag_fx")
  local mouse_down, mouse_released = mouse_release_state(ctx)
  if external_drag ~= "" then
    state.last_external_drag = external_drag
  elseif not mouse_down and not mouse_released then
    state.last_external_drag = nil
  end
  state.mouse_released = mouse_released
  state.mouse_down = mouse_down
end

local function draw_add_zone(app, ctx, settings, track, item_width, insert_index, target_type, take, drop_only)
  target_type = target_type or "track"
  local payload = state.last_external_drag or ""
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local horizontal = settings.orientation == "horizontal"
  local picker_name = settings.add_fx_target == "native" and "native FX browser"
    or settings.add_fx_target == "plugin_browser" and "Plugin Browser"
    or settings.add_fx_target == "tk_fx_browser_mini" and "TK FX Browser Mini"
    or "TK FX Browser"
  local kind = target_type == "input" and "input FX" or target_type == "item" and "item FX" or "FX"
  local add_tip
  if drop_only then add_tip = "Drop " .. kind .. " here"
  elseif settings.add_fx_target == "native" and target_type == "input" then add_tip = "Open input FX chain"
  elseif settings.add_fx_target == "native" and target_type == "item" then add_tip = "Open item FX chain"
  else add_tip = "Add " .. kind .. " (" .. picker_name .. ")" end
  local function do_open()
    if drop_only then return end
    open_add_fx_browser(app, track, target_type, take)
  end
  local function do_drop(p)
    if target_type == "input" then add_external_input_fx(app, track, p)
    elseif target_type == "item" then add_external_take_fx(app, take, p)
    else add_external_fx(app, track, p, insert_index) end
  end
  if horizontal then
    local size = UIScale.round(40)
    local tile_h = expanded_tile_height(settings)
    x, y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_InvisibleButton(ctx, "##ir_add_zone_" .. target_type, size, tile_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local accent = payload ~= ""
    local color = accent and Theme.colors.accent or (hovered and Theme.colors.frame_hover or Theme.colors.border)
    local cx = x + size * 0.5
    local cy = y + tile_h * 0.5
    local radius = size * 0.5 - UIScale.px(2)
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, color, 0, accent and UIScale.px(2) or UIScale.px(1.5))
    local arm = radius * 0.5
    r.ImGui_DrawList_AddLine(draw_list, cx - arm, cy, cx + arm, cy, color, UIScale.px(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, cy - arm, cx, cy + arm, color, UIScale.px(2))
    if clicked then do_open() end
    if hovered then
      local guid = track_guid(track)
      if target_type == "track" and payload ~= "" and guid ~= "" then r.SetExtState("TKMIX", "rack_target", guid .. "|" .. tostring(insert_index or -1), false) end
      if payload ~= "" and state.mouse_released then do_drop(payload) end
      r.ImGui_SetTooltip(ctx, payload ~= "" and "Drop FX here" or add_tip)
    end
    if r.ImGui_BeginDragDropTarget(ctx) then
      local ok_payload, workbench_payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
      if ok_payload and workbench_payload and workbench_payload ~= "" then do_drop(workbench_payload) end
      local ok_move, move_payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
      if ok_move and move_payload and move_payload ~= "" then
        local src_chain, src_idx = move_payload:match("([^|]+)|(%d+)")
        if src_chain and src_idx then move_fx_between(app, track, take, src_chain, tonumber(src_idx), target_type, nil, nil, true) end
      end
      r.ImGui_EndDragDropTarget(ctx)
    end
    return
  end
  local label = payload ~= "" and "+ Drop to add FX" or (target_type == "input" and "+ Add input FX" or target_type == "item" and "+ Add item FX" or "+ Add FX")
  local add_h = UIScale.round(36)
  r.ImGui_InvisibleButton(ctx, "##ir_add_zone_" .. target_type, item_width, add_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local border = payload ~= "" and Theme.colors.accent or (hovered and Theme.colors.frame_hover or Theme.colors.border)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + item_width, y + add_h, border, UIScale.px(4), 0, payload ~= "" and UIScale.px(2) or UIScale.px(1))
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(draw_list, x + (item_width - text_w) * 0.5, y + UIScale.round(12), payload ~= "" and Theme.colors.accent or Theme.colors.text_dim, label)
  if clicked then do_open() end
  if hovered then
    local guid = track_guid(track)
    if target_type == "track" and payload ~= "" and guid ~= "" then r.SetExtState("TKMIX", "rack_target", guid .. "|" .. tostring(insert_index or -1), false) end
    if payload ~= "" and state.mouse_released then do_drop(payload) end
    r.ImGui_SetTooltip(ctx, payload ~= "" and "Drop FX here" or add_tip)
  end
  if r.ImGui_BeginDragDropTarget(ctx) then
    local ok_payload, workbench_payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
    if ok_payload and workbench_payload and workbench_payload ~= "" then do_drop(workbench_payload) end
    local ok_move, move_payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
    if ok_move and move_payload and move_payload ~= "" then
      local src_chain, src_idx = move_payload:match("([^|]+)|(%d+)")
      if src_chain and src_idx then move_fx_between(app, track, take, src_chain, tonumber(src_idx), target_type, nil, nil, true) end
    end
    r.ImGui_EndDragDropTarget(ctx)
  end
end

local function take_fx_enabled(take, fx_index)
  if r.TakeFX_GetEnabled then return r.TakeFX_GetEnabled(take, fx_index) end
  return true
end

local function take_fx_offline(take, fx_index)
  if r.TakeFX_GetOffline then return r.TakeFX_GetOffline(take, fx_index) end
  return false
end

local function set_take_fx_enabled(take, fx_index, enabled)
  if r.TakeFX_SetEnabled then r.TakeFX_SetEnabled(take, fx_index, enabled) end
end

local function set_take_fx_offline(take, fx_index, offline)
  if r.TakeFX_SetOffline then r.TakeFX_SetOffline(take, fx_index, offline) end
end

local function show_take_fx(take, fx_index)
  if not r.TakeFX_Show then return end
  local hwnd = r.TakeFX_GetFloatingWindow and r.TakeFX_GetFloatingWindow(take, fx_index) or nil
  r.TakeFX_Show(take, fx_index, hwnd and 2 or 3)
end

local function delete_take_fx(app, take, fx_index, fx_name)
  if not validate_take(take) or not r.TakeFX_Delete then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.TakeFX_Delete(take, fx_index)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Delete item FX", -1)
  app.status = "Deleted " .. get_fx_short_name(fx_name)
end

local function draw_take_fx_tile(app, ctx, settings, track, take, fx_index, item_width)
  local _, fx_name = r.TakeFX_GetFXName(take, fx_index, "")
  local enabled = take_fx_enabled(take, fx_index)
  local offline = take_fx_offline(take, fx_index)
  local short_name = get_fx_short_name(fx_name)
  r.ImGui_PushID(ctx, "ir_take_fx_" .. tostring(fx_index))
  local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local shot_h = settings.show_screenshots and not settings.tile_compact and UIScale.round(settings.screenshot_height or 90) or 0
  local row1_h = UIScale.round(18)
  local toolbar_h = UIScale.round(20)
  local take_guid = (r.TakeFX_GetFXGUID and r.TakeFX_GetFXGUID(take, fx_index)) or ("TAKEINDEX:" .. tostring(fx_index))
  local collapse_key = "TAKE|" .. tostring(take_guid)
  local is_collapsed = state.collapsed[collapse_key] == true
  if settings.orientation == "horizontal" and is_collapsed then
    draw_collapsed_tile_strip(app, ctx, settings, {
      id = "##ir_take_fx_tile",
      label = short_name,
      enabled = enabled,
      collapse_key = collapse_key,
      height = row1_h + toolbar_h + shot_h + UIScale.round(6),
      drag = { track = track, take = take, chain = "item", local_index = fx_index }
    })
    r.ImGui_PopID(ctx)
    return
  end
  local tile_h = is_collapsed and row1_h or (row1_h + toolbar_h + shot_h + UIScale.round(6))
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  local tile_visible = r.ImGui_BeginChild(ctx, "##ir_take_fx_tile", item_width, tile_h, 0, flags)
  r.ImGui_PopStyleVar(ctx, 1)
  if tile_visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + item_width, by + tile_h, Theme.colors.frame_bg, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + item_width, by + tile_h, enabled and Theme.colors.border or Theme.colors.danger, UIScale.px(3), 0, UIScale.px(1))

    local delete_x = bx + item_width - UIScale.round(10)
    local delete_y = by + row1_h * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, delete_x, delete_y, UIScale.px(4), 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, delete_x - UIScale.round(6), delete_y - UIScale.round(6))
    r.ImGui_InvisibleButton(ctx, "##ir_take_fx_delete", UIScale.round(12), UIScale.round(12))
    if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "##ir_take_delete_pop") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete item FX") end

    local led_x = delete_x - UIScale.round(14)
    r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, by + row1_h * 0.5, UIScale.px(4), enabled and 0x44CC44FF or 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, led_x - UIScale.round(6), by + UIScale.round(2))
    if r.ImGui_InvisibleButton(ctx, "##ir_take_fx_led", UIScale.round(12), UIScale.round(12)) then
      set_take_fx_enabled(take, fx_index, not enabled)
      app.status = (enabled and "Bypassed " or "Enabled ") .. short_name
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, enabled and "Bypass item FX" or "Enable item FX") end

    local chev_size = UIScale.round(12)
    local chev_x = led_x - UIScale.round(20)
    local chev_y = by + (row1_h - chev_size) * 0.5
    local chev_cx = chev_x + chev_size * 0.5
    local chev_cy = chev_y + chev_size * 0.5
    if is_collapsed then
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - UIScale.round(3), chev_cy - UIScale.round(3), chev_cx + UIScale.round(3), chev_cy, chev_cx - UIScale.round(3), chev_cy + UIScale.round(3), 0xAAAAAAFF)
    else
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - UIScale.round(3), chev_cy - UIScale.round(2), chev_cx + UIScale.round(3), chev_cy - UIScale.round(2), chev_cx, chev_cy + UIScale.round(3), 0xAAAAAAFF)
    end
    r.ImGui_SetCursorScreenPos(ctx, chev_x, chev_y)
    if r.ImGui_InvisibleButton(ctx, "##ir_take_fx_collapse", chev_size, chev_size) then state.collapsed[collapse_key] = not is_collapsed end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, is_collapsed and "Expand" or "Collapse") end

    local name_max_w = math.max(UIScale.round(20), chev_x - (bx + UIScale.round(6)) - UIScale.round(4))
    r.ImGui_DrawList_PushClipRect(draw_list, bx + UIScale.round(6), by, bx + UIScale.round(6) + name_max_w, by + row1_h, true)
    r.ImGui_DrawList_AddText(draw_list, bx + UIScale.round(6), by + UIScale.round(2), enabled and Theme.colors.text or Theme.colors.text_dim, short_name)
    r.ImGui_DrawList_PopClipRect(draw_list)

    if not is_collapsed then
      local button_y = by + row1_h + UIScale.round(2)
      local tx = bx + UIScale.round(6)
      if draw_small_button(ctx, draw_list, "##ir_take_fx_float", tx, button_y, UIScale.round(14), UIScale.round(14), "F", 0x33333388, 0xFFFFFFFF, "Open floating") then show_take_fx(take, fx_index) end
      tx = tx + UIScale.round(18)
      if draw_small_button(ctx, draw_list, "##ir_take_fx_offline", tx, button_y, UIScale.round(14), UIScale.round(14), "O", offline and 0xAA3333FF or 0x33333388, 0xFFFFFFFF, offline and "Bring item FX online" or "Set item FX offline") then
        set_take_fx_offline(take, fx_index, not offline)
        app.status = (offline and "Brought online " or "Set offline ") .. short_name
      end
      tx = tx + UIScale.round(18)
      if draw_small_button(ctx, draw_list, "##ir_take_fx_menu", tx, button_y, UIScale.round(16), UIScale.round(14), "...", 0x33333388, 0xFFFFFFFF, "Settings") then r.ImGui_OpenPopup(ctx, "##ir_take_fx_menu_pop") end
      if settings.show_screenshots and not settings.tile_compact then
        r.ImGui_SetCursorScreenPos(ctx, bx + UIScale.round(2), by + row1_h + toolbar_h + UIScale.round(4))
        draw_fx_screenshot(ctx, settings, fx_name, item_width - UIScale.round(4), shot_h, enabled and not offline)
        if r.ImGui_IsItemClicked(ctx, 0) then show_take_fx(take, fx_index) end
        if settings.show_item_name_overlay ~= false then
          local item_name = get_take_label(take)
          if item_name and item_name ~= "" then
            local sx = bx + UIScale.round(2)
            local sw = item_width - UIScale.round(4)
            local text_h = r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx) or UIScale.round(12)
            local overlay_h = text_h + UIScale.round(4)
            local oy = by + row1_h + toolbar_h + UIScale.round(4) + shot_h - overlay_h - UIScale.round(3)
            local item_color = get_item_color(take)
            local bg_color = item_color and ((item_color & 0xFFFFFF00) | 0xC8) or 0x000000B4
            local text_color = item_color and (luminance(item_color) > 0.55 and 0x000000FF or 0xFFFFFFFF) or 0xFFFFFFFF
            r.ImGui_DrawList_AddRectFilled(draw_list, sx, oy, sx + sw, oy + overlay_h, bg_color)
            r.ImGui_DrawList_PushClipRect(draw_list, sx + UIScale.round(3), oy, sx + sw - UIScale.round(3), oy + overlay_h, true)
            r.ImGui_DrawList_AddText(draw_list, sx + UIScale.round(4), oy + (overlay_h - text_h) * 0.5, text_color, item_name)
            r.ImGui_DrawList_PopClipRect(draw_list)
          end
        end
        handle_fx_drag(app, ctx, draw_list, track, take, "item", fx_index, short_name, bx, by, item_width, tile_h)
      end
    end

    if r.ImGui_BeginPopup(ctx, "##ir_take_delete_pop") then
      r.ImGui_Text(ctx, "Delete this item FX?")
      r.ImGui_Separator(ctx)
      if r.ImGui_Button(ctx, "Delete##ir_take_delete_confirm") then
        delete_take_fx(app, take, fx_index, fx_name)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel##ir_take_delete_cancel") then r.ImGui_CloseCurrentPopup(ctx) end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_InvisibleButton(ctx, "##ir_take_fx_title_hit", math.max(1, name_max_w + 8), row1_h) then show_take_fx(take, fx_index) end
    handle_fx_drag(app, ctx, draw_list, track, take, "item", fx_index, short_name, bx, by, item_width, tile_h)
    local function take_menu_items()
      if r.ImGui_MenuItem(ctx, enabled and "Bypass" or "Enable") then set_take_fx_enabled(take, fx_index, not enabled) end
      if r.ImGui_MenuItem(ctx, "Open floating", nil, false, r.TakeFX_Show ~= nil) then show_take_fx(take, fx_index) end
      if r.ImGui_MenuItem(ctx, offline and "Bring online" or "Set offline", nil, false, r.TakeFX_SetOffline ~= nil) then set_take_fx_offline(take, fx_index, not offline) end
      if r.ImGui_MenuItem(ctx, is_collapsed and "Expand" or "Collapse") then state.collapsed[collapse_key] = not is_collapsed end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Remove", nil, false, r.TakeFX_Delete ~= nil) then delete_take_fx(app, take, fx_index, fx_name) end
    end
    if r.ImGui_BeginPopupContextItem(ctx, "##ir_take_fx_context") then
      take_menu_items()
      r.ImGui_EndPopup(ctx)
    end
    if r.ImGui_BeginPopup(ctx, "##ir_take_fx_menu_pop") then
      take_menu_items()
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopID(ctx)
end

local function draw_section_label(ctx, label, detail, count, accent)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local width = math.max(UIScale.round(120), get_available_width(ctx))
  local height = detail and detail ~= "" and UIScale.round(32) or UIScale.round(24)
  r.ImGui_Dummy(ctx, width, height)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + UIScale.round(3), y + height, accent or Theme.colors.accent, UIScale.px(4))
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(10), y + UIScale.round(5), Theme.colors.text, label)
  if count then
    local count_text = tostring(count) .. " FX"
    local count_w = r.ImGui_CalcTextSize(ctx, count_text)
    r.ImGui_DrawList_AddText(draw_list, x + width - count_w - UIScale.round(10), y + UIScale.round(5), Theme.colors.text_dim, count_text)
  end
  if detail and detail ~= "" then r.ImGui_DrawList_AddTextEx(draw_list, nil, UIScale.round(10), x + UIScale.round(10), y + UIScale.round(20), Theme.colors.text_dim, detail) end
end

local function info_line_text(app, track, fx_count, input_fx_count, take_fx_count, item_on_track, take)
  local status = app.status and app.status ~= "" and app.status or "Ready"
  local detail
  if not validate_track(track) then
    detail = "No track selected"
  elseif item_on_track == false then
    detail = string.format("Track FX: %d  |  Input FX: %d  |  Selected item is on another track", fx_count or 0, input_fx_count or 0)
  elseif validate_take(take) then
    detail = string.format("Track FX: %d  |  Input FX: %d  |  Item FX: %d (%s)", fx_count or 0, input_fx_count or 0, take_fx_count or 0, get_take_label(take))
  else
    detail = string.format("Track FX: %d  |  Input FX: %d", fx_count or 0, input_fx_count or 0)
  end
  return detail .. " | " .. status
end

function M.init(app)
  ensure_settings(app)
  build_screenshot_index(false)
  if r.MIDI_GetRecentInputEvent then state.midi_last_retval = r.MIDI_GetRecentInputEvent(0) or 0 end
  load_macros()
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  state.macro_count = settings.macro_count == 16 and 16 or 8
  update_external_drag(ctx)
  run_pending_param_action(app)
  local track = get_target_track(settings)
  if settings.show_macros ~= false then process_macro_cc_input(app, track) end
  draw_header(app, ctx, settings, track)
  r.ImGui_Separator(ctx)
  if not validate_track(track) then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Select a track to show its FX chain.")
    if settings.show_info_bar ~= false then UI.draw_info_line(ctx, info_line_text(app, track, 0, 0, 0, nil, nil)) end
    return
  end
  if settings.body_collapsed then
    if r.ImGui_Button(ctx, "Expand rack##ir_expand") then
      settings.body_collapsed = false
      if app.save_settings then app.save_settings() end
    end
    if settings.show_info_bar ~= false then UI.draw_info_line(ctx, info_line_text(app, track, r.TrackFX_GetCount(track), 0, 0, nil, nil)) end
    return
  end
  local fx_count = r.TrackFX_GetCount(track)
  local show_track_fx = settings.show_track_fx ~= false
  local input_fx_count = settings.show_input_fx and r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(track) or 0
  local selected_item, take, item_on_track = get_selected_take(track)
  local take_fx_count = settings.show_selected_item_fx and item_on_track and validate_take(take) and r.TakeFX_GetCount and r.TakeFX_GetCount(take) or 0
  local info_h = settings.show_info_bar ~= false and UI.info_line_height(ctx) or 0
  local macros_h = settings.show_macros ~= false and macro_bar_height(ctx, settings) or 0
  local flags = 0
  local horizontal = settings.orientation == "horizontal"
  if horizontal then
    if r.ImGui_WindowFlags_NoScrollWithMouse then flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
    if settings.hide_horizontal_scrollbar then
      if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
    elseif r.ImGui_WindowFlags_HorizontalScrollbar then
      flags = flags | r.ImGui_WindowFlags_HorizontalScrollbar()
    end
  end
  if r.ImGui_BeginChild(ctx, "##instrument_rack_scroll", 0, -(info_h + macros_h), 0, flags) then
    local hover_flags = r.ImGui_HoveredFlags_ChildWindows and r.ImGui_HoveredFlags_ChildWindows() or 0
    if horizontal and r.ImGui_GetMouseWheel and r.ImGui_IsWindowHovered(ctx, hover_flags) then
      local wheel_v = r.ImGui_GetMouseWheel(ctx) or 0
      local wheel_h = r.ImGui_GetMouseWheelH and r.ImGui_GetMouseWheelH(ctx) or 0
      local wheel = math.abs(wheel_v) >= math.abs(wheel_h) and wheel_v or wheel_h
      if settings.invert_horizontal_scroll then wheel = -wheel end
      if wheel ~= 0 and r.ImGui_SetScrollX and r.ImGui_GetScrollX then
        local step = UIScale.round(settings.horizontal_tile_width or 240) * 0.5
        r.ImGui_SetScrollX(ctx, r.ImGui_GetScrollX(ctx) - wheel * step)
      end
    end
    local width = horizontal and UIScale.round(settings.horizontal_tile_width or 240) or get_centered_item_width(ctx)
    local col = 0
    local function next_tile()
      if horizontal then
        if col > 0 then r.ImGui_SameLine(ctx) end
        col = col + 1
      else
        center_next_item(ctx, width)
      end
    end
    local function new_section()
      col = 0
    end
    local function section_break(section_id, label, tooltip_extra)
      if not horizontal then return false end
      local sdl = r.ImGui_GetWindowDrawList(ctx)
      local sh = expanded_tile_height(settings)
      local size = UIScale.round(14)
      local has_line = col > 0
      if has_line then r.ImGui_SameLine(ctx) end
      local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
      local bar_w = UIScale.round(20)
      local pad = has_line and UIScale.round(6) or 0
      local bx = sx + pad
      local collapse_key = "SECTION|" .. tostring(section_id)
      local is_collapsed = state.collapsed[collapse_key] == true
      local accent = section_accent_color(settings, track)
      local text_color = luminance(accent) > 0.55 and 0x000000FF or 0xFFFFFFFF
      r.ImGui_DrawList_AddRectFilled(sdl, bx, sy, bx + bar_w, sy + sh, accent, UIScale.px(3))
      local chev_size = UIScale.round(10)
      local chev_cx = bx + bar_w * 0.5
      local chev_cy = sy + UIScale.round(8)
      if is_collapsed then
        r.ImGui_DrawList_AddTriangleFilled(sdl, chev_cx - UIScale.round(3), chev_cy - UIScale.round(4), chev_cx + UIScale.round(4), chev_cy, chev_cx - UIScale.round(3), chev_cy + UIScale.round(4), text_color)
      else
        r.ImGui_DrawList_AddTriangleFilled(sdl, chev_cx + UIScale.round(3), chev_cy - UIScale.round(4), chev_cx - UIScale.round(4), chev_cy, chev_cx + UIScale.round(3), chev_cy + UIScale.round(4), text_color)
      end
      if label and label ~= "" then
        label = label:upper()
        local font_size = r.ImGui_GetFontSize(ctx)
        local scale = size / font_size
        local line_h = size + UIScale.round(2)
        local chars = {}
        for ch in label:gmatch(".") do chars[#chars + 1] = ch end
        local total_h = #chars * line_h
        local top = sy + chev_size + UIScale.round(8)
        local avail_h = sh - (chev_size + UIScale.round(12))
        local start_y = top + math.max(0, (avail_h - total_h) * 0.5)
        for i, ch in ipairs(chars) do
          local ch_w = r.ImGui_CalcTextSize(ctx, ch) * scale
          r.ImGui_DrawList_AddTextEx(sdl, nil, size, bx + (bar_w - ch_w) * 0.5, start_y + (i - 1) * line_h, text_color, ch)
        end
      end
      r.ImGui_SetCursorScreenPos(ctx, bx, sy)
      if r.ImGui_InvisibleButton(ctx, "##ir_section_" .. tostring(section_id), bar_w, sh) then
        state.collapsed[collapse_key] = not is_collapsed
        is_collapsed = not is_collapsed
      end
      if r.ImGui_IsItemHovered(ctx) then
        local tip = is_collapsed and "Expand section" or "Collapse section"
        if tooltip_extra and tooltip_extra ~= "" then tip = tooltip_extra .. "\n" .. tip end
        r.ImGui_SetTooltip(ctx, tip)
      end
      r.ImGui_SetCursorScreenPos(ctx, sx, sy)
      r.ImGui_Dummy(ctx, pad + bar_w, sh)
      col = col + 1
      return is_collapsed
    end
    local function draw_track_section()
      if not show_track_fx then return end
      if fx_count == 0 and not horizontal then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No FX on this track.")
      end
      local collapsed = horizontal and section_break("track", "Track FX")
      if not collapsed then
        for index = 0, fx_count - 1 do
          next_tile()
          draw_fx_tile(app, ctx, settings, track, index, width, "track", take)
        end
        next_tile()
        draw_add_zone(app, ctx, settings, track, width, -1)
      end
    end
    local function draw_input_section()
      if not settings.show_input_fx then return end
      local dragging = (state.last_external_drag ~= nil and state.last_external_drag ~= "") or internal_fx_drag_active(ctx)
      local collapsed = false
      if horizontal then
        if input_fx_count > 0 or dragging then collapsed = section_break("input", "Input FX") end
      else
        new_section()
        draw_section_label(ctx, "Track Input FX", get_track_label(track), input_fx_count, section_accent_color(settings, track))
        if input_fx_count == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No input FX on this track.") end
      end
      if not collapsed then
        for index = 0, input_fx_count - 1 do
          next_tile()
          draw_fx_tile(app, ctx, settings, track, REC_FX_OFFSET + index, width, "input", take)
        end
        if dragging then
          next_tile()
          draw_add_zone(app, ctx, settings, track, width, nil, "input", nil, true)
        end
      end
    end
    local function draw_take_section()
      if not settings.show_selected_item_fx then return end
      local dragging = (state.last_external_drag ~= nil and state.last_external_drag ~= "") or internal_fx_drag_active(ctx)
      if not horizontal then
        new_section()
        draw_section_label(ctx, "Selected Track Item FX", get_track_label(track), take_fx_count, section_accent_color(settings, track))
      end
      if selected_item and item_on_track == false then
        if not horizontal then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Selected item is on another track.") end
      elseif not validate_take(take) then
        if not horizontal then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No selected item with active take on this track.") end
      else
        local collapsed = false
        if horizontal then
          if take_fx_count > 0 or dragging then collapsed = section_break("take", "Take FX", get_take_label(take)) end
        else
          if take_fx_count == 0 then
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No item FX on selected item: " .. get_take_label(take))
          else
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, get_take_label(take))
          end
        end
        if not collapsed then
          for index = 0, take_fx_count - 1 do
            next_tile()
            draw_take_fx_tile(app, ctx, settings, track, take, index, width)
          end
          if dragging then
            next_tile()
            draw_add_zone(app, ctx, settings, track, width, nil, "item", take, true)
          end
        end
      end
    end
    if settings.section_order == "signal_flow" then
      draw_input_section()
      draw_take_section()
      draw_track_section()
    else
      draw_track_section()
      draw_input_section()
      draw_take_section()
    end
    r.ImGui_EndChild(ctx)
  end
  if settings.show_macros ~= false then draw_macro_bar(app, ctx, settings, track) end
  if settings.show_info_bar ~= false then UI.draw_info_line(ctx, info_line_text(app, track, fx_count, input_fx_count, take_fx_count, item_on_track, take)) end
end

return M