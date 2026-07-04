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
local MAX_PARAM_SLOTS = 18
local PARAM_LAYOUTS = {
  vertical = {
    { count = 4, cols = 4, rows = 1 },
    { count = 8, cols = 4, rows = 2 },
    { count = 12, cols = 4, rows = 3 },
    { count = 16, cols = 4, rows = 4 },
  },
  horizontal = {
    { count = 4, cols = 4, rows = 1 },
    { count = 8, cols = 4, rows = 2 },
    { count = 12, cols = 6, rows = 2 },
    { count = 18, cols = 6, rows = 3 },
  },
}
function param_orientation(settings)
  return (settings and settings.orientation == "horizontal") and "horizontal" or "vertical"
end
function param_slots_key(settings)
  return param_orientation(settings) == "horizontal" and "param_slots_horizontal" or "param_slots_vertical"
end
function param_layout(settings)
  local list = PARAM_LAYOUTS[param_orientation(settings)]
  local count = tonumber(settings and settings[param_slots_key(settings)]) or list[1].count
  for _, e in ipairs(list) do if e.count == count then return e end end
  return list[1]
end
function param_slot_count(settings)
  return param_layout(settings).count
end
function param_slot_columns(settings)
  return param_layout(settings).cols
end
function param_slot_rows(settings)
  return param_layout(settings).rows
end
function clamp_param_slots(orient, count)
  local list = PARAM_LAYOUTS[orient] or PARAM_LAYOUTS.vertical
  count = tonumber(count)
  if count then for _, e in ipairs(list) do if e.count == count then return count end end end
  return list[1].count
end
local MACRO_COUNT = 8
local MACRO_MAX = 16
local FX_ROOT = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/"
local WORKBENCH_ROOT = r.GetResourcePath() .. "/Scripts/TK Scripts/TK Workbench/"
local PARSER_PATH = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
local QUICK_RECENT_PATH = FX_ROOT .. "recent_plugins.txt"
local QUICK_SHARED_FAVORITES_PATH = FX_ROOT .. "favorite_plugins.txt"
local QUICK_LOCAL_FAVORITES_PATH = WORKBENCH_ROOT .. "plugin_browser_favorites.txt"
local QUICK_FXCHAINS_ROOT = r.GetResourcePath() .. "/FXChains"

local state = {
  screenshot_path = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/Screenshots/",
  screenshot_index = nil,
  screenshot_cache = {},
  screenshot_missing = {},
  pinned_params = {},
  pinned_project = nil,
  fx_ab = {},
  fx_ab_current = {},
  fx_ab_project = nil,
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
  default_pins_name_index = nil,
  default_pins_loaded = false,
  auto_pin_checked = {},
  fx_value_cache = {},
  quick_add_source = "All Plugins",
  quick_add_group = "",
  quick_add_search = "",
  quick_add_popup_open = false,
  quick_add_context = nil,
  quick_add_parser_loaded = false,
  quick_add_load_error = nil,
  quick_add_plugins = {},
  quick_add_groups = { all = {}, developer = {}, category = {}, folders = {}, types = {} },
  quick_add_fxchains = {},
  quick_add_recent = {},
  quick_add_favorites = {},
  quick_add_list_hash = "",
  quick_add_fxchain_hash = "",
  quick_add_filter_cache = {}
}

local function fx_value_bucket(fx_guid)
  local bucket = state.fx_value_cache[fx_guid]
  if not bucket then
    bucket = { params = {} }
    state.fx_value_cache[fx_guid] = bucket
  end
  return bucket
end

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
  macro_count = 8,
  show_macros = true,
  orientation = "vertical",
  horizontal_tile_width = 240,
  horizontal_titlebar_left = false,
  header_center_name = false,
  header_name_badge = false,
  hide_track_number = false,
  track_name_alpha = 100,
  panel_name_alpha = 100,
  fx_name_center = false,
  hide_horizontal_scrollbar = false,
  invert_horizontal_scroll = false,
  hide_parallel_serial_badges = false,
  distinguish_instruments = true,
  show_type_badge = false,
  quick_add_enabled = true,
  add_zone_border = true,
  section_order = "default",
  section_track_color = false,
  track_color_saturation = 1.0,
  show_item_name_overlay = true,
  show_info_bar = true,
  wet_knob_scale = 1.0,
  wet_knob_alpha = 1.0,
  pinned_param_label_size = 8,
  pinned_param_scale = 1.0,
  pinned_param_alpha = 1.0,
  pinned_param_text_alpha = 1.0,
  pinned_param_display = "name",
  pinned_param_style = "knob",
  pinned_param_under_label = true,
  pinned_param_hide_value = false,
  pinned_param_tooltip_hints = true,
  auto_apply_default_pins = false,
  restore_default_pin_values = false,
  add_pins_to_tcp = false
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
  local legacy_slots = tonumber(settings.macro_param_slots)
  if settings.param_slots_vertical == nil then settings.param_slots_vertical = legacy_slots or 4; changed = true end
  if settings.param_slots_horizontal == nil then settings.param_slots_horizontal = legacy_slots or 4; changed = true end
  settings.macro_param_slots = nil
  settings.param_slots_vertical = clamp_param_slots("vertical", settings.param_slots_vertical)
  settings.param_slots_horizontal = clamp_param_slots("horizontal", settings.param_slots_horizontal)
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function param_slots_height(settings)
  if not settings or settings.show_pinned_params == false then return 0 end
  local rows = param_slot_rows(settings)
  local extra = math.max(0, UIScale.round(tonumber(settings.pinned_param_label_size) or 8) - UIScale.round(8))
  local row_step = UIScale.round(44) + extra
  return UIScale.round(54) + (rows - 1) * row_step
end

function horizontal_tile_pixels(settings)
  local base = UIScale.round(tonumber(settings and settings.horizontal_tile_width) or 240)
  if settings and settings.show_pinned_params ~= false then
    local cols = param_slot_columns(settings)
    if cols > 4 then
      local inset = UIScale.round(14)
      base = math.floor((base - inset) * cols / 4 + inset + 0.5)
    end
  end
  return base
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

