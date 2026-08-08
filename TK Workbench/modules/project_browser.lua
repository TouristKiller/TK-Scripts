local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")
local UI = require("core.ui")
local json = require("core.json")

local M = {
  id = "project_browser",
  title = "Project Browser",
  icon = "PRJ",
  version = "0.1.0"
}

local resource_path = r.GetResourcePath()
local locations_path = resource_path .. "/Scripts/TK_project_browser_locations.txt"
local project_template_locations_path = resource_path .. "/Scripts/TK_project_template_browser_locations.txt"
local track_template_locations_path = resource_path .. "/Scripts/TK_track_template_browser_locations.txt"
local project_covers_path = resource_path .. "/Scripts/TK Scripts/FX/ProjectCovers/"
local project_preview_active_path = resource_path .. "/Scripts/TK Scripts/FX/project_preview_active.json"

local modes = {
  projects = { label = "Projects", short = "Projects", locations_path = locations_path, extension = "rpp", item_label = "project", plural = "projects" },
  project_templates = { label = "Project Templates", short = "Proj Tpl", locations_path = project_template_locations_path, extension = "rpp", item_label = "project template", plural = "project templates" },
  track_templates = { label = "Track Templates", short = "Track Tpl", locations_path = track_template_locations_path, extension = "rtracktemplate", item_label = "track template", plural = "track templates" }
}

local mode_order = { "projects", "project_templates", "track_templates" }

local defaults = {
  browser_mode = "projects",
  search_term = "",
  current_location = "",
  current_locations = {},
  pending_location = "",
  pending_locations = {},
  recursive = true,
  folder_view = true,
  compact_list = false,
  -- 0 keeps the list. Anything above the floor switches to tiles of about this
  -- width, with the column count following from however wide the pane is.
  tile_size = 0,
  preview_volume = 1.0,
  folder_paths = {},
  max_depth = 5,
  -- Hides anything shallower. 0 shows everything; 1 drops the projects lying
  -- loose in the scan root and keeps only what sits inside a folder.
  min_depth = 0,
  show_detail_panel = true,
  show_playback_panel = true,
  show_hover_info = true,
  show_recent = false,
  recent_count = 15,
  max_scan_projects = 5000,
  open_new_tab_on_double_click = false,
  sort_by = "name",
  sort_ascending = true
}

local state = {
  locations = {},
  projects = {},
  filtered = {},
  visible_entries = {},
  folder_entries = {},
  selected_index = nil,
  selected_project = nil,
  selected_folder = nil,
  project_list_keyboard_focus = false,
  scroll_selected_project = false,
  scan_queue = {},
  scan_seen_dirs = {},
  scan_seen_projects = {},
  scanning = false,
  scan_limited = false,
  scan_location = "",
  filter_dirty = true,
  search_changed_at = 0,
  metadata_cache = {},
  cover_queue = {},
  recent_cache = nil,
  recent_cache_limit = nil,
  cover_path_cache = {},
  preview_path_cache = {},
  preview_length_cache = {},
  preview_active = {},
  preview_active_loaded = false,
  preview = nil,
  preview_source = nil,
  preview_project_path = nil,
  preview_path = nil,
  preview_length = 0,
  preview_started_at = 0,
  manage_previews_project = nil,
  cover_image_cache = {},
  settings_popup = false,
  detail_panel_collapsed = false,
  playback_panel_collapsed = false,
  last_error = nil
}

local stop_project_preview

local image_ext = { png = true, jpg = true, jpeg = true, webp = true, bmp = true }

local function active_mode(settings)
  local mode = tostring(settings.browser_mode or "projects")
  if not modes[mode] then mode = "projects" end
  settings.browser_mode = mode
  return mode, modes[mode]
end

local function get_mode_location(settings, mode)
  settings.current_locations = type(settings.current_locations) == "table" and settings.current_locations or {}
  if mode == "projects" and (settings.current_locations[mode] == nil or settings.current_locations[mode] == "") then
    settings.current_locations[mode] = tostring(settings.current_location or "")
  end
  return tostring(settings.current_locations[mode] or "")
end

local function set_mode_location(settings, mode, value)
  settings.current_locations = type(settings.current_locations) == "table" and settings.current_locations or {}
  settings.current_locations[mode] = tostring(value or "")
  if mode == "projects" then settings.current_location = settings.current_locations[mode] end
end

local function get_mode_pending_location(settings, mode)
  settings.pending_locations = type(settings.pending_locations) == "table" and settings.pending_locations or {}
  if mode == "projects" and (settings.pending_locations[mode] == nil or settings.pending_locations[mode] == "") then
    settings.pending_locations[mode] = tostring(settings.pending_location or "")
  end
  return tostring(settings.pending_locations[mode] or "")
end

local function set_mode_pending_location(settings, mode, value)
  settings.pending_locations = type(settings.pending_locations) == "table" and settings.pending_locations or {}
  settings.pending_locations[mode] = tostring(value or "")
  if mode == "projects" then settings.pending_location = settings.pending_locations[mode] end
end

local function clean_relative_folder(path)
  path = tostring(path or ""):gsub("\\", "/"):gsub("/+$", ""):gsub("^/+", "")
  if path == "." then return "" end
  return path
end

local function get_mode_folder_path(settings, mode)
  settings.folder_paths = type(settings.folder_paths) == "table" and settings.folder_paths or {}
  return clean_relative_folder(settings.folder_paths[mode] or "")
end

local function set_mode_folder_path(settings, mode, value)
  settings.folder_paths = type(settings.folder_paths) == "table" and settings.folder_paths or {}
  settings.folder_paths[mode] = clean_relative_folder(value or "")
end

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local target = {}
  for key, child in pairs(value) do target[key] = copy_default(child) end
  return target
end

local function ensure_settings(app)
  app.settings.project_browser = app.settings.project_browser or {}
  local settings = app.settings.project_browser
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  settings.max_depth = math.max(0, math.min(12, math.floor(tonumber(settings.max_depth) or defaults.max_depth)))
  settings.min_depth = math.max(0, math.min(settings.max_depth, math.floor(tonumber(settings.min_depth) or 0)))
  settings.recent_count = math.max(1, math.min(50, math.floor(tonumber(settings.recent_count) or defaults.recent_count)))
  settings.show_recent = settings.show_recent == true
  settings.show_detail_panel = settings.show_detail_panel ~= false
  settings.show_playback_panel = settings.show_playback_panel ~= false
  settings.show_hover_info = settings.show_hover_info ~= false
  settings.max_scan_projects = math.max(50, math.min(50000, math.floor(tonumber(settings.max_scan_projects) or defaults.max_scan_projects)))
  settings.recursive = settings.recursive ~= false
  settings.folder_view = settings.folder_view ~= false
  settings.compact_list = settings.compact_list == true
  settings.preview_volume = math.max(0, math.min(2, tonumber(settings.preview_volume) or defaults.preview_volume))
  settings.open_new_tab_on_double_click = settings.open_new_tab_on_double_click == true
  settings.search_term = tostring(settings.search_term or "")
  settings.pending_location = tostring(settings.pending_location or "")
  settings.current_location = tostring(settings.current_location or "")
  settings.current_locations = type(settings.current_locations) == "table" and settings.current_locations or {}
  settings.pending_locations = type(settings.pending_locations) == "table" and settings.pending_locations or {}
  settings.folder_paths = type(settings.folder_paths) == "table" and settings.folder_paths or {}
  active_mode(settings)
  if settings.sort_by ~= "path" and settings.sort_by ~= "date" then settings.sort_by = "name" end
  settings.sort_ascending = settings.sort_ascending ~= false
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function normalize_path(path)
  path = tostring(path or ""):gsub("\\", "/")
  return path:gsub("/+$", "")
end

local function join_path(folder, name)
  folder = normalize_path(folder)
  if folder == "" then return tostring(name or "") end
  return folder .. "/" .. tostring(name or "")
end

local function file_exists(path)
  if path == nil or path == "" then return false end
  if r.file_exists and r.file_exists(path) then return true end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function directory_exists(path)
  path = normalize_path(path)
  if path == "" then return false end
  local ok, _, code = os.rename(path, path)
  if ok or code == 13 then return true end
  local probe = r.EnumerateFiles and r.EnumerateFiles(path, 0)
  if probe ~= nil then return true end
  local sub = r.EnumerateSubdirectories and r.EnumerateSubdirectories(path, 0)
  return sub ~= nil
end

local function project_name(path)
  local name = tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
  return (name:gsub("%.[Rr][Pp][Pp]$", ""):gsub("%.[Rr][Tt][Rr][Aa][Cc][Kk][Tt][Ee][Mm][Pp][Ll][Aa][Tt][Ee]$", ""))
end

local function project_folder(path)
  return normalize_path(tostring(path or ""):match("^(.*)[/\\][^/\\]+$") or "")
end

local function compact_path(path)
  local folder = project_folder(path)
  if #folder > 80 then return "..." .. folder:sub(-77) end
  return folder
end

