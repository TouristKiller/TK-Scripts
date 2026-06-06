local json = require("core.json")

local M = {}

local defaults = {
  active_module = "project_overview",
  split_view_enabled = false,
  split_module = "action_clipboard",
  split_ratio = 0.5,
  rail_width = 62,
  window_width = 430,
  window_height = 760,
  auto_collapse = false,
  auto_collapse_side = "left",
  auto_collapse_delay = 0.6,
  auto_collapse_width = 2,
  auto_collapse_edge_hover_margin = 12,
  auto_collapse_edge_offset = 0,
  auto_collapse_height_mode = "manual",
  auto_collapse_keep_expanded = false,
  show_status = true,
  hide_scrollbars = false,
  tooltips_enabled = true,
  tooltip_delay = 1.0,
  module_order = {},
  theme_preset = "Graphite",
  custom_themes = {},
  custom_theme_name = "My Theme",
  automation_item_manager = {
    enable_loop = false,
    show_lines_only = false,
    move_edit_cursor = false,
    use_time_selection = true,
    show_tooltips = true,
    curve_color = 0x00FF00FF,
    points_color = 0xFFFF00FF
  },
  control_room = {
    min_db = -60,
    max_db = 12,
    show_master = true,
    show_metronome = true,
    show_selected_track = true,
    show_monitor = true,
    monitor_send_index = -1,
    meter_smoothing = 0.35
  },
  instrument_rack = {
    pinned_track_guid = "",
    add_fx_target = "plugin_browser",
    show_screenshots = true,
    screenshot_height = 90,
    show_pinned_params = true,
    show_ab = false,
    tile_compact = false,
    body_collapsed = false
  },
  fx_chain_builder = {
    plugins = {},
    show_screenshots = true,
    thumbnail_height = 86,
    preserve_chunks = true,
    clear_after_commit = false,
    target_mode = "selected_tracks"
  },
  notes = {
    active_context = "project",
    auto_context = true,
    auto_save_interval = 1.0,
    show_empty_contexts = true,
    block_height = 120
  },
  plugin_browser = {
    search_term = "",
    source = "All",
    view_mode = "list",
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
    type_priority = { "CLAP", "VST3", "VST", "JS", "AU", "LV2", "OTHER" },
    type_filter = { VST3 = true, VST = true, CLAP = true, JS = true, AU = true, LV2 = true, OTHER = true },
    group_selection = { all = "", developer = "", category = "", folders = "", custom_folders = "" }
  },
  track_tags = {
    store_mode = "auto",
    preferred_store = "fx_browser",
    auto_reload = true,
    reload_interval = 2.0,
    last_store_path = "",
    show_empty_tracks = true,
    show_tag_colors = true,
    sync_strategy = "manual",
    search_term = "",
    filter_tag = "",
    selected_tags = {}
  },
  media_browser = {
    search_term = "",
    current_location = "",
    last_browse_location = "",
    location_view_mode = "folders",
    auto_selected_category = "All",
    show_audio = true,
    show_midi = true,
    show_video = false,
    show_image = true,
    recursive = true,
    max_scan_files = 2500,
    waveform_height = 128,
    preview_volume = 1.0,
    preview_pitch = 0,
    preview_rate = 1.0,
    tempo_sync = false,
    loop_preview = false,
    auto_play = false,
    auto_play_next = false,
    link_transport = false,
    link_start_from_editcursor = false,
    exclusive_solo_preview = false,
    use_selected_track_for_audio = false,
    use_selected_track_for_midi = false,
    trim_silence_enabled = false,
    trim_silence_threshold_db = -48,
    trim_silence_padding_ms = 8
  }
}

local function copy_table(source)
  local target = {}
  for key, value in pairs(source) do
    if type(value) == "table" then
      target[key] = copy_table(value)
    else
      target[key] = value
    end
  end
  return target
end

local function merge_table(base, override)
  local target = copy_table(base)
  if type(override) ~= "table" then return target end
  for key, value in pairs(override) do
    if type(value) == "table" and type(target[key]) == "table" then
      target[key] = merge_table(target[key], value)
    else
      target[key] = value
    end
  end
  return target
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
end

local function write_file(path, content)
  local file = io.open(path, "w")
  if not file then return false end
  file:write(content)
  file:close()
  return true
end

function M.load(path)
  local config = copy_table(defaults)
  local content = read_file(path)
  if content then
    local ok, decoded = pcall(json.decode, content)
    if ok and type(decoded) == "table" then
      config = merge_table(defaults, decoded)
    else
      M.save(path, config)
    end
  else
    M.save(path, config)
  end
  return config
end

function M.save(path, config)
  local ok, encoded = pcall(json.encode, config)
  if not ok or not encoded then return false end
  return write_file(path, encoded .. "\n")
end

return M