local function read_lines(path)
  local result = {}
  local file = io.open(path, "r")
  if not file then return result end
  for line in file:lines() do
    if line and line ~= "" then result[#result + 1] = line end
  end
  file:close()
  return result
end

local function resolve_quick_favorites_path()
  if file_exists(QUICK_SHARED_FAVORITES_PATH) then return QUICK_SHARED_FAVORITES_PATH end
  return QUICK_LOCAL_FAVORITES_PATH
end

function quick_source_hash()
  return tostring(#state.quick_add_plugins) .. "|" .. tostring(#state.quick_add_recent) .. "|" .. tostring(#state.quick_add_favorites) .. "|" .. tostring(#state.quick_add_fxchains)
end

function quick_item_label(item)
  if type(item) == "table" then
    return item.label or item.name or item.payload or ""
  end
  return item or ""
end

function quick_item_payload(item)
  if type(item) == "table" then
    return tostring(item.payload or item.name or item.label or "")
  end
  return tostring(item or "")
end

function quick_group_kind_for_category(name)
  local upper = tostring(name or ""):upper()
  if upper == "ALL PLUGINS" then return "all" end
  if upper == "DEVELOPER" then return "developer" end
  if upper == "CATEGORY" then return "category" end
  if upper == "FOLDERS" then return "folders" end
  return nil
end

function quick_natural_less(left, right)
  local a = tostring(left or ""):lower()
  local b = tostring(right or ""):lower()
  local ai, bi = 1, 1
  while ai <= #a and bi <= #b do
    local a_num = a:match("^%d+", ai)
    local b_num = b:match("^%d+", bi)
    if a_num and b_num then
      local an, bn = tonumber(a_num), tonumber(b_num)
      if an ~= bn then return an < bn end
      if #a_num ~= #b_num then return #a_num < #b_num end
      ai = ai + #a_num
      bi = bi + #b_num
    else
      local ac, bc = a:sub(ai, ai), b:sub(bi, bi)
      if ac ~= bc then return ac < bc end
      ai = ai + 1
      bi = bi + 1
    end
  end
  return #a < #b
end

function quick_build_groups(categories)
  local groups = { all = {}, developer = {}, category = {}, folders = {} }
  if type(categories) ~= "table" then return groups end
  for _, category in ipairs(categories) do
    local kind = quick_group_kind_for_category(category and category.name)
    if kind and type(category.list) == "table" then
      for _, entry in ipairs(category.list) do
        local label = tostring(entry and entry.name or "")
        local plugins = type(entry and entry.fx) == "table" and entry.fx or {}
        if label ~= "" then
          groups[kind][#groups[kind] + 1] = { label = label, plugins = plugins }
        end
      end
      table.sort(groups[kind], function(left, right)
        return quick_natural_less(left.label, right.label)
      end)
    end
  end
  return groups
end

function quick_build_type_groups(plugin_list)
  local order = { "CLAP", "CLAPi", "VST", "VSTi", "VST3", "VST3i", "AU", "AUi", "LV2", "LV2i", "JS", "Instrument" }
  local buckets = {}
  for _, key in ipairs(order) do buckets[key] = {} end
  for _, name in ipairs(plugin_list or {}) do
    local text = quick_item_label(name)
    local prefix = text:match("^(%w+):")
    if prefix then
      if buckets[prefix] then
        buckets[prefix][#buckets[prefix] + 1] = name
      end
      if prefix:sub(-1) == "i" then
        buckets.Instrument[#buckets.Instrument + 1] = name
      end
    end
  end
  local groups = {}
  for _, key in ipairs(order) do
    if #buckets[key] > 0 then
      groups[#groups + 1] = { label = key, plugins = buckets[key] }
    end
  end
  return groups
end

function quick_load_user_lists()
  state.quick_add_recent = read_lines(QUICK_RECENT_PATH)
  state.quick_add_favorites = read_lines(resolve_quick_favorites_path())
  state.quick_add_list_hash = quick_source_hash()
  state.quick_add_filter_cache = {}
end

function quick_collect_fxchain_entries(folder_path, relative_path, result)
  result = result or {}
  local file_index = 0
  while true do
    local file_name = r.EnumerateFiles(folder_path, file_index)
    if not file_name then break end
    local lower = tostring(file_name):lower()
    if lower:sub(-9) == ".rfxchain" then
      local rel = relative_path ~= "" and (relative_path .. "/" .. file_name) or file_name
      result[#result + 1] = {
        label = rel:gsub("%.RfxChain$", ""),
        payload = rel
      }
    end
    file_index = file_index + 1
  end
  local dir_index = 0
  while true do
    local child_name = r.EnumerateSubdirectories(folder_path, dir_index)
    if not child_name then break end
    local child_folder = folder_path .. "/" .. child_name
    local child_relative = relative_path ~= "" and (relative_path .. "/" .. child_name) or child_name
    quick_collect_fxchain_entries(child_folder, child_relative, result)
    dir_index = dir_index + 1
  end
  return result
end

function quick_load_fxchains()
  local result = {}
  quick_collect_fxchain_entries(QUICK_FXCHAINS_ROOT, "", result)
  table.sort(result, function(left, right)
    return quick_item_label(left):lower() < quick_item_label(right):lower()
  end)
  state.quick_add_fxchains = result
  state.quick_add_fxchain_hash = tostring(#result)
  state.quick_add_filter_cache = {}
  return result
end

function quick_load_parser(force_scan)
  state.quick_add_load_error = nil
  if not file_exists(PARSER_PATH) then
    state.quick_add_parser_loaded = false
    state.quick_add_load_error = "Sexan parser niet gevonden"
    state.quick_add_plugins = {}
    state.quick_add_groups = { all = {}, developer = {}, category = {}, folders = {}, types = {} }
    return false
  end
  if not state.quick_add_parser_loaded then
    local ok, err = pcall(dofile, PARSER_PATH)
    if not ok then
      state.quick_add_parser_loaded = false
      state.quick_add_load_error = tostring(err)
      return false
    end
    state.quick_add_parser_loaded = true
  end
  if type(ReadFXFile) ~= "function" then
    state.quick_add_load_error = "ReadFXFile is niet beschikbaar"
    return false
  end
  local plugin_list, categories
  if force_scan and type(MakeFXFiles) == "function" then
    local ok_scan, scanned, scanned_categories = pcall(MakeFXFiles)
    if ok_scan then
      plugin_list = scanned
      categories = scanned_categories
    else
      state.quick_add_load_error = tostring(scanned)
    end
  end
  if not plugin_list then
    local ok_read, read_plugins, read_categories = pcall(ReadFXFile)
    if ok_read then
      plugin_list = read_plugins
      categories = read_categories
    else
      state.quick_add_load_error = tostring(read_plugins)
    end
  end
  if type(plugin_list) ~= "table" then plugin_list = {} end
  state.quick_add_plugins = plugin_list
  state.quick_add_groups = quick_build_groups(categories)
  state.quick_add_groups.types = quick_build_type_groups(state.quick_add_plugins)
  quick_load_user_lists()
  return #state.quick_add_plugins > 0
end

function quick_collect_source_plugins(source, group_label)
  if source == "Favorites" then return state.quick_add_favorites end
  if source == "Recent" then return state.quick_add_recent end
  if source == "All Plugins" then return state.quick_add_plugins end
  if source == "FXChains" then return state.quick_add_fxchains end
  if source == "Container" then
    local result = {}
    for _, name in ipairs(state.quick_add_plugins) do
      if tostring(name):lower():find("container", 1, true) then result[#result + 1] = name end
    end
    return result
  end
  local kind = source == "Category" and "category" or source == "Developer" and "developer" or source == "Folders" and "folders" or nil
  if not kind then return state.quick_add_plugins end
  local groups = state.quick_add_groups[kind] or {}
  local fallback = {}
  for _, group in ipairs(groups) do
    if not group_label or group_label == "" then
      fallback = group.plugins or {}
      break
    end
    if group.label == group_label then return group.plugins or {} end
  end
  return fallback
end

function quick_cached_filtered_list(cache_key, plugins, search_term)
  local cache = state.quick_add_filter_cache
  local key = tostring(cache_key or "") .. "\31" .. tostring(search_term or "")
  local cached = cache[key]
  if cached ~= nil then return cached end
  local filtered = quick_filtered_list(plugins, search_term)
  cache[key] = filtered
  return filtered
end

function quick_filter_plugins(source, group_label, search_term)
  local pool = quick_collect_source_plugins(source, group_label)
  local term = tostring(search_term or ""):lower()
  local filtered = {}
  for _, name in ipairs(pool or {}) do
    local plugin_name = quick_item_label(name)
    local payload = quick_item_payload(name)
    local haystack = (plugin_name .. " " .. payload):lower()
    if plugin_name ~= "" and (term == "" or haystack:find(term, 1, true)) then
      filtered[#filtered + 1] = name
    end
  end
  table.sort(filtered, function(left, right)
    return quick_item_label(left):lower() < quick_item_label(right):lower()
  end)
  return filtered
end

function quick_match_plugin(name, search_term)
  local plugin_name = quick_item_label(name)
  if plugin_name == "" then return false end
  local term = tostring(search_term or ""):lower()
  if term == "" then return true end
  local payload = quick_item_payload(name)
  return (plugin_name .. " " .. payload):lower():find(term, 1, true) ~= nil
end

function quick_filtered_list(plugins, search_term)
  local result = {}
  for _, name in ipairs(plugins or {}) do
    if quick_match_plugin(name, search_term) then result[#result + 1] = name end
  end
  table.sort(result, function(left, right)
    return quick_item_label(left):lower() < quick_item_label(right):lower()
  end)
  return result
end

function quick_menu_plugin_items(app, ctx, id_prefix, plugins, search_term, max_items)
  local list = quick_cached_filtered_list(id_prefix, plugins, search_term)
  local shown = 0
  local cap = tonumber(max_items) or 280
  for index, plugin_name in ipairs(list) do
    if shown >= cap then break end
    local label = quick_item_label(plugin_name) .. "##" .. tostring(id_prefix) .. "_" .. tostring(index)
    if r.ImGui_MenuItem(ctx, label) then
      quick_apply_plugin(app, quick_item_payload(plugin_name))
      r.ImGui_CloseCurrentPopup(ctx)
      return true
    end
    shown = shown + 1
  end
  if #list == 0 then
    r.ImGui_MenuItem(ctx, "Geen resultaten", nil, false, false)
  elseif #list > cap then
    r.ImGui_Separator(ctx)
    r.ImGui_MenuItem(ctx, "Toon verfijn zoekterm...", nil, false, false)
  end
  return false
end

function quick_menu_group_source(app, ctx, source_label, group_kind, search_term)
  local groups = state.quick_add_groups[group_kind] or {}
  if not r.ImGui_BeginMenu(ctx, source_label .. "##ir_quick_src_" .. tostring(group_kind)) then return false end
  local searching = search_term ~= nil and search_term ~= ""
  local any = false
  for group_index, group in ipairs(groups) do
    local plugins = group.plugins or {}
    local count = #plugins
    local group_prefix = group_kind .. "_" .. tostring(group_index)
    if searching then
      plugins = quick_cached_filtered_list(group_prefix, group.plugins or {}, search_term)
      count = #plugins
    end
    if count > 0 then
      any = true
      local item_search = searching and search_term or ""
      local sub_label = tostring(group.label or "Group") .. " (" .. tostring(count) .. ")##ir_quick_group_" .. tostring(group_kind) .. "_" .. tostring(group_index)
      if r.ImGui_BeginMenu(ctx, sub_label) then
        if quick_menu_plugin_items(app, ctx, group_prefix, group.plugins or {}, item_search, 220) then
          r.ImGui_EndMenu(ctx)
          r.ImGui_EndMenu(ctx)
          return true
        end
        r.ImGui_EndMenu(ctx)
      end
    end
  end
  if not any then r.ImGui_MenuItem(ctx, "Geen resultaten", nil, false, false) end
  r.ImGui_EndMenu(ctx)
  return false
end

function quick_open_popup(track, target_type, take, insert_index, chain, container_api)
  state.quick_add_context = {
    track = track,
    target_type = target_type or "track",
    take = take,
    insert_index = insert_index,
    chain = chain,
    container_api = container_api
  }
  state.quick_add_popup_open = true
end

function quick_add_recent_plugin(name)
  if not name or name == "" then return end
  for index = #state.quick_add_recent, 1, -1 do
    if state.quick_add_recent[index] == name then table.remove(state.quick_add_recent, index) end
  end
  table.insert(state.quick_add_recent, 1, name)
  while #state.quick_add_recent > 40 do table.remove(state.quick_add_recent) end
  local file = io.open(QUICK_RECENT_PATH, "w")
  if file then
    for _, line in ipairs(state.quick_add_recent) do file:write(line .. "\n") end
    file:close()
  end
end

function quick_apply_plugin(app, plugin_name)
  local context = state.quick_add_context
  if not context or not plugin_name or plugin_name == "" then return end
  if context.container_api ~= nil and context.chain then
    add_external_fx_into_container(app, context.chain, context.container_api, plugin_name)
    quick_add_recent_plugin(plugin_name)
    app.status = "Toegevoegd via Quick Add"
    return
  end
  if context.target_type == "input" then
    add_external_input_fx(app, context.track, plugin_name)
  elseif context.target_type == "item" then
    add_external_take_fx(app, context.take, plugin_name)
  else
    add_external_fx(app, context.track, plugin_name, context.insert_index)
  end
  quick_add_recent_plugin(plugin_name)
  app.status = "Toegevoegd via Quick Add"
end

function draw_quick_add_popup(app, ctx)
  local popup_id = "##ir_quick_add_popup"
  if state.quick_add_popup_open then
    state.quick_add_popup_open = false
    if state.quick_add_list_hash ~= quick_source_hash() then quick_load_user_lists() end
    r.ImGui_OpenPopup(ctx, popup_id)
  end
  if not r.ImGui_BeginPopup(ctx, popup_id) then return end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(110))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##ir_quick_add_search", "Zoek plugin...", state.quick_add_search or "")
  if changed then state.quick_add_search = value or "" end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "X##ir_quick_add_clear") then state.quick_add_search = "" end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Rescan##ir_quick_add_rescan") then quick_load_parser(true) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "FXChains##ir_quick_add_fxchains_refresh") then quick_load_fxchains() end
  if state.quick_add_load_error and state.quick_add_load_error ~= "" then
    r.ImGui_TextColored(ctx, Theme.colors.warning, state.quick_add_load_error)
  end
  r.ImGui_Separator(ctx)
  local search_term = state.quick_add_search or ""
  if search_term ~= "" then
    local search_list = quick_cached_filtered_list("search", state.quick_add_plugins, search_term)
    local search_label = "Search (" .. tostring(#search_list) .. ")##ir_quick_search"
    if r.ImGui_BeginMenu(ctx, search_label) then
      if quick_menu_plugin_items(app, ctx, "search", state.quick_add_plugins, search_term, 320) then
        r.ImGui_EndMenu(ctx)
        r.ImGui_EndPopup(ctx)
        return
      end
      r.ImGui_EndMenu(ctx)
    end
    r.ImGui_Separator(ctx)
  end
  if r.ImGui_BeginMenu(ctx, "Favorites##ir_quick_favorites") then
    if quick_menu_plugin_items(app, ctx, "favorites", state.quick_add_favorites, search_term, 220) then
      r.ImGui_EndMenu(ctx)
      r.ImGui_EndPopup(ctx)
      return
    end
    r.ImGui_EndMenu(ctx)
  end
  if r.ImGui_BeginMenu(ctx, "Recent##ir_quick_recent") then
    if quick_menu_plugin_items(app, ctx, "recent", state.quick_add_recent, search_term, 220) then
      r.ImGui_EndMenu(ctx)
      r.ImGui_EndPopup(ctx)
      return
    end
    r.ImGui_EndMenu(ctx)
  end
  if quick_menu_group_source(app, ctx, "All Plugins", "types", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if quick_menu_group_source(app, ctx, "Category", "category", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if quick_menu_group_source(app, ctx, "Developer", "developer", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if quick_menu_group_source(app, ctx, "Folders", "folders", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if r.ImGui_BeginMenu(ctx, "FXChains##ir_quick_fxchains") then
    if quick_menu_plugin_items(app, ctx, "fxchains", state.quick_add_fxchains, search_term, 180) then
      r.ImGui_EndMenu(ctx)
      r.ImGui_EndPopup(ctx)
      return
    end
    r.ImGui_EndMenu(ctx)
  end
  if r.ImGui_BeginMenu(ctx, "Container##ir_quick_container") then
    if quick_menu_plugin_items(app, ctx, "container", quick_collect_source_plugins("Container"), search_term, 220) then
      r.ImGui_EndMenu(ctx)
      r.ImGui_EndPopup(ctx)
      return
    end
    r.ImGui_EndMenu(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

local function current_project()
  local project = r.EnumProjects(-1, "")
  return project or 0
end

local function clean_storage_field(value)
  return tostring(value or ""):gsub("[\t\r\n\30]", " ")
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

local CONTAINER_BASE = 0x2000000

local function fx_config_value(track, fx, key)
  if not r.TrackFX_GetNamedConfigParm then return nil end
  local ok, value = r.TrackFX_GetNamedConfigParm(track, fx, key)
  if not ok then return nil end
  return tostring(value or "")
end

local function fx_is_container(track, fx)
  return fx_config_value(track, fx, "fx_type") == "Container"
end

local function fx_is_parallel(track, fx)
  local v = fx_config_value(track, fx, "parallel")
  return v ~= nil and v ~= "0"
end

local function make_fx_chain(track, take, kind)
  return { kind = kind or "track", track = track, take = take }
end

local function as_chain(chain)
  if type(chain) == "table" and chain.kind then return chain end
  return make_fx_chain(chain, nil, "track")
end

local function chain_valid(chain)
  if chain.kind == "item" then return validate_take(chain.take) end
  return validate_track(chain.track)
end

local function cfg(chain, fx, key)
  if chain.kind == "item" then
    if not r.TakeFX_GetNamedConfigParm then return nil end
    local ok, value = r.TakeFX_GetNamedConfigParm(chain.take, fx, key)
    if not ok then return nil end
    return tostring(value or "")
  end
  return fx_config_value(chain.track, fx, key)
end

local function cfg_set(chain, fx, key, value)
  if chain.kind == "item" then
    if r.TakeFX_SetNamedConfigParm then r.TakeFX_SetNamedConfigParm(chain.take, fx, key, value) end
    return
  end
  if r.TrackFX_SetNamedConfigParm then r.TrackFX_SetNamedConfigParm(chain.track, fx, key, value) end
end

local function c_count(chain)
  if chain.kind == "item" then return (validate_take(chain.take) and r.TakeFX_GetCount and r.TakeFX_GetCount(chain.take)) or 0 end
  return r.TrackFX_GetCount(chain.track) or 0
end

local function c_guid(chain, fx)
  if chain.kind == "item" then
    local g = r.TakeFX_GetFXGUID and r.TakeFX_GetFXGUID(chain.take, fx)
    if g and g ~= "" then return g end
    return "INDEX:" .. tostring(fx)
  end
  return get_fx_guid(chain.track, fx)
end

local function c_is_container(chain, fx)
  return cfg(chain, fx, "fx_type") == "Container"
end

local function c_is_parallel(chain, fx)
  local v = cfg(chain, fx, "parallel")
  return v ~= nil and v ~= "0"
end

local function c_add_capable(chain)
  if chain.kind == "item" then return r.TakeFX_AddByName ~= nil end
  return r.TrackFX_AddByName ~= nil
end

local function c_add(chain, name, pos)
  if chain.kind == "item" then return r.TakeFX_AddByName and r.TakeFX_AddByName(chain.take, name, pos) end
  return r.TrackFX_AddByName and r.TrackFX_AddByName(chain.track, name, false, pos)
end

local function c_move_capable(chain)
  if chain.kind == "item" then return r.TakeFX_CopyToTake ~= nil end
  return r.TrackFX_CopyToTrack ~= nil
end

local function c_move(chain, src, dest)
  if chain.kind == "item" then return r.TakeFX_CopyToTake and r.TakeFX_CopyToTake(chain.take, src, chain.take, dest, true) end
  return r.TrackFX_CopyToTrack and r.TrackFX_CopyToTrack(chain.track, src, chain.track, dest, true)
end

local function c_delete(chain, idx)
  if chain.kind == "item" then return r.TakeFX_Delete and r.TakeFX_Delete(chain.take, idx) end
  return r.TrackFX_Delete and r.TrackFX_Delete(chain.track, idx)
end

local function collect_container_nodes(chain, container_rel, parent_count, parent_diff, depth, max_depth)
  chain = as_chain(chain)
  local nodes = {}
  local raw = cfg(chain, CONTAINER_BASE + container_rel, "container_count")
  local count = math.floor(tonumber(raw) or 0)
  if count <= 0 then return nodes, 0 end
  local diff = (parent_count + 1) * parent_diff
  for j = 1, count do
    local child_rel = container_rel + diff * j
    local api = CONTAINER_BASE + child_rel
    local is_container = c_is_container(chain, api)
    local node = { api = api, depth = depth, is_container = is_container, parallel = c_is_parallel(chain, api) }
    if is_container and depth < max_depth then
      node.children, node.child_count = collect_container_nodes(chain, child_rel, count, diff, depth + 1, max_depth)
    elseif is_container then
      node.children = {}
      node.child_count = math.floor(tonumber(cfg(chain, api, "container_count")) or 0)
    end
    nodes[#nodes + 1] = node
  end
  return nodes, count
end

local function build_track_fx_tree(chain, top_count, max_depth)
  chain = as_chain(chain)
  local nodes = {}
  for i = 0, top_count - 1 do
    local is_container = c_is_container(chain, i)
    local node = { api = i, depth = 0, is_container = is_container, parallel = c_is_parallel(chain, i) }
    if is_container then
      node.children, node.child_count = collect_container_nodes(chain, i + 1, top_count, 1, 1, max_depth)
    end
    nodes[#nodes + 1] = node
  end
  return nodes
end

local function build_input_fx_tree(chain, top_count)
  chain = as_chain(chain)
  local nodes = {}
  for i = 0, top_count - 1 do
    local api = REC_FX_OFFSET + i
    local node = { api = api, depth = 0, is_container = false, parallel = c_is_parallel(chain, api) }
    nodes[#nodes + 1] = node
  end
  return nodes
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
    local fields = split_storage_fields(line)
    local track_id = fields[1]
    local fx_guid = fields[2]
    local param_idx = tonumber(fields[3])
    local param_name = fields[4] or ""
    local fx_name = fields[5] or ""
    local slot = tonumber(fields[6])
    local custom_name = fields[7] or ""
    local style = fields[8] or ""
    local display = fields[9] or ""
    local under_label_raw = fields[10] or ""
    local under_label = nil
    if under_label_raw == "1" then under_label = true elseif under_label_raw == "0" then under_label = false end
    if track_id and track_id ~= "" and fx_guid and fx_guid ~= "" and param_idx then
      state.pinned_params[track_id] = state.pinned_params[track_id] or {}
      state.pinned_params[track_id][param_key(fx_guid, param_idx)] = {
        track_guid = track_id,
        fx_guid = fx_guid,
        param_idx = param_idx,
        param_name = param_name,
        fx_name = fx_name,
        slot = slot,
        custom_name = custom_name,
        style = style,
        display = (display == "name" or display == "value") and display or nil,
        under_label = under_label,
        reset_value = tonumber(fields[11])
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
        tostring(tonumber(entry.slot) or ""),
        clean_storage_field(entry.custom_name),
        clean_storage_field(entry.style),
        clean_storage_field((entry.display == "name" or entry.display == "value") and entry.display or ""),
        (entry.under_label == true and "1") or (entry.under_label == false and "0") or "",
        (type(entry.reset_value) == "number" and tostring(entry.reset_value)) or ""
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
      local fields = split_storage_fields(line)
      local track_id, fx_guid = fields[1], fields[3]
      local slot = tonumber(fields[2])
      local param_idx = tonumber(fields[4])
      if track_id and track_id ~= "" and slot and slot >= 1 and slot <= MACRO_MAX and fx_guid and fx_guid ~= "" and param_idx then
        state.macro_assignments[track_id] = state.macro_assignments[track_id] or {}
        state.macro_assignments[track_id][slot] = state.macro_assignments[track_id][slot] or {}
        state.macro_assignments[track_id][slot][#state.macro_assignments[track_id][slot] + 1] = {
          track_guid = track_id,
          fx_guid = fx_guid,
          param_idx = param_idx,
          param_name = fields[5] or "",
          fx_name = fields[6] or "",
          range_min = math.max(0, math.min(1, tonumber(fields[7]) or 0)),
          range_max = math.max(0, math.min(1, tonumber(fields[8]) or 1)),
          inverted = fields[9] == "1",
          curve = math.max(0.1, math.min(10, tonumber(fields[10]) or 1)),
          curve_type = (fields[11] == "scurve" or fields[11] == "quant" or fields[11] == "bipolar") and fields[11] or "power"
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
          assignment.inverted and "1" or "0",
          tostring(tonumber(assignment.curve) or 1),
          clean_storage_field(assignment.curve_type or "power")
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
    inverted = false,
    curve = 1,
    curve_type = "power"
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
  local param_count = r.TrackFX_GetOffline(track, fx_index) and 0 or (r.TrackFX_GetNumParams(track, fx_index) or 0)
  for _, entry in pairs(entries) do
    if entry.fx_guid == fx_guid and entry.param_idx >= 0 and (param_count <= 0 or entry.param_idx < param_count) then
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

function tcp_add_fx_parm(track, fx_index, param_idx)
  if not r.SNM_AddTCPFXParm then return false end
  if fx_index >= CONTAINER_BASE then return false end
  r.SNM_AddTCPFXParm(track, fx_index, param_idx)
  r.TrackList_AdjustWindows(false)
  return true
end

function tcp_remove_fx_parm(track, fx_index, param_idx)
  local _, _, minv, maxv = r.TrackFX_GetParamEx(track, fx_index, param_idx)
  local cur = r.TrackFX_GetParam(track, fx_index, param_idx)
  local range = (maxv or 1) - (minv or 0)
  if range == 0 then range = 1 end
  local eps = range * 1e-6
  local nudged = cur + eps
  if maxv and nudged > maxv then nudged = cur - eps end
  r.TrackFX_SetParam(track, fx_index, param_idx, nudged)
  r.TrackFX_SetParam(track, fx_index, param_idx, cur)
  r.Main_OnCommand(41141, 0)
  r.TrackList_AdjustWindows(false)
  return true
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
  if settings.add_pins_to_tcp then tcp_add_fx_parm(track, fx_index, param_idx) end
  app.status = "Pinned " .. (param_name ~= "" and param_name or ("Param " .. tostring(param_idx)))
end

local function unpin_parameter(app, track, fx_index, param_idx)
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local entries = state.pinned_params[track_id]
  if not entries then return end
  entries[param_key(get_fx_guid(track, fx_index), param_idx)] = nil
  save_pinned_params()
  local settings = ensure_settings(app)
  if settings.add_pins_to_tcp then tcp_remove_fx_parm(track, fx_index, param_idx) end
  app.status = "Parameter unpinned"
end

function sync_tcp_params(app, track, fx_filter)
  if not validate_track(track) or not r.CountTCPFXParms then return 0 end
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local added = 0
  local count = r.CountTCPFXParms(0, track)
  for i = 0, count - 1 do
    local ok, fx_idx, param_idx = r.GetTCPFXParm(0, track, i)
    if ok and (fx_filter == nil or fx_idx == fx_filter) then
      local key = param_key(get_fx_guid(track, fx_idx), param_idx)
      if not (state.pinned_params[track_id] and state.pinned_params[track_id][key]) then
        pin_parameter(app, track, fx_idx, param_idx)
        added = added + 1
      end
    end
  end
  app.status = "Synced " .. tostring(added) .. " TCP params"
  return added
end

function fx_ab_key(track, fx_index)
  return track_guid(track) .. "|" .. tostring(get_fx_guid(track, fx_index) or "")
end

function load_fx_ab()
  local project = current_project()
  state.fx_ab_project = project
  state.fx_ab = {}
  state.fx_ab_current = {}
  if not r.GetProjExtState then return end
  local _, content = r.GetProjExtState(project, EXT_SECTION, "fx_ab")
  if content and content ~= "" then
    for line in content:gmatch("[^\r\n]+") do
      local f = split_storage_fields(line)
      local track_id, fx_guid, side = f[1], f[2], f[3]
      local param_idx = tonumber(f[4])
      local value = tonumber(f[5])
      if track_id and track_id ~= "" and (side == "a" or side == "b") and param_idx and value then
        local key = track_id .. "|" .. (fx_guid or "")
        state.fx_ab[key] = state.fx_ab[key] or { a = {}, b = {} }
        state.fx_ab[key][side][param_idx] = value
      end
    end
  end
  local _, cur = r.GetProjExtState(project, EXT_SECTION, "fx_ab_current")
  if cur and cur ~= "" then
    for line in cur:gmatch("[^\r\n]+") do
      local f = split_storage_fields(line)
      if f[1] and f[1] ~= "" and (f[3] == "a" or f[3] == "b") then
        state.fx_ab_current[f[1] .. "|" .. (f[2] or "")] = f[3]
      end
    end
  end
end

function ensure_fx_ab_loaded()
  local project = current_project()
  if state.fx_ab_project ~= project then load_fx_ab() end
end

function save_fx_ab()
  if not r.SetProjExtState then return end
  ensure_fx_ab_loaded()
  local lines = {}
  for key, sides in pairs(state.fx_ab) do
    local track_id, fx_guid = key:match("^(.-)|(.*)$")
    for _, side in ipairs({ "a", "b" }) do
      local snap = sides[side]
      if snap then
        for param_idx, value in pairs(snap) do
          lines[#lines + 1] = table.concat({
            clean_storage_field(track_id),
            clean_storage_field(fx_guid),
            side,
            tostring(param_idx),
            tostring(value)
          }, "\t")
        end
      end
    end
  end
  table.sort(lines)
  r.SetProjExtState(current_project(), EXT_SECTION, "fx_ab", table.concat(lines, "\n"))
  local cur_lines = {}
  for key, side in pairs(state.fx_ab_current) do
    local track_id, fx_guid = key:match("^(.-)|(.*)$")
    cur_lines[#cur_lines + 1] = table.concat({
      clean_storage_field(track_id),
      clean_storage_field(fx_guid),
      side
    }, "\t")
  end
  table.sort(cur_lines)
  r.SetProjExtState(current_project(), EXT_SECTION, "fx_ab_current", table.concat(cur_lines, "\n"))
end

function fx_ab_capture(track, fx_index)
  local snap = {}
  local n = r.TrackFX_GetNumParams(track, fx_index) or 0
  for p = 0, n - 1 do
    snap[p] = r.TrackFX_GetParamNormalized(track, fx_index, p)
  end
  return snap
end

function fx_ab_apply(track, fx_index, snap)
  if not snap then return end
  local n = r.TrackFX_GetNumParams(track, fx_index) or 0
  for p = 0, n - 1 do
    local v = snap[p]
    if v then r.TrackFX_SetParamNormalized(track, fx_index, p, v) end
  end
end

function fx_ab_has_side(sides, side)
  return sides and sides[side] and next(sides[side]) ~= nil
end

function fx_ab_has_data(track, fx_index)
  ensure_fx_ab_loaded()
  local sides = state.fx_ab[fx_ab_key(track, fx_index)]
  return sides ~= nil and (fx_ab_has_side(sides, "a") or fx_ab_has_side(sides, "b"))
end

function fx_ab_toggle(app, track, fx_index)
  if not validate_track(track) then return end
  ensure_fx_ab_loaded()
  local key = fx_ab_key(track, fx_index)
  local sides = state.fx_ab[key]
  if not sides or (not fx_ab_has_side(sides, "a") and not fx_ab_has_side(sides, "b")) then
    local snap = fx_ab_capture(track, fx_index)
    state.fx_ab[key] = { a = snap, b = {} }
    for p, v in pairs(snap) do state.fx_ab[key].b[p] = v end
    state.fx_ab_current[key] = "a"
    save_fx_ab()
    app.status = "Captured A/B"
    return
  end
  local cur = state.fx_ab_current[key] or "a"
  local other = (cur == "a") and "b" or "a"
  if fx_ab_has_side(sides, other) then
    r.Undo_BeginBlock()
    fx_ab_apply(track, fx_index, sides[other])
    r.Undo_EndBlock("Toggle FX A/B", -1)
    state.fx_ab_current[key] = other
    save_fx_ab()
    app.status = "A/B: " .. string.upper(other)
  end
end

function fx_ab_copy_to(app, track, fx_index, side)
  if not validate_track(track) then return end
  ensure_fx_ab_loaded()
  local key = fx_ab_key(track, fx_index)
  state.fx_ab[key] = state.fx_ab[key] or { a = {}, b = {} }
  state.fx_ab[key][side] = fx_ab_capture(track, fx_index)
  state.fx_ab_current[key] = side
  save_fx_ab()
  app.status = "Copied current to " .. string.upper(side)
end

function fx_ab_reset(app, track, fx_index)
  ensure_fx_ab_loaded()
  local key = fx_ab_key(track, fx_index)
  state.fx_ab[key] = nil
  state.fx_ab_current[key] = nil
  save_fx_ab()
  app.status = "Reset A/B"
end

local function fx_plugin_key(track, fx_index)
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local name_key = normalize_plugin_name(fx_name or "")
  local ident_key = ""
  if r.TrackFX_GetNamedConfigParm then
    local ok, ident = r.TrackFX_GetNamedConfigParm(track, fx_index, "fx_ident")
    if ok and ident and ident ~= "" then ident_key = ident end
  end
  if ident_key == "" then ident_key = clean_fx_name(fx_name or "") end
  return ident_key, name_key
end

local function load_default_pins()
  state.default_pins = {}
  state.default_pins_name_index = {}
  state.default_pins_loaded = true
  if not r.GetExtState then return end
  local content = r.GetExtState(EXT_SECTION, "default_pins")
  if not content or content == "" then return end
  for line in content:gmatch("[^\30\r\n]+") do
    local fields = split_storage_fields(line)
    local key, slot, param_idx, param_name, value = fields[1], tonumber(fields[2]), tonumber(fields[3]), fields[4], tonumber(fields[5])
    local name_key = fields[6] or ""
    local custom_name = fields[7] or ""
    local style = fields[8] or ""
    local display = fields[9] or ""
    local under_label_raw = fields[10] or ""
    local under_label = nil
    if under_label_raw == "1" then under_label = true elseif under_label_raw == "0" then under_label = false end
    if key and key ~= "" and param_idx then
      state.default_pins[key] = state.default_pins[key] or {}
      state.default_pins[key][#state.default_pins[key] + 1] = {
        slot = slot,
        param_idx = param_idx,
        param_name = param_name or "",
        value = value,
        name_key = name_key,
        custom_name = custom_name,
        style = style,
        display = (display == "name" or display == "value") and display or nil,
        under_label = under_label,
        reset_value = tonumber(fields[11])
      }
      if name_key ~= "" then state.default_pins_name_index[name_key] = key end
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
        clean_storage_field(entry.param_name or ""),
        tostring(tonumber(entry.value) or ""),
        clean_storage_field(entry.name_key or ""),
        clean_storage_field(entry.custom_name or ""),
        clean_storage_field(entry.style or ""),
        clean_storage_field((entry.display == "name" or entry.display == "value") and entry.display or ""),
        (entry.under_label == true and "1") or (entry.under_label == false and "0") or "",
        (type(entry.reset_value) == "number" and tostring(entry.reset_value)) or ""
      }, "\t")
    end
  end
  table.sort(lines)
  r.SetExtState(EXT_SECTION, "default_pins", table.concat(lines, "\30"), true)
end

function resolve_default_pins_list(track, fx_index)
  local ident_key, name_key = fx_plugin_key(track, fx_index)
  local primary
  if ident_key ~= "" and state.default_pins[ident_key] then
    primary = ident_key
  elseif name_key ~= "" and state.default_pins_name_index[name_key] and state.default_pins[state.default_pins_name_index[name_key]] then
    primary = state.default_pins_name_index[name_key]
  elseif name_key ~= "" and state.default_pins[name_key] then
    primary = name_key
  end
  local list = primary and state.default_pins[primary] or nil
  return list, ident_key, name_key, primary
end

local function has_default_pins(track, fx_index)
  ensure_default_pins_loaded()
  local list = resolve_default_pins_list(track, fx_index)
  return list and #list > 0
end

local function save_current_pins_as_default(app, track, fx_index)
  ensure_default_pins_loaded()
  local ident_key, name_key = fx_plugin_key(track, fx_index)
  local primary = ident_key ~= "" and ident_key or name_key
  if primary == "" then app.status = "Could not identify plugin" return end
  local pinned = get_pinned_for_fx(track, fx_index)
  if #pinned == 0 then app.status = "No pinned parameters to save" return end
  local list = {}
  for _, entry in ipairs(pinned) do
    list[#list + 1] = {
      slot = tonumber(entry.slot),
      param_idx = entry.param_idx,
      param_name = entry.param_name or "",
      value = r.TrackFX_GetParamNormalized(track, fx_index, entry.param_idx),
      name_key = name_key,
      custom_name = entry.custom_name or "",
      style = entry.style or "",
      display = (entry.display == "name" or entry.display == "value") and entry.display or nil,
      under_label = entry.under_label,
      reset_value = entry.reset_value
    }
  end
  state.default_pins[primary] = list
  if name_key ~= "" then state.default_pins_name_index[name_key] = primary end
  save_default_pins()
  app.status = "Saved " .. tostring(#list) .. " default pins for this plugin"
end

local function clear_default_pins(app, track, fx_index)
  ensure_default_pins_loaded()
  local list, ident_key, name_key, primary = resolve_default_pins_list(track, fx_index)
  if not primary or not list then
    app.status = "No default pins for this plugin"
    return
  end
  state.default_pins[primary] = nil
  if name_key ~= "" and state.default_pins_name_index[name_key] == primary then
    state.default_pins_name_index[name_key] = nil
  end
  save_default_pins()
  app.status = "Cleared default pins for this plugin"
end

local function apply_default_pins(app, track, fx_index, silent)
  ensure_default_pins_loaded()
  local defaults_list = resolve_default_pins_list(track, fx_index)
  if not defaults_list or #defaults_list == 0 then
    if not silent then app.status = "No default pins for this plugin" end
    return false
  end
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local fx_guid = get_fx_guid(track, fx_index)
  state.pinned_params[track_id] = state.pinned_params[track_id] or {}
  local is_offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, fx_index)
  local param_count = is_offline and 0 or (r.TrackFX_GetNumParams(track, fx_index) or 0)
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local ir_settings = ensure_settings(app)
  local restore_values = ir_settings.restore_default_pin_values == true
  local applied = 0
  local restored = 0
  for _, def in ipairs(defaults_list) do
    local param_idx = def.param_idx
    if param_idx and param_idx >= 0 and (param_count <= 0 or param_idx < param_count) then
      local pname = def.param_name or ""
      if not is_offline then
        local _, live_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
        pname = live_name
        if def.param_name and def.param_name ~= "" and live_name ~= def.param_name then
          local found = nil
          local scan = math.min(param_count, 512)
          for i = 0, scan - 1 do
            local _, n = r.TrackFX_GetParamName(track, fx_index, i, "")
            if n == def.param_name then found = i break end
          end
          if found then param_idx = found; pname = def.param_name end
        end
      end
      local pkey = param_key(fx_guid, param_idx)
      if not state.pinned_params[track_id][pkey] then
        state.pinned_params[track_id][pkey] = {
          track_guid = track_id,
          fx_guid = fx_guid,
          param_idx = param_idx,
          param_name = (pname ~= "" and pname) or (def.param_name ~= "" and def.param_name) or ("Param " .. tostring(param_idx)),
          fx_name = fx_name or "",
          slot = def.slot,
          custom_name = def.custom_name or "",
          style = def.style or "",
          display = def.display,
          under_label = def.under_label,
          reset_value = def.reset_value
        }
        applied = applied + 1
      end
      if restore_values and def.value ~= nil and not is_offline then
        r.TrackFX_SetParamNormalized(track, fx_index, param_idx, math.max(0, math.min(1, def.value)))
        restored = restored + 1
      end
    end
  end
  if applied > 0 then save_pinned_params() end
  if not silent then
    if restored > 0 then
      app.status = "Applied " .. tostring(#defaults_list) .. " default pins (restored " .. tostring(restored) .. " values)"
    else
      app.status = applied > 0 and ("Applied " .. tostring(applied) .. " default pins") or "Default pins already applied"
    end
  end
  return applied > 0 or restored > 0
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

local function pinned_display_name(entry)
  if entry and entry.custom_name and entry.custom_name ~= "" then return entry.custom_name end
  return (entry and entry.param_name) or ""
end

local function pinned_display_mode(settings, entry)
  if entry and (entry.display == "name" or entry.display == "value") then return entry.display end
  return settings.pinned_param_display or "name"
end

local function pinned_show_under_label(settings, entry)
  if entry and (entry.under_label == true or entry.under_label == false) then return entry.under_label end
  return settings.pinned_param_under_label ~= false
end

function reset_pinned_param(track, fx_index, entry, param_idx)
  param_idx = param_idx or (entry and entry.param_idx)
  if not param_idx then return end
  if entry and type(entry.reset_value) == "number" then
    r.TrackFX_SetParamNormalized(track, fx_index, param_idx, math.max(0, math.min(1, entry.reset_value)))
  else
    local _, minval = r.TrackFX_GetParamEx(track, fx_index, param_idx)
    r.TrackFX_SetParam(track, fx_index, param_idx, minval or 0)
  end
end

local function draw_param_context_menu(app, ctx, track, fx_index, param_idx, entry)
  local request_unpin = false
  local current_value = r.TrackFX_GetParam(track, fx_index, param_idx)
  if r.ImGui_MenuItem(ctx, "Reset") then
    reset_pinned_param(track, fx_index, entry, param_idx)
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
  if entry then
    r.ImGui_Text(ctx, "Name")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
    local rename_changed, rename_value = r.ImGui_InputTextWithHint(ctx, "##ir_rename_pin_" .. tostring(param_idx), entry.param_name ~= "" and entry.param_name or "Name", entry.custom_name or "")
    if rename_changed then entry.custom_name = rename_value end
    if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
      save_pinned_params()
      app.status = "Renamed pinned parameter"
    end
    if entry.custom_name and entry.custom_name ~= "" then
      if r.ImGui_MenuItem(ctx, "Reset name") then
        entry.custom_name = ""
        save_pinned_params()
        app.status = "Reset parameter name"
      end
    end
    local is_button = (entry.style or "") == "button"
    if r.ImGui_MenuItem(ctx, "Button layout", nil, is_button) then
      entry.style = is_button and "knob" or "button"
      save_pinned_params()
      app.status = is_button and "Parameter shown as knob" or "Parameter shown as button"
    end
    if r.ImGui_BeginMenu(ctx, "Show") then
      if r.ImGui_MenuItem(ctx, "Default", nil, entry.display == nil) then
        entry.display = nil; save_pinned_params(); app.status = "Label: default"
      end
      if r.ImGui_MenuItem(ctx, "Name", nil, entry.display == "name") then
        entry.display = "name"; save_pinned_params(); app.status = "Label: name"
      end
      if r.ImGui_MenuItem(ctx, "Value", nil, entry.display == "value") then
        entry.display = "value"; save_pinned_params(); app.status = "Label: value"
      end
      r.ImGui_EndMenu(ctx)
    end
    if r.ImGui_BeginMenu(ctx, "Label under") then
      if r.ImGui_MenuItem(ctx, "Default", nil, entry.under_label == nil) then
        entry.under_label = nil; save_pinned_params(); app.status = "Under label: default"
      end
      if r.ImGui_MenuItem(ctx, "Show", nil, entry.under_label == true) then
        entry.under_label = true; save_pinned_params(); app.status = "Under label: shown"
      end
      if r.ImGui_MenuItem(ctx, "Hide", nil, entry.under_label == false) then
        entry.under_label = false; save_pinned_params(); app.status = "Under label: hidden"
      end
      r.ImGui_EndMenu(ctx)
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Save current value as reset default") then
      entry.reset_value = r.TrackFX_GetParamNormalized(track, fx_index, param_idx)
      save_pinned_params()
      app.status = "Saved reset default value"
    end
    if type(entry.reset_value) == "number" then
      if r.ImGui_MenuItem(ctx, "Clear reset default value") then
        entry.reset_value = nil
        save_pinned_params()
        app.status = "Cleared reset default value"
      end
    end
  end
  r.ImGui_Separator(ctx)
  if r.SNM_AddTCPFXParm then
    local in_container = fx_index >= CONTAINER_BASE
    if r.ImGui_MenuItem(ctx, "Add to TCP/MCP", nil, false, not in_container) then
      tcp_add_fx_parm(track, fx_index, param_idx)
      app.status = "Added to TCP/MCP"
    end
    if in_container then
      local flags = r.ImGui_HoveredFlags_AllowWhenDisabled and r.ImGui_HoveredFlags_AllowWhenDisabled() or nil
      if r.ImGui_IsItemHovered(ctx, flags) then r.ImGui_SetTooltip(ctx, "Not available for FX inside a container") end
    end
    if r.ImGui_MenuItem(ctx, "Remove from TCP/MCP") then
      tcp_remove_fx_parm(track, fx_index, param_idx)
      app.status = "Removed from TCP/MCP"
    end
    r.ImGui_Separator(ctx)
  end
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
  r.DeleteExtState("TKMIX", "rack_add_container", false)
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
  if target_type == "input" or target_type == "item" then
    r.SetExtState("TKMIX", "rack_add_chain", target_type, false)
  elseif r.HasExtState("TKMIX", "rack_add_chain") then
    r.DeleteExtState("TKMIX", "rack_add_chain", false)
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
    r.SetExtState(section, "visibility", "visible", true)
    app.status = "Showing " .. nice_name
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

local function open_container_add_browser(app, chain, container_api)
  chain = as_chain(chain)
  if not chain_valid(chain) then return end
  local cguid = c_guid(chain, container_api)
  if not cguid or cguid == "" then return end
  local target = (app.settings and app.settings.add_fx_target) or "tk_fx_browser"
  if target == "native" then
    open_add_fx_browser(app, chain.track, chain.kind == "item" and "item" or "track", chain.take)
    return
  end
  local kind = chain.kind == "item" and "item" or "track"
  local tguid = track_guid(chain.track)
  if not tguid or tguid == "" then return end
  open_add_fx_browser(app, chain.track, "track", chain.take)
  r.SetExtState("TKMIX", "rack_add_container", tguid .. "|" .. kind .. "|" .. cguid, false)
end

function ir_apply_saturation(rgba, sat)
  sat = tonumber(sat)
  if not sat or sat >= 1 then return rgba end
  if sat < 0 then sat = 0 end
  local a = rgba & 0xFF
  local rr = ((rgba >> 24) & 0xFF) / 255
  local gg = ((rgba >> 16) & 0xFF) / 255
  local bb = ((rgba >> 8) & 0xFF) / 255
  local gray = 0.299 * rr + 0.587 * gg + 0.114 * bb
  rr = gray + (rr - gray) * sat
  gg = gray + (gg - gray) * sat
  bb = gray + (bb - gray) * sat
  local R = math.floor(math.max(0, math.min(1, rr)) * 255 + 0.5)
  local G = math.floor(math.max(0, math.min(1, gg)) * 255 + 0.5)
  local B = math.floor(math.max(0, math.min(1, bb)) * 255 + 0.5)
  return ((R & 0xFF) << 24) | ((G & 0xFF) << 16) | ((B & 0xFF) << 8) | a
end

local function get_track_header_color(settings, track)
  if not validate_track(track) then return 0x44444488 end
  local native = r.GetTrackColor(track) or 0
  if native == 0 then return 0x44444488 end
  local cr, cg, cb = r.ColorFromNative(native)
  local col = ((cr & 0xFF) << 24) | ((cg & 0xFF) << 16) | ((cb & 0xFF) << 8) | 0xCC
  return ir_apply_saturation(col, settings and settings.track_color_saturation)
end

local function luminance(rgba)
  local cr = (rgba >> 24) & 0xFF
  local cg = (rgba >> 16) & 0xFF
  local cb = (rgba >> 8) & 0xFF
  return (0.299 * cr + 0.587 * cg + 0.114 * cb) / 255
end

local function add_zone_visible_color()
  local bg = Theme.colors.child_bg or 0x1E1E1EFF
  return luminance(bg) > 0.5 and 0x2A2A2AFF or 0xD2D2D2FF
end

local function section_accent_color(settings, track)
  if settings and settings.section_track_color and validate_track(track) then
    local native = r.GetTrackColor(track) or 0
    if native ~= 0 then
      local cr, cg, cb = r.ColorFromNative(native)
      local col = ((cr & 0xFF) << 24) | ((cg & 0xFF) << 16) | ((cb & 0xFF) << 8) | 0xCC
      return ir_apply_saturation(col, settings.track_color_saturation)
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

M.launch_horizontal_rack = launch_horizontal_rack

local function draw_rack_settings_popup(app, ctx, settings, track)
  if r.ImGui_BeginPopup(ctx, "Instrument Rack Settings") then
    local changed, value
    if settings.orientation ~= "horizontal" then
      if r.ImGui_Button(ctx, "Open horizontal window##ir_open_horizontal") then
        launch_horizontal_rack(app)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_Separator(ctx)
    end
    local two_col = true
    local table_open = false
    if two_col and r.ImGui_BeginTable then
      local tflags = (r.ImGui_TableFlags_SizingStretchSame and r.ImGui_TableFlags_SizingStretchSame() or 0)
      if r.ImGui_BeginTable(ctx, "##ir_settings_cols", 2, tflags) then
        table_open = true
        r.ImGui_TableNextRow(ctx)
        r.ImGui_TableNextColumn(ctx)
      end
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Display")
    changed, value = r.ImGui_Checkbox(ctx, "Show screenshots", settings.show_screenshots)
    if changed then settings.show_screenshots = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show parameters", settings.show_pinned_params)
    if changed then settings.show_pinned_params = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show macros", settings.show_macros ~= false)
    if changed then settings.show_macros = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show info bar", settings.show_info_bar ~= false)
    if changed then settings.show_info_bar = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show item name on item FX tiles", settings.show_item_name_overlay ~= false)
    if changed then settings.show_item_name_overlay = value; if app.save_settings then app.save_settings() end end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Controls")
    local macro_total = settings.macro_count == 16 and 16 or 8
    r.ImGui_Text(ctx, "Macro count")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, tostring(macro_total) .. "##ir_macro_count", UIScale.text_button_w(ctx, tostring(macro_total), 60, 8), 0) then
      settings.macro_count = macro_total == 8 and 16 or 8
      if app.save_settings then app.save_settings() end
    end
    local slot_layout = param_layout(settings)
    local slot_list = PARAM_LAYOUTS[param_orientation(settings)]
    local slot_label = string.format("%d (%dx%d)", slot_layout.count, slot_layout.rows, slot_layout.cols)
    r.ImGui_Text(ctx, "Parameter buttons")
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, slot_label .. "##ir_macro_param_slots", UIScale.text_button_w(ctx, slot_label, 96, 8), 0) then
      local slot_idx = 1
      for i, e in ipairs(slot_list) do if e.count == slot_layout.count then slot_idx = i break end end
      settings[param_slots_key(settings)] = slot_list[(slot_idx % #slot_list) + 1].count
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Number of pinned parameter slots for the current orientation (cycles through presets)") end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderDouble(ctx, "Wet knob size", tonumber(settings.wet_knob_scale) or 1.0, 0.7, 1.0, "%.2f x")
    if changed then settings.wet_knob_scale = value; if app.save_settings then app.save_settings() end end
    local alpha_pct = math.floor(((tonumber(settings.wet_knob_alpha) or 1.0) * 100) + 0.5)
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Wet knob alpha", alpha_pct, 10, 100, "%d%%")
    if changed then settings.wet_knob_alpha = value / 100; if app.save_settings then app.save_settings() end end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Pinned parameters")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Label size", tonumber(settings.pinned_param_label_size) or 8, 6, 16, "%d px")
    if changed then settings.pinned_param_label_size = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Font size of the pinned parameter label (does not change the knob size)") end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderDouble(ctx, "Knob size", tonumber(settings.pinned_param_scale) or 1.0, 0.7, 1.0, "%.2f x")
    if changed then settings.pinned_param_scale = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Scale of the pinned parameter knob / button (does not change the label size)") end
    local pinned_alpha_pct = math.floor(((tonumber(settings.pinned_param_alpha) or 1.0) * 100) + 0.5)
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Knob alpha", pinned_alpha_pct, 10, 100, "%d%%")
    if changed then settings.pinned_param_alpha = value / 100; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Transparency of the pinned parameter knob / button") end
    local pinned_text_alpha_pct = math.floor(((tonumber(settings.pinned_param_text_alpha) or 1.0) * 100) + 0.5)
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Text alpha", pinned_text_alpha_pct, 10, 100, "%d%%")
    if changed then settings.pinned_param_text_alpha = value / 100; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Transparency of the pinned parameter value and label text") end
    changed, value = r.ImGui_Checkbox(ctx, "Show value instead of name", settings.pinned_param_display == "value")
    if changed then settings.pinned_param_display = value and "value" or "name"; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Show the parameter value as the label instead of the name") end
    changed, value = r.ImGui_Checkbox(ctx, "Button layout by default", settings.pinned_param_style == "button")
    if changed then settings.pinned_param_style = value and "button" or "knob"; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Draw pinned parameters as on/off buttons instead of knobs. Right-click a parameter to override per parameter") end
    changed, value = r.ImGui_Checkbox(ctx, "Show label under knob/button", settings.pinned_param_under_label ~= false)
    if changed then settings.pinned_param_under_label = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Show the parameter name label below the knob / button") end
    changed, value = r.ImGui_Checkbox(ctx, "Hide button value until used", settings.pinned_param_hide_value == true)
    if changed then settings.pinned_param_hide_value = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Hide the value shown on button / cycle parameters until you click, drag or hover them (like the knob layout)") end
    changed, value = r.ImGui_Checkbox(ctx, "Show shortcut hints in tooltips", settings.pinned_param_tooltip_hints ~= false)
    if changed then settings.pinned_param_tooltip_hints = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Show the extra control hints (drag, click, reset, ...) in the parameter tooltips. The parameter name and value are always shown") end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "FX sources")
    changed, value = r.ImGui_Checkbox(ctx, "Show track FX", settings.show_track_fx)
    if changed then settings.show_track_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show input FX", settings.show_input_fx)
    if changed then settings.show_input_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show take FX (selected item)", settings.show_selected_item_fx)
    if changed then settings.show_selected_item_fx = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Shows the take FX chain of the selected item on the track") end
    if table_open then r.ImGui_TableNextColumn(ctx) else r.ImGui_Separator(ctx) end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Layout")
    changed, value = r.ImGui_Checkbox(ctx, "Compact tiles", settings.tile_compact)
    if changed then settings.tile_compact = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Signal flow order (Input > Take > Track)", settings.section_order == "signal_flow")
    if changed then settings.section_order = value and "signal_flow" or "default"; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Color sections by track color", settings.section_track_color == true)
    if changed then settings.section_track_color = value; if app.save_settings then app.save_settings() end end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Track color saturation", math.floor((tonumber(settings.track_color_saturation) or 1.0) * 100 + 0.5), 0, 100, "%d%%")
    if changed then settings.track_color_saturation = value / 100; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Lower the saturation of inherited track colors in the header and sections to better match the real track color") end
    changed, value = r.ImGui_Checkbox(ctx, "Hide parallel/serial tiles", settings.hide_parallel_serial_badges == true)
    if changed then settings.hide_parallel_serial_badges = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Highlight instruments", settings.distinguish_instruments ~= false)
    if changed then settings.distinguish_instruments = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Give instrument plugins (VSTi, VST3i, CLAPi, ...) an accent-colored border to set them apart from effects") end
    changed, value = r.ImGui_Checkbox(ctx, "Plugin type badge on screenshot", settings.show_type_badge == true)
    if changed then settings.show_type_badge = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Show a small plugin-type label (VST3i, CLAP, JS, ...) in the top-right corner of each screenshot, like the Plugin Browser") end
    changed, value = r.ImGui_Checkbox(ctx, "Center plugin name", settings.fx_name_center == true)
    if changed then settings.fx_name_center = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Center the plugin name in the FX tile title instead of left-aligning it") end
    changed, value = r.ImGui_Checkbox(ctx, "Center track name", settings.header_center_name == true)
    if changed then settings.header_center_name = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Center the track name in the rack header") end
    changed, value = r.ImGui_Checkbox(ctx, "Track name badge", settings.header_name_badge == true)
    if changed then settings.header_name_badge = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Draw a rounded background badge behind the track name to make it stand out") end
    changed, value = r.ImGui_Checkbox(ctx, "Hide track number", settings.hide_track_number == true)
    if changed then settings.hide_track_number = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Hide the track number (and separator) in the rack header, showing only the track name") end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Track name opacity", math.floor(tonumber(settings.track_name_alpha) or 100), 10, 100, "%d%%")
    if changed then settings.track_name_alpha = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Opacity of the track name in the rack header") end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Panel name opacity", math.floor(tonumber(settings.panel_name_alpha) or 100), 10, 100, "%d%%")
    if changed then settings.panel_name_alpha = value; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Opacity of the section/panel names (Track FX, Track Input FX, Selected Track Item FX)") end
    if settings.orientation == "horizontal" then
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
      changed, value = r.ImGui_SliderInt(ctx, "Tile width", settings.horizontal_tile_width or 240, 160, 400, "%d px")
      if changed then settings.horizontal_tile_width = value; if app.save_settings then app.save_settings() end end
      changed, value = r.ImGui_Checkbox(ctx, "Vertical title bar (left)", settings.horizontal_titlebar_left == true)
      if changed then settings.horizontal_titlebar_left = value; if app.save_settings then app.save_settings() end end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move the title bar to a narrow vertical strip on the left side of the rack") end
      changed, value = r.ImGui_Checkbox(ctx, "Hide horizontal scrollbar", settings.hide_horizontal_scrollbar)
      if changed then settings.hide_horizontal_scrollbar = value; if app.save_settings then app.save_settings() end end
      changed, value = r.ImGui_Checkbox(ctx, "Invert wheel scroll direction", settings.invert_horizontal_scroll)
      if changed then settings.invert_horizontal_scroll = value; if app.save_settings then app.save_settings() end end
    end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
    changed, value = r.ImGui_SliderInt(ctx, "Screenshot height", settings.screenshot_height or 90, 48, 400, "%d px")
    if changed then settings.screenshot_height = value; if app.save_settings then app.save_settings() end end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Default parameter pins")
    changed, value = r.ImGui_Checkbox(ctx, "Auto-apply default pins on load", settings.auto_apply_default_pins == true)
    if changed then
      settings.auto_apply_default_pins = value
      state.auto_pin_checked = {}
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Automatically pin each plugin's saved default parameters when it first appears in the rack") end
    changed, value = r.ImGui_Checkbox(ctx, "Restore saved parameter values on apply", settings.restore_default_pin_values == true)
    if changed then
      settings.restore_default_pin_values = value
      state.auto_pin_checked = {}
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "When applying default pins, also set each parameter to the value stored when you saved the default pins") end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "TCP / MCP")
    changed, value = r.ImGui_Checkbox(ctx, "Also add pins to TCP/MCP", settings.add_pins_to_tcp == true)
    if changed then
      settings.add_pins_to_tcp = value
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "When pinning a parameter, also add it to the REAPER track control panel (TCP/MCP). Removing the pin removes it again") end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Add FX target")
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
    changed, value = r.ImGui_Checkbox(ctx, "Show Quick Add (cascading menu)", settings.quick_add_enabled ~= false)
    if changed then
      settings.quick_add_enabled = value
      if app.save_settings then app.save_settings() end
    end
    changed, value = r.ImGui_Checkbox(ctx, "Show border around Add buttons", settings.add_zone_border ~= false)
    if changed then
      settings.add_zone_border = value
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Draw an outline around the Add FX / Quick Add buttons (also still shown on hover and while dragging)") end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Refresh screenshots##ir_refresh_screenshots") then
      state.screenshot_index = nil
      state.screenshot_cache = {}
      state.screenshot_missing = {}
      app.status = "Screenshot index refreshed"
    end
    if table_open then r.ImGui_EndTable(ctx) end
    r.ImGui_EndPopup(ctx)
  end
end

local function shade_color(col, f)
  local rr = math.floor(((col >> 24) & 0xFF) * f)
  local gg = math.floor(((col >> 16) & 0xFF) * f)
  local bb = math.floor(((col >> 8) & 0xFF) * f)
  return (rr << 24) | (gg << 16) | (bb << 8) | (col & 0xFF)
end

function apply_text_alpha(col, factor)
  local a = math.floor((col & 0xFF) * (factor or 1) + 0.5)
  if a < 0 then a = 0 elseif a > 255 then a = 255 end
  return (col & 0xFFFFFF00) | a
end

local function draw_header_vertical(app, ctx, settings, track, bar_h)
  local label = get_track_label(track)
  local num_str = "-"
  local name_str = label
  if validate_track(track) then
    if track == r.GetMasterTrack(0) then
      num_str = "M"
      name_str = "MASTER"
    else
      num_str = tostring(math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0))
      local stripped = label:match("^%d+%s*%-%s*(.+)$")
      if stripped and stripped ~= "" then name_str = stripped end
    end
  end
  local header_color = get_track_header_color(settings, track)
  local text_color = luminance(header_color) > 0.55 and 0x000000FF or 0xFFFFFFFF
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local bw = button_h
  local bar_w = bw + UIScale.round(8)
  local pad = UIScale.round(4)
  local gap = UIScale.round(5)
  local oy = UIScale.round(4)
  local flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  if r.ImGui_BeginChild(ctx, "##ir_vbar", bar_w, bar_h + oy, 0, flags) then
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
    local base_y = cursor_y + oy
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local show_header_close = app and app.script_name == "TK Instrument Rack (Horizontal)"
    local n_buttons = 2 + (show_header_close and 1 or 0)
    local buttons_h = n_buttons * bw + (n_buttons - 1) * gap
    local buttons_top = base_y + bar_h - pad - buttons_h
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, base_y, cursor_x + bar_w, base_y + bar_h, header_color, UIScale.px(3))
    local show_number = not settings.hide_track_number
    local num_h = show_number and UIScale.round(16) or 0
    if show_number then
      local num_col = shade_color(header_color, 0.62)
      local num_text_color = luminance(num_col) > 0.55 and 0x000000FF or 0xFFFFFFFF
      local top_corner = r.ImGui_DrawFlags_RoundCornersTop and r.ImGui_DrawFlags_RoundCornersTop() or 0
      r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, base_y, cursor_x + bar_w, base_y + num_h, num_col, UIScale.px(3), top_corner)
      if num_str and num_str ~= "" then
        local nw, nh = r.ImGui_CalcTextSize(ctx, num_str)
        r.ImGui_DrawList_AddText(draw_list, cursor_x + (bar_w - nw) * 0.5, base_y + (num_h - nh) * 0.5, num_text_color, num_str)
      end
    end
    if name_str and name_str ~= "" then
      local target_size = UIScale.round(12)
      local font_size = r.ImGui_GetFontSize(ctx)
      local scale = target_size / font_size
      local line_h = target_size + UIScale.round(1)
      local top = base_y + num_h + pad
      local avail_h = (buttons_top - gap) - top
      local name_color = apply_text_alpha(text_color, (math.floor(tonumber(settings.track_name_alpha) or 100)) / 100)
      if avail_h > line_h then
        local chars = {}
        for ch in name_str:gmatch(".") do chars[#chars + 1] = ch end
        local max_chars = math.max(1, math.floor(avail_h / line_h))
        local truncated = #chars > max_chars
        local shown = math.min(#chars, max_chars)
        if truncated then chars[shown] = "\u{2026}" end
        local total_h = shown * line_h
        local start_y = top + math.max(0, (avail_h - total_h) * 0.5)
        for i = 1, shown do
          local ch = chars[i]
          local ch_w = r.ImGui_CalcTextSize(ctx, ch) * scale
          r.ImGui_DrawList_AddTextEx(draw_list, nil, target_size, cursor_x + (bar_w - ch_w) * 0.5, start_y + (i - 1) * line_h, name_color, ch)
        end
      end
    end
    local bx_screen = cursor_x + (bar_w - bw) * 0.5
    local cur_by = buttons_top
    local pinned = settings.pinned_track_guid ~= ""
    r.ImGui_SetCursorScreenPos(ctx, bx_screen, cur_by)
    if r.ImGui_InvisibleButton(ctx, "##ir_vpin", bw, bw) then
      if pinned then
        settings.pinned_track_guid = ""
        app.status = "Instrument Rack follows selected track"
      elseif track then
        settings.pinned_track_guid = track_guid(track)
        app.status = "Instrument Rack pinned to " .. label
      end
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, pinned and "Unpin track" or "Pin track") end
    local pcx, pcy = bx_screen + bw * 0.5, cur_by + bw * 0.5
    local pin_col = pinned and 0x7AA2F7FF or text_color
    r.ImGui_DrawList_AddCircleFilled(draw_list, pcx, pcy - UIScale.px(3), bw * 0.2, pin_col)
    r.ImGui_DrawList_AddLine(draw_list, pcx, pcy - UIScale.px(1), pcx, pcy + bw * 0.3, pin_col, UIScale.px(1.5))
    cur_by = cur_by + bw + gap
    r.ImGui_SetCursorScreenPos(ctx, bx_screen, cur_by)
    if r.ImGui_InvisibleButton(ctx, "##ir_vsettings", bw, bw) then r.ImGui_OpenPopup(ctx, "Instrument Rack Settings") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Instrument Rack settings") end
    local scx, scy = bx_screen + bw * 0.5, cur_by + bw * 0.5
    local dotr = UIScale.px(1.4)
    r.ImGui_DrawList_AddCircleFilled(draw_list, scx - bw * 0.22, scy, dotr, text_color)
    r.ImGui_DrawList_AddCircleFilled(draw_list, scx, scy, dotr, text_color)
    r.ImGui_DrawList_AddCircleFilled(draw_list, scx + bw * 0.22, scy, dotr, text_color)
    cur_by = cur_by + bw + gap
    if show_header_close then
      r.ImGui_SetCursorScreenPos(ctx, bx_screen, cur_by)
      local close_dot_d = math.max(UIScale.round(10), bw - UIScale.round(4))
      local cmx, cmy = bx_screen + bw * 0.5, cur_by + bw * 0.5
      r.ImGui_DrawList_AddCircleFilled(draw_list, cmx, cmy, close_dot_d * 0.5, 0xF7768EFF)
      r.ImGui_DrawList_AddCircle(draw_list, cmx, cmy, close_dot_d * 0.5, 0x3A1018FF, 16, UIScale.px(1))
      if r.ImGui_InvisibleButton(ctx, "##ir_vclose", bw, bw) then app.close_requested = true end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
    end
    draw_rack_settings_popup(app, ctx, settings, track)
    r.ImGui_EndChild(ctx)
  end
  return bar_w
end

local function draw_header(app, ctx, settings, track)
  local label = get_track_label(track)
  if settings.hide_track_number and validate_track(track) and track ~= r.GetMasterTrack(0) then
    local stripped = label:match("^%d+%s*%-%s*(.+)$")
    if stripped and stripped ~= "" then label = stripped end
  end
  local header_color = get_track_header_color(settings, track)
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
  local show_header_close = settings.orientation == "horizontal" and app and app.script_name == "TK Instrument Rack (Horizontal)"
  local pin_label = (settings.pinned_track_guid ~= "" and "Unpin" or "Pin")
  local pin_w = UIScale.text_button_w(ctx, pin_label, 0, 8)
  local gap = UIScale.round(4)
  local buttons_w = pin_w + gap + button_h + (show_header_close and (gap + button_h) or 0)
  r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + avail, cursor_y + bar_h, header_color, UIScale.px(3))
  local name_left = cursor_x + pad_x
  local name_right = cursor_x + avail - buttons_w - gap * 2
  local name_x = name_left
  if settings.header_center_name then
    name_x = name_left + math.max(0, ((name_right - name_left) - text_w) * 0.5)
  end
  r.ImGui_DrawList_PushClipRect(draw_list, cursor_x + pad_x, cursor_y, math.max(cursor_x + pad_x, name_right), cursor_y + bar_h, true)
  local name_alpha = (math.floor(tonumber(settings.track_name_alpha) or 100)) / 100
  if settings.header_name_badge and label ~= "" then
    local bpx, bpy = UIScale.round(7), UIScale.round(2)
    local badge_col = shade_color(header_color, 0.5)
    local badge_text_color = luminance(badge_col) > 0.55 and 0x000000FF or 0xFFFFFFFF
    local bx0 = name_x - bpx
    local by0 = cursor_y + (bar_h - text_h) * 0.5 - bpy
    local bx1 = name_x + text_w + bpx
    local by1 = cursor_y + (bar_h - text_h) * 0.5 + text_h + bpy
    r.ImGui_DrawList_AddRectFilled(draw_list, bx0, by0, bx1, by1, badge_col, UIScale.px(4))
    r.ImGui_DrawList_AddRect(draw_list, bx0, by0, bx1, by1, (badge_text_color & 0xFFFFFF00) | 0x33, UIScale.px(4), 0, UIScale.px(1))
    r.ImGui_DrawList_AddText(draw_list, name_x, cursor_y + (bar_h - text_h) * 0.5, apply_text_alpha(badge_text_color, name_alpha), label)
  else
    r.ImGui_DrawList_AddText(draw_list, name_x, cursor_y + (bar_h - text_h) * 0.5, apply_text_alpha(text_color, name_alpha), label)
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
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
  if show_header_close then
    r.ImGui_SameLine(ctx, nil, gap)
    local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
    local close_dot_d = math.max(UIScale.round(10), button_h - UIScale.round(4))
    local close_mid_x = close_x + button_h * 0.5
    local close_mid_y = close_y + button_h * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_mid_x, close_mid_y, close_dot_d * 0.5, 0xF7768EFF)
    r.ImGui_DrawList_AddCircle(draw_list, close_mid_x, close_mid_y, close_dot_d * 0.5, 0x3A1018FF, 16, UIScale.px(1))
    if r.ImGui_InvisibleButton(ctx, "##ir_horizontal_close_dot", button_h, button_h) then app.close_requested = true end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
  end
  r.ImGui_SetCursorPosX(ctx, start_pos_x)
  r.ImGui_SetCursorPosY(ctx, start_pos_y + bar_h)
  draw_rack_settings_popup(app, ctx, settings, track)
end

local function get_fx_short_name(fx_name)
  local name = clean_fx_name(fx_name or "")
  if name == "" then name = fx_name or "FX" end
  return name
end

local function fx_name_is_instrument(fx_name)
  local prefix = tostring(fx_name or ""):match("^([%w%d]+):")
  return prefix ~= nil and prefix:sub(-1) == "i"
end

local FX_TYPE_BADGE_COLORS = {
  VST3 = 0x4FC1E9FF,
  VST = 0x48CFADFF,
  CLAP = 0xAC92ECFF,
  JS = 0xFFCE54FF,
  AU = 0xED5565FF,
  LV2 = 0xA0D568FF,
  OTHER = 0x888888FF
}

local function fx_type_prefix(fx_name)
  local prefix = tostring(fx_name or ""):match("^([%w%d]+):")
  if not prefix then return nil, nil end
  local base = prefix:gsub("[iI]$", ""):upper()
  if base == "JSFX" then base = "JS" end
  if not FX_TYPE_BADGE_COLORS[base] then base = "OTHER" end
  return prefix, base
end

local function draw_fx_type_badge(ctx, draw_list, fx_name, right_x, top_y)
  local label, base = fx_type_prefix(fx_name)
  if not label then return end
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  local px = UIScale.round(4)
  local py = UIScale.round(2)
  local pad = UIScale.round(8)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local badge_w = text_w + px * 2
  local bx = right_x - badge_w - pad
  local by = top_y + pad
  r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + badge_w, by + line_h + py * 2, FX_TYPE_BADGE_COLORS[base], UIScale.round(4))
  r.ImGui_DrawList_AddText(draw_list, bx + px, by + py, Theme.colors.badge_text or 0x101010FF, label)
end

local function get_wet_param_index(track, fx_index)
  local idx = r.TrackFX_GetParamFromIdent(track, fx_index, ":wet")
  if idx and idx >= 0 then return idx end
  return nil
end

local function get_fx_wet(track, fx_index)
  local fx_guid = get_fx_guid(track, fx_index)
  if r.TrackFX_GetOffline(track, fx_index) then
    local cached = state.fx_value_cache[fx_guid]
    return cached and cached.wet or 1.0
  end
  local idx = get_wet_param_index(track, fx_index)
  if not idx then
    local cached = state.fx_value_cache[fx_guid]
    return cached and cached.wet or 1.0
  end
  local value = r.TrackFX_GetParamNormalized(track, fx_index, idx) or 1.0
  fx_value_bucket(fx_guid).wet = value
  return value
end

local function set_fx_wet(track, fx_index, value)
  local idx = get_wet_param_index(track, fx_index)
  if not idx then return end
  if value < 0 then value = 0 elseif value > 1 then value = 1 end
  r.TrackFX_SetParamNormalized(track, fx_index, idx, value)
end

local function draw_wet_knob(app, ctx, draw_list, track, fx_index, cx, cy, radius)
  local settings = ensure_settings(app)
  local alpha = tonumber(settings.wet_knob_alpha) or 1.0
  if alpha < 0.1 then alpha = 0.1 elseif alpha > 1.0 then alpha = 1.0 end
  local function with_alpha(color)
    local a = color & 0xFF
    local out_a = math.max(0, math.min(255, math.floor(a * alpha + 0.5)))
    return (color & 0xFFFFFF00) | out_a
  end
  local value = math.max(0, math.min(1, get_fx_wet(track, fx_index)))
  local start_angle = math.pi * 0.75
  local end_angle = math.pi * 2.25
  local value_angle = start_angle + value * (end_angle - start_angle)
  local segments = radius < 8 and 12 or (radius < 14 and 18 or 24)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx + UIScale.px(1), cy + UIScale.px(1), radius, with_alpha(0x00000066), segments)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, with_alpha(0x333333CC), segments)
  r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius - UIScale.px(2), start_angle, end_angle, segments)
  r.ImGui_DrawList_PathStroke(draw_list, with_alpha(0x2A2A2AFF), 0, UIScale.px(2))
  if value > 0.01 then
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius - UIScale.px(2), start_angle, value_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, with_alpha(0x8F8F8FFF), 0, UIScale.px(2.5))
  end
  local ind_x = cx + math.cos(value_angle) * (radius - UIScale.px(3))
  local ind_y = cy + math.sin(value_angle) * (radius - UIScale.px(3))
  r.ImGui_DrawList_AddLine(draw_list, cx, cy, ind_x, ind_y, with_alpha(0xFFFFFFFF), UIScale.px(2))
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius * 0.42, with_alpha(0xB8B8B8FF), segments)
  r.ImGui_SetCursorScreenPos(ctx, cx - radius - UIScale.round(3), cy - radius - UIScale.round(3))
  r.ImGui_InvisibleButton(ctx, "##ir_fx_wet_knob", (radius + UIScale.round(3)) * 2, (radius + UIScale.round(3)) * 2)
  local active = r.ImGui_IsItemActive(ctx)
  if active then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(dy) > 0 then
      value = math.max(0, math.min(1, value - dy * 0.005))
      set_fx_wet(track, fx_index, value)
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if active then
    local label = string.format("%d%%", math.floor(value * 100 + 0.5))
    local tw, th = r.ImGui_CalcTextSize(ctx, label)
    local lx = cx - tw * 0.5
    local ly = cy - th * 0.5
    r.ImGui_DrawList_AddRectFilled(draw_list, lx - UIScale.px(3), ly - UIScale.px(1), lx + tw + UIScale.px(3), ly + th + UIScale.px(1), with_alpha(0x000000CC), UIScale.px(3))
    r.ImGui_DrawList_AddText(draw_list, lx, ly, with_alpha(0xFFFFFFFF), label)
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    set_fx_wet(track, fx_index, 1.0)
    if app then app.status = "Wet reset to 100%" end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    set_fx_wet(track, fx_index, 1.0)
    if app then app.status = "Wet reset to 100%" end
  end
  if r.ImGui_IsItemHovered(ctx) or active then
    r.ImGui_SetTooltip(ctx, string.format("Wet: %d%%\nDrag to adjust - double/right-click to reset", math.floor(value * 100 + 0.5)))
  end