local function relative_folder(path, root)
  root = normalize_path(root)
  local folder = project_folder(path)
  if root == "" or folder == "" then return "" end
  local lower_folder = folder:lower()
  local lower_root = root:lower()
  if lower_folder == lower_root then return "" end
  if lower_folder:sub(1, #lower_root + 1) == lower_root .. "/" then return clean_relative_folder(folder:sub(#root + 2)) end
  return clean_relative_folder(folder)
end

local function direct_child_folder(rel_dir, current)
  rel_dir = clean_relative_folder(rel_dir)
  current = clean_relative_folder(current)
  if rel_dir == "" or rel_dir == current then return nil end
  if current ~= "" then
    local lower_rel = rel_dir:lower()
    local lower_current = current:lower()
    if lower_rel:sub(1, #lower_current + 1) ~= lower_current .. "/" then return nil end
    rel_dir = rel_dir:sub(#current + 2)
  end
  return rel_dir:match("^[^/]+")
end

local function folder_parent(path)
  path = clean_relative_folder(path)
  return clean_relative_folder(path:match("(.+)/[^/]+$") or "")
end

local function read_locations(mode_def)
  local result = {}
  local seen = {}
  local file = io.open(mode_def.locations_path, "r")
  if file then
    for line in file:lines() do
      local path = normalize_path(line:match("^%s*(.-)%s*$"))
      local key = path:lower()
      if path ~= "" and not seen[key] then
        seen[key] = true
        result[#result + 1] = path
      end
    end
    file:close()
  end
  return result
end

local function write_locations(mode_def, locations)
  local file = io.open(mode_def.locations_path, "w")
  if not file then return false end
  for _, path in ipairs(locations or {}) do
    if path and path ~= "" then file:write(path, "\n") end
  end
  file:close()
  return true
end

local function refresh_locations(settings)
  local mode, mode_def = active_mode(settings)
  state.locations = read_locations(mode_def)
  local current = get_mode_location(settings, mode)
  if current == "" and state.locations[1] then current = state.locations[1]; set_mode_location(settings, mode, current) end
  local found = current == ""
  for _, path in ipairs(state.locations) do
    if path == current then found = true; break end
  end
  if not found then set_mode_location(settings, mode, state.locations[1] or ""); set_mode_folder_path(settings, mode, "") end
end

local function add_location(app, settings, path)
  local mode, mode_def = active_mode(settings)
  path = normalize_path(path)
  if path == "" then return false end
  if not directory_exists(path) then state.last_error = "Folder not found"; return false end
  local key = path:lower()
  for _, existing in ipairs(state.locations) do
    if existing:lower() == key then set_mode_location(settings, mode, existing); set_mode_folder_path(settings, mode, ""); set_mode_pending_location(settings, mode, ""); if app.save_settings then app.save_settings() end; return true end
  end
  state.locations[#state.locations + 1] = path
  write_locations(mode_def, state.locations)
  set_mode_location(settings, mode, path)
  set_mode_folder_path(settings, mode, "")
  set_mode_pending_location(settings, mode, "")
  if app.save_settings then app.save_settings() end
  return true
end

local function remove_current_location(app, settings)
  local mode, mode_def = active_mode(settings)
  local current = get_mode_location(settings, mode)
  if current == "" then return end
  for index = #state.locations, 1, -1 do
    if state.locations[index] == current then table.remove(state.locations, index) end
  end
  write_locations(mode_def, state.locations)
  set_mode_location(settings, mode, state.locations[1] or "")
  set_mode_folder_path(settings, mode, "")
  if app.save_settings then app.save_settings() end
end

local fuzzy_norm_cache = {}
local function fuzzy_normalize(value)
  value = tostring(value or "")
  local cached = fuzzy_norm_cache[value]
  if cached then return cached end
  local normalized = value:lower():gsub("[%-_%.%s]+", "")
  fuzzy_norm_cache[value] = normalized
  return normalized
end

local function fuzzy_find(haystack, needle)
  if not needle or needle == "" then return true end
  if not haystack then return false end
  local needle_lower = needle:lower()
  local hay_lower = haystack:lower()
  if hay_lower:find(needle_lower, 1, true) then return true end
  if needle_lower:find("%s") then
    local hay_norm = fuzzy_normalize(haystack)
    for token in needle_lower:gmatch("%S+") do
      local compact = token:gsub("[%-_%.]+", "")
      if compact ~= "" and not hay_lower:find(token, 1, true) and not hay_norm:find(compact, 1, true) then return false end
    end
    return true
  end
  if needle_lower:find("[%-_%.]") then
    local compact = needle_lower:gsub("[%-_%.%s]+", "")
    return compact ~= "" and fuzzy_normalize(haystack):find(compact, 1, true) ~= nil
  end
  return false
end

local function plausible_file_time(value)
  value = tonumber(value) or 0
  if value >= 946684800 and value <= 4102444800 then return value end
  return 0
end

local function project_file_date_value(path)
  if not r.JS_File_Stat then return 0 end
  local ok, retval, _, _, _, datetime = pcall(r.JS_File_Stat, path)
  if not ok or not retval then return 0 end
  return datetime or 0
end

local function project_date(value)
  local file_time = plausible_file_time(value)
  if file_time > 0 then return os.date("%Y-%m-%d %H:%M", file_time) or "" end
  value = tostring(value or "")
  if value == "0" then return "" end
  return value
end

local function project_date_sort_value(value)
  local file_time = plausible_file_time(value)
  if file_time > 0 then return string.format("%010d", file_time) end
  value = tostring(value or ""):lower()
  if value == "0" then return "" end
  return value
end

local function make_project(path, mode, root)
  path = normalize_path(path)
  local date_sort = project_file_date_value(path)
  return { path = path, name = project_name(path), folder = project_folder(path), rel_dir = relative_folder(path, root or state.scan_location), date = project_date(date_sort), date_sort = date_sort, mode = mode or "projects" }
end

local function refresh_project_date(project)
  if not project or not project.path then return end
  local date_sort = project_file_date_value(project.path)
  project.date_sort = date_sort
  project.date = project_date(date_sort)
end

local function sort_projects(list, settings)
  local field = settings.sort_by or "name"
  local ascending = settings.sort_ascending ~= false
  if field == "date" then
    for _, project in ipairs(list) do refresh_project_date(project) end
  end
  table.sort(list, function(a, b)
    if field == "date" then
      local av = project_date_sort_value(a.date_sort)
      local bv = project_date_sort_value(b.date_sort)
      if av ~= bv then
        if ascending then return av < bv end
        return av > bv
      end
    end
    local av = tostring(a[field] or a.name or ""):lower()
    local bv = tostring(b[field] or b.name or ""):lower()
    if av == bv then return tostring(a.path or ""):lower() < tostring(b.path or ""):lower() end
    if ascending then return av < bv end
    return av > bv
  end)
end

-- How far below the scan root a project sits: 0 for one lying loose in the root
-- itself, 1 one folder down, and so on. Same counting as max_depth uses while
-- scanning, so the two settings mean the same thing by the same numbers.
-- REAPER keeps its recent files in reaper.ini under [Recent], newest first as
-- recent01. Entries pointing at something that no longer exists are dropped
-- rather than shown as dead rows. Cached, because apply_filter runs on every
-- keystroke in the search box and this reads a file.
local function read_recent_projects(limit)
  limit = math.max(1, math.floor(tonumber(limit) or 15))
  if state.recent_cache and state.recent_cache_limit == limit then return state.recent_cache end
  local ini = r.get_ini_file and r.get_ini_file() or nil
  if not ini or ini == "" then ini = r.GetResourcePath() .. "/reaper.ini" end
  local list = {}
  local file = io.open(ini, "r")
  if file then
    local found = {}
    local in_section = false
    for line in file:lines() do
      local header = line:match("^%s*%[(.-)%]%s*$")
      if header then
        in_section = header:lower() == "recent"
      elseif in_section then
        local key, value = line:match("^%s*(recent%d+)%s*=%s*(.-)%s*$")
        if key and value and value ~= "" then found[#found + 1] = { key = key, path = value } end
      end
    end
    file:close()
    table.sort(found, function(a, b) return a.key < b.key end)
    for _, entry in ipairs(found) do
      if #list >= limit then break end
      if file_exists(entry.path) then list[#list + 1] = make_project(entry.path, "projects", "") end
    end
  end
  state.recent_cache = list
  state.recent_cache_limit = limit
  return list
end

local function project_depth(project)
  local rel = clean_relative_folder(project.rel_dir or "")
  if rel == "" then return 0 end
  local depth = 1
  for _ in rel:gmatch("/") do depth = depth + 1 end
  return depth
end

local function apply_filter(settings)
  state.filtered = {}
  state.visible_entries = {}
  state.folder_entries = {}
  local term = tostring(settings.search_term or "")
  local mode = active_mode(settings)
  -- Recent is a flat list from REAPER's own history, so neither the folder view
  -- nor the depth filter mean anything while it is on.
  local recent = settings.show_recent == true
  local source = recent and read_recent_projects(settings.recent_count) or state.projects
  local folder_view = settings.folder_view == true and term == "" and not recent
  local current_folder = get_mode_folder_path(settings, mode)
  local folder_map = {}
  local min_depth = recent and 0 or math.max(0, math.floor(tonumber(settings.min_depth) or 0))
  for _, project in ipairs(source) do
    project.rel_dir = project.rel_dir or relative_folder(project.path, state.scan_location)
    local deep_enough = min_depth == 0 or project_depth(project) >= min_depth
    local haystack = table.concat({ project.name or "", project.path or "", project.folder or "" }, " ")
    if deep_enough and fuzzy_find(haystack, term) then
      if folder_view then
        local child_name = direct_child_folder(project.rel_dir, current_folder)
        if child_name then
          local child_path = current_folder == "" and child_name or (current_folder .. "/" .. child_name)
          local key = child_path:lower()
          local folder = folder_map[key]
          if not folder then
            folder = { name = child_name, path = child_path, count = 0 }
            folder_map[key] = folder
            state.folder_entries[#state.folder_entries + 1] = folder
          end
          folder.count = folder.count + 1
        elseif clean_relative_folder(project.rel_dir) == current_folder then
          state.filtered[#state.filtered + 1] = project
        end
      else
        state.filtered[#state.filtered + 1] = project
      end
    end
  end
  table.sort(state.folder_entries, function(a, b) return tostring(a.name or ""):lower() < tostring(b.name or ""):lower() end)
  sort_projects(state.filtered, settings)
  if folder_view and current_folder ~= "" then
    state.visible_entries[#state.visible_entries + 1] = { kind = "folder", folder = { name = "..", path = folder_parent(current_folder), count = 0, up = true } }
  end
  for _, folder in ipairs(state.folder_entries) do state.visible_entries[#state.visible_entries + 1] = { kind = "folder", folder = folder } end
  for _, project in ipairs(state.filtered) do state.visible_entries[#state.visible_entries + 1] = { kind = "project", project = project } end
  if state.selected_project then
    local selected_found = false
    for index, entry in ipairs(state.visible_entries) do
      if entry.kind == "project" and entry.project and entry.project.path == state.selected_project.path then
        state.selected_index = index
        state.selected_project = entry.project
        selected_found = true
        break
      end
    end
    if not selected_found then state.selected_index = nil; state.selected_project = nil; state.selected_folder = nil end
  end
  if state.selected_folder then
    local selected_found = false
    for index, entry in ipairs(state.visible_entries) do
      local folder = entry.kind == "folder" and entry.folder or nil
      if folder and folder.path == state.selected_folder.path and folder.up == state.selected_folder.up then
        state.selected_index = index
        state.selected_folder = folder
        selected_found = true
        break
      end
    end
    if not selected_found then state.selected_index = nil; state.selected_folder = nil end
  end
  if not state.selected_project and not state.selected_folder then
    for index, entry in ipairs(state.visible_entries) do
      if entry.kind == "project" and entry.project then
        state.selected_index = index
        state.selected_project = entry.project
        break
      end
    end
  end
  state.filter_dirty = false
end

-- Destroying an image is not enough: while it stays attached it keeps occupying
-- one of the context's attachment slots, and running out of those is what threw
-- "ImGui_Attach: exceeded maximum object attachment limit" once the tile view
-- put dozens of covers on screen at once. Detach first, then destroy.
local function release_cover_entry(ctx, path)
  local entry = state.cover_image_cache[path]
  if not entry then return end
  state.cover_image_cache[path] = nil
  if entry.image then
    if r.ImGui_Detach then pcall(r.ImGui_Detach, ctx, entry.image) end
    if r.ImGui_DestroyImage then pcall(r.ImGui_DestroyImage, ctx, entry.image) end
  end
end

local function clear_cover_image_cache(ctx)
  for path in pairs(state.cover_image_cache) do
    release_cover_entry(ctx, path)
  end
  state.cover_queue = {}
end

local function clear_project_cache(ctx)
  state.metadata_cache = {}
  state.cover_path_cache = {}
  state.preview_path_cache = {}
  state.preview_length_cache = {}
  clear_cover_image_cache(ctx)
end

local function start_scan(app, settings)
  local mode, mode_def = active_mode(settings)
  state.projects = {}
  state.filtered = {}
  state.visible_entries = {}
  state.folder_entries = {}
  state.selected_index = nil
  state.selected_project = nil
  state.selected_folder = nil
  state.scan_queue = {}
  state.scan_seen_dirs = {}
  state.scan_seen_projects = {}
  state.scan_limited = false
  state.last_error = nil
  clear_project_cache(app.ctx)
  refresh_locations(settings)
  local root = normalize_path(get_mode_location(settings, mode))
  state.scan_location = root
  if root ~= "" and directory_exists(root) then
    state.scan_queue[#state.scan_queue + 1] = { path = root, depth = 0 }
    state.scan_seen_dirs[root:lower()] = true
    state.scanning = true
  else
    state.scanning = false
    state.last_error = root == "" and "Add a " .. mode_def.item_label .. " location" or mode_def.label .. " location not found"
  end
  state.filter_dirty = true
end

local function scan_directory(settings, entry)
  local mode, mode_def = active_mode(settings)
  local folder = entry.path
  local file_index = 0
  while #state.projects < settings.max_scan_projects do
    local name = r.EnumerateFiles(folder, file_index)
    if not name then break end
    if name:lower():match("%." .. mode_def.extension .. "$") then
      local path = join_path(folder, name)
      local key = path:lower()
      if not state.scan_seen_projects[key] then
        state.scan_seen_projects[key] = true
        state.projects[#state.projects + 1] = make_project(path, mode, state.scan_location)
      end
    end
    file_index = file_index + 1
  end
  if #state.projects >= settings.max_scan_projects then state.scan_limited = true; return end
  if settings.recursive and entry.depth < settings.max_depth then
    local dir_index = 0
    while true do
      local name = r.EnumerateSubdirectories(folder, dir_index)
      if not name then break end
      local child = join_path(folder, name)
      local key = child:lower()
      if not state.scan_seen_dirs[key] then
        state.scan_seen_dirs[key] = true
        state.scan_queue[#state.scan_queue + 1] = { path = child, depth = entry.depth + 1 }
      end
      dir_index = dir_index + 1
    end
  end
end

local function scan_step(settings)
  if not state.scanning then return end
  local processed = 0
  while processed < 8 and #state.scan_queue > 0 and not state.scan_limited do
    local entry = table.remove(state.scan_queue, 1)
    if entry then scan_directory(settings, entry) end
    processed = processed + 1
  end
  state.filter_dirty = true
  if #state.scan_queue == 0 or state.scan_limited then state.scanning = false end
end

local function format_project_length(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return "" end
  local total = math.floor(seconds + 0.5)
  local hours = math.floor(total / 3600)
  local minutes = math.floor((total % 3600) / 60)
  local secs = total % 60
  if hours > 0 then return string.format("%d:%02d:%02d", hours, minutes, secs) end
  return string.format("%d:%02d", minutes, secs)
end

local function load_project_preview_active()
  if state.preview_active_loaded then return end
  state.preview_active_loaded = true
  local file = io.open(project_preview_active_path, "r")
  if not file then return end
  local content = file:read("*a")
  file:close()
  local ok, data = pcall(json.decode, content)
  state.preview_active = ok and type(data) == "table" and data or {}
end

local function active_preview_filename(project_path)
  load_project_preview_active()
  local value = state.preview_active[project_path]
  if value and value ~= "" then return value end
  return nil
end

local function save_project_preview_active()
  local file = io.open(project_preview_active_path, "w")
  if not file then return false end
  file:write(json.encode(state.preview_active or {}))
  file:close()
  return true
end

local function set_active_preview_filename(project_path, basename)
  if not project_path then return end
  load_project_preview_active()
  state.preview_active[project_path] = basename
  save_project_preview_active()
  state.preview_path_cache[project_path] = nil
end

local function clear_active_preview_filename(project_path)
  if not project_path then return end
  load_project_preview_active()
  state.preview_active[project_path] = nil
  save_project_preview_active()
  state.preview_path_cache[project_path] = nil
end

local function clear_project_preview_cache(project_path)
  if project_path then state.preview_path_cache[project_path] = nil else state.preview_path_cache = {} end
  state.preview_length_cache = {}
end

local function project_preview_base(project)
  if not project then return "" end
  return project_name(project.path or project.name or "")
end

local function list_project_previews(project)
  local list = {}
  if not project or not project.path then return list end
  local dir = project.folder or project_folder(project.path)
  local base = project_preview_base(project)
  if dir == "" or base == "" then return list end
  local prefix = base .. ".tkprev."
  local prefix_l = prefix:lower()
  local allowed_ext = { wav = true, mp3 = true, flac = true, ogg = true, aif = true, aiff = true }
  local index = 0
  while true do
    local name = r.EnumerateFiles(dir, index)
    if not name then break end
    local suffix = name:sub(#prefix + 1)
    local ext = suffix:match("%.([^%.]+)$")
    local has_allowed_ext = ext and allowed_ext[ext:lower()]
    local extensionless = suffix ~= "" and not suffix:find("%.")
    if name:lower():sub(1, #prefix_l) == prefix_l and (has_allowed_ext or extensionless) then
      local path = join_path(dir, name)
      local stamp_part = has_allowed_ext and suffix:sub(1, -(#ext + 2)) or suffix
      local timestamp = tonumber(stamp_part:match("^(%d+)")) or 0
      local modified = 0
      if r.JS_File_Stat then
        local ok_call, ok_stat, _, _, mtime = pcall(r.JS_File_Stat, path)
        if ok_call and ok_stat then modified = tonumber(mtime) or 0 end
      end
      list[#list + 1] = { name = name, path = path, score = timestamp * 1e9 + modified }
    end
    index = index + 1
  end
  table.sort(list, function(a, b) return a.score > b.score end)
  return list
end

local function project_preview_path(project)
  if not project or not project.path then return nil end
  if state.preview_path_cache[project.path] ~= nil then return state.preview_path_cache[project.path] or nil end
  local dir = project.folder or project_folder(project.path)
  local base = project_preview_base(project)
  if dir ~= "" then
    local project_file = project.path:match("([^/\\]+)$") or (base .. ".rpp")
    local direct_proxies = { join_path(dir, project_file .. "-PROX"), join_path(dir, project_file .. "-prox") }
    for _, proxy in ipairs(direct_proxies) do
      if file_exists(proxy) then state.preview_path_cache[project.path] = proxy; return proxy end
    end
  end
  local listed = list_project_previews(project)
  if listed[1] and listed[1].path then
    state.preview_path_cache[project.path] = listed[1].path
    return listed[1].path
  end
  if dir ~= "" and base ~= "" then
    local prefix = base .. ".tkprev."
    local prefix_l = prefix:lower()
    local allowed_ext = { wav = true, mp3 = true, flac = true, ogg = true, aif = true, aiff = true }
    local override = active_preview_filename(project.path)
    if override and override:lower():sub(1, #prefix_l) == prefix_l then
      local path = join_path(dir, override)
      if file_exists(path) then state.preview_path_cache[project.path] = path; return path end
    end
    local newest, newest_score = nil, -1
    local index = 0
    while true do
      local name = r.EnumerateFiles(dir, index)
      if not name then break end
      local suffix = name:sub(#prefix + 1)
      local ext = suffix:match("%.([^%.]+)$")
      local has_allowed_ext = ext and allowed_ext[ext:lower()]
      local extensionless = suffix ~= "" and not suffix:find("%.")
      if name:lower():sub(1, #prefix_l) == prefix_l and (has_allowed_ext or extensionless) then
        local path = join_path(dir, name)
        local stamp_part = has_allowed_ext and suffix:sub(1, -(#ext + 2)) or suffix
        local timestamp = tonumber(stamp_part:match("^(%d+)")) or 0
        local modified = 0
        if r.JS_File_Stat then
          local ok_call, ok_stat, _, _, mtime = pcall(r.JS_File_Stat, path)
          if ok_call and ok_stat then modified = tonumber(mtime) or 0 end
        end
        local score = timestamp * 1e9 + modified
        if score >= newest_score then newest, newest_score = path, score end
      end
      index = index + 1
    end
    if newest then state.preview_path_cache[project.path] = newest; return newest end
  end
  local proxies = { project.path .. "-PROX", project.path .. "-prox" }
  for _, proxy in ipairs(proxies) do
    if file_exists(proxy) then state.preview_path_cache[project.path] = proxy; return proxy end
  end
  if dir ~= "" then
    local project_file = project.path:match("([^/\\]+)$") or (base .. ".rpp")
    local expected_proxy = (project_file .. "-prox"):lower()
    local index = 0
    while true do
      local name = r.EnumerateFiles(dir, index)
      if not name then break end
      if name:lower() == expected_proxy then
        local proxy = join_path(dir, name)
        state.preview_path_cache[project.path] = proxy
        return proxy
      end
      index = index + 1
    end
  end
  return nil
end

local function media_source_length(source)
  if not source or not r.GetMediaSourceLength then return 0 end
  local ok, length = pcall(r.GetMediaSourceLength, source)
  if ok then return tonumber(length) or 0 end
  return 0
end

local function project_preview_length(path)
  if not path or path == "" then return 0 end
  if state.preview_length_cache[path] ~= nil then return state.preview_length_cache[path] end
  local length = 0
  if r.PCM_Source_CreateFromFile then
    local ok_source, source = pcall(r.PCM_Source_CreateFromFile, path)
    if ok_source and source then
      length = media_source_length(source)
      if r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, source) end
    end
  end
  state.preview_length_cache[path] = length
  return length
end

stop_project_preview = function()
  if state.preview and r.CF_Preview_Stop then pcall(r.CF_Preview_Stop, state.preview) end
  if state.preview_source and r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, state.preview_source) end
  state.preview = nil
  state.preview_source = nil
  state.preview_project_path = nil
  state.preview_path = nil
  state.preview_length = 0
  state.preview_started_at = 0
end

local function start_project_preview(app, settings, project)
  if not r.CF_CreatePreview or not r.CF_Preview_Play or not r.PCM_Source_CreateFromFile then
    app.status = "SWS preview API not available"
    return false
  end
  local path = project_preview_path(project)
  if not path then app.status = "No project preview found"; return false end
  stop_project_preview()
  local ok_source, source = pcall(r.PCM_Source_CreateFromFile, path)
  if not ok_source or not source then app.status = "Could not open project preview"; return false end
  local ok_preview, preview = pcall(r.CF_CreatePreview, source)
  if not ok_preview or not preview then
    if r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, source) end
    app.status = "Could not create project preview"
    return false
  end
  state.preview = preview
  state.preview_source = source
  state.preview_project_path = project.path
  state.preview_path = path
  state.preview_length = media_source_length(source)
  if state.preview_length <= 0 then state.preview_length = project_preview_length(path) end
  state.preview_started_at = r.time_precise and r.time_precise() or os.clock()
  if r.CF_Preview_SetValue then r.CF_Preview_SetValue(preview, "D_VOLUME", settings.preview_volume or defaults.preview_volume) end
  pcall(r.CF_Preview_Play, preview)
  app.status = "Playing project preview"
  return true
end

local function play_project_preview_file(app, settings, project, path)
  if not path or not file_exists(path) then app.status = "Preview file not found"; return false end
  if not r.CF_CreatePreview or not r.CF_Preview_Play or not r.PCM_Source_CreateFromFile then app.status = "SWS preview API not available"; return false end
  stop_project_preview()
  local ok_source, source = pcall(r.PCM_Source_CreateFromFile, path)
  if not ok_source or not source then app.status = "Could not open project preview"; return false end
  local ok_preview, preview = pcall(r.CF_CreatePreview, source)
  if not ok_preview or not preview then
    if r.PCM_Source_Destroy then pcall(r.PCM_Source_Destroy, source) end
    app.status = "Could not create project preview"
    return false
  end
  state.preview = preview
  state.preview_source = source
  state.preview_project_path = project.path
  state.preview_path = path
  state.preview_length = media_source_length(source)
  if state.preview_length <= 0 then state.preview_length = project_preview_length(path) end
  state.preview_started_at = r.time_precise and r.time_precise() or os.clock()
  if r.CF_Preview_SetValue then r.CF_Preview_SetValue(preview, "D_VOLUME", settings.preview_volume or defaults.preview_volume) end
  pcall(r.CF_Preview_Play, preview)
  app.status = "Playing project preview"
  return true
end

local function find_open_project_by_path(project_path)
  if not project_path then return nil end
  local target = normalize_path(project_path):lower()
  local index = 0
  while true do
    local project, filename = r.EnumProjects(index)
    if not project then break end
    if filename and filename ~= "" and normalize_path(filename):lower() == target then return project end
    index = index + 1
  end
  return nil
end

local function make_project_preview(app, settings, project, mode)
  if not project or not project.path then return end
  local project_path = project.path
  if mode == "custom" then
    if not r.JS_Dialog_BrowseForOpenFiles then app.status = "js_ReaScriptAPI required for file dialog"; return end
    local dir = project_path:match("(.*[/\\])") or ""
    local nul = string.char(0)
    local filter = "Audio files" .. nul .. "*.wav;*.mp3;*.flac;*.ogg;*.aif;*.aiff" .. nul .. "All files" .. nul .. "*.*" .. nul
    local ok, file = r.JS_Dialog_BrowseForOpenFiles("Choose Audio File for Preview", dir, "", filter, false)
    if not ok or not file or file == "" then return end
    local ext = file:match("%.([^%.]+)$")
    ext = ext and ext:lower() or nil
    local allowed = { wav = true, mp3 = true, flac = true, ogg = true, aif = true, aiff = true }
    if not ext or not allowed[ext] then app.status = "Unsupported audio format"; return end
    local base = project_preview_base(project)
    local stamp = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    local out_path = dir .. base .. ".tkprev." .. stamp .. "." .. ext
    local input = io.open(file, "rb")
    if not input then app.status = "Could not read source file"; return end
    local output = io.open(out_path, "wb")
    if not output then input:close(); app.status = "Could not write preview file"; return end
    while true do
      local chunk = input:read(1024 * 1024)
      if not chunk then break end
      output:write(chunk)
    end
    input:close()
    output:close()
    clear_active_preview_filename(project_path)
    clear_project_preview_cache(project_path)
    play_project_preview_file(app, settings, project, out_path)
    app.status = "Project preview imported"
    return
  end

  local was_open = find_open_project_by_path(project_path) ~= nil
  if mode == "timesel" and not was_open then
    app.status = "Open the project first and set a time selection"
    r.ShowMessageBox("Open the project first and set a time selection before making a time-selection preview.", "Make Preview", 0)
    return
  end
  if not was_open then
    r.Main_OnCommand(41929, 0)
    r.Main_openProject(project_path)
  end
  local reaper_project = find_open_project_by_path(project_path)
  if not reaper_project then app.status = "Could not open project"; return end
  r.SelectProjectInstance(reaper_project)
  if mode == "full" then
    r.Main_OnCommand(42332, 0)
    clear_project_preview_cache(project_path)
    app.status = "Full project preview render started"
    if not was_open then r.Main_OnCommand(40860, 0) end
    return
  end
  local start_time, end_time = r.GetSet_LoopTimeRange2(reaper_project, false, false, 0, 0, false)
  if not start_time or not end_time or end_time <= start_time then
    if not was_open then r.Main_OnCommand(40860, 0) end
    app.status = "No time selection set"
    r.ShowMessageBox("No time selection set in the project. Set a time selection first.", "Make Preview", 0)
    return
  end
  if r.CF_Preview_StopAll then r.CF_Preview_StopAll() end
  stop_project_preview()
  local dir = project_path:match("(.*[/\\])") or ""
  local base = project_preview_base(project)
  local stamp = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
  local pattern = base .. ".tkprev." .. stamp
  local out_path = dir .. pattern .. ".wav"
  local old_bounds = r.GetSetProjectInfo(reaper_project, "RENDER_BOUNDSFLAG", 0, false)
  local old_settings = r.GetSetProjectInfo(reaper_project, "RENDER_SETTINGS", 0, false)
  local _, old_file = r.GetSetProjectInfo_String(reaper_project, "RENDER_FILE", "", false)
  local _, old_pattern = r.GetSetProjectInfo_String(reaper_project, "RENDER_PATTERN", "", false)
  r.GetSet_LoopTimeRange2(reaper_project, true, false, start_time, end_time, false)
  r.GetSetProjectInfo(reaper_project, "RENDER_BOUNDSFLAG", 2, true)
  r.GetSetProjectInfo(reaper_project, "RENDER_SETTINGS", 0, true)
  r.GetSetProjectInfo_String(reaper_project, "RENDER_FILE", dir, true)
  r.GetSetProjectInfo_String(reaper_project, "RENDER_PATTERN", pattern, true)
  r.Main_OnCommand(42230, 0)
  r.GetSetProjectInfo(reaper_project, "RENDER_BOUNDSFLAG", old_bounds, true)
  r.GetSetProjectInfo(reaper_project, "RENDER_SETTINGS", old_settings, true)
  r.GetSetProjectInfo_String(reaper_project, "RENDER_FILE", old_file, true)
  r.GetSetProjectInfo_String(reaper_project, "RENDER_PATTERN", old_pattern, true)
  clear_active_preview_filename(project_path)
  clear_project_preview_cache(project_path)
  if file_exists(out_path) then play_project_preview_file(app, settings, project, out_path) end
  if not was_open then r.Main_OnCommand(40860, 0) end
  app.status = "Project preview rendered"
end

local function delete_project_preview_file(app, project, entry)
  if not project or not entry or not entry.path then return end
  if state.preview_path and normalize_path(state.preview_path):lower() == normalize_path(entry.path):lower() then stop_project_preview() end
  local ok = os.remove(entry.path) ~= nil
  local peaks = entry.path .. ".reapeaks"
  if file_exists(peaks) then os.remove(peaks) end
  if active_preview_filename(project.path) == entry.name then clear_active_preview_filename(project.path) end
  clear_project_preview_cache(project.path)
  app.status = ok and "Project preview deleted" or "Could not delete project preview"
end

local function project_preview_position()
  if not state.preview then return 0 end
  if r.CF_Preview_GetValue then
    local ok, value_ok, position = pcall(r.CF_Preview_GetValue, state.preview, "D_POSITION")
    if ok and value_ok and tonumber(position) then return math.max(0, tonumber(position)) end
  end
  local now = r.time_precise and r.time_precise() or os.clock()
  return math.max(0, now - (state.preview_started_at or now))
end

local function update_project_preview(app)
  if not state.preview then return end
  if state.preview_length > 0 and project_preview_position() >= state.preview_length - 0.02 then stop_project_preview() end
end

local function parse_rpp(path)
  local cached = state.metadata_cache[path]
  if cached then return cached end
  local info = { bpm = nil, samplerate = nil, track_count = 0, timesig = "", length = 0 }
  local file = io.open(path, "r")
  if not file then state.metadata_cache[path] = info; return info end
  local in_item = false
  local item_position, item_length = nil, nil
  local lines = 0
  for line in file:lines() do
    lines = lines + 1
    if lines > 8000 then break end
    if not info.bpm then
      local bpm, num, den = line:match("^%s*TEMPO%s+([%d%.]+)%s+(%d+)%s+(%d+)")
      if bpm then
        info.bpm = tonumber(bpm)
        info.timesig = tostring(num) .. "/" .. tostring(den)
      else
        local bpm_only = line:match("^%s*TEMPO%s+([%d%.]+)")
        if bpm_only then info.bpm = tonumber(bpm_only) end
      end
    end
    if not info.samplerate then
      local samplerate = line:match("^%s*SAMPLERATE%s+(%d+)")
      if samplerate then info.samplerate = tonumber(samplerate) end
    end
    if line:match("^%s*<TRACK") then info.track_count = info.track_count + 1 end
    if line:match("^%s*<ITEM") then
      in_item = true
      item_position, item_length = nil, nil
    elseif in_item then
      item_position = item_position or tonumber(line:match("^%s*POSITION%s+([%-%.%d]+)"))
      item_length = item_length or tonumber(line:match("^%s*LENGTH%s+([%-%.%d]+)"))
      if item_position and item_length then
        info.length = math.max(info.length, item_position + item_length)
        in_item = false
      elseif line:match("^%s*>%s*$") then
        in_item = false
      end
    end
  end
  file:close()
  state.metadata_cache[path] = info
  return info
end

local function project_cover_path(project)
  if not project or not project.path then return nil end
  if state.cover_path_cache[project.path] ~= nil then return state.cover_path_cache[project.path] or nil end
  local safe_name = project.name:gsub("[^%w%s-]", "_")
  local central = { project_covers_path .. safe_name .. ".png", project_covers_path .. safe_name .. ".jpg", project_covers_path .. safe_name .. ".jpeg" }
  for _, path in ipairs(central) do
    if file_exists(path) then state.cover_path_cache[project.path] = path; return path end
  end
  local folder = project.folder
  local names = { project.name .. ".png", project.name .. ".jpg", project.name .. ".jpeg", "cover.png", "cover.jpg", "cover.jpeg", "folder.png", "folder.jpg", "folder.jpeg", "front.png", "front.jpg", "front.jpeg", "artwork.png", "artwork.jpg", "artwork.jpeg" }
  for _, name in ipairs(names) do
    local path = join_path(folder, name)
    if file_exists(path) then state.cover_path_cache[project.path] = path; return path end
  end
  local index = 0
  while folder ~= "" do
    local name = r.EnumerateFiles(folder, index)
    if not name then break end
    local ext = name:match("%.([^%.]+)$")
    if ext and image_ext[ext:lower()] then
      local path = join_path(folder, name)
      state.cover_path_cache[project.path] = path
      return path
    end
    index = index + 1
  end
  state.cover_path_cache[project.path] = false
  return nil
end

-- Cover loading follows what TK FX Browser settled on for its screenshots, after
-- it hit these same two errors: nothing is created while drawing, and nothing is
-- thrown away while drawing either.
--
-- Drawing only ever asks for a cover; a pass at the top of the frame creates a
-- handful of them and detaches whatever has gone unused for a couple of seconds.
-- So a screenful of new tiles fills in over a frame or two instead of attaching
-- eighty images at once, and a tile that stays on screen keeps its image because
-- asking for it is what marks it as still in use.
local COVER_CACHE_MAX = 100
local COVER_CACHE_MIN = 25
local COVER_LOADS_PER_FRAME = 12
local COVER_IDLE_SECONDS = 2

local function cover_now()
  return r.time_precise and r.time_precise() or os.clock()
end

-- Returns the entry when it is ready, otherwise nil plus true to say it is on its
-- way - which lets the caller leave the box empty rather than flashing "No image"
-- for the frame or two before it arrives.
local function load_cover(ctx, project)
  if not project then return nil end
  local path = project_cover_path(project)
  if not path or not r.ImGui_CreateImage then return nil end
  local cached = state.cover_image_cache[path]
  if cached then
    cached.used = cover_now()
    return cached
  end
  state.cover_queue[path] = true
  return nil, true
end

local function process_cover_queue(ctx)
  if not r.ImGui_CreateImage then return end
  local now = cover_now()
  local size = 0
  for _ in pairs(state.cover_image_cache) do size = size + 1 end
  local loaded = 0
  for path in pairs(state.cover_queue) do
    if loaded >= COVER_LOADS_PER_FRAME or size >= COVER_CACHE_MAX then break end
    state.cover_queue[path] = nil
    if not state.cover_image_cache[path] then
      local ok, image = pcall(r.ImGui_CreateImage, path)
      if ok and image then
        local attached = true
        if r.ImGui_Attach then attached = pcall(r.ImGui_Attach, ctx, image) end
        if attached then
          local width, height = 0, 0
          if r.ImGui_Image_GetSize then
            local size_ok, w, h = pcall(r.ImGui_Image_GetSize, image)
            if size_ok then width, height = w or 0, h or 0 end
          end
          state.cover_image_cache[path] = { image = image, path = path, width = width, height = height, used = now }
          size = size + 1
          loaded = loaded + 1
        elseif r.ImGui_DestroyImage then
          pcall(r.ImGui_DestroyImage, ctx, image)
        end
      end
    end
  end
  -- Oldest first, never below the floor, and never anything asked for recently.
  -- The floor is what stops a full screen of tiles from evicting each other.
  if size > COVER_CACHE_MIN then
    local order = {}
    for path, entry in pairs(state.cover_image_cache) do
      order[#order + 1] = { path = path, used = entry.used or 0 }
    end
    table.sort(order, function(a, b) return a.used < b.used end)
    for _, item in ipairs(order) do
      if size <= COVER_CACHE_MIN then break end
      if now - item.used <= COVER_IDLE_SECONDS then break end
      release_cover_entry(ctx, item.path)
      size = size - 1
    end
  end
end

local function draw_cover(ctx, draw_list, entry, x1, y1, x2, y2, fallback_text, options)
  options = options or {}
  if options.no_frame ~= true then r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, Theme.colors.frame_bg, UIScale.px(5)) end
  if entry and entry.image and r.ImGui_DrawList_AddImage then
    local iw = entry.width > 0 and entry.width or 1
    local ih = entry.height > 0 and entry.height or 1
    local w, h = x2 - x1, y2 - y1
    local scale = math.min(w / iw, h / ih)
    local draw_w, draw_h = iw * scale, ih * scale
    local dx, dy = x1 + (w - draw_w) * 0.5, y1 + (h - draw_h) * 0.5
    if options.align_top_left == true then dx, dy = x1, y1 end
    r.ImGui_DrawList_AddImage(draw_list, entry.image, dx, dy, dx + draw_w, dy + draw_h, 0, 0, 1, 1, 0xFFFFFFFF)
  elseif options.no_image_box == true then
    local box_size = math.max(1, math.min(x2 - x1, y2 - y1))
    x2 = x1 + box_size
    y2 = y1 + box_size
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, Theme.colors.frame_bg, UIScale.px(5))
    -- Step down as the box gets smaller rather than letting the label run over
    -- its edge, which is what a small tile would otherwise do.
    local text_h = r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx) or UIScale.round(14)
    local room = (x2 - x1) - UIScale.round(6)
    local label, text_w = nil, 0
    for _, candidate in ipairs({ "No image", "No img", fallback_text and fallback_text:sub(1, 1):upper() or "" }) do
      if candidate ~= "" then
        local width = r.ImGui_CalcTextSize and (r.ImGui_CalcTextSize(ctx, candidate) or 0) or #candidate * 7
        if width <= room then label, text_w = candidate, width break end
      end
    end
    if label then
      r.ImGui_DrawList_AddText(draw_list, x1 + ((x2 - x1) - text_w) * 0.5, y1 + ((y2 - y1) - text_h) * 0.5, Theme.colors.text_dim, label)
    end
  elseif fallback_text and fallback_text ~= "" then
    r.ImGui_DrawList_AddText(draw_list, x1 + UIScale.round(13), y1 + UIScale.round(10), Theme.colors.text_dim, fallback_text:sub(1, 1):upper())
  end
  if options.no_frame ~= true then r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, Theme.colors.border, UIScale.px(5), 0, UIScale.px(0.8)) end
end

local function open_project_now(app, project, new_tab)
  if not project or not project.path then return end
  if not r.Main_openProject then app.status = "Main_openProject is not available"; return end
  local mode_def = modes[project.mode or "projects"] or modes.projects
  if project.mode == "track_templates" then
    local ok = pcall(r.Main_openProject, project.path, 1)
    if not ok then r.Main_openProject(project.path) end
    app.status = "Inserting track template: " .. project.name
    return
  end
  if new_tab and r.Main_OnCommand then r.Main_OnCommand(41929, 0) end
  if project.mode == "project_templates" then
    r.Main_openProject("template:" .. project.path)
  else
    r.Main_openProject(project.path)
  end
  -- Everything in the project being replaced is freed by that call, and the
  -- snapshot the frame started with is still pointing at it. Modules updating
  -- after this one would read those pointers - and validating them is not enough,
  -- because a freed address can be handed straight back out to an item in the
  -- project just opened. It then passes every check while naming the wrong thing.
  -- Dropping the snapshot is the only honest answer; the next frame rebuilds it.
  app.selection = {}
  app.status = "Opening " .. mode_def.item_label .. ": " .. project.name
end

-- Every caller sits inside the draw pass, most of them between a row or tile's
-- PushID and its PopID. Main_openProject blocks and pumps REAPER's message loop
-- while it works, which can re-enter this script mid-frame and leave that id
-- stack crooked - the "EndChild: Missing PopID()" some people ran into. Queueing
-- it costs one frame and nothing else, and M.update opens it before the next
-- frame is built.
local function open_project(app, project, new_tab)
  if not project or not project.path then return end
  state.pending_open_project = { project = project, new_tab = new_tab == true }
end

local function navigate_folder(app, settings, folder_path)
  local mode = active_mode(settings)
  set_mode_folder_path(settings, mode, folder_path)
  state.selected_index = nil
  state.selected_project = nil
  state.selected_folder = nil
  state.scroll_selected_project = false
  state.filter_dirty = true
  if app.save_settings then app.save_settings() end
end

-- `offset` is how much was already drawn above the rows being virtualised, so a
-- grid with folder rows over it still lines up once the pane is scrolled.
local function visible_range(ctx, count, row_h, overscan, height, offset)
  if count <= 0 then return 1, 0, 0, 0 end
  local scroll_y = r.ImGui_GetScrollY and r.ImGui_GetScrollY(ctx) or 0
  scroll_y = math.max(0, scroll_y - (tonumber(offset) or 0))
  local first = math.max(1, math.floor(scroll_y / row_h) + 1 - overscan)
  local visible = math.ceil((height or 400) / row_h) + overscan * 2
  local last = math.min(count, first + visible)
  local top_pad = (first - 1) * row_h
  local bottom_pad = math.max(0, (count - last) * row_h)
  return first, last, top_pad, bottom_pad
end

local function key_pressed(ctx, name)
  if not r.ImGui_IsKeyPressed then return false end
  local key = r["ImGui_Key_" .. name]
  if not key then return false end
  local ok_key, key_value = pcall(key)
  if not ok_key or not key_value then return false end
  local ok, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key_value)
  return ok and pressed == true
end

local function keyboard_input_available(ctx)
  if r.ImGui_IsAnyItemActive then
    local ok, active = pcall(r.ImGui_IsAnyItemActive, ctx)
    if ok and active then return false end
  end
  if r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopupId then
    local ok, any_popup = pcall(r.ImGui_IsPopupOpen, ctx, "", r.ImGui_PopupFlags_AnyPopupId())
    if ok and any_popup then return false end
  end
  return true
end

local function scroll_selected_project_into_view(ctx, row_h)
  if not state.selected_index or not r.ImGui_GetScrollY or not r.ImGui_GetWindowHeight or not r.ImGui_SetScrollY then return end
  local top = (state.selected_index - 1) * row_h
  local bottom = top + row_h
  local scroll_y = r.ImGui_GetScrollY(ctx)
  local window_h = math.max(row_h, r.ImGui_GetWindowHeight(ctx) - (row_h * 1.5))
  if top < scroll_y then
    r.ImGui_SetScrollY(ctx, math.max(0, top - row_h))
  elseif bottom > scroll_y + window_h then
    r.ImGui_SetScrollY(ctx, math.max(0, bottom - window_h + row_h))
  end
end

local function project_list_window_active(ctx)
  if r.ImGui_IsWindowHovered then
    local ok, hovered = pcall(r.ImGui_IsWindowHovered, ctx)
    if ok and hovered then return true end
  end
  if r.ImGui_IsWindowFocused then
    local ok, focused = pcall(r.ImGui_IsWindowFocused, ctx)
    if ok and focused then return true end
  end
  return state.project_list_keyboard_focus == true
end

-- `columns` is 1 in the list and the tile column count in the grid. Up and down
-- then step a whole row where that is what a row means, and left and right walk
-- one item either way - which in the list is the same thing as up and down, so
-- the arrows keep working the way they always did.
local function handle_project_list_keyboard(app, settings, row_h, columns)
  local ctx = app.ctx
  if #state.visible_entries == 0 or not project_list_window_active(ctx) or not keyboard_input_available(ctx) then return false end
  local index = state.selected_index
  local count = #state.visible_entries
  columns = math.max(1, math.floor(tonumber(columns) or 1))
  -- A folder occupies its own full width row even in the grid, so stepping by a
  -- column count only makes sense once the selection is among the tiles.
  local step = columns
  if columns > 1 and index and state.visible_entries[index] and state.visible_entries[index].kind ~= "project" then step = 1 end
  local target_index = nil
  if key_pressed(ctx, "UpArrow") then target_index = index and math.max(1, index - step) or 1
  elseif key_pressed(ctx, "DownArrow") then target_index = index and math.min(count, index + step) or 1
  elseif key_pressed(ctx, "LeftArrow") then target_index = index and math.max(1, index - 1) or 1
  elseif key_pressed(ctx, "RightArrow") then target_index = index and math.min(count, index + 1) or 1
  elseif key_pressed(ctx, "PageUp") then target_index = index and math.max(1, index - 10 * step) or 1
  elseif key_pressed(ctx, "PageDown") then target_index = index and math.min(count, index + 10 * step) or 1
  elseif key_pressed(ctx, "Home") then target_index = 1
  elseif key_pressed(ctx, "End") then target_index = count end
  if target_index then
    local entry = state.visible_entries[target_index]
    if entry then
      state.selected_index = target_index
      state.selected_project = entry.kind == "project" and entry.project or nil
      state.selected_folder = entry.kind == "folder" and entry.folder or nil
      state.project_list_keyboard_focus = true
      state.scroll_selected_project = true
      scroll_selected_project_into_view(ctx, row_h)
    end
    return true
  end
  if key_pressed(ctx, "Enter") or key_pressed(ctx, "KeypadEnter") then
    if state.selected_folder then
      navigate_folder(app, settings, state.selected_folder.path)
    elseif state.selected_project then
      open_project(app, state.selected_project, settings.open_new_tab_on_double_click)
    end
    return true
  end
  return false
end

local function select_project(project, index)
  state.selected_project = project
  state.selected_folder = nil
  state.selected_index = index
  state.project_list_keyboard_focus = true
  if project and project.path then clear_project_preview_cache(project.path) end
end

local function select_folder(folder, index)
  state.selected_folder = folder
  state.selected_project = nil
  state.selected_index = index
  state.project_list_keyboard_focus = true
end

local function draw_folder_row(app, settings, folder, index, width)
  local ctx = app.ctx
  local compact = settings.compact_list == true
  local row_h = compact and UIScale.round(24) or UIScale.round(54)
  r.ImGui_PushID(ctx, "folder_" .. tostring(folder.path or folder.name or index))
  local clicked = r.ImGui_InvisibleButton(ctx, "##row", width, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double_clicked = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local selected = state.selected_folder and state.selected_folder.path == folder.path and state.selected_folder.up == folder.up
  local bg = selected and 0x7AA2F730 or (hovered and 0xFFFFFF12 or 0x00000000)
  local row_top = compact and y or y + UIScale.round(2)
  local row_bottom = compact and y + row_h - UIScale.round(1) or y + row_h - UIScale.round(2)
  local row_radius = compact and UIScale.px(2) or UIScale.px(5)
  if bg ~= 0x00000000 then r.ImGui_DrawList_AddRectFilled(draw_list, x, row_top, x + width, row_bottom, bg, row_radius) end
  r.ImGui_DrawList_AddRect(draw_list, x, row_top, x + width, row_bottom, selected and Theme.colors.accent or Theme.colors.border, row_radius, 0, selected and UIScale.px(1.4) or UIScale.px(0.7))
  local icon_x, icon_y = compact and x + UIScale.round(16) or x + UIScale.round(25), compact and y + UIScale.round(15) or y + UIScale.round(26)
  r.ImGui_DrawList_AddRect(draw_list, icon_x - UIScale.round(10), icon_y - UIScale.round(5), icon_x + UIScale.round(10), icon_y + UIScale.round(7), Theme.colors.accent, UIScale.px(3), 0, UIScale.px(1.5))
  r.ImGui_DrawList_AddLine(draw_list, icon_x - UIScale.round(8), icon_y - UIScale.round(5), icon_x - UIScale.round(3), icon_y - UIScale.round(10), Theme.colors.accent, UIScale.px(1.5))
  r.ImGui_DrawList_AddLine(draw_list, icon_x - UIScale.round(3), icon_y - UIScale.round(10), icon_x + UIScale.round(5), icon_y - UIScale.round(10), Theme.colors.accent, UIScale.px(1.5))
  local text_x = compact and x + UIScale.round(34) or x + UIScale.round(52)
  r.ImGui_DrawList_PushClipRect(draw_list, text_x, y + UIScale.round(4), x + width - UIScale.round(8), y + row_h - UIScale.round(4), true)
  r.ImGui_DrawList_AddText(draw_list, text_x, compact and y + UIScale.round(4) or y + UIScale.round(8), Theme.colors.text, folder.name or "Folder")
  if not compact then
    local detail = folder.up and "Parent folder" or (tostring(folder.count or 0) .. " items")
    r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(29), Theme.colors.text_dim, detail)
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked then select_folder(folder, index) end
  if double_clicked then navigate_folder(app, settings, folder.path) end
  if hovered then r.ImGui_SetTooltip(ctx, folder.up and "Go up" or folder.path) end
  if selected and state.scroll_selected_project and r.ImGui_SetScrollHereY then
    local ok = pcall(r.ImGui_SetScrollHereY, ctx, 0.5)
    if ok then state.scroll_selected_project = false end
  end
  r.ImGui_PopID(ctx)
end

local function draw_project_row(app, settings, project, index, width)
  local ctx = app.ctx
  local mode_def = modes[project.mode or "projects"] or modes.projects
  local compact = settings.compact_list == true
  local row_h = compact and UIScale.round(24) or UIScale.round(54)
  r.ImGui_PushID(ctx, "project_" .. tostring(index))
  local clicked = r.ImGui_InvisibleButton(ctx, "##row", width, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double_clicked = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local selected = state.selected_project and state.selected_project.path == project.path
  local bg = selected and 0x7AA2F730 or (hovered and 0xFFFFFF12 or 0x00000000)
  local row_top = compact and y or y + UIScale.round(2)
  local row_bottom = compact and y + row_h - UIScale.round(1) or y + row_h - UIScale.round(2)
  local row_radius = compact and UIScale.px(2) or UIScale.px(5)
  if bg ~= 0x00000000 then r.ImGui_DrawList_AddRectFilled(draw_list, x, row_top, x + width, row_bottom, bg, row_radius) end
  r.ImGui_DrawList_AddRect(draw_list, x, row_top, x + width, row_bottom, selected and Theme.colors.accent or Theme.colors.border, row_radius, 0, selected and UIScale.px(1.4) or UIScale.px(0.7))
  local text_x = compact and x + UIScale.round(10) or x + UIScale.round(52)
  if not compact then
    local cover = load_cover(ctx, project)
    draw_cover(ctx, draw_list, cover, x + UIScale.round(7), y + UIScale.round(8), x + UIScale.round(43), y + UIScale.round(44), project.name)
  end
  r.ImGui_DrawList_PushClipRect(draw_list, text_x, y + UIScale.round(4), x + width - UIScale.round(8), y + row_h - UIScale.round(4), true)
  r.ImGui_DrawList_AddText(draw_list, text_x, compact and y + UIScale.round(4) or y + UIScale.round(8), Theme.colors.text, project.name)
  if not compact then
    local detail = compact_path(project.path)
    if project.date ~= "" then detail = project.date .. " | " .. detail end
    r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(29), Theme.colors.text_dim, detail)
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked then select_project(project, index) end
  if double_clicked then open_project(app, project, settings.open_new_tab_on_double_click) end
  if r.ImGui_BeginPopupContextItem(ctx, "##project_context") then
    if project.mode == "track_templates" then
      if r.ImGui_MenuItem(ctx, "Insert track template") then open_project(app, project, false) end
    else
      if r.ImGui_MenuItem(ctx, "Open " .. mode_def.item_label .. " in current tab") then open_project(app, project, false) end
      if r.ImGui_MenuItem(ctx, "Open " .. mode_def.item_label .. " in new tab") then open_project(app, project, true) end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Copy path") and r.CF_SetClipboard then r.CF_SetClipboard(project.path) end
    r.ImGui_EndPopup(ctx)
  end
  if hovered and settings.show_hover_info ~= false then r.ImGui_SetTooltip(ctx, project.path) end
  if selected and state.scroll_selected_project and r.ImGui_SetScrollHereY then
    local ok = pcall(r.ImGui_SetScrollHereY, ctx, 0.5)
    if ok then state.scroll_selected_project = false end
  end
  r.ImGui_PopID(ctx)
end

-- Tiles. Returns nil while the setting is below the floor, which is what keeps
-- the list the default: one setting instead of a separate list/grid switch.
local TILE_MIN = 64

local function tile_text_w(ctx, text)
  if not r.ImGui_CalcTextSize then return #tostring(text or "") * 7 end
  local w = r.ImGui_CalcTextSize(ctx, tostring(text or ""))
  return tonumber(w) or 0
end

local function tile_metrics(ctx, settings, width)
  local size = math.floor(tonumber(settings.tile_size) or 0)
  if size < TILE_MIN then return nil end
  size = UIScale.round(size)
  local gap = UIScale.round(8)
  local columns = math.max(1, math.floor((width + gap) / (size + gap)))
  local tile_w = math.max(UIScale.round(48), (width - gap * (columns - 1)) / columns)
  local line_h = r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx) or UIScale.round(14)
  local caption_h = line_h * 2 + UIScale.round(10)
  return { columns = columns, w = tile_w, h = tile_w + caption_h, gap = gap, caption_h = caption_h, line_h = line_h }
end

-- Two lines, breaking on the last space that still fits so a name splits between
-- words rather than mid-syllable. The second line is ellipsised if it overruns.
local function tile_caption_lines(ctx, text, max_w)
  text = tostring(text or "")
  if tile_text_w(ctx, text) <= max_w then return text, nil end
  local break_at = nil
  for pos in text:gmatch("()%s") do
    if tile_text_w(ctx, text:sub(1, pos - 1)) <= max_w then break_at = pos else break end
  end
  if not break_at then
    local cut = #text
    while cut > 1 and tile_text_w(ctx, text:sub(1, cut)) > max_w do cut = cut - 1 end
    break_at = cut + 1
  end
  local first = text:sub(1, break_at - 1)
  local second = text:sub(break_at + 1)
  if tile_text_w(ctx, second) > max_w then
    while #second > 1 and tile_text_w(ctx, second .. "...") > max_w do second = second:sub(1, -2) end
    second = second .. "..."
  end
  return first, second
end

-- Mirrors draw_project_row: same selection, same double click, same context menu.
-- Only the arrangement differs.
local function draw_project_tile(app, settings, project, index, tile)
  local ctx = app.ctx
  local mode_def = modes[project.mode or "projects"] or modes.projects
  r.ImGui_PushID(ctx, "project_tile_" .. tostring(index))
  local clicked = r.ImGui_InvisibleButton(ctx, "##tile", tile.w, tile.h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double_clicked = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local selected = state.selected_project and state.selected_project.path == project.path
  local bg = selected and 0x7AA2F730 or (hovered and 0xFFFFFF12 or 0x00000000)
  if bg ~= 0x00000000 then
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + tile.w, y + tile.h, bg, UIScale.px(5))
  end
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + tile.w, y + tile.h,
    selected and Theme.colors.accent or Theme.colors.border, UIScale.px(5), 0,
    selected and UIScale.px(1.4) or UIScale.px(0.7))
  local inset = UIScale.round(4)
  -- While a cover is still on its way the box stays blank; only a project that
  -- genuinely has no artwork gets the label.
  local cover, pending = load_cover(ctx, project)
  draw_cover(ctx, draw_list, cover, x + inset, y + inset, x + tile.w - inset, y + tile.w - inset, project.name, { no_image_box = not pending })
  local text_w = tile.w - inset * 2
  local first, second = tile_caption_lines(ctx, project.name, text_w)
  r.ImGui_DrawList_PushClipRect(draw_list, x + inset, y + tile.w, x + tile.w - inset, y + tile.h, true)
  r.ImGui_DrawList_AddText(draw_list, x + inset, y + tile.w + UIScale.round(3), Theme.colors.text, first)
  if second then
    r.ImGui_DrawList_AddText(draw_list, x + inset, y + tile.w + UIScale.round(3) + tile.line_h, Theme.colors.text_dim, second)
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked then select_project(project, index) end
  if double_clicked then open_project(app, project, settings.open_new_tab_on_double_click) end
  if r.ImGui_BeginPopupContextItem(ctx, "##project_tile_context") then
    if project.mode == "track_templates" then
      if r.ImGui_MenuItem(ctx, "Insert track template") then open_project(app, project, false) end
    else
      if r.ImGui_MenuItem(ctx, "Open " .. mode_def.item_label .. " in current tab") then open_project(app, project, false) end
      if r.ImGui_MenuItem(ctx, "Open " .. mode_def.item_label .. " in new tab") then open_project(app, project, true) end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Copy path") and r.CF_SetClipboard then r.CF_SetClipboard(project.path) end
    r.ImGui_EndPopup(ctx)
  end
  if hovered and settings.show_hover_info ~= false then r.ImGui_SetTooltip(ctx, project.name .. "\n" .. project.path) end
  if selected and state.scroll_selected_project and r.ImGui_SetScrollHereY then
    local ok = pcall(r.ImGui_SetScrollHereY, ctx, 0.5)
    if ok then state.scroll_selected_project = false end
  end
  r.ImGui_PopID(ctx)
end

-- Folders keep their full width rows above the tiles. apply_filter always emits
-- folders first and projects after, never interleaved, so the two can simply be
-- drawn one after the other.
local function draw_project_grid(app, settings, width, height, tile)
  local ctx = app.ctx
  local entries = state.visible_entries
  local first_project = nil
  for index, entry in ipairs(entries) do
    if entry.kind == "folder" and entry.folder then
      draw_folder_row(app, settings, entry.folder, index, width)
    elseif entry.kind == "project" then
      first_project = index
      break
    end
  end
  if not first_project then return end
  -- Whatever the folder rows just consumed, so the tile maths below knows where
  -- it actually starts within the scrolled content.
  local consumed = r.ImGui_GetCursorPosY and r.ImGui_GetCursorPosY(ctx) or 0
  local count = #entries - first_project + 1
  local rows = math.ceil(count / tile.columns)
  local row_h = tile.h + tile.gap
  -- One row of overscan, not two: every off-screen tile still loads a cover.
  local first_row, last_row, top_pad, bottom_pad = visible_range(ctx, rows, row_h, 1, height, consumed)
  if top_pad > 0 then r.ImGui_Dummy(ctx, 1, top_pad) end
  for row = first_row, last_row do
    for column = 1, tile.columns do
      local offset = (row - 1) * tile.columns + column
      local index = first_project + offset - 1
      local entry = entries[index]
      if entry and entry.kind == "project" and entry.project then
        if column > 1 then r.ImGui_SameLine(ctx, 0, tile.gap) end
        draw_project_tile(app, settings, entry.project, index, tile)
      end
    end
  end
  if bottom_pad > 0 then r.ImGui_Dummy(ctx, 1, bottom_pad) end
end

local function draw_project_list(app, settings, width, height)
  local ctx = app.ctx
  local _, mode_def = active_mode(settings)
  local row_h = settings.compact_list == true and UIScale.round(24) or UIScale.round(54)
  local child_flags = 0
  if r.ImGui_WindowFlags_NoNavInputs then
    local ok_flags, flags = pcall(r.ImGui_WindowFlags_NoNavInputs)
    if ok_flags and flags then child_flags = flags end
  end
  if r.ImGui_WindowFlags_NoNavFocus then
    local ok_flags, flags = pcall(r.ImGui_WindowFlags_NoNavFocus)
    if ok_flags and flags then child_flags = child_flags | flags end
  end
  local child_visible = r.ImGui_BeginChild(ctx, "##project_list", 0, height, 0, child_flags)
  if child_visible then
    local inner_w = math.max(UIScale.round(80), width - UIScale.round(12))
    local tile = tile_metrics(ctx, settings, inner_w)
    handle_project_list_keyboard(app, settings, tile and (tile.h + tile.gap) or row_h, tile and tile.columns or 1)
    if #state.locations == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Add a " .. mode_def.item_label .. " location")
    elseif state.scanning then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Scanning... " .. tostring(#state.projects) .. " " .. mode_def.plural)
    elseif #state.visible_entries == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No " .. mode_def.plural .. " found")
    end
    if tile then
      draw_project_grid(app, settings, inner_w, height, tile)
    else
      local compact_spacing = settings.compact_list == true and r.ImGui_PushStyleVar and r.ImGui_StyleVar_ItemSpacing
      if compact_spacing then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), UIScale.round(8), 0) end
      local first, last, top_pad, bottom_pad = visible_range(ctx, #state.visible_entries, row_h, UIScale.round(6), height)
      if top_pad > 0 then r.ImGui_Dummy(ctx, 1, top_pad) end
      for index = first, last do
        local entry = state.visible_entries[index]
        if entry and entry.kind == "folder" and entry.folder then
          draw_folder_row(app, settings, entry.folder, index, inner_w)
        elseif entry and entry.kind == "project" and entry.project then
          draw_project_row(app, settings, entry.project, index, inner_w)
        end
      end
      if bottom_pad > 0 then r.ImGui_Dummy(ctx, 1, bottom_pad) end
      if compact_spacing then r.ImGui_PopStyleVar(ctx, 1) end
    end
  end
  r.ImGui_EndChild(ctx)
end

local function metadata_line(ctx, label, value)
  value = tostring(value or "")
  if value == "" then return end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, label)
  r.ImGui_SameLine(ctx, UIScale.round(72))
  r.ImGui_TextColored(ctx, Theme.colors.text, value)
end

local function push_slider_theme(ctx)
  local count = 0
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.colors.frame_bg); count = count + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.colors.frame_hover); count = count + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.colors.accent_soft); count = count + 1 end
  if r.ImGui_Col_SliderGrab then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent); count = count + 1 end
  if r.ImGui_Col_SliderGrabActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.text); count = count + 1 end
  return count
end

local function pop_slider_theme(ctx, count)
  if count and count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

local function draw_panel_header(ctx, label, collapsed, id)
  local button_label = (collapsed and ">" or "v") .. "##" .. id
  if r.ImGui_Button(ctx, button_label, UIScale.round(22), 0) then collapsed = not collapsed end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text, label)
  return collapsed
end

local function draw_playback_collapse_button(ctx)
  local collapsed = state.playback_panel_collapsed == true
  if r.ImGui_Button(ctx, (collapsed and ">" or "v") .. "##project_playback_collapse", UIScale.round(22), 0) then
    state.playback_panel_collapsed = not collapsed
    collapsed = state.playback_panel_collapsed == true
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, collapsed and "Expand" or "Collapse") end
  return collapsed
end

local function draw_playback_placeholder(ctx, text)
  local collapsed = draw_playback_collapse_button(ctx)
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  r.ImGui_Button(ctx, "Play##project_preview_placeholder", UIScale.text_button_w(ctx, "Play", 58), 0)
  if collapsed then return end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, text)
end

local function draw_project_preview_transport(app, settings, project, width)
  local ctx = app.ctx
  local preview_path = project_preview_path(project)
  local is_playing = state.preview_project_path == project.path and state.preview ~= nil
  local length = preview_path and (is_playing and state.preview_length or project_preview_length(preview_path)) or 0
  local position = is_playing and project_preview_position() or 0
  local button_label = is_playing and "Stop##project_preview" or "Play##project_preview"
  local disabled = preview_path == nil or not r.CF_CreatePreview or not r.CF_Preview_Play
  local length_text = format_project_length(length)
  local time_text = format_project_length(position) .. " / " .. (length_text ~= "" and length_text or "0:00")
  local preview_label = preview_path and "Preview" or "No preview"
  local collapsed = draw_playback_collapse_button(ctx)
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  if disabled then
    r.ImGui_Button(ctx, "Play##project_preview", UIScale.text_button_w(ctx, "Play", 58), 0)
  elseif r.ImGui_Button(ctx, button_label, UIScale.text_button_w(ctx, "Stop", 58), 0) then
    if is_playing then stop_project_preview() else start_project_preview(app, settings, project) end
  end
  if collapsed then return end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, preview_path and Theme.colors.text or Theme.colors.text_dim, preview_label)
  if preview_path and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, preview_path) end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, time_text)
  if r.ImGui_ProgressBar then
    local progress = length > 0 and math.max(0, math.min(1, position / length)) or 0
    r.ImGui_ProgressBar(ctx, progress, -1, UIScale.round(6), "")
  end
  if r.ImGui_SliderDouble then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Volume")
    r.ImGui_SameLine(ctx)
    local slider_w = math.max(1, select(1, r.ImGui_GetContentRegionAvail(ctx)))
    r.ImGui_PushItemWidth(ctx, slider_w)
    local slider_theme_count = push_slider_theme(ctx)
    local changed, value = r.ImGui_SliderDouble(ctx, "##project_preview_volume", settings.preview_volume or defaults.preview_volume, 0, 2, "")
    pop_slider_theme(ctx, slider_theme_count)
    if changed then
      settings.preview_volume = value
      if state.preview and r.CF_Preview_SetValue then r.CF_Preview_SetValue(state.preview, "D_VOLUME", value) end
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_PopItemWidth(ctx)
  end
  local button_gap = UIScale.gap(8)
  local action_row_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local action_button_w = math.max(1, (action_row_w - button_gap) * 0.5)
  if r.ImGui_Button(ctx, "Make Preview", action_button_w, 0) then r.ImGui_OpenPopup(ctx, "##project_preview_make") end
  if r.ImGui_BeginPopup(ctx, "##project_preview_make") then
    -- Noted rather than run: making a preview opens projects, puts up dialogs and
    -- kicks off a render, and none of that belongs inside a half-drawn frame.
    -- M.update picks it up before the next one is built.
    if r.ImGui_MenuItem(ctx, "Full project") then state.pending_preview_make = { project = project, mode = "full" } end
    if r.ImGui_MenuItem(ctx, "Time selection") then state.pending_preview_make = { project = project, mode = "timesel" } end
    if r.ImGui_MenuItem(ctx, "Custom audio file...") then state.pending_preview_make = { project = project, mode = "custom" } end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_SameLine(ctx, 0, button_gap)
  if r.ImGui_Button(ctx, "Manage", action_button_w, 0) then
    state.manage_previews_project = project
    r.ImGui_OpenPopup(ctx, "##project_preview_manage")
  end
  if r.ImGui_BeginPopup(ctx, "##project_preview_manage") then
    local target = state.manage_previews_project or project
    local list = list_project_previews(target)
    local active = active_preview_filename(target.path)
    r.ImGui_Text(ctx, "Previews: " .. target.name)
    r.ImGui_Separator(ctx)
    if #list == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "(no preview files)") end
    -- The row body runs inside its own pcall so the PopID below always happens.
    -- This whole function is called through a pcall, and an error thrown while an
    -- id was pushed left the stack unbalanced: the caller's EndChild then failed
    -- with "Missing PopID()" and took the frame down with it, hiding whatever the
    -- real error had been.
    local function draw_manage_row(index, entry)
      local is_active = active == entry.name or (not active and index == 1)
      r.ImGui_TextColored(ctx, is_active and Theme.colors.accent or Theme.colors.text, (is_active and "* " or "  ") .. entry.name)
      local playing_this = state.preview_path and normalize_path(state.preview_path):lower() == normalize_path(entry.path):lower()
      if r.ImGui_Button(ctx, playing_this and "Stop" or "Play", UIScale.text_button_w(ctx, "Stop", 54), 0) then
        if playing_this then stop_project_preview() else play_project_preview_file(app, settings, target, entry.path) end
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Set Active", UIScale.text_button_w(ctx, "Set Active", 84), 0) then
        set_active_preview_filename(target.path, entry.name)
        clear_project_preview_cache(target.path)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Delete", UIScale.text_button_w(ctx, "Delete", 64), 0) then
        -- Only note it down. ShowMessageBox blocks, and blocking here means doing
        -- it inside the ImGui frame with an id still pushed: REAPER keeps pumping
        -- messages while that dialog is up, which can re-enter this script and
        -- leave the id stack crooked. M.update runs before the frame is built, so
        -- the question gets asked there instead.
        state.pending_preview_delete = { project = target, entry = entry }
      end
    end
    for index, entry in ipairs(list) do
      r.ImGui_PushID(ctx, index)
      local row_ok, row_err = pcall(draw_manage_row, index, entry)
      r.ImGui_PopID(ctx)
      if not row_ok then state.last_error = tostring(row_err) end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Close", UIScale.text_button_w(ctx, "Close", 80), 0) then r.ImGui_CloseCurrentPopup(ctx) end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_project_detail(app, project, width, height)
  local ctx = app.ctx
  local detail_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then detail_flags = detail_flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then detail_flags = detail_flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  if r.ImGui_WindowFlags_NoNavInputs then detail_flags = detail_flags | r.ImGui_WindowFlags_NoNavInputs() end
  if r.ImGui_WindowFlags_NoNavFocus then detail_flags = detail_flags | r.ImGui_WindowFlags_NoNavFocus() end
  local child_visible = r.ImGui_BeginChild(ctx, "##project_detail", width, height, 1, detail_flags)
  if child_visible then
    local label = project and project.name or "Preview"
    state.detail_panel_collapsed = draw_panel_header(ctx, label, state.detail_panel_collapsed == true, "project_detail_collapse")
    if not project then
      if state.detail_panel_collapsed ~= true then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select a project") end
    elseif state.detail_panel_collapsed ~= true then
      local header_h = r.ImGui_GetFrameHeight and r.ImGui_GetFrameHeight(ctx) or UIScale.round(22)
      local available_h = math.max(UIScale.round(52), height - header_h - UIScale.round(8))
      local gap = UIScale.gap(10)
      local meta_w = width > UIScale.round(430) and UIScale.round(176) or UIScale.round(146)
      local cover_w = math.max(UIScale.round(52), width - meta_w - gap - UIScale.round(10))
      local cover_bottom_padding = UIScale.round(14)
      local cover_h = math.max(UIScale.round(52), available_h - cover_bottom_padding)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      local draw_list = r.ImGui_GetWindowDrawList(ctx)
      local detail_cover, detail_pending = load_cover(ctx, project)
      draw_cover(ctx, draw_list, detail_cover, x, y, x + cover_w, y + cover_h, project.name, { no_frame = true, align_top_left = true, no_image_box = not detail_pending })
      r.ImGui_Dummy(ctx, cover_w, cover_h)
      r.ImGui_SameLine(ctx, 0, gap)
      r.ImGui_BeginGroup(ctx)
      if project.mode == "track_templates" then
        metadata_line(ctx, "Type", "Track template")
      else
        local info = parse_rpp(project.path)
        metadata_line(ctx, "BPM", info.bpm and string.format("%.2f", info.bpm) or "")
        metadata_line(ctx, "Sig", info.timesig)
        metadata_line(ctx, "Tracks", info.track_count > 0 and tostring(info.track_count) or "")
        metadata_line(ctx, "Rate", info.samplerate and tostring(info.samplerate) or "")
        metadata_line(ctx, "Length", format_project_length(info.length))
      end
      r.ImGui_EndGroup(ctx)
    end
  end
  r.ImGui_EndChild(ctx)
end

local function draw_project_playback_panel(app, project, width, height)
  local ctx = app.ctx
  local flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then flags = flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then flags = flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  local child_visible = r.ImGui_BeginChild(ctx, "##project_playback", width, height, 1, flags)
  if child_visible then
    if not project then
      draw_playback_placeholder(ctx, "Select a project")
    elseif project.mode == "track_templates" then
      draw_playback_placeholder(ctx, "No project playback for track templates")
    else
      local ok, err = pcall(draw_project_preview_transport, app, ensure_settings(app), project, width)
      if not ok then
        -- Show what actually went wrong rather than a polite nothing. This is
        -- the pcall that hid the cause while the broken id stack surfaced as an
        -- EndChild failure further along, which is not where the fault was.
        state.last_error = tostring(err)
        r.ImGui_TextColored(ctx, Theme.colors.warning, "Preview controls: " .. tostring(err):sub(1, 120))
      end
    end
  end
  r.ImGui_EndChild(ctx)
end

local function draw_settings_popup(app, settings)
  local ctx = app.ctx
  local mode, mode_def = active_mode(settings)
  if state.settings_popup then
    r.ImGui_OpenPopup(ctx, "Project Browser Settings")
    state.settings_popup = false
  end
  if r.ImGui_BeginPopup(ctx, "Project Browser Settings") then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, mode_def.label)
    local pending = get_mode_pending_location(settings, mode)
    local changed, value = r.ImGui_InputText(ctx, "Location", pending)
    if changed then set_mode_pending_location(settings, mode, value); if app.save_settings then app.save_settings() end end
    if r.JS_Dialog_BrowseForFolder then
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Browse", UIScale.text_button_w(ctx, "Browse", 72), 0) then
        local ok, folder = r.JS_Dialog_BrowseForFolder("Choose " .. mode_def.item_label .. " folder", pending)
        if ok and folder and folder ~= "" then set_mode_pending_location(settings, mode, folder); if add_location(app, settings, folder) then start_scan(app, settings) elseif app.save_settings then app.save_settings() end end
      end
    end
    if r.ImGui_Button(ctx, "Add Location", UIScale.text_button_w(ctx, "Add Location", 110), 0) then if add_location(app, settings, get_mode_pending_location(settings, mode)) then start_scan(app, settings) end end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Remove Current", UIScale.text_button_w(ctx, "Remove Current", 120), 0) then remove_current_location(app, settings); start_scan(app, settings) end
    local c, v = r.ImGui_Checkbox(ctx, "Recursive scan", settings.recursive == true)
    if c then settings.recursive = v; if app.save_settings then app.save_settings() end end
    c, v = r.ImGui_Checkbox(ctx, "Folder view", settings.folder_view == true)
    if c then settings.folder_view = v; state.filter_dirty = true; if app.save_settings then app.save_settings() end end
    c, v = r.ImGui_Checkbox(ctx, "Compact list view", settings.compact_list == true)
    if c then settings.compact_list = v; if app.save_settings then app.save_settings() end end
    c, v = r.ImGui_Checkbox(ctx, "Show project info panel", settings.show_detail_panel ~= false)
    if c then settings.show_detail_panel = v; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "The metadata panel under the list. Hiding it gives its height to the list")
    end
    c, v = r.ImGui_Checkbox(ctx, "Show preview panel", settings.show_playback_panel ~= false)
    if c then
      settings.show_playback_panel = v
      -- Stopping first, so a preview cannot keep playing with its controls gone.
      if not v then stop_project_preview() end
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "The Play, volume and Make Preview row. Hiding it stops any preview that is playing")
    end
    c, v = r.ImGui_Checkbox(ctx, "Show hover info", settings.show_hover_info ~= false)
    if c then settings.show_hover_info = v; if app.save_settings then app.save_settings() end end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "The name and path that follow the pointer over a project.\nFolders keep theirs, since there is nothing else naming where they lead")
    end
    if r.ImGui_SliderInt then
      -- One slider rather than a list/grid switch: all the way down is the list,
      -- and above that the number is roughly how wide a tile wants to be, with
      -- the column count following from the width of the pane.
      local tile_size = math.floor(tonumber(settings.tile_size) or 0)
      c, v = r.ImGui_SliderInt(ctx, "Tile size", tile_size, 0, 240, tile_size < 64 and "List" or "%d px")
      if c then
        settings.tile_size = v < 64 and 0 or v
        if app.save_settings then app.save_settings() end
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Drag right for cover art tiles, all the way left for the list.\nFolders keep their own full width rows above the tiles")
      end
      c, v = r.ImGui_SliderInt(ctx, "Max depth", settings.max_depth, 0, 12)
      if c then settings.max_depth = v; if app.save_settings then app.save_settings() end end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "How far down the scan goes. Takes effect on the next scan")
      end
      local min_depth = math.floor(tonumber(settings.min_depth) or 0)
      c, v = r.ImGui_SliderInt(ctx, "Min depth", min_depth, 0, settings.max_depth, min_depth == 0 and "All" or "%d")
      if c then
        settings.min_depth = v
        state.filter_dirty = true
        if app.save_settings then app.save_settings() end
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Hides anything shallower than this. 1 drops the projects lying loose in the scan root and keeps only what sits inside a folder.\nFilters what is shown, so unlike Max depth it applies straight away")
      end
      c, v = r.ImGui_SliderInt(ctx, "Max items", settings.max_scan_projects, 50, 50000)
      if c then settings.max_scan_projects = v; if app.save_settings then app.save_settings() end end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Ceiling on how many items one scan collects. Reaching it stops the scan and the status line adds \"limited\".\nA safety brake for large drives: raise it only if you actually hit it")
      end
      c, v = r.ImGui_SliderInt(ctx, "Recent count", settings.recent_count, 1, 50)
      if c then
        settings.recent_count = v
        state.recent_cache = nil
        state.filter_dirty = true
        if app.save_settings then app.save_settings() end
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "How many entries the Rec button shows. REAPER keeps at most 50")
      end
    end
    if mode ~= "track_templates" then
      c, v = r.ImGui_Checkbox(ctx, "Double-click opens in new tab", settings.open_new_tab_on_double_click == true)
      if c then settings.open_new_tab_on_double_click = v; if app.save_settings then app.save_settings() end end
    end
    if r.ImGui_BeginCombo(ctx, "Sort", settings.sort_by) then
      for _, item in ipairs({ "name", "date", "path" }) do
        local selected = settings.sort_by == item
        if r.ImGui_Selectable(ctx, item, selected) then settings.sort_by = item; state.filter_dirty = true; if app.save_settings then app.save_settings() end end
      end
      r.ImGui_EndCombo(ctx)
    end
    c, v = r.ImGui_Checkbox(ctx, "Ascending", settings.sort_ascending == true)
    if c then settings.sort_ascending = v; state.filter_dirty = true; if app.save_settings then app.save_settings() end end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_toolbar(app, settings)
  local ctx = app.ctx
  local mode, mode_def = active_mode(settings)
  local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local button_w = UIScale.round(28)
  local spacing = UIScale.gap(6)
  local mode_w = math.min(UIScale.round(126), math.max(UIScale.round(92), avail_w * 0.28))
  local combo_w = math.max(UIScale.round(70), avail_w - mode_w - (button_w * 3) - (spacing * 4))
  r.ImGui_SetNextItemWidth(ctx, mode_w)
  if r.ImGui_BeginCombo(ctx, "##project_browser_mode", mode_def.short) then
    for _, item in ipairs(mode_order) do
      local item_def = modes[item]
      local selected = item == mode
      if r.ImGui_Selectable(ctx, item_def.label, selected) then
        settings.browser_mode = item
        refresh_locations(settings)
        start_scan(app, settings)
        if app.save_settings then app.save_settings() end
      end
      if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  local current_location = get_mode_location(settings, mode)
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  if r.ImGui_BeginCombo(ctx, "##project_location", current_location ~= "" and current_location or "No location") then
    for _, location in ipairs(state.locations) do
      local selected = location == current_location
      if r.ImGui_Selectable(ctx, location, selected) then set_mode_location(settings, mode, location); set_mode_folder_path(settings, mode, ""); if app.save_settings then app.save_settings() end; start_scan(app, settings) end
      if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  local recent_on = settings.show_recent == true
  if recent_on then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds({ Theme.colors.accent, Theme.colors.warning }, Theme.colors.text, nil, 4.5))
  end
  local recent_clicked = r.ImGui_Button(ctx, "Rec", button_w, 0)
  if recent_on then r.ImGui_PopStyleColor(ctx, 4) end
  if recent_clicked then
    settings.show_recent = not recent_on
    -- Re-read on every switch on, so it reflects what you have opened since.
    state.recent_cache = nil
    state.filter_dirty = true
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Recently opened projects, straight from REAPER's own history.\nIgnores the location, the folder view and the depth settings.\nHow many it shows is under Settings")
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "R", button_w, 0) then state.recent_cache = nil; start_scan(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Refresh") end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "...", button_w, 0) then state.settings_popup = true end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Settings") end
  local changed, value = UI.search_input(ctx, "##project_search", "Search", settings.search_term or "")
  if changed then
    settings.search_term = value
    state.search_changed_at = r.time_precise and r.time_precise() or os.clock()
    state.filter_dirty = true
    if app.save_settings then app.save_settings() end
  end
