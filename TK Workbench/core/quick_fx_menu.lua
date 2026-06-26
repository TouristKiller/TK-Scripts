local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")

local M = {}

local PARSER_PATH = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
local FX_ROOT = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/"
local WORKBENCH_ROOT = r.GetResourcePath() .. "/Scripts/TK Scripts/TK Workbench/"
local RECENT_PATH = FX_ROOT .. "recent_plugins.txt"
local SHARED_FAVORITES_PATH = FX_ROOT .. "favorite_plugins.txt"
local LOCAL_FAVORITES_PATH = WORKBENCH_ROOT .. "plugin_browser_favorites.txt"
local FXCHAINS_ROOT = r.GetResourcePath() .. "/FXChains"

local state = {
  plugins = {},
  groups = { all = {}, developer = {}, category = {}, folders = {}, types = {} },
  recent = {},
  favorites = {},
  fxchains = {},
  filter_cache = {},
  parser_loaded = false,
  loaded = false,
  load_error = nil,
  search = "",
  list_hash = "",
  fxchain_hash = "",
  popup_open = false,
  on_pick = nil
}

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

local function resolve_favorites_path()
  if file_exists(SHARED_FAVORITES_PATH) then return SHARED_FAVORITES_PATH end
  return LOCAL_FAVORITES_PATH
end

local function item_label(item)
  if type(item) == "table" then
    return item.label or item.name or item.payload or ""
  end
  return item or ""
end

local function item_payload(item)
  if type(item) == "table" then
    return tostring(item.payload or item.name or item.label or "")
  end
  return tostring(item or "")
end