end

local function chain_wet_param(chain, api)
  if chain.kind == "item" then
    if not r.TakeFX_GetParamFromIdent then return nil end
    local idx = r.TakeFX_GetParamFromIdent(chain.take, api, ":wet")
    if idx and idx >= 0 then return idx end
    return nil
  end
  if not r.TrackFX_GetParamFromIdent then return nil end
  local idx = r.TrackFX_GetParamFromIdent(chain.track, api, ":wet")
  if idx and idx >= 0 then return idx end
  return nil
end

local function chain_get_wet(chain, api, idx)
  if chain.kind == "item" then return r.TakeFX_GetParamNormalized(chain.take, api, idx) or 1.0 end
  return r.TrackFX_GetParamNormalized(chain.track, api, idx) or 1.0
end

local function chain_set_wet(chain, api, idx, value)
  if value < 0 then value = 0 elseif value > 1 then value = 1 end
  if chain.kind == "item" then
    if r.TakeFX_SetParamNormalized then r.TakeFX_SetParamNormalized(chain.take, api, idx, value) end
    return
  end
  r.TrackFX_SetParamNormalized(chain.track, api, idx, value)
end

local function draw_container_wet_knob(app, ctx, draw_list, chain, api, wet_idx, cx, cy, radius, id)
  local settings = ensure_settings(app)
  local alpha = tonumber(settings.wet_knob_alpha) or 1.0
  if alpha < 0.1 then alpha = 0.1 elseif alpha > 1.0 then alpha = 1.0 end
  local function with_alpha(color)
    local a = color & 0xFF
    local out_a = math.max(0, math.min(255, math.floor(a * alpha + 0.5)))
    return (color & 0xFFFFFF00) | out_a
  end
  local value = math.max(0, math.min(1, chain_get_wet(chain, api, wet_idx)))
  local start_angle = math.pi * 0.75
  local end_angle = math.pi * 2.25
  local value_angle = start_angle + value * (end_angle - start_angle)
  local segments = radius < 8 and 12 or (radius < 14 and 18 or 24)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx + UIScale.px(1), cy + UIScale.px(1), radius, with_alpha(0x00000066), segments)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, with_alpha(0x333333CC), segments)
  r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius - UIScale.px(2), start_angle, end_angle, segments)
  r.ImGui_DrawList_PathStroke(draw_list, with_alpha(0x2A2A2AFF), 0, UIScale.px(2))
  if value > 0.01 then
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius - UIScale.px(2), start_angle, value_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, with_alpha(0x8F8F8FFF), 0, UIScale.px(2.5))
  end
  local ind_x = cx + math.cos(value_angle) * (radius - UIScale.px(3))
  local ind_y = cy + math.sin(value_angle) * (radius - UIScale.px(3))
  r.ImGui_DrawList_AddLine(draw_list, cx, cy, ind_x, ind_y, with_alpha(0xFFFFFFFF), UIScale.px(2))
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius * 0.42, with_alpha(0xB8B8B8FF), segments)
  r.ImGui_SetCursorScreenPos(ctx, cx - radius - UIScale.round(3), cy - radius - UIScale.round(3))
  r.ImGui_InvisibleButton(ctx, id or "##ir_cont_wet", (radius + UIScale.round(3)) * 2, (radius + UIScale.round(3)) * 2)
  local active = r.ImGui_IsItemActive(ctx)
  if active then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(dy) > 0 then
      value = math.max(0, math.min(1, value - dy * 0.005))
      chain_set_wet(chain, api, wet_idx, value)
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if active then
    local label = string.format("%d%%", math.floor(value * 100 + 0.5))
    local tw, th = r.ImGui_CalcTextSize(ctx, label)
    local lx = cx - tw * 0.5
    local ly = cy - th * 0.5
    r.ImGui_DrawList_AddRectFilled(draw_list, lx - UIScale.px(3), ly - UIScale.px(1), lx + tw + UIScale.px(3), ly + th + UIScale.px(1), with_alpha(0x000000CC), UIScale.px(3))
    r.ImGui_DrawList_AddText(draw_list, lx, ly, with_alpha(0xFFFFFFFF), label)
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    chain_set_wet(chain, api, wet_idx, 1.0)
    if app then app.status = "Container wet reset to 100%" end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    chain_set_wet(chain, api, wet_idx, 1.0)
    if app then app.status = "Container wet reset to 100%" end
  end
  if r.ImGui_IsItemHovered(ctx) or active then
    r.ImGui_SetTooltip(ctx, string.format("Container wet: %d%%\nDrag to adjust - double/right-click to reset", math.floor(value * 100 + 0.5)))
  end
  return active
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