end

function M.init(app)
  local settings = ensure_settings(app)
  refresh_locations(settings)
  local mode = active_mode(settings)
  if get_mode_location(settings, mode) ~= "" then start_scan(app, settings) end
end

function M.update(app)
  local settings = ensure_settings(app)
  -- Asked here rather than from the Manage list, because this runs before the
  -- ImGui frame is built and a blocking dialog cannot disturb it from here.
  local pending = state.pending_preview_delete
  if pending then
    state.pending_preview_delete = nil
    if pending.entry and pending.entry.name then
      local result = r.ShowMessageBox("Delete preview file?\n\n" .. pending.entry.name, "Confirm", 4)
      if result == 6 then delete_project_preview_file(app, pending.project, pending.entry) end
    end
  end
  local make = state.pending_preview_make
  if make then
    state.pending_preview_make = nil
    if make.project then make_project_preview(app, settings, make.project, make.mode) end
  end
  local opening = state.pending_open_project
  if opening then
    state.pending_open_project = nil
    open_project_now(app, opening.project, opening.new_tab)
  end
  scan_step(settings)
  update_project_preview(app)
  if state.filter_dirty then
    local now = r.time_precise and r.time_precise() or os.clock()
    if state.scanning or now - (state.search_changed_at or 0) >= 0.15 then apply_filter(settings) end
  end