local function source_hash()
  return tostring(#state.plugins) .. "|" .. tostring(#state.recent) .. "|" .. tostring(#state.favorites) .. "|" .. tostring(#state.fxchains)
end

local function group_kind_for_category(name)
  local upper = tostring(name or ""):upper()
  if upper == "ALL PLUGINS" then return "all" end
  if upper == "DEVELOPER" then return "developer" end
  if upper == "CATEGORY" then return "category" end
  if upper == "FOLDERS" then return "folders" end
  return nil
end

local function build_groups(categories)
  local groups = { all = {}, developer = {}, category = {}, folders = {} }
  if type(categories) ~= "table" then return groups end
  for _, category in ipairs(categories) do
    local kind = group_kind_for_category(category and category.name)
    if kind and type(category.list) == "table" then
      for _, entry in ipairs(category.list) do
        local label = tostring(entry and entry.name or "")
        local plugins = type(entry and entry.fx) == "table" and entry.fx or {}
        if label ~= "" then
          groups[kind][#groups[kind] + 1] = { label = label, plugins = plugins }
        end
      end
      table.sort(groups[kind], function(left, right)
        return tostring(left.label):lower() < tostring(right.label):lower()
      end)
    end
  end
  return groups
end

local function build_type_groups(plugin_list)
  local order = { "CLAP", "CLAPi", "VST", "VSTi", "VST3", "VST3i", "JS", "Instrument" }
  local buckets = {}
  for _, key in ipairs(order) do buckets[key] = {} end
  for _, name in ipairs(plugin_list or {}) do
    local text = item_label(name)
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

local function load_user_lists()
  state.recent = read_lines(RECENT_PATH)
  state.favorites = read_lines(resolve_favorites_path())
  state.list_hash = source_hash()
  state.filter_cache = {}
end

local function collect_fxchain_entries(folder_path, relative_path, result)
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
    collect_fxchain_entries(child_folder, child_relative, result)
    dir_index = dir_index + 1
  end
  return result
end

local function load_fxchains()
  local result = {}
  collect_fxchain_entries(FXCHAINS_ROOT, "", result)
  table.sort(result, function(left, right)
    return item_label(left):lower() < item_label(right):lower()
  end)
  state.fxchains = result
  state.fxchain_hash = tostring(#result)
  state.filter_cache = {}
  return result
end

local function load_parser(force_scan)
  state.load_error = nil
  if not file_exists(PARSER_PATH) then
    state.parser_loaded = false
    state.load_error = "Sexan parser not found"
    state.plugins = {}
    state.groups = { all = {}, developer = {}, category = {}, folders = {}, types = {} }
    return false
  end
  if not state.parser_loaded then
    local ok, err = pcall(dofile, PARSER_PATH)
    if not ok then
      state.parser_loaded = false
      state.load_error = tostring(err)
      return false
    end
    state.parser_loaded = true
  end
  if type(ReadFXFile) ~= "function" then
    state.load_error = "ReadFXFile is not available"
    return false
  end
  local plugin_list, categories
  if force_scan and type(MakeFXFiles) == "function" then
    local ok_scan, scanned, scanned_categories = pcall(MakeFXFiles)
    if ok_scan then
      plugin_list = scanned
      categories = scanned_categories
    else
      state.load_error = tostring(scanned)
    end
  end
  if not plugin_list then
    local ok_read, read_plugins, read_categories = pcall(ReadFXFile)
    if ok_read then
      plugin_list = read_plugins
      categories = read_categories
    else
      state.load_error = tostring(read_plugins)
    end
  end
  if type(plugin_list) ~= "table" then plugin_list = {} end
  state.plugins = plugin_list
  state.groups = build_groups(categories)
  state.groups.types = build_type_groups(state.plugins)
  load_user_lists()
  return #state.plugins > 0
end

local function ensure_loaded()
  if state.loaded then return end
  load_parser(false)
  load_fxchains()
  state.loaded = true
end

local function collect_source_plugins(source)
  if source == "Favorites" then return state.favorites end
  if source == "Recent" then return state.recent end
  if source == "All Plugins" then return state.plugins end
  if source == "FXChains" then return state.fxchains end
  return state.plugins
end

local function match_plugin(name, search_term)
  local plugin_name = item_label(name)
  if plugin_name == "" then return false end
  local term = tostring(search_term or ""):lower()
  if term == "" then return true end
  local payload = item_payload(name)
  return (plugin_name .. " " .. payload):lower():find(term, 1, true) ~= nil
end

local function filtered_list(plugins, search_term)
  local result = {}
  for _, name in ipairs(plugins or {}) do
    if match_plugin(name, search_term) then result[#result + 1] = name end
  end
  table.sort(result, function(left, right)
    return item_label(left):lower() < item_label(right):lower()
  end)
  return result
end

local function cached_filtered_list(cache_key, plugins, search_term)
  local cache = state.filter_cache
  local key = tostring(cache_key or "") .. "\31" .. tostring(search_term or "")
  local cached = cache[key]
  if cached ~= nil then return cached end
  local filtered = filtered_list(plugins, search_term)
  cache[key] = filtered
  return filtered
end

local function add_recent(name)
  if not name or name == "" then return end
  for index = #state.recent, 1, -1 do
    if state.recent[index] == name then table.remove(state.recent, index) end
  end
  table.insert(state.recent, 1, name)
  while #state.recent > 40 do table.remove(state.recent) end
  local file = io.open(RECENT_PATH, "w")
  if file then
    for _, line in ipairs(state.recent) do file:write(line .. "\n") end
    file:close()
  end
end

local function pick(payload)
  if not payload or payload == "" then return end
  if state.on_pick then state.on_pick(payload) end
  add_recent(payload)
end

local function menu_plugin_items(ctx, id_prefix, plugins, search_term, max_items)
  local list = cached_filtered_list(id_prefix, plugins, search_term)
  local shown = 0
  local cap = tonumber(max_items) or 280
  for index, plugin_name in ipairs(list) do
    if shown >= cap then break end
    local label = item_label(plugin_name) .. "##" .. tostring(id_prefix) .. "_" .. tostring(index)
    if r.ImGui_MenuItem(ctx, label) then
      pick(item_payload(plugin_name))
      r.ImGui_CloseCurrentPopup(ctx)
      return true
    end
    shown = shown + 1
  end
  if #list == 0 then
    r.ImGui_MenuItem(ctx, "No results", nil, false, false)
  elseif #list > cap then
    r.ImGui_Separator(ctx)
    r.ImGui_MenuItem(ctx, "Refine search...", nil, false, false)
  end
  return false
end

local function menu_group_source(ctx, source_label, group_kind, search_term)
  local groups = state.groups[group_kind] or {}
  if not r.ImGui_BeginMenu(ctx, source_label .. "##tk_qfx_src_" .. tostring(group_kind)) then return false end
  local searching = search_term ~= nil and search_term ~= ""
  local any = false
  for group_index, group in ipairs(groups) do
    local plugins = group.plugins or {}
    local count = #plugins
    local group_prefix = group_kind .. "_" .. tostring(group_index)
    if searching then
      plugins = cached_filtered_list(group_prefix, group.plugins or {}, search_term)
      count = #plugins
    end
    if count > 0 then
      any = true
      local item_search = searching and search_term or ""
      local sub_label = tostring(group.label or "Group") .. " (" .. tostring(count) .. ")##tk_qfx_group_" .. tostring(group_kind) .. "_" .. tostring(group_index)
      if r.ImGui_BeginMenu(ctx, sub_label) then
        if menu_plugin_items(ctx, group_prefix, group.plugins or {}, item_search, 220) then
          r.ImGui_EndMenu(ctx)
          r.ImGui_EndMenu(ctx)
          return true
        end
        r.ImGui_EndMenu(ctx)
      end
    end
  end
  if not any then r.ImGui_MenuItem(ctx, "No results", nil, false, false) end
  r.ImGui_EndMenu(ctx)
  return false
end

function M.request_open(on_pick)
  state.on_pick = on_pick
  state.popup_open = true
  ensure_loaded()
end

function M.draw(ctx, popup_id)
  popup_id = popup_id or "##tk_quick_fx_menu"
  if state.popup_open then
    state.popup_open = false
    if state.list_hash ~= source_hash() then load_user_lists() end
    r.ImGui_OpenPopup(ctx, popup_id)
  end
  if not r.ImGui_BeginPopup(ctx, popup_id) then return end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(110))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##tk_qfx_search", "Search plugin...", state.search or "")
  if changed then state.search = value or "" end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "X##tk_qfx_clear") then state.search = "" end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Rescan##tk_qfx_rescan") then load_parser(true) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "FXChains##tk_qfx_fxchains_refresh") then load_fxchains() end
  if state.load_error and state.load_error ~= "" then
    r.ImGui_TextColored(ctx, Theme.colors.warning, state.load_error)
  end
  r.ImGui_Separator(ctx)
  local search_term = state.search or ""
  if search_term ~= "" then
    local search_list = cached_filtered_list("search", state.plugins, search_term)
    local search_label = "Search (" .. tostring(#search_list) .. ")##tk_qfx_search_menu"
    if r.ImGui_BeginMenu(ctx, search_label) then
      if menu_plugin_items(ctx, "search", state.plugins, search_term, 320) then
        r.ImGui_EndMenu(ctx)
        r.ImGui_EndPopup(ctx)
        return
      end
      r.ImGui_EndMenu(ctx)
    end
    r.ImGui_Separator(ctx)
  end
  if r.ImGui_BeginMenu(ctx, "Favorites##tk_qfx_favorites") then
    if menu_plugin_items(ctx, "favorites", state.favorites, search_term, 220) then
      r.ImGui_EndMenu(ctx)
      r.ImGui_EndPopup(ctx)
      return
    end
    r.ImGui_EndMenu(ctx)
  end
  if r.ImGui_BeginMenu(ctx, "Recent##tk_qfx_recent") then
    if menu_plugin_items(ctx, "recent", state.recent, search_term, 220) then
      r.ImGui_EndMenu(ctx)
      r.ImGui_EndPopup(ctx)
      return
    end
    r.ImGui_EndMenu(ctx)
  end
  if menu_group_source(ctx, "All Plugins", "types", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if menu_group_source(ctx, "Category", "category", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if menu_group_source(ctx, "Developer", "developer", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if menu_group_source(ctx, "Folders", "folders", search_term) then
    r.ImGui_EndPopup(ctx)
    return
  end
  if r.ImGui_BeginMenu(ctx, "FXChains##tk_qfx_fxchains") then
    if menu_plugin_items(ctx, "fxchains", state.fxchains, search_term, 180) then
      r.ImGui_EndMenu(ctx)
      r.ImGui_EndPopup(ctx)
      return
    end
    r.ImGui_EndMenu(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

return M