local function add_empty_container(app, track, insert_index)
  if not validate_track(track) or not r.TrackFX_AddByName then return end
  local target = insert_index and (-1000 - insert_index) or -1
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local new_index = r.TrackFX_AddByName(track, "Container", false, target)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add container", -1)
  if new_index and new_index >= 0 then
    app.status = "Added container"
  else
    app.status = "Container could not be added"
  end
  return new_index
end

local wrap_nested_fx_in_container
local function wrap_fx_in_container(app, chain, source_api_id)
  chain = as_chain(chain)
  if not chain_valid(chain) then return end
  if not (c_add_capable(chain) and c_move_capable(chain)) then return end
  source_api_id = math.floor(tonumber(source_api_id) or -1)
  if source_api_id < 0 then return end
  if source_api_id >= CONTAINER_BASE then
    if wrap_nested_fx_in_container then wrap_nested_fx_in_container(app, chain, source_api_id) end
    return
  end
  local count = c_count(chain)
  if source_api_id >= count then return end
  local source_parallel = cfg(chain, source_api_id, "parallel") or "0"
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local new_container_api_id = c_add(chain, "Container", -1000 - source_api_id)
  local ok = new_container_api_id and new_container_api_id >= 0
  if ok then
    local container_api_id = new_container_api_id < CONTAINER_BASE and new_container_api_id or source_api_id
    local source_after_insert = source_api_id
    if container_api_id <= source_api_id then source_after_insert = source_api_id + 1 end
    cfg_set(chain, container_api_id, "parallel", source_parallel)
    cfg_set(chain, source_after_insert, "parallel", "0")
    local container_id = container_api_id + 1
    local parent_count = c_count(chain)
    local insert_index = CONTAINER_BASE + container_id + ((parent_count + 1) * 1)
    ok = c_move(chain, source_after_insert, insert_index) ~= false
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Wrap FX in container", -1)
  app.status = ok and "Wrapped FX in container" or "FX could not be wrapped"
end

local function unpack_container(app, chain, container_api_id)
  chain = as_chain(chain)
  if not chain_valid(chain) then return end
  if not (c_move_capable(chain) and c_count) then return end
  container_api_id = math.floor(tonumber(container_api_id) or -1)
  if container_api_id < 0 or container_api_id >= CONTAINER_BASE then
    app.status = "Unpack is only available for top-level containers"
    return
  end
  if not c_is_container(chain, container_api_id) then return end
  local container_id = container_api_id + 1
  local child_count = math.floor(tonumber(cfg(chain, CONTAINER_BASE + container_id, "container_count")) or 0)
  local container_parallel = cfg(chain, container_api_id, "parallel") or "0"
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok = true
  local moved = 0
  while ok and moved < child_count do
    local parent_count = c_count(chain)
    local child_api_id = CONTAINER_BASE + container_id + ((parent_count + 1) * 1)
    local child_parallel = cfg(chain, child_api_id, "parallel") or "0"
    local dest_index = container_api_id + moved + 1
    ok = c_move(chain, child_api_id, dest_index) ~= false
    if ok then
      cfg_set(chain, dest_index, "parallel", moved == 0 and container_parallel or child_parallel)
      moved = moved + 1
    end
  end
  if ok then ok = c_delete(chain, container_api_id) ~= false end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Unpack container", -1)
  app.status = ok and "Unpacked container" or "Container could not be unpacked"
end

local function toggle_fx_parallel(app, chain, api_id)
  chain = as_chain(chain)
  if not chain_valid(chain) then return end
  local current = cfg(chain, api_id, "parallel") or "0"
  local new_value = current ~= "0" and "0" or "1"
  r.Undo_BeginBlock()
  cfg_set(chain, api_id, "parallel", new_value)
  r.Undo_EndBlock("Toggle parallel", -1)
  app.status = new_value ~= "0" and "Set parallel" or "Set serial"
end

local function container_end_insert_index(chain, container_api)
  chain = as_chain(chain)
  local top_count = c_count(chain)
  if container_api < CONTAINER_BASE then
    local container_rel = container_api + 1
    local diff = top_count + 1
    local child_count = math.floor(tonumber(cfg(chain, CONTAINER_BASE + container_rel, "container_count")) or 0)
    return CONTAINER_BASE + container_rel + diff * (child_count + 1)
  end
  local function recurse(parent_rel, parent_count, parent_diff)
    local count = math.floor(tonumber(cfg(chain, CONTAINER_BASE + parent_rel, "container_count")) or 0)
    if count <= 0 then return nil end
    local diff = (parent_count + 1) * parent_diff
    for j = 1, count do
      local child_rel = parent_rel + diff * j
      local child_api = CONTAINER_BASE + child_rel
      if child_api == container_api then
        local inner_diff = (count + 1) * diff
        local cc = math.floor(tonumber(cfg(chain, child_api, "container_count")) or 0)
        return CONTAINER_BASE + child_rel + inner_diff * (cc + 1)
      end
      if c_is_container(chain, child_api) then
        local res = recurse(child_rel, count, diff)
        if res then return res end
      end
    end
    return nil
  end
  for i = 0, top_count - 1 do
    if c_is_container(chain, i) then
      local res = recurse(i + 1, top_count, 1)
      if res then return res end
    end
  end
  return nil
end

local function add_container_inside(app, chain, container_api)
  chain = as_chain(chain)
  if not chain_valid(chain) or not c_add_capable(chain) then return end
  if not c_is_container(chain, container_api) then return end
  local insert_index = container_end_insert_index(chain, container_api)
  if not insert_index then
    app.status = "Could not calculate container insert position"
    return
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local new_index = c_add(chain, "Container", insert_index)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add container inside", -1)
  if new_index and new_index >= 0 then
    app.status = "Added container inside"
  else
    app.status = "Container could not be added"
  end
  return new_index
end

function add_external_fx(app, track, payload, insert_index)
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
    local fx_index = r.TrackFX_AddByName(track, name, false, target_index)
    if fx_index < 0 and name:lower():sub(-9) == ".rfxchain" then
      local basename = name:match("([^/\\]+)$") or name
      if basename ~= name then r.TrackFX_AddByName(track, basename, false, target_index) end
    end
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

function add_external_input_fx(app, track, payload)
  if not validate_track(track) then return end
  local names = payload_to_names(payload)
  if #names == 0 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, name in ipairs(names) do
    local dest = r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(track) or 0
    local fx_index = r.TrackFX_AddByName(track, name, true, -1000 - dest)
    if fx_index < 0 and name:lower():sub(-9) == ".rfxchain" then
      local basename = name:match("([^/\\]+)$") or name
      if basename ~= name then r.TrackFX_AddByName(track, basename, true, -1000 - dest) end
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add input FX to instrument rack", -1)
  r.SetExtState("TKFXB", "drag_consumed", "1", false)
  r.DeleteExtState("TKFXB", "drag_fx", false)
  if r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
  app.status = "Added " .. tostring(#names) .. " input FX"
end

function add_external_take_fx(app, take, payload)
  if not validate_take(take) or not r.TakeFX_AddByName then return end
  local names = payload_to_names(payload)
  if #names == 0 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, name in ipairs(names) do
    local dest = r.TakeFX_GetCount and r.TakeFX_GetCount(take) or 0
    local fx_index = r.TakeFX_AddByName(take, name, -1000 - dest)
    if fx_index < 0 and name:lower():sub(-9) == ".rfxchain" then
      local basename = name:match("([^/\\]+)$") or name
      if basename ~= name then r.TakeFX_AddByName(take, basename, -1000 - dest) end
    end
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
  if r.GetTouchedOrFocusedFX or r.GetLastTouchedFX then
    local ok, touched_track, touched_fx, param_idx
    if r.GetTouchedOrFocusedFX then
      local got, track_index, item_index, _, fx_idx, parm = r.GetTouchedOrFocusedFX(0)
      ok = got
      if got and (not item_index or item_index < 0) then
        if track_index < 0 then touched_track = r.GetMasterTrack(0) else touched_track = r.GetTrack(0, track_index) end
        touched_fx = fx_idx
        param_idx = parm
      end
    else
      local got, track_index, fx_idx, parm = r.GetLastTouchedFX()
      ok = got
      if got then
        if track_index == 0 then touched_track = r.GetMasterTrack(0) else touched_track = r.GetTrack(0, track_index - 1) end
        touched_fx = fx_idx
        param_idx = parm
      end
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

local function truncate_to_width(ctx, text, max_w, size)
  text = tostring(text or "")
  if text == "" then return text end
  local font_size = r.ImGui_GetFontSize(ctx)
  if not font_size or font_size <= 0 then return text end
  local scale = size / font_size
  if r.ImGui_CalcTextSize(ctx, text) * scale <= max_w then return text end
  for n = #text - 1, 1, -1 do
    local cand = text:sub(1, n) .. "."
    if r.ImGui_CalcTextSize(ctx, cand) * scale <= max_w then return cand end
  end
  return text:sub(1, 1)
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
  local fx_guid = get_fx_guid(track, fx_index)
  if r.TrackFX_GetOffline(track, fx_index) then
    local cached = state.fx_value_cache[fx_guid]
    local value = cached and cached.params and cached.params[param_idx]
    return value or 0, false
  end
  local value = r.TrackFX_GetParamNormalized(track, fx_index, param_idx) or 0
  fx_value_bucket(fx_guid).params[param_idx] = value
  return value, false
end

local function set_rack_param_value(track, fx_index, param_idx, value, uses_baseline)
  value = math.max(0, math.min(1, value or 0))
  if uses_baseline then
    r.TrackFX_SetNamedConfigParm(track, fx_index, param_config_key(param_idx, "mod.baseline"), tostring(value))
  else
    r.TrackFX_SetParamNormalized(track, fx_index, param_idx, value)
  end
end

local function curve_quant_steps(amount)
  local t = math.log(math.max(0.1, math.min(10, tonumber(amount) or 1))) / math.log(10)
  local steps = math.floor(2 + (t + 1) * 0.5 * 14 + 0.5)
  return steps < 2 and 2 or (steps > 16 and 16 or steps)
end

local function shape_macro_value(value, curve_type, amount)
  value = value < 0 and 0 or (value > 1 and 1 or value)
  amount = tonumber(amount) or 1
  if curve_type == "scurve" then
    if amount == 1 then return value end
    if value < 0.5 then return 0.5 * (2 * value) ^ amount end
    return 1 - 0.5 * (2 * (1 - value)) ^ amount
  elseif curve_type == "quant" then
    local steps = curve_quant_steps(amount)
    if steps < 2 then return value end
    return math.floor(value * (steps - 1) + 0.5) / (steps - 1)
  elseif curve_type == "bipolar" then
    local d = math.abs(2 * value - 1)
    return amount == 1 and d or d ^ amount
  end
  return amount == 1 and value or value ^ amount
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
        local curve = tonumber(assignment.curve) or 1
        local shaped = shape_macro_value(value, assignment.curve_type, curve)
        local macro_value = assignment.inverted and (1 - shaped) or shaped
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
        r.ImGui_Separator(ctx)
        local curve = math.max(0.1, math.min(10, tonumber(assignment.curve) or 1))
        local curve_t = math.max(-1, math.min(1, math.log(curve) / math.log(10)))
        local ctype = assignment.curve_type or "power"
        local type_labels = { power = "Power", scurve = "S-Curve", quant = "Quantize", bipolar = "Bipolar" }
        local type_order = { "power", "scurve", "quant", "bipolar" }
        for ti, tname in ipairs(type_order) do
          if ti > 1 then r.ImGui_SameLine(ctx) end
          local selected = ctype == tname
          if selected then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent) end
          if r.ImGui_SmallButton(ctx, type_labels[tname] .. "##ir_curvetype_" .. tostring(slot) .. "_" .. tostring(assignment_index) .. "_" .. tname) then
            assignment.curve_type = tname
            ctype = tname
            save_macros()
          end
          if selected then r.ImGui_PopStyleColor(ctx) end
        end
        local info
        if ctype == "quant" then
          info = string.format("Quantize: %d steps", curve_quant_steps(curve))
        elseif ctype == "scurve" then
          info = string.format("S-Curve: %.2f", curve)
        elseif ctype == "bipolar" then
          info = string.format("Bipolar: %.2f", curve)
        else
          info = string.format("Power: %.2f", curve)
        end
        r.ImGui_Text(ctx, info)
        local pad = UIScale.round(112)
        local curve_draw = r.ImGui_GetWindowDrawList(ctx)
        local pad_x, pad_y = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_InvisibleButton(ctx, "##ir_curvepad_" .. tostring(slot) .. "_" .. tostring(assignment_index), pad, pad)
        if r.ImGui_IsItemActive(ctx) then
          local _, drag_y = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
          if math.abs(drag_y) > 0 then
            curve_t = math.max(-1, math.min(1, curve_t + drag_y * 0.01))
            assignment.curve = 10 ^ curve_t
            curve = assignment.curve
            save_macros()
            r.ImGui_ResetMouseDragDelta(ctx, 0)
          end
        end
        if r.ImGui_IsItemHovered(ctx) then
          if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            assignment.curve = 1
            curve = 1
            save_macros()
          end
          r.ImGui_SetTooltip(ctx, "Drag up/down to change the curve amount.\nDouble-click to reset.")
        end
        r.ImGui_DrawList_AddRectFilled(curve_draw, pad_x, pad_y, pad_x + pad, pad_y + pad, 0x1E222BFF, UIScale.round(4))
        r.ImGui_DrawList_AddRect(curve_draw, pad_x, pad_y, pad_x + pad, pad_y + pad, Theme.colors.border, UIScale.round(4))
        r.ImGui_DrawList_AddLine(curve_draw, pad_x, pad_y + pad, pad_x + pad, pad_y, 0x39414FFF, UIScale.px(1))
        local curve_steps = 64
        local prev_sx, prev_sy
        for s = 0, curve_steps do
          local xa = s / curve_steps
          local ya = shape_macro_value(xa, ctype, curve)
          if assignment.inverted then ya = 1 - ya end
          local sx = pad_x + xa * pad
          local sy = pad_y + (1 - ya) * pad
          if prev_sx then
            r.ImGui_DrawList_AddLine(curve_draw, prev_sx, prev_sy, sx, sy, Theme.colors.accent, UIScale.px(1.6))
          end
          prev_sx, prev_sy = sx, sy
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

function draw_pinned_label(draw_list, size, x, y, text, text_col, outline_col, alpha)
  if alpha and alpha < 1.0 then
    local function ap(c)
      local a = c & 0xFF
      return (c & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(a * alpha + 0.5)))
    end
    text_col = ap(text_col)
    outline_col = ap(outline_col)
  end
  local o = UIScale.px(1)
  r.ImGui_DrawList_AddTextEx(draw_list, nil, size, x - o, y, outline_col, text)
  r.ImGui_DrawList_AddTextEx(draw_list, nil, size, x + o, y, outline_col, text)
  r.ImGui_DrawList_AddTextEx(draw_list, nil, size, x, y - o, outline_col, text)
  r.ImGui_DrawList_AddTextEx(draw_list, nil, size, x, y + o, outline_col, text)
  r.ImGui_DrawList_AddTextEx(draw_list, nil, size, x, y, text_col, text)
end

