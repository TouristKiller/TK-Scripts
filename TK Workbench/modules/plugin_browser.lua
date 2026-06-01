local r = reaper
local json = require("core.json")
local UI = require("core.ui")
local Theme = require("core.theme")

local M = {
  id = "plugin_browser",
  title = "Plugin Browser",
  icon = "PLG",
  version = "0.1.1"
}

local fx_root = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/"
local workbench_root = r.GetResourcePath() .. "/Scripts/TK Scripts/TK Workbench/"
local parser_path = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
local shared_favorites_path = fx_root .. "favorite_plugins.txt"
local local_favorites_path = workbench_root .. "plugin_browser_favorites.txt"
local shared_ratings_path = fx_root .. "plugin_ratings.json"
local shared_pinned_path = fx_root .. "pinned_plugins.txt"
local custom_folders_path = fx_root .. "custom_folders.json"

local defaults = {
  search_term = "",
  source = "All",
  view_mode = "tiles",
  show_screenshots = true,
  screenshot_size = 82,
  target_mode = "selected_track",
  recent_max = 30,
  sort_mode = "name",
  show_pinned_on_top = true,
  show_favorites_on_top = false,
  show_x86 = true,
  enable_drag_add_fx = true,
  open_floating_after_drag_add = false,
  double_click_insert = false,
  use_type_priority = true,
  dropdown_rows = 18,
  return_to_rack_after_add = true,
  return_to_chain_builder_after_add = true,
  type_priority = { "CLAP", "VST3", "VST", "JS", "AU", "LV2", "OTHER" },
  type_filter = { VST3 = true, VST = true, CLAP = true, JS = true, AU = true, LV2 = true, OTHER = true },
  group_selection = { all = "", developer = "", category = "", folders = "", custom_folders = "" }
}

local sources = { "All", "Favorites", "Recent", "Instruments", "All Plugins", "Developer", "Category", "Folders", "Custom Folders" }
local plugin_types = { "VST3", "VST", "CLAP", "JS", "AU", "LV2", "OTHER" }
local max_screenshot_cache = 100
local min_screenshot_cache = 25
local max_screenshot_loads_per_frame = 12
local min_screenshot_load_interval = 0
local min_screenshot_lifetime = 2.0
local screenshot_signature_check_interval = 5.0
local screenshot_normalization_version = 4
local row_height = 40
local uniform_ratio = 0.625

local state = {
  plugins = {},
  plugin_by_name = {},
  filtered = {},
  aliases = {},
  favorites = {},
  favorite_set = {},
  favorite_path = local_favorites_path,
  favorite_source = "local",
  ratings = {},
  rating_norm = {},
  rating_source = "none",
  rating_path = shared_ratings_path,
  rating_count = 0,
  pinned = {},
  pinned_set = {},
  pinned_norm_set = {},
  pinned_extra_lines = {},
  pinned_source = "none",
  pinned_path = shared_pinned_path,
  recent = {},
  recent_index = {},
  screenshot_path = fx_root .. "Screenshots/",
  screenshot_index = nil,
  screenshot_cache = {},
  screenshot_cache_order = {},
  screenshot_load_queue = {},
  screenshot_load_order = {},
  screenshot_load_queued = {},
  screenshot_visible_keys = {},
  screenshot_next_load_time = 0,
  screenshot_missing = {},
  screenshot_signature = nil,
  screenshot_signature_checked_at = 0,
  screenshot_normalization_version = nil,
  screenshot_count = 0,
  screenshot_image_errors = 0,
  screenshot_capture_active = false,
  screenshot_capture_plugin = nil,
  parser_loaded = false,
  parser_categories = {},
  parser_developers = {},
  groups = { all = {}, developer = {}, category = {}, folders = {}, custom_folders = {} },
  parser_group_counts = { all = 0, developer = 0, category = 0, folders = 0 },
  custom_folder_source = "none",
  custom_folder_count = 0,
  custom_folder_plugin_count = 0,
  load_error = nil,
  source = "Not loaded",
  last_filter_key = nil,
  fuzzy_cache = {},
  selected_plugins = {},
  selection_anchor_index = nil,
  potential_drag_plugin = nil,
  potential_drag_plugins = nil,
  potential_drag_x = 0,
  potential_drag_y = 0,
  dragging_plugin = nil,
  dragging_plugins = nil,
  drag_target_track = nil,
  drag_target_item = nil,
  drag_target_mode = "track",
  drag_threshold = 4
}

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local target = {}
  for key, child in pairs(value) do target[key] = copy_default(child) end
  return target
end

