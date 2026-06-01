local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local categorizer = require("core.media_categorizer")

local M = {
  id = "media_browser",
  title = "Media Browser",
  icon = "MED",
  version = "0.1.4"
}

local resource_path = r.GetResourcePath()
local locations_path = resource_path .. "/Scripts/TK_media_browser_locations.txt"
local cache_dir = resource_path .. "/Scripts/TK_Workbench_media_cache"
local peak_debug_path = resource_path .. "/Scripts/TK_Workbench_media_peak_debug.txt"
local PROJECT_FILES_LOCATION = "::current_project_files::"

local defaults = {
  search_term = "",
  current_location = "",
  last_browse_location = "",
  location_view_mode = "folders",
  folder_browse = false,
  auto_selected_category = "All",
  show_audio = true,
  show_midi = true,
  show_video = false,
  show_image = true,
  recursive = true,
  max_scan_files = 50000,
  waveform_height = 128,
  preview_volume = 1.0,
  preview_fade_ms = 0,
  preview_restart_gap_ms = 12,
  preview_pitch = 0,
  preview_rate = 1.0,
  preview_tape_speed = false,
  tempo_sync = false,
  loop_preview = false,
  auto_play = false,
  auto_play_next = false,
  random_play_next = false,
  min_display_time = 0,
  link_transport = false,
  link_start_from_editcursor = false,
  exclusive_solo_preview = false,
  use_selected_track_for_audio = false,
  use_selected_track_for_midi = false,
  folder_double_click_open = false,
  trim_silence_enabled = false,
  trim_silence_threshold_db = -48,
  trim_silence_padding_ms = 8
}

local audio_ext = { wav = true, wave = true, aif = true, aiff = true, flac = true, mp3 = true, ogg = true, opus = true, m4a = true, wv = true }
local midi_ext = { mid = true, midi = true, rpp = false }
local video_ext = { mp4 = true, mov = true, mkv = true, avi = true, webm = true, mpg = true, mpeg = true, wmv = true, flv = true, m4v = true, gif = true }
local image_ext = { png = true, jpg = true, jpeg = true, webp = true, bmp = true }

local state = {
  locations = {},
  files = {},
  filtered = {},
  selected_index = nil,
  selected_file = nil,
  file_list_keyboard_focus = false,
  scroll_selected_file = false,
  scan_queue = {},
  scanning = false,
  scan_total = 0,
  scan_seen = {},
  scan_limited = false,
  activated = false,
  loaded_location = "",
  scanning_location = "",
  cache_status = "",
  folder_path = "",
  filtered_file_count = 0,
  visible_file_count = 0,
  last_filter_key = nil,
  metadata_cache = {},
  category_cache = {},
  category_counts = {},
  category_counts_key = "",
  image_cache = {},
  folder_art_path_cache = {},
  folder_art_image_cache = {},
  waveform_cache = {},
  midi_note_cache = {},
  waveform_pending = {},
  waveform_build_pending = {},
  waveform_refresh_pending = {},
  waveform_debug_logged = {},
  waveform_peak_sources = {},
  waveform_selection_file = nil,
  waveform_selection_start = 0,
  waveform_selection_end = 0,
  waveform_dragging = false,
  waveform_selection_auto = false,
  waveform_zoom = 1.0,
  waveform_scroll = 0.0,
  waveform_vertical_zoom = 1.0,
  silence_trim_cache = {},
  preview = nil,
  preview_source = nil,
  preview_path = nil,
  preview_kind = nil,
  preview_track = nil,
  preview_item = nil,
  preview_take = nil,
  preview_track_owned = false,
  preview_track_playback = false,
  preview_length = 0,
  preview_source_length = 0,
  preview_started_at = 0,
  auto_advance_pending = false,
  auto_advance_due = 0,
  preview_paused = false,
  preview_paused_position = 0,
  preview_paused_project_position = nil,
  preview_fade = nil,
  pending_preview_file = nil,
  pending_preview_settings = nil,
  pending_preview_due = 0,
  retired_preview_sources = {},
  project_files_signature = "",
  last_transport_state = 0,
  saved_loop_start = nil,
  saved_loop_end = nil,
  saved_repeat = nil,
  saved_cursor = nil,
  saved_solo_states = nil,
  potential_drag_file = nil,
  potential_drag_x = 0,
  potential_drag_y = 0,
  dragging_file = nil,
  drag_target_track = nil,
  drag_target_lane = nil,
  drag_saved_cursor = nil,
  drag_cursor_position = nil,
  drag_threshold = 4,
  last_error = nil
}

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local target = {}
  for key, child in pairs(value) do target[key] = copy_default(child) end
  return target
end

local function ensure_settings(app)
  app.settings.media_browser = app.settings.media_browser or {}
  local settings = app.settings.media_browser
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  local max_scan_files = math.floor(tonumber(settings.max_scan_files) or defaults.max_scan_files)
  if max_scan_files == 2500 then max_scan_files = defaults.max_scan_files end
  if settings.max_scan_files ~= max_scan_files then changed = true end
  settings.max_scan_files = math.max(100, max_scan_files)
  settings.waveform_height = math.max(72, math.min(220, math.floor(tonumber(settings.waveform_height) or defaults.waveform_height)))
  if settings.preview_fade_defaulted ~= true then
    settings.preview_fade_ms = 0
    settings.preview_fade_defaulted = true
    changed = true
  end
  settings.preview_volume = math.max(0, math.min(2, tonumber(settings.preview_volume) or defaults.preview_volume))
  settings.preview_fade_ms = math.max(0, math.min(250, tonumber(settings.preview_fade_ms) or defaults.preview_fade_ms))
  settings.preview_restart_gap_ms = math.max(0, math.min(100, tonumber(settings.preview_restart_gap_ms) or defaults.preview_restart_gap_ms))
  settings.preview_pitch = math.max(-24, math.min(24, tonumber(settings.preview_pitch) or defaults.preview_pitch))
  settings.preview_rate = math.max(0.25, math.min(4, tonumber(settings.preview_rate) or defaults.preview_rate))
  settings.preview_tape_speed = settings.preview_tape_speed == true
  settings.min_display_time = (tonumber(settings.min_display_time) or 0) > 0 and 1.0 or 0
  settings.trim_silence_threshold_db = math.max(-96, math.min(-12, tonumber(settings.trim_silence_threshold_db) or defaults.trim_silence_threshold_db))
  settings.trim_silence_padding_ms = math.max(0, math.min(250, tonumber(settings.trim_silence_padding_ms) or defaults.trim_silence_padding_ms))
  if settings.location_view_mode ~= "auto" then settings.location_view_mode = "folders" end
  settings.folder_browse = settings.folder_browse == true
  settings.folder_double_click_open = settings.folder_double_click_open == true
  settings.auto_selected_category = tostring(settings.auto_selected_category or defaults.auto_selected_category)
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function ensure_cache_dir()
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(cache_dir, 0) end
end

local function normalize_path(path)
  path = tostring(path or ""):gsub("\\", "/")
  return path:gsub("/+$", "")
end