function param_enum_stops(track, fx_index, param_idx, entry)
  if entry and entry._enum_stops ~= nil then
    return entry._enum_stops or nil
  end
  if not track then return nil end
  if r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, fx_index) then return nil end
  local stops = nil
  if r.TrackFX_FormatParamValueNormalized then
    local N = 128
    local list, last_label, run_start = {}, nil, 0
    for i = 0, N do
      local norm = i / N
      local ok, label = r.TrackFX_FormatParamValueNormalized(track, fx_index, param_idx, norm, "")
      if not ok then list = nil break end
      label = label or ""
      if last_label == nil then
        last_label, run_start = label, norm
      elseif label ~= last_label then
        list[#list + 1] = { label = last_label, norm = (run_start + (i - 1) / N) * 0.5 }
        last_label, run_start = label, norm
        if #list > 64 then list = nil break end
      end
    end
    if list and last_label ~= nil then
      list[#list + 1] = { label = last_label, norm = (run_start + 1) * 0.5 }
    end
    if list and #list >= 2 and #list <= 64 then stops = list end
  end
  if not stops and r.TrackFX_GetParameterStepSizes then
    local ok, step = r.TrackFX_GetParameterStepSizes(track, fx_index, param_idx)
    local _, minv, maxv = r.TrackFX_GetParamEx(track, fx_index, param_idx)
    if ok and step and step > 0 and minv and maxv and maxv > minv then
      local count = math.floor((maxv - minv) / step + 0.5) + 1
      if count >= 2 and count <= 64 then
        stops = {}
        for i = 0, count - 1 do
          stops[i + 1] = { norm = (count > 1) and (i / (count - 1)) or 0 }
        end
      end
    end
  end
  if not stops and r.TrackFX_GetParamNormalized and r.TrackFX_SetParamNormalized and r.TrackFX_GetFormattedParamValue then
    local orig = r.TrackFX_GetParamNormalized(track, fx_index, param_idx)
    if orig and orig >= 0 then
      if r.PreventUIRefresh then r.PreventUIRefresh(1) end
      local N = 100
      local list, last_label, run_start = {}, nil, 0
      for i = 0, N do
        local norm = i / N
        r.TrackFX_SetParamNormalized(track, fx_index, param_idx, norm)
        local ok, label = r.TrackFX_GetFormattedParamValue(track, fx_index, param_idx, "")
        label = (ok and label) and label or ""
        if last_label == nil then
          last_label, run_start = label, norm
        elseif label ~= last_label then
          list[#list + 1] = { label = last_label, norm = (run_start + (i - 1) / N) * 0.5 }
          last_label, run_start = label, norm
          if #list > 64 then break end
        end
      end
      if #list <= 64 and last_label ~= nil then
        list[#list + 1] = { label = last_label, norm = (run_start + 1) * 0.5 }
      end
      r.TrackFX_SetParamNormalized(track, fx_index, param_idx, orig)
      if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
      if #list >= 2 and #list <= 64 then stops = list end
    end
  end
  local result = (stops and #stops >= 2 and #stops <= 64) and stops or false
  if entry then entry._enum_stops = result end
  return result or nil
end

function draw_param_cycle(app, ctx, draw_list, track, fx_index, entry, cx, cy, radius, active, stops)
  local settings = ensure_settings(app)
  local count = #stops
  local hide_value = settings.pinned_param_hide_value == true
  local prev_active = entry._cyc_active
  local prev_hover = entry._cyc_hover
  local alpha = tonumber(settings.pinned_param_alpha) or 1.0
  if alpha < 0.1 then alpha = 0.1 elseif alpha > 1.0 then alpha = 1.0 end
  local text_alpha = tonumber(settings.pinned_param_text_alpha) or 1.0
  if text_alpha < 0.1 then text_alpha = 0.1 elseif text_alpha > 1.0 then text_alpha = 1.0 end
  local function with_alpha(color)
    local a = color & 0xFF
    return (color & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(a * alpha + 0.5)))
  end
  local norm, uses_baseline = get_rack_param_value(track, fx_index, entry.param_idx)
  norm = math.max(0, math.min(1, norm or 0))
  local _, cur_label = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
  cur_label = cur_label or ""
  local idx
  for i = 1, count do
    if cur_label ~= "" and stops[i].label == cur_label then idx = i - 1 break end
  end
  if idx == nil then
    local bestd = math.huge
    for i = 1, count do
      local d = math.abs(stops[i].norm - norm)
      if d < bestd then bestd = d; idx = i - 1 end
    end
  end
  idx = idx or 0
  local function apply_idx(new_idx)
    set_rack_param_value(track, fx_index, entry.param_idx, stops[(new_idx % count) + 1].norm, uses_baseline)
  end
  local accent = 0x7AA2F7FF
  local bw = radius * 3.4
  local bh = radius * 1.7
  local x0, y0 = cx - bw * 0.5, cy - bh * 0.5
  local x1, y1 = cx + bw * 0.5, cy + bh * 0.5
  local base = active and 0x4A4A4AFF or 0x363636FF
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, with_alpha(base), UIScale.px(3))
  local frac = count > 1 and ((idx + 1) / count) or 1
  local meter = (accent & 0xFFFFFF00) | (active and 0xFF or 0xDD)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x0 + bw * frac, y1, with_alpha(meter), UIScale.px(3))
  local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
  local mode_size = UIScale.round(math.max(tonumber(settings.pinned_param_label_size) or 8, 9))
  local mode_text = truncate_to_width(ctx, (formatted and formatted ~= "") and formatted or tostring(idx + 1), bw - UIScale.px(5), mode_size)
  local show_dots = count <= 8
  local dots_h = show_dots and UIScale.px(4) or 0
  local mode_w = r.ImGui_CalcTextSize(ctx, mode_text) * (mode_size / r.ImGui_GetFontSize(ctx))
  if (not hide_value) or prev_active or prev_hover then
    draw_pinned_label(draw_list, mode_size, cx - mode_w * 0.5, cy - mode_size * 0.5 - dots_h * 0.5, mode_text, 0xF5F5F5FF, 0x000000DC, text_alpha)
  end
  if show_dots then
    local dot_r = UIScale.px(1.5)
    local spacing = dot_r * 3.2
    local dx = cx - spacing * (count - 1) * 0.5
    local dy = y1 - UIScale.px(4)
    for i = 0, count - 1 do
      r.ImGui_DrawList_AddCircleFilled(draw_list, dx + i * spacing, dy, dot_r, with_alpha(i == idx and accent or 0x666666FF), 8)
    end
  end
  local param_label_size = UIScale.round(tonumber(settings.pinned_param_label_size) or 8)
  if pinned_show_under_label(settings, entry) then
    local label = short_param_label(pinned_display_name(entry))
    local lbl_color = active and Theme.colors.text or Theme.colors.text_dim
    local lbl_w = r.ImGui_CalcTextSize(ctx, label) * (param_label_size / r.ImGui_GetFontSize(ctx))
    local lbl_outline = (luminance(lbl_color) > 0.5) and 0x000000DC or 0xFFFFFFDC
    draw_pinned_label(draw_list, param_label_size, cx - lbl_w * 0.5, y1 + UIScale.round(1) - (param_label_size - UIScale.round(8)) * 0.5, label, lbl_color, lbl_outline, text_alpha)
  end
  r.ImGui_SetCursorScreenPos(ctx, x0, y0)
  r.ImGui_InvisibleButton(ctx, "##ir_param_cycle_" .. tostring(entry.param_idx), bw, bh)
  entry._cyc_active = r.ImGui_IsItemActive(ctx)
  entry._cyc_hover = r.ImGui_IsItemHovered(ctx)
  if r.ImGui_IsItemActivated(ctx) then entry._cyc_dragged = false end
  if r.ImGui_IsItemActive(ctx) then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(dy) >= UIScale.round(10) then
      entry._cyc_dragged = true
      apply_idx(idx + (dy < 0 and 1 or -1))
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then entry._cyc_dbl = true end
  if r.ImGui_IsItemDeactivated(ctx) then
    if entry._cyc_dbl then
      entry._cyc_dbl = false
      reset_pinned_param(track, fx_index, entry, entry.param_idx)
      app.status = "Parameter reset"
    elseif not entry._cyc_dragged then
      apply_idx(idx + 1)
    end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    nudge_param_as_last_touched(track, fx_index, entry.param_idx)
    r.ImGui_OpenPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx))
  end
  if r.ImGui_BeginPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx)) then
    if draw_param_context_menu(app, ctx, track, fx_index, entry.param_idx, entry) then unpin_parameter(app, track, fx_index, entry.param_idx) end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
    local disp = pinned_display_name(entry)
    local vtext = (formatted and formatted ~= "") and formatted or tostring(idx + 1)
    local tip = (disp ~= "" and disp or "Param") .. ": " .. vtext .. string.format(" (%d/%d)", idx + 1, count)
    if settings.pinned_param_tooltip_hints ~= false then
      tip = tip .. "\nClick to cycle - drag up/down to scrub - double-click resets - right-click menu"
    end
    r.ImGui_SetTooltip(ctx, tip)
  end
end

local function draw_param_button(app, ctx, draw_list, track, fx_index, entry, cx, cy, radius, active)
  local settings = ensure_settings(app)
  local hide_value = settings.pinned_param_hide_value == true
  local prev_active = entry._btn_active
  local prev_hover = entry._btn_hover
  local alpha = tonumber(settings.pinned_param_alpha) or 1.0
  if alpha < 0.1 then alpha = 0.1 elseif alpha > 1.0 then alpha = 1.0 end
  local text_alpha = tonumber(settings.pinned_param_text_alpha) or 1.0
  if text_alpha < 0.1 then text_alpha = 0.1 elseif text_alpha > 1.0 then text_alpha = 1.0 end
  local function with_alpha(color)
    local a = color & 0xFF
    return (color & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(a * alpha + 0.5)))
  end
  local value, uses_baseline = get_rack_param_value(track, fx_index, entry.param_idx)
  value = math.max(0, math.min(1, value or 0))
  local on = value >= 0.5
  local accent = 0x7AA2F7FF
  local bw = radius * 3.4
  local bh = radius * 1.7
  local x0, y0 = cx - bw * 0.5, cy - bh * 0.5
  local x1, y1 = cx + bw * 0.5, cy + bh * 0.5
  local base_off = active and 0x4A4A4AFF or 0x363636FF
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, with_alpha(base_off), UIScale.px(3))
  if value > 0.001 then
    local meter = (accent & 0xFFFFFF00) | (active and 0xFF or 0xDD)
    r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x0 + bw * value, y1, with_alpha(meter), UIScale.px(3))
  end
  local display_mode = pinned_display_mode(settings, entry)
  local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
  local mode_size = UIScale.round(math.max(tonumber(settings.pinned_param_label_size) or 8, 9))
  local mode_text = truncate_to_width(ctx, (formatted and formatted ~= "") and formatted or (on and "On" or "Off"), bw - UIScale.px(5), mode_size)
  local mode_w = r.ImGui_CalcTextSize(ctx, mode_text) * (mode_size / r.ImGui_GetFontSize(ctx))
  if (not hide_value) or prev_active or prev_hover then
    draw_pinned_label(draw_list, mode_size, cx - mode_w * 0.5, cy - mode_size * 0.5, mode_text, 0xF5F5F5FF, 0x000000DC, text_alpha)
  end
  if pinned_show_under_label(settings, entry) then
    local label = (display_mode == "value") and mode_text or short_param_label(pinned_display_name(entry))
    local param_label_size = UIScale.round(tonumber(settings.pinned_param_label_size) or 8)
    local lbl_color = active and Theme.colors.text or Theme.colors.text_dim
    local lbl_w = r.ImGui_CalcTextSize(ctx, label) * (param_label_size / r.ImGui_GetFontSize(ctx))
    local lbl_outline = (luminance(lbl_color) > 0.5) and 0x000000DC or 0xFFFFFFDC
    draw_pinned_label(draw_list, param_label_size, cx - lbl_w * 0.5, y1 + UIScale.round(1) - (param_label_size - UIScale.round(8)) * 0.5, label, lbl_color, lbl_outline, text_alpha)
  end
  r.ImGui_SetCursorScreenPos(ctx, x0, y0)
  r.ImGui_InvisibleButton(ctx, "##ir_param_btn_" .. tostring(entry.param_idx), bw, bh)
  entry._btn_active = r.ImGui_IsItemActive(ctx)
  entry._btn_hover = r.ImGui_IsItemHovered(ctx)
  if r.ImGui_IsItemActivated(ctx) then entry._btn_dragged = false end
  if r.ImGui_IsItemActive(ctx) then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(dy) > 0 then
      entry._btn_dragged = true
      local fine = r.ImGui_GetKeyMods and r.ImGui_Mod_Shift and (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
      local next_value = math.max(0, math.min(1, value - dy * (fine and 0.001 or 0.005)))
      set_rack_param_value(track, fx_index, entry.param_idx, next_value, uses_baseline)
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then entry._btn_dbl = true end
  if r.ImGui_IsItemDeactivated(ctx) then
    if entry._btn_dbl then
      entry._btn_dbl = false
      reset_pinned_param(track, fx_index, entry, entry.param_idx)
      app.status = "Parameter reset"
    elseif not entry._btn_dragged then
      set_rack_param_value(track, fx_index, entry.param_idx, on and 0 or 1, uses_baseline)
    end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    nudge_param_as_last_touched(track, fx_index, entry.param_idx)
    r.ImGui_OpenPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx))
  end
  if r.ImGui_BeginPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx)) then
    if draw_param_context_menu(app, ctx, track, fx_index, entry.param_idx, entry) then unpin_parameter(app, track, fx_index, entry.param_idx) end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
    local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
    local disp = pinned_display_name(entry)
    local tip = (disp ~= "" and disp or "Param") .. ": " .. (formatted or string.format("%.0f%%", value * 100))
    if settings.pinned_param_tooltip_hints ~= false then
      tip = tip .. "\nDrag to change (Shift = fine) - click to toggle - double/right-click to reset"
    end
    r.ImGui_SetTooltip(ctx, tip)
  end
end

local function draw_param_knob(app, ctx, draw_list, track, fx_index, entry, cx, cy, radius, active)
  if active == nil then active = true end
  local settings = ensure_settings(app)
  local pscale = tonumber(settings.pinned_param_scale) or 1.0
  if pscale < 0.7 then pscale = 0.7 elseif pscale > 1.0 then pscale = 1.0 end
  local top = cy - radius
  radius = radius * pscale
  cy = top + radius
  local style = (entry.style and entry.style ~= "") and entry.style or (settings.pinned_param_style or "knob")
  if style == "button" then
    local stops = param_enum_stops(track, fx_index, entry.param_idx, entry)
    if stops and #stops >= 3 and #stops <= 32 then
      return draw_param_cycle(app, ctx, draw_list, track, fx_index, entry, cx, cy, radius, active, stops)
    end
    return draw_param_button(app, ctx, draw_list, track, fx_index, entry, cx, cy, radius, active)
  end
  local alpha = tonumber(settings.pinned_param_alpha) or 1.0
  if alpha < 0.1 then alpha = 0.1 elseif alpha > 1.0 then alpha = 1.0 end
  local text_alpha = tonumber(settings.pinned_param_text_alpha) or 1.0
  if text_alpha < 0.1 then text_alpha = 0.1 elseif text_alpha > 1.0 then text_alpha = 1.0 end
  local function with_alpha(color)
    local a = color & 0xFF
    return (color & 0xFFFFFF00) | math.max(0, math.min(255, math.floor(a * alpha + 0.5)))
  end
  local accent_color = nil
  local value, uses_baseline = get_rack_param_value(track, fx_index, entry.param_idx)
  local start_angle = math.pi * 0.75
  local end_angle = math.pi * 2.25
  local value_angle = start_angle + value * (end_angle - start_angle)
  local segments = radius < 8 and 12 or (radius < 14 and 18 or 24)
  local body_color = active and 0x555555FF or 0x3C3C3CFF
  local arc_color = active and (accent_color or 0xCCCCCCFF) or 0x808080FF
  local cap_color = active and (accent_color or 0xCCCCCCFF) or 0x808080FF
  local label_color = active and Theme.colors.text or Theme.colors.text_dim
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx + UIScale.px(1), cy + UIScale.px(1), radius, with_alpha(0x00000066), segments)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, with_alpha(body_color), segments)
  if value > 0.01 then
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius - UIScale.px(2), start_angle, value_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, with_alpha(arc_color), 0, UIScale.px(2.5))
  end
  if value < 0.02 then
    local line_x = cx + math.cos(value_angle) * radius * 0.85
    local line_y = cy + math.sin(value_angle) * radius * 0.85
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, line_x, line_y, with_alpha(arc_color), UIScale.px(2))
  end
  if active and uses_baseline then
    local mod_value = r.TrackFX_GetParamNormalized(track, fx_index, entry.param_idx)
    mod_value = math.max(0, math.min(1, mod_value or 0))
    local mod_angle = start_angle + mod_value * (end_angle - start_angle)
    local outer_r = radius + UIScale.px(2)
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, outer_r, start_angle, end_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, with_alpha(0x7AA2F744), 0, UIScale.px(1.5))
    if mod_value > 0.001 then
      r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, outer_r, start_angle, mod_angle, segments)
      r.ImGui_DrawList_PathStroke(draw_list, with_alpha(0x7AA2F7FF), 0, UIScale.px(1.8))
    end
  end
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius * 0.45, with_alpha(cap_color), segments)
  if pinned_show_under_label(settings, entry) then
    local display_mode = pinned_display_mode(settings, entry)
    local label
    if display_mode == "value" then
      local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
      label = short_param_label((formatted and formatted ~= "") and formatted or string.format("%.0f%%", value * 100))
    else
      label = short_param_label(pinned_display_name(entry))
    end
    local param_label_size = UIScale.round(tonumber(settings.pinned_param_label_size) or 8)
    local text_w = r.ImGui_CalcTextSize(ctx, label) * (param_label_size / r.ImGui_GetFontSize(ctx))
    local label_x = cx - text_w * 0.5
    local label_y = cy + radius + UIScale.round(1) - (param_label_size - UIScale.round(8)) * 0.5
    local label_outline = (luminance(label_color) > 0.5) and 0x000000DC or 0xFFFFFFDC
    draw_pinned_label(draw_list, param_label_size, label_x, label_y, label, label_color, label_outline, text_alpha)
  end
  r.ImGui_SetCursorScreenPos(ctx, cx - radius - UIScale.round(4), cy - radius - UIScale.round(4))
  r.ImGui_InvisibleButton(ctx, "##ir_param_knob_" .. tostring(entry.param_idx), (radius + UIScale.round(4)) * 2, (radius + UIScale.round(4)) * 2)
  if r.ImGui_IsItemActive(ctx) then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(dy) > 0 then
      local fine = r.ImGui_GetKeyMods and r.ImGui_Mod_Shift and (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
      local next_value = math.max(0, math.min(1, value - dy * (fine and 0.001 or 0.005)))
      set_rack_param_value(track, fx_index, entry.param_idx, next_value, uses_baseline)
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    reset_pinned_param(track, fx_index, entry, entry.param_idx)
    app.status = "Parameter reset"
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    nudge_param_as_last_touched(track, fx_index, entry.param_idx)
    r.ImGui_OpenPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx))
  end
  if r.ImGui_BeginPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx)) then
    if draw_param_context_menu(app, ctx, track, fx_index, entry.param_idx, entry) then unpin_parameter(app, track, fx_index, entry.param_idx) end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
    local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
    local prefix = uses_baseline and "Baseline: " or ""
    local disp = pinned_display_name(entry)
    local tip = (disp ~= "" and disp or "Param") .. ": " .. prefix .. (formatted or string.format("%.0f%%", value * 100))
    if settings.pinned_param_tooltip_hints ~= false then
      tip = tip .. "\nDrag to change (Shift = fine)"
    end
    r.ImGui_SetTooltip(ctx, tip)
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

local function draw_param_slots(app, ctx, track, fx_index, item_width, active)
  if active == nil then active = true end
  local settings = ensure_settings(app)
  local slot_count = param_slot_count(settings)
  local cols = param_slot_columns(settings)
  local rows = param_slot_rows(settings)
  local row_width = math.max(1, item_width)
  local label_extra = math.max(0, UIScale.round(tonumber(settings.pinned_param_label_size) or 8) - UIScale.round(8))
  local row_step = UIScale.round(44) + label_extra
  local row_height = param_slots_height(settings)
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
  for divider = 1, rows - 1 do
    local dy = y + divider * row_step + UIScale.round(3)
    r.ImGui_DrawList_AddLine(draw_list, x + UIScale.round(4), dy, x + row_width - UIScale.round(4), dy, 0x3D4450AA, UIScale.px(1))
  end
  for slot = 1, slot_count do
    local row = math.floor((slot - 1) / cols)
    local column = ((slot - 1) % cols) + 1
    local cell_width = row_width / cols
    local cx = x + (column - 0.5) * cell_width
    local cy = y + UIScale.round(23) + row * row_step
    local knob_radius = UIScale.round(12)
    local entry = pinned_by_slot[slot]
    if entry then
      draw_param_knob(app, ctx, draw_list, track, fx_index, entry, cx, cy, knob_radius, active)
    else
      draw_empty_param_slot(app, ctx, draw_list, track, fx_index, cx, cy, knob_radius, slot)
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

