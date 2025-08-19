MAX_SUBMENU_WIDTH = 160
FX_LIST_WIDTH = 280
FLT_MAX = 3.402823466e+38
show_settings = false
SHOW_PREVIEW = true
ADD_FX_TO_ITEM = false
old_t = {}
favorite_plugins = {}
old_filter = ""
current_hovered_plugin = nil
is_master_track_selected = false
copied_plugin = nil
last_selected_folder = nil
new_search_performed = false
folder_changed = false

-- TRACK INFO
show_rename_popup = false
new_track_name = ""
show_color_picker = false
current_color = 0
picker_color = {0, 0, 0, 1}
show_add_script_popup = false
userScripts = {}
keep_context_menu_open = false
pinned_menu_pos_x = nil
pinned_menu_pos_y = nil
track_tags = {}
new_tag_buffer = ""
current_tag_window_height = 70

-- TAGS
tag_colors = {}
available_tags = {}
hide_mode = 0

-- SCREENSHOTS
START = false
is_screenshot_visible = false
screenshot_texture = nil
screenshot_width = 0
screenshot_height = 0
is_bulk_screenshot_running = false
STOP_REQUESTED = false
screenshot_database = {}
screenshot_search_results = nil
update_search_screenshots = false
search_texture_cache = {}
texture_load_queue = {}
texture_last_used = {}
screenshot_window_opened = false
show_screenshot_window = false
show_screenshot_settings = true
screenshot_window_interactive = false
screenshot_window_display_size = 200
selected_folder = nil
show_plugin_manager = false
last_viewed_folder = nil
last_selected_track = nil
collapsed_tracks = {}
all_tracks_collapsed = false
SHOULD_CLOSE_SCRIPT = false
IS_COPYING_TO_ALL_TRACKS = false

-- DOCK
dock = 0
change_dock = false

-- PROJECTS
script_path       = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
project_locations = {}
new_location = ""
PROJECTS_INFO_FILE = script_path .. "project_info.txt"
PROJECTS_DIR = reaper.GetProjectPath() .. "\\"
projects = {}
project_search_term = ""
filtered_projects = {}
preview_volume = 1.0
show_project_info = false
current_project_info = nil
selected_project = nil
max_depth = 1  -- Toegevoegd

-- NOTES
notes = {}
-- show_notes = true
notes_height = 100

-- ACTIONS
show_categories = true
show_only_active = false

-- MATRIX
show_matrix_exclusive = false

--custom folders
custom_folder_states = {}
show_plugin_browser = false
selected_custom_folder_for_browse = nil
plugin_search_text = ""
new_custom_folder_name = ""
custom_folders_open = {}
current_folder_context = nil
plugin_input_text = {}
show_rename_folder_popup = false
rename_folder_path = nil
rename_folder_new_name = ""
show_create_folder_popup = false
new_folder_for_plugin = ""
new_folder_name_input = ""
show_create_parent_folder_popup = false
selected_folder_for_parent = nil
selected_folder_name = nil
new_parent_folder_name = ""

-- MISC
needs_font_update = false
selected_plugin = nil
browser_search_term = ""
current_open_folder = nil
ITEMS_PER_BATCH = 30
loaded_items_count = ITEMS_PER_BATCH
last_scroll_position = 0
current_filtered_fx = {} 
was_hidden = false
unique_id_counter = 0
pushed_main_styles = false