local function read_locations()
  local result = {}
  local seen = {}
  local file = io.open(locations_path, "r")
  if file then
    for line in file:lines() do
      local path = normalize_path(line:match("^%s*(.-)%s*$"))
      if path ~= "" and not seen[path:lower()] then
        seen[path:lower()] = true
        result[#result + 1] = path
      end
    end
    file:close()
  end
  return result
end

local function write_locations(locations)
  local file = io.open(locations_path, "w")
  if not file then return false end
  for _, path in ipairs(locations or {}) do file:write(path, "\n") end
  file:close()
  return true
end

local function extension(path)
  local ext = tostring(path or ""):match("%.([^%./\\]+)$")
  return ext and ext:lower() or ""
end

local function file_kind(path)
  local ext = extension(path)
  if audio_ext[ext] then return "audio" end
  if midi_ext[ext] then return "midi" end
  if video_ext[ext] then return "video" end
  if image_ext[ext] then return "image" end
  return "other"
end

local function is_supported(path)
  local kind = file_kind(path)
  return kind == "audio" or kind == "midi" or kind == "video" or kind == "image"
end

local function filename(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function parent_folder(path)
  return normalize_path(path):match("(.+)/[^/]+$") or ""
end

local function relative_folder(path, root)
  root = normalize_path(root)
  local folder = parent_folder(path)
  if root == "" or folder == "" then return "" end
  local lower_folder = folder:lower()
  local lower_root = root:lower()
  if lower_folder == lower_root then return "" end
  if lower_folder:sub(1, #lower_root + 1) == lower_root .. "/" then return folder:sub(#root + 2) end
  return folder
end

local function folder_parent(path)
  return tostring(path or ""):match("(.+)/[^/]+$") or ""
end

local function format_file_size(path)
  local file = io.open(path, "rb")
  if not file then return "" end
  local size = file:seek("end")
  file:close()
  if not size then return "" end
  if size < 1024 then return tostring(size) .. " B" end
  if size < 1024 * 1024 then return string.format("%.1f KB", size / 1024) end
  if size < 1024 * 1024 * 1024 then return string.format("%.1f MB", size / (1024 * 1024)) end
  return string.format("%.2f GB", size / (1024 * 1024 * 1024))
end

local function format_duration(length)
  if not length or length <= 0 then return "" end
  if length < 60 then return string.format("%.2fs", length) end
  local mins = math.floor(length / 60)
  local secs = math.floor(length % 60)
  return string.format("%d:%02d", mins, secs)
end

local function file_metadata(file)
  if not file then return {} end
  local cached = state.metadata_cache[file.path]
  if cached then return cached end
  local meta = { type = file.ext and file.ext:upper() or file.kind:upper(), size = format_file_size(file.path), duration = "", sample_rate = "", channels = "" }
  if file.kind == "audio" or file.kind == "midi" then
    local source = r.PCM_Source_CreateFromFile(file.path)
    if source then
      local length = r.GetMediaSourceLength(source)
      if file.kind == "midi" and length then length = length / 2 end
      meta.duration = format_duration(length)
      if file.kind == "audio" then
        local sr = r.GetMediaSourceSampleRate and r.GetMediaSourceSampleRate(source) or nil
        local ch = r.GetMediaSourceNumChannels(source)
        if sr and sr > 0 then meta.sample_rate = string.format("%.0fk", sr / 1000) end
        if ch and ch > 0 then meta.channels = ch == 1 and "Mono" or (ch == 2 and "Stereo" or tostring(ch) .. "ch") end
      end
      r.PCM_Source_Destroy(source)
    end
  end
  state.metadata_cache[file.path] = meta
  return meta
end

local function compact_tags(file)
  local meta = file_metadata(file)
  local parts = {}
  local function add(value) if value and value ~= "" then parts[#parts + 1] = value end end
  add(meta.type)
  add(meta.size)
  add(meta.duration)
  add(meta.sample_rate)
  add(meta.channels)
  return table.concat(parts, " - ")
end

local function destroy_image(ctx, path)
  local entry = state.image_cache[path]
  if entry and entry.image and r.ImGui_DestroyImage then pcall(r.ImGui_DestroyImage, ctx, entry.image) end
  state.image_cache[path] = nil
end

local function clear_image_cache(ctx, keep_path)
  for path in pairs(state.image_cache) do
    if path ~= keep_path then destroy_image(ctx, path) end
  end
end

function destroy_folder_art(ctx, path)
  local entry = state.folder_art_image_cache[path]
  if entry and entry.image and r.ImGui_DestroyImage then pcall(r.ImGui_DestroyImage, ctx, entry.image) end
  state.folder_art_image_cache[path] = nil
end

function clear_folder_art_cache(ctx)
  for path in pairs(state.folder_art_image_cache) do destroy_folder_art(ctx, path) end
  state.folder_art_path_cache = {}
end

function folder_art_path(folder)
  folder = normalize_path(folder)
  if folder == "" then return nil end
  if state.folder_art_path_cache[folder] ~= nil then return state.folder_art_path_cache[folder] or nil end
  local names = { "cover.jpg", "cover.jpeg", "cover.png", "cover.webp", "folder.jpg", "folder.jpeg", "folder.png", "folder.webp", "front.jpg", "front.jpeg", "front.png" }
  for _, name in ipairs(names) do
    local path = folder .. "/" .. name
    if file_exists(path) then
      state.folder_art_path_cache[folder] = path
      return path
    end
  end
  state.folder_art_path_cache[folder] = false
  return nil
end

function load_folder_art(ctx, folder)
  if not r.ImGui_CreateImage then return nil end
  local path = folder_art_path(folder)
  if not path then return nil end
  local cached = state.folder_art_image_cache[path]
  if cached then return cached end
  local cache_count = 0
  for _ in pairs(state.folder_art_image_cache) do cache_count = cache_count + 1 end
  if cache_count > 80 then clear_folder_art_cache(ctx) end
  local ok, image = pcall(r.ImGui_CreateImage, path)
  if not ok or not image then state.folder_art_path_cache[normalize_path(folder)] = false; return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, image) end
  local img_w, img_h = 0, 0
  if r.ImGui_Image_GetSize then
    local size_ok, w, h = pcall(r.ImGui_Image_GetSize, image)
    if size_ok then img_w, img_h = w or 0, h or 0 end
  end
  local entry = { image = image, width = img_w, height = img_h, path = path }
  state.folder_art_image_cache[path] = entry
  return entry
end

local function load_image(ctx, file)
  if not file or file.kind ~= "image" or not r.ImGui_CreateImage then return nil end
  local cached = state.image_cache[file.path]
  if cached then return cached end
  clear_image_cache(ctx, file.path)
  local ok, image = pcall(r.ImGui_CreateImage, file.path)
  if not ok or not image then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, image) end
  local img_w, img_h = 0, 0
  if r.ImGui_Image_GetSize then
    local size_ok, w, h = pcall(r.ImGui_Image_GetSize, image)
    if size_ok then img_w, img_h = w or 0, h or 0 end
  end
  local entry = { image = image, width = img_w, height = img_h }
  state.image_cache[file.path] = entry
  return entry
end

local function selected_location(settings)
  if settings.current_location == PROJECT_FILES_LOCATION then return PROJECT_FILES_LOCATION end
  if settings.current_location ~= "" then return settings.current_location end
  return state.locations[1] or ""
end

local function is_project_files_location(path)
  return path == PROJECT_FILES_LOCATION
end

local function location_label(path)
  if is_project_files_location(path) then return "Project files" end
  return path ~= "" and filename(path) or "No location"
end

local function project_files_tooltip()
  local _, project_path = r.EnumProjects(-1, "")
  if project_path and project_path ~= "" then return project_path end
  return "Media files used in the current project"
end

local function cache_key(path)
  path = normalize_path(path)
  local hash = 5381
  for index = 1, #path do hash = (hash * 33 + path:byte(index)) % 2147483647 end
  return tostring(hash) .. "_" .. filename(path):gsub("[^%w_]", "_")
end

local function cache_path(location)
  return cache_dir .. "/media_" .. cache_key(location) .. ".idx"
end

local function legacy_cache_path(location)
  return cache_dir .. "/media_" .. cache_key(location) .. ".lua"
end

local function cache_escape(value)
  return tostring(value or ""):gsub("%%", "%%25"):gsub("\t", "%%09"):gsub("\r", "%%0D"):gsub("\n", "%%0A")
end

local function cache_unescape(value)
  return tostring(value or ""):gsub("%%09", "\t"):gsub("%%0D", "\r"):gsub("%%0A", "\n"):gsub("%%25", "%%")
end

local function split_cache_line(line)
  line = tostring(line or "")
  local parts = {}
  local start_pos = 1
  while true do
    local tab_pos = line:find("\t", start_pos, true)
    if not tab_pos then
      parts[#parts + 1] = line:sub(start_pos)
      break
    end
    parts[#parts + 1] = line:sub(start_pos, tab_pos - 1)
    start_pos = tab_pos + 1
  end
  return parts
end

local function save_location_cache(location, files)
  if not location or location == "" or is_project_files_location(location) then return false end
  ensure_cache_dir()
  local path = cache_path(location)
  local temp_path = path .. ".tmp"
  local file = io.open(temp_path, "w")
  if not file then return false end
  file:write("TKWBMEDIA1\n")
  file:write("location\t", cache_escape(normalize_path(location)), "\n")
  file:write("cache_time\t", tostring(os.time()), "\n")
  for _, entry in ipairs(files or {}) do
    file:write("file\t", cache_escape(entry.path), "\t", cache_escape(entry.name), "\t", cache_escape(entry.kind), "\t", cache_escape(entry.ext), "\t", cache_escape(entry.rel_dir), "\n")
  end
  file:close()
  os.remove(path)
  return os.rename(temp_path, path) == true
end

local function load_location_cache(location)
  if not location or location == "" or is_project_files_location(location) then return nil end
  local file = io.open(cache_path(location), "r")
  if not file then return nil end
  local header = file:read("*l")
  if header ~= "TKWBMEDIA1" then file:close(); return nil end
  local expected_location = normalize_path(location)
  local cached_location = ""
  local files = {}
  local cache_time = 0
  for line in file:lines() do
    local parts = split_cache_line(line)
    if parts[1] == "location" then
      cached_location = normalize_path(cache_unescape(parts[2]))
    elseif parts[1] == "cache_time" then
      cache_time = tonumber(parts[2]) or 0
    elseif parts[1] == "file" then
      local path = normalize_path(cache_unescape(parts[2]))
      local kind = cache_unescape(parts[4])
      if path ~= "" and kind ~= "" then
        files[#files + 1] = { path = path, name = cache_unescape(parts[3]), kind = kind, ext = cache_unescape(parts[5] or extension(path)), rel_dir = cache_unescape(parts[6]) }
      end
    end
  end
  file:close()
  if cached_location ~= expected_location then return nil end
  return files, cache_time
end

local function delete_location_cache(location)
  if not location or location == "" or is_project_files_location(location) then return end
  os.remove(cache_path(location))
  os.remove(cache_path(location) .. ".tmp")
  os.remove(legacy_cache_path(location))
end

local function browse_location(settings)
  local start_folder = normalize_path(settings.last_browse_location)
  if start_folder == "" then start_folder = normalize_path(selected_location(settings)) end
  if r.JS_Dialog_BrowseForFolder then
    local ok, folder = r.JS_Dialog_BrowseForFolder(0, "Select media location", start_folder)
    if ok and folder and folder ~= "" then return normalize_path(folder) end
    return ""
  end
  local ok, value = r.GetUserInputs("Add media location", 1, "Folder path:,extrawidth=260", start_folder)
  if not ok then return "" end
  return normalize_path(value)
end

local function refresh_locations(settings)
  state.locations = read_locations()
  local current = normalize_path(settings.current_location)
  if settings.current_location == PROJECT_FILES_LOCATION then return end
  local found = false
  for _, path in ipairs(state.locations) do
    if path:lower() == current:lower() then found = true; break end
  end
  if not found then settings.current_location = state.locations[1] or "" end
end

local function reset_scan()
  state.files = {}
  state.filtered = {}
  state.filtered_file_count = 0
  state.visible_file_count = 0
  state.scan_queue = {}
  state.scan_seen = {}
  state.scan_total = 0
  state.scanning = false
  state.scan_limited = false
  state.scanning_location = ""
  state.folder_path = ""
  state.selected_index = nil
  state.selected_file = nil
  state.last_filter_key = nil
  state.metadata_cache = {}
  state.midi_note_cache = {}
  state.category_cache = {}
  state.category_counts = {}
  state.category_counts_key = ""
  state.silence_trim_cache = {}
end

local clear_waveform_pending

local function set_loaded_files(location, files, status)
  clear_waveform_pending()
  reset_scan()
  state.files = files or {}
  state.loaded_location = location or ""
  state.cache_status = status or ""
  state.last_error = nil
  state.last_filter_key = nil
end

local function project_files_signature()
  local change_count = r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0) or 0
  return tostring(change_count) .. "|" .. tostring(r.CountMediaItems(0) or 0)
end

local function media_source_file_path(source)
  local current = source
  for _ = 1, 8 do
    if not current then return "" end
    local ok, path = pcall(r.GetMediaSourceFileName, current, "")
    if ok and path and path ~= "" then return normalize_path(path) end
    if not r.GetMediaSourceParent then break end
    local parent_ok, parent = pcall(r.GetMediaSourceParent, current)
    if not parent_ok or not parent or parent == current then break end
    current = parent
  end
  return ""
end

local function add_project_file(path, seen)
  path = normalize_path(path)
  if path == "" or seen[path:lower()] or not is_supported(path) then return end
  seen[path:lower()] = true
  local kind = file_kind(path)
  state.files[#state.files + 1] = { path = path, name = filename(path), kind = kind, ext = extension(path), rel_dir = "" }
end

local function collect_project_files()
  local seen = {}
  local item_count = r.CountMediaItems(0) or 0
  for item_index = 0, item_count - 1 do
    local item = r.GetMediaItem(0, item_index)
    local take_count = item and r.CountTakes(item) or 0
    for take_index = 0, take_count - 1 do
      local take = r.GetTake(item, take_index)
      local source = take and r.GetMediaItemTake_Source(take)
      add_project_file(media_source_file_path(source), seen)
    end
  end
  table.sort(state.files, function(left, right) return left.name:lower() < right.name:lower() end)
  state.project_files_signature = project_files_signature()
  state.last_filter_key = nil
end

local function destroy_waveform_source(path)
  local source = state.waveform_peak_sources[path]
  if source and r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
  state.waveform_peak_sources[path] = nil
end

clear_waveform_pending = function()
  for path in pairs(state.waveform_peak_sources) do destroy_waveform_source(path) end
  state.waveform_pending = {}
  state.waveform_build_pending = {}
  state.waveform_refresh_pending = {}
end

local function enqueue_folder(path)
  path = normalize_path(path)
  if path == "" or state.scan_seen[path:lower()] then return end
  state.scan_seen[path:lower()] = true
  state.scan_queue[#state.scan_queue + 1] = path
end

local function start_scan(settings)
  clear_waveform_pending()
  reset_scan()
  local path = selected_location(settings)
  if path == "" then state.last_error = "No media location"; return end
  if is_project_files_location(path) then
    collect_project_files()
    state.loaded_location = path
    state.cache_status = "project"
    state.scanning = false
    state.last_error = nil
    return
  end
  enqueue_folder(path)
  state.loaded_location = path
  state.scanning_location = path
  state.cache_status = "scanning"
  state.scanning = true
  state.last_error = nil
end

local function add_file(path, root)
  if not is_supported(path) then return end
  path = normalize_path(path)
  local kind = file_kind(path)
  state.files[#state.files + 1] = { path = path, name = filename(path), kind = kind, ext = extension(path), rel_dir = relative_folder(path, root) }
end

local function scan_step(settings)
  if not state.scanning then return end
  local budget = 18
  local max_files = settings.max_scan_files or defaults.max_scan_files
  local root = state.scanning_location ~= "" and state.scanning_location or selected_location(settings)
  while budget > 0 and #state.scan_queue > 0 and #state.files < max_files do
    local folder = table.remove(state.scan_queue, 1)
    local file_index = 0
    while #state.files < max_files do
      local name = r.EnumerateFiles(folder, file_index)
      if not name then break end
      add_file(folder .. "/" .. name, root)
      file_index = file_index + 1
    end
    if settings.recursive ~= false then
      local dir_index = 0
      while true do
        local name = r.EnumerateSubdirectories(folder, dir_index)
        if not name then break end
        enqueue_folder(folder .. "/" .. name)
        dir_index = dir_index + 1
      end
    end
    state.scan_total = state.scan_total + 1
    budget = budget - 1
  end
  if #state.scan_queue == 0 or #state.files >= max_files then
    table.sort(state.files, function(left, right) return left.name:lower() < right.name:lower() end)
    state.scan_limited = #state.files >= max_files
    state.scanning = false
    if state.scanning_location ~= "" then save_location_cache(state.scanning_location, state.files) end
    state.cache_status = state.scan_limited and "limited" or "cached"
    state.last_filter_key = nil
  end
end

local function load_or_scan_location(settings, force_refresh)
  local path = selected_location(settings)
  if path == "" then state.last_error = "No media location"; return end
  if is_project_files_location(path) then
    if force_refresh or state.loaded_location ~= path or state.project_files_signature ~= project_files_signature() then
      set_loaded_files(path, {}, "project")
      collect_project_files()
      state.loaded_location = path
      state.cache_status = "project"
    end
    return
  end
  if not force_refresh and state.loaded_location == path and (state.scanning or #state.files > 0 or state.cache_status ~= "") then return end
  if force_refresh then delete_location_cache(path) end
  if not force_refresh then
    local cached = load_location_cache(path)
    if cached then set_loaded_files(path, cached, "cached"); return end
  end
  start_scan(settings)
end

function category_for_file(file)
  if not file then return "other" end
  local key = file.path or file.name or ""
  local cached = state.category_cache[key]
  if cached then return cached end
  local folder = tostring(file.path or ""):match("(.+)[/\\]") or ""
  local category = categorizer.classify(file.name or file.path or "", folder)
  state.category_cache[key] = category
  return category
end

function auto_category_scope(settings)
  if settings.location_view_mode ~= "auto" then return "" end
  if is_project_files_location(selected_location(settings)) then return "" end
  return tostring(state.folder_path or "")
end

function file_in_folder_scope(file, folder_path)
  if folder_path == "" then return true end
  return tostring(file and file.rel_dir or "") == folder_path
end

function build_category_counts(settings)
  local folder_scope = auto_category_scope(settings)
  local key = table.concat({ selected_location(settings), folder_scope, tostring(#state.files) }, "|")
  if state.category_counts_key == key then return end
  local counts = { All = 0, other = 0 }
  for _, category in ipairs(categorizer.get_category_order()) do counts[category] = 0 end
  for _, file in ipairs(state.files) do
    if file_in_folder_scope(file, folder_scope) then
      counts.All = counts.All + 1
      local category = category_for_file(file)
      counts[category] = (counts[category] or 0) + 1
    end
  end
  state.category_counts = counts
  state.category_counts_key = key
end

function category_label(category)
  if category == "All" then return "All" end
  local text = tostring(category or "other")
  return text:sub(1, 1):upper() .. text:sub(2)
end

function folder_browse_active(settings)
  return settings.folder_browse == true and settings.location_view_mode ~= "auto" and not is_project_files_location(selected_location(settings))
end

local function add_folder_entry(folders, seen, path, count)
  if not path or path == "" then return end
  local key = path:lower()
  local folder = seen[key]
  if not folder then
    folder = { kind = "folder", path = path, folder_path = path, name = filename(path), file_count = 0 }
    seen[key] = folder
    folders[#folders + 1] = folder
  end
  folder.file_count = folder.file_count + (count or 1)
end

local function build_folder_filter(files)
  local current = tostring(state.folder_path or "")
  local folders = {}
  local folder_seen = {}
  local visible_files = {}
  for _, file in ipairs(files) do
    local rel_dir = tostring(file.rel_dir or "")
    if current == "" then
      if rel_dir == "" then
        visible_files[#visible_files + 1] = file
      else
        local child = rel_dir:match("([^/]+)")
        add_folder_entry(folders, folder_seen, child, 1)
      end
    elseif rel_dir == current then
      visible_files[#visible_files + 1] = file
    else
      local prefix = current .. "/"
      if rel_dir:sub(1, #prefix) == prefix then
        local child = rel_dir:sub(#prefix + 1):match("([^/]+)")
        if child then add_folder_entry(folders, folder_seen, prefix .. child, 1) end
      end
    end
  end
  table.sort(folders, function(left, right) return left.name:lower() < right.name:lower() end)
  table.sort(visible_files, function(left, right) return left.name:lower() < right.name:lower() end)
  local result = {}
  if current ~= "" then result[#result + 1] = { kind = "folder_up", path = folder_parent(current), name = "..", file_count = 0 } end
  for _, folder in ipairs(folders) do result[#result + 1] = folder end
  for _, file in ipairs(visible_files) do result[#result + 1] = file end
  state.visible_file_count = #visible_files
  return result
end

local function filter_key(settings)
  return table.concat({ settings.search_term or "", tostring(settings.show_audio), tostring(settings.show_midi), tostring(settings.show_video), tostring(settings.show_image), tostring(settings.location_view_mode), tostring(settings.folder_browse), tostring(state.folder_path or ""), tostring(settings.auto_selected_category), tostring(#state.files), state.category_counts_key or "" }, "|")
end

local function refresh_filter(settings)
  if settings.location_view_mode == "auto" then build_category_counts(settings) end
  local key = filter_key(settings)
  if key == state.last_filter_key then return end
  local term = tostring(settings.search_term or ""):lower()
  local auto_scope = settings.location_view_mode == "auto" and auto_category_scope(settings) or ""
  local result = {}
  for _, file in ipairs(state.files) do
    local include = true
    if file.kind == "audio" and settings.show_audio == false then include = false end
    if file.kind == "midi" and settings.show_midi == false then include = false end
    if file.kind == "video" and settings.show_video ~= true then include = false end
    if file.kind == "image" and settings.show_image ~= true then include = false end
    if include and settings.location_view_mode == "auto" and not file_in_folder_scope(file, auto_scope) then include = false end
    if include and settings.location_view_mode == "auto" and settings.auto_selected_category ~= "All" then
      include = category_for_file(file) == settings.auto_selected_category
    end
    if include and term ~= "" and not (file.name:lower():find(term, 1, true) or file.path:lower():find(term, 1, true)) then include = false end
    if include then result[#result + 1] = file end
  end
  state.filtered_file_count = #result
  if folder_browse_active(settings) and term == "" then
    state.filtered = build_folder_filter(result)
  else
    state.filtered = result
    state.visible_file_count = #result
  end
  state.last_filter_key = key
  if state.selected_file then
    local found = false
    for index, file in ipairs(state.filtered) do
      if file.path == state.selected_file.path then state.selected_index = index; found = true; break end
    end
    if not found then
      state.selected_index = nil
      if not folder_browse_active(settings) or term ~= "" then state.selected_file = nil end
    end
  end
end

local function visible_range(ctx, item_count, item_height, buffer)
  if item_count <= 0 then return 1, 0, 0, 0 end
  local scroll_y = r.ImGui_GetScrollY(ctx)
  local window_h = r.ImGui_GetWindowHeight(ctx)
  local first = math.min(item_count, math.max(1, math.floor(scroll_y / item_height) + 1 - buffer))
  local last = math.min(item_count, math.ceil((scroll_y + window_h) / item_height) + buffer)
  if last < first then last = first end
  return first, last, (first - 1) * item_height, math.max(0, (item_count - last) * item_height)
end

local function track_pointer_valid(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
  if r.ValidatePtr then return r.ValidatePtr(track, "MediaTrack*") end
  return true
end

local function take_pointer_valid(take)
  if not take then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, take, "MediaItem_Take*") end
  if r.ValidatePtr then return r.ValidatePtr(take, "MediaItem_Take*") end
  return true
end

local function volume_to_db(volume)
  volume = tonumber(volume) or 0
  if volume <= 0.000001 then return -60 end
  return 20 * (math.log(volume) / math.log(10))
end

local function db_to_volume(db)
  db = tonumber(db) or -60
  if db <= -60 then return 0 end
  return 10 ^ (db / 20)
end

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function right_clicked(ctx)
  if not r.ImGui_IsMouseClicked then return false end
  local button = r.ImGui_MouseButton_Right and r.ImGui_MouseButton_Right() or 1
  return r.ImGui_IsMouseClicked(ctx, button)
end

local function hovered_mouse_wheel(ctx, enabled)
  if enabled == false or not r.ImGui_GetMouseWheel or not r.ImGui_IsItemHovered then return 0 end
  if not r.ImGui_IsItemHovered(ctx) then return 0 end
  local wheel = r.ImGui_GetMouseWheel(ctx)
  return tonumber(wheel) or 0
end

local function clear_waveform_selection()
  state.waveform_selection_file = nil
  state.waveform_selection_start = 0
  state.waveform_selection_end = 0
  state.waveform_dragging = false
  state.waveform_selection_auto = false
end

local function waveform_selection_active(file)
  return file and file.kind == "audio" and state.waveform_selection_file == file.path and math.abs((state.waveform_selection_end or 0) - (state.waveform_selection_start or 0)) >= 0.01
end

local function waveform_selection_range(file, length)
  if not waveform_selection_active(file) or not length or length <= 0 then return nil, nil end
  local start_norm = math.min(state.waveform_selection_start or 0, state.waveform_selection_end or 0)
  local end_norm = math.max(state.waveform_selection_start or 0, state.waveform_selection_end or 0)
  return start_norm * length, end_norm * length
end

local function seek_audio_preview(position)
  position = math.max(0, tonumber(position) or 0)
  if state.preview and state.preview_kind == "audio" and r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(state.preview, "D_POSITION", position)
  elseif state.preview_paused and state.preview_kind == "audio" then
    state.preview_paused_position = position
  end
end

local function waveform_visible_range()
  state.waveform_zoom = clamp(tonumber(state.waveform_zoom) or 1.0, 1.0, 16.0)
  state.waveform_scroll = clamp(tonumber(state.waveform_scroll) or 0.0, 0.0, 1.0)
  local duration = 1.0 / state.waveform_zoom
  local max_scroll = math.max(0, 1.0 - duration)
  local start_norm = max_scroll > 0 and state.waveform_scroll * max_scroll or 0
  return start_norm, start_norm + duration, duration
end

local function waveform_view_to_norm(local_norm)
  local start_norm, _, duration = waveform_visible_range()
  return clamp(start_norm + clamp(local_norm, 0, 1) * duration, 0, 1)
end

local function waveform_norm_to_view(normalized)
  local start_norm, end_norm, duration = waveform_visible_range()
  normalized = tonumber(normalized) or 0
  if normalized < start_norm or normalized > end_norm then return nil end
  return duration > 0 and (normalized - start_norm) / duration or 0
end

local function reset_waveform_zoom()
  state.waveform_zoom = 1.0
  state.waveform_scroll = 0.0
  state.waveform_vertical_zoom = 1.0
end

local function modifier_down(ctx, name)
  local mod = r["ImGui_Mod_" .. name]
  if not r.ImGui_GetKeyMods or not mod then return false end
  local ok_mod, mod_value = pcall(mod)
  if not ok_mod or not mod_value then return false end
  local ok, mods = pcall(r.ImGui_GetKeyMods, ctx)
  if ok and mods then
    local ok_bits, down = pcall(function() return (mods & mod_value) ~= 0 end)
    return ok_bits and down == true
  end
  return false
end

local function mouse_button(name, fallback)
  local fn = r["ImGui_MouseButton_" .. name]
  if fn then
    local ok, value = pcall(fn)
    if ok and value ~= nil then return value end
  end
  return fallback
end

local function mouse_clicked(ctx, name, fallback)
  if not r.ImGui_IsMouseClicked then return false end
  local ok, clicked = pcall(r.ImGui_IsMouseClicked, ctx, mouse_button(name, fallback))
  return ok and clicked == true
end

local function mouse_down(ctx, name, fallback)
  if not r.ImGui_IsMouseDown then return false end
  local ok, down = pcall(r.ImGui_IsMouseDown, ctx, mouse_button(name, fallback))
  return ok and down == true
end

local function item_hovered(ctx)
  if not r.ImGui_IsItemHovered then return false end
  local ok, hovered = pcall(r.ImGui_IsItemHovered, ctx)
  return ok and hovered == true
end

local function mouse_position(ctx)
  if not r.ImGui_GetMousePos then return nil end
  local ok, mouse_x, mouse_y = pcall(r.ImGui_GetMousePos, ctx)
  if not ok then return nil end
  return tonumber(mouse_x), tonumber(mouse_y)
end

local function mouse_x_position(ctx)
  local mouse_x = mouse_position(ctx)
  return mouse_x
end

local function mouse_wheel_delta(ctx)
  if not r.ImGui_GetMouseWheel then return 0 end
  local ok, wheel = pcall(r.ImGui_GetMouseWheel, ctx)
  return ok and (tonumber(wheel) or 0) or 0
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

local function waveform_reset_rect(ctx, x, y, height)
  if math.abs((state.waveform_zoom or 1.0) - 1.0) < 0.001 and math.abs((state.waveform_vertical_zoom or 1.0) - 1.0) < 0.001 then return nil end
  local tw, th = r.ImGui_CalcTextSize(ctx, "RESET")
  return x + 8, y + height - th - 7, x + tw + 18, y + height - 4
end

local function waveform_reset_hovered(ctx, x, y, height)
  local x1, y1, x2, y2 = waveform_reset_rect(ctx, x, y, height)
  if not x1 then return false end
  local mx, my = mouse_position(ctx)
  if not mx or not my then return false end
  return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
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

local function draw_slider_value(ctx, text)
  if not r.ImGui_GetItemRectMin or not r.ImGui_GetItemRectMax or not r.ImGui_GetWindowDrawList then return end
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local tx = x1 + ((x2 - x1) - tw) * 0.5
  local ty = y1 + ((y2 - y1) - th) * 0.5
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, tx - 4, ty - 1, tx + tw + 4, ty + th + 1, (Theme.colors.frame_bg & 0xFFFFFF00) | 0xCC, 3)
  r.ImGui_DrawList_AddText(draw_list, tx, ty, Theme.colors.text, text)
end

local function draw_transport_button(ctx, id, icon, active, enabled, size)
  if not r.ImGui_InvisibleButton or not r.ImGui_GetWindowDrawList or not r.ImGui_GetCursorScreenPos then
    local clicked = r.ImGui_Button(ctx, id, size, size)
    return clicked and enabled ~= false, r.ImGui_IsItemHovered(ctx)
  end
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local color = Theme.colors.text_dim
  if enabled == false then color = Theme.colors.border elseif active then color = Theme.colors.accent elseif hovered then color = Theme.colors.text end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  if icon == "play" then
    r.ImGui_DrawList_AddTriangleFilled(draw_list, x + size * 0.24, y + size * 0.16, x + size * 0.24, y + size * 0.84, x + size * 0.82, y + size * 0.50, color)
  elseif icon == "pause" then
    local bar_w = size * 0.23
    local gap = size * 0.14
    local cx = x + size * 0.5
    r.ImGui_DrawList_AddRectFilled(draw_list, cx - bar_w - gap * 0.5, y + size * 0.16, cx - gap * 0.5, y + size * 0.84, color)
    r.ImGui_DrawList_AddRectFilled(draw_list, cx + gap * 0.5, y + size * 0.16, cx + bar_w + gap * 0.5, y + size * 0.84, color)
  elseif icon == "stop" then
    r.ImGui_DrawList_AddRectFilled(draw_list, x + size * 0.20, y + size * 0.20, x + size * 0.80, y + size * 0.80, color)
  elseif icon == "prev" then
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.22, y + size * 0.18, x + size * 0.22, y + size * 0.82, color, 1.5)
    r.ImGui_DrawList_AddTriangleFilled(draw_list, x + size * 0.78, y + size * 0.18, x + size * 0.78, y + size * 0.82, x + size * 0.30, y + size * 0.50, color)
  elseif icon == "next" then
    r.ImGui_DrawList_AddTriangleFilled(draw_list, x + size * 0.22, y + size * 0.18, x + size * 0.22, y + size * 0.82, x + size * 0.70, y + size * 0.50, color)
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.78, y + size * 0.18, x + size * 0.78, y + size * 0.82, color, 1.5)
  elseif icon == "random" then
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.18, y + size * 0.30, x + size * 0.42, y + size * 0.30, color, 1.5)
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.42, y + size * 0.30, x + size * 0.72, y + size * 0.70, color, 1.5)
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.18, y + size * 0.70, x + size * 0.42, y + size * 0.70, color, 1.5)
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.42, y + size * 0.70, x + size * 0.72, y + size * 0.30, color, 1.5)
    r.ImGui_DrawList_AddTriangleFilled(draw_list, x + size * 0.72, y + size * 0.24, x + size * 0.72, y + size * 0.36, x + size * 0.84, y + size * 0.30, color)
    r.ImGui_DrawList_AddTriangleFilled(draw_list, x + size * 0.72, y + size * 0.64, x + size * 0.72, y + size * 0.76, x + size * 0.84, y + size * 0.70, color)
  end
  return clicked and enabled ~= false, hovered
end

local function draw_text_transport_button(ctx, id, label, active, width, height)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), active and Theme.colors.accent or Theme.colors.text_dim)
  local clicked = r.ImGui_Button(ctx, label .. id, width, height)
  r.ImGui_PopStyleColor(ctx)
  return clicked, r.ImGui_IsItemHovered(ctx)
end

local function effective_playrate(source, kind, settings)
  local rate = tonumber(settings.preview_rate) or defaults.preview_rate
  if kind == "audio" and settings.tempo_sync and r.GetTempoMatchPlayRate then
    local ok, tempo_rate = r.GetTempoMatchPlayRate(source, 1, 0, 1)
    if ok and tempo_rate and tempo_rate > 0 then rate = tempo_rate end
  end
  return math.max(0.25, math.min(8, rate))
end

local function tape_speed_pitch_offset(rate)
  rate = tonumber(rate) or 1
  if rate <= 0 then return 0 end
  return 12 * (math.log(rate) / math.log(2))
end

local function effective_preview_pitch(settings, rate)
  local pitch = tonumber(settings.preview_pitch) or defaults.preview_pitch
  if settings.preview_tape_speed == true then pitch = pitch + tape_speed_pitch_offset(rate) end
  return math.max(-48, math.min(48, pitch))
end

local function display_playrate(settings)
  if not settings.tempo_sync then return settings.preview_rate end
  if state.preview_source then return effective_playrate(state.preview_source, state.preview_kind, settings) end
  if state.selected_file and state.selected_file.kind == "audio" then
    local source = r.PCM_Source_CreateFromFile(state.selected_file.path)
    if source then
      local rate = effective_playrate(source, "audio", settings)
      if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
      return rate
    end
  end
  return settings.preview_rate
end

local function apply_track_preview_rate(settings)
  if not state.preview_track_playback or not take_pointer_valid(state.preview_take) or not r.SetMediaItemTakeInfo_Value then return end
  local rate = effective_playrate(state.preview_source, state.preview_kind, settings)
  r.SetMediaItemTakeInfo_Value(state.preview_take, "D_PLAYRATE", rate)
  r.SetMediaItemTakeInfo_Value(state.preview_take, "D_PITCH", effective_preview_pitch(settings, rate))
  local length = state.preview_source_length > 0 and state.preview_source_length / rate or state.preview_length
  state.preview_length = length
  if state.preview_item then
    r.SetMediaItemLength(state.preview_item, length, false)
    r.UpdateItemInProject(state.preview_item)
  end
  r.GetSet_LoopTimeRange(true, true, 0, length, false)
end

local function apply_preview_rate(settings)
  if state.preview and r.CF_Preview_SetValue then
    local rate = effective_playrate(state.preview_source, state.preview_kind, settings)
    r.CF_Preview_SetValue(state.preview, "D_PLAYRATE", rate)
    r.CF_Preview_SetValue(state.preview, "D_PITCH", effective_preview_pitch(settings, rate))
    state.preview_length = state.preview_source_length > 0 and state.preview_source_length / rate or state.preview_length
  elseif state.preview_track_playback then
    apply_track_preview_rate(settings)
  elseif state.preview_paused and state.preview_source then
    local rate = effective_playrate(state.preview_source, state.preview_kind, settings)
    state.preview_length = state.preview_source_length > 0 and state.preview_source_length / rate or state.preview_length
  end
end

local function restore_solo_states()
  if not state.saved_solo_states then return end
  for track_index, solo_state in pairs(state.saved_solo_states) do
    local track = r.GetTrack(0, track_index)
    if track then r.SetMediaTrackInfo_Value(track, "I_SOLO", solo_state) end
  end
  state.saved_solo_states = nil
end

local function apply_exclusive_solo(track)
  if not track_pointer_valid(track) then return end
  state.saved_solo_states = {}
  local track_count = r.CountTracks(0)
  for index = 0, track_count - 1 do
    local project_track = r.GetTrack(0, index)
    if project_track then
      state.saved_solo_states[index] = r.GetMediaTrackInfo_Value(project_track, "I_SOLO") or 0
      r.SetMediaTrackInfo_Value(project_track, "I_SOLO", 0)
    end
  end
  r.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
end

local function preview_fade_seconds(settings)
  if not r.CF_Preview_SetValue then return 0 end
  return math.max(0, math.min(0.25, (tonumber(settings and settings.preview_fade_ms) or defaults.preview_fade_ms) / 1000))
end

local function preview_restart_gap_seconds(settings)
  return math.max(0, math.min(0.1, (tonumber(settings and settings.preview_restart_gap_ms) or defaults.preview_restart_gap_ms) / 1000))
end

local function retire_preview_source(source)
  if not source or not r.PCM_Source_Destroy then return end
  state.retired_preview_sources[#state.retired_preview_sources + 1] = {
    source = source,
    due = (r.time_precise and r.time_precise() or os.clock()) + 0.25
  }
end

local function cleanup_retired_preview_sources(force)
  if not r.PCM_Source_Destroy then state.retired_preview_sources = {}; return end
  local now = r.time_precise and r.time_precise() or os.clock()
  for index = #state.retired_preview_sources, 1, -1 do
    local entry = state.retired_preview_sources[index]
    if force or not entry or now >= (entry.due or 0) then
      if entry and entry.source then pcall(r.PCM_Source_Destroy, entry.source) end
      table.remove(state.retired_preview_sources, index)
    end
  end
end

local function set_preview_volume(volume)
  if state.preview and r.CF_Preview_SetValue then r.CF_Preview_SetValue(state.preview, "D_VOLUME", math.max(0, tonumber(volume) or 0)) end
end

local function destroy_preview_now(settings, from_transport)
  if settings and settings.link_transport and state.preview and not from_transport and r.CSurf_OnStop then r.CSurf_OnStop() end
  if state.preview and r.CF_Preview_Stop then r.CF_Preview_Stop(state.preview) end
  state.preview = nil
  if state.preview_track_playback then
    r.Main_OnCommand(1016, 0)
    restore_solo_states()
    if track_pointer_valid(state.preview_track) and state.preview_item then
      local count = r.CountTrackMediaItems(state.preview_track)
      for index = count - 1, 0, -1 do
        local item = r.GetTrackMediaItem(state.preview_track, index)
        if item == state.preview_item then r.DeleteTrackMediaItem(state.preview_track, item) end
      end
    end
    if state.preview_track_owned and track_pointer_valid(state.preview_track) then r.DeleteTrack(state.preview_track) end
    if state.saved_loop_start and state.saved_loop_end then r.GetSet_LoopTimeRange(true, true, state.saved_loop_start, state.saved_loop_end, false) end
    if state.saved_repeat ~= nil then r.GetSetRepeat(state.saved_repeat) end
    if state.saved_cursor then r.SetEditCurPos(state.saved_cursor, false, false) end
  elseif state.preview_track_owned and track_pointer_valid(state.preview_track) then
    r.DeleteTrack(state.preview_track)
    if state.preview_source and r.PCM_Source_Destroy then r.PCM_Source_Destroy(state.preview_source) end
  elseif state.preview_source then
    if state.preview_kind == "audio" then retire_preview_source(state.preview_source) elseif r.PCM_Source_Destroy then r.PCM_Source_Destroy(state.preview_source) end
  end
  state.preview_source = nil
  state.preview_path = nil
  state.preview_kind = nil
  state.preview_track = nil
  state.preview_item = nil
  state.preview_take = nil
  state.preview_track_owned = false
  state.preview_track_playback = false
  state.preview_length = 0
  state.preview_source_length = 0
  state.preview_started_at = 0
  state.auto_advance_pending = false
  state.auto_advance_due = 0
  state.preview_paused = false
  state.preview_paused_position = 0
  state.preview_paused_project_position = nil
  state.preview_fade = nil
  state.pending_preview_file = nil
  state.pending_preview_settings = nil
  state.pending_preview_due = 0
  state.saved_loop_start = nil
  state.saved_loop_end = nil
  state.saved_repeat = nil
  state.saved_cursor = nil
  state.saved_solo_states = nil
end

local function destroy_preview(settings, from_transport, immediate)
  if immediate or state.preview_track_playback or state.preview_paused or not state.preview or state.preview_kind ~= "audio" then
    destroy_preview_now(settings, from_transport)
    return
  end
  local duration = preview_fade_seconds(settings)
  if duration <= 0 then
    destroy_preview_now(settings, from_transport)
    return
  end
  if state.preview_fade and state.preview_fade.kind == "out" then return end
  local current_volume = tonumber(settings and settings.preview_volume) or defaults.preview_volume
  if r.CF_Preview_GetValue then
    local ok, value_ok, value = pcall(r.CF_Preview_GetValue, state.preview, "D_VOLUME")
    if ok and value_ok and value then current_volume = tonumber(value) or current_volume end
  end
  state.preview_fade = {
    kind = "out",
    preview = state.preview,
    started = r.time_precise and r.time_precise() or os.clock(),
    duration = duration,
    from_volume = current_volume,
    settings = settings,
    from_transport = from_transport
  }
end

local function validate_track(track)
  return track_pointer_valid(track)
end

local function track_label(track)
  if not validate_track(track) then return "No track" end
  local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  local _, name = r.GetTrackName(track)
  if not name or name == "" then name = index > 0 and ("Track " .. tostring(index)) or "MASTER" end
  return index > 0 and (tostring(index) .. " - " .. name) or name
end

local function clear_drag()
  state.potential_drag_file = nil
  state.dragging_file = nil
  state.drag_target_track = nil
  state.drag_target_lane = nil
  state.drag_saved_cursor = nil
  state.drag_cursor_position = nil
end

local function mouse_screen_position()
  if r.GetMousePosition then return r.GetMousePosition() end
  return nil, nil
end

local function track_under_mouse()
  if not r.GetTrackFromPoint then return nil end
  local x, y = mouse_screen_position()
  if not x or not y then return nil end
  local track, info = r.GetTrackFromPoint(x, y)
  if validate_track(track) then
    local lane = nil
    if r.GetMediaTrackInfo_Value(track, "I_FREEMODE") == 2 then
      lane = math.floor((tonumber(info) or 0) / 256) % 256
    end
    return track, lane
  end
  return nil
end

local function arrange_time_under_mouse()
  if not r.JS_Window_FindChildByID or not r.JS_Window_GetRect or not r.GetSet_ArrangeView2 then return nil end
  local x = mouse_screen_position()
  if not x then return nil end
  local arrange = r.JS_Window_FindChildByID(r.GetMainHwnd(), 0x3E8)
  if not arrange then return nil end
  local _, left, _, right = r.JS_Window_GetRect(arrange)
  local width = (right or 0) - (left or 0)
  if width <= 0 then return nil end
  local arrange_x = x - left
  if arrange_x < 0 or arrange_x > width then return nil end
  local view_start, view_end = r.GetSet_ArrangeView2(0, false, 0, 0)
  local time = view_start + (arrange_x / width) * (view_end - view_start)
  if r.SnapToGrid then time = r.SnapToGrid(0, time) end
  return math.max(0, time)
end

local function is_video_window_open()
  return r.GetToggleCommandStateEx and r.GetToggleCommandStateEx(0, 50125) == 1
end

local function create_preview_track(kind, volume)
  local track_count = r.CountTracks(0)
  r.InsertTrackAtIndex(track_count, false)
  local track = r.GetTrack(0, track_count)
  if not track then return nil end
  r.GetSetMediaTrackInfo_String(track, "P_NAME", "__TK_WORKBENCH_MEDIA_PREVIEW__", true)
  r.SetMediaTrackInfo_Value(track, "D_VOL", volume or defaults.preview_volume)
  if kind == "midi" then
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
    r.TrackFX_AddByName(track, "ReaSynth (Cockos)", false, -1)
  else
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
  end
  return track
end

local function start_track_preview(settings, file)
  if not file or (file.kind ~= "midi" and file.kind ~= "video") then return false end
  destroy_preview(nil, nil, true)
  local source = r.PCM_Source_CreateFromFile(file.path)
  if not source then return false end
  local track = nil
  local track_owned = true
  if file.kind == "midi" and settings.use_selected_track_for_midi then
    track = r.GetSelectedTrack(0, 0)
    track_owned = false
    if not track then
      if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
      state.last_error = "Select a track for MIDI preview"
      return false
    end
  else
    track = create_preview_track(file.kind, settings.preview_volume)
  end
  if not track then if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end; return false end
  local item = r.AddMediaItemToTrack(track)
  local take = item and r.AddTakeToMediaItem(item) or nil
  if not take then
    if track_owned then r.DeleteTrack(track) end
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    return false
  end
  r.SetMediaItemTake_Source(take, source)
  local source_length = r.GetMediaSourceLength(source) or 0
  if file.kind == "midi" then source_length = source_length > 0 and source_length / 2 or 60 end
  if source_length <= 0 then source_length = 5 end
  local rate = effective_playrate(source, file.kind, settings)
  if r.SetMediaItemTakeInfo_Value then
    r.SetMediaItemTakeInfo_Value(take, "D_PITCH", effective_preview_pitch(settings, rate))
    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
  end
  local length = source_length / rate
  r.SetMediaItemPosition(item, 0, false)
  r.SetMediaItemLength(item, length, false)
  r.UpdateItemInProject(item)
  state.saved_loop_start, state.saved_loop_end = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
  state.saved_repeat = r.GetSetRepeat(-1)
  state.saved_cursor = r.GetCursorPosition()
  state.preview_source = source
  state.preview_path = file.path
  state.preview_kind = file.kind
  state.preview_track = track
  state.preview_item = item
  state.preview_take = take
  state.preview_track_owned = track_owned
  state.preview_track_playback = true
  state.preview_length = length
  state.preview_source_length = source_length
  state.preview_started_at = r.time_precise and r.time_precise() or os.clock()
  state.auto_advance_pending = false
  state.auto_advance_due = 0
  state.preview_paused = false
  state.preview_paused_position = 0
  state.preview_paused_project_position = nil
  state.last_error = nil
  if settings.exclusive_solo_preview then apply_exclusive_solo(track) end
  r.GetSet_LoopTimeRange(true, true, 0, length, false)
  r.GetSetRepeat(settings.loop_preview and 1 or 0)
  r.SetEditCurPos(0, false, false)
  if file.kind == "video" and not is_video_window_open() then r.Main_OnCommand(50125, 0) end
  r.UpdateArrange()
  r.Main_OnCommand(1007, 0)
  state.last_transport_state = r.GetPlayState and r.GetPlayState() or 0
  return true
end

local apply_silence_trim_selection

local function start_preview(settings, file)
  if not file then return false end
  if file.kind == "midi" or file.kind == "video" then return start_track_preview(settings, file) end
  if file.kind ~= "audio" then return false end
  if not r.CF_CreatePreview or not r.CF_Preview_Play then return false end
  if state.preview and state.preview_kind == "audio" and preview_fade_seconds(settings) > 0 then
    state.pending_preview_file = file
    state.pending_preview_settings = settings
    state.pending_preview_due = 0
    destroy_preview(settings)
    return true
  end
  if state.preview and state.preview_kind == "audio" and preview_restart_gap_seconds(settings) > 0 then
    local pending_file = file
    local pending_settings = settings
    local due = (r.time_precise and r.time_precise() or os.clock()) + preview_restart_gap_seconds(settings)
    destroy_preview(settings, nil, true)
    state.pending_preview_file = pending_file
    state.pending_preview_settings = pending_settings
    state.pending_preview_due = due
    return true
  end
  if apply_silence_trim_selection then apply_silence_trim_selection(file, settings, false) end
  destroy_preview(nil, nil, true)
  local source = r.PCM_Source_CreateFromFile(file.path)
  if not source then return false end
  local source_length = r.GetMediaSourceLength(source) or 0
  local rate = effective_playrate(source, file.kind, settings)
  local preview_length = rate > 0 and source_length / rate or source_length
  local selection_start = waveform_selection_range(file, preview_length)
  local output_track = nil
  if settings.use_selected_track_for_audio and r.CF_Preview_SetOutputTrack then output_track = r.GetSelectedTrack(0, 0) end
  local preview = r.CF_CreatePreview(source)
  if not preview then
    r.PCM_Source_Destroy(source)
    return false
  end
  local fade_in = preview_fade_seconds(settings)
  local target_volume = settings.preview_volume or defaults.preview_volume
  if r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(preview, "D_VOLUME", fade_in > 0 and 0 or target_volume)
    r.CF_Preview_SetValue(preview, "B_LOOP", settings.loop_preview and 1 or 0)
    r.CF_Preview_SetValue(preview, "D_PITCH", effective_preview_pitch(settings, rate))
    r.CF_Preview_SetValue(preview, "D_PLAYRATE", rate)
  end
  if output_track then r.CF_Preview_SetOutputTrack(preview, 0, output_track) end
  r.CF_Preview_Play(preview)
  if selection_start and r.CF_Preview_SetValue then r.CF_Preview_SetValue(preview, "D_POSITION", selection_start) end
  state.preview = preview
  state.preview_source = source
  state.preview_path = file.path
  state.preview_kind = file.kind
  state.preview_track = output_track
  state.preview_track_owned = false
  state.preview_length = preview_length
  state.preview_source_length = source_length
  state.preview_started_at = (r.time_precise and r.time_precise() or os.clock()) - (selection_start or 0)
  state.auto_advance_pending = false
  state.auto_advance_due = 0
  state.preview_paused = false
  state.preview_paused_position = 0
  state.preview_paused_project_position = nil
  state.last_error = nil
  if fade_in > 0 then
    state.preview_fade = {
      kind = "in",
      preview = preview,
      started = r.time_precise and r.time_precise() or os.clock(),
      duration = fade_in,
      from_volume = 0,
      target_volume = target_volume
    }
  end
  if settings.link_transport and r.CSurf_OnPlay then
    if settings.link_start_from_editcursor ~= true then r.SetEditCurPos(0, false, false) end
    r.CSurf_OnPlay()
    state.last_transport_state = r.GetPlayState and r.GetPlayState() or 0
  end
  return true
end

local function restart_audio_preview_at(settings, position)
  if not state.preview_path or not r.CF_CreatePreview or not r.CF_Preview_Play then return false end
  local source = r.PCM_Source_CreateFromFile(state.preview_path)
  if not source then return false end
  if state.preview and r.CF_Preview_Stop then r.CF_Preview_Stop(state.preview) end
  if state.preview_source and r.PCM_Source_Destroy then r.PCM_Source_Destroy(state.preview_source) end
  local preview = r.CF_CreatePreview(source)
  if not preview then if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end; return false end
  local rate = effective_playrate(source, state.preview_kind, settings)
  local output_track = nil
  if settings.use_selected_track_for_audio and r.CF_Preview_SetOutputTrack then output_track = r.GetSelectedTrack(0, 0) end
  local fade_in = preview_fade_seconds(settings)
  local target_volume = settings.preview_volume or defaults.preview_volume
  if r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(preview, "D_VOLUME", fade_in > 0 and 0 or target_volume)
    r.CF_Preview_SetValue(preview, "B_LOOP", settings.loop_preview and 1 or 0)
    r.CF_Preview_SetValue(preview, "D_PITCH", effective_preview_pitch(settings, rate))
    r.CF_Preview_SetValue(preview, "D_PLAYRATE", rate)
    r.CF_Preview_SetValue(preview, "D_POSITION", position)
  end
  if output_track then r.CF_Preview_SetOutputTrack(preview, 0, output_track) end
  r.CF_Preview_Play(preview)
  if r.CF_Preview_SetValue then r.CF_Preview_SetValue(preview, "D_POSITION", position) end
  state.preview = preview
  state.preview_source = source
  state.preview_track = output_track
  state.preview_track_owned = false
  state.preview_paused = false
  state.preview_paused_position = 0
  state.preview_paused_project_position = nil
  state.preview_started_at = (r.time_precise and r.time_precise() or os.clock()) - position
  if fade_in > 0 then
    state.preview_fade = {
      kind = "in",
      preview = preview,
      started = r.time_precise and r.time_precise() or os.clock(),
      duration = fade_in,
      from_volume = 0,
      target_volume = target_volume
    }
  end
  return true
end

local function track_preview_position()
  if r.GetPlayPosition then
    local position = r.GetPlayPosition()
    if position then return position end
  end
  return r.GetCursorPosition() or 0
end

local function pause_preview(settings, from_transport)
  if state.preview_track_playback then
    if state.preview_paused then
      r.Main_OnCommand(1007, 0)
      state.preview_paused = false
      state.preview_started_at = (r.time_precise and r.time_precise() or os.clock()) - (r.GetCursorPosition() or 0)
    else
      r.Main_OnCommand(1008, 0)
      state.preview_paused = true
      state.preview_paused_position = track_preview_position()
    end
    return
  end
  if state.preview and r.CF_Preview_Stop then
    local position = 0
    if r.CF_Preview_GetValue then
      local ok, value_ok, value = pcall(r.CF_Preview_GetValue, state.preview, "D_POSITION")
      if ok and value_ok and value then position = value end
    end
    r.CF_Preview_Stop(state.preview)
    state.preview = nil
    state.preview_paused = true
    state.preview_paused_position = position
    state.preview_paused_project_position = r.GetPlayPosition and r.GetPlayPosition() or nil
    if settings.link_transport and not from_transport and r.CSurf_OnPause then r.CSurf_OnPause() end
    return
  end
  if state.preview_paused and state.preview_source and r.CF_CreatePreview and r.CF_Preview_Play then
    local preview = r.CF_CreatePreview(state.preview_source)
    if not preview then return end
    local rate = effective_playrate(state.preview_source, state.preview_kind, settings)
    local output_track = nil
    if settings.use_selected_track_for_audio and r.CF_Preview_SetOutputTrack then output_track = r.GetSelectedTrack(0, 0) end
    if r.CF_Preview_SetValue then
      r.CF_Preview_SetValue(preview, "D_VOLUME", settings.preview_volume or defaults.preview_volume)
      r.CF_Preview_SetValue(preview, "B_LOOP", settings.loop_preview and 1 or 0)
      r.CF_Preview_SetValue(preview, "D_PITCH", effective_preview_pitch(settings, rate))
      r.CF_Preview_SetValue(preview, "D_PLAYRATE", rate)
      r.CF_Preview_SetValue(preview, "D_POSITION", state.preview_paused_position or 0)
    end
    if output_track then r.CF_Preview_SetOutputTrack(preview, 0, output_track) end
    r.CF_Preview_Play(preview)
    state.preview = preview
    state.preview_track = output_track
    state.preview_track_owned = false
    state.preview_paused = false
    if settings.link_transport and not from_transport then
      if state.preview_paused_project_position then r.SetEditCurPos(state.preview_paused_project_position, false, false) end
      if r.CSurf_OnPlay then r.CSurf_OnPlay() end
    end
    state.preview_started_at = (r.time_precise and r.time_precise() or os.clock()) - (state.preview_paused_position or 0)
    state.preview_paused_position = 0
    state.preview_paused_project_position = nil
  end
end

local function update_preview_fades(settings)
  local fade = state.preview_fade
  if not fade then return end
  if not fade.preview or state.preview ~= fade.preview or not r.CF_Preview_SetValue then state.preview_fade = nil; return end
  local now = r.time_precise and r.time_precise() or os.clock()
  local progress = math.max(0, math.min(1, (now - (fade.started or now)) / math.max(0.001, fade.duration or 0.001)))
  if fade.kind == "out" then
    set_preview_volume((fade.from_volume or 0) * (1 - progress))
    if progress >= 1 then
      local pending_file = state.pending_preview_file
      local pending_settings = state.pending_preview_settings or settings
      destroy_preview_now(fade.settings or settings, fade.from_transport)
      if pending_file then
        local gap = preview_restart_gap_seconds(pending_settings)
        if gap > 0 then
          state.pending_preview_file = pending_file
          state.pending_preview_settings = pending_settings
          state.pending_preview_due = (r.time_precise and r.time_precise() or os.clock()) + gap
        else
          start_preview(pending_settings, pending_file)
        end
      end
    end
  elseif fade.kind == "in" then
    local target = tonumber(settings and settings.preview_volume) or fade.target_volume or defaults.preview_volume
    set_preview_volume((fade.from_volume or 0) + (target - (fade.from_volume or 0)) * progress)
    if progress >= 1 then
      set_preview_volume(target)
      state.preview_fade = nil
    end
  else
    state.preview_fade = nil
  end
end

local function update_pending_preview(settings)
  if not state.pending_preview_file then return end
  if state.preview_fade then return end
  local due = tonumber(state.pending_preview_due) or 0
  if due > 0 and (r.time_precise and r.time_precise() or os.clock()) < due then return end
  local file = state.pending_preview_file
  local pending_settings = state.pending_preview_settings or settings
  state.pending_preview_file = nil
  state.pending_preview_settings = nil
  state.pending_preview_due = 0
  start_preview(pending_settings, file)
end

local function can_preview_file(file)
  return file and (file.kind == "audio" or file.kind == "midi" or file.kind == "video")
end

local function preview_is_active()
  return state.preview ~= nil or state.preview_track_playback or state.preview_paused
end

local function preview_finished(settings)
  if state.preview_paused then return false end
  if not preview_is_active() or settings.loop_preview then return false end
  local now = r.time_precise and r.time_precise() or os.clock()
  if now - (state.preview_started_at or 0) < 0.25 then return false end
  if state.preview then
    local selection_start, selection_end = waveform_selection_range({ path = state.preview_path, kind = "audio" }, state.preview_length)
    if selection_start and selection_end and r.CF_Preview_GetValue then
      local ok, value_ok, position = pcall(r.CF_Preview_GetValue, state.preview, "D_POSITION")
      if ok and value_ok and position and position >= selection_end - 0.01 then return true end
    end
    if r.CF_Preview_GetValue then
      local ok, value_ok, playing = pcall(r.CF_Preview_GetValue, state.preview, "B_PLAYING")
      if ok and value_ok then return playing == 0 or playing == false end
    end
    return state.preview_length and state.preview_length > 0 and now - (state.preview_started_at or now) >= state.preview_length
  end
  if state.preview_track_playback then
    local pos = track_preview_position()
    local length = state.preview_length or 0
    if length > 0 and pos >= length - 0.03 then return true end
  end
  return false
end

local function monitor_transport_link(settings)
  if not r.GetPlayState then return end
  local current_state = r.GetPlayState()
  if not settings.link_transport then
    state.last_transport_state = current_state
    return
  end
  local is_playing = (current_state & 1) == 1
  local is_paused = (current_state & 2) == 2
  local was_playing = (state.last_transport_state & 1) == 1
  local was_paused = (state.last_transport_state & 2) == 2
  if is_paused and not was_paused and state.preview and not state.preview_track_playback then
    pause_preview(settings, true)
  elseif is_playing and not was_playing and state.preview_paused and state.preview_source and not state.preview_track_playback then
    pause_preview(settings, true)
  elseif not is_playing and not is_paused and (was_playing or was_paused) and (state.preview or state.preview_paused) and not state.preview_track_playback then
    destroy_preview(settings, true)
  end
  state.last_transport_state = current_state
end

local function monitor_audio_selection(settings)
  if (settings.auto_play_next and settings.loop_preview ~= true) or state.preview_paused or state.preview_kind ~= "audio" or not state.preview or not r.CF_Preview_GetValue then return end
  local selection_start, selection_end = waveform_selection_range({ path = state.preview_path, kind = "audio" }, state.preview_length)
  if not selection_start or not selection_end then return end
  local ok, value_ok, position = pcall(r.CF_Preview_GetValue, state.preview, "D_POSITION")
  if settings.loop_preview then
    local play_ok, play_value_ok, playing = pcall(r.CF_Preview_GetValue, state.preview, "B_PLAYING")
    local stopped = play_ok and play_value_ok and (playing == 0 or playing == false)
    if stopped or (ok and value_ok and position and (position >= selection_end - 0.01 or position < selection_start - 0.01)) then
      if stopped then
        restart_audio_preview_at(settings, selection_start)
      else
        seek_audio_preview(selection_start)
        state.preview_started_at = (r.time_precise and r.time_precise() or os.clock()) - selection_start
      end
    end
  else
    if ok and value_ok and position and position >= selection_end - 0.01 then destroy_preview(settings) end
  end
end

local function preview_progress(file)
  if not file or state.preview_path ~= file.path then return nil end
  local length = state.preview_length or 0
  if length <= 0 then return nil end
  local position = nil
  if state.preview_paused then
    position = state.preview_paused_position or 0
  elseif state.preview and r.CF_Preview_GetValue then
    local ok, value_ok, value = pcall(r.CF_Preview_GetValue, state.preview, "D_POSITION")
    if ok and value_ok and value then position = value end
  elseif state.preview_track_playback then
    position = track_preview_position()
  end
  if not position then return nil end
  return math.max(0, math.min(1, position / length))
end

local function draw_preview_cursor(draw_list, file, x, y, width, height)
  local progress = preview_progress(file)
  if not progress then return end
  local view_progress = file and file.kind == "audio" and waveform_norm_to_view(progress) or progress
  if not view_progress then return end
  local cursor_x = x + view_progress * width
  r.ImGui_DrawList_AddLine(draw_list, cursor_x, y + 1, cursor_x, y + height - 1, 0x000000AA, 4)
  r.ImGui_DrawList_AddLine(draw_list, cursor_x, y + 1, cursor_x, y + height - 1, Theme.colors.accent, 2)
end

local function draw_waveform_selection(draw_list, file, x, y, width, height)
  if not waveform_selection_active(file) then return end
  local start_norm = math.min(state.waveform_selection_start or 0, state.waveform_selection_end or 0)
  local end_norm = math.max(state.waveform_selection_start or 0, state.waveform_selection_end or 0)
  local visible_start, visible_end, visible_duration = waveform_visible_range()
  if end_norm < visible_start or start_norm > visible_end then return end
  start_norm = math.max(start_norm, visible_start)
  end_norm = math.min(end_norm, visible_end)
  local start_x = x + ((start_norm - visible_start) / visible_duration) * width
  local end_x = x + ((end_norm - visible_start) / visible_duration) * width
  local fill = (Theme.colors.accent & 0xFFFFFF00) | 0x33
  r.ImGui_DrawList_AddRectFilled(draw_list, start_x, y + 1, end_x, y + height - 1, fill, 2)
  r.ImGui_DrawList_AddLine(draw_list, start_x, y + 1, start_x, y + height - 1, Theme.colors.accent, 1.5)
  r.ImGui_DrawList_AddLine(draw_list, end_x, y + 1, end_x, y + height - 1, Theme.colors.accent, 1.5)
end

local function handle_waveform_interaction(ctx, file, x, y, width, height)
  if not file or file.kind ~= "audio" then return end
  local hovered = item_hovered(ctx)
  local mouse_x = mouse_x_position(ctx)
  if not mouse_x then return end
  local local_norm = clamp((mouse_x - x) / math.max(1, width), 0, 1)
  local normalized = waveform_view_to_norm(local_norm)
  if hovered and waveform_reset_hovered(ctx, x, y, height) and mouse_clicked(ctx, "Left", 0) then
    reset_waveform_zoom()
    return
  end
  if hovered then
    local wheel = mouse_wheel_delta(ctx)
    if wheel ~= 0 and modifier_down(ctx, "Ctrl") and modifier_down(ctx, "Alt") then
      local factor = wheel > 0 and 1.12 or (1 / 1.12)
      state.waveform_vertical_zoom = clamp((state.waveform_vertical_zoom or 1.0) * factor, 0.25, 8.0)
      return
    elseif wheel ~= 0 and modifier_down(ctx, "Ctrl") then
      local visible_start, _, visible_duration = waveform_visible_range()
      local anchor = visible_start + local_norm * visible_duration
      local factor = wheel > 0 and 1.15 or (1 / 1.15)
      state.waveform_zoom = clamp((state.waveform_zoom or 1.0) * factor, 1.0, 16.0)
      local _, _, new_duration = waveform_visible_range()
      local max_scroll = math.max(0, 1.0 - new_duration)
      local new_start = clamp(anchor - local_norm * new_duration, 0, max_scroll)
      state.waveform_scroll = max_scroll > 0 and new_start / max_scroll or 0
      return
    elseif wheel ~= 0 and (state.waveform_zoom or 1.0) > 1.0 then
      state.waveform_scroll = clamp((state.waveform_scroll or 0.0) - wheel * 0.05, 0.0, 1.0)
      return
    end
  end
  if hovered and mouse_clicked(ctx, "Right", 1) then
    clear_waveform_selection()
    return
  end
  if hovered and mouse_clicked(ctx, "Left", 0) then
    state.waveform_selection_file = file.path
    state.waveform_selection_start = normalized
    state.waveform_selection_end = normalized
    state.waveform_dragging = true
    state.waveform_selection_auto = false
    if state.preview_path == file.path then seek_audio_preview(normalized * (state.preview_length or 0)) end
  end
  if state.waveform_dragging and state.waveform_selection_file == file.path then
    state.waveform_selection_end = normalized
    if not mouse_down(ctx, "Left", 0) then
      state.waveform_dragging = false
      if not waveform_selection_active(file) then clear_waveform_selection() end
    end
  end
end

local select_file

local function next_preview_file(path)
  if not path then return nil, nil end
  local start_index = nil
  for index, file in ipairs(state.filtered) do
    if file.path == path then start_index = index; break end
  end
  if not start_index then return nil, nil end
  for index = start_index + 1, #state.filtered do
    local file = state.filtered[index]
    if can_preview_file(file) then return file, index end
  end
  return nil, nil
end

local function random_preview_index(current_index)
  if #state.filtered < 2 then return nil end
  math.randomseed(math.floor((r.time_precise and r.time_precise() or os.clock()) * 1000000))
  local next_index = current_index
  for _ = 1, 12 do
    next_index = math.random(#state.filtered)
    local file = state.filtered[next_index]
    if next_index ~= current_index and can_preview_file(file) then return next_index end
  end
  for index = 1, #state.filtered do
    local file = state.filtered[index]
    if index ~= current_index and can_preview_file(file) then return index end
  end
  return nil
end

local function play_filtered_index(app, settings, index, disable_auto_progress)
  local file = state.filtered[index]
  if not can_preview_file(file) then return false end
  state.auto_advance_pending = false
  state.auto_advance_due = 0
  if disable_auto_progress then settings.auto_play_next = false end
  if select_file(app, file, index, false) then
    state.scroll_selected_file = true
    start_preview(settings, file)
    if disable_auto_progress and app.save_settings then app.save_settings() end
    return true
  end
  return false
end

local function previous_preview_file(app, settings)
  local index = state.selected_index or 1
  for target = index - 1, 1, -1 do
    if play_filtered_index(app, settings, target, true) then return true end
  end
  return false
end

local function advance_preview_file(app, settings)
  local next_index = nil
  if settings.random_play_next then
    next_index = random_preview_index(state.selected_index)
  else
    local current_path = state.preview_path or (state.selected_file and state.selected_file.path)
    local _, index = next_preview_file(current_path)
    next_index = index
  end
  if next_index then return play_filtered_index(app, settings, next_index, false) end
  return false
end

local function can_auto_advance(settings)
  local min_time = tonumber(settings.min_display_time) or 0
  if min_time <= 0 then return true end
  if not state.preview_started_at or state.preview_started_at <= 0 then return true end
  return ((r.time_precise and r.time_precise() or os.clock()) - state.preview_started_at) >= min_time
end

local function try_auto_advance(app, settings)
  if can_auto_advance(settings) then
    state.auto_advance_pending = false
    state.auto_advance_due = 0
    if advance_preview_file(app, settings) then return true end
    destroy_preview(settings)
    state.last_error = "Auto: end of list"
    return false
  end
  if not state.auto_advance_pending then
    state.auto_advance_pending = true
    state.auto_advance_due = (state.preview_started_at or (r.time_precise and r.time_precise() or os.clock())) + (tonumber(settings.min_display_time) or 0)
  end
  return false
end

local function process_pending_auto_advance(app, settings)
  if not state.auto_advance_pending then return false end
  if state.preview_paused or settings.loop_preview or not settings.auto_play_next then
    state.auto_advance_pending = false
    state.auto_advance_due = 0
    return false
  end
  if (r.time_precise and r.time_precise() or os.clock()) < (state.auto_advance_due or 0) then return false end
  state.auto_advance_pending = false
  state.auto_advance_due = 0
  if advance_preview_file(app, settings) then return true end
  destroy_preview(settings)
  state.last_error = "Auto: end of list"
  return false
end

local function update_auto_play(app, settings)
  process_pending_auto_advance(app, settings)
  if not settings.auto_play_next or not preview_finished(settings) then return end
  try_auto_advance(app, settings)
end

local function peak_cache_key(path, width)
  return path .. "|" .. tostring(math.max(24, math.floor(width or 0)))
end

local function read_source_peaks(source, peakrate, start_time, channels, count)
  local buffer = r.new_array(count * channels * 2)
  buffer.clear()
  local ok = r.PCM_Source_GetPeaks(source, peakrate, start_time, channels, count, 0, buffer)
  local has_signal = false
  if ok then
    for index = 1, count * channels * 2 do
      if math.abs(buffer[index] or 0) > 0 then
        has_signal = true
        break
      end
    end
  end
  return ok, buffer, has_signal
end

local request_peak_build

local function silence_trim_key(file, settings)
  return table.concat({ file.path or "", tostring(settings.trim_silence_threshold_db), tostring(settings.trim_silence_padding_ms) }, "|")
end

local function detect_silence_trim(file, settings)
  if not file or file.kind ~= "audio" or not file.path or file.path == "" then return nil end
  local cache_key = silence_trim_key(file, settings)
  if state.silence_trim_cache[cache_key] ~= nil then return state.silence_trim_cache[cache_key] end
  local source = r.PCM_Source_CreateFromFile(file.path)
  if not source then return nil end
  local length = r.GetMediaSourceLength(source) or 0
  if length <= 0 then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    return nil
  end
  local channels = r.GetMediaSourceNumChannels(source) or 1
  if channels < 1 then channels = 1 end
  local samples = math.max(256, math.min(32768, math.floor(length * 1000)))
  local peakrate = samples / length
  local ok, buffer, has_signal = read_source_peaks(source, peakrate, 0, channels, samples)
  if (not ok or not has_signal) and samples < 32768 then
    if buffer and buffer.clear then buffer.clear() end
    samples = math.min(32768, math.max(samples * 4, 1024))
    peakrate = samples / length
    ok, buffer, has_signal = read_source_peaks(source, peakrate, 0, channels, samples)
  end
  if not ok or not has_signal then
    request_peak_build(source, file.path)
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    if buffer and buffer.clear then buffer.clear() end
    return nil
  end
  local threshold = 10 ^ ((tonumber(settings.trim_silence_threshold_db) or defaults.trim_silence_threshold_db) / 20)
  local first_index, last_index = nil, nil
  for index = 1, samples do
    local peak = 0
    for channel = 1, channels do
      local pos = ((index - 1) * channels) + channel
      peak = math.max(peak, math.abs(buffer[pos] or 0), math.abs(buffer[(samples * channels) + pos] or 0))
    end
    if peak >= threshold then
      first_index = first_index or index
      last_index = index
    end
  end
  if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
  if buffer and buffer.clear then buffer.clear() end
  if not first_index or not last_index then return nil end
  local padding = (tonumber(settings.trim_silence_padding_ms) or defaults.trim_silence_padding_ms) / 1000
  local start_time = math.max(0, ((first_index - 1) / samples) * length - padding)
  local end_time = math.min(length, (last_index / samples) * length + padding)
  if end_time - start_time < 0.01 then return nil end
  local result = { start_time = start_time, end_time = end_time, length = length }
  if start_time <= 0.002 and length - end_time <= 0.002 then result.full = true end
  state.silence_trim_cache[cache_key] = result
  return result
end

apply_silence_trim_selection = function(file, settings, force)
  if not settings or settings.trim_silence_enabled ~= true or not file or file.kind ~= "audio" then return false end
  if waveform_selection_active(file) and state.waveform_selection_auto ~= true and not force then return false end
  local result = detect_silence_trim(file, settings)
  if not result or result.full then
    if state.waveform_selection_auto == true and state.waveform_selection_file == file.path then clear_waveform_selection() end
    return false
  end
  state.waveform_selection_file = file.path
  state.waveform_selection_start = clamp(result.start_time / result.length, 0, 1)
  state.waveform_selection_end = clamp(result.end_time / result.length, 0, 1)
  state.waveform_dragging = false
  state.waveform_selection_auto = true
  return waveform_selection_active(file)
end

local function log_peak_miss(file, length, channels, samples, peakrate, ok, buffer)
  if not file or not file.path or state.waveform_debug_logged[file.path] then return end
  state.waveform_debug_logged[file.path] = true
  local max_peak = 0
  if buffer then
    for index = 1, math.min(samples * channels * 2, 4096) do
      max_peak = math.max(max_peak, math.abs(buffer[index] or 0))
    end
  end
  local handle = io.open(peak_debug_path, "a")
  if not handle then return end
  handle:write(os.date("%Y-%m-%d %H:%M:%S"), "\t", tostring(file.path), "\t")
  handle:write("ok=", tostring(ok), "\tlength=", tostring(length), "\tchannels=", tostring(channels), "\tsamples=", tostring(samples), "\tpeakrate=", tostring(peakrate), "\tmax4096=", tostring(max_peak), "\n")
  handle:close()
end

request_peak_build = function(source, path)
  if not source or not r.PCM_Source_BuildPeaks then return end
  local now = r.time_precise and r.time_precise() or os.clock()
  local last = state.waveform_build_pending[path] or 0
  if now - last > 0.75 then
    state.waveform_build_pending[path] = now
    r.PCM_Source_BuildPeaks(source, 0)
  end
end

local function generate_peak_file(path)
  if not path or path == "" or not r.PCM_Source_BuildPeaks then return end
  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return end
  r.PCM_Source_BuildPeaks(source, 0)
  if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
end

local function invalidate_waveform_cache(path)
  if not path or path == "" then return end
  for key in pairs(state.waveform_cache) do
    if key:sub(1, #path + 1) == path .. "|" then state.waveform_cache[key] = nil end
  end
  state.waveform_pending[path] = nil
  state.waveform_refresh_pending[path] = nil
  state.waveform_build_pending[path] = nil
end

local function mark_waveform_pending(path, samples)
  local now = r.time_precise and r.time_precise() or os.clock()
  local pending = state.waveform_pending[path]
  if pending then
    pending.count = math.min(8, (pending.count or 0) + 1)
    pending.time = now + 0.35
    pending.samples = samples
  else
    state.waveform_pending[path] = { count = 1, time = now + 0.35, samples = samples }
  end
end

local function waveform_retry_due(path)
  local pending = state.waveform_pending[path]
  if not pending then return true end
  local now = r.time_precise and r.time_precise() or os.clock()
  return now >= (pending.time or 0)
end

local function waveform_refresh_due(path, samples)
  local refresh = state.waveform_refresh_pending[path]
  if not refresh or refresh.samples ~= samples then return false end
  local now = r.time_precise and r.time_precise() or os.clock()
  return now >= (refresh.time or 0)
end

local function schedule_waveform_refresh(source, path, samples)
  local now = r.time_precise and r.time_precise() or os.clock()
  local refresh = state.waveform_refresh_pending[path]
  if not refresh then
    state.waveform_refresh_pending[path] = { time = now + 0.75, count = 1, samples = samples }
  elseif refresh.count < 4 then
    refresh.count = refresh.count + 1
    refresh.time = now + 0.75
    refresh.samples = samples
  else
    state.waveform_refresh_pending[path] = nil
    state.waveform_build_pending[path] = nil
    return
  end
  request_peak_build(source, path)
end

local function load_waveform(file, width)
  if not file or file.kind ~= "audio" then return nil end
  local zoom = clamp(tonumber(state.waveform_zoom) or 1.0, 1.0, 16.0)
  local samples = math.max(32, math.floor(width or 200))
  local key = peak_cache_key(file.path, samples)
  local refresh_due = waveform_refresh_due(file.path, samples)
  if state.waveform_cache[key] and not refresh_due then return state.waveform_cache[key] end
  if refresh_due then state.waveform_cache[key] = nil end
  if not waveform_retry_due(file.path) then return nil end
  if state.waveform_peak_sources[file.path] then destroy_waveform_source(file.path) end
  local source = r.PCM_Source_CreateFromFile(file.path)
  if not source then return nil end
  local length = r.GetMediaSourceLength(source)
  if not length or length <= 0 then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    return nil
  end
  local channels = r.GetMediaSourceNumChannels(source) or 1
  if channels < 1 then channels = 1 end
  local peakrate = samples / length
  local peak_samples = samples
  local ok, buffer, has_signal = read_source_peaks(source, peakrate, 0, channels, samples)
  if not ok or not has_signal then request_peak_build(source, file.path) end
  if not has_signal then
    local fallback_samples = math.max(samples * 4, math.min(4096, math.max(1024, math.floor(length * 500))))
    if fallback_samples > samples then
      if buffer and buffer.clear then buffer.clear() end
      peakrate = fallback_samples / length
      ok, buffer, has_signal = read_source_peaks(source, peakrate, 0, channels, fallback_samples)
      peak_samples = fallback_samples
      if not ok or not has_signal then request_peak_build(source, file.path) end
    end
  end
  if not ok or not has_signal then
    log_peak_miss(file, length, channels, peak_samples, peakrate, ok, buffer)
    mark_waveform_pending(file.path, samples)
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    if buffer and buffer.clear then buffer.clear() end
    return nil
  end
  local peaks = {}
  for index = 1, samples do
    local peak = 0
    local first_peak = math.floor((index - 1) * peak_samples / samples) + 1
    local last_peak = math.max(first_peak, math.floor(index * peak_samples / samples))
    for source_index = first_peak, math.min(last_peak, peak_samples) do
      for channel = 1, channels do
        local pos = ((source_index - 1) * channels) + channel
        peak = math.max(peak, math.abs(buffer[pos] or 0), math.abs(buffer[(peak_samples * channels) + pos] or 0))
      end
    end
    peaks[index] = peak
  end
  local data = { peaks = peaks, length = length }
  state.waveform_cache[key] = data
  state.waveform_pending[file.path] = nil
  schedule_waveform_refresh(source, file.path, samples)
  if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
  if buffer and buffer.clear then buffer.clear() end
  return data
end

local function load_midi_notes(file)
  if not file or file.kind ~= "midi" or not file.path or file.path == "" then return nil end
  local cached = state.midi_note_cache[file.path]
  if cached then return cached end
  local notes = {}
  local source = r.PCM_Source_CreateFromFile(file.path)
  if not source then return nil end
  local source_length = r.GetMediaSourceLength(source) or 0
  local length = source_length > 0 and source_length / 2 or 0
  local track = r.GetTrack(0, 0)
  local temp_track = false
  if not track then
    r.InsertTrackAtIndex(0, false)
    track = r.GetTrack(0, 0)
    temp_track = true
  end
  if not track then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    return nil
  end
  r.PreventUIRefresh(1)
  local item = r.AddMediaItemToTrack(track)
  local take = item and r.AddTakeToMediaItem(item) or nil
  if take then
    r.SetMediaItemTake_Source(take, source)
    if length > 0 then r.SetMediaItemLength(item, length, false) end
    r.UpdateItemInProject(item)
    local ok_count, note_count = r.MIDI_CountEvts(take)
    if ok_count and note_count and note_count > 0 then
      local min_pitch, max_pitch = 127, 0
      for note_index = 0, math.min(note_count, 20000) - 1 do
        local ok_note, _, muted, start_ppq, end_ppq, channel, pitch, velocity = r.MIDI_GetNote(take, note_index)
        if ok_note then
          local start_time = r.MIDI_GetProjTimeFromPPQPos(take, start_ppq) or 0
          local end_time = r.MIDI_GetProjTimeFromPPQPos(take, end_ppq) or start_time
          min_pitch = math.min(min_pitch, pitch or 0)
          max_pitch = math.max(max_pitch, pitch or 0)
          notes[#notes + 1] = { start = start_time, finish = math.max(start_time + 0.001, end_time), pitch = pitch or 60, velocity = velocity or 96, channel = channel or 0, muted = muted == true }
        end
      end
      if #notes > 0 then
        length = math.max(length, notes[#notes].finish or 0.01)
      end
      state.midi_note_cache[file.path] = { notes = notes, length = math.max(0.01, length), min_pitch = min_pitch, max_pitch = max_pitch }
    else
      state.midi_note_cache[file.path] = { notes = notes, length = math.max(0.01, length), min_pitch = 60, max_pitch = 72 }
    end
  else
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
  end
  if item then r.DeleteTrackMediaItem(track, item) end
  if temp_track then r.DeleteTrack(track) end
  r.PreventUIRefresh(-1)
  return state.midi_note_cache[file.path]
end

local function draw_midi_preview(ctx, draw_list, file, x, y, width, height)
  local data = load_midi_notes(file)
  if not data or #data.notes == 0 then
    local text = "No MIDI notes"
    local tw = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(draw_list, x + (width - tw) * 0.5, y + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, text)
    return
  end
  local min_pitch = math.max(0, (data.min_pitch or 60) - 2)
  local max_pitch = math.min(127, (data.max_pitch or 72) + 2)
  if max_pitch <= min_pitch then max_pitch = min_pitch + 1 end
  local length = math.max(0.01, data.length or 0.01)
  local inner_x, inner_y = x + 8, y + 8
  local inner_w, inner_h = math.max(1, width - 16), math.max(1, height - 16)
  local oct_start = math.floor(min_pitch / 12) * 12
  for pitch = oct_start, max_pitch, 12 do
    if pitch >= min_pitch then
      local gy = inner_y + (1 - ((pitch - min_pitch) / (max_pitch - min_pitch))) * inner_h
      r.ImGui_DrawList_AddLine(draw_list, inner_x, gy, inner_x + inner_w, gy, Theme.colors.separator, 1)
    end
  end
  for _, note in ipairs(data.notes) do
    local sx = inner_x + clamp(note.start / length, 0, 1) * inner_w
    local ex = inner_x + clamp(note.finish / length, 0, 1) * inner_w
    if ex - sx < 2 then ex = sx + 2 end
    local pitch_norm = (note.pitch - min_pitch) / (max_pitch - min_pitch)
    local ny = inner_y + (1 - clamp(pitch_norm, 0, 1)) * inner_h
    local velocity = clamp((note.velocity or 96) / 127, 0.25, 1)
    local alpha = note.muted and 0x55 or math.floor(0x88 + velocity * 0x77)
    local color = (Theme.colors.accent & 0xFFFFFF00) | alpha
    r.ImGui_DrawList_AddRectFilled(draw_list, sx, ny - 2, ex, ny + 2, color, 2)
  end
  local label = tostring(#data.notes) .. " notes | " .. format_duration(length)
  r.ImGui_DrawList_AddText(draw_list, x + 8, y + 7, Theme.colors.text, label)
end

local function draw_waveform(ctx, file, width, height)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##media_waveform", width, height)
  local interaction_ok, interaction_err = pcall(handle_waveform_interaction, ctx, file, x, y, width, height)
  if not interaction_ok then state.last_error = tostring(interaction_err) end
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, 4)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, 4, 0, 1)
  if not file then
    local text = "Select media"
    local tw = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(draw_list, x + (width - tw) * 0.5, y + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, text)
    return
  end
  if file.kind == "image" then
    local entry = load_image(ctx, file)
    if not entry or not entry.image then
      local text = "Image preview unavailable"
      local tw = r.ImGui_CalcTextSize(ctx, text)
      r.ImGui_DrawList_AddText(draw_list, x + (width - tw) * 0.5, y + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, text)
      return
    end
    local img_w = entry.width or 0
    local img_h = entry.height or 0
    if img_w <= 0 or img_h <= 0 then img_w, img_h = width, height end
    local max_w = math.max(1, width - 14)
    local max_h = math.max(1, height - 14)
    local scale = math.min(max_w / img_w, max_h / img_h)
    local draw_w = math.max(1, img_w * scale)
    local draw_h = math.max(1, img_h * scale)
    local draw_x = x + (width - draw_w) * 0.5
    local draw_y = y + (height - draw_h) * 0.5
    if r.ImGui_DrawList_AddImage then
      r.ImGui_DrawList_AddImage(draw_list, entry.image, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, 0xFFFFFFFF)
    elseif r.ImGui_Image and r.ImGui_SetCursorScreenPos then
      r.ImGui_SetCursorScreenPos(ctx, draw_x, draw_y)
      r.ImGui_Image(ctx, entry.image, draw_w, draw_h)
    end
    return
  end
  if file.kind == "midi" then
    draw_midi_preview(ctx, draw_list, file, x, y, width, height)
    draw_preview_cursor(draw_list, file, x, y, width, height)
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "MIDI note preview") end
    return
  end
  if file.kind ~= "audio" then
    local text = file.kind == "midi" and "MIDI file" or (file.kind == "video" and "Video file" or file.kind:upper())
    local detail = state.preview_path == file.path and "Playing via REAPER transport" or "Press Play to preview"
    local tw = r.ImGui_CalcTextSize(ctx, text)
    local dw = r.ImGui_CalcTextSize(ctx, detail)
    local line_h = r.ImGui_GetTextLineHeight(ctx)
    local text_y = y + (height - line_h * 2 - 4) * 0.5
    r.ImGui_DrawList_AddText(draw_list, x + (width - tw) * 0.5, text_y, Theme.colors.text, text)
    r.ImGui_DrawList_AddText(draw_list, x + (width - dw) * 0.5, text_y + line_h + 4, Theme.colors.text_dim, detail)
    draw_preview_cursor(draw_list, file, x, y, width, height)
    return
  end
  local data = load_waveform(file, width)
  if not data then
    local pending = state.waveform_pending[file.path]
    local text = pending and "Building peaks..." or "Building waveform"
    local tw = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(draw_list, x + (width - tw) * 0.5, y + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, text)
    draw_waveform_selection(draw_list, file, x, y, width, height)
    draw_preview_cursor(draw_list, file, x, y, width, height)
    local rx1, ry1, rx2, ry2 = waveform_reset_rect(ctx, x, y, height)
    if rx1 then
      local hovered_reset = waveform_reset_hovered(ctx, x, y, height)
      r.ImGui_DrawList_AddRectFilled(draw_list, rx1 - 4, ry1 - 2, rx2 + 4, ry2 + 2, hovered_reset and 0xFFFFFF33 or 0x00000077, 3)
      r.ImGui_DrawList_AddText(draw_list, rx1, ry1, hovered_reset and Theme.colors.text or Theme.colors.text_dim, "RESET")
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Click seek | Drag select | Ctrl-wheel zoom | Ctrl-Alt-wheel height | Right-click clear") end
    return
  end
  local mid = y + height * 0.5
  local half = math.max(4, height * 0.44)
  local count = #data.peaks
  local visible_start, visible_end, visible_duration = waveform_visible_range()
  local vertical_zoom = clamp(tonumber(state.waveform_vertical_zoom) or 1.0, 0.25, 8.0)
  for index, peak in ipairs(data.peaks) do
    local normalized = (index - 1) / math.max(1, count - 1)
    if normalized >= visible_start and normalized <= visible_end then
      local px = x + ((normalized - visible_start) / visible_duration) * width
      local amp = math.min(1, (peak or 0) * vertical_zoom)
      r.ImGui_DrawList_AddLine(draw_list, px, mid - amp * half, px, mid + amp * half, Theme.colors.accent, 1)
    end
  end
  draw_waveform_selection(draw_list, file, x, y, width, height)
  local label = format_duration(data.length)
  if label ~= "" then r.ImGui_DrawList_AddText(draw_list, x + 8, y + 7, Theme.colors.text, label) end
  local rx1, ry1, rx2, ry2 = waveform_reset_rect(ctx, x, y, height)
  if rx1 then
    local hovered_reset = waveform_reset_hovered(ctx, x, y, height)
    r.ImGui_DrawList_AddRectFilled(draw_list, rx1 - 4, ry1 - 2, rx2 + 4, ry2 + 2, hovered_reset and 0xFFFFFF33 or 0x00000077, 3)
    r.ImGui_DrawList_AddText(draw_list, rx1, ry1, hovered_reset and Theme.colors.text or Theme.colors.text_dim, "RESET")
  end
  draw_preview_cursor(draw_list, file, x, y, width, height)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Click seek | Drag select | Ctrl-wheel zoom | Ctrl-Alt-wheel height | Right-click clear") end
end

local function target_track()
  return r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
end

local function force_peaks_in_item(item, take)
  if not item or not take then return end
  r.UpdateItemInProject(item)
  local position = r.GetMediaItemInfo_Value(item, "D_POSITION")
  r.SetMediaItemInfo_Value(item, "D_POSITION", position + 0.0001)
  r.UpdateItemInProject(item)
  r.SetMediaItemInfo_Value(item, "D_POSITION", position)
  r.UpdateItemInProject(item)
  r.MarkProjectDirty(0)
  r.UpdateArrange()
end

local function insert_file_on_track(app, file, track, target_lane)
  if not file then app.status = "No media selected"; return end
  if not track then app.status = "No target track"; return end
  if file.kind == "audio" then generate_peak_file(file.path) end
  r.Undo_BeginBlock()
  local cursor = r.GetCursorPosition()
  local item = r.AddMediaItemToTrack(track)
  local lane_changed = false
  local take = item and r.AddTakeToMediaItem(item) or nil
  local source = take and r.PCM_Source_CreateFromFile(file.path) or nil
  if source then
    local settings = ensure_settings(app)
    r.SetMediaItemTake_Source(take, source)
    local length = r.GetMediaSourceLength(source) or 1
    if file.kind == "midi" then length = math.max(0.01, length / 2) end
    if file.kind == "audio" then
      local rate = effective_playrate(source, file.kind, settings)
      local display_length = rate > 0 and length / rate or length
      if apply_silence_trim_selection then apply_silence_trim_selection(file, settings, false) end
      local selection_start, selection_end = waveform_selection_range(file, display_length)
      r.SetMediaItemTakeInfo_Value(take, "D_VOL", settings.preview_volume or defaults.preview_volume)
      r.SetMediaItemTakeInfo_Value(take, "D_PITCH", effective_preview_pitch(settings, rate))
      r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
      if selection_start and selection_end then
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", selection_start * rate)
        length = selection_end - selection_start
      else
        length = display_length
      end
    elseif file.kind == "midi" then
      local rate = effective_playrate(source, file.kind, settings)
      r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
      length = length / rate
    end
    r.SetMediaItemPosition(item, cursor, false)
    r.SetMediaItemLength(item, math.max(0.01, length), false)
    if target_lane ~= nil and r.GetMediaTrackInfo_Value(track, "I_FREEMODE") == 2 then
      local lane_count = math.floor(r.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or 0)
      target_lane = math.floor(tonumber(target_lane) or 0)
      if target_lane < 0 then target_lane = 0 end
      if lane_count > 0 then
        if target_lane >= lane_count then
          r.SetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES", target_lane + 1)
          if r.UpdateTimeline then r.UpdateTimeline() end
          lane_count = math.floor(r.GetMediaTrackInfo_Value(track, "I_NUMFIXEDLANES") or lane_count)
        end
        if target_lane >= lane_count then target_lane = lane_count - 1 end
        r.SetMediaItemInfo_Value(item, "I_FIXEDLANE", target_lane)
        lane_changed = true
      end
    end
    r.UpdateItemInProject(item)
    if file.kind == "audio" then
      local active_take = r.GetActiveTake(item) or take
      if active_take then
        local active_source = r.GetMediaItemTake_Source(active_take)
        if active_source and r.PCM_Source_BuildPeaks then r.PCM_Source_BuildPeaks(active_source, 0) end
        force_peaks_in_item(item, active_take)
        if lane_changed then
          if r.UpdateItemLanes then r.UpdateItemLanes(0) end
          r.UpdateItemInProject(item)
          force_peaks_in_item(item, active_take)
        end
      end
      invalidate_waveform_cache(file.path)
    end
  elseif item then
    r.DeleteTrackMediaItem(track, item)
  end
  if source and file.kind == "audio" then
    r.SetMediaItemSelected(item, true)
    r.Main_OnCommand(40047, 0)
    r.Main_OnCommand(40441, 0)
    r.UpdateTimeline()
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
  end
  r.Undo_EndBlock("Workbench Media Browser: Insert media", -1)
  if source then app.status = "Inserted " .. file.name .. " on " .. track_label(track) else app.status = "Could not insert " .. file.name end
end

local function insert_file(app, file)
  insert_file_on_track(app, file, target_track())
end

local Sampler = {
  mpl_rs5k_cmd_id = nil,
  note_names = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"},
  pad_ranges = {
    { start_note = 20, end_note = 35, label = "G#0 - B1" },
    { start_note = 36, end_note = 51, label = "C2 - D#3 *" },
    { start_note = 52, end_note = 67, label = "E3 - G4" },
    { start_note = 68, end_note = 83, label = "G#4 - B5" },
    { start_note = 84, end_note = 99, label = "C6 - D#7" }
  }
}

function Sampler.compatible(file)
  if not file or file.kind ~= "audio" or not file.path then return false end
  local ext = extension(file.path)
  return ext ~= "" and ext ~= "mid" and ext ~= "midi"
end

function Sampler.sample_name(path)
  local name = filename(path)
  return name:gsub("%.[^.]+$", "")
end

function Sampler.midi_note_name(note)
  note = math.floor(tonumber(note) or 0)
  local octave = math.floor(note / 12) - 1
  return Sampler.note_names[(note % 12) + 1] .. tostring(octave)
end

function Sampler.fx_is_rs5k(name)
  name = tostring(name or ""):lower()
  return name:find("reasamplomatic") ~= nil or name:find("rs5k") ~= nil
end

function Sampler.fx_is_cartridge(name)
  return tostring(name or ""):lower():find("cartridge") ~= nil
end

function Sampler.track_name_from_file(track, file_path)
  r.GetSetMediaTrackInfo_String(track, "P_NAME", Sampler.sample_name(file_path), true)
end

function Sampler.workbench_selection(file_path)
  if state.waveform_selection_file ~= file_path then return nil, nil end
  local start_norm = tonumber(state.waveform_selection_start)
  local end_norm = tonumber(state.waveform_selection_end)
  if not start_norm or not end_norm then return nil, nil end
  if start_norm > end_norm then start_norm, end_norm = end_norm, start_norm end
  start_norm = clamp(start_norm, 0, 1)
  end_norm = clamp(end_norm, 0, 1)
  if end_norm - start_norm < 0.001 then return nil, nil end
  return start_norm, end_norm
end

function Sampler.insert_with_reasamplomatic(app, file)
  if not Sampler.compatible(file) then return false end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local track_index = r.CountTracks(0)
  r.InsertTrackAtIndex(track_index, true)
  local track = r.GetTrack(0, track_index)
  if not track then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Workbench Media Browser: Add RS5K track", -1)
    app.status = "Could not create RS5K track"
    return false
  end
  Sampler.track_name_from_file(track, file.path)
  local fx = r.TrackFX_AddByName(track, "ReaSamploMatic5000", false, -1)
  if fx >= 0 then
    r.TrackFX_SetNamedConfigParm(track, fx, "FILE0", file.path)
    r.TrackFX_SetNamedConfigParm(track, fx, "DONE", "")
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Workbench Media Browser: Add RS5K track", -1)
  app.status = fx >= 0 and ("Added RS5K track for " .. file.name) or "Could not add ReaSamplomatic5000"
  return fx >= 0
end

function Sampler.replace_reasamplomatic_sample(app, file)
  if not Sampler.compatible(file) then return false end
  local track = r.GetSelectedTrack(0, 0)
  if not track then app.status = "Select a track for RS5K first"; return false end
  local fx = -1
  for i = 0, r.TrackFX_GetCount(track) - 1 do
    local _, name = r.TrackFX_GetFXName(track, i, "")
    if Sampler.fx_is_rs5k(name) then fx = i; break end
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if fx < 0 then fx = r.TrackFX_AddByName(track, "ReaSamploMatic5000", false, -1) end
  if fx >= 0 then
    r.TrackFX_SetNamedConfigParm(track, fx, "FILE0", file.path)
    r.TrackFX_SetNamedConfigParm(track, fx, "DONE", "")
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Workbench Media Browser: Replace RS5K sample", -1)
  app.status = fx >= 0 and ("Loaded sample to RS5K on " .. track_label(track)) or "Could not add ReaSamplomatic5000"
  return fx >= 0
end

function Sampler.cartridge_config_dir()
  local appdata = os.getenv("APPDATA")
  if not appdata then
    local home = os.getenv("HOME") or ""
    local os_name = r.GetOS()
    appdata = (os_name:match("OSX") or os_name:match("macOS")) and (home .. "/Library/Application Support") or (home .. "/.config")
  end
  local dir = appdata .. "/Cartridge"
  r.RecursiveCreateDirectory(dir, 0)
  return dir
end

function Sampler.cartridge_trigger_load(track, fx, sample_path)
  local file_handle = io.open(Sampler.cartridge_config_dir() .. "/pending_load.txt", "w")
  if file_handle then file_handle:write(sample_path); file_handle:close() end
  for i = 0, r.TrackFX_GetNumParams(track, fx) - 1 do
    local _, name = r.TrackFX_GetParamName(track, fx, i, "")
    if name == "Load Trigger" then
      local value = r.TrackFX_GetParam(track, fx, i)
      r.TrackFX_SetParam(track, fx, i, value < 0.5 and 1 or 0)
      return true
    end
  end
  return false
end

function Sampler.cartridge_apply_trim(track, fx, file_path)
  local start_norm, end_norm = Sampler.workbench_selection(file_path)
  if not start_norm or not end_norm then return false end
  for i = 0, r.TrackFX_GetNumParams(track, fx) - 1 do
    local _, name = r.TrackFX_GetParamName(track, fx, i, "")
    if name == "Sample Start" then
      r.TrackFX_SetParam(track, fx, i, start_norm)
    elseif name == "Sample End" then
      r.TrackFX_SetParam(track, fx, i, end_norm)
    elseif name == "Zoom To Fit" then
      local value = r.TrackFX_GetParam(track, fx, i)
      r.TrackFX_SetParam(track, fx, i, value < 0.5 and 1 or 0)
    end
  end
  return true
end

function Sampler.find_focused_cartridge()
  for track_index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, track_index)
    for fx = 0, r.TrackFX_GetCount(track) - 1 do
      local _, name = r.TrackFX_GetFXName(track, fx, "")
      if r.TrackFX_GetOpen(track, fx) and Sampler.fx_is_cartridge(name) then return track, fx end
    end
  end
  local master = r.GetMasterTrack(0)
  for fx = 0, r.TrackFX_GetCount(master) - 1 do
    local _, name = r.TrackFX_GetFXName(master, fx, "")
    if r.TrackFX_GetOpen(master, fx) and Sampler.fx_is_cartridge(name) then return master, fx end
  end
  return nil, nil
end

function Sampler.create_track_with_cartridge(app, file)
  if not Sampler.compatible(file) then return false end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local track_index = r.CountTracks(0)
  r.InsertTrackAtIndex(track_index, true)
  local track = r.GetTrack(0, track_index)
  if not track then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Workbench Media Browser: Add Cartridge track", -1)
    app.status = "Could not create Cartridge track"
    return false
  end
  Sampler.track_name_from_file(track, file.path)
  r.SetMediaTrackInfo_Value(track, "I_RECINPUT", 6112)
  r.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
  r.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
  local fx = r.TrackFX_AddByName(track, "Cartridge", false, -1)
  if fx < 0 then fx = r.TrackFX_AddByName(track, "VST3:Cartridge", false, -1) end
  if fx < 0 then
    r.PreventUIRefresh(-1)
    r.ShowMessageBox("Cartridge not found.\nMake sure it's installed.", "TK Workbench", 0)
    r.Undo_EndBlock("Workbench Media Browser: Add Cartridge track", -1)
    app.status = "Cartridge not found"
    return false
  end
  Sampler.cartridge_trigger_load(track, fx, file.path)
  Sampler.cartridge_apply_trim(track, fx, file.path)
  r.TrackFX_Show(track, fx, 3)
  r.SetOnlyTrackSelected(track)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Workbench Media Browser: Add Cartridge track", -1)
  app.status = "Added Cartridge track for " .. file.name
  return true
end

function Sampler.load_to_focused_cartridge(app, file)
  if not Sampler.compatible(file) then return false end
  local track, fx = Sampler.find_focused_cartridge()
  if not track then app.status = "Open a Cartridge UI first"; return false end
  r.Undo_BeginBlock()
  Sampler.cartridge_trigger_load(track, fx, file.path)
  Sampler.cartridge_apply_trim(track, fx, file.path)
  r.Undo_EndBlock("Workbench Media Browser: Load Cartridge sample", -1)
  app.status = "Loaded sample to focused Cartridge"
  return true
end

function Sampler.rs5k_instances(track)
  local instances = {}
  if not track then return instances end
  for fx = 0, r.TrackFX_GetCount(track) - 1 do
    local _, name = r.TrackFX_GetFXName(track, fx, "")
    if Sampler.fx_is_rs5k(name) then
      local note_start = math.floor((r.TrackFX_GetParamNormalized(track, fx, 3) or 0) * 127 + 0.5)
      local note_end = math.floor((r.TrackFX_GetParamNormalized(track, fx, 4) or 0) * 127 + 0.5)
      local _, sample_file = r.TrackFX_GetNamedConfigParm(track, fx, "FILE0")
      local sample_name = sample_file and sample_file ~= "" and filename(sample_file):gsub("%.[^.]+$", "") or ""
      instances[#instances + 1] = { fx = fx, note_start = note_start, note_end = note_end, sample_name = sample_name }
    end
  end
  table.sort(instances, function(a, b) return a.note_start < b.note_start end)
  return instances
end

function Sampler.load_rs5k_pad(app, file, track, fx, note)
  if not Sampler.compatible(file) or not track then return false end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if not fx then
    fx = r.TrackFX_AddByName(track, "ReaSamploMatic5000", false, -1000)
    if fx >= 0 and note then
      r.TrackFX_SetParamNormalized(track, fx, 3, note / 127)
      r.TrackFX_SetParamNormalized(track, fx, 4, note / 127)
    end
  end
  if fx and fx >= 0 then
    r.TrackFX_SetNamedConfigParm(track, fx, "FILE0", file.path)
    r.TrackFX_SetNamedConfigParm(track, fx, "DONE", "")
    Sampler.track_name_from_file(track, file.path)
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Workbench Media Browser: Load RS5K pad", -1)
  app.status = fx and fx >= 0 and "Loaded sample to RS5K pad" or "Could not add RS5K pad"
  return fx and fx >= 0
end

function Sampler.mpl_rs5k_cmd_id_value()
  if Sampler.mpl_rs5k_cmd_id and Sampler.mpl_rs5k_cmd_id > 0 then return Sampler.mpl_rs5k_cmd_id end
  local sep = package.config:sub(1, 1)
  local script_path = r.GetResourcePath() .. sep .. "Scripts" .. sep .. "MPL Scripts" .. sep .. "FX specific" .. sep .. "mpl_RS5k manager (background).lua"
  local file_handle = io.open(script_path, "r")
  if not file_handle then return nil end
  file_handle:close()
  Sampler.mpl_rs5k_cmd_id = r.AddRemoveReaScript(true, 0, script_path, true)
  return Sampler.mpl_rs5k_cmd_id
end

function Sampler.open_mpl_rs5k_manager(app)
  local command_id = Sampler.mpl_rs5k_cmd_id_value()
  if not command_id or command_id <= 0 then app.status = "MPL RS5K Manager script not found"; return false end
  r.Main_OnCommand(command_id, 0)
  app.status = "Toggled RS5K Manager"
  return true
end

function Sampler.track_guid(track)
  local _, guid = r.GetSetMediaTrackInfo_String(track, "GUID", "", false)
  return guid or ""
end

function Sampler.is_mpl_parent(track)
  if not track then return false end
  local _, parent_guid = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_GUIDINTERNAL", "", false)
  if parent_guid and parent_guid ~= "" then return true end
  if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
    local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0) - 1
    local next_track = r.GetTrack(0, index + 1)
    if next_track then
      local _, child_parent = r.GetSetMediaTrackInfo_String(next_track, "P_EXT:MPLRS5KMAN_CHILD_PARENTGUID", "", false)
      if child_parent and child_parent ~= "" then return true end
    end
  end
  return false
end

function Sampler.parent_from_child(track)
  if not track then return nil end
  local _, child_parent_guid = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_CHILD_PARENTGUID", "", false)
  if not child_parent_guid or child_parent_guid == "" then return nil end
  for track_index = 0, r.CountTracks(0) - 1 do
    local candidate = r.GetTrack(0, track_index)
    if candidate and Sampler.track_guid(candidate) == child_parent_guid then return candidate end
  end
  return nil
end

function Sampler.mpl_track_and_parent(track)
  if Sampler.is_mpl_parent(track) then return track, true end
  local parent = Sampler.parent_from_child(track)
  if parent then return parent, true end
  return track, false
end

function Sampler.find_mpl_midi_bus(parent_track, parent_guid)
  local parent_index = math.floor(r.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") or 0) - 1
  for track_index = parent_index + 1, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, track_index)
    if not track then break end
    local _, is_midibus = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_MIDIBUS", "", false)
    if is_midibus == "1" then
      local _, bus_parent = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_CHILD_PARENTGUID", "", false)
      if bus_parent == parent_guid then return track, track_index end
    end
    if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") < 0 then break end
  end
  return nil, nil
end

function Sampler.create_mpl_midi_bus(parent_track, parent_guid, parent_index)
  local insert_index = parent_index + 1
  r.InsertTrackAtIndex(insert_index, false)
  local midi_bus = r.GetTrack(0, insert_index)
  if not midi_bus then return nil, nil end
  r.GetSetMediaTrackInfo_String(midi_bus, "P_NAME", "MIDI bus", true)
  r.SetMediaTrackInfo_Value(midi_bus, "I_RECMON", 1)
  r.SetMediaTrackInfo_Value(midi_bus, "I_RECARM", 1)
  r.SetMediaTrackInfo_Value(midi_bus, "I_RECMODE", 0)
  r.SetMediaTrackInfo_Value(midi_bus, "I_RECINPUT", 4096 + (63 << 5))
  r.GetSetMediaTrackInfo_String(midi_bus, "P_EXT:MPLRS5KMAN_VERSION", "4.14", true)
  r.GetSetMediaTrackInfo_String(midi_bus, "P_EXT:MPLRS5KMAN_MIDIBUS", "1", true)
  r.GetSetMediaTrackInfo_String(midi_bus, "P_EXT:MPLRS5KMAN_CHILD_PARENTGUID", parent_guid, true)
  if r.GetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH") ~= 1 then
    r.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
    r.SetMediaTrackInfo_Value(midi_bus, "I_FOLDERDEPTH", -1)
  else
    r.SetMediaTrackInfo_Value(midi_bus, "I_FOLDERDEPTH", 0)
  end
  return midi_bus, insert_index
end

function Sampler.create_midi_send_to_child(midi_bus, child_track)
  if not midi_bus or not child_track then return end
  for send_index = 0, r.GetTrackNumSends(midi_bus, 0) - 1 do
    if r.GetTrackSendInfo_Value(midi_bus, 0, send_index, "P_DESTTRACK") == child_track then return end
  end
  local send_index = r.CreateTrackSend(midi_bus, child_track)
  if send_index >= 0 then
    r.SetTrackSendInfo_Value(midi_bus, 0, send_index, "I_SRCCHAN", -1)
    r.SetTrackSendInfo_Value(midi_bus, 0, send_index, "I_MIDIFLAGS", 0)
  end
end

function Sampler.filled_mpl_pads(parent_track)
  local filled = {}
  if not parent_track then return filled end
  local parent_index = math.floor(r.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") or 0) - 1
  local parent_guid = Sampler.track_guid(parent_track)
  local _, parent_guid_internal = r.GetSetMediaTrackInfo_String(parent_track, "P_EXT:MPLRS5KMAN_GUIDINTERNAL", "", false)
  local folder_depth = 0
  for track_index = parent_index + 1, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, track_index)
    if not track then break end
    folder_depth = folder_depth + (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0)
    local _, is_midibus = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_MIDIBUS", "", false)
    if is_midibus ~= "1" then
      local _, child_parent = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_CHILD_PARENTGUID", "", false)
      local is_child = child_parent ~= "" and (child_parent == parent_guid or child_parent == parent_guid_internal)
      if not is_child and r.GetParentTrack(track) == parent_track then is_child = true end
      if is_child then
        for fx = 0, r.TrackFX_GetCount(track) - 1 do
          local _, name = r.TrackFX_GetFXName(track, fx, "")
          if Sampler.fx_is_rs5k(name) then
            local _, note_text = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_NOTE", "", false)
            local note = tonumber(note_text) or math.floor((r.TrackFX_GetParamNormalized(track, fx, 3) or 0) * 127 + 0.5)
            local _, sample_file = r.TrackFX_GetNamedConfigParm(track, fx, "FILE0")
            local sample_name = sample_file and sample_file ~= "" and filename(sample_file):gsub("%.[^.]+$", "") or ""
            filled[#filled + 1] = { note = note, track = track, fx = fx, sample_name = sample_name }
            break
          end
        end
      end
    end
    if folder_depth < 0 then break end
  end
  table.sort(filled, function(a, b) return a.note < b.note end)
  return filled
end

function Sampler.find_mpl_pad(filled_pads, note)
  for _, pad in ipairs(filled_pads or {}) do
    if pad.note == note then return pad end
  end
  return nil
end

function Sampler.delete_mpl_pad(app, pad)
  if not pad or not pad.track then return false end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.DeleteTrack(pad.track)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Workbench Media Browser: Delete RS5K Manager pad", -1)
  app.status = "Deleted RS5K Manager pad " .. Sampler.midi_note_name(pad.note)
  return true
end

function Sampler.empty_child_track_for_note(parent_track, parent_guid, note)
  local parent_index = math.floor(r.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") or 0) - 1
  for track_index = parent_index + 1, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, track_index)
    if not track then break end
    local _, is_midibus = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_MIDIBUS", "", false)
    if is_midibus ~= "1" then
      local _, child_parent = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_CHILD_PARENTGUID", "", false)
      local _, note_text = r.GetSetMediaTrackInfo_String(track, "P_EXT:MPLRS5KMAN_NOTE", "", false)
      if child_parent == parent_guid and tonumber(note_text) == note then
        local has_rs5k = false
        for fx = 0, r.TrackFX_GetCount(track) - 1 do
          local _, name = r.TrackFX_GetFXName(track, fx, "")
          if Sampler.fx_is_rs5k(name) then has_rs5k = true; break end
        end
        if not has_rs5k then return track end
      end
    end
    if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") < 0 then break end
  end
  return nil
end

function Sampler.create_rs5k_manager_pad(app, file, parent_track, note)
  if not Sampler.compatible(file) or not parent_track then return false end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local parent_guid = Sampler.track_guid(parent_track)
  local parent_index = math.floor(r.GetMediaTrackInfo_Value(parent_track, "IP_TRACKNUMBER") or 0) - 1
  if r.GetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH") ~= 1 then r.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1) end
  r.GetSetMediaTrackInfo_String(parent_track, "P_EXT:MPLRS5KMAN_GUIDINTERNAL", parent_guid, true)
  r.GetSetMediaTrackInfo_String(parent_track, "P_EXT:MPLRS5KMAN_DRRACKSHIFT", "36", true)
  local midi_bus, midi_bus_index = Sampler.find_mpl_midi_bus(parent_track, parent_guid)
  if not midi_bus then midi_bus, midi_bus_index = Sampler.create_mpl_midi_bus(parent_track, parent_guid, parent_index) end
  local pad_track = Sampler.empty_child_track_for_note(parent_track, parent_guid, note)
  if pad_track and midi_bus then
    Sampler.create_midi_send_to_child(midi_bus, pad_track)
  elseif not pad_track then
    local insert_index = midi_bus_index or (parent_index + 1)
    r.InsertTrackAtIndex(insert_index, false)
    pad_track = r.GetTrack(0, insert_index)
    if not pad_track then
      r.PreventUIRefresh(-1)
      r.Undo_EndBlock("Workbench Media Browser: Create RS5K Manager pad", -1)
      app.status = "Could not create RS5K Manager pad"
      return false
    end
    r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_VERSION", "4.14", true)
    r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_NOTE", tostring(note), true)
    r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_CHILD_PARENTGUID", parent_guid, true)
    r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_TYPE_REGCHILD", "1", true)
    r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_TSADD", tostring(os.time()), true)
    r.SetMediaTrackInfo_Value(pad_track, "I_FOLDERDEPTH", 0)
    midi_bus = midi_bus or Sampler.find_mpl_midi_bus(parent_track, parent_guid)
    if midi_bus then Sampler.create_midi_send_to_child(midi_bus, pad_track) end
  end
  Sampler.track_name_from_file(pad_track, file.path)
  local source = r.PCM_Source_CreateFromFileEx(file.path, true)
  if source then
    local sample_length = r.GetMediaSourceLength(source)
    r.PCM_Source_Destroy(source)
    if sample_length and sample_length > 0 then r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_SAMPLELEN", tostring(sample_length), true) end
  end
  local fx = r.TrackFX_AddByName(pad_track, "ReaSamploMatic5000", false, -1000)
  if fx >= 0 then
    r.TrackFX_SetNamedConfigParm(pad_track, fx, "FILE0", file.path)
    r.TrackFX_SetNamedConfigParm(pad_track, fx, "DONE", "")
    r.TrackFX_SetNamedConfigParm(pad_track, fx, "MODE", "1")
    r.TrackFX_SetParamNormalized(pad_track, fx, 3, note / 127)
    r.TrackFX_SetParamNormalized(pad_track, fx, 4, note / 127)
    r.TrackFX_SetParamNormalized(pad_track, fx, 2, 0)
    r.TrackFX_SetParamNormalized(pad_track, fx, 11, 1)
    r.TrackFX_SetParamNormalized(pad_track, fx, 8, 0)
    r.TrackFX_SetOpen(pad_track, fx, false)
    local fx_guid = r.TrackFX_GetFXGUID(pad_track, fx)
    if fx_guid then r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_CHILD_INSTR_FXGUID", fx_guid, true) end
    r.GetSetMediaTrackInfo_String(pad_track, "P_EXT:MPLRS5KMAN_CHILD_ISRS5K", "1", true)
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Workbench Media Browser: Create RS5K Manager pad", -1)
  app.status = fx >= 0 and ("Loaded sample to RS5K Manager " .. Sampler.midi_note_name(note)) or "Could not add RS5K to manager pad"
  return fx >= 0
end

function Sampler.create_empty_rs5k_manager(app)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local track_index = r.CountTracks(0)
  r.InsertTrackAtIndex(track_index, true)
  local parent_track = r.GetTrack(0, track_index)
  if not parent_track then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Workbench Media Browser: Create RS5K Manager", -1)
    app.status = "Could not create RS5K Manager"
    return false
  end
  r.GetSetMediaTrackInfo_String(parent_track, "P_NAME", "RS5K Manager", true)
  r.SetMediaTrackInfo_Value(parent_track, "I_FOLDERDEPTH", 1)
  local parent_guid = Sampler.track_guid(parent_track)
  r.GetSetMediaTrackInfo_String(parent_track, "P_EXT:MPLRS5KMAN_GUIDINTERNAL", parent_guid, true)
  r.GetSetMediaTrackInfo_String(parent_track, "P_EXT:MPLRS5KMAN_DRRACKSHIFT", "36", true)
  local midi_bus = Sampler.create_mpl_midi_bus(parent_track, parent_guid, track_index)
  if midi_bus then r.SetMediaTrackInfo_Value(midi_bus, "I_FOLDERDEPTH", -1) end
  r.SetOnlyTrackSelected(parent_track)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Workbench Media Browser: Create RS5K Manager", -1)
  app.status = "Created RS5K Manager"
  return true
end

function Sampler.draw_rs5k_pad_menu(ctx, app, file)
  local track = r.GetSelectedTrack(0, 0)
  if track then
    local parent_track, is_manager = Sampler.mpl_track_and_parent(track)
    if is_manager then
      local filled_pads = Sampler.filled_mpl_pads(parent_track)
      if r.ImGui_BeginMenu(ctx, "Load to RS5K Manager...") then
        for _, pad in ipairs(filled_pads) do
          local label = Sampler.midi_note_name(pad.note)
          if pad.sample_name ~= "" then label = label .. " - " .. pad.sample_name end
          if r.ImGui_MenuItem(ctx, label) then Sampler.load_rs5k_pad(app, file, pad.track, pad.fx, nil) end
        end
        if #filled_pads > 0 then r.ImGui_Separator(ctx) end
        for _, range in ipairs(Sampler.pad_ranges) do
          if r.ImGui_BeginMenu(ctx, range.label) then
            for note = range.start_note, range.end_note do
              if not Sampler.find_mpl_pad(filled_pads, note) and r.ImGui_MenuItem(ctx, Sampler.midi_note_name(note)) then Sampler.create_rs5k_manager_pad(app, file, parent_track, note) end
            end
            r.ImGui_EndMenu(ctx)
          end
        end
        r.ImGui_EndMenu(ctx)
      end
      if #filled_pads > 0 and r.ImGui_BeginMenu(ctx, "Delete RS5K Manager Pad...") then
        for _, pad in ipairs(filled_pads) do
          local label = Sampler.midi_note_name(pad.note)
          if pad.sample_name ~= "" then label = label .. " - " .. pad.sample_name end
          if r.ImGui_MenuItem(ctx, label) then Sampler.delete_mpl_pad(app, pad) end
        end
        r.ImGui_EndMenu(ctx)
      end
    elseif r.ImGui_MenuItem(ctx, "Create RS5K Manager from selected track (C2)") then
      Sampler.create_rs5k_manager_pad(app, file, parent_track, 36)
    elseif r.ImGui_MenuItem(ctx, "Create new RS5K Manager and load to C2") then
      if Sampler.create_empty_rs5k_manager(app) then Sampler.create_rs5k_manager_pad(app, file, r.GetSelectedTrack(0, 0), 36) end
    end
  elseif r.ImGui_MenuItem(ctx, "Create new RS5K Manager and load to C2") then
    if Sampler.create_empty_rs5k_manager(app) then Sampler.create_rs5k_manager_pad(app, file, r.GetSelectedTrack(0, 0), 36) end
  end
  if r.ImGui_MenuItem(ctx, "Create empty RS5K Manager") then Sampler.create_empty_rs5k_manager(app) end
  if r.ImGui_MenuItem(ctx, "RS5K Manager") then Sampler.open_mpl_rs5k_manager(app) end
end

function Sampler.draw_context_menu(ctx, app, file)
  if not Sampler.compatible(file) then return end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Add to new track with ReaSamplomatic5000") then Sampler.insert_with_reasamplomatic(app, file) end
  if r.ImGui_MenuItem(ctx, "Replace or add sample on selected track") then Sampler.replace_reasamplomatic_sample(app, file) end
  if r.ImGui_MenuItem(ctx, "Add to new track with Cartridge") then Sampler.create_track_with_cartridge(app, file) end
  if r.ImGui_MenuItem(ctx, "Load sample to focused Cartridge") then Sampler.load_to_focused_cartridge(app, file) end
  Sampler.draw_rs5k_pad_menu(ctx, app, file)
end

local function shift_down(ctx)
  if not r.ImGui_IsKeyDown then return false end
  return (r.ImGui_Key_LeftShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift())) or (r.ImGui_Key_RightShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift()))
end

local function register_drag_source(ctx, file, hovered)
  if not hovered or state.dragging_file then return end
  if r.ImGui_IsMouseClicked(ctx, 0) then
    local x, y = mouse_screen_position()
    state.potential_drag_file = file
    state.potential_drag_x = x or 0
    state.potential_drag_y = y or 0
  end
end

local function update_drag(app)
  local ctx = app.ctx
  if not r.ImGui_IsMouseDown or not r.ImGui_IsMouseReleased or not r.GetTrackFromPoint then return end
  local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
  local released = r.ImGui_IsMouseReleased(ctx, 0)
  if state.potential_drag_file and not state.dragging_file then
    if not mouse_down then
      state.potential_drag_file = nil
    else
      local x, y = mouse_screen_position()
      if x and y then
        local dx = x - (state.potential_drag_x or x)
        local dy = y - (state.potential_drag_y or y)
        if dx * dx + dy * dy >= state.drag_threshold * state.drag_threshold then
          state.dragging_file = state.potential_drag_file
          state.potential_drag_file = nil
          state.drag_saved_cursor = r.GetCursorPosition()
        end
      end
    end
  end
  if state.dragging_file then
    local track, lane = track_under_mouse()
    state.drag_target_track = track
    state.drag_target_lane = lane
    if track then
      local cursor = arrange_time_under_mouse()
      if cursor then
        state.drag_cursor_position = cursor
        r.SetEditCurPos(cursor, false, false)
      end
      app.status = "Drop " .. state.dragging_file.name .. " on " .. track_label(track)
    else
      app.status = "Drop " .. state.dragging_file.name .. " on a track"
    end
    if released or not mouse_down then
      if track then
        insert_file_on_track(app, state.dragging_file, track, lane)
      elseif state.drag_saved_cursor then
        r.SetEditCurPos(state.drag_saved_cursor, false, false)
      end
      clear_drag()
    end
  elseif released then
    state.potential_drag_file = nil
  end
end

local function draw_drag_overlay(app)
  if not state.dragging_file or not r.ImGui_GetMousePos or not r.ImGui_GetMainViewport then return end
  local ctx = app.ctx
  local imx, imy = r.ImGui_GetMousePos(ctx)
  local vp = r.ImGui_GetMainViewport(ctx)
  local vp_x, vp_y = r.ImGui_Viewport_GetPos(vp)
  local target_color = state.drag_target_track and 0x40C040FF or 0xFF4040FF
  local marker_radius = 22
  local flags = r.ImGui_WindowFlags_NoDecoration() | r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoSavedSettings() | r.ImGui_WindowFlags_NoInputs() | r.ImGui_WindowFlags_NoBackground()
  r.ImGui_SetNextWindowPos(ctx, imx - vp_x - 30, imy - vp_y - 30, r.ImGui_Cond_Always())
  r.ImGui_SetNextWindowSize(ctx, 60, 60, r.ImGui_Cond_Always())
  r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
  if r.ImGui_Begin(ctx, "##media_drag_marker", true, flags) then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddCircleFilled(draw_list, imx, imy, marker_radius, (target_color & 0xFFFFFF00) | 0x44, 0)
    r.ImGui_DrawList_AddCircle(draw_list, imx, imy, marker_radius, target_color, 0, 3)
    r.ImGui_End(ctx)
  end
  local overlay_flags = r.ImGui_WindowFlags_NoDecoration() | r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoSavedSettings() | r.ImGui_WindowFlags_NoInputs()
  r.ImGui_SetNextWindowBgAlpha(ctx, 0.42)
  r.ImGui_SetNextWindowPos(ctx, imx - vp_x + 34, imy - vp_y + 34, r.ImGui_Cond_Always())
  if r.ImGui_Begin(ctx, "##media_drag_overlay", true, overlay_flags) then
    r.ImGui_Text(ctx, "Media " .. state.dragging_file.name)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), target_color)
    r.ImGui_Text(ctx, "Track: " .. track_label(state.drag_target_track))
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Text(ctx, "Release to insert")
    r.ImGui_End(ctx)
  end
end

local function draw_location_combo(ctx, settings, app, width)
  local current = selected_location(settings)
  if settings.location_view_mode == "auto" then
    build_category_counts(settings)
    local selected = settings.auto_selected_category or "All"
    local label = "Auto: " .. category_label(selected)
    r.ImGui_PushItemWidth(ctx, width)
    if r.ImGui_BeginCombo(ctx, "##media_location", label) then
      local all_count = state.category_counts.All or #state.files
      if r.ImGui_Selectable(ctx, "All (" .. tostring(all_count) .. ")##cat_all", selected == "All") then
        settings.auto_selected_category = "All"
        state.last_filter_key = nil
        if app.save_settings then app.save_settings() end
      end
      if selected == "All" then r.ImGui_SetItemDefaultFocus(ctx) end
      for _, category in ipairs(categorizer.get_category_order()) do
        local count = state.category_counts[category] or 0
        if count > 0 then
          local is_selected = selected == category
          if r.ImGui_Selectable(ctx, category_label(category) .. " (" .. tostring(count) .. ")##cat_" .. category, is_selected) then
            settings.auto_selected_category = category
            state.last_filter_key = nil
            if app.save_settings then app.save_settings() end
          end
          if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
      end
      local other_count = state.category_counts.other or 0
      if other_count > 0 then
        local is_selected = selected == "other"
        if r.ImGui_Selectable(ctx, "Other (" .. tostring(other_count) .. ")##cat_other", is_selected) then
          settings.auto_selected_category = "other"
          state.last_filter_key = nil
          if app.save_settings then app.save_settings() end
        end
        if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, is_project_files_location(current) and project_files_tooltip() or (current ~= "" and current or "No source location")) end
    r.ImGui_PopItemWidth(ctx)
    return
  end
  local label = location_label(current)
  if folder_browse_active(settings) and (state.folder_path or "") ~= "" then label = label .. "/" .. filename(state.folder_path) end
  r.ImGui_PushItemWidth(ctx, width)
  if r.ImGui_BeginCombo(ctx, "##media_location", label) then
    local project_selected = is_project_files_location(current)
    if r.ImGui_Selectable(ctx, "Project files##loc_project_files", project_selected) then
      settings.current_location = PROJECT_FILES_LOCATION
      if app.save_settings then app.save_settings() end
      load_or_scan_location(settings, false)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, project_files_tooltip()) end
    if project_selected then r.ImGui_SetItemDefaultFocus(ctx) end
    if #state.locations > 0 then r.ImGui_Separator(ctx) end
    for index, path in ipairs(state.locations) do
      local selected = path == current
      if r.ImGui_Selectable(ctx, filename(path) .. "##loc" .. tostring(index), selected) then
        settings.current_location = path
        if app.save_settings then app.save_settings() end
        load_or_scan_location(settings, false)
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, path) end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_PopItemWidth(ctx)
end

local function add_location(settings, app)
  local path = browse_location(settings)
  if path == "" then return end
  settings.last_browse_location = path
  for _, existing in ipairs(state.locations) do
    if existing:lower() == path:lower() then
      settings.current_location = existing
      if app.save_settings then app.save_settings() end
      load_or_scan_location(settings, false)
      return
    end
  end
  state.locations[#state.locations + 1] = path
  write_locations(state.locations)
  settings.current_location = path
  if app.save_settings then app.save_settings() end
  load_or_scan_location(settings, false)
end

local function select_location(settings, app, path)
  if not path or path == "" or settings.current_location == path then return end
  settings.current_location = path
  if app.save_settings then app.save_settings() end
  load_or_scan_location(settings, false)
end

local function save_location_order(settings, app, selected_path)
  write_locations(state.locations)
  if selected_path and selected_path ~= "" then settings.current_location = selected_path end
  if settings.current_location == "" or not selected_location(settings) then settings.current_location = state.locations[1] or "" end
  if app.save_settings then app.save_settings() end
end

local function move_location(settings, app, index, direction)
  local target = index + direction
  if target < 1 or target > #state.locations then return end
  local selected_path = selected_location(settings)
  state.locations[index], state.locations[target] = state.locations[target], state.locations[index]
  save_location_order(settings, app, selected_path)
end

local function remove_location(settings, app, index)
  local removed = table.remove(state.locations, index)
  if not removed then return end
  if settings.current_location == removed then
    settings.current_location = state.locations[math.min(index, #state.locations)] or state.locations[1] or ""
    save_location_order(settings, app, settings.current_location)
    load_or_scan_location(settings, false)
  else
    save_location_order(settings, app, selected_location(settings))
  end
end

local function draw_location_manager(app, settings)
  local ctx = app.ctx
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Locations")
  local row_h = r.ImGui_GetFrameHeight(ctx) + 4
  local child_h = math.min(180, math.max(row_h + 8, #state.locations * row_h + 8))
  if r.ImGui_BeginChild(ctx, "##media_location_manager", 0, child_h, 1) then
    for index, path in ipairs(state.locations) do
      r.ImGui_PushID(ctx, "location_manager_" .. tostring(index))
      local current = path == selected_location(settings)
      if r.ImGui_Button(ctx, "x", 22, 0) then remove_location(settings, app, index); r.ImGui_PopID(ctx); break end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove") end
      r.ImGui_SameLine(ctx)
      local label = filename(path) .. "##managed_location"
      if r.ImGui_Selectable(ctx, label, current) then select_location(settings, app, path) end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, path) end
      if r.ImGui_BeginDragDropSource and r.ImGui_BeginDragDropSource(ctx, 0) then
        r.ImGui_SetDragDropPayload(ctx, "TK_WB_LOCATION_REORDER", tostring(index))
        r.ImGui_Text(ctx, filename(path))
        r.ImGui_EndDragDropSource(ctx)
      end
      if r.ImGui_BeginDragDropTarget and r.ImGui_BeginDragDropTarget(ctx) then
        local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WB_LOCATION_REORDER")
        if ok then
          local source_index = tonumber(payload)
          if source_index and source_index ~= index and state.locations[source_index] then
            local selected_path = selected_location(settings)
            local item = table.remove(state.locations, source_index)
            table.insert(state.locations, index, item)
            save_location_order(settings, app, selected_path)
          end
        end
        r.ImGui_EndDragDropTarget(ctx)
      end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
end

local function draw_media_settings_popup(app, settings)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup(ctx, "##media_browser_settings") then return end
  local changed = false
  r.ImGui_Text(ctx, "Preview")
  local c, v = r.ImGui_Checkbox(ctx, "Use selected track for audio", settings.use_selected_track_for_audio == true)
  if c then settings.use_selected_track_for_audio = v; changed = true end
  if settings.use_selected_track_for_audio and not r.CF_Preview_SetOutputTrack then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.colors.text_dim)
    r.ImGui_Text(ctx, "Selected audio track routing unavailable")
    r.ImGui_PopStyleColor(ctx)
  end
  c, v = r.ImGui_Checkbox(ctx, "Use selected track for MIDI", settings.use_selected_track_for_midi == true)
  if c then settings.use_selected_track_for_midi = v; changed = true end
  c, v = r.ImGui_Checkbox(ctx, "Exclusive solo MIDI/video preview", settings.exclusive_solo_preview == true)
  if c then
    settings.exclusive_solo_preview = v
    changed = true
    if state.preview_track_playback then
      if v then apply_exclusive_solo(state.preview_track) else restore_solo_states() end
    end
  end
  c, v = r.ImGui_Checkbox(ctx, "Sync rate to project tempo", settings.tempo_sync == true)
  if c then
    settings.tempo_sync = v
    if v then settings.preview_tape_speed = false end
    changed = true
    apply_preview_rate(settings)
  end
  c, v = r.ImGui_Checkbox(ctx, "Tape-speed rate", settings.preview_tape_speed == true)
  if c then
    settings.preview_tape_speed = v
    if v then settings.tempo_sync = false end
    changed = true
    apply_preview_rate(settings)
  end
  c, v = r.ImGui_Checkbox(ctx, "Loop preview", settings.loop_preview == true)
  if c then
    settings.loop_preview = v
    changed = true
    if state.preview and r.CF_Preview_SetValue then
      r.CF_Preview_SetValue(state.preview, "B_LOOP", settings.loop_preview and 1 or 0)
    elseif state.preview_track_playback then
      r.GetSetRepeat(settings.loop_preview and 1 or 0)
    end
  end
  c, v = r.ImGui_Checkbox(ctx, "Auto play", settings.auto_play == true)
  if c then settings.auto_play = v; changed = true end
  c, v = r.ImGui_Checkbox(ctx, "Auto play next", settings.auto_play_next == true)
  if c then settings.auto_play_next = v; changed = true end
  c, v = r.ImGui_Checkbox(ctx, "Random play next", settings.random_play_next == true)
  if c then settings.random_play_next = v; changed = true end
  r.ImGui_PushItemWidth(ctx, 170)
  c, v = r.ImGui_SliderDouble(ctx, "Preview fade ms", settings.preview_fade_ms or defaults.preview_fade_ms, 0, 250, "%.0f")
  if c then settings.preview_fade_ms = v; changed = true end
  c, v = r.ImGui_SliderDouble(ctx, "Switch gap ms", settings.preview_restart_gap_ms or defaults.preview_restart_gap_ms, 0, 100, "%.0f")
  if c then settings.preview_restart_gap_ms = v; changed = true end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Folder browsing")
  c, v = r.ImGui_Checkbox(ctx, "Double-click to open folders", settings.folder_double_click_open == true)
  if c then settings.folder_double_click_open = v; changed = true end
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Trim")
  local trim_changed = false
  c, v = r.ImGui_Checkbox(ctx, "Auto trim silence", settings.trim_silence_enabled == true)
  if c then settings.trim_silence_enabled = v; changed = true; trim_changed = true end
  local disabled = settings.trim_silence_enabled ~= true
  if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  r.ImGui_PushItemWidth(ctx, 170)
  c, v = r.ImGui_SliderDouble(ctx, "Threshold dB", settings.trim_silence_threshold_db or defaults.trim_silence_threshold_db, -96, -12, "%.0f")
  if c then settings.trim_silence_threshold_db = v; changed = true; trim_changed = true end
  c, v = r.ImGui_SliderDouble(ctx, "Padding ms", settings.trim_silence_padding_ms or defaults.trim_silence_padding_ms, 0, 250, "%.0f")
  if c then settings.trim_silence_padding_ms = v; changed = true; trim_changed = true end
  r.ImGui_PopItemWidth(ctx)
  if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  if trim_changed and state.selected_file then
    if settings.trim_silence_enabled then
      if apply_silence_trim_selection then apply_silence_trim_selection(state.selected_file, settings, true) end
    elseif state.waveform_selection_auto then
      clear_waveform_selection()
    end
  end
  draw_location_manager(app, settings)
  if changed and app.save_settings then app.save_settings() end
  r.ImGui_EndPopup(ctx)
end

local function draw_toolbar(app, settings, width)
  local ctx = app.ctx
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local compact = width < 330
  local auto_w = button_h
  local loc_w = compact and math.max(70, width - auto_w - button_h * 4 - 44) or math.max(120, width - auto_w - button_h * 4 - 44)
  draw_location_combo(ctx, settings, app, loc_w)
  r.ImGui_SameLine(ctx)
  local auto_active = settings.location_view_mode == "auto"
  if auto_active then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent & 0xFFFFFFAA) end
  if r.ImGui_Button(ctx, "A", auto_w, button_h) then
    settings.location_view_mode = auto_active and "folders" or "auto"
    state.last_filter_key = nil
    if app.save_settings then app.save_settings() end
  end
  if auto_active then r.ImGui_PopStyleColor(ctx) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Auto categories") end
  r.ImGui_SameLine(ctx)
  local folder_active = folder_browse_active(settings)
  if folder_active then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent & 0xFFFFFFAA) end
  if r.ImGui_Button(ctx, "F", button_h, button_h) then
    settings.folder_browse = not folder_active
    if settings.folder_browse then settings.location_view_mode = "folders" end
    state.last_filter_key = nil
    if app.save_settings then app.save_settings() end
  end
  if folder_active then r.ImGui_PopStyleColor(ctx) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Folder view") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+", button_h, button_h) then add_location(settings, app) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add location") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "R", button_h, button_h) then load_or_scan_location(settings, true) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Refresh cache") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "...", button_h, button_h) then r.ImGui_OpenPopup(ctx, "##media_browser_settings") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Media Browser settings") end
  draw_media_settings_popup(app, settings)
end

local function draw_filter_icon(draw_list, kind, x, y, size, color)
  local cx = x + size * 0.5
  local cy = y + size * 0.5
  if kind == "audio" then
    local steps = 18
    local prev_x, prev_y = x, cy
    for index = 1, steps do
      local t = index / steps
      local nx = x + t * size
      local ny = cy + math.sin(t * math.pi * 2) * (size * 0.30)
      r.ImGui_DrawList_AddLine(draw_list, prev_x, prev_y, nx, ny, color, 1.5)
      prev_x, prev_y = nx, ny
    end
  elseif kind == "midi" then
    r.ImGui_DrawList_AddCircleFilled(draw_list, x + size * 0.32, y + size * 0.72, size * 0.18, color)
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.50, y + size * 0.72, x + size * 0.50, y + size * 0.18, color, 1.6)
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.50, y + size * 0.18, x + size * 0.84, y + size * 0.32, color, 1.6)
    r.ImGui_DrawList_AddLine(draw_list, x + size * 0.50, y + size * 0.36, x + size * 0.84, y + size * 0.50, color, 1.6)
  elseif kind == "video" then
    local pad = size * 0.14
    r.ImGui_DrawList_AddRect(draw_list, x + pad, y + pad, x + size - pad, y + size - pad, color, 2, 0, 1.4)
    r.ImGui_DrawList_AddTriangleFilled(draw_list, cx - size * 0.12, cy - size * 0.18, cx - size * 0.12, cy + size * 0.18, cx + size * 0.20, cy, color)
  elseif kind == "image" then
    local pad = size * 0.14
    r.ImGui_DrawList_AddRect(draw_list, x + pad, y + pad, x + size - pad, y + size - pad, color, 2, 0, 1.4)
    r.ImGui_DrawList_AddCircleFilled(draw_list, x + size * 0.70, y + size * 0.34, size * 0.08, color)
    r.ImGui_DrawList_AddTriangle(draw_list, x + pad + 1, y + size - pad - 1, x + size * 0.50, y + size * 0.46, x + size - pad - 1, y + size - pad - 1, color, 1.5)
  end
end

local function draw_filter_toggle(ctx, kind, active, tooltip)
  local button_size = 22
  local icon_size = 16
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##media_filter_" .. kind, button_size, button_size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  if hovered then r.ImGui_SetTooltip(ctx, tooltip) end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local color = active and (hovered and Theme.colors.text or Theme.colors.accent) or Theme.colors.text_dim
  draw_filter_icon(draw_list, kind, x + (button_size - icon_size) * 0.5, y + (button_size - icon_size) * 0.5, icon_size, color)
  return clicked
end

local function draw_filter_buttons(ctx, settings, app, width)
  local changed = false
  local row_w = width or r.ImGui_GetContentRegionAvail(ctx) or 320
  local spacing_x = 4
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    spacing_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing()) or spacing_x
  end
  local icon_w = 22
  local search_w = math.max(1, row_w - icon_w * 4 - spacing_x * 4)
  r.ImGui_PushItemWidth(ctx, search_w)
  local search_changed, search = r.ImGui_InputTextWithHint(ctx, "##media_search", "Search", settings.search_term or "")
  if search_changed then settings.search_term = search; state.last_filter_key = nil; if app.save_settings then app.save_settings() end end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_SameLine(ctx)
  if draw_filter_toggle(ctx, "audio", settings.show_audio ~= false, "Audio files") then settings.show_audio = not (settings.show_audio ~= false); changed = true end
  r.ImGui_SameLine(ctx)
  if draw_filter_toggle(ctx, "midi", settings.show_midi ~= false, "MIDI files") then settings.show_midi = not (settings.show_midi ~= false); changed = true end
  r.ImGui_SameLine(ctx)
  if draw_filter_toggle(ctx, "video", settings.show_video == true, "Video files") then settings.show_video = not (settings.show_video == true); changed = true end
  r.ImGui_SameLine(ctx)
  if draw_filter_toggle(ctx, "image", settings.show_image == true, "Picture files") then settings.show_image = not (settings.show_image == true); changed = true end
  if changed then state.last_filter_key = nil; if app.save_settings then app.save_settings() end end
end

function select_file(app, file, index, autoplay)
  if not file then return false end
  local changed = not state.selected_file or state.selected_file.path ~= file.path
  if changed then
    clear_waveform_pending()
    clear_waveform_selection()
    reset_waveform_zoom()
    clear_image_cache(app.ctx, file.path)
  end
  state.selected_file = file
  state.selected_index = index
  state.file_list_keyboard_focus = true
  local settings = ensure_settings(app)
  if changed and apply_silence_trim_selection then apply_silence_trim_selection(file, settings, false) end
  if autoplay and settings.auto_play and can_preview_file(file) then start_preview(settings, file) end
  return true
end

local function scroll_selected_file_into_view(ctx, row_h)
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

local function file_list_window_active(ctx)
  if r.ImGui_IsWindowHovered then
    local ok, hovered = pcall(r.ImGui_IsWindowHovered, ctx)
    if ok and hovered then return true end
  end
  if r.ImGui_IsWindowFocused then
    local ok, focused = pcall(r.ImGui_IsWindowFocused, ctx)
    if ok and focused then return true end
  end
  return state.file_list_keyboard_focus == true
end

local function open_folder_entry(app, entry)
  if not entry or (entry.kind ~= "folder" and entry.kind ~= "folder_up") then return false end
  state.folder_path = entry.kind == "folder_up" and (entry.path or "") or (entry.folder_path or entry.path or "")
  state.last_filter_key = nil
  state.selected_index = nil
  state.selected_file = nil
  state.file_list_keyboard_focus = true
  clear_waveform_pending()
  clear_waveform_selection()
  reset_waveform_zoom()
  clear_image_cache(app.ctx)
  return true
end

local function handle_file_list_keyboard(app, settings, row_h)
  local ctx = app.ctx
  if #state.filtered == 0 or not file_list_window_active(ctx) or not keyboard_input_available(ctx) then return false end
  local index = state.selected_index
  local target_index = nil
  local random_navigation = settings.auto_play == true and settings.random_play_next == true
  if key_pressed(ctx, "UpArrow") then target_index = random_navigation and random_preview_index(index) or (index and math.max(1, index - 1) or 1)
  elseif key_pressed(ctx, "DownArrow") then target_index = random_navigation and random_preview_index(index) or (index and math.min(#state.filtered, index + 1) or 1)
  elseif key_pressed(ctx, "PageUp") then target_index = index and math.max(1, index - 10) or 1
  elseif key_pressed(ctx, "PageDown") then target_index = index and math.min(#state.filtered, index + 10) or 1
  elseif key_pressed(ctx, "Home") then target_index = 1
  elseif key_pressed(ctx, "End") then target_index = #state.filtered end
  if target_index then
    local entry = state.filtered[target_index]
    if entry and (entry.kind == "folder" or entry.kind == "folder_up") then
      state.selected_index = target_index
      state.selected_file = nil
      state.file_list_keyboard_focus = true
      state.scroll_selected_file = true
      scroll_selected_file_into_view(ctx, row_h)
    elseif select_file(app, entry, target_index, true) then
      state.scroll_selected_file = true
      scroll_selected_file_into_view(ctx, row_h)
    end
    return true
  end
  if key_pressed(ctx, "Enter") or key_pressed(ctx, "KeypadEnter") then
    local entry = state.filtered[index or 1]
    if entry and (entry.kind == "folder" or entry.kind == "folder_up") then return open_folder_entry(app, entry) end
    local file = state.selected_file or entry
    if file and can_preview_file(file) then start_preview(settings, file); return true end
  end
  return false
end

local function draw_folder_row(app, settings, entry, index, width)
  local ctx = app.ctx
  local row_h = 48
  r.ImGui_PushID(ctx, "media_folder_" .. tostring(index))
  local clicked = r.ImGui_InvisibleButton(ctx, "##row", width, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double_clicked = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local selected = state.selected_index == index and not state.selected_file
  local bg = selected and 0x7AA2F730 or (hovered and 0xFFFFFF12 or 0x00000000)
  if bg ~= 0x00000000 then r.ImGui_DrawList_AddRectFilled(draw_list, x, y + 2, x + width, y + row_h - 2, bg, 5) end
  r.ImGui_DrawList_AddRect(draw_list, x, y + 2, x + width, y + row_h - 2, selected and Theme.colors.accent or Theme.colors.border, 5, 0, selected and 1.4 or 0.7)
  local icon_color = entry.kind == "folder_up" and Theme.colors.text_dim or Theme.colors.accent
  local text_x = x + 32
  local folder_art = nil
  if entry.kind == "folder" then folder_art = load_folder_art(ctx, normalize_path(selected_location(settings) .. "/" .. tostring(entry.path or ""))) end
  if entry.kind == "folder_up" and (state.folder_path or "") ~= "" then folder_art = load_folder_art(ctx, normalize_path(selected_location(settings) .. "/" .. tostring(state.folder_path or ""))) end
  local drew_art = false
  if folder_art and folder_art.image and r.ImGui_DrawList_AddImage then
    local box_x, box_y, box_size = x + 7, y + 8, 32
    r.ImGui_DrawList_AddRectFilled(draw_list, box_x, box_y, box_x + box_size, box_y + box_size, Theme.colors.frame_bg, 4)
    local image_ok = pcall(r.ImGui_DrawList_AddImage, draw_list, folder_art.image, box_x + 2, box_y + 2, box_x + box_size - 2, box_y + box_size - 2, 0, 0, 1, 1, 0xFFFFFFFF)
    if image_ok then
      r.ImGui_DrawList_AddRect(draw_list, box_x, box_y, box_x + box_size, box_y + box_size, Theme.colors.border, 4, 0, 1)
      text_x = x + 48
      drew_art = true
    elseif folder_art.path then
      destroy_folder_art(ctx, folder_art.path)
    end
  end
  if not drew_art then
    r.ImGui_DrawList_AddRectFilled(draw_list, x + 7, y + 16, x + 25, y + 29, icon_color, 3)
    r.ImGui_DrawList_AddRectFilled(draw_list, x + 10, y + 12, x + 20, y + 18, icon_color, 2)
  end
  r.ImGui_DrawList_PushClipRect(draw_list, text_x, y + 4, x + width - 8, y + row_h - 4, true)
  r.ImGui_DrawList_AddText(draw_list, text_x, y + 7, Theme.colors.text, entry.kind == "folder_up" and ".." or entry.name)
  local detail = entry.kind == "folder_up" and "Parent folder" or (tostring(entry.file_count or 0) .. " media")
  r.ImGui_DrawList_AddText(draw_list, text_x, y + 27, Theme.colors.text_dim, detail)
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked or double_clicked then
    if settings.folder_double_click_open == true then
      state.selected_index = index
      state.selected_file = nil
      state.file_list_keyboard_focus = true
      if double_clicked then open_folder_entry(app, entry) end
    else
      open_folder_entry(app, entry)
    end
  end
  if hovered then r.ImGui_SetTooltip(ctx, entry.kind == "folder_up" and "Go up" or entry.path) end
  if selected and state.scroll_selected_file and r.ImGui_SetScrollHereY then
    local ok = pcall(r.ImGui_SetScrollHereY, ctx, 0.5)
    if ok then state.scroll_selected_file = false end
  end
  r.ImGui_PopID(ctx)
end

local function draw_file_row(app, file, index, width)
  local ctx = app.ctx
  local row_h = 48
  r.ImGui_PushID(ctx, "media_file_" .. tostring(index))
  local clicked = r.ImGui_InvisibleButton(ctx, "##row", width, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local selected = state.selected_file and state.selected_file.path == file.path
  local previewing = state.preview_path == file.path
  local bg = selected and 0x7AA2F730 or (previewing and 0x48CFAD24 or (hovered and 0xFFFFFF12 or 0x00000000))
  if bg ~= 0x00000000 then r.ImGui_DrawList_AddRectFilled(draw_list, x, y + 2, x + width, y + row_h - 2, bg, 5) end
  r.ImGui_DrawList_AddRect(draw_list, x, y + 2, x + width, y + row_h - 2, (selected or previewing) and Theme.colors.accent or Theme.colors.border, 5, 0, (selected or previewing) and 1.4 or 0.7)
  local kind_color = file.kind == "audio" and 0x48CFADFF or file.kind == "midi" and 0xFFCE54FF or file.kind == "video" and 0xED5565FF or 0x8F9AA8FF
  r.ImGui_DrawList_AddRectFilled(draw_list, x + 7, y + 10, x + 23, y + 26, kind_color, 3)
  r.ImGui_DrawList_AddText(draw_list, x + 12, y + 11, 0x111111FF, file.kind:sub(1, 1):upper())
  r.ImGui_DrawList_PushClipRect(draw_list, x + 30, y + 4, x + width - 8, y + row_h - 4, true)
  r.ImGui_DrawList_AddText(draw_list, x + 30, y + 7, Theme.colors.text, file.name)
  local tags = compact_tags(file)
  if tags ~= "" then r.ImGui_DrawList_AddText(draw_list, x + 30, y + 27, Theme.colors.text_dim, tags) end
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked then
    local insert_on_click = shift_down(ctx)
    if insert_on_click then
      insert_file(app, file)
    elseif not state.selected_file or state.selected_file.path ~= file.path then
      select_file(app, file, index, true)
    else
      select_file(app, file, index, false)
      local settings = ensure_settings(app)
      if can_preview_file(file) and (settings.auto_play or state.preview_path == file.path) then start_preview(settings, file) end
    end
  end
  register_drag_source(ctx, file, hovered)
  if r.ImGui_BeginDragDropSource and r.ImGui_SetDragDropPayload and r.ImGui_BeginDragDropSource(ctx, 0) then
    r.ImGui_SetDragDropPayload(ctx, "TK_WORKBENCH_MEDIA_FILE", file.path)
    r.ImGui_Text(ctx, file.name)
    r.ImGui_EndDragDropSource(ctx)
  end
  if r.ImGui_BeginPopupContextItem(ctx, "##media_context") then
    if r.ImGui_MenuItem(ctx, "Insert on selected track") then insert_file(app, file) end
    if can_preview_file(file) and r.ImGui_MenuItem(ctx, "Preview") then start_preview(ensure_settings(app), file) end
    Sampler.draw_context_menu(ctx, app, file)
    r.ImGui_EndPopup(ctx)
  end
  if hovered then r.ImGui_SetTooltip(ctx, file.path) end
  if selected and state.scroll_selected_file and r.ImGui_SetScrollHereY then
    local ok = pcall(r.ImGui_SetScrollHereY, ctx, 0.5)
    if ok then state.scroll_selected_file = false end
  end
  r.ImGui_PopID(ctx)
end

local function draw_file_list(app, settings, width, height)
  local ctx = app.ctx
  local shown = 0
  local child_flags = 0
  if r.ImGui_WindowFlags_NoNavInputs then
    local ok_flags, flags = pcall(r.ImGui_WindowFlags_NoNavInputs)
    if ok_flags and flags then child_flags = flags end
  end
  if r.ImGui_BeginChild(ctx, "##media_files", 0, height, 0, child_flags) then
    if state.scanning then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Scanning... " .. tostring(#state.files) .. " files")
    elseif #state.filtered == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, selected_location(settings) == "" and "Add a media location" or "No media found")
    end
    local row_h = 48
    handle_file_list_keyboard(app, settings, row_h)
    local first, last, top_pad, bottom_pad = visible_range(ctx, #state.filtered, row_h, 8)
    shown = math.max(0, last - first + 1)
    if top_pad > 0 then r.ImGui_Dummy(ctx, 1, top_pad) end
    for index = first, last do
      local entry = state.filtered[index]
      if entry then
        if entry.kind == "folder" or entry.kind == "folder_up" then
          draw_folder_row(app, settings, entry, index, math.max(80, width - 12))
        else
          draw_file_row(app, entry, index, math.max(80, width - 12))
        end
      end
    end
    if bottom_pad > 0 then r.ImGui_Dummy(ctx, 1, bottom_pad) end
    r.ImGui_EndChild(ctx)
  end
  return shown
end

function M.init(app)
  local settings = ensure_settings(app)
  refresh_locations(settings)
end

function M.update(app)
  local settings = ensure_settings(app)
  local active = app.settings and app.settings.active_module == M.id
  cleanup_retired_preview_sources(false)
  update_pending_preview(settings)
  if state.activated and (active or state.scanning) then
    if is_project_files_location(selected_location(settings)) and state.loaded_location == PROJECT_FILES_LOCATION and state.project_files_signature ~= project_files_signature() then load_or_scan_location(settings, true) end
    scan_step(settings)
    if active then refresh_filter(settings) end
  end
  if preview_is_active() or settings.link_transport then
    update_preview_fades(settings)
    monitor_transport_link(settings)
    update_auto_play(app, settings)
    monitor_audio_selection(settings)
  end
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  state.activated = true
  load_or_scan_location(settings, false)
  update_drag(app)
  refresh_filter(settings)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  draw_toolbar(app, settings, avail_w or 320)
  draw_filter_buttons(ctx, settings, app, avail_w or 320)
  r.ImGui_Separator(ctx)
  local _, remaining_h = r.ImGui_GetContentRegionAvail(ctx)
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local status_h = app.settings.show_status and UI.info_line_height(ctx) or 0
  local available_h = math.max(120, remaining_h or 360) - status_h
  local controls_h = button_h * 2 + 18
  local wave_h = math.min(settings.waveform_height, math.max(64, available_h * 0.30))
  local list_h = math.max(56, available_h - wave_h - controls_h - 12)
  if list_h <= 60 then
    wave_h = math.max(48, available_h - controls_h - 72)
    list_h = math.max(56, available_h - wave_h - controls_h - 12)
  end
  local shown = draw_file_list(app, settings, avail_w or 320, list_h)
  r.ImGui_Spacing(ctx)
  draw_waveform(ctx, state.selected_file, math.max(80, (avail_w or 320) - 2), wave_h)
  local can_preview = can_preview_file(state.selected_file)
  local preview_active = preview_is_active()
  local transport_size = math.min(20, math.max(18, button_h))
  local prev_clicked, prev_hovered = draw_transport_button(ctx, "##media_prev", "prev", false, (state.selected_index or 1) > 1, transport_size)
  if prev_hovered then r.ImGui_SetTooltip(ctx, "Previous file") end
  if prev_clicked then previous_preview_file(app, settings) end
  r.ImGui_SameLine(ctx)
  local play_clicked, play_hovered = draw_transport_button(ctx, "##media_play_stop", preview_active and "stop" or "play", preview_active, preview_active or can_preview, transport_size)
  if play_hovered then r.ImGui_SetTooltip(ctx, preview_active and "Stop" or "Play") end
  if play_clicked then
    if preview_active then destroy_preview(settings) else start_preview(settings, state.selected_file) end
  end
  r.ImGui_SameLine(ctx)
  local pause_clicked, pause_hovered = draw_transport_button(ctx, "##media_pause", "pause", state.preview_paused, preview_active, transport_size)
  if pause_hovered then r.ImGui_SetTooltip(ctx, state.preview_paused and "Resume" or "Pause") end
  if pause_clicked then pause_preview(settings) end
  r.ImGui_SameLine(ctx)
  local next_clicked, next_hovered = draw_transport_button(ctx, "##media_next", "next", false, #state.filtered > 0, transport_size)
  if next_hovered then r.ImGui_SetTooltip(ctx, "Next file") end
  if next_clicked then advance_preview_file(app, settings) end
  r.ImGui_SameLine(ctx)
  local random_clicked, random_hovered = draw_transport_button(ctx, "##media_random", "random", settings.random_play_next == true, true, transport_size)
  if random_hovered then r.ImGui_SetTooltip(ctx, "Random auto play next") end
  if random_clicked then
    settings.random_play_next = not (settings.random_play_next == true)
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx)
  local min_label = (tonumber(settings.min_display_time) or 0) > 0 and "1s" or "off"
  local min_clicked, min_hovered = draw_text_transport_button(ctx, "##media_min_display", min_label, (tonumber(settings.min_display_time) or 0) > 0, 34, transport_size)
  if min_hovered then r.ImGui_SetTooltip(ctx, "Minimum display time") end
  if min_clicked then
    settings.min_display_time = (tonumber(settings.min_display_time) or 0) > 0 and 0 or 1.0
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx)
  local link_w = 30
  local link_clicked, link_hovered = draw_text_transport_button(ctx, "##media_link", "link", settings.link_transport == true, link_w, transport_size)
  if link_clicked then
    settings.link_transport = not settings.link_transport
    if app.save_settings then app.save_settings() end
  end
  if link_hovered then r.ImGui_SetTooltip(ctx, "Link transport | Right-click options") end
  if r.ImGui_BeginPopupContextItem(ctx, "##media_link_options") then
    local changed_link, start_from_cursor = r.ImGui_Checkbox(ctx, "Start arrange from edit cursor", settings.link_start_from_editcursor == true)
    if changed_link then settings.link_start_from_editcursor = start_from_cursor; if app.save_settings then app.save_settings() end end
    r.ImGui_EndPopup(ctx)
  end
  local slider_w = math.max(62, ((avail_w or 320) - 16) / 3)
  local slider_colors = push_slider_theme(ctx)
  r.ImGui_PushItemWidth(ctx, slider_w)
  local volume_db = volume_to_db(settings.preview_volume)
  local changed, new_volume_db = r.ImGui_SliderDouble(ctx, "##media_volume", volume_db, -60, 12, "")
  local wheel = hovered_mouse_wheel(ctx, true)
  if wheel ~= 0 then new_volume_db = clamp(new_volume_db + wheel * 0.1, -60, 12); changed = true end
  draw_slider_value(ctx, string.format("%.1f dB", new_volume_db))
  local reset_volume = r.ImGui_IsItemHovered(ctx) and right_clicked(ctx)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Volume | Wheel fine tune | Right-click reset") end
  if changed or reset_volume then
    settings.preview_volume = reset_volume and defaults.preview_volume or db_to_volume(new_volume_db)
    if state.preview and r.CF_Preview_SetValue then r.CF_Preview_SetValue(state.preview, "D_VOLUME", settings.preview_volume) end
    if state.preview_track_playback and validate_track(state.preview_track) then r.SetMediaTrackInfo_Value(state.preview_track, "D_VOL", settings.preview_volume) end
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_PushItemWidth(ctx, slider_w)
  local new_pitch = settings.preview_pitch
  changed, new_pitch = r.ImGui_SliderDouble(ctx, "##media_pitch", new_pitch, -24, 24, "")
  wheel = hovered_mouse_wheel(ctx, true)
  if wheel ~= 0 then new_pitch = clamp(new_pitch + wheel * 0.1, -24, 24); changed = true end
  draw_slider_value(ctx, string.format("%.1f st", new_pitch))
  local reset_pitch = r.ImGui_IsItemHovered(ctx) and right_clicked(ctx)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Pitch | Wheel fine tune | Right-click reset") end
  if reset_pitch then settings.preview_pitch = defaults.preview_pitch elseif changed then settings.preview_pitch = new_pitch end
  if changed or reset_pitch then
    local rate = effective_playrate(state.preview_source, state.preview_kind, settings)
    if state.preview and r.CF_Preview_SetValue then r.CF_Preview_SetValue(state.preview, "D_PITCH", effective_preview_pitch(settings, rate)) end
    if state.preview_track_playback and take_pointer_valid(state.preview_take) and r.SetMediaItemTakeInfo_Value then
      r.SetMediaItemTakeInfo_Value(state.preview_take, "D_PITCH", effective_preview_pitch(settings, rate))
      if state.preview_item then r.UpdateItemInProject(state.preview_item) end
    end
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_PushItemWidth(ctx, slider_w)
  local rate_locked = settings.tempo_sync == true
  local shown_rate = display_playrate(settings)
  if rate_locked and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  changed, shown_rate = r.ImGui_SliderDouble(ctx, "##media_rate", shown_rate, 0.25, 4, "")
  if rate_locked and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  wheel = hovered_mouse_wheel(ctx, not rate_locked)
  if wheel ~= 0 then shown_rate = clamp(shown_rate + wheel * 0.01, 0.25, 4); changed = true end
  draw_slider_value(ctx, string.format("%.2fx", shown_rate))
  local reset_rate = r.ImGui_IsItemHovered(ctx) and right_clicked(ctx)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, rate_locked and "Rate synced to project tempo" or "Rate | Wheel fine tune | Right-click reset") end
  if reset_rate then settings.preview_rate = defaults.preview_rate end
  if (changed and not rate_locked) or reset_rate then
    if changed and not rate_locked then settings.preview_rate = shown_rate end
    apply_preview_rate(settings)
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_PopItemWidth(ctx)
  pop_slider_theme(ctx, slider_colors)
  local source = location_label(selected_location(settings))
  if folder_browse_active(settings) and (state.folder_path or "") ~= "" then source = source .. "/" .. state.folder_path end
  local filtered_count = state.filtered_file_count or #state.filtered
  local info = source .. " | " .. tostring(filtered_count) .. " / " .. tostring(#state.files) .. " media"
  if shown and shown < #state.filtered then info = info .. " | showing " .. tostring(shown) end
  if state.scanning then info = info .. " | scanning" elseif state.scan_limited then info = info .. " | scan limit" elseif state.cache_status == "cached" then info = info .. " | cached" end
  if state.selected_file then info = info .. " | " .. state.selected_file.name end
  if state.last_error then info = state.last_error end
  app.status = info
end

function M.shutdown(app)
  destroy_preview(ensure_settings(app), nil, true)
  cleanup_retired_preview_sources(true)
  clear_drag()
  clear_waveform_pending()
  clear_image_cache(app.ctx)
  clear_folder_art_cache(app.ctx)
  state.waveform_cache = {}
end

return M