local function find_sibling_context(chain, api)
  chain = as_chain(chain)
  if not api then return nil end
  local top_count = c_count(chain)
  if api < CONTAINER_BASE then
    if api < 0 or api >= top_count then return nil end
    local list = {}
    for i = 0, top_count - 1 do list[#list + 1] = i end
    return { siblings = list, index = api + 1, container_rel = nil }
  end
  local function recurse(container_rel, parent_count, parent_diff)
    local count = math.floor(tonumber(cfg(chain, CONTAINER_BASE + container_rel, "container_count")) or 0)
    if count <= 0 then return nil end
    local diff = (parent_count + 1) * parent_diff
    local list = {}
    for j = 1, count do list[j] = CONTAINER_BASE + container_rel + diff * j end
    for idx = 1, count do
      if list[idx] == api then
        return { siblings = list, index = idx, container_rel = container_rel, count = count, diff = diff }
      end
    end
    for j = 1, count do
      local child_rel = container_rel + diff * j
      if c_is_container(chain, CONTAINER_BASE + child_rel) then
        local res = recurse(child_rel, count, diff)
        if res then return res end
      end
    end
    return nil
  end
  for i = 0, top_count - 1 do
    if c_is_container(chain, i) then
      local res = recurse(i + 1, top_count, 1)
      if res then return res end
    end
  end
  return nil
end

local function resolve_track_move_dest(chain, src_full, dest_index)
  chain = as_chain(chain)
  local dctx = find_sibling_context(chain, dest_index)
  local sctx = find_sibling_context(chain, src_full)
  if dctx and sctx and dctx.container_rel == sctx.container_rel and sctx.index and dctx.index and sctx.index < dctx.index then
    local next_api = dctx.siblings[dctx.index + 1]
    if next_api then return next_api end
    if dctx.container_rel then
      return CONTAINER_BASE + dctx.container_rel + dctx.diff * (dctx.count + 1)
    end
    return c_count(chain) or dest_index
  end
  return dest_index
end

local function container_descendant_apis(chain, container_api, acc)
  chain = as_chain(chain)
  acc = acc or {}
  if not c_is_container(chain, container_api) then return acc end
  local top_count = c_count(chain)
  local container_rel
  local parent_count, parent_diff
  if container_api < CONTAINER_BASE then
    container_rel = container_api + 1
    parent_count = top_count
    parent_diff = 1
  else
    local sctx = find_sibling_context(chain, container_api)
    if not sctx then return acc end
    container_rel = container_api - CONTAINER_BASE
    parent_count = sctx.count or top_count
    parent_diff = sctx.diff or 1
  end
  local count = math.floor(tonumber(cfg(chain, CONTAINER_BASE + container_rel, "container_count")) or 0)
  if count <= 0 then return acc end
  local diff = (parent_count + 1) * parent_diff
  for j = 1, count do
    local child_api = CONTAINER_BASE + container_rel + diff * j
    acc[child_api] = true
    if c_is_container(chain, child_api) then container_descendant_apis(chain, child_api, acc) end
  end
  return acc
end

local function move_fx_into_container(app, chain, src_chain, src_index, container_api, short_name)
  chain = as_chain(chain)
  if not chain_valid(chain) or not c_move_capable(chain) then return end
  if not c_is_container(chain, container_api) then return end
  local want = chain.kind == "item" and "item" or "track"
  if src_chain ~= want then
    app.status = want == "item" and "Only item FX can be dropped into this container" or "Only track FX can be dropped into a container"
    return
  end
  local src_full = math.floor(tonumber(src_index) or -1)
  if src_full < 0 then return end
  if src_full == container_api then return end
  local descendants = container_descendant_apis(chain, container_api)
  if descendants[src_full] then
    app.status = "Cannot drop a container into itself"
    return
  end
  local dest = container_end_insert_index(chain, container_api)
  if not dest then
    app.status = "Could not calculate container insert position"
    return
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  cfg_set(chain, src_full, "parallel", "0")
  local ok = c_move(chain, src_full, dest) ~= false
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Move FX into container", -1)
  app.status = ok and ("Moved " .. (short_name or "FX") .. " into container") or "FX could not be moved"
end

function add_external_fx_into_container(app, chain, container_api, payload)
  chain = as_chain(chain)
  if not chain_valid(chain) or not c_add_capable(chain) then return end
  if not c_is_container(chain, container_api) then return end
  local names = {}
  for name in (payload or ""):gmatch("[^\n]+") do
    if name ~= "" then names[#names + 1] = name end
  end
  if #names == 0 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, name in ipairs(names) do
    local insert_index = container_end_insert_index(chain, container_api)
    if insert_index then c_add(chain, name, insert_index) end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX into container", -1)
  r.SetExtState("TKFXB", "drag_consumed", "1", false)
  r.DeleteExtState("TKFXB", "drag_fx", false)
  if r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
  app.status = "Added " .. tostring(#names) .. " FX into container"
end

local function container_direct_children(chain, container_api)
  chain = as_chain(chain)
  local children = {}
  if not c_is_container(chain, container_api) then return children end
  local top_count = c_count(chain)
  local container_rel, parent_count, parent_diff
  if container_api < CONTAINER_BASE then
    container_rel = container_api + 1
    parent_count = top_count
    parent_diff = 1
  else
    local sctx = find_sibling_context(chain, container_api)
    if not sctx then return children end
    container_rel = container_api - CONTAINER_BASE
    parent_count = sctx.count or top_count
    parent_diff = sctx.diff or 1
  end
  local count = math.floor(tonumber(cfg(chain, CONTAINER_BASE + container_rel, "container_count")) or 0)
  if count <= 0 then return children end
  local diff = (parent_count + 1) * parent_diff
  for j = 1, count do
    children[#children + 1] = CONTAINER_BASE + container_rel + diff * j
  end
  return children
end

local function find_track_fx_api_by_guid(chain, guid)
  chain = as_chain(chain)
  if not guid or guid == "" then return nil end
  local top_count = c_count(chain)
  local function recurse(container_rel, parent_count, parent_diff)
    local count = math.floor(tonumber(cfg(chain, CONTAINER_BASE + container_rel, "container_count")) or 0)
    if count <= 0 then return nil end
    local diff = (parent_count + 1) * parent_diff
    for j = 1, count do
      local child_rel = container_rel + diff * j
      local child_api = CONTAINER_BASE + child_rel
      if c_guid(chain, child_api) == guid then return child_api end
      if c_is_container(chain, child_api) then
        local res = recurse(child_rel, count, diff)
        if res then return res end
      end
    end
    return nil
  end
  for i = 0, top_count - 1 do
    if c_guid(chain, i) == guid then return i end
    if c_is_container(chain, i) then
      local res = recurse(i + 1, top_count, 1)
      if res then return res end
    end
  end
  return nil
end

function wrap_nested_fx_in_container(app, chain, source_api_id)
  chain = as_chain(chain)
  if not chain_valid(chain) then return end
  if not (c_add_capable(chain) and c_move_capable(chain)) then return end
  local sctx = find_sibling_context(chain, source_api_id)
  if not sctx or not sctx.container_rel then
    app.status = "Could not resolve parent container"
    return
  end
  local top_count = c_count(chain)
  local parent_api
  if sctx.container_rel <= top_count then
    parent_api = sctx.container_rel - 1
  else
    parent_api = CONTAINER_BASE + sctx.container_rel
  end
  local source_guid = c_guid(chain, source_api_id)
  local source_parallel = cfg(chain, source_api_id, "parallel") or "0"
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok = false
  local fail_reason = nil
  local insert_index = container_end_insert_index(chain, parent_api)
  if insert_index then
    local new_container_api = c_add(chain, "Container", insert_index)
    if new_container_api and new_container_api >= 0 then
      local children = container_direct_children(chain, parent_api)
      local container_api2 = children[#children] or new_container_api
      cfg_set(chain, container_api2, "parallel", source_parallel)
      local src_api = find_track_fx_api_by_guid(chain, source_guid) or source_api_id
      local dest = container_end_insert_index(chain, container_api2)
      if dest then
        cfg_set(chain, src_api, "parallel", "0")
        ok = c_move(chain, src_api, dest) ~= false
        if not ok then fail_reason = "move failed" end
      else
        fail_reason = "no dest index"
      end
    else
      fail_reason = "container add failed"
    end
  else
    fail_reason = "no parent insert index"
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Wrap FX in container", -1)
  app.status = ok and "Wrapped FX in container" or ("FX could not be wrapped (" .. tostring(fail_reason) .. ")")
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
    elseif dest_chain == "input" then
      local d = dest_index
      if src_chain == dest_chain and src_index < dest_index then d = dest_index + 1 end
      dest_full = chain_full_index(dest_chain, d)
    else
      dest_full = resolve_track_move_dest(track, src_full, dest_index)
    end
    if (src_full >= CONTAINER_BASE or dest_full >= CONTAINER_BASE) and r.TrackFX_SetNamedConfigParm then
      r.TrackFX_SetNamedConfigParm(track, src_full, "parallel", "0")
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
  local param_h = param_slots_height(settings)
  local row1_h = UIScale.round(18)
  local toolbar_h = UIScale.round(20)
  return row1_h + toolbar_h + UIScale.round(2) + shot_h + param_h + UIScale.round(4)
end

local function tile_mod_action(ctx)
  if not (r.ImGui_GetKeyMods and r.ImGui_Mod_Alt) then return nil end
  local mods = r.ImGui_GetKeyMods(ctx)
  if (mods & r.ImGui_Mod_Alt()) ~= 0 then return "delete" end
  local shift = (mods & r.ImGui_Mod_Shift()) ~= 0
  local ctrl = (mods & r.ImGui_Mod_Ctrl()) ~= 0
  if shift and ctrl then return "offline" end
  if shift then return "bypass" end
  return nil
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
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + strip_w, by + th, opts.enabled and (opts.is_instrument and Theme.colors.accent or Theme.colors.border) or Theme.colors.danger, UIScale.px(3), 0, opts.is_instrument and UIScale.px(2) or UIScale.px(1))
    if opts.is_instrument then
      r.ImGui_DrawList_AddRectFilled(draw_list, bx + UIScale.px(1), by + UIScale.px(1), bx + UIScale.px(4), by + th - UIScale.px(1), Theme.colors.accent, UIScale.px(2))
    end
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
    if r.ImGui_InvisibleButton(ctx, "##ir_strip_btn", strip_w, th) then
      if not (opts.mod_action and opts.mod_action()) then state.collapsed[opts.collapse_key] = false end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, label .. " — click to expand (Alt-click delete, Shift bypass, Ctrl+Shift offline)") end
    local d = opts.drag
    handle_fx_drag(app, ctx, draw_list, d.track, d.take, d.chain, d.local_index, label, bx, by, strip_w, th)
    r.ImGui_EndChild(ctx)
  end
end

local function draw_fx_tile(app, ctx, settings, track, fx_index, item_width, chain, take, opts)
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local enabled = r.TrackFX_GetEnabled(track, fx_index)
  local offline = r.TrackFX_GetOffline(track, fx_index)
  local short_name = get_fx_short_name(fx_name)
  local is_instrument = settings.distinguish_instruments ~= false and fx_name_is_instrument(fx_name)
  chain = chain or "track"
  local local_index = chain == "input" and (fx_index - REC_FX_OFFSET) or fx_index
  local function apply_tile_mod()
    local action = tile_mod_action(ctx)
    if action == "delete" then
      delete_fx(app, track, fx_index, fx_name)
    elseif action == "bypass" then
      r.TrackFX_SetEnabled(track, fx_index, not enabled)
      app.status = (enabled and "Bypassed " or "Enabled ") .. short_name
    elseif action == "offline" then
      r.TrackFX_SetOffline(track, fx_index, not offline)
      app.status = (offline and "Brought online " or "Set offline ") .. short_name
    else
      return false
    end
    return true
  end
  r.ImGui_PushID(ctx, "ir_fx_" .. tostring(fx_index))
  local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local nested_scale = opts and opts.nested == true
  local scale_y = tonumber(opts and opts.scale_y) or 1
  if scale_y < 0.55 then scale_y = 0.55 end
  if scale_y > 1.0 then scale_y = 1.0 end
  local shot_h = settings.show_screenshots and not settings.tile_compact and UIScale.round(settings.screenshot_height or 90) or 0
  local param_h = param_slots_height(settings)
  local row1_h = UIScale.round(18)
  local toolbar_h = UIScale.round(20)
  if nested_scale then
    if shot_h > 0 then shot_h = math.max(UIScale.round(34), UIScale.round(shot_h * scale_y)) end
    if param_h > 0 then param_h = math.max(UIScale.round(30), UIScale.round(param_h * scale_y)) end
    row1_h = math.max(UIScale.round(14), UIScale.round(row1_h * scale_y))
    toolbar_h = math.max(UIScale.round(14), UIScale.round(toolbar_h * scale_y))
  end
  local collapse_key = track_guid(track) .. "|" .. get_fx_guid(track, fx_index)
  if settings.auto_apply_default_pins and not state.auto_pin_checked[collapse_key] then
    state.auto_pin_checked[collapse_key] = true
    if #get_pinned_for_fx(track, fx_index) == 0 or settings.restore_default_pin_values then apply_default_pins(app, track, fx_index, true) end
  end
  local is_collapsed = state.collapsed[collapse_key] == true
  if settings.orientation == "horizontal" and is_collapsed then
    local collapsed_h = nested_scale and math.max(UIScale.round(72), UIScale.round(expanded_tile_height(settings) * scale_y)) or expanded_tile_height(settings)
    draw_collapsed_tile_strip(app, ctx, settings, {
      id = "##ir_fx_tile",
      label = short_name,
      enabled = enabled,
      is_instrument = is_instrument,
      collapse_key = collapse_key,
      height = collapsed_h,
      drag = { track = track, take = take, chain = chain, local_index = local_index },
      mod_action = apply_tile_mod
    })
    r.ImGui_PopID(ctx)
    return
  end
  local title_h = row1_h + toolbar_h + UIScale.round(2)
  local tile_h = is_collapsed and title_h or (title_h + shot_h + param_h + UIScale.round(4))
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  local tile_visible = r.ImGui_BeginChild(ctx, "##ir_fx_tile", item_width, tile_h, 0, flags)
  r.ImGui_PopStyleVar(ctx, 1)
  if tile_visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + item_width, by + tile_h, Theme.colors.frame_bg, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + item_width, by + tile_h, enabled and (is_instrument and Theme.colors.accent or Theme.colors.border) or Theme.colors.danger, UIScale.px(3), 0, is_instrument and UIScale.px(2) or UIScale.px(1))
    if is_instrument then
      r.ImGui_DrawList_AddRectFilled(draw_list, bx + UIScale.px(1), by + UIScale.px(1), bx + UIScale.px(4), by + tile_h - UIScale.px(1), Theme.colors.accent, UIScale.px(2))
    end

    local delete_x = bx + item_width - UIScale.round(10)
    local delete_y = by + row1_h * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, delete_x, delete_y, UIScale.px(4), 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, delete_x - UIScale.round(6), delete_y - UIScale.round(6))
    r.ImGui_InvisibleButton(ctx, "##ir_fx_delete", UIScale.round(12), UIScale.round(12))
    if r.ImGui_IsItemClicked(ctx, 0) then
      if tile_mod_action(ctx) == "delete" then delete_fx(app, track, fx_index, fx_name) else r.ImGui_OpenPopup(ctx, "##ir_delete_pop") end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete FX (Alt-click to delete instantly)") end

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

    local wet_scale = tonumber(settings.wet_knob_scale) or 1.0
    if wet_scale < 0.7 then wet_scale = 0.7 elseif wet_scale > 1.0 then wet_scale = 1.0 end
    local knob_radius = math.max(UIScale.round(9), UIScale.round(13 * wet_scale))
    local knob_cx = bx + UIScale.round(5) + knob_radius
    local knob_cy = by + math.floor(title_h * 0.5)
    local content_x = knob_cx + knob_radius + UIScale.round(6)
    draw_wet_knob(app, ctx, draw_list, track, fx_index, knob_cx, knob_cy, knob_radius)

    local name_max_w = math.max(UIScale.round(20), chev_x - content_x - UIScale.round(4))
    local name_tx = content_x
    if settings.fx_name_center then
      local nw = r.ImGui_CalcTextSize(ctx, short_name)
      name_tx = content_x + math.max(0, (name_max_w - nw) * 0.5)
    end
    r.ImGui_DrawList_PushClipRect(draw_list, content_x, by, content_x + name_max_w, by + row1_h, true)
    r.ImGui_DrawList_AddText(draw_list, name_tx, by + UIScale.round(2), enabled and Theme.colors.text or Theme.colors.text_dim, short_name)
    r.ImGui_DrawList_PopClipRect(draw_list)

    local button_y = by + row1_h + UIScale.round(2)
    local tx = content_x
    do
      local ab_key = fx_ab_key(track, fx_index)
      local ab_side = state.fx_ab_current[ab_key]
      local ab_has = fx_ab_has_data(track, fx_index)
      local ab_bg = ab_has and ((ab_side == "b") and 0x4488CCFF or 0x44CC44FF) or 0x33333388
      local ab_label = ab_has and (ab_side == "b" and "a|B" or "A|b") or "A|B"
      local ab_tip = ab_has and "A/B: click to recall other side (right-click to capture/reset)" or "A/B: click to capture initial snapshot (right-click for menu)"
      local ab_clicked, ab_right = draw_small_button(ctx, draw_list, "##ir_fx_ab", tx, button_y, UIScale.round(20), UIScale.round(14), ab_label, ab_bg, 0xFFFFFFFF, ab_tip)
      if ab_clicked then fx_ab_toggle(app, track, fx_index) end
      if ab_right then r.ImGui_OpenPopup(ctx, "##ir_fx_ab_pop") end
      if r.ImGui_BeginPopup(ctx, "##ir_fx_ab_pop") then
        if r.ImGui_MenuItem(ctx, "Copy current to A") then fx_ab_copy_to(app, track, fx_index, "a") end
        if r.ImGui_MenuItem(ctx, "Copy current to B") then fx_ab_copy_to(app, track, fx_index, "b") end
        if r.ImGui_MenuItem(ctx, "Reset A/B", nil, false, fx_ab_has_data(track, fx_index)) then fx_ab_reset(app, track, fx_index) end
        r.ImGui_EndPopup(ctx)
      end
    end
    tx = tx + UIScale.round(24)
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

    if not is_collapsed then
      local sep_y = by + title_h - 1
      r.ImGui_DrawList_AddLine(draw_list, bx + UIScale.round(4), sep_y, bx + item_width - UIScale.round(4), sep_y, Theme.colors.separator, UIScale.px(1))

      if settings.show_screenshots and not settings.tile_compact then
        r.ImGui_SetCursorScreenPos(ctx, bx + UIScale.round(2), by + title_h)
        draw_fx_screenshot(ctx, settings, fx_name, item_width - UIScale.round(4), shot_h, enabled and not offline)
        if r.ImGui_IsItemClicked(ctx, 0) then
          if not apply_tile_mod() then
            local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
            r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
          end
        end
        if settings.show_type_badge then
          draw_fx_type_badge(ctx, draw_list, fx_name, bx + item_width - UIScale.round(2), by + title_h)
        end
        handle_fx_drag(app, ctx, draw_list, track, take, chain, local_index, short_name, bx, by, item_width, tile_h)
      end
      if settings.show_pinned_params then
        r.ImGui_SetCursorScreenPos(ctx, bx + UIScale.round(7), by + title_h + shot_h + UIScale.round(4))
        draw_param_slots(app, ctx, track, fx_index, item_width - UIScale.round(14), enabled and not offline)
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

    r.ImGui_SetCursorScreenPos(ctx, content_x, by)
    if r.ImGui_InvisibleButton(ctx, "##ir_fx_title_hit", math.max(1, name_max_w), row1_h) then
      if not apply_tile_mod() then
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
        r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
      end
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
      if r.SNM_AddTCPFXParm and r.CountTCPFXParms then
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Sync this FX's TCP/MCP params to pins") then sync_tcp_params(app, track, fx_index) end
      end
      r.ImGui_Separator(ctx)
      local fx_parallel = (fx_config_value(track, fx_index, "parallel") or "0") ~= "0"
      if r.ImGui_MenuItem(ctx, "Parallel", nil, fx_parallel) then toggle_fx_parallel(app, track, fx_index) end
      if r.ImGui_MenuItem(ctx, "Wrap in container") then wrap_fx_in_container(app, track, fx_index) end
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

local function global_mouse_pos(ctx)
  if r.GetMousePosition and r.ImGui_PointConvertNative then
    local sx, sy = r.GetMousePosition()
    return r.ImGui_PointConvertNative(ctx, sx, sy)
  end
  return r.ImGui_GetMousePos(ctx)
end

local function update_external_drag(ctx)
  local external_drag = r.GetExtState("TKFXB", "drag_fx")
  local mouse_down, mouse_released = mouse_release_state(ctx)
  if external_drag ~= "" then
    if not state.last_external_drag then
      if r.GetExtState("TKFXB", "drag_consumed") == "1" then r.DeleteExtState("TKFXB", "drag_consumed", false) end
      if r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
    end
    state.last_external_drag = external_drag
  elseif not mouse_down and not mouse_released then
    if state.last_external_drag and r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
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
  local quick_enabled = settings.quick_add_enabled ~= false
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
  local function do_quick_open()
    if drop_only or not quick_enabled then return end
    quick_open_popup(track, target_type, take, insert_index, nil, nil)
  end
  local function do_drop(p)
    if target_type == "input" then add_external_input_fx(app, track, p)
    elseif target_type == "item" then add_external_take_fx(app, take, p)
    else add_external_fx(app, track, p, insert_index) end
  end
  local add_menu_id = "##ir_add_menu_" .. target_type
  local function add_zone_menu()
    if target_type ~= "track" then return end
    if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, add_menu_id) end
    if r.ImGui_BeginPopup(ctx, add_menu_id) then
      if r.ImGui_MenuItem(ctx, "Add FX...") then do_open() end
      if quick_enabled and r.ImGui_MenuItem(ctx, "Quick Add...") then do_quick_open() end
      if r.ImGui_MenuItem(ctx, "Add empty container") then add_empty_container(app, track, insert_index) end
      r.ImGui_EndPopup(ctx)
    end
  end
  if horizontal then
    local size = UIScale.round(30)
    local gap = UIScale.round(6)
    local stack_h = quick_enabled and (size * 2 + gap) or size
    local tile_h = expanded_tile_height(settings)
    x, y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_InvisibleButton(ctx, "##ir_add_zone_" .. target_type, size, tile_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local clicked = r.ImGui_IsItemClicked(ctx, 0)
    local mx, my = r.ImGui_GetMousePos(ctx)
    local accent = payload ~= ""
    local color = accent and Theme.colors.accent or (hovered and Theme.colors.frame_hover or add_zone_visible_color())
    local cx = x + size * 0.5
    local cy = y + (tile_h - stack_h) * 0.5 + size * 0.5
    local radius = size * 0.5 - UIScale.px(2)
    local quick_cx, quick_cy = cx, cy + size + gap
    local quick_r = radius
    local add_hovered = (mx >= cx - radius and mx <= cx + radius and my >= cy - radius and my <= cy + radius)
    local quick_hovered = quick_enabled and (mx >= quick_cx - quick_r and mx <= quick_cx + quick_r and my >= quick_cy - quick_r and my <= quick_cy + quick_r)
    local add_col = add_hovered and Theme.colors.accent or color
    local show_add_border = settings.add_zone_border ~= false
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, hovered and Theme.colors.frame_bg or Theme.colors.child_bg, 0)
    if show_add_border or accent or add_hovered then
      r.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, add_col, 0, accent and UIScale.px(2) or UIScale.px(1.5))
    end
    local arm = radius * 0.5
    r.ImGui_DrawList_AddLine(draw_list, cx - arm, cy, cx + arm, cy, add_col, UIScale.px(2))
    r.ImGui_DrawList_AddLine(draw_list, cx, cy - arm, cx, cy + arm, add_col, UIScale.px(2))
    if quick_enabled then
      local quick_col = quick_hovered and Theme.colors.accent or color
      r.ImGui_DrawList_AddCircleFilled(draw_list, quick_cx, quick_cy, quick_r, hovered and Theme.colors.frame_bg or Theme.colors.child_bg, 0)
      if show_add_border or accent or quick_hovered then
        r.ImGui_DrawList_AddCircle(draw_list, quick_cx, quick_cy, quick_r, quick_col, 0, UIScale.px(1.5))
      end
      local q_w = r.ImGui_CalcTextSize(ctx, "Q")
      r.ImGui_DrawList_AddText(draw_list, quick_cx - q_w * 0.5, quick_cy - r.ImGui_GetTextLineHeight(ctx) * 0.5, quick_col, "Q")
    end
    if clicked then
      if quick_hovered then do_quick_open() else do_open() end
    end
    add_zone_menu()
    local zone_hovered = hovered
    if payload ~= "" then
      local gmx, gmy = global_mouse_pos(ctx)
      zone_hovered = (gmx >= x and gmx <= x + size and gmy >= y and gmy <= y + tile_h)
    end
    if zone_hovered and payload ~= "" then
      local guid = track_guid(track)
      if state.mouse_released then
        if r.HasExtState("TKFXB", "drag_fx") and (target_type ~= "track" or r.HasExtState("TKMIX", "rack_target")) then do_drop(payload) end
      elseif target_type == "track" and guid ~= "" then
        r.SetExtState("TKMIX", "rack_target", guid .. "|" .. tostring(insert_index or -1), false)
      end
    end
    if hovered then
      if quick_hovered then
        r.ImGui_SetTooltip(ctx, "Quick Add (cascading menu)")
      else
        r.ImGui_SetTooltip(ctx, payload ~= "" and "Drop FX here" or add_tip)
      end
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
  local label = payload ~= "" and "+ Drop" or (target_type == "input" and "+ Input" or target_type == "item" and "+ Item" or "+ Add")
  local add_h = UIScale.round(32)
  r.ImGui_InvisibleButton(ctx, "##ir_add_zone_" .. target_type, item_width, add_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local border = payload ~= "" and Theme.colors.accent or (hovered and Theme.colors.frame_hover or add_zone_visible_color())
  local btn_bg = hovered and Theme.colors.frame_bg or Theme.colors.child_bg
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + item_width, y + add_h, btn_bg, UIScale.px(4))
  local quick_w = quick_enabled and UIScale.round(64) or 0
  local quick_gap = quick_enabled and UIScale.round(6) or 0
  local main_w = item_width - quick_w - quick_gap
  local show_add_border = settings.add_zone_border ~= false
  if show_add_border or payload ~= "" or hovered then
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + main_w, y + add_h, border, UIScale.px(4), 0, payload ~= "" and UIScale.px(2) or UIScale.px(1))
  end
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(draw_list, x + (main_w - text_w) * 0.5, y + UIScale.round(10), payload ~= "" and Theme.colors.accent or add_zone_visible_color(), label)
  local quick_hovered = false
  if quick_enabled then
    local qx0 = x + main_w + quick_gap
    local qx1 = qx0 + quick_w
    local qy0 = y
    local qy1 = y + add_h
    quick_hovered = mx >= qx0 and mx <= qx1 and my >= qy0 and my <= qy1
    local q_border = quick_hovered and Theme.colors.accent or add_zone_visible_color()
    local q_bg = quick_hovered and Theme.colors.frame_bg or Theme.colors.child_bg
    r.ImGui_DrawList_AddRectFilled(draw_list, qx0, qy0, qx1, qy1, q_bg, UIScale.px(4))
    if show_add_border or payload ~= "" or quick_hovered then
      r.ImGui_DrawList_AddRect(draw_list, qx0, qy0, qx1, qy1, q_border, UIScale.px(4), 0, UIScale.px(1))
    end
    local q_w = r.ImGui_CalcTextSize(ctx, "Quick")
    local q_col = quick_hovered and Theme.colors.accent or add_zone_visible_color()
    r.ImGui_DrawList_AddText(draw_list, qx0 + (quick_w - q_w) * 0.5, y + UIScale.round(10), q_col, "Quick")
  end
  if clicked then
    if quick_hovered then do_quick_open() else do_open() end
  end
  add_zone_menu()
  local zone_hovered = hovered
  if payload ~= "" then
    local gmx, gmy = global_mouse_pos(ctx)
    zone_hovered = (gmx >= x and gmx <= x + item_width and gmy >= y and gmy <= y + add_h)
  end
  if zone_hovered and payload ~= "" then
    local guid = track_guid(track)
    if state.mouse_released then
      if r.HasExtState("TKFXB", "drag_fx") and (target_type ~= "track" or r.HasExtState("TKMIX", "rack_target")) then do_drop(payload) end
    elseif target_type == "track" and guid ~= "" then
      r.SetExtState("TKMIX", "rack_target", guid .. "|" .. tostring(insert_index or -1), false)
    end
  end
  if hovered then
    if quick_hovered then
      r.ImGui_SetTooltip(ctx, "Quick Add (cascading menu)")
    else
      r.ImGui_SetTooltip(ctx, payload ~= "" and "Drop FX here" or add_tip)
    end
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

function take_fx_enabled(take, fx_index)
  if r.TakeFX_GetEnabled then return r.TakeFX_GetEnabled(take, fx_index) end
  return true
end

function take_fx_offline(take, fx_index)
  if r.TakeFX_GetOffline then return r.TakeFX_GetOffline(take, fx_index) end
  return false
end

function set_take_fx_enabled(take, fx_index, enabled)
  if r.TakeFX_SetEnabled then r.TakeFX_SetEnabled(take, fx_index, enabled) end
end

function set_take_fx_offline(take, fx_index, offline)
  if r.TakeFX_SetOffline then r.TakeFX_SetOffline(take, fx_index, offline) end
end

function show_take_fx(take, fx_index)
  if not r.TakeFX_Show then return end
  local hwnd = r.TakeFX_GetFloatingWindow and r.TakeFX_GetFloatingWindow(take, fx_index) or nil
  r.TakeFX_Show(take, fx_index, hwnd and 2 or 3)
end