end

function M.draw(app)
  local ctx = app.ctx
  process_cover_queue(ctx)
  local settings = ensure_settings(app)
  local _, mode_def = active_mode(settings)
  draw_toolbar(app, settings)
  draw_settings_popup(app, settings)
  local width, height = r.ImGui_GetContentRegionAvail(ctx)
  -- Hidden panels take no height at all and no spacing either, so whatever they
  -- were using goes to the list rather than leaving a gap behind.
  local show_detail = settings.show_detail_panel ~= false
  local show_playback = settings.show_playback_panel ~= false
  local strip_h = (r.ImGui_GetFrameHeight and r.ImGui_GetFrameHeight(ctx) or UIScale.round(22)) + UIScale.round(18)
  local detail_h = 0
  if show_detail then
    detail_h = state.detail_panel_collapsed == true and strip_h or math.min(UIScale.round(166), math.max(UIScale.round(150), height * 0.25))
  end
  local playback_h = 0
  if show_playback then
    playback_h = state.playback_panel_collapsed == true and strip_h or UIScale.round(112)
  end
  local bottom_margin = 1
  local panel_count = (show_detail and 1 or 0) + (show_playback and 1 or 0)
  local spacing_h = UIScale.round(9) * panel_count + bottom_margin
  local list_h = height - detail_h - playback_h - spacing_h
  if list_h < UIScale.round(76) then
    local shortage = UIScale.round(76) - list_h
    if show_detail then
      local detail_min = state.detail_panel_collapsed == true and strip_h or UIScale.round(132)
      local detail_reduce = math.min(shortage, math.max(0, detail_h - detail_min))
      detail_h = detail_h - detail_reduce
      shortage = shortage - detail_reduce
    end
    if shortage > 0 and show_playback then
      local playback_min = state.playback_panel_collapsed == true and strip_h or UIScale.round(96)
      playback_h = math.max(playback_min, playback_h - shortage)
    end
    list_h = math.max(UIScale.round(48), height - detail_h - playback_h - spacing_h)
  end
  draw_project_list(app, settings, width, list_h)
  if show_detail then draw_project_detail(app, state.selected_project, width, detail_h) end
  if show_playback then draw_project_playback_panel(app, state.selected_project, width, playback_h) end
  r.ImGui_Dummy(ctx, 1, bottom_margin)
  local status = mode_def.label .. ": " .. tostring(#state.filtered)
  local mode = active_mode(settings)
  local folder_path = get_mode_folder_path(settings, mode)
  if settings.folder_view == true and tostring(settings.search_term or "") == "" then
    status = mode_def.label .. ": " .. tostring(#state.visible_entries) .. " entries"
    if folder_path ~= "" then status = status .. " | " .. folder_path end
  end
  if state.scanning then status = status .. " | scanning " .. tostring(#state.projects) end
  if state.scan_limited then status = status .. " | limited" end
  if state.last_error then status = status .. " | " .. state.last_error end
  app.status = status
end

function M.shutdown(app)
  stop_project_preview()
  clear_project_cache(app.ctx)
end

return M