local function ensure_settings(app)
  app.settings.plugin_browser = app.settings.plugin_browser or {}
  local settings = app.settings.plugin_browser
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  if type(settings.group_selection) ~= "table" then
    settings.group_selection = { all = "", developer = "", category = "", folders = "", custom_folders = "" }
    changed = true
  else
    for key, value in pairs(defaults.group_selection) do
      if settings.group_selection[key] == nil then
        settings.group_selection[key] = value
        changed = true
      end
    end
  end
  if type(settings.type_filter) ~= "table" then
    settings.type_filter = { VST3 = true, VST = true, CLAP = true, JS = true, AU = true, LV2 = true, OTHER = true }
    changed = true
  else
    for key, value in pairs(defaults.type_filter) do
      if settings.type_filter[key] == nil then
        settings.type_filter[key] = value
        changed = true
      end
    end
  end
  if type(settings.type_priority) ~= "table" then
    settings.type_priority = copy_default(defaults.type_priority)
    changed = true
  else
    local allowed = {}
    for _, plugin_type_name in ipairs(defaults.type_priority) do allowed[plugin_type_name] = true end
    local seen = {}
    local normalized = {}
    for _, plugin_type_name in ipairs(settings.type_priority) do
      if allowed[plugin_type_name] and not seen[plugin_type_name] then
        normalized[#normalized + 1] = plugin_type_name
        seen[plugin_type_name] = true
      end
    end
    for _, plugin_type_name in ipairs(defaults.type_priority) do
      if not seen[plugin_type_name] then
        normalized[#normalized + 1] = plugin_type_name
        changed = true
      end
    end
    if #normalized ~= #settings.type_priority then changed = true end
    settings.type_priority = normalized
  end
  local dropdown_rows = math.floor(tonumber(settings.dropdown_rows) or defaults.dropdown_rows)
  if dropdown_rows < 8 then dropdown_rows = 8 end
  if dropdown_rows > 36 then dropdown_rows = 36 end
  if settings.dropdown_rows ~= dropdown_rows then
    settings.dropdown_rows = dropdown_rows
    changed = true
  end
  if settings.return_to_rack_after_add_initialized ~= true then
    settings.return_to_rack_after_add = true
    settings.return_to_rack_after_add_initialized = true
    changed = true
  end
  if settings.return_to_chain_builder_after_add_initialized ~= true then
    settings.return_to_chain_builder_after_add = true
    settings.return_to_chain_builder_after_add_initialized = true
    changed = true
  end
  if settings.double_click_instruments_as_virtual_track ~= nil then
    settings.double_click_instruments_as_virtual_track = nil
    changed = true
  end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function file_exists(path)
  if r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function read_text(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
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

local function write_lines(path, lines)
  local file = io.open(path, "w")
  if not file then return false end
  for _, line in ipairs(lines) do file:write(line .. "\n") end
  file:close()
  return true
end

local function read_json(path)
  local content = read_text(path)
  if not content or content == "" then return {} end
  local ok, decoded = pcall(json.decode, content)
  if ok and type(decoded) == "table" then return decoded end
  return {}
end

local function write_json(path, value)
  local ok, encoded = pcall(json.encode, value)
  if not ok or not encoded then return false end
  local file = io.open(path, "w")
  if not file then return false end
  file:write(encoded)
  file:close()
  return true
end

local function strip_x86(value)
  local name = tostring(value or "")
  name = name:gsub("%s*[%(%[][xX]86[^%]%)]*[%]%)]", "")
  name = name:gsub("%s*[%(%[][xX]64[^%]%)]*[%]%)]", "")
  name = name:gsub("^[_%s%-:]*[xX]86[_%s%-]*[Bb]ridged[_%s%-:]*", "")
  name = name:gsub("[_%s%-:]+[xX]86[_%s%-]*[Bb]ridged[_%s%-:]*", " ")
  name = name:gsub("^[_%s%-:]*[xX]64[_%s%-]*[Bb]ridged[_%s%-:]*", "")
  name = name:gsub("[_%s%-:]+[xX]64[_%s%-]*[Bb]ridged[_%s%-:]*", " ")
  name = name:gsub("[_%s%-]+[xX]86[_%s%-]*$", "")
  name = name:gsub("^[_%s%-]*[xX]86[_%s%-]+", "")
  name = name:gsub("[_%s%-]+[xX]86[_%s%-]+", " ")
  name = name:gsub("[_%s%-]+[xX]64[_%s%-]*$", "")
  name = name:gsub("^[_%s%-]*[xX]64[_%s%-]+", "")
  name = name:gsub("[_%s%-]+[xX]64[_%s%-]+", " ")
  name = name:gsub("^[xX]86%s*:%s*", "")
  name = name:gsub("^[xX]64%s*:%s*", "")
  return name
end

local function plugin_arch(value)
  local name = tostring(value or "")
  if name:find("[%(%[][xX]86") or name:find("[xX]86[_%s%-]*[Bb]ridged") or name:find("[_%s%-][xX]86[_%s%-]") or name:find("^[xX]86%s*:") then return "x86" end
  if name:find("[%(%[][xX]64") or name:find("[xX]64[_%s%-]*[Bb]ridged") or name:find("[_%s%-][xX]64[_%s%-]") or name:find("^[xX]64%s*:") then return "x64" end
  return ""
end

local function clean_plugin_name(value)
  local name = strip_x86(value)
  name = name:gsub("^[%w%d]+i?:%s*", "")
  name = name:gsub("%s+$", "")
  return name ~= "" and name or tostring(value or "")
end

local function strip_trailing_plugin_tag(value)
  local name = tostring(value or "")
  name = name:gsub("%s*%([^()]+%)%s*$", "")
  name = name:gsub("%s*%[[^%[%]]+%]%s*$", "")
  name = name:gsub("%s*%{[^{}]+%}%s*$", "")
  name = name:gsub("[_%s]+_[^_]+_%s*$", "")
  return name
end

local function strip_channel_tag(value)
  local name = tostring(value or "")
  name = name:gsub("%s*%([Mm]ono%)", "")
  name = name:gsub("%s*%([Ss]tereo%)", "")
  name = name:gsub("[_%s]+_[Mm]ono_", " ")
  name = name:gsub("[_%s]+_[Ss]tereo_", " ")
  return name
end

local function strip_redundant_leading_tag(value)
  local name = tostring(value or "")
  local prefix, body = name:match("^([Vv][Ss][Tt]3[Ii]?[%s_:%-]+)(.*)$")
  if not prefix then prefix, body = name:match("^([Vv][Ss][Tt][Ii]?[%s_:%-]+)(.*)$") end
  if not prefix then prefix, body = name:match("^([Jj][Ss][Ff][Xx][%s_:%-]+)(.*)$") end
  if not prefix then prefix, body = name:match("^([Jj][Ss][%s_:%-]+)(.*)$") end
  if not prefix then prefix, body = name:match("^([Cc][Ll][Aa][Pp][Ii]?[%s_:%-]+)(.*)$") end
  if not prefix then prefix, body = name:match("^([Aa][Uu][Ii]?[%s_:%-]+)(.*)$") end
  if not prefix then prefix, body = name:match("^([Ll][Vv]2[Ii]?[%s_:%-]+)(.*)$") end
  prefix = prefix or ""
  body = body or name
  local content, tag = body:match("^(.-)%s*%(([^()]+)%)%s*$")
  if not content then content, tag = body:match("^(.-)%s*%[([^%[%]]+)%]%s*$") end
  if not content then content, tag = body:match("^(.-)%s*%{([^{}]+)%}%s*$") end
  if not content then content, tag = body:match("^(.-)[_%s]+_([^_]+)_%s*$") end
  if content and tag then
    local tag_pattern = tag:gsub("([^%w])", "%%%1")
    local stripped = content:gsub("^%s*" .. tag_pattern .. "%s+", "")
    if stripped ~= content then return prefix .. stripped .. " (" .. tag .. ")" end
  end
  return name
end

local function normalize_plugin_name(value)
  local name = strip_x86(value):lower()
  name = name:gsub("^vst3i[%s_:%-]*", "")
  name = name:gsub("^vst3[%s_:%-]*", "")
  name = name:gsub("^vsti[%s_:%-]*", "")
  name = name:gsub("^vst[%s_:%-]*", "")
  name = name:gsub("^jsfx[%s_:%-]*", "")
  name = name:gsub("^js[%s_:%-]*", "")
  name = name:gsub("^clapi[%s_:%-]*", "")
  name = name:gsub("^clap[%s_:%-]*", "")
  name = name:gsub("^aui[%s_:%-]*", "")
  name = name:gsub("^au[%s_:%-]*", "")
  name = name:gsub("^lv2i[%s_:%-]*", "")
  name = name:gsub("^lv2[%s_:%-]*", "")
  name = strip_redundant_leading_tag(name)
  name = name:gsub("^[^%w]+", "")
  name = name:gsub("%s+$", "")
  name = name:gsub("%s+", " ")
  return name:gsub("[^%w]+", "")
end

local function plugin_type(value)
  local name = tostring(value or "")
  if name:match("^VST3i?:") then return "VST3" end
  if name:match("^VSTi?:") then return "VST" end
  if name:match("^CLAPi?:") then return "CLAP" end
  if name:match("^JSFX:") or name:match("^JS:") then return "JS" end
  if name:match("^AUi?:") then return "AU" end
  if name:match("^LV2i?:") then return "LV2" end
  return "OTHER"
end

local function is_instrument(value)
  local name = tostring(value or "")
  return name:match("^VSTi:") or name:match("^VST3i:") or name:match("^CLAPi:") or name:match("^AUi:") or name:match("^LV2i:") or false
end

local function instrument_track_name(plugin)
  local name = plugin and (plugin.display_name or plugin.clean_name or clean_plugin_name(plugin.name)) or ""
  name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" and plugin then name = clean_plugin_name(plugin.name) end
  return name ~= "" and name or "Instrument"
end

local function virtual_track_midi_input_value(midi_input_value)
  local value = tonumber(midi_input_value) or 6112
  if value == 6112 then return 6112 end
  local device_index = value - 6113
  if device_index < 0 then return 6112 end
  return (device_index * 32) + 4096
end

local function fuzzy_normalize(value)
  if not value then return "" end
  local cached = state.fuzzy_cache[value]
  if cached then return cached end
  local normalized = value:lower():gsub("[%-_%.%s]+", "")
  state.fuzzy_cache[value] = normalized
  return normalized
end

local function fuzzy_find(haystack, needle)
  if not needle or needle == "" then return true end
  if not haystack then return false end
  local needle_lower = needle:lower()
  local haystack_lower = haystack:lower()
  if haystack_lower:find(needle_lower, 1, true) then return true end
  if needle_lower:find("%s") then
    local haystack_norm = fuzzy_normalize(haystack)
    for token in needle_lower:gmatch("%S+") do
      local token_norm = token:gsub("[%-_%.]+", "")
      if token_norm ~= "" and not haystack_lower:find(token, 1, true) and not haystack_norm:find(token_norm, 1, true) then return false end
    end
    return true
  end
  if needle_lower:find("[%-_%.]") then
    local haystack_norm = fuzzy_normalize(haystack)
    local needle_norm = needle_lower:gsub("[%-_%.%s]+", "")
    return needle_norm ~= "" and haystack_norm:find(needle_norm, 1, true) ~= nil
  end
  return false
end

local function resolve_favorites_path()
  if file_exists(shared_favorites_path) then return shared_favorites_path, "shared" end
  return local_favorites_path, "local"
end

local function rebuild_rating_index()
  state.rating_norm = {}
  state.rating_count = 0
  for name, rating in pairs(state.ratings or {}) do
    local value = tonumber(rating) or 0
    if value > 0 then
      state.rating_count = state.rating_count + 1
      local key = normalize_plugin_name(name)
      if key ~= "" and not state.rating_norm[key] then state.rating_norm[key] = value end
    end
  end
end

local function rebuild_pinned_sets()
  state.pinned_set = {}
  state.pinned_norm_set = {}
  for _, name in ipairs(state.pinned or {}) do
    if type(name) == "string" and name ~= "" then
      state.pinned_set[name] = true
      local key = normalize_plugin_name(name)
      if key ~= "" then state.pinned_norm_set[key] = true end
    end
  end
end

local function load_shared_ratings()
  state.ratings = {}
  state.rating_source = "none"
  if file_exists(shared_ratings_path) then
    state.ratings = read_json(shared_ratings_path)
    state.rating_source = "shared"
  end
  rebuild_rating_index()
end

local function load_shared_pinned()
  state.pinned = {}
  state.pinned_extra_lines = {}
  state.pinned_source = "none"
  if file_exists(shared_pinned_path) then
    local lines = read_lines(shared_pinned_path)
    for _, line in ipairs(lines) do
      local plugin_name = line:match("^PLUGIN:(.+)$")
      if plugin_name and plugin_name ~= "" then
        state.pinned[#state.pinned + 1] = plugin_name
      elseif line ~= "" then
        state.pinned_extra_lines[#state.pinned_extra_lines + 1] = line
      end
    end
    state.pinned_source = "shared"
  end
  rebuild_pinned_sets()
end

local function load_user_data()
  state.aliases = read_json(fx_root .. "plugin_aliases.json")
  state.favorite_path, state.favorite_source = resolve_favorites_path()
  state.favorites = read_lines(state.favorite_path)
  load_shared_ratings()
  load_shared_pinned()
  state.recent = read_lines(fx_root .. "recent_plugins.txt")
  state.favorite_set = {}
  state.recent_index = {}
  for _, name in ipairs(state.favorites) do state.favorite_set[name] = true end
  for index, name in ipairs(state.recent) do
    if not state.recent_index[name] then state.recent_index[name] = index end
  end
end

local function save_favorites()
  if not state.favorite_path or state.favorite_path == "" then state.favorite_path, state.favorite_source = resolve_favorites_path() end
  write_lines(state.favorite_path, state.favorites)
end

local function save_recent(settings)
  local cap = tonumber(settings.recent_max) or 30
  while #state.recent > cap do table.remove(state.recent) end
  write_lines(fx_root .. "recent_plugins.txt", state.recent)
end

local function save_ratings()
  if state.rating_source ~= "shared" then return false end
  return write_json(state.rating_path or shared_ratings_path, state.ratings)
end

local function save_pinned()
  if state.pinned_source ~= "shared" then return false end
  local lines = {}
  for _, name in ipairs(state.pinned or {}) do lines[#lines + 1] = "PLUGIN:" .. name end
  for _, line in ipairs(state.pinned_extra_lines or {}) do lines[#lines + 1] = line end
  return write_lines(state.pinned_path or shared_pinned_path, lines)
end

local function plugin_rating(plugin)
  if state.rating_source ~= "shared" or not plugin then return 0 end
  local exact = tonumber(state.ratings[plugin.name]) or 0
  if exact > 0 then return exact end
  return tonumber(state.rating_norm[plugin.dedupe_key or normalize_plugin_name(plugin.name)]) or 0
end

local function plugin_pinned(plugin)
  if state.pinned_source ~= "shared" or not plugin then return false end
  if state.pinned_set[plugin.name] then return true end
  local key = plugin.dedupe_key or normalize_plugin_name(plugin.name)
  return key ~= "" and state.pinned_norm_set[key] == true
end

local function set_plugin_rating(plugin, rating)
  if state.rating_source ~= "shared" or not plugin then return end
  local value = math.max(0, math.min(5, tonumber(rating) or 0))
  local key = plugin.dedupe_key or normalize_plugin_name(plugin.name)
  local remove = {}
  for name in pairs(state.ratings) do
    if name == plugin.name or (key ~= "" and normalize_plugin_name(name) == key) then remove[#remove + 1] = name end
  end
  for _, name in ipairs(remove) do state.ratings[name] = nil end
  if value > 0 then state.ratings[plugin.name] = value end
  rebuild_rating_index()
  save_ratings()
  plugin.rating = value
  state.last_filter_key = nil
end

local function pin_plugin(plugin)
  if state.pinned_source ~= "shared" or not plugin or plugin_pinned(plugin) then return end
  state.pinned[#state.pinned + 1] = plugin.name
  rebuild_pinned_sets()
  save_pinned()
  plugin.pinned = true
  state.last_filter_key = nil
end

local function unpin_plugin(plugin)
  if state.pinned_source ~= "shared" or not plugin then return end
  local key = plugin.dedupe_key or normalize_plugin_name(plugin.name)
  for index = #state.pinned, 1, -1 do
    local name = state.pinned[index]
    if name == plugin.name or (key ~= "" and normalize_plugin_name(name) == key) then table.remove(state.pinned, index) end
  end
  rebuild_pinned_sets()
  save_pinned()
  plugin.pinned = false
  state.last_filter_key = nil
end

local function add_recent(settings, plugin_name)
  for index = #state.recent, 1, -1 do
    if state.recent[index] == plugin_name then table.remove(state.recent, index) end
  end
  table.insert(state.recent, 1, plugin_name)
  state.recent_index = {}
  for index, name in ipairs(state.recent) do state.recent_index[name] = index end
  save_recent(settings)
end

local function add_favorite(plugin)
  if not state.favorite_set[plugin.name] then
    state.favorite_set[plugin.name] = true
    table.insert(state.favorites, plugin.name)
    save_favorites()
    plugin.favorite = true
    state.last_filter_key = nil
  end
end

local function remove_favorite(plugin)
  if not state.favorite_set[plugin.name] then return end
  state.favorite_set[plugin.name] = nil
  for index = #state.favorites, 1, -1 do
    if state.favorites[index] == plugin.name then table.remove(state.favorites, index) end
  end
  save_favorites()
  plugin.favorite = false
  state.last_filter_key = nil
end

local function build_screenshot_index(force)
  local now = r.time_precise()
  if state.screenshot_normalization_version ~= screenshot_normalization_version then
    force = true
    state.screenshot_normalization_version = screenshot_normalization_version
  end
  if state.screenshot_index and not force and now - (state.screenshot_signature_checked_at or 0) < screenshot_signature_check_interval then return end
  local signature_parts = {}
  local signature_index = 0
  while true do
    local file_name = r.EnumerateFiles(state.screenshot_path, signature_index)
    if not file_name then break end
    local lower_file = file_name:lower()
    if lower_file:match("%.png$") or lower_file:match("%.jpg$") or lower_file:match("%.jpeg$") then signature_parts[#signature_parts + 1] = file_name end
    signature_index = signature_index + 1
  end
  local signature = tostring(#signature_parts) .. "|" .. table.concat(signature_parts, "|")
  state.screenshot_signature_checked_at = now
  if state.screenshot_index and not force and signature == state.screenshot_signature then return end
  state.screenshot_signature = signature
  state.screenshot_index = {}
  state.screenshot_count = 0
  state.screenshot_missing = {}
  state.screenshot_image_errors = 0
  for _, file_name in ipairs(signature_parts) do
    local lower_file = file_name:lower()
    local base = lower_file:match("%.png$") and file_name:gsub("%.[Pp][Nn][Gg]$", "") or lower_file:match("%.jpg$") and file_name:gsub("%.[Jj][Pp][Gg]$", "") or lower_file:match("%.jpeg$") and file_name:gsub("%.[Jj][Pp][Ee][Gg]$", "")
    if base then
      local function index_key(value)
        local key = normalize_plugin_name(value)
        if key ~= "" and not state.screenshot_index[key] then state.screenshot_index[key] = file_name end
      end
      local key = normalize_plugin_name(base)
      if key ~= "" then
        if not state.screenshot_index[key] then state.screenshot_index[key] = file_name end
        state.screenshot_count = state.screenshot_count + 1
      end
      index_key(strip_trailing_plugin_tag(base))
      index_key(strip_channel_tag(base))
      index_key(strip_trailing_plugin_tag(strip_channel_tag(base)))
    end
  end
end

local function screenshot_keys(plugin)
  if type(plugin) == "table" then
    local signature = table.concat({ tostring(plugin.name or ""), tostring(plugin.clean_name or ""), tostring(plugin.display_name or ""), tostring(plugin.alias or "") }, "\31")
    if plugin.screenshot_keys_version == screenshot_normalization_version and plugin.screenshot_keys_signature == signature and type(plugin.screenshot_keys_cache) == "table" then return plugin.screenshot_keys_cache end
  end
  local result = {}
  local seen = {}
  local function add(value)
    local key = normalize_plugin_name(value)
    if key ~= "" and not seen[key] then
      seen[key] = true
      result[#result + 1] = key
    end
  end
  local function add_tagless(value)
    add(strip_trailing_plugin_tag(value))
  end
  local function add_channelless(value)
    local stripped = strip_channel_tag(value)
    add(stripped)
    add_tagless(stripped)
  end
  local function add_without_redundant_tag(value)
    local stripped = strip_redundant_leading_tag(value)
    add(stripped)
    add_tagless(stripped)
    add_channelless(stripped)
  end
  if type(plugin) == "table" then
    add(plugin.name)
    add_tagless(plugin.name)
    add_channelless(plugin.name)
    add_without_redundant_tag(plugin.name)
    add(plugin.clean_name)
    add_tagless(plugin.clean_name)
    add_channelless(plugin.clean_name)
    add_without_redundant_tag(plugin.clean_name)
    add(plugin.display_name)
    add_tagless(plugin.display_name)
    add_channelless(plugin.display_name)
    add_without_redundant_tag(plugin.display_name)
    add(plugin.alias)
    add_tagless(plugin.alias)
    add_channelless(plugin.alias)
    add_without_redundant_tag(plugin.alias)
  else
    add(plugin)
    add_tagless(plugin)
    add_channelless(plugin)
    add_without_redundant_tag(plugin)
  end
  if type(plugin) == "table" then
    plugin.screenshot_keys_version = screenshot_normalization_version
    plugin.screenshot_keys_signature = table.concat({ tostring(plugin.name or ""), tostring(plugin.clean_name or ""), tostring(plugin.display_name or ""), tostring(plugin.alias or "") }, "\31")
    plugin.screenshot_keys_cache = result
  end
  return result
end

local function remove_screenshot_order_key(key)
  for index = #state.screenshot_cache_order, 1, -1 do
    if state.screenshot_cache_order[index] == key then table.remove(state.screenshot_cache_order, index) end
  end
end

local function detach_screenshot_image(ctx, key)
  local entry = state.screenshot_cache[key]
  if not entry then return end
  if entry.image then
    if r.ImGui_Detach then pcall(r.ImGui_Detach, ctx, entry.image) end
  end
  state.screenshot_cache[key] = nil
  remove_screenshot_order_key(key)
end

local function touch_screenshot_image(key)
  remove_screenshot_order_key(key)
  state.screenshot_cache_order[#state.screenshot_cache_order + 1] = key
  local entry = state.screenshot_cache[key]
  if entry then entry.last_seen = r.time_precise() end
end

local function trim_screenshot_cache(ctx, max_count, force)
  while #state.screenshot_cache_order > max_count do
    local remove_index = nil
    local now = r.time_precise()
    for index, key in ipairs(state.screenshot_cache_order) do
      local entry = state.screenshot_cache[key]
      local old_enough = force or max_count == 0 or not entry or not entry.created_at or now - entry.created_at >= min_screenshot_lifetime
      if (force or not state.screenshot_visible_keys[key]) and old_enough then
        remove_index = index
        break
      end
    end
    if not remove_index then return false end
    local key = table.remove(state.screenshot_cache_order, remove_index)
    local entry = state.screenshot_cache[key]
    if entry and entry.image then
      if r.ImGui_Detach then pcall(r.ImGui_Detach, ctx, entry.image) end
    end
    state.screenshot_cache[key] = nil
  end
  return true
end

local function pop_next_screenshot_load()
  for index, key in ipairs(state.screenshot_load_order) do
    if state.screenshot_visible_keys[key] then
      table.remove(state.screenshot_load_order, index)
      return key
    end
  end
  return table.remove(state.screenshot_load_order, 1)
end

local function requeue_screenshot_load(key, queued)
  state.screenshot_load_queue[key] = queued
  if not state.screenshot_load_queued[key] then
    table.insert(state.screenshot_load_order, 1, key)
    state.screenshot_load_queued[key] = true
  end
end

local function get_screenshot_image(ctx, plugin)
  build_screenshot_index(false)
  local keys = screenshot_keys(plugin)
  local now = r.time_precise()
  for _, candidate in ipairs(keys) do
    if state.screenshot_cache[candidate] then
      touch_screenshot_image(candidate)
      state.screenshot_visible_keys[candidate] = true
      return state.screenshot_cache[candidate].image
    end
  end
  local key = keys[1] or ""
  local file_name
  for _, candidate in ipairs(keys) do
    local missing_at = state.screenshot_missing[candidate]
    if missing_at == true or (missing_at and now - missing_at >= 2.0) then
      state.screenshot_missing[candidate] = nil
      missing_at = nil
    end
    if not missing_at then
      file_name = state.screenshot_index and state.screenshot_index[candidate]
      if file_name then
        key = candidate
        break
      end
    end
  end
  if not file_name then state.screenshot_missing[key] = now; return nil end
  local path = state.screenshot_path .. file_name
  if not file_exists(path) then state.screenshot_missing[key] = now; return nil end
  state.screenshot_visible_keys[key] = true
  if not state.screenshot_load_queued[key] then
    state.screenshot_load_queue[key] = { key = key, path = path }
    state.screenshot_load_order[#state.screenshot_load_order + 1] = key
    state.screenshot_load_queued[key] = true
  end
  return nil
end

local function process_screenshot_load_queue(ctx)
  if #state.screenshot_load_order == 0 then return end
  local now = r.time_precise()
  if now < (state.screenshot_next_load_time or 0) then return end
  local loaded = 0
  while loaded < max_screenshot_loads_per_frame and #state.screenshot_load_order > 0 do
    local key = pop_next_screenshot_load()
    local queued = state.screenshot_load_queue[key]
    state.screenshot_load_queue[key] = nil
    state.screenshot_load_queued[key] = nil
    if queued and not state.screenshot_cache[key] and not state.screenshot_missing[key] then
      local path = queued.path
      if not file_exists(path) then
        state.screenshot_missing[key] = r.time_precise()
      else
        if #state.screenshot_cache_order >= max_screenshot_cache and not trim_screenshot_cache(ctx, max_screenshot_cache - 1, false) then
          trim_screenshot_cache(ctx, math.max(min_screenshot_cache, max_screenshot_cache - 10), true)
        end
        local ok, image = false, nil
        if r.ImGui_CreateImage then ok, image = pcall(r.ImGui_CreateImage, path) end
        if ok and image then
          local attached = true
          if r.ImGui_Attach then attached = pcall(r.ImGui_Attach, ctx, image) end
          if attached then
            detach_screenshot_image(ctx, key)
            state.screenshot_cache[key] = { image = image, path = path, created_at = now, last_seen = now }
            touch_screenshot_image(key)
            loaded = loaded + 1
            state.screenshot_next_load_time = now + min_screenshot_load_interval
          else
            if r.ImGui_DestroyImage then pcall(r.ImGui_DestroyImage, image) end
            state.screenshot_missing[key] = r.time_precise()
            state.screenshot_image_errors = state.screenshot_image_errors + 1
            state.screenshot_next_load_time = now + min_screenshot_load_interval
          end
        else
          local message = tostring(image or "")
          if message:lower():find("excessive creation", 1, true) then
            requeue_screenshot_load(key, queued)
            state.screenshot_next_load_time = now + 0.5
            return
          else
            state.screenshot_missing[key] = r.time_precise()
            state.screenshot_image_errors = state.screenshot_image_errors + 1
            state.screenshot_next_load_time = now + min_screenshot_load_interval
          end
        end
      end
    end
  end
end

local function invalidate_screenshots(ctx)
  for index = #state.screenshot_cache_order, 1, -1 do
    detach_screenshot_image(ctx, state.screenshot_cache_order[index])
  end
  state.screenshot_index = nil
  state.screenshot_signature = nil
  state.screenshot_signature_checked_at = 0
  state.screenshot_missing = {}
  state.screenshot_load_queue = {}
  state.screenshot_load_order = {}
  state.screenshot_load_queued = {}
  build_screenshot_index(true)
end

local function screenshot_capture_available(screen_capture)
  if not (r.JS_Window_GetClientRect and r.JS_GDI_Blit and r.JS_LICE_CreateBitmap and r.JS_LICE_GetDC and r.JS_LICE_WritePNG and r.JS_LICE_DestroyBitmap) then return false end
  if screen_capture then return r.JS_Window_GetRect and r.JS_GDI_GetScreenDC and r.JS_GDI_ReleaseDC end
  return r.JS_GDI_GetClientDC and r.JS_GDI_ReleaseDC
end

local function screenshot_file_size(path)
  local file = io.open(path, "rb")
  if not file then return 0 end
  local size = file:seek("end") or 0
  file:close()
  return size
end

local function ensure_screenshot_folder()
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(state.screenshot_path, 0) end
end

local function capture_fx_window_screenshot(plugin_name, track, fx_index, screen_capture)
  local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
  if not hwnd then return false, nil end
  ensure_screenshot_folder()
  local safe_name = plugin_name:gsub("[^%w%s-]", "_")
  local filename = state.screenshot_path .. safe_name .. ".png"
  local srcx, srcy = 0, 27
  local target_w = 500
  local ok = pcall(function()
    local source_dc, source_bmp, dest_bmp
    local w, h, source_x, source_y = 0, 0, srcx, srcy
    if screen_capture then
      local _, wl, wt, wr, wb = r.JS_Window_GetRect(hwnd)
      local _, cl, ct, cr, cb = r.JS_Window_GetClientRect(hwnd)
      local border_l = cl - wl
      local border_t = ct - wt
      local border_r = wr - cr
      local border_b = wb - cb
      source_x = wl + border_l
      source_y = wt + border_t + srcy
      w = (wr - wl) - border_l - border_r
      h = (wb - wt) - border_t - border_b - srcy
      source_dc = r.JS_GDI_GetScreenDC()
    else
      local _, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
      w = right - left
      h = bottom - top - srcy
      source_dc = r.JS_GDI_GetClientDC(hwnd)
    end
    if w <= 0 or h <= 0 or not source_dc then error("invalid screenshot size") end
    source_bmp = r.JS_LICE_CreateBitmap(true, w, h)
    local source_bmp_dc = r.JS_LICE_GetDC(source_bmp)
    r.JS_GDI_Blit(source_bmp_dc, 0, 0, source_dc, source_x, source_y, w, h)
    local scale = target_w / w
    local target_h = math.max(1, math.floor(h * scale))
    dest_bmp = r.JS_LICE_CreateBitmap(true, target_w, target_h)
    if r.JS_LICE_ScaledBlit then
      r.JS_LICE_ScaledBlit(dest_bmp, 0, 0, target_w, target_h, source_bmp, 0, 0, w, h, 1, "FAST")
      r.JS_LICE_WritePNG(filename, dest_bmp, false)
    else
      r.JS_LICE_WritePNG(filename, source_bmp, false)
    end
    if dest_bmp then r.JS_LICE_DestroyBitmap(dest_bmp) end
    if screen_capture then r.JS_GDI_ReleaseDC(nil, source_dc) else r.JS_GDI_ReleaseDC(hwnd, source_dc) end
    r.JS_LICE_DestroyBitmap(source_bmp)
  end)
  if ok and screenshot_file_size(filename) > 0 then return true, filename end
  return false, filename
end

local function start_screenshot_capture(app, plugin, screen_capture)
  if state.screenshot_capture_active then
    app.status = "Screenshot capture already running"
    return
  end
  if not screenshot_capture_available(screen_capture) then
    app.status = "JS_ReaScriptAPI is required for screenshots"
    return
  end
  local plugin_name = plugin and plugin.name
  if not plugin_name or plugin_name == "" then return end
  local function valid_track(track)
    if not track then return false end
    if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
    if r.ValidatePtr then return r.ValidatePtr(track, "MediaTrack*") end
    return true
  end
  r.Undo_BeginBlock()
  local master = r.GetMasterTrack(0)
  local track = master and r.IsTrackSelected and r.IsTrackSelected(master) and master or r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
  local temp_track = false
  if not valid_track(track) then
    local track_index = r.CountTracks(0)
    r.InsertTrackAtIndex(track_index, false)
    track = r.GetTrack(0, track_index)
    temp_track = true
  end
  if not valid_track(track) then
    r.Undo_EndBlock("Workbench plugin screenshot", -1)
    app.status = "No track available for screenshot capture"
    return
  end
  state.screenshot_capture_active = true
  state.screenshot_capture_plugin = plugin_name
  app.status = "Opening " .. plugin.display_name .. " for screenshot"
  local dest_index = r.TrackFX_GetCount(track)
  local fx_index = r.TrackFX_AddByName(track, plugin_name, false, -1000 - dest_index)
  if not fx_index or fx_index < 0 then
    if temp_track then r.DeleteTrack(track) end
    state.screenshot_capture_active = false
    state.screenshot_capture_plugin = nil
    r.Undo_EndBlock("Workbench plugin screenshot", -1)
    app.status = "Could not load plugin for screenshot"
    return
  end
  r.TrackFX_Show(track, fx_index, 3)
  local start_time = r.time_precise()
  local function finish_capture()
    if r.time_precise() - start_time < 0.5 then
      r.defer(finish_capture)
      return
    end
    local ok, path = capture_fx_window_screenshot(plugin_name, track, fx_index, screen_capture)
    r.TrackFX_Show(track, fx_index, 2)
    r.TrackFX_Delete(track, fx_index)
    if temp_track then r.DeleteTrack(track) end
    state.screenshot_capture_active = false
    state.screenshot_capture_plugin = nil
    r.Undo_EndBlock("Workbench plugin screenshot", -1)
    if ok then
      invalidate_screenshots(app.ctx)
      app.status = "Screenshot saved: " .. tostring(path)
    else
      app.status = "Screenshot failed: " .. plugin.display_name
    end
  end
  r.defer(finish_capture)
end

local function display_name_for(name)
  local alias = state.aliases[name]
  if alias and alias ~= "" then return alias end
  return clean_plugin_name(name)
end

local function rebuild_plugins(plugin_list)
  state.plugins = {}
  state.plugin_by_name = {}
  state.fuzzy_cache = {}
  local seen = {}
  if type(plugin_list) ~= "table" then plugin_list = {} end
  for _, entry in ipairs(plugin_list) do
    local name = type(entry) == "table" and (entry.name or entry[1] or entry.fxname) or entry
    name = tostring(name or "")
    if name ~= "" and not seen[name] then
      seen[name] = true
      local display_name = display_name_for(name)
      local alias = state.aliases[name]
      local plugin = {
        name = name,
        display_name = display_name,
        clean_name = clean_plugin_name(name),
        dedupe_key = normalize_plugin_name(name),
        alias = alias,
        type = plugin_type(name),
        arch = plugin_arch(name),
        instrument = is_instrument(name),
        favorite = state.favorite_set[name] == true,
        recent_index = state.recent_index[name],
        search_key = table.concat({ name, display_name, alias or "", plugin_type(name) }, " "):lower()
      }
      state.plugins[#state.plugins + 1] = plugin
      state.plugin_by_name[name] = plugin
    end
  end
  table.sort(state.plugins, function(left, right) return left.display_name:lower() < right.display_name:lower() end)
  state.last_filter_key = nil
end

local function count_parser_groups(categories)
  local counts = { all = 0, developer = 0, category = 0, folders = 0 }
  if type(categories) ~= "table" then return counts end
  for _, entry in ipairs(categories) do
    local name = tostring(entry and entry.name or "")
    local count = type(entry and entry.list) == "table" and #entry.list or 0
    if name == "ALL PLUGINS" then counts.all = count end
    if name == "DEVELOPER" then counts.developer = count end
    if name == "CATEGORY" then counts.category = count end
    if name == "FOLDERS" then counts.folders = count end
  end
  return counts
end

local function group_kind_for_category(name)
  if name == "ALL PLUGINS" then return "all" end
  if name == "DEVELOPER" then return "developer" end
  if name == "CATEGORY" then return "category" end
  if name == "FOLDERS" then return "folders" end
end

local function group_kind_for_source(source)
  if source == "All Plugins" then return "all" end
  if source == "Developer" then return "developer" end
  if source == "Category" then return "category" end
  if source == "Folders" then return "folders" end
  if source == "Custom Folders" then return "custom_folders" end
end

local function build_group(kind, label, path, plugins, source)
  local plugin_set = {}
  local plugin_norm_set = {}
  local clean_plugins = {}
  if type(plugins) == "table" then
    for _, plugin_name in ipairs(plugins) do
      if type(plugin_name) == "string" and plugin_name ~= "" then
        clean_plugins[#clean_plugins + 1] = plugin_name
        plugin_set[plugin_name] = true
        local norm = normalize_plugin_name(plugin_name)
        if norm ~= "" then plugin_norm_set[norm] = true end
      end
    end
  end
  return { kind = kind, label = label, path = path, plugins = clean_plugins, plugin_set = plugin_set, plugin_norm_set = plugin_norm_set, count = #clean_plugins, source = source }
end

local function collect_custom_folder_plugins(folder)
  local plugins = {}
  if type(folder) ~= "table" then return plugins end
  if type(folder.plugins) == "table" then
    for _, plugin_name in ipairs(folder.plugins) do
      if type(plugin_name) == "string" and plugin_name ~= "" then plugins[#plugins + 1] = plugin_name end
    end
  end
  for key, value in pairs(folder) do
    if type(key) == "number" and type(value) == "string" and value ~= "" then plugins[#plugins + 1] = value end
  end
  return plugins
end

local function collect_custom_subfolders(folder)
  local subfolders = {}
  if type(folder) ~= "table" then return subfolders end
  if type(folder.subfolders) == "table" then
    for name, child in pairs(folder.subfolders) do
      if type(name) == "string" and type(child) == "table" then subfolders[#subfolders + 1] = { name = name, folder = child } end
    end
  end
  for name, child in pairs(folder) do
    if type(name) == "string" and name ~= "plugins" and name ~= "subfolders" and name ~= "_empty" and type(child) == "table" then
      subfolders[#subfolders + 1] = { name = name, folder = child }
    end
  end
  table.sort(subfolders, function(left, right) return left.name:lower() < right.name:lower() end)
  return subfolders
end

local function load_custom_folder_groups()
  state.custom_folder_source = "none"
  state.custom_folder_count = 0
  state.custom_folder_plugin_count = 0
  if not file_exists(custom_folders_path) then return {} end
  local data = read_json(custom_folders_path)
  if type(data) ~= "table" then return {} end
  local groups = {}
  local function walk(folder, label, path)
    local plugins = collect_custom_folder_plugins(folder)
    if label ~= "" then
      groups[#groups + 1] = build_group("custom_folders", path, path, plugins, "custom")
      state.custom_folder_plugin_count = state.custom_folder_plugin_count + #plugins
    end
    for _, child in ipairs(collect_custom_subfolders(folder)) do
      local child_path = path ~= "" and (path .. "/" .. child.name) or child.name
      walk(child.folder, child.name, child_path)
    end
  end
  for name, folder in pairs(data) do
    if type(name) == "string" and type(folder) == "table" then walk(folder, name, name) end
  end
  table.sort(groups, function(left, right) return left.path:lower() < right.path:lower() end)
  state.custom_folder_source = "shared"
  state.custom_folder_count = #groups
  return groups
end

local function selected_group_for_kind(settings, kind)
  local groups = state.groups[kind] or {}
  if #groups == 0 then return nil end
  settings.group_selection = type(settings.group_selection) == "table" and settings.group_selection or {}
  local selected_path = tostring(settings.group_selection[kind] or "")
  for _, group in ipairs(groups) do
    if group.path == selected_path then return group end
  end
  settings.group_selection[kind] = groups[1].path
  return groups[1]
end

local function build_parser_groups(categories)
  local groups = { all = {}, developer = {}, category = {}, folders = {}, custom_folders = {} }
  if type(categories) ~= "table" then return groups end
  for _, category in ipairs(categories) do
    local kind = group_kind_for_category(tostring(category and category.name or ""))
    if kind and type(category.list) == "table" then
      for _, entry in ipairs(category.list) do
        local label = tostring(entry and entry.name or "")
        local plugins = type(entry and entry.fx) == "table" and entry.fx or {}
        if label ~= "" then
          groups[kind][#groups[kind] + 1] = build_group(kind, label, label, plugins, "parser")
        end
      end
      table.sort(groups[kind], function(left, right) return left.label:lower() < right.label:lower() end)
    end
  end
  return groups
end

local function store_parser_data(categories, developers)
  state.parser_categories = type(categories) == "table" and categories or {}
  state.parser_developers = type(developers) == "table" and developers or {}
  state.groups = build_parser_groups(state.parser_categories)
  state.groups.custom_folders = load_custom_folder_groups()
  state.parser_group_counts = count_parser_groups(state.parser_categories)
end

local function load_parser(force_scan)
  state.load_error = nil
  if not file_exists(parser_path) then
    state.parser_loaded = false
    state.load_error = "Sexan parser not found"
    state.plugins = {}
    state.filtered = {}
    return false
  end
  if not state.parser_loaded then
    local ok, err = pcall(dofile, parser_path)
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
  local plugin_list, categories, developers
  if force_scan and type(MakeFXFiles) == "function" then
    local ok_scan, scanned, scanned_categories, scanned_developers = pcall(MakeFXFiles)
    if ok_scan then
      plugin_list = scanned
      categories = scanned_categories
      developers = scanned_developers
    else
      state.load_error = tostring(scanned)
    end
  end
  if not plugin_list then
    local ok_read, read_plugins, read_categories, read_developers = pcall(ReadFXFile)
    if ok_read then
      plugin_list = read_plugins
      categories = read_categories
      developers = read_developers
    else
      state.load_error = tostring(read_plugins)
    end
  end
  if type(plugin_list) ~= "table" or #plugin_list == 0 then
    if type(MakeFXFiles) == "function" then
      local ok_scan, scanned, scanned_categories, scanned_developers = pcall(MakeFXFiles)
      if ok_scan then
        plugin_list = scanned
        categories = scanned_categories
        developers = scanned_developers
      else
        state.load_error = tostring(scanned)
      end
    end
  end
  store_parser_data(categories, developers)
  rebuild_plugins(plugin_list or {})
  state.source = "Sexan parser"
  return #state.plugins > 0
end

local function parser_group_summary()
  local counts = state.parser_group_counts or {}
  return " | groups all " .. tostring(counts.all or 0) .. " dev " .. tostring(counts.developer or 0) .. " cat " .. tostring(counts.category or 0) .. " folders " .. tostring(counts.folders or 0)
end

local function favorites_source_summary()
  return " | favorites " .. tostring(state.favorite_source or "local")
end

local function shared_data_summary()
  local parts = {}
  if state.rating_source == "shared" then parts[#parts + 1] = "ratings shared" end
  if state.pinned_source == "shared" then parts[#parts + 1] = "pinned shared" end
  if state.custom_folder_source == "shared" then parts[#parts + 1] = "custom folders shared " .. tostring(state.custom_folder_count or 0) end
  return #parts > 0 and (" | " .. table.concat(parts, " ")) or ""
end

local function active_filter_key(settings)
  local parts = { tostring(settings.show_x86 ~= false), tostring(settings.sort_mode or "name"), tostring(settings.show_pinned_on_top ~= false), tostring(settings.show_favorites_on_top == true), tostring(settings.use_type_priority ~= false) }
  settings.type_filter = type(settings.type_filter) == "table" and settings.type_filter or {}
  for _, plugin_type_name in ipairs(plugin_types) do
    parts[#parts + 1] = plugin_type_name .. "=" .. tostring(settings.type_filter[plugin_type_name] ~= false)
  end
  if type(settings.type_priority) == "table" then parts[#parts + 1] = table.concat(settings.type_priority, ",") end
  return table.concat(parts, ",")
end

local type_priority_rank

local function compare_plugin_order(left, right, settings, source)
  if state.pinned_source == "shared" and settings.show_pinned_on_top ~= false and left.pinned ~= right.pinned then return left.pinned end
  if settings.show_favorites_on_top == true and left.favorite ~= right.favorite then return left.favorite end
  if source == "Recent" then
    local left_index = left.recent_index or 999999
    local right_index = right.recent_index or 999999
    if left_index ~= right_index then return left_index < right_index end
  elseif settings.sort_mode == "rating" and state.rating_source == "shared" then
    local left_rating = left.rating or 0
    local right_rating = right.rating or 0
    if left_rating ~= right_rating then return left_rating > right_rating end
  end
  return left.display_name:lower() < right.display_name:lower()
end

local function has_active_type_filters(settings)
  if settings.show_x86 == false then return true end
  local type_filter = type(settings.type_filter) == "table" and settings.type_filter or {}
  for _, plugin_type_name in ipairs(plugin_types) do
    if type_filter[plugin_type_name] == false then return true end
  end
  return false
end

local function has_active_browser_options(settings)
  return has_active_type_filters(settings) or settings.sort_mode ~= "name" or settings.show_pinned_on_top == false or settings.show_favorites_on_top == true or settings.use_type_priority == false
end

type_priority_rank = function(settings, plugin_type_name)
  local priority = type(settings.type_priority) == "table" and settings.type_priority or defaults.type_priority
  for index, value in ipairs(priority) do
    if value == plugin_type_name then return index end
  end
  return 999
end

local function dedupe_by_type_priority(settings, plugins)
  if settings.use_type_priority == false or type(plugins) ~= "table" or #plugins <= 1 then return plugins end
  local best_by_key = {}
  local order = {}
  local has_duplicates = false
  for _, plugin in ipairs(plugins) do
    local key = plugin.dedupe_key or normalize_plugin_name(plugin.name)
    if key ~= "" then
      local rank = type_priority_rank(settings, plugin.type)
      local current = best_by_key[key]
      if not current then
        best_by_key[key] = { plugin = plugin, rank = rank }
        order[#order + 1] = key
      else
        has_duplicates = true
        if rank < current.rank then best_by_key[key] = { plugin = plugin, rank = rank } end
      end
    else
      order[#order + 1] = plugin
    end
  end
  if not has_duplicates then return plugins end
  local result = {}
  for _, key in ipairs(order) do
    if type(key) == "table" then
      result[#result + 1] = key
    elseif best_by_key[key] then
      result[#result + 1] = best_by_key[key].plugin
    end
  end
  return result
end

local function refresh_filter(settings, force)
  if settings.sort_mode == "type_priority" then settings.sort_mode = "name" end
  if settings.sort_mode == "rating" and state.rating_source ~= "shared" then settings.sort_mode = "name" end
  if settings.source == "Custom Folders" and state.custom_folder_source ~= "shared" then settings.source = "All" end
  local source = settings.source or "All"
  local group_kind = group_kind_for_source(source)
  local selected_group = group_kind and selected_group_for_kind(settings, group_kind) or nil
  local group_path = selected_group and selected_group.path or ""
  local key = table.concat({ settings.search_term or "", source, group_path, active_filter_key(settings), tostring(#state.plugins), tostring(#state.favorites), tostring(#state.recent), tostring(state.rating_count), tostring(#state.pinned), tostring(state.custom_folder_count), tostring(state.custom_folder_plugin_count) }, "|")
  if not force and key == state.last_filter_key then return end
  local result = {}
  local type_filter = type(settings.type_filter) == "table" and settings.type_filter or {}
  for _, plugin in ipairs(state.plugins) do
    plugin.favorite = state.favorite_set[plugin.name] == true
    plugin.rating = plugin_rating(plugin)
    plugin.pinned = plugin_pinned(plugin)
    plugin.recent_index = state.recent_index[plugin.name]
    local include = true
    if source == "Favorites" then include = plugin.favorite end
    if source == "Recent" then include = plugin.recent_index ~= nil end
    if source == "Instruments" then include = plugin.instrument end
    if group_kind then
      include = selected_group ~= nil and (selected_group.plugin_set[plugin.name] == true or (plugin.dedupe_key ~= "" and selected_group.plugin_norm_set and selected_group.plugin_norm_set[plugin.dedupe_key] == true))
    end
    if include and settings.show_x86 == false and plugin.arch == "x86" then include = false end
    if include and type_filter[plugin.type] == false then include = false end
    if include and fuzzy_find(plugin.search_key, settings.search_term or "") then result[#result + 1] = plugin end
  end
  result = dedupe_by_type_priority(settings, result)
  table.sort(result, function(left, right) return compare_plugin_order(left, right, settings, source) end)
  state.filtered = result
  state.last_filter_key = key
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

local function get_target_track()
  local master = r.GetMasterTrack(0)
  if master and r.IsTrackSelected and r.IsTrackSelected(master) then return master end
  return r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0)
end

local function track_label(track)
  if not validate_track(track) then return "No track" end
  if track == r.GetMasterTrack(0) then return "MASTER" end
  local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  local _, name = r.GetTrackName(track)
  if not name or name == "" then name = "Track " .. tostring(index) end
  return tostring(index) .. " - " .. name
end

local function collect_selected_tracks()
  local tracks = {}
  local master = r.GetMasterTrack(0)
  if master and r.IsTrackSelected and r.IsTrackSelected(master) then tracks[#tracks + 1] = master end
  local count = r.CountSelectedTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    if validate_track(track) then tracks[#tracks + 1] = track end
  end
  if #tracks == 0 then
    local target = get_target_track()
    if validate_track(target) then tracks[#tracks + 1] = target end
  end
  return tracks
end

local function add_fx_to_track_pointer(track, plugin)
  if not validate_track(track) then return false end
  local dest_index = r.TrackFX_GetCount(track)
  local fx_index = r.TrackFX_AddByName(track, plugin.name, false, -1000 - dest_index)
  return fx_index and fx_index >= 0
end

local function add_fx_to_input_pointer(track, plugin)
  if not validate_track(track) then return false, -1 end
  local fx_index = r.TrackFX_AddByName(track, plugin.name, true, -1)
  return fx_index and fx_index >= 0, fx_index or -1
end

local function add_fx_to_item_pointer(item, plugin)
  if not validate_item(item) then return false, -1 end
  local take = r.GetActiveTake(item)
  if not take then return false, -1 end
  local dest_index = r.TakeFX_GetCount(take)
  local fx_index = r.TakeFX_AddByName(take, plugin.name, -1000 - dest_index)
  return fx_index and fx_index >= 0, fx_index or -1, take
end

local function clear_external_drag()
  state.potential_drag_plugin = nil
  state.potential_drag_plugins = nil
  state.dragging_plugin = nil
  state.dragging_plugins = nil
  state.drag_target_track = nil
  state.drag_target_item = nil
  state.drag_target_mode = "track"
  if r.HasExtState and r.HasExtState("TKFXB", "drag_fx") then r.DeleteExtState("TKFXB", "drag_fx", false) end
end

local function mouse_screen_position()
  if r.GetMousePosition then return r.GetMousePosition() end
  return nil, nil
end

local function track_under_mouse()
  if not r.GetTrackFromPoint then return nil end
  local x, y = mouse_screen_position()
  if not x or not y then return nil end
  local track = select(1, r.GetTrackFromPoint(x, y))
  if validate_track(track) then return track end
  return nil
end

local function item_under_mouse()
  if not r.GetItemFromPoint then return nil end
  local x, y = mouse_screen_position()
  if not x or not y then return nil end
  local item = r.GetItemFromPoint(x, y, false)
  if validate_item(item) then return item end
  return nil
end

local function item_label(item)
  if not validate_item(item) then return "No item" end
  local take = r.GetActiveTake(item)
  if take then
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if name and name ~= "" then return name end
  end
  local track = r.GetMediaItemTrack(item)
  if validate_track(track) then return "Item on " .. track_label(track) end
  return "Item"
end

local function drag_modifier_mode(ctx)
  if not r.ImGui_IsKeyDown then return "track" end
  local shift = (r.ImGui_Key_LeftShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift())) or (r.ImGui_Key_RightShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift()))
  if shift then return "item" end
  local ctrl = (r.ImGui_Key_LeftCtrl and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl())) or (r.ImGui_Key_RightCtrl and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl()))
  local alt = (r.ImGui_Key_LeftAlt and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt())) or (r.ImGui_Key_RightAlt and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt()))
  if ctrl or alt then return "input" end
  return "track"
end

local function selection_key(plugin)
  return plugin and plugin.name or ""
end

local function is_plugin_selected(plugin)
  return state.selected_plugins[selection_key(plugin)] == true
end

local function selection_count()
  local count = 0
  for _ in pairs(state.selected_plugins) do count = count + 1 end
  return count
end

local function selected_plugin_list()
  local plugins = {}
  for _, plugin in ipairs(state.filtered) do
    if is_plugin_selected(plugin) then plugins[#plugins + 1] = plugin end
  end
  return plugins
end

local function drag_plugins_for(plugin)
  if is_plugin_selected(plugin) and selection_count() > 1 then
    local plugins = selected_plugin_list()
    if #plugins > 0 then return plugins end
  end
  return { plugin }
end

local function drag_plugins_label(plugins)
  local count = plugins and #plugins or 0
  if count > 1 then return tostring(count) .. " FX" end
  local plugin = plugins and plugins[1]
  return plugin and plugin.display_name or "FX"
end

local function is_selection_ctrl_down(ctx)
  if not r.ImGui_IsKeyDown then return false end
  return (r.ImGui_Key_LeftCtrl and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl())) or (r.ImGui_Key_RightCtrl and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl()))
end

local function is_selection_shift_down(ctx)
  if not r.ImGui_IsKeyDown then return false end
  return (r.ImGui_Key_LeftShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift())) or (r.ImGui_Key_RightShift and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift()))
end

local function select_range(first_index, last_index, additive)
  if not additive then state.selected_plugins = {} end
  local first = math.max(1, math.min(first_index or last_index or 1, #state.filtered))
  local last = math.max(1, math.min(last_index or first, #state.filtered))
  if first > last then first, last = last, first end
  for index = first, last do
    local plugin = state.filtered[index]
    if plugin then state.selected_plugins[selection_key(plugin)] = true end
  end
end

local function clear_selection(app)
  if selection_count() == 0 then return end
  state.selected_plugins = {}
  state.selection_anchor_index = nil
  if app then app.status = "FX selection cleared" end
end

local function return_to_rack_after_add(app, settings)
  if not settings.return_to_rack_after_add then return end
  if not app or not app.cache or app.cache.plugin_browser_return_module ~= "instrument_rack" then return end
  if not app.modules_by_id or not app.modules_by_id.instrument_rack then return end
  if app.set_active_view then app.set_active_view("instrument_rack") end
end

local function return_to_chain_builder_after_add(app, settings)
  if not settings.return_to_chain_builder_after_add then return end
  if not app or not app.modules_by_id or not app.modules_by_id.fx_chain_builder then return end
  if app.set_active_view then app.set_active_view("fx_chain_builder") end
end

local function add_fx_to_drag_target(app, settings, plugin, track)
  if not validate_track(track) or not plugin then app.status = "No track under mouse"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = add_fx_to_track_pointer(track, plugin)
  local fx_index = added and (r.TrackFX_GetCount(track) - 1) or -1
  if added and settings.open_floating_after_drag_add and fx_index >= 0 then r.TrackFX_Show(track, fx_index, 3) end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX from Workbench drag", -1)
  if added then
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    app.status = "Dropped " .. plugin.display_name .. " on " .. track_label(track)
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not drop " .. plugin.display_name
  end
end

local function add_fx_to_input_target(app, settings, plugin, track)
  if not validate_track(track) or not plugin then app.status = "No track under mouse"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = add_fx_to_input_pointer(track, plugin)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to Input FX from Workbench drag", -1)
  if added then
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    app.status = "Dropped " .. plugin.display_name .. " to Input FX on " .. track_label(track)
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not drop " .. plugin.display_name .. " to Input FX"
  end
end

local function add_fx_to_item_target(app, settings, plugin, item)
  if not validate_item(item) or not plugin then app.status = "No item under mouse"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added, fx_index, take = add_fx_to_item_pointer(item, plugin)
  if added and settings.open_floating_after_drag_add and fx_index >= 0 and take and r.TakeFX_Show then r.TakeFX_Show(take, fx_index, 3) end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to Item from Workbench drag", -1)
  if added then
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    app.status = "Dropped " .. plugin.display_name .. " on " .. item_label(item)
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not drop " .. plugin.display_name .. " on item"
  end
end

local function add_plugins_to_track_target(app, settings, plugins, track)
  if not validate_track(track) or not plugins or #plugins == 0 then app.status = "No track under mouse"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = 0
  local last_fx_index = -1
  for _, plugin in ipairs(plugins) do
    if add_fx_to_track_pointer(track, plugin) then
      added = added + 1
      last_fx_index = r.TrackFX_GetCount(track) - 1
      add_recent(settings, plugin.name)
    end
  end
  if added == 1 and settings.open_floating_after_drag_add and last_fx_index >= 0 then r.TrackFX_Show(track, last_fx_index, 3) end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX from Workbench drag", -1)
  if added > 0 then
    state.last_filter_key = nil
    app.status = "Dropped " .. drag_plugins_label(plugins) .. " on " .. track_label(track)
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not drop " .. drag_plugins_label(plugins)
  end
end

local function add_plugins_to_input_target(app, settings, plugins, track)
  if not validate_track(track) or not plugins or #plugins == 0 then app.status = "No track under mouse"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = 0
  for _, plugin in ipairs(plugins) do
    if add_fx_to_input_pointer(track, plugin) then
      added = added + 1
      add_recent(settings, plugin.name)
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to Input FX from Workbench drag", -1)
  if added > 0 then
    state.last_filter_key = nil
    app.status = "Dropped " .. drag_plugins_label(plugins) .. " to Input FX on " .. track_label(track)
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not drop " .. drag_plugins_label(plugins) .. " to Input FX"
  end
end

local function add_plugins_to_item_target(app, settings, plugins, item)
  if not validate_item(item) or not plugins or #plugins == 0 then app.status = "No item under mouse"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = 0
  local last_fx_index = -1
  local last_take = nil
  for _, plugin in ipairs(plugins) do
    local ok, fx_index, take = add_fx_to_item_pointer(item, plugin)
    if ok then
      added = added + 1
      last_fx_index = fx_index
      last_take = take
      add_recent(settings, plugin.name)
    end
  end
  if added == 1 and settings.open_floating_after_drag_add and last_fx_index >= 0 and last_take and r.TakeFX_Show then r.TakeFX_Show(last_take, last_fx_index, 3) end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to Item from Workbench drag", -1)
  if added > 0 then
    state.last_filter_key = nil
    app.status = "Dropped " .. drag_plugins_label(plugins) .. " on " .. item_label(item)
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not drop " .. drag_plugins_label(plugins) .. " on item"
  end
end

local function register_external_drag_source(ctx, settings, plugin, index, hovered)
  if not settings.enable_drag_add_fx or not hovered or state.dragging_plugin then return end
  if r.ImGui_IsMouseClicked(ctx, 0) then
    local x, y = mouse_screen_position()
    state.potential_drag_plugin = plugin
    state.potential_drag_plugins = drag_plugins_for(plugin)
    state.selection_anchor_index = state.selection_anchor_index or index
    state.potential_drag_x = x or 0
    state.potential_drag_y = y or 0
  end
end

local function update_external_drag(app, settings)
  local ctx = app.ctx
  if not settings.enable_drag_add_fx then clear_external_drag(); return end
  if not r.GetTrackFromPoint or not r.ImGui_IsMouseDown or not r.ImGui_IsMouseReleased then return end
  local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
  local released = r.ImGui_IsMouseReleased(ctx, 0)
  if state.potential_drag_plugin and not state.dragging_plugin then
    if not mouse_down then
      state.potential_drag_plugin = nil
    else
      local x, y = mouse_screen_position()
      if x and y then
        local dx = x - (state.potential_drag_x or x)
        local dy = y - (state.potential_drag_y or y)
        if dx * dx + dy * dy >= state.drag_threshold * state.drag_threshold then
          state.dragging_plugin = state.potential_drag_plugin
          state.dragging_plugins = state.potential_drag_plugins or { state.potential_drag_plugin }
          state.potential_drag_plugin = nil
          state.potential_drag_plugins = nil
        end
      end
    end
  end
  if state.dragging_plugin then
    local plugin = state.dragging_plugin
    local plugins = state.dragging_plugins or { plugin }
    local label = drag_plugins_label(plugins)
    local mode = drag_modifier_mode(ctx)
    local track = mode == "item" and nil or track_under_mouse()
    local item = mode == "item" and item_under_mouse() or nil
    state.drag_target_mode = mode
    state.drag_target_track = track
    state.drag_target_item = item
    if r.SetExtState then r.SetExtState("TKFXB", "drag_fx", plugin.name, false) end
    if mode == "item" and item then
      app.status = "Drop " .. label .. " on " .. item_label(item)
    elseif mode == "item" then
      app.status = "Drop " .. label .. " on an item"
    elseif mode == "input" and track then
      app.status = "Drop " .. label .. " to Input FX on " .. track_label(track)
    elseif mode == "input" then
      app.status = "Drop " .. label .. " to Input FX on a track"
    elseif track then
      app.status = "Drop " .. label .. " on " .. track_label(track)
    else
      app.status = "Drop " .. label .. " on a track"
    end
    if released or not mouse_down then
      if mode == "item" and item then
        add_plugins_to_item_target(app, settings, plugins, item)
      elseif mode == "input" and track then
        add_plugins_to_input_target(app, settings, plugins, track)
      elseif track then
        add_plugins_to_track_target(app, settings, plugins, track)
      end
      clear_external_drag()
    end
  elseif released then
    state.potential_drag_plugin = nil
  end
end

local function drag_target_label(track)
  if state.drag_target_mode == "item" then
    if not validate_item(state.drag_target_item) then return "Item", "No item", 0xFF4040FF end
    return "Item", item_label(state.drag_target_item), 0xFFA040FF
  end
  if state.drag_target_mode == "input" then
    if not validate_track(track) then return "Input FX", "No track", 0xFF4040FF end
    return "Input FX", track_label(track), 0x40A0FFFF
  end
  if not validate_track(track) then return "Track", "No track", 0xFF4040FF end
  return "Track", track_label(track), 0x40C040FF
end

local function draw_drag_overlay(app)
  if not state.dragging_plugin then return end
  local ctx = app.ctx
  local plugin = state.dragging_plugin
  local plugins = state.dragging_plugins or { plugin }
  if not r.ImGui_GetMousePos or not r.ImGui_GetMainViewport then return end
  local imx, imy = r.ImGui_GetMousePos(ctx)
  local target_type, target_name, target_color = drag_target_label(state.drag_target_track)
  local vp = r.ImGui_GetMainViewport(ctx)
  local vp_x, vp_y = r.ImGui_Viewport_GetPos(vp)
  local marker_radius = 24
  local marker_pad = 8
  local marker_size = (marker_radius + marker_pad) * 2
  local marker_flags = r.ImGui_WindowFlags_NoDecoration() | r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoSavedSettings() | r.ImGui_WindowFlags_NoInputs() | r.ImGui_WindowFlags_NoBackground()
  r.ImGui_SetNextWindowPos(ctx, imx - vp_x - marker_radius - marker_pad, imy - vp_y - marker_radius - marker_pad, r.ImGui_Cond_Always())
  r.ImGui_SetNextWindowSize(ctx, marker_size, marker_size, r.ImGui_Cond_Always())
  r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
  if r.ImGui_Begin(ctx, "##tk_workbench_drag_marker", true, marker_flags) then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local fill_col = (target_color & 0xFFFFFF00) | 0x44
    r.ImGui_DrawList_AddCircleFilled(draw_list, imx, imy, marker_radius, fill_col, 0)
    r.ImGui_DrawList_AddCircle(draw_list, imx, imy, marker_radius, target_color, 0, 3.0)
    r.ImGui_DrawList_AddCircle(draw_list, imx, imy, marker_radius - 6, target_color, 0, 1.5)
    r.ImGui_DrawList_AddLine(draw_list, imx - marker_radius * 0.55, imy, imx + marker_radius * 0.55, imy, target_color, 2.0)
    r.ImGui_DrawList_AddLine(draw_list, imx, imy - marker_radius * 0.55, imx, imy + marker_radius * 0.55, target_color, 2.0)
    r.ImGui_End(ctx)
  end
  local overlay_flags = r.ImGui_WindowFlags_NoDecoration() | r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoSavedSettings() | r.ImGui_WindowFlags_NoInputs()
  r.ImGui_SetNextWindowBgAlpha(ctx, 0.42)
  r.ImGui_SetNextWindowPos(ctx, imx - vp_x + marker_radius + marker_pad + 6, imy - vp_y + marker_radius + marker_pad + 6, r.ImGui_Cond_Always())
  if r.ImGui_Begin(ctx, "##tk_workbench_drag_overlay", true, overlay_flags) then
    r.ImGui_Text(ctx, "FX " .. drag_plugins_label(plugins))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), target_color)
    r.ImGui_Text(ctx, target_type .. ": " .. target_name)
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFF99)
    if state.drag_target_mode == "track" then r.ImGui_Text(ctx, "Shift = Item FX | Ctrl/Alt = Input FX") end
    r.ImGui_Text(ctx, "Release to add")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_End(ctx)
  end
end

local function add_fx_to_track(app, settings, plugin)
  local track = get_target_track()
  if not validate_track(track) then app.status = "No target track"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = add_fx_to_track_pointer(track, plugin)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX from Workbench", -1)
  if added then
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    app.status = "Added " .. plugin.display_name .. " to " .. track_label(track)
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not add " .. plugin.display_name
  end
end

local function add_instrument_to_new_track(app, settings, plugin, midi_input_value)
  if not plugin then return end
  local index = r.CountTracks(0) or 0
  local track = nil
  local added = false
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.InsertTrackAtIndex(index, true)
  track = r.GetTrack(0, index)
  if validate_track(track) then
    added = add_fx_to_track_pointer(track, plugin)
    if added then
      r.GetSetMediaTrackInfo_String(track, "P_NAME", instrument_track_name(plugin), true)
      r.SetMediaTrackInfo_Value(track, "I_RECINPUT", virtual_track_midi_input_value(midi_input_value))
      r.SetMediaTrackInfo_Value(track, "I_RECMODE", 0)
      r.SetMediaTrackInfo_Value(track, "I_RECMON", 2)
      r.SetOnlyTrackSelected(track)
    elseif r.DeleteTrack then
      r.DeleteTrack(track)
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add virtual instrument track from Workbench", -1)
  if added then
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    r.UpdateArrange()
    app.status = "Added " .. plugin.display_name .. " as virtual instrument track"
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not create virtual instrument track for " .. plugin.display_name
  end
end

local function handle_plugin_click(app, settings, plugin, index, double_clicked)
  local ctx = app.ctx
  local ctrl = is_selection_ctrl_down(ctx)
  local shift = is_selection_shift_down(ctx)
  if shift then
    local anchor = state.selection_anchor_index or index
    select_range(anchor, index, ctrl)
    app.status = tostring(selection_count()) .. " FX selected"
    return
  end
  if ctrl then
    local key = selection_key(plugin)
    if state.selected_plugins[key] then state.selected_plugins[key] = nil else state.selected_plugins[key] = true end
    state.selection_anchor_index = index
    app.status = tostring(selection_count()) .. " FX selected"
    return
  end
  if settings.double_click_insert then
    if double_clicked then
      add_fx_to_track(app, settings, plugin)
    else
      state.selected_plugins = { [selection_key(plugin)] = true }
      state.selection_anchor_index = index
      app.status = plugin.display_name .. " selected"
    end
    return
  end
  add_fx_to_track(app, settings, plugin)
end

local function add_fx_to_selected_tracks(app, settings, plugin)
  local tracks = collect_selected_tracks()
  if #tracks == 0 then app.status = "No target track"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = 0
  for _, track in ipairs(tracks) do
    if add_fx_to_track_pointer(track, plugin) then added = added + 1 end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to selected tracks from Workbench", -1)
  if added > 0 then
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    app.status = "Added " .. plugin.display_name .. " to " .. tostring(added) .. " track(s)"
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not add " .. plugin.display_name
  end
end

local function add_fx_to_new_track(app, settings, plugin)
  local index = r.CountTracks(0) or 0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.InsertTrackAtIndex(index, true)
  local track = r.GetTrack(0, index)
  local added = add_fx_to_track_pointer(track, plugin)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to new track from Workbench", -1)
  if added then
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    app.status = "Added " .. plugin.display_name .. " to new track"
    return_to_rack_after_add(app, settings)
  else
    app.status = "Could not add " .. plugin.display_name .. " to new track"
  end
end

local function add_fx_to_chain_builder(app, plugin)
  local settings = ensure_settings(app)
  local builder = app.modules_by_id and app.modules_by_id.fx_chain_builder
  if builder and builder.add_plugin then
    builder.add_plugin(app, plugin.name)
    add_recent(settings, plugin.name)
    state.last_filter_key = nil
    return_to_chain_builder_after_add(app, settings)
  else
    app.status = "FX Chain Builder is not loaded"
  end
end

local function add_plugins_to_chain_builder(app, settings, plugins)
  local builder = app.modules_by_id and app.modules_by_id.fx_chain_builder
  if not builder or not builder.add_plugin then app.status = "FX Chain Builder is not loaded"; return end
  if not plugins or #plugins == 0 then app.status = "No FX selected"; return end
  for _, plugin in ipairs(plugins) do
    builder.add_plugin(app, plugin.name)
    add_recent(settings, plugin.name)
  end
  state.last_filter_key = nil
  app.status = "Added " .. drag_plugins_label(plugins) .. " to Chain Builder"
  return_to_chain_builder_after_add(app, settings)
end

local type_colors = {
  VST3 = 0x4FC1E9FF,
  VST = 0x48CFADFF,
  CLAP = 0xAC92ECFF,
  JS = 0xFFCE54FF,
  JSFX = 0xFFCE54FF,
  AU = 0xED5565FF,
  LV2 = 0xA0D568FF,
  OTHER = 0x888888FF
}

local function truncate_text(ctx, text, max_width)
  text = tostring(text or "")
  if r.ImGui_CalcTextSize(ctx, text) <= max_width then return text end
  local value = text
  while #value > 1 and r.ImGui_CalcTextSize(ctx, value .. "..") > max_width do
    value = value:sub(1, -2)
  end
  return value .. ".."
end

local function draw_type_badge(ctx, draw_list, plugin, x, y, w)
  local label = plugin.type or "FX"
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  local px, py = 4, 2
  local pad = 8
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local badge_w = text_w + px * 2
  local bx = x + w - badge_w - pad
  local by = y + pad
  local color = type_colors[label] or type_colors.OTHER
  r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + badge_w, by + line_h + py * 2, color, 4)
  r.ImGui_DrawList_AddText(draw_list, bx + px, by + py, Theme.colors.badge_text, label)
end

local function draw_favorite_dot(draw_list, plugin, x, y, radius)
  if not plugin.favorite then return end
  r.ImGui_DrawList_AddCircleFilled(draw_list, x, y, radius or 4, 0xFFCE54FF, 16)
end

local function draw_pinned_marker(draw_list, plugin, x, y, radius)
  if not plugin.pinned then return end
  r.ImGui_DrawList_AddCircleFilled(draw_list, x, y, radius or 4, 0x7AA2F7FF, 16)
end

local function rating_label(plugin)
  local rating = tonumber(plugin and plugin.rating) or 0
  return rating > 0 and string.rep("*", rating) or ""
end

local function draw_rating_label(ctx, draw_list, plugin, x, y, size_delta)
  local label = rating_label(plugin)
  if label == "" then return end
  if r.ImGui_DrawList_AddTextEx then
    r.ImGui_DrawList_AddTextEx(draw_list, nil, r.ImGui_GetFontSize(ctx) + (size_delta or 2), x, y - 1, 0xFFCE54FF, label)
  else
    r.ImGui_DrawList_AddText(draw_list, x, y, 0xFFCE54FF, label)
  end
end

local function draw_plugin_context_menu(app, settings, plugin, popup_id)
  local ctx = app.ctx
  if r.ImGui_BeginPopupContextItem(ctx, popup_id) then
    local chain_plugins = drag_plugins_for(plugin)
    if r.ImGui_MenuItem(ctx, "Add to selected track(s)") then add_fx_to_selected_tracks(app, settings, plugin) end
    if r.ImGui_MenuItem(ctx, "Add to new track") then add_fx_to_new_track(app, settings, plugin) end
    if is_instrument(plugin.name) and r.ImGui_BeginMenu(ctx, "Add as virtual instrument to new track") then
      if r.ImGui_MenuItem(ctx, "All MIDI inputs") then add_instrument_to_new_track(app, settings, plugin, 6112) end
      local num_midi_inputs = r.GetNumMIDIInputs and r.GetNumMIDIInputs() or 0
      for index = 0, num_midi_inputs - 1 do
        local ok, name = r.GetMIDIInputName(index, "")
        if ok and name and name ~= "" then
          if r.ImGui_MenuItem(ctx, name) then add_instrument_to_new_track(app, settings, plugin, 6113 + index) end
        end
      end
      r.ImGui_EndMenu(ctx)
    end
    if r.ImGui_MenuItem(ctx, #chain_plugins > 1 and ("Add " .. drag_plugins_label(chain_plugins) .. " to Chain Builder") or "Add to Chain Builder") then add_plugins_to_chain_builder(app, settings, chain_plugins) end
    local is_favorite = state.favorite_set[plugin.name] == true
    if r.ImGui_MenuItem(ctx, is_favorite and "Remove from favorites" or "Add to favorites") then
      if is_favorite then
        remove_favorite(plugin)
        app.status = plugin.display_name .. " removed from favorites"
      else
        add_favorite(plugin)
        app.status = plugin.display_name .. " added to favorites"
      end
    end
    if state.pinned_source == "shared" then
      local is_pinned = plugin_pinned(plugin)
      if r.ImGui_MenuItem(ctx, is_pinned and "Unpin plugin" or "Pin plugin") then
        if is_pinned then
          unpin_plugin(plugin)
          app.status = plugin.display_name .. " unpinned"
        else
          pin_plugin(plugin)
          app.status = plugin.display_name .. " pinned"
        end
      end
    end
    if state.rating_source == "shared" then
      r.ImGui_Separator(ctx)
      local rating = plugin_rating(plugin)
      for value = 1, 5 do
        if r.ImGui_MenuItem(ctx, "Rating " .. tostring(value) .. "/5", "", rating == value) then
          set_plugin_rating(plugin, value)
          app.status = plugin.display_name .. " rating " .. tostring(value) .. "/5"
        end
      end
      if rating > 0 and r.ImGui_MenuItem(ctx, "Clear rating") then
        set_plugin_rating(plugin, 0)
        app.status = plugin.display_name .. " rating cleared"
      end
    end
    r.ImGui_Separator(ctx)
    if state.screenshot_capture_active then
      r.ImGui_Text(ctx, "Screenshot capture running")
    else
      if r.ImGui_MenuItem(ctx, "Make Screenshot") then start_screenshot_capture(app, plugin, false) end
      if r.ImGui_MenuItem(ctx, "Make Screenshot (OpenGL/DX)") then start_screenshot_capture(app, plugin, true) end
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function set_next_combo_height(ctx, settings)
  local rows = math.floor(tonumber(settings.dropdown_rows) or defaults.dropdown_rows)
  if rows < 8 then rows = 8 end
  if rows > 36 then rows = 36 end
  local height = rows * (r.ImGui_GetTextLineHeight(ctx) + 6) + 12
  if r.ImGui_SetNextWindowSizeConstraints then
    local width = r.ImGui_CalcItemWidth and r.ImGui_CalcItemWidth(ctx) or 180
    r.ImGui_SetNextWindowSizeConstraints(ctx, width, 0, 100000, height)
  elseif r.ImGui_SetNextWindowSize then
    r.ImGui_SetNextWindowSize(ctx, 0, height, r.ImGui_Cond_Appearing())
  end
end

local function draw_source_combo(ctx, settings, app)
  local current = settings.source or "All"
  set_next_combo_height(ctx, settings)
  if r.ImGui_BeginCombo(ctx, "##pb_source", current) then
    for _, source in ipairs(sources) do
      if source ~= "Custom Folders" or state.custom_folder_source == "shared" then
        local selected = current == source
        if r.ImGui_Selectable(ctx, source, selected) then
          settings.source = source
          state.last_filter_key = nil
          if app.save_settings then app.save_settings() end
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function draw_group_combo(ctx, settings, app, kind)
  local group = selected_group_for_kind(settings, kind)
  local groups = state.groups[kind] or {}
  local current = group and group.label or "No groups"
  set_next_combo_height(ctx, settings)
  if r.ImGui_BeginCombo(ctx, "##pb_group", current) then
    for index, entry in ipairs(groups) do
      local selected = group and group.path == entry.path
      local label = entry.label .. " (" .. tostring(entry.count or #entry.plugins or 0) .. ")##" .. tostring(index)
      if r.ImGui_Selectable(ctx, label, selected) then
        settings.group_selection[kind] = entry.path
        state.last_filter_key = nil
        if app.save_settings then app.save_settings() end
      end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function save_filter_change(app)
  state.last_filter_key = nil
  if app.save_settings then app.save_settings() end
end

local function draw_filter_popup(ctx, settings, app)
  if not r.ImGui_BeginPopup(ctx, "##pb_filter_menu") then return end
  settings.type_filter = type(settings.type_filter) == "table" and settings.type_filter or {}
  r.ImGui_Text(ctx, "Ordering")
  if state.pinned_source == "shared" then
    local changed, pinned_on_top = r.ImGui_Checkbox(ctx, "Pinned on top", settings.show_pinned_on_top ~= false)
    if changed then
      settings.show_pinned_on_top = pinned_on_top
      save_filter_change(app)
    end
  end
  local changed, favorites_on_top = r.ImGui_Checkbox(ctx, "Favorites on top", settings.show_favorites_on_top == true)
  if changed then
    settings.show_favorites_on_top = favorites_on_top
    save_filter_change(app)
  end
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Display")
  local click_changed, double_click_insert = r.ImGui_Checkbox(ctx, "Double-click inserts FX", settings.double_click_insert == true)
  if click_changed then
    settings.double_click_insert = double_click_insert
    if app.save_settings then app.save_settings() end
  end
  local return_changed, return_to_rack = r.ImGui_Checkbox(ctx, "Return to Rack after add", settings.return_to_rack_after_add == true)
  if return_changed then
    settings.return_to_rack_after_add = return_to_rack
    if app.save_settings then app.save_settings() end
  end
  local chain_return_changed, return_to_chain_builder = r.ImGui_Checkbox(ctx, "Return to Chain Builder after add", settings.return_to_chain_builder_after_add == true)
  if chain_return_changed then
    settings.return_to_chain_builder_after_add = return_to_chain_builder
    if app.save_settings then app.save_settings() end
  end
  local dropdown_changed, dropdown_rows = r.ImGui_SliderInt(ctx, "Dropdown rows", settings.dropdown_rows or defaults.dropdown_rows, 8, 36, "%d")
  if dropdown_changed then
    settings.dropdown_rows = dropdown_rows
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Sort")
  if settings.sort_mode == "type_priority" then settings.sort_mode = "name" end
  local sort_label = settings.sort_mode == "rating" and "Rating" or "Name"
  if r.ImGui_Button(ctx, sort_label, 150, 0) then
    settings.sort_mode = settings.sort_mode == "name" and state.rating_source == "shared" and "rating" or "name"
    save_filter_change(app)
  end
  if r.ImGui_IsItemHovered(ctx) then
    local tooltip = state.rating_source == "shared" and "Name or Rating; type priority can hide duplicates" or "Name; type priority can hide duplicates"
    r.ImGui_SetTooltip(ctx, tooltip)
  end
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Types")
  local changed, value = r.ImGui_Checkbox(ctx, "Show x86", settings.show_x86 ~= false)
  if changed then
    settings.show_x86 = value
    save_filter_change(app)
  end
  r.ImGui_Separator(ctx)
  for _, plugin_type_name in ipairs(plugin_types) do
    changed, value = r.ImGui_Checkbox(ctx, plugin_type_name, settings.type_filter[plugin_type_name] ~= false)
    if changed then
      settings.type_filter[plugin_type_name] = value
      save_filter_change(app)
    end
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "All types") then
    settings.show_x86 = true
    for _, plugin_type_name in ipairs(plugin_types) do settings.type_filter[plugin_type_name] = true end
    save_filter_change(app)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Hide x86") then
    settings.show_x86 = false
    save_filter_change(app)
  end
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Type priority")
  local priority_changed, use_type_priority = r.ImGui_Checkbox(ctx, "Use type priority", settings.use_type_priority ~= false)
  if priority_changed then
    settings.use_type_priority = use_type_priority
    save_filter_change(app)
  end
  for index, plugin_type_name in ipairs(settings.type_priority or defaults.type_priority) do
    r.ImGui_PushID(ctx, "prio_" .. tostring(index))
    if r.ImGui_Button(ctx, "U", 22, 0) and index > 1 then
      settings.type_priority[index], settings.type_priority[index - 1] = settings.type_priority[index - 1], settings.type_priority[index]
      save_filter_change(app)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move up") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "D", 22, 0) and index < #settings.type_priority then
      settings.type_priority[index], settings.type_priority[index + 1] = settings.type_priority[index + 1], settings.type_priority[index]
      save_filter_change(app)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move down") end
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, tostring(index) .. ". " .. plugin_type_name)
    r.ImGui_PopID(ctx)
  end
  if r.ImGui_Button(ctx, "Reset priority", 150, 0) then
    settings.type_priority = copy_default(defaults.type_priority)
    save_filter_change(app)
  end
  r.ImGui_EndPopup(ctx)
end

local function draw_row_screenshot(ctx, draw_list, settings, plugin, x, y, width, height)
  if not settings.show_screenshots then return end
  local image = get_screenshot_image(ctx, plugin)
  if image then
    local image_w, image_h = r.ImGui_Image_GetSize(image)
    local scale = math.min(width / image_w, height / image_h)
    local draw_w = image_w * scale
    local draw_h = image_h * scale
    local draw_x = x + (width - draw_w) * 0.5
    local draw_y = y + (height - draw_h) * 0.5
    r.ImGui_DrawList_AddImage(draw_list, image, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, 0xFFFFFFFF)
  else
    local label = plugin.type or "FX"
    local text_w = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, 3, 0, 1)
    r.ImGui_DrawList_AddText(draw_list, x + (width - text_w) * 0.5, y + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, label)
  end
end

local function draw_plugin_row(app, settings, plugin, index, row_width)
  local ctx = app.ctx
  r.ImGui_PushID(ctx, "pb_" .. tostring(index))
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local width = math.max(40, row_width or 180)
  local row_h = row_height
  local gap = 6
  local show_shot = settings.show_screenshots and width >= 170
  local show_type = width >= 150
  local show_add = width >= 120
  local shot_w = show_shot and 60 or 0
  local marker_w = width >= 220 and 58 or 24
  local add_w = show_add and 26 or 0
  local type_w = show_type and 42 or 0
  local right_w = (show_add and (add_w + gap) or 0) + (show_type and (type_w + gap) or 0)
  local name_w = math.max(24, width - shot_w - marker_w - gap - right_w)
  local clicked = r.ImGui_InvisibleButton(ctx, "##row", width, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double_clicked = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local selected = is_plugin_selected(plugin)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local center_y = y + (row_h - 22) * 0.5
  if selected then
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + row_h, 0x7AA2F724, 3)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + row_h, Theme.colors.accent, 3, 0, 1.5)
  end
  if hovered then r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + row_h, 0xFFFFFF10, 3) end
  if show_shot then
    draw_row_screenshot(ctx, draw_list, settings, plugin, x, y + 4, 54, 32)
  end
  local dot_x = x + shot_w + 7
  draw_favorite_dot(draw_list, plugin, dot_x, y + row_h * 0.5, 4)
  draw_pinned_marker(draw_list, plugin, dot_x + 12, y + row_h * 0.5, 4)
  if width >= 220 then draw_rating_label(ctx, draw_list, plugin, dot_x + 24, center_y + 2) end
  local name_x = x + shot_w + marker_w + gap
  local display_name = truncate_text(ctx, plugin.display_name, name_w - 4)
  r.ImGui_DrawList_AddText(draw_list, name_x, center_y + 2, Theme.colors.text, display_name)
  if show_add then
    local add_x = x + width - right_w
    r.ImGui_DrawList_AddRect(draw_list, add_x, center_y, add_x + add_w, center_y + 22, 0x8F9AA866, 3, 0, 1)
    r.ImGui_DrawList_AddText(draw_list, add_x + 8, center_y + 2, Theme.colors.text, "+")
  end
  if show_type then
    local type_label = truncate_text(ctx, plugin.type, type_w)
    r.ImGui_DrawList_AddText(draw_list, x + width - type_w, center_y + 2, Theme.colors.text_dim, type_label)
  end
  if clicked or double_clicked then handle_plugin_click(app, settings, plugin, index, double_clicked) end
  register_external_drag_source(ctx, settings, plugin, index, hovered)
  if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
    r.ImGui_SetDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN", plugin.name)
    r.ImGui_Text(ctx, drag_plugins_label(drag_plugins_for(plugin)))
    r.ImGui_EndDragDropSource(ctx)
  end
  if hovered then r.ImGui_SetTooltip(ctx, plugin.name .. (selected and selection_count() > 1 and ("\n" .. tostring(selection_count()) .. " FX selected") or "")) end
  draw_plugin_context_menu(app, settings, plugin, "##plugin_context")
  r.ImGui_PopID(ctx)
end

local function draw_uniform_card(app, settings, plugin, index, cell_w, cell_h, label_h)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local bg = Theme.colors.frame_bg
  local border = Theme.colors.border
  local hover = Theme.colors.accent
  r.ImGui_PushID(ctx, "pb_uniform_" .. tostring(index))
  label_h = label_h or (r.ImGui_GetTextLineHeight(ctx) + 8)
  local total_h = cell_h + label_h
  local clicked = r.ImGui_InvisibleButton(ctx, "##uniform_card", cell_w, total_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double_clicked = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local selected = is_plugin_selected(plugin)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  if selected then r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + cell_w, y + total_h, 0x7AA2F718, 4) end
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + cell_w, y + cell_h, bg, 4)
  if settings.show_screenshots then
    local image = get_screenshot_image(ctx, plugin)
    if image then
      local image_w, image_h = r.ImGui_Image_GetSize(image)
      if image_w and image_h and image_w > 0 and image_h > 0 then
        local inset = 8
        local inner_w = cell_w - inset * 2
        local inner_h = cell_h - inset * 2
        local scale = math.min(inner_w / image_w, inner_h / image_h)
        local draw_w = image_w * scale
        local draw_h = image_h * scale
        local draw_x = x + inset + (inner_w - draw_w) * 0.5
        local draw_y = y + inset + (inner_h - draw_h) * 0.5
        r.ImGui_DrawList_AddImage(draw_list, image, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, 0xFFFFFFFF)
      end
    else
      local text = "No Image"
      local text_w = r.ImGui_CalcTextSize(ctx, text)
      r.ImGui_DrawList_AddText(draw_list, x + (cell_w - text_w) * 0.5, y + (cell_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, text)
    end
  else
    local text = plugin.type or "FX"
    local text_w = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(draw_list, x + (cell_w - text_w) * 0.5, y + (cell_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, text)
  end
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + cell_w, y + cell_h, hovered and hover or border, 4, 0, hovered and 2 or 1.5)
  if selected then r.ImGui_DrawList_AddRect(draw_list, x, y, x + cell_w, y + total_h, Theme.colors.accent, 4, 0, 2.0) end
  draw_type_badge(ctx, draw_list, plugin, x, y, cell_w)
  draw_favorite_dot(draw_list, plugin, x + 10, y + 10, 5)
  draw_pinned_marker(draw_list, plugin, x + 23, y + 10, 5)
  draw_rating_label(ctx, draw_list, plugin, x + 8, y + cell_h - 22, 7)
  local display_name = truncate_text(ctx, plugin.display_name, cell_w - 8)
  local name_w = r.ImGui_CalcTextSize(ctx, display_name)
  r.ImGui_DrawList_AddText(draw_list, x + (cell_w - name_w) * 0.5, y + cell_h + 4, Theme.colors.text, display_name)
  if clicked or double_clicked then handle_plugin_click(app, settings, plugin, index, double_clicked) end
  register_external_drag_source(ctx, settings, plugin, index, hovered)
  draw_plugin_context_menu(app, settings, plugin, "##plugin_context")
  if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
    r.ImGui_SetDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN", plugin.name)
    r.ImGui_Text(ctx, drag_plugins_label(drag_plugins_for(plugin)))
    r.ImGui_EndDragDropSource(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, plugin.name .. (selected and selection_count() > 1 and ("\n" .. tostring(selection_count()) .. " FX selected") or "")) end
  r.ImGui_PopID(ctx)
end

local function visible_range(ctx, item_count, item_height, buffer)
  if item_count <= 0 then return 1, 0, 0, 0 end
  local scroll_y = r.ImGui_GetScrollY(ctx)
  local window_h = r.ImGui_GetWindowHeight(ctx)
  local first = math.min(item_count, math.max(1, math.floor(scroll_y / item_height) + 1 - buffer))
  local last = math.min(item_count, math.ceil((scroll_y + window_h) / item_height) + buffer)
  if last < first then last = first end
  local top_pad = (first - 1) * item_height
  local bottom_pad = math.max(0, (item_count - last) * item_height)
  return first, last, top_pad, bottom_pad
end

local function draw_virtual_list(app, settings, row_width)
  local ctx = app.ctx
  local first, last, top_pad, bottom_pad = visible_range(ctx, #state.filtered, row_height, 6)
  if top_pad > 0 then r.ImGui_Dummy(ctx, 1, top_pad) end
  for index = first, last do
    local plugin = state.filtered[index]
    if plugin then draw_plugin_row(app, settings, plugin, index, row_width) end
  end
  if bottom_pad > 0 then r.ImGui_Dummy(ctx, 1, bottom_pad) end
end

local function draw_virtual_tiles(app, settings, avail_w)
  local ctx = app.ctx
  local padding = 0
  local gap = 10
  local usable_w = math.max(1, avail_w - padding * 2)
  local preferred_w = math.max(112, math.min(150, tonumber(settings.screenshot_size) or 126))
  local columns = math.max(1, math.floor((usable_w + gap) / (preferred_w + gap)))
  local cell_w = math.floor((usable_w - (columns - 1) * gap) / columns)
  local cell_h = math.floor(cell_w * uniform_ratio)
  local label_h = r.ImGui_GetTextLineHeight(ctx) + 8
  local item_h = cell_h + label_h + gap
  local row_count = math.ceil(#state.filtered / columns)
  local first_row, last_row, top_pad, bottom_pad = visible_range(ctx, row_count, item_h, 3)
  if top_pad > 0 then r.ImGui_Dummy(ctx, 1, top_pad) end
  local start_x = r.ImGui_GetCursorPosX(ctx)
  for row = first_row, last_row do
    r.ImGui_SetCursorPosX(ctx, start_x + padding)
    for col = 1, columns do
      local index = (row - 1) * columns + col
      local plugin = state.filtered[index]
      if not plugin then break end
      draw_uniform_card(app, settings, plugin, index, cell_w, cell_h, label_h)
      if col < columns and state.filtered[index + 1] then
        r.ImGui_SameLine(ctx, 0, gap)
      end
    end
    r.ImGui_Dummy(ctx, 1, gap)
  end
  if bottom_pad > 0 then r.ImGui_Dummy(ctx, 1, bottom_pad) end
end

local function draw_toolbar(app, settings, avail_w)
  local ctx = app.ctx
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local mode_label = settings.view_mode == "tiles" and "Uniform" or "List"
  local mode_w = math.max(button_h, r.ImGui_CalcTextSize(ctx, mode_label) + 14)
  local group_kind = group_kind_for_source(settings.source or "All")
  local width = math.max(1, avail_w or 320)
  local source_w = math.min(118, math.max(86, width * 0.22))
  local group_w = group_kind and math.min(168, math.max(104, width * 0.30)) or 0
  local gap = 4
  local min_search_w = 110
  local visible = { source = true, group = group_kind ~= nil, mode = true, screenshots = true, filter = true, rescan = true }
  local hide_order = { "rescan", "filter", "screenshots", "mode", "group", "source" }
  local function item_width(name)
    if name == "source" then return source_w end
    if name == "group" then return group_w end
    if name == "mode" then return mode_w end
    return button_h
  end
  local function total_width(include_overflow)
    local total = 0
    for _, name in ipairs({ "source", "group", "mode", "screenshots", "filter", "rescan" }) do
      if visible[name] then total = total + (total > 0 and gap or 0) + item_width(name) end
    end
    if include_overflow then total = total + (total > 0 and gap or 0) + button_h end
    return total
  end
  local hidden_count = 0
  local index = 1
  while total_width(hidden_count > 0) > width and index <= #hide_order do
    local name = hide_order[index]
    if visible[name] then
      visible[name] = false
      hidden_count = hidden_count + 1
    end
    index = index + 1
  end
  local has_overflow = hidden_count > 0
  local function draw_mode_button(label, w)
    if r.ImGui_Button(ctx, label, w, button_h) then
      settings.view_mode = settings.view_mode == "tiles" and "list" or "tiles"
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, settings.view_mode == "tiles" and "Uniform layout" or "List view") end
  end
  local function draw_screenshot_button(label, w)
    if r.ImGui_Button(ctx, label, w, button_h) then
      settings.show_screenshots = not settings.show_screenshots
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, settings.show_screenshots and "Screenshots on" or "Screenshots off") end
  end
  local function draw_filter_button(label, w)
    if r.ImGui_Button(ctx, label, w, button_h) then r.ImGui_OpenPopup(ctx, "##pb_filter_menu") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Plugin Browser options") end
    draw_filter_popup(ctx, settings, app)
  end
  local function draw_rescan_button(label, w)
    if r.ImGui_Button(ctx, label, w, button_h) then
      load_user_data()
      if load_parser(true) then app.status = "Plugin list rescanned" else app.status = state.load_error or "Plugin rescan failed" end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Rescan plugins") end
  end
  local row_started = false
  local function next_item()
    if row_started then r.ImGui_SameLine(ctx, 0, gap) end
    row_started = true
  end

  if visible.source then
    next_item()
    r.ImGui_PushItemWidth(ctx, source_w)
    draw_source_combo(ctx, settings, app)
    r.ImGui_PopItemWidth(ctx)
  end
  if visible.group and group_kind then
    next_item()
    r.ImGui_PushItemWidth(ctx, group_w)
    draw_group_combo(ctx, settings, app, group_kind)
    r.ImGui_PopItemWidth(ctx)
  end
  if visible.mode then
    next_item()
    draw_mode_button(mode_label, mode_w)
  end
  if visible.screenshots then
    next_item()
    draw_screenshot_button(settings.show_screenshots and "S" or "-", button_h)
  end
  if visible.filter then
    next_item()
    draw_filter_button(has_active_browser_options(settings) and "O*" or "O", button_h)
  end
  if visible.rescan then
    next_item()
    draw_rescan_button("R", button_h)
  end
  if has_overflow then
    next_item()
    if r.ImGui_Button(ctx, "...", button_h, button_h) then r.ImGui_OpenPopup(ctx, "##pb_overflow_menu") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "More controls") end
    if r.ImGui_BeginPopup(ctx, "##pb_overflow_menu") then
      local popup_w = 210
      if not visible.source then
        r.ImGui_PushItemWidth(ctx, popup_w)
        draw_source_combo(ctx, settings, app)
        r.ImGui_PopItemWidth(ctx)
      end
      if not visible.group and group_kind then
        if not visible.source then r.ImGui_Separator(ctx) end
        r.ImGui_PushItemWidth(ctx, popup_w)
        draw_group_combo(ctx, settings, app, group_kind)
        r.ImGui_PopItemWidth(ctx)
      end
      if not visible.mode then
        r.ImGui_Separator(ctx)
        draw_mode_button("View: " .. mode_label, popup_w)
      end
      if not visible.screenshots then
        r.ImGui_Separator(ctx)
        draw_screenshot_button(settings.show_screenshots and "Screenshots: On" or "Screenshots: Off", popup_w)
      end
      if not visible.filter then
        r.ImGui_Separator(ctx)
        draw_filter_button(has_active_browser_options(settings) and "Plugin options *" or "Plugin options", popup_w)
      end
      if not visible.rescan then
        r.ImGui_Separator(ctx)
        draw_rescan_button("Rescan plugins", popup_w)
      end
      r.ImGui_EndPopup(ctx)
    end
  end
  if row_started then r.ImGui_SetCursorPosY(ctx, math.max(0, r.ImGui_GetCursorPosY(ctx))) end
  r.ImGui_PushItemWidth(ctx, width)
  local changed, search = r.ImGui_InputTextWithHint(ctx, "##pb_search", "Search plugins", settings.search_term or "")
  if changed then
    settings.search_term = search
    state.last_filter_key = nil
  end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_Separator(ctx)
end

local function switch_module(app, module_id, label)
  if not app.modules_by_id or not app.modules_by_id[module_id] then
    app.status = label .. " is not loaded"
    return
  end
  app.settings.active_module = module_id
  if app.save_settings then app.save_settings() end
  app.status = "Opened " .. label
end

local function draw_bottom_shortcuts(app, width)
  local ctx = app.ctx
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local gap = 6
  local button_w = math.max(80, ((width or 320) - gap) * 0.5)
  if r.ImGui_Button(ctx, "Rack", button_w, button_h) then switch_module(app, "instrument_rack", "Instrument Rack") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Go to Instrument Rack") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Chain", button_w, button_h) then switch_module(app, "fx_chain_builder", "FX Chain Builder") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Go to FX Chain Builder") end
end

function M.init(app)
  ensure_settings(app)
  load_user_data()
  load_parser(false)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then clear_selection(app) end
  update_external_drag(app, settings)
  state.screenshot_visible_keys = {}
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  draw_toolbar(app, settings, avail_w or 320)
  if not settings.show_screenshots then
    state.screenshot_load_queue = {}
    state.screenshot_load_order = {}
    state.screenshot_load_queued = {}
    trim_screenshot_cache(ctx, 0, true)
  end
  refresh_filter(settings, false)
  local target = get_target_track()
  local shot_status = settings.show_screenshots and (" | shots " .. tostring(state.screenshot_index and state.screenshot_count or "lazy")) or ""
  if settings.show_screenshots then shot_status = shot_status .. " | img " .. tostring(#state.screenshot_cache_order) .. "/" .. tostring(max_screenshot_cache) .. " | queue " .. tostring(#state.screenshot_load_order) end
  if state.screenshot_image_errors > 0 then shot_status = shot_status .. " | image errors " .. tostring(state.screenshot_image_errors) end
  local info_text = track_label(target) .. " | " .. tostring(#state.filtered) .. " / " .. tostring(#state.plugins) .. " | " .. state.source .. parser_group_summary() .. favorites_source_summary() .. shared_data_summary() .. shot_status
  if state.load_error then
    info_text = state.load_error
  end
  local _, remaining_h = r.ImGui_GetContentRegionAvail(ctx)
  local shortcut_h = r.ImGui_GetFrameHeight(ctx) + 6
  local list_h = math.max(120, (remaining_h or avail_h or 360) - UI.info_line_height(ctx) - shortcut_h)
  local child_visible = r.ImGui_BeginChild(ctx, "##pb_results", 0, list_h, 0)
  local ok, err = true, nil
  if child_visible then
    ok, err = pcall(function()
      local results_w = r.ImGui_GetContentRegionAvail(ctx) or avail_w or 320
      if #state.plugins == 0 and not state.load_error then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No plugins loaded")
      elseif settings.view_mode == "tiles" then
        draw_virtual_tiles(app, settings, results_w)
      else
        local row_width = math.max(80, results_w)
        draw_virtual_list(app, settings, row_width)
      end
      if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 0) and not r.ImGui_IsAnyItemHovered(ctx) and not state.dragging_plugin then clear_selection(app) end
    end)
  end
  r.ImGui_EndChild(ctx)
  if not ok then error(err) end
  draw_drag_overlay(app)
  draw_bottom_shortcuts(app, avail_w or 320)
  UI.draw_info_line(ctx, info_text)
  if settings.show_screenshots then process_screenshot_load_queue(ctx) end
end

function M.shutdown(app)
  clear_external_drag()
  state.screenshot_visible_keys = {}
  trim_screenshot_cache(app.ctx, 0, true)
end

return M