function delete_take_fx(app, take, fx_index, fx_name)
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
  local is_instrument = settings.distinguish_instruments ~= false and fx_name_is_instrument(fx_name)
  local function apply_tile_mod()
    local action = tile_mod_action(ctx)
    if action == "delete" then
      delete_take_fx(app, take, fx_index, fx_name)
    elseif action == "bypass" then
      set_take_fx_enabled(take, fx_index, not enabled)
      app.status = (enabled and "Bypassed " or "Enabled ") .. short_name
    elseif action == "offline" then
      set_take_fx_offline(take, fx_index, not offline)
      app.status = (offline and "Brought online " or "Set offline ") .. short_name
    else
      return false
    end
    return true
  end
  r.ImGui_PushID(ctx, "ir_take_fx_" .. tostring(fx_index))
  local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local shot_h = settings.show_screenshots and not settings.tile_compact and UIScale.round(settings.screenshot_height or 90) or 0
  local param_h = param_slots_height(settings)
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
      is_instrument = is_instrument,
      collapse_key = collapse_key,
      height = row1_h + toolbar_h + shot_h + UIScale.round(6),
      drag = { track = track, take = take, chain = "item", local_index = fx_index },
      mod_action = apply_tile_mod
    })
    r.ImGui_PopID(ctx)
    return
  end
  local tile_h = is_collapsed and row1_h or (row1_h + toolbar_h + shot_h + param_h + UIScale.round(6))
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  local tile_visible = r.ImGui_BeginChild(ctx, "##ir_take_fx_tile", item_width, tile_h, 0, flags)
  r.ImGui_PopStyleVar(ctx, 1)
  if tile_visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + item_width, by + tile_h, Theme.colors.frame_bg, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + item_width, by + tile_h, enabled and (is_instrument and Theme.colors.accent or Theme.colors.border) or Theme.colors.danger, UIScale.px(3), 0, is_instrument and UIScale.px(2) or UIScale.px(1))
    if is_instrument then
      r.ImGui_DrawList_AddRectFilled(draw_list, bx + UIScale.px(1), by + UIScale.px(1), bx + UIScale.px(4), by + tile_h - UIScale.px(1), Theme.colors.accent, UIScale.px(2))
    end

    local delete_x = bx + item_width - UIScale.round(10)
    local delete_y = by + row1_h * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, delete_x, delete_y, UIScale.px(4), 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, delete_x - UIScale.round(6), delete_y - UIScale.round(6))
    r.ImGui_InvisibleButton(ctx, "##ir_take_fx_delete", UIScale.round(12), UIScale.round(12))
    if r.ImGui_IsItemClicked(ctx, 0) then
      if tile_mod_action(ctx) == "delete" then delete_take_fx(app, take, fx_index, fx_name) else r.ImGui_OpenPopup(ctx, "##ir_take_delete_pop") end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete item FX (Alt-click to delete instantly)") end

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
    local name_base = bx + UIScale.round(6)
    local name_tx = name_base
    if settings.fx_name_center then
      local nw = r.ImGui_CalcTextSize(ctx, short_name)
      name_tx = name_base + math.max(0, (name_max_w - nw) * 0.5)
    end
    r.ImGui_DrawList_PushClipRect(draw_list, name_base, by, name_base + name_max_w, by + row1_h, true)
    r.ImGui_DrawList_AddText(draw_list, name_tx, by + UIScale.round(2), enabled and Theme.colors.text or Theme.colors.text_dim, short_name)
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
        if r.ImGui_IsItemClicked(ctx, 0) then
          if not apply_tile_mod() then show_take_fx(take, fx_index) end
        end
        if settings.show_type_badge then
          draw_fx_type_badge(ctx, draw_list, fx_name, bx + item_width - UIScale.round(2), by + row1_h + toolbar_h + UIScale.round(4))
        end
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
      if param_h > 0 then
        local sep_y = by + row1_h + toolbar_h + shot_h + UIScale.round(4)
        r.ImGui_DrawList_AddLine(draw_list, bx + UIScale.round(4), sep_y, bx + item_width - UIScale.round(4), sep_y, Theme.colors.separator, UIScale.px(1))
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
    if r.ImGui_InvisibleButton(ctx, "##ir_take_fx_title_hit", math.max(1, name_max_w + 8), row1_h) then
      if not apply_tile_mod() then show_take_fx(take, fx_index) end
    end
    handle_fx_drag(app, ctx, draw_list, track, take, "item", fx_index, short_name, bx, by, item_width, tile_h)
    local function take_menu_items()
      if r.ImGui_MenuItem(ctx, enabled and "Bypass" or "Enable") then set_take_fx_enabled(take, fx_index, not enabled) end
      if r.ImGui_MenuItem(ctx, "Open floating", nil, false, r.TakeFX_Show ~= nil) then show_take_fx(take, fx_index) end
      if r.ImGui_MenuItem(ctx, offline and "Bring online" or "Set offline", nil, false, r.TakeFX_SetOffline ~= nil) then set_take_fx_offline(take, fx_index, not offline) end
      if r.ImGui_MenuItem(ctx, is_collapsed and "Expand" or "Collapse") then state.collapsed[collapse_key] = not is_collapsed end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Parallel", nil, c_is_parallel(make_fx_chain(track, take, "item"), fx_index)) then
        toggle_fx_parallel(app, make_fx_chain(track, take, "item"), fx_index)
      end
      if r.ImGui_MenuItem(ctx, "Wrap in container") then
        wrap_fx_in_container(app, make_fx_chain(track, take, "item"), fx_index)
      end
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

local function draw_section_label(ctx, label, detail, count, accent, section_id, text_alpha)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local width = math.max(UIScale.round(120), get_available_width(ctx))
  local height = detail and detail ~= "" and UIScale.round(32) or UIScale.round(24)
  local collapse_key = section_id and ("SECTION|" .. tostring(section_id)) or nil
  local is_collapsed = (collapse_key and state.collapsed[collapse_key] == true) or false
  if collapse_key then
    if r.ImGui_InvisibleButton(ctx, "##ir_vsection_" .. tostring(section_id), width, height) then
      state.collapsed[collapse_key] = not is_collapsed
      is_collapsed = not is_collapsed
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, is_collapsed and "Expand section" or "Collapse section") end
  else
    r.ImGui_Dummy(ctx, width, height)
  end
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + UIScale.round(3), y + height, accent or Theme.colors.accent, UIScale.px(4))
  local text_x = x + UIScale.round(10)
  if collapse_key then
    local chev_cx = x + UIScale.round(15)
    local chev_cy = y + UIScale.round(12)
    if is_collapsed then
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - UIScale.round(3), chev_cy - UIScale.round(4), chev_cx + UIScale.round(4), chev_cy, chev_cx - UIScale.round(3), chev_cy + UIScale.round(4), Theme.colors.text)
    else
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - UIScale.round(4), chev_cy - UIScale.round(3), chev_cx + UIScale.round(4), chev_cy - UIScale.round(3), chev_cx, chev_cy + UIScale.round(4), Theme.colors.text)
    end
    text_x = x + UIScale.round(26)
  end
  r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(5), apply_text_alpha(Theme.colors.text, text_alpha or 1), label)
  if count then
    local count_text = tostring(count) .. " FX"
    local count_w = r.ImGui_CalcTextSize(ctx, count_text)
    r.ImGui_DrawList_AddText(draw_list, x + width - count_w - UIScale.round(10), y + UIScale.round(5), Theme.colors.text_dim, count_text)
  end
  if detail and detail ~= "" then r.ImGui_DrawList_AddTextEx(draw_list, nil, UIScale.round(10), text_x, y + UIScale.round(20), Theme.colors.text_dim, detail) end
  return is_collapsed
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
  quick_load_user_lists()
  quick_load_parser(false)
  quick_load_fxchains()
  if r.MIDI_GetRecentInputEvent then state.midi_last_retval = r.MIDI_GetRecentInputEvent(0) or 0 end
  load_macros()
end

local function handle_rack_window_external_drop(app, ctx, track)
  local payload = state.last_external_drag
  if not payload or payload == "" then return end
  if not validate_track(track) then return end
  local wx, wy = r.ImGui_GetWindowPos(ctx)
  local ww, wh = r.ImGui_GetWindowSize(ctx)
  local mx, my = global_mouse_pos(ctx)
  if mx < wx or mx > wx + ww or my < wy or my > wy + wh then return end
  if state.mouse_released then
    if r.HasExtState("TKFXB", "drag_fx") then
      add_external_fx(app, track, payload, nil)
    end
  else
    local guid = track_guid(track)
    if guid ~= "" and not r.HasExtState("TKMIX", "rack_target") then
      r.SetExtState("TKMIX", "rack_target", guid .. "|-1", false)
    end
  end
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  if state.request_open_settings then
    r.ImGui_OpenPopup(ctx, "Instrument Rack Settings")
    state.request_open_settings = false
  end
  state.macro_count = settings.macro_count == 16 and 16 or 8
  update_external_drag(ctx)
  run_pending_param_action(app)
  local track = get_target_track(settings)
  app.current_rack_track = track
  if settings.show_macros ~= false then process_macro_cc_input(app, track) end
  local vertical_titlebar = settings.orientation == "horizontal" and settings.horizontal_titlebar_left == true
  local vbar_open = false
  local function finish_vbar()
    if vbar_open then
      r.ImGui_EndGroup(ctx)
      vbar_open = false
    end
  end
  if vertical_titlebar then
    draw_header_vertical(app, ctx, settings, track, expanded_tile_height(settings))
    r.ImGui_SameLine(ctx, nil, UIScale.gap(4))
    r.ImGui_BeginGroup(ctx)
    vbar_open = true
  else
    draw_header(app, ctx, settings, track)
    r.ImGui_Separator(ctx)
  end
  if not validate_track(track) then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Select a track to show its FX chain.")
    if settings.show_info_bar ~= false then UI.draw_info_line(ctx, info_line_text(app, track, 0, 0, 0, nil, nil)) end
    finish_vbar()
    return
  end
  if settings.body_collapsed then
    if r.ImGui_Button(ctx, "Expand rack##ir_expand") then
      settings.body_collapsed = false
      if app.save_settings then app.save_settings() end
    end
    if settings.show_info_bar ~= false then UI.draw_info_line(ctx, info_line_text(app, track, r.TrackFX_GetCount(track), 0, 0, nil, nil)) end
    finish_vbar()
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
    if horizontal and r.ImGui_IsWindowHovered(ctx, hover_flags) and r.ImGui_SetScrollX and r.ImGui_GetScrollX then
      local wheel_v, wheel_h = 0, 0
      if r.ImGui_GetMouseWheel then wheel_v, wheel_h = r.ImGui_GetMouseWheel(ctx) end
      wheel_v = wheel_v or 0
      wheel_h = wheel_h or 0
      local delta = wheel_h - wheel_v
      if settings.invert_horizontal_scroll then delta = -delta end
      if delta ~= 0 then
        local step = horizontal_tile_pixels(settings) * 0.5
        r.ImGui_SetScrollX(ctx, r.ImGui_GetScrollX(ctx) + delta * step)
      end
    end
    local width = horizontal and horizontal_tile_pixels(settings) or get_centered_item_width(ctx)
    local col = 0
    local function next_tile()
      if horizontal then
        if col > 0 then
          if settings.hide_parallel_serial_badges then
            r.ImGui_SameLine(ctx, nil, 0)
          else
            r.ImGui_SameLine(ctx)
          end
        end
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
      if has_line then r.ImGui_SameLine(ctx, nil, 0) end
      local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
      local bar_w = UIScale.round(20)
      local pad = has_line and UIScale.round(4) or 0
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
        local compact = label:upper():gsub("%s+", "")
        local chars = {}
        for ch in compact:gmatch(".") do chars[#chars + 1] = ch end
        local top = sy + chev_size + UIScale.round(8)
        local avail_h = sh - (chev_size + UIScale.round(12))
        local target_size = math.floor((avail_h / math.max(1, #chars)) - 1)
        if target_size < UIScale.round(7) then target_size = UIScale.round(7) end
        if target_size > UIScale.round(12) then target_size = UIScale.round(12) end
        local font_size = r.ImGui_GetFontSize(ctx)
        local scale = target_size / font_size
        local line_h = target_size + UIScale.round(1)
        local max_chars = math.max(1, math.floor(avail_h / line_h))
        local total_h = math.min(#chars, max_chars) * line_h
        local start_y = top + math.max(0, (avail_h - total_h) * 0.5)
        local name_color = apply_text_alpha(text_color, (math.floor(tonumber(settings.panel_name_alpha) or 100)) / 100)
        for i = 1, math.min(#chars, max_chars) do
          local ch = chars[i]
          local ch_w = r.ImGui_CalcTextSize(ctx, ch) * scale
          r.ImGui_DrawList_AddTextEx(sdl, nil, target_size, bx + (bar_w - ch_w) * 0.5, start_y + (i - 1) * line_h, name_color, ch)
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
    local INDENT_STEP = UIScale.round(16)
    local function indent_cursor(depth)
      center_next_item(ctx, width)
      if depth > 0 then r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + depth * INDENT_STEP) end
    end
    local function container_menu_id(node)
      return "##ir_cont_menu_" .. tostring(node.api)
    end
    local function open_container_menu(node)
      r.ImGui_OpenPopup(ctx, container_menu_id(node))
    end
    local render_chain = make_fx_chain(track, take, "track")
    local function rc_is_take()
      return render_chain.kind == "item"
    end
    local function rc_name(api)
      if rc_is_take() then
        local _, n = r.TakeFX_GetFXName(take, api, "")
        return n or ""
      end
      local _, n = r.TrackFX_GetFXName(track, api, "")
      return n or ""
    end
    local function rc_enabled(api)
      if rc_is_take() then return take_fx_enabled(take, api) end
      return r.TrackFX_GetEnabled(track, api)
    end
    local function rc_set_enabled(api, value)
      if rc_is_take() then set_take_fx_enabled(take, api, value); return end
      r.TrackFX_SetEnabled(track, api, value)
    end
    local function rc_offline(api)
      if rc_is_take() then return take_fx_offline(take, api) end
      return r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, api) or false
    end
    local function rc_set_offline(api, value)
      if rc_is_take() then set_take_fx_offline(take, api, value); return end
      if r.TrackFX_SetOffline then r.TrackFX_SetOffline(track, api, value) end
    end
    local function rc_delete(api, name)
      if rc_is_take() then delete_take_fx(app, take, api, name); return end
      delete_fx(app, track, api, name)
    end
    local function rc_collapse_key(api)
      return render_chain.kind .. "|" .. track_guid(track) .. "|" .. c_guid(render_chain, api)
    end
    local function rc_draw_tile(node, tile_w)
      if rc_is_take() then
        draw_take_fx_tile(app, ctx, settings, track, take, node.api, tile_w)
      else
        draw_fx_tile(app, ctx, settings, track, node.api, tile_w, "track", take)
      end
    end
    local function draw_container_menu(node, name, is_collapsed, collapse_key)
      if not r.ImGui_BeginPopup(ctx, container_menu_id(node)) then return end
      local enabled = rc_enabled(node.api)
      local offline = rc_offline(node.api)
      local is_parallel = node.parallel == true
      local top_level = node.api < CONTAINER_BASE
      if r.ImGui_MenuItem(ctx, is_collapsed and "Expand" or "Collapse") then
        state.collapsed[collapse_key] = not is_collapsed
      end
      if r.ImGui_MenuItem(ctx, "Parallel", nil, is_parallel) then
        toggle_fx_parallel(app, render_chain, node.api)
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Bypass", nil, not enabled) then
        rc_set_enabled(node.api, not enabled)
      end
      if r.ImGui_MenuItem(ctx, "Offline", nil, offline) then
        rc_set_offline(node.api, not offline)
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Add container inside") then
        add_container_inside(app, render_chain, node.api)
      end
      if r.ImGui_MenuItem(ctx, "Unpack container", nil, false, top_level) then
        unpack_container(app, render_chain, node.api)
      end
      if r.ImGui_MenuItem(ctx, "Delete container") then
        rc_delete(node.api, name)
      end
      r.ImGui_EndPopup(ctx)
    end
    local function draw_container_header(node, tile_w, collapse_key, is_collapsed)
      local accent = section_accent_color(settings, track)
      local name = rc_name(node.api)
      local short = get_fx_short_name(name or "")
      if short == nil or short == "" then short = "Container" end
      local enabled = rc_enabled(node.api)
      local offline = rc_offline(node.api)
      local header_h = UIScale.round(24)
      local wet_idx = chain_wet_param(render_chain, node.api)
      local has_wet = wet_idx ~= nil
      local wet_radius = UIScale.round(8)
      local wet_zone_w = has_wet and (wet_radius * 2 + UIScale.round(10)) or 0
      r.ImGui_PushID(ctx, "ir_cont_" .. tostring(node.api))
      local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
      local visible = r.ImGui_BeginChild(ctx, "##ir_container_hdr", tile_w, header_h, 0, flags)
      r.ImGui_PopStyleVar(ctx, 1)
      if visible then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local bx, by = r.ImGui_GetCursorScreenPos(ctx)
        local tint = (accent & 0xFFFFFF00) | 0x26
        local bg = offline and 0x332020E6 or ((not enabled) and 0x24262BE6 or tint)
        r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + tile_w, by + header_h, bg, UIScale.px(4))
        r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + UIScale.round(4), by + header_h, accent, UIScale.px(2))
        r.ImGui_DrawList_AddRect(dl, bx, by, bx + tile_w, by + header_h, accent, UIScale.px(4), 0, UIScale.px(1.5))
        local chx = bx + UIScale.round(14)
        local chy = by + header_h * 0.5
        local col_text = enabled and Theme.colors.text or Theme.colors.text_dim
        local icon_col = enabled and accent or Theme.colors.text_dim
        if is_collapsed then
          r.ImGui_DrawList_AddTriangleFilled(dl, chx - UIScale.round(3), chy - UIScale.round(4), chx + UIScale.round(4), chy, chx - UIScale.round(3), chy + UIScale.round(4), col_text)
        else
          r.ImGui_DrawList_AddTriangleFilled(dl, chx - UIScale.round(4), chy - UIScale.round(3), chx + UIScale.round(4), chy - UIScale.round(3), chx, chy + UIScale.round(4), col_text)
        end
        local fw, fh = UIScale.round(12), UIScale.round(9)
        local fx0 = bx + UIScale.round(24)
        local fy0 = by + (header_h - fh) * 0.5
        r.ImGui_DrawList_AddRectFilled(dl, fx0 + UIScale.round(1), fy0 - UIScale.round(2), fx0 + UIScale.round(6), fy0 + UIScale.round(1), icon_col, UIScale.px(1))
        r.ImGui_DrawList_AddRectFilled(dl, fx0, fy0, fx0 + fw, fy0 + fh, icon_col, UIScale.px(1.5))
        local label = short
        if node.child_count and node.child_count > 0 then label = short .. "   (" .. tostring(node.child_count) .. ")" end
        r.ImGui_DrawList_AddText(dl, bx + UIScale.round(42), by + (header_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5, col_text, label)
        if node.parallel then
          local pw = r.ImGui_CalcTextSize(ctx, "||")
          r.ImGui_DrawList_AddText(dl, bx + tile_w - wet_zone_w - pw - UIScale.round(8), by + (header_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5, accent, "||")
        end
        r.ImGui_SetCursorScreenPos(ctx, bx, by)
        if r.ImGui_InvisibleButton(ctx, "##ir_container_btn", tile_w - wet_zone_w, header_h) then
          local action = tile_mod_action(ctx)
          if action == "delete" then
            rc_delete(node.api, name)
          elseif action == "bypass" then
            rc_set_enabled(node.api, not enabled)
          elseif action == "offline" then
            rc_set_offline(node.api, not offline)
          else
            state.collapsed[collapse_key] = not is_collapsed
          end
        end
        if r.ImGui_IsItemClicked(ctx, 1) then open_container_menu(node) end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, short .. (node.parallel and " (parallel)" or "") .. " — container, click to " .. (is_collapsed and "expand" or "collapse") .. " (Alt-click delete, Shift bypass, Ctrl+Shift offline)")
        end
        if r.ImGui_BeginDragDropTarget(ctx) then
          local ok_payload, wp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
          if ok_payload and wp and wp ~= "" then add_external_fx_into_container(app, render_chain, node.api, wp) end
          local ok_move, mp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
          if ok_move and mp and mp ~= "" then
            local sc, si = mp:match("([^|]+)|(%d+)")
            if sc and si then move_fx_into_container(app, render_chain, sc, tonumber(si), node.api) end
          end
          r.ImGui_EndDragDropTarget(ctx)
        end
        local hpayload = state.last_external_drag or ""
        if hpayload ~= "" and state.mouse_released and r.ImGui_IsItemHovered(ctx) then
          add_external_fx_into_container(app, render_chain, node.api, hpayload)
        end
        if has_wet then
          local kcx = bx + tile_w - wet_radius - UIScale.round(6)
          local kcy = by + header_h * 0.5
          draw_container_wet_knob(app, ctx, dl, render_chain, node.api, wet_idx, kcx, kcy, wet_radius, "##ir_cont_wet_v")
        end
        draw_container_menu(node, name, is_collapsed, collapse_key)
        r.ImGui_EndChild(ctx)
      end
      r.ImGui_PopID(ctx)
    end
    local seam_toggle_pending = nil
    local seam_toggle_chain = nil
    local function draw_parallel_badge(dl, cx, cy, col, is_horizontal)
      if settings.hide_parallel_serial_badges then return end
      local hs = UIScale.round(11)
      local x0, y0, x1, y1 = cx - hs, cy - hs, cx + hs, cy + hs
      local sym = luminance(col) > 0.55 and 0x000000FF or 0xFFFFFFFF
      r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, col, UIScale.px(4))
      r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, sym, UIScale.px(4), 0, UIScale.px(1))
      local a = UIScale.round(3)
      local b = UIScale.round(6)
      if is_horizontal then
        r.ImGui_DrawList_AddLine(dl, cx - b, cy - a, cx + b, cy - a, sym, UIScale.px(1.5))
        r.ImGui_DrawList_AddLine(dl, cx - b, cy + a, cx + b, cy + a, sym, UIScale.px(1.5))
      else
        r.ImGui_DrawList_AddLine(dl, cx - a, cy - b, cx - a, cy + b, sym, UIScale.px(1.5))
        r.ImGui_DrawList_AddLine(dl, cx + a, cy - b, cx + a, cy + b, sym, UIScale.px(1.5))
      end
    end
    local function draw_serial_badge(dl, cx, cy, col, is_horizontal)
      if settings.hide_parallel_serial_badges then return end
      local hs = UIScale.round(11)
      local x0, y0, x1, y1 = cx - hs, cy - hs, cx + hs, cy + hs
      local sym = luminance(col) > 0.55 and 0x000000FF or 0xFFFFFFFF
      r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x1, y1, col, UIScale.px(4))
      r.ImGui_DrawList_AddRect(dl, x0, y0, x1, y1, sym, UIScale.px(4), 0, UIScale.px(1))
      local b = UIScale.round(6)
      local h = UIScale.round(4)
      if is_horizontal then
        r.ImGui_DrawList_AddLine(dl, cx - b, cy, cx + b, cy, sym, UIScale.px(1.5))
        r.ImGui_DrawList_AddLine(dl, cx + b - h, cy - h, cx + b, cy, sym, UIScale.px(1.5))
        r.ImGui_DrawList_AddLine(dl, cx + b - h, cy + h, cx + b, cy, sym, UIScale.px(1.5))
      else
        r.ImGui_DrawList_AddLine(dl, cx, cy - b, cx, cy + b, sym, UIScale.px(1.5))
        r.ImGui_DrawList_AddLine(dl, cx - h, cy + b - h, cx, cy + b, sym, UIScale.px(1.5))
        r.ImGui_DrawList_AddLine(dl, cx + h, cy + b - h, cx, cy + b, sym, UIScale.px(1.5))
      end
    end
    local function seam_badge_button(api, cx, cy, is_parallel)
      if not api or not cx or not cy then return end
      local hs = UIScale.round(11)
      if not r.ImGui_IsMouseHoveringRect(ctx, cx - hs, cy - hs, cx + hs, cy + hs) then return end
      if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
      end
      if r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, (is_parallel and "Parallel" or "Serial") .. " - click to switch to " .. (is_parallel and "serial" or "parallel"))
      end
      if (r.ImGui_IsMouseClicked(ctx, 0) or r.ImGui_IsMouseClicked(ctx, 1)) and not seam_toggle_pending then
        seam_toggle_pending = api
        seam_toggle_chain = render_chain
      end
    end
    local function draw_container_inner_zone(container_api, zone_w, depth)
      indent_cursor(depth)
      local payload = state.last_external_drag or ""
      local quick_enabled = settings.quick_add_enabled ~= false
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      local zone_h = UIScale.round(32)
      r.ImGui_PushID(ctx, "ir_cdrop_" .. tostring(container_api))
      r.ImGui_InvisibleButton(ctx, "##ir_container_drop", zone_w, zone_h)
      local hovered = r.ImGui_IsItemHovered(ctx)
      local clicked = r.ImGui_IsItemClicked(ctx, 0)
      local mx, my = r.ImGui_GetMousePos(ctx)
      local zx0, zy0 = r.ImGui_GetItemRectMin(ctx)
      local zx1, zy1 = r.ImGui_GetItemRectMax(ctx)
      local active = payload ~= ""
      local border = active and Theme.colors.accent or (hovered and Theme.colors.frame_hover or add_zone_visible_color())
      local quick_w = quick_enabled and UIScale.round(64) or 0
      local quick_gap = quick_enabled and UIScale.round(6) or 0
      local main_w = zone_w - quick_w - quick_gap
      local show_add_border = settings.add_zone_border ~= false
      if show_add_border or active or hovered then
        r.ImGui_DrawList_AddRect(dl, x, y, x + main_w, y + zone_h, border, UIScale.px(4), 0, active and UIScale.px(2) or UIScale.px(1))
      end
      local label = active and "+ Drop" or "+ Add FX"
      local tw = r.ImGui_CalcTextSize(ctx, label)
      r.ImGui_DrawList_AddText(dl, x + (main_w - tw) * 0.5, y + (zone_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5, active and Theme.colors.accent or add_zone_visible_color(), label)
      local quick_hovered = false
      if quick_enabled then
        local qx0 = x + main_w + quick_gap
        local qx1 = qx0 + quick_w
        quick_hovered = mx >= qx0 and mx <= qx1 and my >= y and my <= y + zone_h
        local q_border = quick_hovered and Theme.colors.accent or add_zone_visible_color()
        if show_add_border or active or quick_hovered then
          r.ImGui_DrawList_AddRect(dl, qx0, y, qx1, y + zone_h, q_border, UIScale.px(4), 0, UIScale.px(1))
        end
        local q_w = r.ImGui_CalcTextSize(ctx, "Quick")
        local q_col = quick_hovered and Theme.colors.accent or add_zone_visible_color()
        r.ImGui_DrawList_AddText(dl, qx0 + (quick_w - q_w) * 0.5, y + (zone_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5, q_col, "Quick")
      end
      if clicked and payload == "" then
        if quick_hovered then
          quick_open_popup(render_chain.track, render_chain.kind == "item" and "item" or "track", render_chain.take, nil, render_chain, container_api)
        else
          open_container_add_browser(app, render_chain, container_api)
        end
      end
      local inner_menu_id = "##ir_cinner_menu_" .. tostring(container_api)
      if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, inner_menu_id) end
      if r.ImGui_BeginPopup(ctx, inner_menu_id) then
        if r.ImGui_MenuItem(ctx, "Add FX...") then open_container_add_browser(app, render_chain, container_api) end
        if settings.quick_add_enabled ~= false and r.ImGui_MenuItem(ctx, "Quick Add...") then
          quick_open_popup(render_chain.track, render_chain.kind == "item" and "item" or "track", render_chain.take, nil, render_chain, container_api)
        end
        if r.ImGui_MenuItem(ctx, "Add empty container inside") then add_container_inside(app, render_chain, container_api) end
        r.ImGui_EndPopup(ctx)
      end
      if hovered then
        if payload ~= "" and state.mouse_released then add_external_fx_into_container(app, render_chain, container_api, payload) end
        if quick_hovered and payload == "" then
          r.ImGui_SetTooltip(ctx, "Quick Add (cascading menu)")
        else
          r.ImGui_SetTooltip(ctx, payload ~= "" and "Drop FX here to add it inside this container" or "Add FX into this container (click) or drop FX here")
        end
      end
      if r.ImGui_BeginDragDropTarget(ctx) then
        local ok_payload, wp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
        if ok_payload and wp and wp ~= "" then add_external_fx_into_container(app, render_chain, container_api, wp) end
        local ok_move, mp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
        if ok_move and mp and mp ~= "" then
          local sc, si = mp:match("([^|]+)|(%d+)")
          if sc and si then move_fx_into_container(app, render_chain, sc, tonumber(si), container_api) end
        end
        r.ImGui_EndDragDropTarget(ctx)
      end
      r.ImGui_PopID(ctx)
      return zx0, zy0, zx1, zy1
    end
    local function render_fx_nodes(nodes, depth)
      local minx, miny, maxx, maxy
      local V_TILE_GAP = settings.hide_parallel_serial_badges and 0 or UIScale.round(20)
      local function acc(x0, y0, x1, y1)
        if not x0 then return end
        minx = minx and math.min(minx, x0) or x0
        miny = miny and math.min(miny, y0) or y0
        maxx = maxx and math.max(maxx, x1) or x1
        maxy = maxy and math.max(maxy, y1) or y1
      end
      local items = {}
      for _, node in ipairs(nodes) do
        if #items > 0 and V_TILE_GAP > 0 then r.ImGui_Dummy(ctx, 1, V_TILE_GAP) end
        local tile_w = width - depth * INDENT_STEP
        local min_w = UIScale.round(140)
        if tile_w < min_w then tile_w = min_w end
        if node.is_container then
          local collapse_key = rc_collapse_key(node.api)
          local is_collapsed = state.collapsed[collapse_key] == true
          indent_cursor(depth)
          draw_container_header(node, tile_w, collapse_key, is_collapsed)
          local hx0, hy0 = r.ImGui_GetItemRectMin(ctx)
          local hx1, hy1 = r.ImGui_GetItemRectMax(ctx)
          acc(hx0, hy0, hx1, hy1)
          local block_bottom = hy1
          if not is_collapsed then
            local cminx, cmaxx, cmaxy
            if node.children and #node.children > 0 then
              local a, _, c, d = render_fx_nodes(node.children, depth + 1)
              cminx, cmaxx, cmaxy = a, c, d
            end
            r.ImGui_Dummy(ctx, 1, UIScale.round(4))
            local zone_w = width - (depth + 1) * INDENT_STEP
            if zone_w < min_w then zone_w = min_w end
            local zx0, _, zx1, zy1 = draw_container_inner_zone(node.api, zone_w, depth + 1)
            local pad = UIScale.round(3)
            local bx0 = math.min(hx0, cminx or hx0, zx0 or hx0) - pad
            local by0 = hy0 - pad
            local bx1 = math.max(hx1, cmaxx or hx1, zx1 or hx1) + pad
            local by1 = math.max(cmaxy or hy1, zy1 or hy1) + pad
            local accent = section_accent_color(settings, track)
            local rail_col = (accent & 0xFFFFFF00) | 0xFF
            r.ImGui_DrawList_AddRect(r.ImGui_GetWindowDrawList(ctx), bx0, by0, bx1, by1, rail_col, UIScale.px(3), 0, UIScale.px(2.5))
            acc(bx0, by0, bx1, by1)
            block_bottom = by1
          end
          items[#items + 1] = { x0 = hx0, x1 = hx1, top = hy0, bottom = block_bottom, parallel = node.parallel, api = node.api }
        else
          indent_cursor(depth)
          rc_draw_tile(node, tile_w)
          local tx0, ty0 = r.ImGui_GetItemRectMin(ctx)
          local tx1, ty1 = r.ImGui_GetItemRectMax(ctx)
          acc(tx0, ty0, tx1, ty1)
          items[#items + 1] = { x0 = tx0, x1 = tx1, top = ty0, bottom = ty1, parallel = node.parallel, api = node.api }
        end
      end
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local accent = section_accent_color(settings, track)
      local col = (accent & 0xFFFFFF00) | 0xFF
      for k = 2, #items do
        local prev, cur = items[k - 1], items[k]
        local cx = (cur.x0 + cur.x1) * 0.5
        local cy = (prev.bottom + cur.top) * 0.5
        if cur.parallel then
          draw_parallel_badge(dl, cx, cy, col, false)
        else
          draw_serial_badge(dl, cx, cy, col, false)
        end
        seam_badge_button(cur.api, cx, cy, cur.parallel)
      end
      return minx, miny, maxx, maxy
    end
    local function draw_container_strip_h(node, collapse_key, is_collapsed, depth, th_override, strip_w_override)
      local strip_w = strip_w_override or UIScale.round(26)
      local th = th_override or expanded_tile_height(settings)
      local accent = section_accent_color(settings, track)
      local name = rc_name(node.api)
      local short = get_fx_short_name(name or "")
      if short == nil or short == "" then short = "Container" end
      local enabled = rc_enabled(node.api)
      local offline = rc_offline(node.api)
      local wet_idx = chain_wet_param(render_chain, node.api)
      local has_wet = wet_idx ~= nil
      local wet_radius = UIScale.round(8)
      local wet_zone_h = has_wet and (wet_radius * 2 + UIScale.round(10)) or 0
      r.ImGui_PushID(ctx, "ir_conth_" .. tostring(node.api))
      local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
      local visible = r.ImGui_BeginChild(ctx, "##ir_container_striph", strip_w, th, 0, flags)
      r.ImGui_PopStyleVar(ctx, 1)
      if visible then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local bx, by = r.ImGui_GetCursorScreenPos(ctx)
        local text_color = enabled and Theme.colors.text or Theme.colors.text_dim
        local icon_col = enabled and accent or Theme.colors.text_dim
        local tint_alpha = depth > 0 and 0x50 or 0x26
        local body_bg = offline and 0x332020E6 or ((not enabled) and 0x24262BE6 or ((accent & 0xFFFFFF00) | tint_alpha))
        r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + strip_w, by + th, body_bg, UIScale.px(3))
        r.ImGui_DrawList_AddRect(dl, bx, by, bx + strip_w, by + th, accent, UIScale.px(3), 0, UIScale.px(1.5))
        if depth > 0 then
          r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + strip_w, by + UIScale.round(3), accent, UIScale.px(2))
        end
        local chev_cx = bx + strip_w * 0.5
        local chev_cy = by + UIScale.round(8)
        if is_collapsed then
          r.ImGui_DrawList_AddTriangleFilled(dl, chev_cx - UIScale.round(3), chev_cy - UIScale.round(4), chev_cx + UIScale.round(4), chev_cy, chev_cx - UIScale.round(3), chev_cy + UIScale.round(4), text_color)
        else
          r.ImGui_DrawList_AddTriangleFilled(dl, chev_cx + UIScale.round(3), chev_cy - UIScale.round(4), chev_cx - UIScale.round(4), chev_cy, chev_cx + UIScale.round(3), chev_cy + UIScale.round(4), text_color)
        end
        local fw, fh = UIScale.round(13), UIScale.round(10)
        local fx0 = bx + (strip_w - fw) * 0.5
        local fy0 = by + UIScale.round(19)
        r.ImGui_DrawList_AddRectFilled(dl, fx0 + UIScale.round(1), fy0 - UIScale.round(2), fx0 + UIScale.round(6), fy0 + UIScale.round(1), icon_col, UIScale.px(1))
        r.ImGui_DrawList_AddRectFilled(dl, fx0, fy0, fx0 + fw, fy0 + fh, icon_col, UIScale.px(1.5))
        local name_top = by + UIScale.round(34)
        if node.parallel then
          local pw = r.ImGui_CalcTextSize(ctx, "||")
          r.ImGui_DrawList_AddText(dl, bx + (strip_w - pw) * 0.5, name_top, accent, "||")
          name_top = name_top + UIScale.round(16)
        end
        local size = UIScale.round(12)
        local scale = size / r.ImGui_GetFontSize(ctx)
        local line_h = size + UIScale.round(1)
        local top = name_top
        local avail_h = th - (top - by) - UIScale.round(4) - wet_zone_h
        local max_chars = math.max(1, math.floor(avail_h / line_h))
        local chars = {}
        for ch in short:gmatch(".") do chars[#chars + 1] = ch; if #chars >= max_chars then break end end
        for i, ch in ipairs(chars) do
          local ch_w = r.ImGui_CalcTextSize(ctx, ch) * scale
          r.ImGui_DrawList_AddTextEx(dl, nil, size, bx + (strip_w - ch_w) * 0.5, top + (i - 1) * line_h, text_color, ch)
        end
        r.ImGui_SetCursorScreenPos(ctx, bx, by)
        if r.ImGui_InvisibleButton(ctx, "##ir_container_btnh", strip_w, th - wet_zone_h) then
          local action = tile_mod_action(ctx)
          if action == "delete" then
            rc_delete(node.api, name)
          elseif action == "bypass" then
            rc_set_enabled(node.api, not enabled)
          elseif action == "offline" then
            rc_set_offline(node.api, not offline)
          else
            state.collapsed[collapse_key] = not is_collapsed
          end
        end
        if r.ImGui_IsItemClicked(ctx, 1) then open_container_menu(node) end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, short .. " — container, click to " .. (is_collapsed and "expand" or "collapse") .. " (Alt-click delete, Shift bypass, Ctrl+Shift offline)")
        end
        if r.ImGui_BeginDragDropTarget(ctx) then
          local ok_payload, wp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
          if ok_payload and wp and wp ~= "" then add_external_fx_into_container(app, render_chain, node.api, wp) end
          local ok_move, mp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
          if ok_move and mp and mp ~= "" then
            local sc, si = mp:match("([^|]+)|(%d+)")
            if sc and si then move_fx_into_container(app, render_chain, sc, tonumber(si), node.api) end
          end
          r.ImGui_EndDragDropTarget(ctx)
        end
        local hpayload = state.last_external_drag or ""
        if hpayload ~= "" and state.mouse_released and r.ImGui_IsItemHovered(ctx) then
          add_external_fx_into_container(app, render_chain, node.api, hpayload)
        end
        if has_wet then
          local kcx = bx + strip_w * 0.5
          local kcy = by + th - wet_radius - UIScale.round(6)
          draw_container_wet_knob(app, ctx, dl, render_chain, node.api, wet_idx, kcx, kcy, wet_radius, "##ir_cont_wet_h")
        end
        draw_container_menu(node, name, is_collapsed, collapse_key)
        r.ImGui_EndChild(ctx)
      end
      r.ImGui_PopID(ctx)
    end
    local H_TILE_GAP = settings.hide_parallel_serial_badges and UIScale.round(4) or UIScale.round(20)
    local H_STRIP_W = UIScale.round(26)
    local H_INNER_MARGIN = UIScale.round(8)
    local H_OUTLINE_PAD = UIScale.round(5)
    local H_DROP_W = UIScale.round(46)
    local function draw_container_inner_zone_h(container_api, zone_w, zone_h)
      local payload = state.last_external_drag or ""
      local quick_enabled = settings.quick_add_enabled ~= false
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      r.ImGui_PushID(ctx, "ir_cdroph_" .. tostring(container_api))
      r.ImGui_InvisibleButton(ctx, "##ir_container_droph", zone_w, zone_h)
      local hovered = r.ImGui_IsItemHovered(ctx)
      local clicked = r.ImGui_IsItemClicked(ctx, 0)
      local mx, my = r.ImGui_GetMousePos(ctx)
      local active = payload ~= ""
      local color = active and Theme.colors.accent or (hovered and Theme.colors.frame_hover or add_zone_visible_color())
      local circle_d = UIScale.round(30)
      local gap = UIScale.round(6)
      local radius = circle_d * 0.5 - UIScale.px(2)
      local quick_r = radius
      local stack_h = quick_enabled and (circle_d * 2 + gap) or circle_d
      local cx = x + zone_w * 0.5
      local cy = y + (zone_h - stack_h) * 0.5 + radius + UIScale.px(2)
      local quick_cx, quick_cy = cx, cy + circle_d + gap
      local add_hovered = (mx >= cx - radius and mx <= cx + radius and my >= cy - radius and my <= cy + radius)
      local quick_hovered = quick_enabled and (mx >= quick_cx - quick_r and mx <= quick_cx + quick_r and my >= quick_cy - quick_r and my <= quick_cy + quick_r)
      local add_col = (add_hovered and not active) and Theme.colors.accent or color
      local show_add_border = settings.add_zone_border ~= false
      if show_add_border or active or add_hovered then
        r.ImGui_DrawList_AddCircle(dl, cx, cy, radius, add_col, 0, active and UIScale.px(2) or UIScale.px(1.5))
      end
      local arm = radius * 0.5
      r.ImGui_DrawList_AddLine(dl, cx - arm, cy, cx + arm, cy, add_col, UIScale.px(2))
      r.ImGui_DrawList_AddLine(dl, cx, cy - arm, cx, cy + arm, add_col, UIScale.px(2))
      if quick_enabled then
        local quick_col = (quick_hovered and not active) and Theme.colors.accent or color
        if show_add_border or active or quick_hovered then
          r.ImGui_DrawList_AddCircle(dl, quick_cx, quick_cy, quick_r, quick_col, 0, UIScale.px(1.5))
        end
        local q_w = r.ImGui_CalcTextSize(ctx, "Q")
        r.ImGui_DrawList_AddText(dl, quick_cx - q_w * 0.5, quick_cy - r.ImGui_GetTextLineHeight(ctx) * 0.5, quick_col, "Q")
      end
      if clicked and payload == "" then
        if quick_hovered then
          quick_open_popup(render_chain.track, render_chain.kind == "item" and "item" or "track", render_chain.take, nil, render_chain, container_api)
        else
          open_container_add_browser(app, render_chain, container_api)
        end
      end
      local inner_menu_id = "##ir_cinnerh_menu_" .. tostring(container_api)
      if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, inner_menu_id) end
      if r.ImGui_BeginPopup(ctx, inner_menu_id) then
        if r.ImGui_MenuItem(ctx, "Add FX...") then open_container_add_browser(app, render_chain, container_api) end
        if settings.quick_add_enabled ~= false and r.ImGui_MenuItem(ctx, "Quick Add...") then
          quick_open_popup(render_chain.track, render_chain.kind == "item" and "item" or "track", render_chain.take, nil, render_chain, container_api)
        end
        if r.ImGui_MenuItem(ctx, "Add empty container inside") then add_container_inside(app, render_chain, container_api) end
        r.ImGui_EndPopup(ctx)
      end
      if hovered then
        if payload ~= "" and state.mouse_released then add_external_fx_into_container(app, render_chain, container_api, payload) end
        if quick_hovered and payload == "" then
          r.ImGui_SetTooltip(ctx, "Quick Add (cascading menu)")
        else
          r.ImGui_SetTooltip(ctx, payload ~= "" and "Drop FX here to add it inside this container" or "Add FX into this container (click) or drop FX here")
        end
      end
      if r.ImGui_BeginDragDropTarget(ctx) then
        local ok_payload, wp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
        if ok_payload and wp and wp ~= "" then add_external_fx_into_container(app, render_chain, container_api, wp) end
        local ok_move, mp = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
        if ok_move and mp and mp ~= "" then
          local sc, si = mp:match("([^|]+)|(%d+)")
          if sc and si then move_fx_into_container(app, render_chain, sc, tonumber(si), container_api) end
        end
        r.ImGui_EndDragDropTarget(ctx)
      end
      r.ImGui_PopID(ctx)
    end
    local function node_is_container(node)
      return node.is_container == true
    end
    local function node_collapse_key(node)
      return rc_collapse_key(node.api)
    end
    local measure_children_h
    local function measure_node_h(node)
      if node_is_container(node) then
        local collapse_key = node_collapse_key(node)
        if state.collapsed[collapse_key] == true then
          return H_STRIP_W, expanded_tile_height(settings)
        end
        local iw, ih = measure_children_h(node.children)
        local w = H_OUTLINE_PAD + H_STRIP_W + H_INNER_MARGIN + iw + H_INNER_MARGIN + H_OUTLINE_PAD
        local h = H_OUTLINE_PAD + math.max(expanded_tile_height(settings), ih) + H_OUTLINE_PAD
        return w, h
      end
      local collapse_key = node_collapse_key(node)
      local w = state.collapsed[collapse_key] == true and H_STRIP_W or width
      return w, expanded_tile_height(settings)
    end
    function measure_children_h(nodes)
      local total_w, max_h = 0, 0
      for i, node in ipairs(nodes) do
        if i > 1 then total_w = total_w + H_TILE_GAP end
        local w, h = measure_node_h(node)
        total_w = total_w + w
        if h > max_h then max_h = h end
      end
      total_w = total_w + H_DROP_W
      if max_h <= 0 then max_h = expanded_tile_height(settings) end
      return total_w, max_h
    end
    local render_node_h
    local function render_container_h(node, depth, collapse_key)
      local iw, ih = measure_children_h(node.children)
      local inner_h = math.max(expanded_tile_height(settings), ih)
      local total_w = H_OUTLINE_PAD + H_STRIP_W + H_INNER_MARGIN + iw + H_INNER_MARGIN + H_OUTLINE_PAD
      local total_h = H_OUTLINE_PAD + inner_h + H_OUTLINE_PAD
      local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
      r.ImGui_PushID(ctx, "ir_conwrap_" .. tostring(node.api))
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
      local visible = r.ImGui_BeginChild(ctx, "##ir_container_wrap", total_w, total_h, 0, flags)
      r.ImGui_PopStyleVar(ctx, 1)
      if visible then
        local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local accent = section_accent_color(settings, track)
        local rail_col = (accent & 0xFFFFFF00) | 0xFF
        local strip_x = ox + H_OUTLINE_PAD
        local strip_y = oy + H_OUTLINE_PAD
        r.ImGui_SetCursorScreenPos(ctx, strip_x, strip_y)
        draw_container_strip_h(node, collapse_key, false, depth, inner_h, H_STRIP_W)
        local child_x = strip_x + H_STRIP_W + H_INNER_MARGIN
        local items = {}
        for _, child in ipairs(node.children) do
          local cw, ch = measure_node_h(child)
          local cy = oy + H_OUTLINE_PAD + (inner_h - ch) * 0.5
          r.ImGui_SetCursorScreenPos(ctx, child_x, cy)
          local x0, y0, x1, y1, par = render_node_h(child, depth + 1)
          items[#items + 1] = { left = x0, right = x1, top = y0, bottom = y1, parallel = par, api = child.api }
          child_x = child_x + cw + H_TILE_GAP
        end
        if #node.children > 0 then child_x = child_x - H_TILE_GAP end
        local drop_y = oy + H_OUTLINE_PAD
        r.ImGui_SetCursorScreenPos(ctx, child_x, drop_y)
        draw_container_inner_zone_h(node.api, H_DROP_W, inner_h)
        r.ImGui_DrawList_AddRect(dl, ox + H_OUTLINE_PAD * 0.5, oy + H_OUTLINE_PAD * 0.5, ox + total_w - H_OUTLINE_PAD * 0.5, oy + total_h - H_OUTLINE_PAD * 0.5, rail_col, UIScale.px(3), 0, UIScale.px(2.5))
        local col = (accent & 0xFFFFFF00) | 0xFF
        for k = 2, #items do
          local prev, cur = items[k - 1], items[k]
          local seam_x = (prev.right + cur.left) * 0.5
          local cy = (cur.top + cur.bottom) * 0.5
          if cur.parallel then
            draw_parallel_badge(dl, seam_x, cy, col, true)
          else
            draw_serial_badge(dl, seam_x, cy, col, true)
          end
          seam_badge_button(cur.api, seam_x, cy, cur.parallel)
        end
        r.ImGui_EndChild(ctx)
      end
      r.ImGui_PopID(ctx)
      local x0, y0 = r.ImGui_GetItemRectMin(ctx)
      local x1, y1 = r.ImGui_GetItemRectMax(ctx)
      return x0, y0, x1, y1, node.parallel
    end
    function render_node_h(node, depth)
      if node_is_container(node) then
        local collapse_key = node_collapse_key(node)
        if state.collapsed[collapse_key] == true then
          draw_container_strip_h(node, collapse_key, true, depth, expanded_tile_height(settings), H_STRIP_W)
          local x0, y0 = r.ImGui_GetItemRectMin(ctx)
          local x1, y1 = r.ImGui_GetItemRectMax(ctx)
          return x0, y0, x1, y1, node.parallel
        end
        return render_container_h(node, depth, collapse_key)
      end
      rc_draw_tile(node, width)
      local x0, y0 = r.ImGui_GetItemRectMin(ctx)
      local x1, y1 = r.ImGui_GetItemRectMax(ctx)
      return x0, y0, x1, y1, node.parallel
    end
    local function render_fx_nodes_h(nodes)
      local items = {}
      for _, node in ipairs(nodes) do
        if #items > 0 and H_TILE_GAP > 0 then
          r.ImGui_SameLine(ctx)
          r.ImGui_Dummy(ctx, H_TILE_GAP, 1)
        end
        next_tile()
        local x0, y0, x1, y1, par = render_node_h(node, 0)
        items[#items + 1] = { left = x0, right = x1, top = y0, bottom = y1, parallel = par, api = node.api }
      end
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local accent = section_accent_color(settings, track)
      local col = (accent & 0xFFFFFF00) | 0xFF
      for k = 2, #items do
        local prev, cur = items[k - 1], items[k]
        local seam_x = (prev.right + cur.left) * 0.5
        local cy = (cur.top + cur.bottom) * 0.5
        if cur.parallel then
          draw_parallel_badge(dl, seam_x, cy, col, true)
        else
          draw_serial_badge(dl, seam_x, cy, col, true)
        end
        seam_badge_button(cur.api, seam_x, cy, cur.parallel)
      end
    end
    local function draw_track_section()
      if not show_track_fx then return end
      local collapsed = false
      if horizontal then
        collapsed = section_break("track", "TRACK")
      else
        new_section()
        collapsed = draw_section_label(ctx, "Track FX", nil, fx_count, section_accent_color(settings, track), "track", (math.floor(tonumber(settings.panel_name_alpha) or 100)) / 100)
        if fx_count == 0 and not collapsed then
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No FX on this track.")
        end
      end
      if not collapsed then
        render_chain = make_fx_chain(track, take, "track")
        if horizontal then
          render_fx_nodes_h(build_track_fx_tree(render_chain, fx_count, 4))
        else
          local nodes = build_track_fx_tree(render_chain, fx_count, 4)
          render_fx_nodes(nodes, 0)
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
        collapsed = section_break("input", "INPUT")
      else
        new_section()
        collapsed = draw_section_label(ctx, "Track Input FX", nil, input_fx_count, section_accent_color(settings, track), "input", (math.floor(tonumber(settings.panel_name_alpha) or 100)) / 100)
        if input_fx_count == 0 and not collapsed then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No input FX on this track.") end
      end
      if not collapsed then
        local input_chain = make_fx_chain(track, take, "input")
        render_chain = input_chain
        if horizontal then
          render_fx_nodes_h(build_input_fx_tree(input_chain, input_fx_count))
        else
          render_fx_nodes(build_input_fx_tree(input_chain, input_fx_count), 0)
        end
        render_chain = make_fx_chain(track, take, "track")
        next_tile()
        draw_add_zone(app, ctx, settings, track, width, nil, "input", nil, false)
      end
    end
    local function draw_take_section()
      if not settings.show_selected_item_fx then return end
      local dragging = (state.last_external_drag ~= nil and state.last_external_drag ~= "") or internal_fx_drag_active(ctx)
      if not horizontal then
        new_section()
        if draw_section_label(ctx, "Selected Track Item FX", nil, take_fx_count, section_accent_color(settings, track), "take", (math.floor(tonumber(settings.panel_name_alpha) or 100)) / 100) then return end
      end
      if selected_item and item_on_track == false then
        if not horizontal then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Selected item is on another track.") end
      elseif not validate_take(take) then
        if not horizontal then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No selected item with active take on this track.") end
      else
        local collapsed = false
        if horizontal then
          collapsed = section_break("take", "TAKE", get_take_label(take))
        else
          if take_fx_count == 0 then
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No item FX on selected item: " .. get_take_label(take))
          else
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, get_take_label(take))
          end
        end
        if not collapsed then
          render_chain = make_fx_chain(track, take, "item")
          if horizontal then
            render_fx_nodes_h(build_track_fx_tree(render_chain, take_fx_count, 4))
          else
            render_fx_nodes(build_track_fx_tree(render_chain, take_fx_count, 4), 0)
          end
          render_chain = make_fx_chain(track, take, "track")
          next_tile()
          draw_add_zone(app, ctx, settings, track, width, nil, "item", take, false)
        end
      end
    end
    if horizontal then
      r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + UIScale.round(5))
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
    if seam_toggle_pending then
      toggle_fx_parallel(app, seam_toggle_chain or render_chain, seam_toggle_pending)
      seam_toggle_pending = nil
      seam_toggle_chain = nil
    end
    draw_quick_add_popup(app, ctx)
    r.ImGui_EndChild(ctx)
  end
  if settings.show_macros ~= false then draw_macro_bar(app, ctx, settings, track) end
  if settings.show_info_bar ~= false then UI.draw_info_line(ctx, info_line_text(app, track, fx_count, input_fx_count, take_fx_count, item_on_track, take)) end
  handle_rack_window_external_drop(app, ctx, track)
  finish_vbar()
end

function M.request_settings()
  state.request_open_settings = true
end

return M