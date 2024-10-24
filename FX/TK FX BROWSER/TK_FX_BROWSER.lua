-- @description TK FX BROWSER
-- @author TouristKiller
-- @version 0.6.4
-- @changelog:
--        * Removed label "user scripts" 
--        * Invisible botton top of Track info bar to switch between normal track and master
--        * Added option to lock the context menu of Track info bar
--
--------------------------------------------------------------------------
local r                 = reaper
local script_path       = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator      = package.config:sub(1, 1)
package.path            = script_path .. "?.lua;"
local json              = require("json")
local screenshot_path   = script_path .. "Screenshots" .. os_separator
------ SEXAN FX BROWSER PARSER V7 ----------------------------------------
function ThirdPartyDeps()
    local fx_browser = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
    local fx_browser_reapack = '"sexan fx browser parser v7"'
    local reapack_process
    local repos = {
        { name = "Sexan_Scripts",   url = 'https://github.com/GoranKovac/ReaScripts/raw/master/index.xml' }
    }
    for i = 1, #repos do
        local retinfo, url, enabled, autoInstall = r.ReaPack_GetRepositoryInfo(repos[i].name)
        if not retinfo then
            retval, error = r.ReaPack_AddSetRepository(repos[i].name, repos[i].url, true, 0)
            reapack_process = true
        end
    end
    if reapack_process then
        r.ShowMessageBox("Added Third-Party ReaPack Repositories", "ADDING REPACK REPOSITORIES", 0)
        r.ReaPack_ProcessQueue(true)
        reapack_process = nil
    end
    if not reapack_process then
        local deps = {}
        if not r.ImGui_GetBuiltinPath then
           deps[#deps + 1] = '"Dear Imgui"'
        end
        if r.file_exists(fx_browser) then
            dofile(fx_browser)
        else
            deps[#deps + 1] = fx_browser_reapack
        end        
        if #deps ~= 0 then
            r.ShowMessageBox("Need Additional Packages.\nPlease Install it in next window", "MISSING DEPENDENCIES", 0)
            r.ReaPack_BrowsePackages(table.concat(deps, " OR "))
            return true
        end
    end
end
if ThirdPartyDeps() then return end
local fx_browser = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
if r.file_exists(fx_browser) then
    dofile(fx_browser)
else
    error("Sexan FX Browser Parser not found. Please run the script again to install dependencies.")
end
--------------------------------------------------------------------------
-- GUI
local ctx = r.ImGui_CreateContext('TK FX BROWSER')
local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar()
local NormalFont = r.ImGui_CreateFont('sans-serif', 12, r.ImGui_FontFlags_Bold())
r.ImGui_Attach(ctx, NormalFont)
local LargeFont = r.ImGui_CreateFont('sans-serif', 16, r.ImGui_FontFlags_Bold())
r.ImGui_Attach(ctx, LargeFont)
local TinyFont = r.ImGui_CreateFont('sans-serif', 10)
r.ImGui_Attach(ctx, TinyFont)
local IconFont = r.ImGui_CreateFont(script_path .. 'Icons-Regular.otf', 12)
r.ImGui_Attach(ctx, IconFont)
local MAX_SUBMENU_WIDTH = 160
local FX_LIST_WIDTH = 280
local FLT_MAX = 3.402823466e+38
-- GLOBAl
local show_settings = false
local SHOW_PREVIEW = true
local TRACK, LAST_USED_FX, FILTER, ADDFX_Sel_Entry
local FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = ReadFXFile()
if not FX_LIST_TEST or not CAT_TEST or not FX_DEV_LIST_FILE then
    FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = MakeFXFiles()
end
local PLUGIN_LIST = GetFXTbl()
local ADD_FX_TO_ITEM = false
local old_t = {}
local favorite_plugins = {}
local old_filter = ""
local current_hovered_plugin = nil
local is_master_track_selected = false
local copied_plugin = nil
local last_selected_folder = nil
local new_search_performed = false
local folder_changed = false
-- TRACK INFO
local show_rename_popup = false
local new_track_name = ""
local show_color_picker = false
local current_color = 0
local picker_color = {0, 0, 0, 1}
local show_add_script_popup = false
local userScripts = {}
local keep_context_menu_open = false
local pinned_menu_pos_x, pinned_menu_pos_y = nil, nil
-- PROJECTS
local function GetProjectsDirectory()
    local path = reaper.GetProjectPath("")
    if path ~= "" then
        path = path:match("(.*[/\\])")
    else
        path = reaper.GetResourcePath() .. "/Projects/"
    end
    return path
end
PROJECTS_DIR = GetProjectsDirectory()
local PROJECTS_INFO_FILE = PROJECTS_DIR .. "projects_info.txt"
local projects = {}
local project_search_term = ""
local filtered_projects = {}
-- SCREENSHOTS
local is_screenshot_visible = false
local screenshot_texture = nil
local screenshot_width, screenshot_height = 0, 0
local is_bulk_screenshot_running = false
local STOP_REQUESTED = false
local screenshot_database = {} 
local screenshot_search_results = nil
local update_search_screenshots = false
local search_texture_cache = {}
local texture_load_queue = {}
local texture_last_used = {}
local screenshot_window_opened = false 
local show_screenshot_window = false 
local screenshot_window_interactive = false 
local screenshot_window_display_size = 200
local selected_folder = nil
local show_plugin_manager = false
local last_viewed_folder = nil
local last_selected_track = nil
local collapsed_tracks = {}
local all_tracks_collapsed = false
local SHOULD_CLOSE_SCRIPT = false
local IS_COPYING_TO_ALL_TRACKS = false
local function get_safe_name(name)
    return (name or ""):gsub("[^%w%s-]", "_")
end
-- DOCK
local dock = 0
local change_dock = false
-- LOG
local log_file_path = script_path .. "screenshot_log.txt"
local function log_to_file(message)
    local file = io.open(log_file_path, "a")
    if file then
        file:write(message .. "\n")
        file:close()
    end
end
--------------------------------------------------------------------------
-- CONFIG
local function SetDefaultConfig()
    return {
        srcx = 0,
        srcy = 27,
        capture_height_offset = 0,
        screenshot_display_size = 200,
        screenshot_window_width = 200,
        screenshot_window_size = 200,
        use_global_screenshot_size = false,
        global_screenshot_size = 200,
        dropdown_menu_length = 20,
        max_textures_per_frame = 15,
        max_cached_search_textures = 100,
        min_cached_textures = 25,
        texture_reload_delay = 2,
        window_alpha = 0.9,
        text_gray = 200,  
        background_gray = 28,
        background_color = r.ImGui_ColorConvertDouble4ToU32(28/255, 28/255, 28/255, 1),
        button_background_gray = 51,
        button_background_color = r.ImGui_ColorConvertDouble4ToU32(51/255, 51/255, 51/255, 1),
        button_hover_gray = 61,
        button_hover_color = r.ImGui_ColorConvertDouble4ToU32(61/255, 61/255, 61/255, 1),
        frame_bg_gray = 51,
        frame_bg_color = r.ImGui_ColorConvertDouble4ToU32(51/255, 51/255, 51/255, 1),
        frame_bg_hover_gray = 61,
        frame_bg_hover_color = r.ImGui_ColorConvertDouble4ToU32(61/255, 61/255, 61/255, 1),
        frame_bg_active_gray = 71,
        frame_bg_active_color = r.ImGui_ColorConvertDouble4ToU32(71/255, 71/255, 71/255, 1),
        dropdown_bg_gray = 51,
        dropdown_bg_color = r.ImGui_ColorConvertDouble4ToU32(51/255, 51/255, 51/255, 1),
        tab_gray = 71,
        tab_color = r.ImGui_ColorConvertDouble4ToU32(71/255, 71/255, 71/255, 1),
        tab_hovered_gray = 91,
        tab_hovered_color = r.ImGui_ColorConvertDouble4ToU32(91/255, 91/255, 91/255, 1),
        auto_refresh_fx_list = false,
        show_screenshot_in_search = false,
        show_screenshot_window = true,
        resize_screenshots_with_window = false,
        dock_screenshot_window = false, 
        dock_screenshot_left = true,
        default_folder = nil,
        show_all_plugins = true,
        show_developer = true,
        show_folders = true,
        show_fx_chains = true,
        show_track_templates = true,
        show_category = true,
        show_container = true,
        show_video_processor = true,
        show_favorites = true,
        show_projects = true,
        bulk_screenshot_vst = true,
        bulk_screenshot_vst3 = true,
        bulk_screenshot_js = true,
        bulk_screenshot_au = true,
        bulk_screenshot_clap = true,
        bulk_screenshot_lv2 = true,
        bulk_screenshot_vsti = true,  
        bulk_screenshot_vst3i = true, 
        bulk_screenshot_jsi = true,   
        bulk_screenshot_aui = true,   
        bulk_screenshot_clapi = true, 
        bulk_screenshot_lv2i = true,  
        default_folder = nil,
        screenshot_size_option = 2, -- 1 = 128x128, 2 = 500x(to scale), 3 = original
        screenshot_default_folder_only = false,
        close_after_adding_fx = false,
        folder_specific_sizes = {},
        include_x86_bridged = false,
        hide_default_titlebar_menu_items = false,
        show_name_in_screenshot_window = true,
        show_name_in_main_window = true,
        hidden_names = {},
        excluded_plugins = {},
        plugin_visibility = {},
        show_tooltips = true,
        hideBottomButtons = false,
        hideTopButtons = false,
    } 
end
local config = SetDefaultConfig()    
local window_alpha_int = math.floor(config.window_alpha * 100)  
local function SaveConfig()
    local file = io.open(script_path .. "config.json", "w")
    if file then
        file:write(json.encode(config))
        file:close()
    end
end

local function LoadConfig()
    local file = io.open(script_path .. "config.json", "r")
    if file then
        local content = file:read("*all")
        file:close()
        local loaded_config = json.decode(content)
        for k, v in pairs(loaded_config) do
            config[k] = v
        end
        config.folder_specific_sizes = loaded_config.folder_specific_sizes or {}
    else
        SetDefaultConfig()
    end
end
LoadConfig()
local function ResetConfig()
    config = SetDefaultConfig()
    SaveConfig()
end

local function SaveFavorites()
    local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
    local file = io.open(script_path .. "favorite_plugins.txt", "w")
    if file then
        for _, fav in ipairs(favorite_plugins) do
            file:write(fav .. "\n")
        end
        file:close()
    end
end

local function LoadFavorites()
    local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
    local file = io.open(script_path .. "favorite_plugins.txt", "r")
    if file then
        for line in file:lines() do
            table.insert(favorite_plugins, line)
        end
        file:close()
    end
end
LoadFavorites()
--------------------------------------------------------------------------
function table.contains(tbl, item)
    for _, value in pairs(tbl) do
        if value == item then
            return true
        end
    end
    return false
end
local function ClearScreenshotCache(periodic_cleanup)
    local current_time = r.time_precise()
    
    if periodic_cleanup then
        local to_remove = {}
        for key, last_used in pairs(texture_last_used) do
            if current_time - last_used > 300 then -- 5 minuten timeout
                table.insert(to_remove, key)
            end
        end
        for _, key in ipairs(to_remove) do
            if search_texture_cache[key] and r.ImGui_DestroyImage then
                r.ImGui_DestroyImage(ctx, search_texture_cache[key])
            end
            search_texture_cache[key] = nil
            texture_last_used[key] = nil
            texture_load_queue[key] = nil
        end
    else
        -- Volledige cache wissen
        if r.ImGui_DestroyImage then
            for key, texture in pairs(search_texture_cache) do
                r.ImGui_DestroyImage(ctx, texture)
            end
        end
        search_texture_cache = {}
        texture_last_used = {}
        texture_load_queue = {}
    end
end

local folders_category = {}
local function initFoldersCategory()
    for i = 1, #CAT_TEST do
        if CAT_TEST[i].name == "FOLDERS" then
            folders_category = CAT_TEST[i].list
            break
        end
    end
end
initFoldersCategory()

local function UpdateLastViewedFolder(new_folder)
    if new_folder ~= "Current Project FX" then
        last_viewed_folder = new_folder
    end
end

function IsPluginVisible(plugin_name)
    return config.plugin_visibility[plugin_name] ~= false
end

local function GetTrackName(track)
    if not track then return "No Track Selected" end
    if track == r.GetMasterTrack(0) then return "Master Track" end
    local _, name = r.GetTrackName(track)
    return name
end

local function GetCurrentProjectFX()
    local fx_list = {}
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track)
        local track_number = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        local track_color = reaper.GetTrackColor(track)
        local fx_count = reaper.TrackFX_GetCount(track)
        for j = 0, fx_count - 1 do
            local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
            if retval then
                table.insert(fx_list, {
                    fx_name = fx_name,
                    track_name = track_name,
                    track_number = track_number,
                    track_color = track_color
                })
            end
        end
    end
    return fx_list
end

local function GetCurrentTrackFX()
    local fx_list = {}
    if TRACK then
        local fx_count = reaper.TrackFX_GetCount(TRACK)
        for j = 0, fx_count - 1 do
            local retval, fx_name = reaper.TrackFX_GetFXName(TRACK, j, "")
            if retval then
                table.insert(fx_list, {fx_name = fx_name, track_name = GetTrackName(TRACK)})
            end
        end
    end
    return fx_list
end

local search_filter = ""
local filtered_plugins = {}
local function InitializeFilteredPlugins()
    for _, plugin_name in ipairs(PLUGIN_LIST) do
        table.insert(filtered_plugins, {
            name = plugin_name, 
            visible = config.plugin_visibility[plugin_name] ~= false,
            searchable = not config.excluded_plugins[plugin_name]
        })
    end
    table.sort(filtered_plugins, function(a, b) return a.name:lower() < b.name:lower() end)
end

local CHECKBOX_WIDTH = 15
local last_clicked_plugin_index = nil
local last_clicked_column = nil  -- 1 voor Bulk, 2 voor Search
local function ShowPluginManagerTab()
    if #filtered_plugins == 0 then
        InitializeFilteredPlugins()
    end
    local changed, new_search_filter = r.ImGui_InputText(ctx, "Search plugins", search_filter)
    if changed then
        search_filter = new_search_filter
        filtered_plugins = {}
        for _, plugin in ipairs(PLUGIN_LIST) do
            if search_filter == "" or string.find(string.lower(plugin), string.lower(search_filter)) then
                table.insert(filtered_plugins, {
                    name = plugin, 
                    visible = config.plugin_visibility[plugin] ~= false,
                    searchable = not config.excluded_plugins[plugin]
                })
            end
        end
        table.sort(filtered_plugins, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    r.ImGui_Text(ctx, string.format("Total plugins: %d", #PLUGIN_LIST))
    r.ImGui_Text(ctx, string.format("Shown plugins: %d", #filtered_plugins))
    
    if r.ImGui_BeginChild(ctx, "PluginList", 0, -60) then
        local window_width = r.ImGui_GetWindowWidth(ctx)
        local column1_width = 50  -- Voor "Bulk" checkbox
        local column2_width = 50  -- Voor "Search" checkbox
        local column3_width = window_width - column1_width - column2_width - 20  -- Voor plugin naam

        -- Koppen
        r.ImGui_SetCursorPosX(ctx, column1_width / 2 - r.ImGui_CalcTextSize(ctx, "Bulk") / 2)
        r.ImGui_Text(ctx, "Bulk")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column1_width + column2_width / 2 - r.ImGui_CalcTextSize(ctx, "Search") / 2)
        r.ImGui_Text(ctx, "Search")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column1_width + column2_width + 10)
        r.ImGui_Text(ctx, "Plugin Name")
        
        r.ImGui_Separator(ctx)

        for i, plugin in ipairs(filtered_plugins) do
            r.ImGui_SetCursorPosX(ctx, (column1_width - 15) / 2)
            
            -- Bulk checkbox
            local checkbox_visible_changed, new_visible = r.ImGui_Checkbox(ctx, "##Visible"..plugin.name, config.plugin_visibility[plugin.name])
            if checkbox_visible_changed then
                if r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) and last_clicked_plugin_index and last_clicked_column == 1 then
                    local start_idx = math.min(i, last_clicked_plugin_index)
                    local end_idx = math.max(i, last_clicked_plugin_index)
                    for j = start_idx, end_idx do
                        config.plugin_visibility[filtered_plugins[j].name] = new_visible
                    end
                else
                    config.plugin_visibility[plugin.name] = new_visible
                end
                last_clicked_plugin_index = i
                last_clicked_column = 1
                SaveConfig()
            end
            
            r.ImGui_SameLine(ctx)
            
            -- Search checkbox
            r.ImGui_SetCursorPosX(ctx, column1_width + (column2_width - 15) / 2)
            local checkbox_searchable_changed, new_searchable = r.ImGui_Checkbox(ctx, "##Searchable"..plugin.name, not config.excluded_plugins[plugin.name])
            if checkbox_searchable_changed then
                if r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) and last_clicked_plugin_index and last_clicked_column == 2 then
                    local start_idx = math.min(i, last_clicked_plugin_index)
                    local end_idx = math.max(i, last_clicked_plugin_index)
                    for j = start_idx, end_idx do
                        config.excluded_plugins[filtered_plugins[j].name] = not new_searchable
                    end
                else
                    config.excluded_plugins[plugin.name] = not new_searchable
                end
                last_clicked_plugin_index = i
                last_clicked_column = 2
                SaveConfig()
            end
            r.ImGui_SameLine(ctx)
            
            r.ImGui_SetCursorPosX(ctx, column1_width + column2_width + 10)
            r.ImGui_Text(ctx, plugin.name)
        end
        r.ImGui_EndChild(ctx)
    end
    local button_width = (r.ImGui_GetWindowWidth(ctx) - 15) / 2
    if r.ImGui_Button(ctx, "Select All for Bulk", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.plugin_visibility[plugin.name] = true
        end
        SaveConfig()
    end

    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Deselect All for Bulk", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.plugin_visibility[plugin.name] = false
        end
        SaveConfig()
    end
    local button_width = (r.ImGui_GetWindowWidth(ctx) - 15) / 2  -- Bereken de breedte voor twee knoppen
    
    if r.ImGui_Button(ctx, "Select All for Search", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.excluded_plugins[plugin.name] = nil
        end
        SaveConfig()
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, "Deselect All for Search", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.excluded_plugins[plugin.name] = true
        end
        SaveConfig()
    end
end

local function GetPluginsForFolder(folder_name)
    local filtered_plugins = {}
    for i = 1, #CAT_TEST do
        if CAT_TEST[i].name == "FOLDERS" then
            for j = 1, #CAT_TEST[i].list do
                if CAT_TEST[i].list[j].name == folder_name then
                    return CAT_TEST[i].list[j].fx
                end
            end
        end
    end
    return filtered_plugins
end

local function ShowConfigWindow()
    local config_open = true
    local window_width = 480
    local window_height = 760
    local column1_width = 10
    local column2_width = 120
    local column3_width = 250
    local column4_width = 360
    local slider_width = 110
    r.ImGui_SetNextWindowSize(ctx, window_width, window_height, r.ImGui_Cond_Always())
    r.ImGui_SetNextWindowSizeConstraints(ctx, window_width, window_height, window_width, window_height)
    local visible, open = r.ImGui_Begin(ctx, "Settings", true, window_flags | r.ImGui_WindowFlags_NoResize())
    if visible then
        r.ImGui_PushFont(ctx, LargeFont)
        r.ImGui_Text(ctx, "TK FX BROWSER SETTINGS")
        r.ImGui_PopFont(ctx)
        r.ImGui_Separator(ctx)
        if r.ImGui_BeginTabBar(ctx, "SettingsTabs") then
            if r.ImGui_BeginTabItem(ctx, "GENERAL") then

        local function NewSection(title)
            r.ImGui_Spacing(ctx)
            r.ImGui_PushFont(ctx, NormalFont)
            r.ImGui_Text(ctx, title)
            r.ImGui_PopFont(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 5)
        NewSection("SCREENSHOT:")

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "X Offset")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.srcx = r.ImGui_SliderInt(ctx, "##X Offset", config.srcx, 0, 500)
        r.ImGui_PopItemWidth(ctx)
       
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Y Offset")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.srcy = r.ImGui_SliderInt(ctx, "##Y Offset", config.srcy, 0, 500)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Height Offset")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.capture_height_offset = r.ImGui_SliderInt(ctx, "##Height Offset", config.capture_height_offset, 0, 500)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Screenshot Size:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local size_options = "128x128 (TrackIcon\0 500x(Scale)\0Original\0\0"
        _, config.screenshot_size_option = r.ImGui_Combo(ctx, "##Size Option", config.screenshot_size_option - 1, size_options)
        config.screenshot_size_option = config.screenshot_size_option + 1
        r.ImGui_PopItemWidth(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Display Size")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.screenshot_display_size = r.ImGui_SliderInt(ctx, "##Display Size", config.screenshot_display_size, 100, 500)
        r.ImGui_PopItemWidth(ctx)
        r.ImGui_Dummy(ctx, 0, 5)
        NewSection("GUI:")

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Background")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed, new_gray = r.ImGui_SliderInt(ctx, "##Background", config.background_gray, 0, 255)
        if changed then
            config.background_gray = new_gray
            config.background_color = r.ImGui_ColorConvertDouble4ToU32(new_gray/255, new_gray/255, new_gray/255, config.window_alpha)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Transparency")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_alpha, new_alpha_int = r.ImGui_SliderInt(ctx, "##Transparency", window_alpha_int, 0, 100, "%d%%")
        if changed_alpha then
            window_alpha_int = new_alpha_int
            config.window_alpha = window_alpha_int / 100
            config.background_color = r.ImGui_ColorConvertDouble4ToU32(config.background_gray/255, config.background_gray/255, config.background_gray/255, config.window_alpha)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Text")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_text, new_text_gray = r.ImGui_SliderInt(ctx, "##Text", config.text_gray, 0, 255)
        if changed_text then
            config.text_gray = new_text_gray
            config.text_color = r.ImGui_ColorConvertDouble4ToU32(new_text_gray/255, new_text_gray/255, new_text_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Dropdown BG")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_dropdown, new_dropdown_gray = r.ImGui_SliderInt(ctx, "##Dropdown BG", config.dropdown_bg_gray, 0, 255)
        if changed_dropdown then
            config.dropdown_bg_gray = new_dropdown_gray
            config.dropdown_bg_color = r.ImGui_ColorConvertDouble4ToU32(new_dropdown_gray/255, new_dropdown_gray/255, new_dropdown_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)
       
        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Button BG")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_button_bg, new_button_bg_gray = r.ImGui_SliderInt(ctx, "##Button BG", config.button_background_gray, 0, 255)
        if changed_button_bg then
            config.button_background_gray = new_button_bg_gray
            config.button_background_color = r.ImGui_ColorConvertDouble4ToU32(new_button_bg_gray/255, new_button_bg_gray/255, new_button_bg_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Button Hover")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_hover, new_hover_gray = r.ImGui_SliderInt(ctx, "##Button Hover", config.button_hover_gray, 0, 255)
        if changed_hover then
            config.button_hover_gray = new_hover_gray
            config.button_hover_color = r.ImGui_ColorConvertDouble4ToU32(new_hover_gray/255, new_hover_gray/255, new_hover_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)
        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Frame BG")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_frame_bg, new_frame_bg_gray = r.ImGui_SliderInt(ctx, "##Frame BG", config.frame_bg_gray, 0, 255)
        if changed_frame_bg then
            config.frame_bg_gray = new_frame_bg_gray
            config.frame_bg_color = r.ImGui_ColorConvertDouble4ToU32(new_frame_bg_gray/255, new_frame_bg_gray/255, new_frame_bg_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Frame Hover")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_frame_hover, new_frame_hover_gray = r.ImGui_SliderInt(ctx, "##Frame Hover", config.frame_bg_hover_gray, 0, 255)
        if changed_frame_hover then
            config.frame_bg_hover_gray = new_frame_hover_gray
            config.frame_bg_hover_color = r.ImGui_ColorConvertDouble4ToU32(new_frame_hover_gray/255, new_frame_hover_gray/255, new_frame_hover_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Frame Active")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_frame_active, new_frame_active_gray = r.ImGui_SliderInt(ctx, "##Frame Active", config.frame_bg_active_gray, 0, 255)
        if changed_frame_active then
            config.frame_bg_active_gray = new_frame_active_gray
            config.frame_bg_active_color = r.ImGui_ColorConvertDouble4ToU32(new_frame_active_gray/255, new_frame_active_gray/255, new_frame_active_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Dropdown Length")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.dropdown_menu_length = r.ImGui_SliderInt(ctx, "##Dropdown Length", config.dropdown_menu_length, 5, 75)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Tab Color")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_tab, new_tab_gray = r.ImGui_SliderInt(ctx, "##Tab Color", config.tab_gray, 0, 255)
        if changed_tab then
            config.tab_gray = new_tab_gray
            config.tab_color = r.ImGui_ColorConvertDouble4ToU32(new_tab_gray/255, new_tab_gray/255, new_tab_gray/255, 1)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Tab Hovered")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        local changed_tab_hovered, new_tab_hovered_gray = r.ImGui_SliderInt(ctx, "##Tab Hovered", config.tab_hovered_gray, 0, 255)
        if changed_tab_hovered then
            config.tab_hovered_gray = new_tab_hovered_gray
            config.tab_hovered_color = r.ImGui_ColorConvertDouble4ToU32(new_tab_hovered_gray/255, new_tab_hovered_gray/255, new_tab_hovered_gray/255, 1)
        end
        
        r.ImGui_Dummy(ctx, 0, 5)
        NewSection("PERFORMANCE:")
        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Max Textures/Frame")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.max_textures_per_frame = r.ImGui_SliderInt(ctx, "##Max Textures/Frame", config.max_textures_per_frame, 1, 30)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Max Cached Textures")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.max_cached_search_textures = r.ImGui_SliderInt(ctx, "##Max Cached Textures", config.max_cached_search_textures, 10, 200)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Min Cached Textures")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.min_cached_textures = r.ImGui_SliderInt(ctx, "##Min Cached Textures", config.min_cached_textures, 5, 50)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        r.ImGui_Text(ctx, "Texture Reload Delay")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        _, config.texture_reload_delay = r.ImGui_SliderInt(ctx, "##Texture Reload Delay", config.texture_reload_delay or 2, 1, 10)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_Dummy(ctx, 0, 5)
        NewSection("VIEW:")
        r.ImGui_SetCursorPosX(ctx, column1_width)
        _, config.show_screenshot_in_search = r.ImGui_Checkbox(ctx, "Show in Search", config.show_screenshot_in_search)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        _, config.resize_screenshots_with_window = r.ImGui_Checkbox(ctx, "Resize with Window", config.resize_screenshots_with_window)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        _, config.show_screenshot_window = r.ImGui_Checkbox(ctx, "Show Window", config.show_screenshot_window)
        r.ImGui_SameLine(ctx)

        r.ImGui_SetCursorPosX(ctx, column4_width)
        _, config.dock_screenshot_window = r.ImGui_Checkbox(ctx, "Dock", config.dock_screenshot_window)
        if config.dock_screenshot_window then

        r.ImGui_SameLine(ctx, 0, 20)
        _, config.dock_screenshot_left = r.ImGui_Checkbox(ctx, "Left", config.dock_screenshot_left)
        end
        r.ImGui_SetCursorPosX(ctx, column1_width)
        _, config.show_name_in_screenshot_window = r.ImGui_Checkbox(ctx, "Show Names in Screenshot Window", config.show_name_in_screenshot_window)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        _, config.show_name_in_main_window = r.ImGui_Checkbox(ctx, "Show Names in Main Window", config.show_name_in_main_window)
        r.ImGui_SetCursorPosX(ctx, column1_width)
        _, config.hide_default_titlebar_menu_items = r.ImGui_Checkbox(ctx, "Hide Default Titlebar Menu Items", config.hide_default_titlebar_menu_items)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        _, config.show_tooltips = r.ImGui_Checkbox(ctx, "Show Tooltips", config.show_tooltips)
        r.ImGui_SetCursorPosX(ctx, column1_width)
        _, config.hideBottomButtons = r.ImGui_Checkbox(ctx, "Hide Bottom Buttons", config.hideBottomButtons)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        _, config.hideTopButtons = r.ImGui_Checkbox(ctx, "Hide Top Bottons", config.hideTopButtons)

       
       
       
        r.ImGui_Dummy(ctx, 0, 5)
                NewSection("BULK:")
                r.ImGui_SetCursorPosX(ctx, column1_width)
                changed, config.bulk_screenshot_vst = r.ImGui_Checkbox(ctx, "VST Plugins", config.bulk_screenshot_vst)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column2_width)
                changed, config.bulk_screenshot_vsti = r.ImGui_Checkbox(ctx, "VSTi Plugins", config.bulk_screenshot_vsti)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column3_width)
                changed, config.bulk_screenshot_vst3 = r.ImGui_Checkbox(ctx, "VST3 Plugins", config.bulk_screenshot_vst3)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column4_width)
                changed, config.bulk_screenshot_vst3i = r.ImGui_Checkbox(ctx, "VST3i Plugins", config.bulk_screenshot_vst3i)
                r.ImGui_SetCursorPosX(ctx, column4_width)
                
                r.ImGui_SetCursorPosX(ctx, column1_width)
                changed, config.bulk_screenshot_au = r.ImGui_Checkbox(ctx, "AU Plugins", config.bulk_screenshot_au)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column2_width)
                changed, config.bulk_screenshot_aui = r.ImGui_Checkbox(ctx, "AUi Plugins", config.bulk_screenshot_aui)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column3_width)
                changed, config.bulk_screenshot_lv2 = r.ImGui_Checkbox(ctx, "LV2 Plugins", config.bulk_screenshot_lv2)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column4_width)
                changed, config.bulk_screenshot_lv2i = r.ImGui_Checkbox(ctx, "LV2i Plugins", config.bulk_screenshot_lv2i)
                
                r.ImGui_SetCursorPosX(ctx, column1_width)
                changed, config.bulk_screenshot_js = r.ImGui_Checkbox(ctx, "JS Plugins", config.bulk_screenshot_js)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column2_width)
                changed, config.bulk_screenshot_clap = r.ImGui_Checkbox(ctx, "CLAP Plugins", config.bulk_screenshot_clap)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column3_width)
                changed, config.bulk_screenshot_clapi = r.ImGui_Checkbox(ctx, "CLAPi Plugins", config.bulk_screenshot_clapi)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, column4_width)
                _, config.screenshot_default_folder_only = r.ImGui_Checkbox(ctx, "Default Only", config.screenshot_default_folder_only)

        r.ImGui_Dummy(ctx, 0, 5)
        NewSection("MISC:")
        r.ImGui_SetCursorPosX(ctx, column1_width)
        r.ImGui_Text(ctx, "Default Folder")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        r.ImGui_PushItemWidth(ctx, slider_width)
        r.ImGui_SetNextWindowSizeConstraints(ctx, 0, 0, FLT_MAX, config.dropdown_menu_length * r.ImGui_GetTextLineHeightWithSpacing(ctx))
        if r.ImGui_BeginCombo(ctx, "##Default Folder", config.default_folder or "None") then
            if r.ImGui_Selectable(ctx, "None", config.default_folder == nil) then
                config.default_folder = nil
            end
            if r.ImGui_Selectable(ctx, "Favorites", config.default_folder == "Favorites") then
                config.default_folder = "Favorites"
            end
            if r.ImGui_Selectable(ctx, "Current Project FX", config.default_folder == "Current Project FX") then
                config.default_folder = "Current Project FX"
            end
            if r.ImGui_Selectable(ctx, "Current Track FX", config.default_folder == "Current Track FX") then
                config.default_folder = "Current Track FX"
            end
            for i = 1, #folders_category do
                local is_selected = (config.default_folder == folders_category[i].name)
                if r.ImGui_Selectable(ctx, folders_category[i].name, is_selected) then
                    config.default_folder = folders_category[i].name
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then
            local wheel_delta = r.ImGui_GetMouseWheel(ctx)
            if wheel_delta ~= 0 then
                local current_index = 0
                for i, folder in ipairs(folders_category) do
                    if folder.name == config.default_folder then
                        current_index = i
                        break
                    end
                end
                current_index = current_index - wheel_delta
                if current_index < 0 then
                    config.default_folder = nil
                elseif current_index == 0 then
                    config.default_folder = folders_category[1].name
                elseif current_index > #folders_category then
                    config.default_folder = folders_category[#folders_category].name
                else
                    config.default_folder = folders_category[current_index].name
                end
                SaveConfig()
            end
        end
        r.ImGui_PopItemWidth(ctx)

        local changed, new_value
        r.ImGui_SetCursorPosX(ctx, column1_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "All Plugins", config.show_all_plugins)
        if changed then config.show_all_plugins = new_value end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Developer", config.show_developer)
        if changed then config.show_developer = new_value end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Folders", config.show_folders)
        if changed then config.show_folders = new_value end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "FX Chains", config.show_fx_chains)
        if changed then config.show_fx_chains = new_value end
       
        r.ImGui_SetCursorPosX(ctx, column1_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Track Templates", config.show_track_templates)
        if changed then config.show_track_templates = new_value end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Category", config.show_category)
        if changed then config.show_category = new_value end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column3_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Container", config.show_container)
        if changed then config.show_container = new_value end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column4_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Video Processor", config.show_video_processor)
        if changed then config.show_video_processor = new_value end
        r.ImGui_SetCursorPosX(ctx, column1_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Favorites", config.show_favorites)
        if changed then config.show_favorites = new_value end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column2_width)
        changed, new_value = r.ImGui_Checkbox(ctx, "Projects", config.show_projects)
        if changed then config.show_projects = new_value end

        r.ImGui_Separator(ctx)
        _, config.close_after_adding_fx = r.ImGui_Checkbox(ctx, "Close script after adding FX", config.close_after_adding_fx)
        r.ImGui_SameLine(ctx)
        _, config.include_x86_bridged = r.ImGui_Checkbox(ctx, "Include x86 bridged plugins", config.include_x86_bridged)
        r.ImGui_Separator(ctx)
        r.ImGui_SetCursorPosY(ctx, window_height - 30)
        local button_width = (window_width - 20) / 3
        if r.ImGui_Button(ctx, "Save", button_width, 20) then
            SaveConfig()
            config_open = false
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel", button_width, 20) then
            config_open = false
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Reset", button_width, 20) then
            ResetConfig()
        end
        r.ImGui_EndTabItem(ctx)
    end
    if r.ImGui_BeginTabItem(ctx, "PLUGIN MANAGER") then
        ShowPluginManagerTab()
        r.ImGui_EndTabItem(ctx)
    end
    r.ImGui_EndTabBar(ctx)
    end
    r.ImGui_End(ctx)
    end
    return config_open
end
local function EnsureTrackIconsFolderExists()
    local track_icons_path = script_path .. "TrackIcons" .. os_separator
    if not r.file_exists(track_icons_path) then
        local success = r.RecursiveCreateDirectory(track_icons_path, 0)
        if success then
            log_to_file("Made TrackIcons Folder: " .. track_icons_path)
        else
            log_to_file("Error making TrackIcons Folder: " .. track_icons_path)
        end
    end
    return track_icons_path
end
EnsureTrackIconsFolderExists()

local function EnsureScreenshotFolderExists()
    if not r.file_exists(screenshot_path) then
        local success = r.RecursiveCreateDirectory(screenshot_path, 0)
        if success then
            log_to_file("Made screenshot Folder: " .. screenshot_path)
        else
            log_to_file("Error making screenshot Folder: " .. screenshot_path)
        end
    end
end
EnsureScreenshotFolderExists()

local function check_esc_key() 
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        return true
    end
    return false
end

local function handleDocking()
    if change_dock then
        r.ImGui_SetNextWindowDockID(ctx, ~dock)
        change_dock = nil
    end
end

local function IsX86Bridged(plugin_name)
    return plugin_name:find("x86") ~= nil
end

local function ScreenshotExists(plugin_name, size_option)
    if screenshot_database[plugin_name] ~= nil then
        return true
    end

    local safe_name = plugin_name:gsub("[^%w%s-]", "_")
    if size_option == 1 then -- 128x128
        local track_icons_path = script_path .. "TrackIcons" .. os_separator
        local filename = track_icons_path .. safe_name .. ".png"
        return r.file_exists(filename)
    else
        local filename = screenshot_path .. safe_name .. ".png"
        return r.file_exists(filename)
    end
end

local function OpenScreenshotsFolder()
    local os_name = reaper.GetOS()
    if os_name:match("Win") then
        os.execute('start "" "' .. screenshot_path .. '"')
    elseif os_name:match("OSX") then
        os.execute('open "' .. screenshot_path .. '"')
    else
        reaper.ShowMessageBox("Unsupported OS", "Error", 0)
    end
end

-- bodem knoppen
local function IsMuted(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        return r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    end
    return false
end

local function ToggleMute(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local mute = r.GetMediaTrackInfo_Value(track, "B_MUTE")
        r.SetMediaTrackInfo_Value(track, "B_MUTE", mute == 0 and 1 or 0)
    end
end

local function IsSoloed(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        return r.GetMediaTrackInfo_Value(track, "I_SOLO") ~= 0
    end
    return false
end

local function ToggleSolo(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO")
        r.SetMediaTrackInfo_Value(track, "I_SOLO", solo == 0 and 1 or 0)
    end
end

local function ToggleArm(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local armed = r.GetMediaTrackInfo_Value(track, "I_RECARM")
        r.SetMediaTrackInfo_Value(track, "I_RECARM", armed == 0 and 1 or 0)
    end
end

local function IsArmed(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        return r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
    end
    return false
end
-------------
local function AddFXToItem(fx_name)
    local item = r.GetSelectedMediaItem(0, 0)
    if item then
        local take = r.GetActiveTake(item)
        if take then
            r.TakeFX_AddByName(take, fx_name, 1)
        end
    end
end

local function CreateFXChain()
    if not TRACK then return end
    local fx_count = r.TrackFX_GetCount(TRACK)
    if fx_count == 0 then return end
    r.SetOnlyTrackSelected(TRACK)
    r.Main_OnCommand(r.NamedCommandLookup("_S&M_SAVE_FXCHAIN_SLOT1"), 0)
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
    r.ShowMessageBox("FX Chain created successfully!", "Success", 0)
end

local function LoadTexture(file)
    local texture = r.ImGui_CreateImage(file)
    if texture == nil then
        log_to_file("Failed to load texture: " .. file)
    end
    return texture
end
    
local function LoadSearchTexture(file, plugin_name)
    local relative_path = file:gsub(screenshot_path, "")
    local unique_key = relative_path .. "_" .. (plugin_name or "unknown")
    local current_time = r.time_precise()
    if search_texture_cache[unique_key] then
        texture_last_used[unique_key] = current_time
        return search_texture_cache[unique_key]
    end
    if r.file_exists(file) then
        local texture = r.ImGui_CreateImage(file)
        if texture then
            search_texture_cache[unique_key] = texture
            texture_last_used[unique_key] = current_time
            log_to_file("Texture loaded: " .. file .. " for plugin: " .. (plugin_name or "unknown"))
            return texture
        else
            log_to_file("Failed to create texture: " .. file .. " for plugin: " .. (plugin_name or "unknown"))
        end
    else
        log_to_file("File does not exist: " .. file .. " for plugin: " .. (plugin_name or "unknown"))
    end
    return nil
end

local function ProcessTextureLoadQueue()
    local textures_loaded = 0
    local current_time = r.time_precise()
    -- Laad nieuwe textures
    for file, queue_time in pairs(texture_load_queue) do
        if textures_loaded >= config.max_textures_per_frame then break end
        if not search_texture_cache[file] then
            local texture = r.ImGui_CreateImage(file)
            if texture then
                search_texture_cache[file] = texture
                texture_last_used[file] = current_time
                textures_loaded = textures_loaded + 1
                log_to_file("Texture loaded: " .. file)
            else
                log_to_file("Error loading texture: " .. file)
            end
        end
        texture_load_queue[file] = nil
    end
    -- Verwijder oude textures, maar houd een minimum aantal
    local cache_size = 0
    for _ in pairs(search_texture_cache) do cache_size = cache_size + 1 end
    
    if cache_size > config.max_cached_search_textures then
        local textures_to_remove = {}
        for file, last_used in pairs(texture_last_used) do
            if current_time - last_used > config.texture_reload_delay and cache_size > config.min_cached_textures then
                table.insert(textures_to_remove, file)
                cache_size = cache_size - 1
            end
        end
        for _, file in ipairs(textures_to_remove) do
            if r.ImGui_DestroyImage then
                r.ImGui_DestroyImage(ctx, search_texture_cache[file])
            else
                log_to_file("ImGui_DestroyImage not available, texture not destroyed: " .. file)
            end
            search_texture_cache[file] = nil
            texture_last_used[file] = nil
            log_to_file("Texture removed: " .. file)
        end
    end
    -- Herlaad verwijderde textures indien nodig
    if cache_size < config.min_cached_textures then
        for file in pairs(texture_last_used) do
            if not search_texture_cache[file] then
                texture_load_queue[file] = current_time
            end
        end
    end
end

local function Lead_Trim_ws(s) return s:match '^%s*(.*)' end

local function SetMinMax(Input, Min, Max)
    return math.max(Min, math.min(Input, Max))
end

local function SortTable(tab, val1, val2)
    table.sort(tab, function(a, b)
        if (a[val1] < b[val1]) then return true
        elseif (a[val1] > b[val1]) then return false
        else return a[val2] < b[val2] end
    end)
end

local function GetTrackColorAndTextColor(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return r.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1), 0xFFFFFFFF
    end
    local color = r.GetTrackColor(track)
    if color == 0 then
        return r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 0x000000FF
    else
        local red = (color & 0xFF) / 255
        local green = ((color >> 8) & 0xFF) / 255
        local blue = ((color >> 16) & 0xFF) / 255
        local brightness = (red * 0.299 + green * 0.587 + blue * 0.114)
        local text_color = brightness > 0.5 and 0x000000FF or 0xFFFFFFFF
        return r.ImGui_ColorConvertDouble4ToU32(red, green, blue, 1), text_color
    end
end

local function GetBounds(hwnd)
    local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
    return left, top, right-left, bottom-top
end

local function Literalize(str)
    return str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

local function GetFileContext(filename)
    local file = io.open(filename, "r")
    if file then
        local content = file:read("*all")
        file:close()
        return content
    end
    return nil
end

local function GetTrackName(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return "No Track Selected"
    end
    local _, name = r.GetTrackName(track)
    return name
end
local function IsOSX()
    local platform = reaper.GetOS()
    return platform:match("OSX") or platform:match("macOS")
end

local function ScreenshotOSX(path, x, y, w, h)
    x, y = r.ImGui_PointConvertNative(ctx, x, y, false)
    local command = 'screencapture -x -R %d,%d,%d,%d -t png "%s"'
    os.execute(command:format(x, y, w, h, path))
end

local wait_time = 0.5 -- Wachttijd in seconden
local timeout_duration = 5 -- Timeout duur in seconden
local function Wait(callback, start_time)
    start_time = start_time or r.time_precise()
    local function check()
        if r.time_precise() - start_time >= wait_time then
            callback()
        else
            r.defer(check)
        end
    end
    r.defer(check)
end

local function IsPluginClosed(fx_index)
    return not r.TrackFX_GetFloatingWindow(TRACK, fx_index)
end

local function EnsurePluginRemoved(fx_index, callback)
    local function check()
        if IsPluginClosed(fx_index) then
            if callback then
                callback()
            else
                print("Error: callback is nil")
            end
        else
            r.defer(check)
        end
    end
    r.defer(check)
end

local function CaptureScreenshot(plugin_name, fx_index)
    local hwnd = r.TrackFX_GetFloatingWindow(TRACK, fx_index)
    if hwnd then
        local safe_name = plugin_name:gsub("[^%w%s-]", "_")
        local filename
        if config.screenshot_size_option == 1 then
        local track_icons_path = EnsureTrackIconsFolderExists()
        filename = track_icons_path .. safe_name .. ".png"
        else
        filename = screenshot_path .. safe_name .. ".png"
        end
        local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
        local w, h = right - left, bottom - top
        local offset = plugin_name:match("^JS") and 0 or config.capture_height_offset
        h = h - offset
        log_to_file("Capturing screenshot for plugin: " .. plugin_name)
        if not IsOSX() then
            local srcDC = r.JS_GDI_GetClientDC(hwnd)
            local srcBmp = r.JS_LICE_CreateBitmap(true, w, h)
            local srcDC_LICE = r.JS_LICE_GetDC(srcBmp)
            r.JS_GDI_Blit(srcDC_LICE, 0, 0, srcDC, config.srcx, config.srcy, w, h)
            local destBmp
            if config.screenshot_size_option == 1 then
                -- 128x128
                destBmp = r.JS_LICE_CreateBitmap(true, 128, 128)
                r.JS_LICE_ScaledBlit(destBmp, 0, 0, 128, 128, srcBmp, 0, 0, w, h, 1, "FAST")
            elseif config.screenshot_size_option == 2 then
                -- 500x(verhouding)
                local scale = 500 / w
                local newW, newH = 500, math.floor(h * scale)
                destBmp = r.JS_LICE_CreateBitmap(true, newW, newH)
                r.JS_LICE_ScaledBlit(destBmp, 0, 0, newW, newH, srcBmp, 0, 0, w, h, 1, "FAST")
            else
                -- Origineel
                destBmp = srcBmp
            end
            r.JS_LICE_WritePNG(filename, destBmp, false)
            if destBmp ~= srcBmp then
                r.JS_LICE_DestroyBitmap(destBmp)
            end
            r.JS_GDI_ReleaseDC(hwnd, srcDC)
            r.JS_LICE_DestroyBitmap(srcBmp)
        else
            -- Voor macOS gebruiken we nog steeds de originele methode
            ScreenshotOSX(filename, left, top, w, h)
        end
        local file = io.open(filename, "rb")
        if file then
            local size = file:seek("end")
            file:close()
            if size > 0 then
                print("Screenshot Saved " .. filename .. " (Grootte: " .. size .. " bytes)")
            else
                print("Screenshot File is Empty: " .. filename)
            end
        else
            print("Cant make screenshot: " .. filename)
        end
    else
        print("No Plugin Window " .. plugin_name)
    end
    r.TrackFX_Show(TRACK, fx_index, 2)
    r.TrackFX_Delete(TRACK, fx_index)
end

local function CaptureExistingFX(track, fx_index)
    local retval, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
    if retval then
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
        if hwnd then
            local safe_name = fx_name:gsub("[^%w%s-]", "_")
            local filename = screenshot_path .. safe_name .. ".png"
            
            local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
            local w, h = right - left, bottom - top
            
            local offset = fx_name:match("^JS") and 0 or config.capture_height_offset
            h = h - offset

            log_to_file("Capturing screenshot for existing FX: " .. fx_name)
            if not IsOSX() then
                local srcDC = r.JS_GDI_GetClientDC(hwnd)
                local destBmp = r.JS_LICE_CreateBitmap(true, w, h)
                local destDC = r.JS_LICE_GetDC(destBmp)
                r.JS_GDI_Blit(destDC, 0, 0, srcDC, config.srcx, config.srcy, w, h)
                r.JS_LICE_WritePNG(filename, destBmp, false)
                r.JS_GDI_ReleaseDC(hwnd, srcDC)
                r.JS_LICE_DestroyBitmap(destBmp)
            else
                ScreenshotOSX(filename, left, top, w, h)
            end
            
            print("Screenshot Saved: " .. filename)
        else
            print("No Plugin Window for " .. fx_name)
        end
    end
end
local function CaptureFirstTrackFX()
    if not TRACK then return end
    
    local fx_count = r.TrackFX_GetCount(TRACK)
    if fx_count > 0 then
        CaptureExistingFX(TRACK, 0)
    else
        r.ShowMessageBox("No FX on the selected track", "Info", 0)
    end
end

local function IsARAPlugin(track, fx_index)
    return r.TrackFX_GetNamedConfigParm(track, fx_index, "ARA")
end

local function CaptureARAScreenshot(track, fx_index, plugin_name)
    local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
    if hwnd then
        -- Open ARA interface
        r.TrackFX_Show(track, fx_index, 3)
        r.defer(function()
            -- Geef de ARA interface tijd om te openen
            r.time_precise()
            r.defer(function()
                local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                local filename = screenshot_path .. safe_name .. ".png"
                local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
                local w, h = right - left, bottom - top
                
                -- Maak screenshot van ARA interface
                local srcDC = r.JS_GDI_GetClientDC(hwnd)
                local srcBmp = r.JS_LICE_CreateBitmap(true, w, h)
                local srcDC_LICE = r.JS_LICE_GetDC(srcBmp)
                r.JS_GDI_Blit(srcDC_LICE, 0, 0, srcDC, config.srcx, config.srcy, w, h)
                r.JS_LICE_WritePNG(filename, srcBmp, false)
                r.JS_GDI_ReleaseDC(hwnd, srcDC)
                r.JS_LICE_DestroyBitmap(srcBmp)
                
                -- Sluit ARA interface
                r.TrackFX_Show(track, fx_index, 2)
            end)
        end)
    end
end


local function MakeScreenshot(plugin_name, callback, is_individual)
    if not IsPluginVisible(plugin_name) then
        if callback then callback() end
        return
    end
    if not is_individual then
        if config.screenshot_size_option ~= 1 and ScreenshotExists(plugin_name, config.screenshot_size_option) then
            log_to_file("Screenshot already exists: " .. plugin_name)
            if callback then callback() end
            return
        end
    
    local should_screenshot = false
    if plugin_name:match("^VST3i:") and config.bulk_screenshot_vst3i then
        should_screenshot = true
    elseif plugin_name:match("^VST3:") and config.bulk_screenshot_vst3 then
        should_screenshot = true
    elseif plugin_name:match("^VSTi:") and config.bulk_screenshot_vsti then
        should_screenshot = true
    elseif plugin_name:match("^VST:") and config.bulk_screenshot_vst then
        should_screenshot = true
    elseif plugin_name:match("^JS:") and config.bulk_screenshot_js then
        should_screenshot = true
    elseif plugin_name:match("^AU:") and config.bulk_screenshot_au then
        should_screenshot = true
    elseif plugin_name:match("^AUi:") and config.bulk_screenshot_aui then
        should_screenshot = true
    elseif plugin_name:match("^CLAP:") and config.bulk_screenshot_clap then
        should_screenshot = true
    elseif plugin_name:match("^CLAPi:") and config.bulk_screenshot_clapi then
        should_screenshot = true
    elseif plugin_name:match("^LV2:") and config.bulk_screenshot_lv2 then
        should_screenshot = true
    elseif plugin_name:match("^LV2i:") and config.bulk_screenshot_lv2i then
        should_screenshot = true
    end
        if not should_screenshot then
            log_to_file("Plugin skipped because of configuration: " .. plugin_name)
            if callback then callback() end
            return
        end
    end
    if type(plugin_name) ~= "string" then
        r.ShowMessageBox("Invalid plugin name", "Error", 0)
        return
    end
    if not IsX86Bridged(plugin_name) or config.include_x86_bridged then
        local fx_index = r.TrackFX_AddByName(TRACK, plugin_name, false, -1)
        r.TrackFX_Show(TRACK, fx_index, 3)
        
        Wait(function()
            if IsARAPlugin(TRACK, fx_index) then
                CaptureARAScreenshot(TRACK, fx_index, plugin_name)
            else
                CaptureScreenshot(plugin_name, fx_index)
            end
            r.TrackFX_Show(TRACK, fx_index, 2)
            r.TrackFX_Delete(TRACK, fx_index)
            EnsurePluginRemoved(fx_index, callback)
        end)
    else
        if callback then callback() end
    end
end



local bulk_screenshot_progress = 0
local total_fx_count = 0
local loaded_fx_count = 0  
local fx_list = {}
local function EnumerateInstalledFX()
    fx_list = {}
    total_fx_count = 0
    local default_folder_plugins = {}
    
    if config.screenshot_default_folder_only and config.default_folder then
        for i = 1, #CAT_TEST do
            if CAT_TEST[i].name == "FOLDERS" then
                for j = 1, #CAT_TEST[i].list do
                    if CAT_TEST[i].list[j].name == config.default_folder then
                        for k = 1, #CAT_TEST[i].list[j].fx do
                            default_folder_plugins[CAT_TEST[i].list[j].fx[k]] = true
                        end
                        break
                    end
                end
                break
            end
        end
    end
    for i = 1, math.huge do
        local retval, fx_name = r.EnumInstalledFX(i)
        if not retval then break end
        
        local include_fx = false
        if not config.screenshot_default_folder_only or default_folder_plugins[fx_name] then
            if fx_name:match("^VST:") and not fx_name:match("^VST3:") and not fx_name:match("^VSTi:") and config.bulk_screenshot_vst then
                include_fx = true
            elseif fx_name:match("^VSTi:") and not fx_name:match("^VST3i:") and config.bulk_screenshot_vsti then
                include_fx = true
            elseif fx_name:match("^VST3:") and not fx_name:match("^VST3i:") and config.bulk_screenshot_vst3 then
                include_fx = true
            elseif fx_name:match("^VST3i:") and config.bulk_screenshot_vst3i then
                include_fx = true
            elseif fx_name:match("^JS:") and not fx_name:match("^JSi:") and config.bulk_screenshot_js then
                include_fx = true
            elseif fx_name:match("^JSi:") and config.bulk_screenshot_jsi then
                include_fx = true
            elseif fx_name:match("^AU:") and not fx_name:match("^AUi:") and config.bulk_screenshot_au then
                include_fx = true
            elseif fx_name:match("^AUi:") and config.bulk_screenshot_aui then
                include_fx = true
            elseif fx_name:match("^CLAP:") and not fx_name:match("^CLAPi:") and config.bulk_screenshot_clap then
                include_fx = true
            elseif fx_name:match("^CLAPi:") and config.bulk_screenshot_clapi then
                include_fx = true
            elseif fx_name:match("^LV2:") and not fx_name:match("^LV2i:") and config.bulk_screenshot_lv2 then
                include_fx = true
            elseif fx_name:match("^LV2i:") and config.bulk_screenshot_lv2i then
                include_fx = true
            end
        end
        if include_fx and (not IsX86Bridged(fx_name) or config.include_x86_bridged) then
            total_fx_count = total_fx_count + 1
            fx_list[total_fx_count] = fx_name
        end
    end
    log_to_file("Totaal aantal geselecteerde plugins voor screenshots: " .. total_fx_count)
end



local PROCESS = false
local START = false
local function ProcessFX(index, start_time)
    start_time = start_time or r.time_precise()
    if STOP_REQUESTED or index > total_fx_count then
        log_to_file("Process completed or stopped at index: " .. index)
        START = false
        PROCESS = false
        STOP_REQUESTED = false
        bulk_screenshot_progress = 0
        loaded_fx_count = 0
        r.defer(function()
            reaper.ShowMessageBox("Bulk screenshot process " .. (STOP_REQUESTED and "stopped" or "completed"), "Info", 0)
        end)
    elseif index <= total_fx_count then
        local plugin_name = fx_list[index]
        if config.include_x86_bridged or not IsX86Bridged(plugin_name) then
            if config.screenshot_size_option == 1 or not ScreenshotExists(plugin_name, config.screenshot_size_option) then       
                MakeScreenshot(plugin_name, function()
                    loaded_fx_count = loaded_fx_count + 1
                    bulk_screenshot_progress = loaded_fx_count / total_fx_count
                    log_to_file("Processed plugin: " .. plugin_name .. " Progress: " .. bulk_screenshot_progress)
                    r.defer(function() 
                        if r.time_precise() - start_time > 300 then -- 5 minuten timeout
                            log_to_file("Process timed out")
                            ProcessFX(total_fx_count + 1) -- Forceer afsluiting
                        else
                            ProcessFX(index + 1) 
                        end
                    end)
                end)
            else
                loaded_fx_count = loaded_fx_count + 1
                bulk_screenshot_progress = loaded_fx_count / total_fx_count
                r.defer(function() ProcessFX(index + 1) end)
            end
        else
            r.defer(function() ProcessFX(index + 1) end)
        end
    end
end


local function ClearScreenshots()
    for file in io.popen('dir "'..screenshot_path..'" /b'):lines() do
        os.remove(screenshot_path .. file)
    end
    -- BuildScreenshotDatabase() -- Update de database na het verwijderen van de screenshots
    print("All screenshots cleared.")
end

local function ShowConfirmClearPopup()
    local popup_open = true
    r.ImGui_OpenPopup(ctx, "Confirm Clear Screenshots")
    if r.ImGui_BeginPopupModal(ctx, "Confirm Clear Screenshots", popup_open, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "Are you sure you want to clear all screenshots?")
        if r.ImGui_Button(ctx, "Yes", 80, 0) then
            ClearScreenshots()
            show_confirm_clear = false
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "No", 80, 0) then
            show_confirm_clear = false
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end
end

local function StartBulkScreenshot()
    if not START then
        EnumerateInstalledFX()
        bulk_screenshot_progress = 0
        loaded_fx_count = 0  -- Reset het aantal geladen plugins
        START = true
        PROCESS = true
        STOP_REQUESTED = false
        ProcessFX(1)
    else
        STOP_REQUESTED = true
    end
end

function LoadPluginScreenshot(plugin_name)
    local safe_name = plugin_name:gsub("[^%w%s-]", "_")
    local screenshot_file = screenshot_path .. safe_name .. ".png"
   
    if r.file_exists(screenshot_file) then
        screenshot_texture = LoadTexture(screenshot_file)
        if screenshot_texture then
            screenshot_width, screenshot_height = r.ImGui_Image_GetSize(screenshot_texture)
        end
    else
        screenshot_texture = nil
    end
end

function ShowPluginScreenshot()
    if screenshot_texture and current_hovered_plugin and is_screenshot_visible then
        if r.ImGui_ValidatePtr(screenshot_texture, 'ImGui_Image*') then
            local width, height = r.ImGui_Image_GetSize(screenshot_texture)
            if width and height then
                local display_width = config.screenshot_display_size
                local display_height = display_width * (height / width)
                local max_height = display_width * 1.2 -- 120% van de ingestelde breedte
                
                if display_height > max_height then
                    display_height = max_height
                    display_width = display_height * (width / height)
                end
                    
                    local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                    local vp_width, vp_height = r.ImGui_GetWindowSize(ctx)
                    
                    local window_pos_x = mouse_x + 20
                    local window_pos_y = mouse_y + 20
                    
                    if window_pos_x + display_width > vp_width then
                        window_pos_x = mouse_x - display_width - 20
                    end
                    if window_pos_y + display_height > vp_height * 3 then
                        window_pos_y = mouse_y - display_height - 20
                    end
                    local show_name = config.show_name_in_main_window and not config.hidden_names[current_hovered_plugin]
                    local window_height = display_height + (show_name and 30 or 0)
                    r.ImGui_SetNextWindowSize(ctx, display_width, window_height)
                    r.ImGui_SetNextWindowPos(ctx, window_pos_x, window_pos_y)
                    r.ImGui_SetNextWindowBgAlpha(ctx, 0.9)
                    r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 1)
                    r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 14)
                    r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 1)
                    r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 1, 1)
                    r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 2,2)
                    r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 7)

                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
                    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x000000FF)
                    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x000000FF)
                    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x000000FF)
                    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0x000000FF)
                    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x000000FF)
                    
                    if r.ImGui_Begin(ctx, "Plugin Screenshot", true, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoFocusOnAppearing() | r.ImGui_WindowFlags_NoDocking() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoResize()) then
                        r.ImGui_Image(ctx, screenshot_texture, display_width, display_height)
                        
                        if show_name then
                            local text_width = r.ImGui_CalcTextSize(ctx, current_hovered_plugin)
                            local text_pos_x = (display_width - text_width) * 0.5
                            local text_pos_y = display_height + 12
                            
                            r.ImGui_SetCursorPos(ctx, text_pos_x, text_pos_y)
                            r.ImGui_Text(ctx, current_hovered_plugin)
                        end
                        r.ImGui_End(ctx)
                    end
                    
                    r.ImGui_PopStyleVar(ctx, 6)
                    r.ImGui_PopStyleColor(ctx, 6)
                else
                    log_to_file("Ongeldige afmetingen voor texture: " .. tostring(screenshot_texture))
                    screenshot_texture = nil
                end
            else
                log_to_file("Ongeldige texture voor plugin: " .. current_hovered_plugin)
                screenshot_texture = nil
            end
        end
    end

local function GetCurrentProjectFX()
    local fx_list = {}
    local track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = reaper.GetTrack(0, i)
        local _, track_name = reaper.GetTrackName(track)
        local track_number = reaper.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        local track_color = reaper.GetTrackColor(track)
        local fx_count = reaper.TrackFX_GetCount(track)
        for j = 0, fx_count - 1 do
            local retval, fx_name = reaper.TrackFX_GetFXName(track, j, "")
            if retval then
                table.insert(fx_list, {
                    fx_name = fx_name,
                    track_name = track_name,
                    track_number = track_number,
                    track_color = track_color
                })
            end
        end
    end
    return fx_list
end
------------------------------------------------
local function get_all_projects()
    local projects = {}
    local stack = {{path = PROJECTS_DIR, depth = 0}}
    local max_depth = 2
    while #stack > 0 do
        local current = table.remove(stack)
        local path, depth = current.path, current.depth
        local i = 0
        repeat
            local file = r.EnumerateFiles(path, i)
            if file then
                local full_path = path .. file
                if file:match("%.rpp$") then
                    local project_name = file:gsub("%.rpp$", "")
                    table.insert(projects, {
                        name = project_name,
                        path = full_path
                    })
                end
            end
            i = i + 1
        until not file
        if depth < max_depth then
            i = 0
            repeat
                local subdir = r.EnumerateSubdirectories(path, i)
                if subdir then
                    table.insert(stack, {path = path .. subdir .. "\\", depth = depth + 1})
                end
                i = i + 1
            until not subdir
        end
    end
    table.sort(projects, function(a, b) return a.name:lower() < b.name:lower() end)
    return projects
  end
    local function open_project(project_path)
        r.Main_openProject(project_path)
    end
    local function save_projects_info(projects)
        local file = io.open(PROJECTS_INFO_FILE, "w")
        if file then
            for _, project in ipairs(projects) do
                file:write(string.format("%s|%s\n", project.name, project.path))
            end
            file:close()
        end
    end
    local function LoadProjects()
        projects = get_all_projects()
        filtered_projects = projects
        save_projects_info(projects)
    end

------------------------------------------------------
local function AddPluginToSelectedTracks(plugin_name)
    local track_count = r.CountSelectedTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        local fx_index = r.TrackFX_AddByName(track, plugin_name, false, -1000 - r.TrackFX_GetCount(track))
        r.TrackFX_Show(track, fx_index, 2)  -- 2 sluit het venster
    end
end

local function AddPluginToAllTracks(plugin_name)
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local fx_index = r.TrackFX_AddByName(track, plugin_name, false, -1000 - r.TrackFX_GetCount(track))
        r.TrackFX_Show(track, fx_index, 2)  -- 2 sluit het venster
    end
end

local function AddToFavorites(plugin_name)
    table.insert(favorite_plugins, plugin_name)
    SaveFavorites()
end

local function RemoveFromFavorites(plugin_name)
    for i, fav in ipairs(favorite_plugins) do
        if fav == plugin_name then
            table.remove(favorite_plugins, i)
            SaveFavorites()
            break
        end
    end
end

local function ShowScreenshotWindow()
    if not config.show_screenshot_window then return end
    if screenshot_search_results and #screenshot_search_results > 0 then
        selected_folder = nil
    elseif config.default_folder and selected_folder == nil then
        selected_folder = config.default_folder
    end
    local main_window_pos_x, main_window_pos_y = r.ImGui_GetWindowPos(ctx)
    local main_window_width = r.ImGui_GetWindowWidth(ctx)
    local main_window_height = r.ImGui_GetWindowHeight(ctx)
    local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoFocusOnAppearing()
    if config.dock_screenshot_window then
        if config.dock_screenshot_left then
            r.ImGui_SetNextWindowPos(ctx, main_window_pos_x - config.screenshot_window_width - 5, main_window_pos_y, r.ImGui_Cond_Always())
        else
            r.ImGui_SetNextWindowPos(ctx, main_window_pos_x + main_window_width + 5, main_window_pos_y, r.ImGui_Cond_Always())
        end
        r.ImGui_SetNextWindowSizeConstraints(ctx, 100, main_window_height, FLT_MAX, main_window_height)
    end
    r.ImGui_SetNextWindowSize(ctx, config.screenshot_window_width, main_window_height, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, "Screenshots##NoTitle", true, window_flags)
    if visible then
        
        r.ImGui_PushFont(ctx, LargeFont)
        if show_media_browser then
            r.ImGui_Text(ctx, "PROJECTS:")          
        else
            r.ImGui_Text(ctx, "SCREENSHOTS: " .. (FILTER or ""))
        end
        r.ImGui_PopFont(ctx)
        r.ImGui_SameLine(ctx)
        local window_width = r.ImGui_GetWindowWidth(ctx)
        local button_width = 15
        local button_height = 15
        -- Plaats de cursor in de rechterbovenhoek
        r.ImGui_SetCursorPos(ctx, window_width - button_width - 5, 5)
        if r.ImGui_Button(ctx, "X", button_width, button_height) then
            config.show_screenshot_window = false
            SaveConfig()
        end
        r.ImGui_Separator(ctx)
        
        if show_media_browser then
            r.ImGui_PushItemWidth(ctx, -1)
            local changed, new_search_term = r.ImGui_InputText(ctx, "##ProjectSearch", project_search_term)
            if changed then
                project_search_term = new_search_term
                filtered_projects = {}
                for _, project in ipairs(projects) do
                    if project.name:lower():find(project_search_term:lower(), 1, true) then
                        table.insert(filtered_projects, project)
                    end
                end
            end
            r.ImGui_PopItemWidth(ctx)
            if r.ImGui_BeginChild(ctx, "MediaBrowserList", 0, 0) then
                for _, project in ipairs(filtered_projects) do
                    if r.ImGui_Selectable(ctx, project.name) then
                        open_project(project.path)
                    end
                    if r.ImGui_IsItemClicked(ctx, 1) then  
                        r.Main_OnCommand(41929, 0)  -- New project tab (ignore default template)
                        r.Main_openProject(project.path)
                    end
                end
                r.ImGui_EndChild(ctx)
            end
        else
            local folders_category
            for i = 1, #CAT_TEST do
                if CAT_TEST[i].name == "FOLDERS" then
                    folders_category = CAT_TEST[i].list
                    break
                end
            end
        if folders_category and #folders_category > 0 then
            r.ImGui_SetNextWindowSizeConstraints(ctx, 0, 0, FLT_MAX, config.dropdown_menu_length * r.ImGui_GetTextLineHeightWithSpacing(ctx))
            if r.ImGui_BeginCombo(ctx, "##FolderDropdown", selected_folder or "Select Folder") then
                if r.ImGui_Selectable(ctx, "No Folder", selected_folder == nil) then
                    selected_folder = nil
                end
                if r.ImGui_Selectable(ctx, "Favorites", selected_folder == "Favorites") then
                    selected_folder = "Favorites"
                    ClearScreenshotCache()
                end
                if r.ImGui_Selectable(ctx, "Current Project FX", selected_folder == "Current Project FX") then
                    selected_folder = "Current Project FX"
                    ClearScreenshotCache()
                end
                if r.ImGui_Selectable(ctx, "Current Track FX", selected_folder == "Current Track FX") then
                    selected_folder = "Current Track FX"
                    ClearScreenshotCache()
                end
                r.ImGui_Separator(ctx)
                for i = 1, #folders_category do
                    local is_selected = (selected_folder == folders_category[i].name)
                    if r.ImGui_Selectable(ctx, folders_category[i].name, is_selected) then
                        selected_folder = folders_category[i].name
                        UpdateLastViewedFolder(selected_folder)
                        screenshot_search_results = nil
                        ClearScreenshotCache()
                        GetPluginsForFolder(selected_folder)
                    end
                    if is_selected then
                        r.ImGui_SetItemDefaultFocus(ctx)
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            
                if r.ImGui_IsItemHovered(ctx) then
                    local wheel_delta = r.ImGui_GetMouseWheel(ctx)
                    if wheel_delta ~= 0 then
                        local current_index = 0
                        for i, folder in ipairs(folders_category) do
                            if folder.name == selected_folder then
                                current_index = i
                                break
                            end
                        end
                        current_index = current_index - wheel_delta
                        if current_index < 1 then
                            current_index = #folders_category
                        elseif current_index > #folders_category then
                            current_index = 1
                        end
                        selected_folder = folders_category[current_index].name
                        UpdateLastViewedFolder(selected_folder)
                        screenshot_search_results = nil
                        ClearScreenshotCache()
                        GetPluginsForFolder(selected_folder)
                    end
                end
            r.ImGui_SameLine(ctx)
            local changed, new_value = r.ImGui_Checkbox(ctx, "Global", config.use_global_screenshot_size)
            if changed then
                config.use_global_screenshot_size = new_value
                SaveConfig()
            end
            if config.use_global_screenshot_size then
                local global_changed, new_global_size = r.ImGui_SliderInt(ctx, "##Global Size", config.global_screenshot_size, 100, 500)
                if global_changed then
                    config.global_screenshot_size = new_global_size
                    display_size = new_global_size
                    SaveConfig()
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Reset Global") then
                    config.global_screenshot_size = 200
                    display_size = 200
                    SaveConfig()
                end
            else
                if selected_folder then
                    local current_size = config.folder_specific_sizes[selected_folder] or config.screenshot_window_size
                    local changed, new_size = r.ImGui_SliderInt(ctx, "##Folder Size", current_size, 100, 500)
                    if changed then
                        config.folder_specific_sizes[selected_folder] = new_size
                        display_size = new_size
                        SaveConfig()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Reset Folder") then
                        config.folder_specific_sizes[selected_folder] = nil
                        display_size = config.screenshot_window_size
                        SaveConfig()
                    end
                end
            end
        end
        local available_width = r.ImGui_GetContentRegionAvail(ctx)
        local display_size
        if config.use_global_screenshot_size then
            display_size = config.global_screenshot_size
        elseif config.resize_screenshots_with_window then
            display_size = available_width
        else
            display_size = selected_folder and (config.folder_specific_sizes[selected_folder] or config.screenshot_window_size) or config.screenshot_window_size
        end
        local num_columns = math.max(1, math.floor(available_width / display_size))
        local column_width = available_width / num_columns 

        local function ScaleScreenshotSize(width, height, max_display_size)
            local max_height = max_display_size * 1.2 -- 120% van de ingestelde breedte
            local display_width = max_display_size
            local display_height = display_width * (height / width)
            
            if display_height > max_height then
                display_height = max_height
                display_width = display_height * (width / height)
            end
            
            return display_width, display_height
        end

        if r.ImGui_BeginChild(ctx, "ScreenshotList", 0, 0) then
            if folder_changed or new_search_performed then
                r.ImGui_SetScrollY(ctx, 0)
                folder_changed = false
                new_search_performed = false
            end
            if selected_folder ~= last_selected_folder then
                folder_changed = true
                last_selected_folder = selected_folder
            end
            
            if selected_folder then
                local filtered_plugins = {}
                if selected_folder == "Favorites" then
                    filtered_plugins = favorite_plugins
                elseif selected_folder == "Current Project FX" then
                    filtered_plugins = GetCurrentProjectFX()
                elseif selected_folder == "Current Track FX" then
                    filtered_plugins = GetCurrentTrackFX()
            
                    if update_search_screenshots then
                        screenshot_search_results = nil
                        update_search_screenshots = false
                    end
                else
                    for i = 1, #CAT_TEST do
                        if CAT_TEST[i].name == "FOLDERS" then
                            for j = 1, #CAT_TEST[i].list do
                                if CAT_TEST[i].list[j].name == selected_folder then
                                    filtered_plugins = CAT_TEST[i].list[j].fx
                                    break
                                end
                            end
                            break
                        end
                    end
                end    
                if selected_folder and selected_folder ~= "Current Project FX" and selected_folder ~= "Current Track FX" then
                    local available_width = r.ImGui_GetContentRegionAvail(ctx)
                    local display_size
                    if config.use_global_screenshot_size then
                        display_size = config.global_screenshot_size
                    elseif config.resize_screenshots_with_window then
                        display_size = available_width
                    else
                        display_size = selected_folder and (config.folder_specific_sizes[selected_folder] or config.screenshot_window_size) or config.screenshot_window_size
                    end
                    local num_columns = math.max(1, math.floor(available_width / display_size))
                    local column_width = available_width / num_columns
                    for i = 1, #filtered_plugins do
                        local column = (i - 1) % num_columns
                        if column > 0 then
                            r.ImGui_SameLine(ctx)
                        end
                        r.ImGui_BeginGroup(ctx)
                        local plugin_name = filtered_plugins[i]
                        local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                        local screenshot_file = screenshot_path .. safe_name .. ".png"
                        if r.file_exists(screenshot_file) then
                            local texture = LoadSearchTexture(screenshot_file, plugin and plugin.fx_name or get_safe_name(plugin_name))
                            if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                local width, height = r.ImGui_Image_GetSize(texture)
                                if width and height then
                                    local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                    if r.ImGui_ImageButton(ctx, "##"..plugin_name, texture, display_width, display_height) then
                                        if TRACK then
                                            r.TrackFX_AddByName(TRACK, plugin_name, false, -1000 - r.TrackFX_GetCount(TRACK))
                                            if config.close_after_adding_fx then
                                                SHOULD_CLOSE_SCRIPT = true
                                            end
                                        end
                                    end
                                    if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtsklik
                                        r.ImGui_OpenPopup(ctx, "ScreenshotPluginMenu_" .. i)
                                    end
                                    
                                    if r.ImGui_BeginPopup(ctx, "ScreenshotPluginMenu_" .. i) then
                                        if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                                            MakeScreenshot(plugin_name, nil, true)
                                        end
                                        if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                            AddPluginToSelectedTracks(plugin_name)
                                        end
                                        if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                            AddPluginToAllTracks(plugin_name)
                                        end
                                        if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                            AddToFavorites(plugin_name)
                                        end
                                        if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                            RemoveFromFavorites(plugin_name)
                                        end
                                        if config.hidden_names[plugin_name] then
                                            if r.ImGui_MenuItem(ctx, "Show Name") then
                                                config.hidden_names[plugin_name] = nil
                                                SaveConfig()  -- Sla de configuratie op na wijziging
                                            end
                                        else
                                            if r.ImGui_MenuItem(ctx, "Hide Name") then
                                                config.hidden_names[plugin_name] = true
                                                SaveConfig()  -- Sla de configuratie op na wijziging
                                            end
                                        end
                                        r.ImGui_EndPopup(ctx)
                                    end
                                    if config.show_name_in_screenshot_window and not config.hidden_names[plugin_name] then
                                        r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                        r.ImGui_Text(ctx, plugin_name)
                                        r.ImGui_PopTextWrapPos(ctx)
                                    end
                                    
                                end
                            end
                        end
                        r.ImGui_EndGroup(ctx)
                        if column == num_columns - 1 then
                            r.ImGui_Dummy(ctx, 0, 10)  -- Voeg wat ruimte toe tussen de rijen
                        end
                    end
                end
                if #filtered_plugins > 0 then
                    local current_track_identifier = nil
                    local column_width = available_width / num_columns
                    for i, plugin in ipairs(filtered_plugins) do
                        local track_identifier = (plugin.track_number or "Unknown") .. "_" .. (plugin.track_name or "Unnamed")
                        if selected_folder == "Current Project FX" and track_identifier ~= current_track_identifier then
                            current_track_identifier = track_identifier
                            local track_color, text_color = GetTrackColorAndTextColor(reaper.GetTrack(0, plugin.track_number - 1))
                            local track_number = plugin.track_number
                            r.ImGui_Separator(ctx)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color)
                            if r.ImGui_BeginChild(ctx, "TrackHeader" .. track_number, -1, 20) then
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                                local is_collapsed = collapsed_tracks[track_number] or false
                                if r.ImGui_Button(ctx, is_collapsed and "+" or "-", 20, 20) then
                                    collapsed_tracks[track_number] = not is_collapsed
                                    if not is_collapsed then
                                        ClearScreenshotCache()
                                        GetPluginsForFolder(selected_folder)
                                    end
                                end
                                if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtermuisklik
                                    all_tracks_collapsed = not all_tracks_collapsed
                                    for i = 1, r.CountTracks(0) do
                                        collapsed_tracks[i] = all_tracks_collapsed
                                    end
                                    ClearScreenshotCache()
                                    GetPluginsForFolder(selected_folder)
                                end
                                r.ImGui_SameLine(ctx)
                                if r.ImGui_Button(ctx, "Track " .. track_number .. ": " .. plugin.track_name) then
                                    r.SetOnlyTrackSelected(reaper.GetTrack(0, plugin.track_number - 1))
                                end
                                r.ImGui_PopStyleColor(ctx, 4)
                                r.ImGui_EndChild(ctx)
                            end
                            r.ImGui_PopStyleColor(ctx)
                         r.ImGui_Dummy(ctx, 0, 0)
                        end
                
                        if selected_folder ~= "Current Project FX" or not collapsed_tracks[plugin.track_number] then
                            local column = (i - 1) % num_columns
                            if column > 0 then
                                r.ImGui_SameLine(ctx)
                            end
                            r.ImGui_BeginGroup(ctx)
                            r.ImGui_PushItemWidth(ctx, column_width)
                            if plugin and plugin.fx_name then
                                local safe_name = plugin.fx_name:gsub("[^%w%s-]", "_")
                                local screenshot_file = screenshot_path .. safe_name .. ".png"
                                if r.file_exists(screenshot_file) then
                                    local texture = LoadSearchTexture(screenshot_file, plugin and plugin.fx_name or get_safe_name(plugin_name))
                                    if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                        local width, height = r.ImGui_Image_GetSize(texture)
                                        if width and height then
                                            local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                            
                                            if r.ImGui_ImageButton(ctx, "##"..plugin.fx_name..(plugin.track_number and ("_"..plugin.track_number) or ""), texture, display_width, display_height) then

                                                if selected_folder == "Current Project FX" then
                                                    local track = r.GetTrack(0, plugin.track_number - 1)
                                                    if track then
                                                        local fx_count = r.TrackFX_GetCount(track)
                                                        for j = 0, fx_count - 1 do
                                                            local retval, fx_name = r.TrackFX_GetFXName(track, j, "")
                                                            if retval and fx_name == plugin.fx_name then
                                                                local is_open = r.TrackFX_GetFloatingWindow(track, j) ~= nil
                                                                r.TrackFX_Show(track, j, is_open and 2 or 3)
                                                                break
                                                            end
                                                        end
                                                    end
                                                elseif selected_folder == "Current Track FX" then
                                                    local fx_index = r.TrackFX_GetByName(TRACK, plugin.fx_name, false)
                                                    if fx_index >= 0 then
                                                        local is_open = r.TrackFX_GetFloatingWindow(TRACK, fx_index)
                                                        r.TrackFX_Show(TRACK, fx_index, is_open and 2 or 3)
                                                    end
                                                else
                                                    if TRACK then
                                                        r.TrackFX_AddByName(TRACK, plugin.fx_name, false, -1000 - r.TrackFX_GetCount(TRACK))
                                                        if config.close_after_adding_fx then
                                                            SHOULD_CLOSE_SCRIPT = true
                                                        end
                                                    end
                                                end
                                            end
                                            
                                            if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtermuisklik
                                                if selected_folder == "Current Project FX" or selected_folder == "Current Track FX" then
                                                    r.ImGui_OpenPopup(ctx, "FXContextMenu_" .. i)
                                                else
                                                    MakeScreenshot(plugin.fx_name, nil, true)
                                                end
                                            end
                                            
                                            if r.ImGui_BeginPopup(ctx, "FXContextMenu_" .. i) then
                                                local track = selected_folder == "Current Project FX" 
                                                    and r.GetTrack(0, plugin.track_number - 1) 
                                                    or TRACK
                                                local fx_index = selected_folder == "Current Project FX"
                                                    and (function()
                                                        local fx_count = r.TrackFX_GetCount(track)
                                                        for j = 0, fx_count - 1 do
                                                            local retval, fx_name = r.TrackFX_GetFXName(track, j, "")
                                                            if retval and fx_name == plugin.fx_name then
                                                                return j
                                                            end
                                                        end
                                                    end)()
                                                    or r.TrackFX_GetByName(TRACK, plugin.fx_name, false)
                                            
                                                if r.ImGui_MenuItem(ctx, "Delete") then
                                                    r.TrackFX_Delete(track, fx_index)
                                                    if selected_folder == "Current Track FX" then
                                                        update_search_screenshots = true
                                                    end
                                                end
                                            
                                                if r.ImGui_MenuItem(ctx, "Copy to all tracks") then
                                                    IS_COPYING_TO_ALL_TRACKS = true
                                                    local track_count = r.CountTracks(0)
                                                    for j = 0, track_count - 1 do
                                                        local target_track = r.GetTrack(0, j)
                                                        if target_track ~= track then
                                                            r.TrackFX_CopyToTrack(track, fx_index, target_track, r.TrackFX_GetCount(target_track), false)
                                                        end
                                                    end
                                                    IS_COPYING_TO_ALL_TRACKS = false
                                                end
                                            
                                                if r.ImGui_MenuItem(ctx, "Copy Plugin") then
                                                    copied_plugin = {track = track, index = fx_index}
                                                end
                                            
                                                if r.ImGui_MenuItem(ctx, "Paste Plugin", nil, copied_plugin ~= nil) then
                                                    if copied_plugin then
                                                        local _, orig_name = r.TrackFX_GetFXName(copied_plugin.track, copied_plugin.index, "")
                                                        r.TrackFX_AddByName(track, orig_name, false, -1000)
                                                    end
                                                end
                                            
                                                local is_enabled = r.TrackFX_GetEnabled(track, fx_index)
                                                if r.ImGui_MenuItem(ctx, is_enabled and "Bypass plugin" or "Unbypass plugin") then
                                                    r.TrackFX_SetEnabled(track, fx_index, not is_enabled)
                                                end
                                            
                                                local fx_name = plugin.fx_name
                                                if table.contains(favorite_plugins, fx_name) then
                                                    if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                                        RemoveFromFavorites(fx_name)
                                                    end
                                                else
                                                    if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                                        AddToFavorites(fx_name)
                                                    end
                                                end
                                            
                                                r.ImGui_EndPopup(ctx)
                                            end


                                            if config.show_name_in_screenshot_window and not config.hidden_names[plugin.fx_name] then
                                                r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                                r.ImGui_Text(ctx, plugin.fx_name)
                                                r.ImGui_PopTextWrapPos(ctx)
                                            end
                                        end
                                    end
                                end
                            end
                            r.ImGui_PopItemWidth(ctx)
                            r.ImGui_EndGroup(ctx)
                            
                            if column == num_columns - 1 then
                                r.ImGui_Dummy(ctx, 0, 15)
                            end
                        end
                    end
                else
                    r.ImGui_Text(ctx, "No Plugins in Selected Folder.")
                end
            elseif screenshot_search_results and #screenshot_search_results > 0 then
                local available_width = r.ImGui_GetContentRegionAvail(ctx)
                local display_size
                if config.use_global_screenshot_size then
                    display_size = config.global_screenshot_size
                elseif config.resize_screenshots_with_window then
                    display_size = available_width
                else
                    display_size = config.screenshot_window_size
                end
                local num_columns = math.max(1, math.floor(available_width / display_size))
                local column_width = available_width / num_columns
                for i, fx in ipairs(screenshot_search_results) do
                    local column = (i - 1) % num_columns
                    if column > 0 then
                        r.ImGui_SameLine(ctx)
                    end
                    r.ImGui_BeginGroup(ctx)
                    local safe_name = fx.name:gsub("[^%w%s-]", "_")
                    local screenshot_file = screenshot_path .. safe_name .. ".png"
                    if r.file_exists(screenshot_file) then
                        local texture = LoadSearchTexture(screenshot_file, fx.name)
                        if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                            local width, height = r.ImGui_Image_GetSize(texture)
                            if width and height then
                                local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                
                                if r.ImGui_ImageButton(ctx, "##"..fx.name, texture, display_width, display_height) then
                                    if TRACK then
                                        r.TrackFX_AddByName(TRACK, fx.name, false, -1000 - r.TrackFX_GetCount(TRACK))
                                        if config.close_after_adding_fx then
                                            SHOULD_CLOSE_SCRIPT = true
                                        end
                                    end
                                end
                                if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtsklik
                                    r.ImGui_OpenPopup(ctx, "ScreenshotPluginMenu_" .. i)
                                end
                                
                                if r.ImGui_BeginPopup(ctx, "ScreenshotPluginMenu_" .. i) then
                                    if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                                        MakeScreenshot(fx.name, nil, true)
                                    end
                                    if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                        AddPluginToSelectedTracks(fx.name)
                                    end
                                    if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                        AddPluginToAllTracks(fx.name)
                                    end
                                    if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                        AddToFavorites(fx.name)
                                    end
                                    if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                        RemoveFromFavorites(fx.name)
                                    end
                                    if config.hidden_names[fx.name] then
                                        if r.ImGui_MenuItem(ctx, "Show Name") then
                                            config.hidden_names[fx.name] = nil
                                            SaveConfig()
                                        end
                                    else
                                        if r.ImGui_MenuItem(ctx, "Hide Name") then
                                            config.hidden_names[fx.name] = true
                                            SaveConfig()
                                        end
                                    end
                                    r.ImGui_EndPopup(ctx)
                                end
                    
                                if config.show_name_in_screenshot_window and not config.hidden_names[fx.name] then
                                    r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                    r.ImGui_Text(ctx, fx.name)
                                    r.ImGui_PopTextWrapPos(ctx)
                                end
                            end
                        end
                    end
                    r.ImGui_EndGroup(ctx)
                    
                    if column == num_columns - 1 then
                        r.ImGui_Separator(ctx)
                    end
                end
            else
                r.ImGui_Text(ctx, "Select a folder or enter a search term.")
            end
            r.ImGui_EndChild(ctx)
        end
    end
    config.screenshot_window_width = r.ImGui_GetWindowWidth(ctx)
    end
    r.ImGui_End(ctx)
end

local function Filter_actions(filter_text)
    if old_filter == filter_text then return old_t end
    filter_text = Lead_Trim_ws(filter_text)
    local t = {}
    if filter_text == "" or not filter_text then return t end
    for i = 1, #FX_LIST_TEST do
        if not config.excluded_plugins[FX_LIST_TEST[i]] then
            local name = FX_LIST_TEST[i]:lower()
            local found = true
            for word in filter_text:gmatch("%S+") do
                if not name:find(word:lower(), 1, true) then
                    found = false
                    break
                end
            end
            if found then t[#t + 1] = { score = FX_LIST_TEST[i]:len() - filter_text:len(), name = FX_LIST_TEST[i] } end
        end
    end
    if #t >= 2 then SortTable(t, "score", "name") end
    old_t, old_filter = t, filter_text
    return t
end

local function FilterBox()
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local track_info_width = math.max(window_width - 20, 125)
    local x_button_width = 20
    local margin = 3
    local search_width = track_info_width - x_button_width - margin    
    if r.ImGui_IsWindowAppearing(ctx) then
        r.ImGui_SetKeyboardFocusHere(ctx)
    end
    r.ImGui_PushItemWidth(ctx, search_width)
    local changed
    changed, FILTER = r.ImGui_InputTextWithHint(ctx, '##input', "SEARCH FX", FILTER)
    if changed then
        new_search_performed = true
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_SameLine(ctx)
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
        if FILTER == "" then
            if last_viewed_folder then
                selected_folder = last_viewed_folder
                r.ImGui_SetScrollY(ctx, 0)
                show_screenshot_window = true
                screenshot_window_interactive = true
                screenshot_search_results = nil
                ClearScreenshotCache()
                GetPluginsForFolder(selected_folder)
            end
        else
            UpdateLastViewedFolder(selected_folder)
            screenshot_search_results = Filter_actions(FILTER)
            new_search_performed = true
            update_search_screenshots = true
            show_screenshot_window = true
            screenshot_window_interactive = true
            selected_folder = nil
            ClearScreenshotCache()
        end
    end
    r.ImGui_SameLine(ctx)
    local button_height = r.ImGui_GetFrameHeight(ctx)
    if r.ImGui_Button(ctx, "X", x_button_width, r.ImGui_GetFrameHeight(ctx)) then
        FILTER = ""
        screenshot_search_results = nil
        r.ImGui_SetScrollY(ctx, 0)
        show_screenshot_window = true
        selected_folder = config.default_folder
        ClearScreenshotCache()
        if selected_folder then
            local filtered_plugins = GetPluginsForFolder(selected_folder)
            for _, plugin_name in ipairs(filtered_plugins) do
                local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                local screenshot_file = screenshot_path .. safe_name .. ".png"
                if r.file_exists(screenshot_file) then
                    texture_load_queue[screenshot_file] = r.time_precise()
                end
            end
        end
    end
    local filtered_fx = Filter_actions(FILTER)
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local bottom_buttons_height = config.hideBottomButtons and 0 or 80
    local available_height = window_height - r.ImGui_GetCursorPosY(ctx) - bottom_buttons_height - 10
    if #filtered_fx ~= 0 then
        if r.ImGui_BeginChild(ctx, "##popupp", window_width, available_height) then
            for i = 1, #filtered_fx do
                if r.ImGui_Selectable(ctx, filtered_fx[i].name, i == ADDFX_Sel_Entry) then
                    r.TrackFX_AddByName(TRACK, filtered_fx[i].name, false, -1000 - r.TrackFX_GetCount(TRACK))
                    r.ImGui_CloseCurrentPopup(ctx)
                    LAST_USED_FX = filtered_fx[i].name
                end
                if r.ImGui_IsItemHovered(ctx) then
                    if filtered_fx[i].name ~= current_hovered_plugin then
                        current_hovered_plugin = filtered_fx[i].name
                        if config.show_screenshot_in_search then
                            LoadPluginScreenshot(current_hovered_plugin)
                        end
                    end
                    is_screenshot_visible = true
                    if not config.show_screenshot_in_search or not ScreenshotExists(filtered_fx[i].name) then
                        r.ImGui_BeginTooltip(ctx)
                        r.ImGui_Text(ctx, filtered_fx[i].name)
                        r.ImGui_EndTooltip(ctx)
                    end
                end
                if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtsklik
                    r.ImGui_OpenPopup(ctx, "DrawItemsPluginMenu_" .. i)
                end
                
                if r.ImGui_BeginPopup(ctx, "DrawItemsPluginMenu_" .. i) then
                    if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                        MakeScreenshot(filtered_fx[i].name, nil, true)
                    end
                    if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                        AddPluginToSelectedTracks(filtered_fx[i].name, false)
                    end
                    if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                        AddPluginToAllTracks(filtered_fx[i].name, false)
                    end
                    if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                        AddToFavorites(filtered_fx[i].name)
                    end
                    if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                        RemoveFromFavorites(filtered_fx[i].name)
                    end
                    if config.hidden_names[filtered_fx[i].name] then
                        if r.ImGui_MenuItem(ctx, "Show Name") then
                            config.hidden_names[filtered_fx[i].name] = nil
                            SaveConfig()
                        end
                    else
                        if r.ImGui_MenuItem(ctx, "Hide Name") then
                            config.hidden_names[filtered_fx[i].name] = true
                            SaveConfig()
                        end
                    end
                    r.ImGui_EndPopup(ctx)
                end
            end
            if not r.ImGui_IsWindowHovered(ctx) then
                is_screenshot_visible = false
                current_hovered_plugin = nil
            end
            r.ImGui_EndChild(ctx)
        end
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
            if ADDFX_Sel_Entry and ADDFX_Sel_Entry > 0 and ADDFX_Sel_Entry <= #filtered_fx then
                r.TrackFX_AddByName(TRACK, filtered_fx[ADDFX_Sel_Entry].name, false, -1000 - r.TrackFX_GetCount(TRACK))
                LAST_USED_FX = filtered_fx[ADDFX_Sel_Entry].name
                ADDFX_Sel_Entry = nil
                FILTER = ''
                r.ImGui_CloseCurrentPopup(ctx)
            end
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow()) then
            ADDFX_Sel_Entry = (ADDFX_Sel_Entry or 1) - 1
            if ADDFX_Sel_Entry < 1 then ADDFX_Sel_Entry = #filtered_fx end
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow()) then
            ADDFX_Sel_Entry = (ADDFX_Sel_Entry or 0) + 1
            if ADDFX_Sel_Entry > #filtered_fx then ADDFX_Sel_Entry = 1 end
        end
        
    end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        FILTER = ''
        r.ImGui_CloseCurrentPopup(ctx)
    end
    return #filtered_fx ~= 0
end

local function DrawFxChains(tbl, path)
    local extension = ".RfxChain"
    path = path or ""
    local i = 1
    while i <= #tbl do
        local item = tbl[i]
        if type(item) == "table" and item.dir then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)  
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), config.background_color) 
            if r.ImGui_BeginMenu(ctx, item.dir) then               
                DrawFxChains(item, table.concat({ path, os_separator, item.dir }))              
                r.ImGui_EndMenu(ctx)               
            end  
            reaper.ImGui_PopStyleColor(ctx)
        elseif type(item) ~= "table" then
            if r.ImGui_Selectable(ctx, item) then
                if ADD_FX_TO_ITEM then
                    local selected_item = r.GetSelectedMediaItem(0, 0)
                    if selected_item then
                        local take = r.GetActiveTake(selected_item)
                        if take then
                            r.TakeFX_AddByName(take, table.concat({ path, os_separator, item, extension }), 1)
                        end
                    end
                else
                    if TRACK then
                        r.TrackFX_AddByName(TRACK, table.concat({ path, os_separator, item, extension }), false,
                            -1000 - r.TrackFX_GetCount(TRACK))
                        if config.close_after_adding_fx then
                            SHOULD_CLOSE_SCRIPT = true
                        end
                    end
                end
            end
            if r.ImGui_IsItemClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "FXChainOptions_" .. i)
            end
            if r.ImGui_BeginPopup(ctx, "FXChainOptions_" .. i) then
                if r.ImGui_MenuItem(ctx, "Rename") then
                    local retval, new_name = r.GetUserInputs("Rename FX Chain", 1, "New name:", item)
                    if retval then
                        local resource_path = r.GetResourcePath()
                        local fx_chains_path = resource_path .. "/FXChains"
                        local old_path = fx_chains_path .. "/" .. item .. extension
                        local new_path = fx_chains_path .. "/" .. new_name .. extension
                        if os.rename(old_path, new_path) then
                            tbl[i] = new_name
                            FX_LIST_TEST, CAT_TEST = MakeFXFiles()  
                            r.ShowMessageBox("FX Chain renamed", "Success", 0)
                        else
                            r.ShowMessageBox("Could not rename FX Chain", "Error", 0)
                        end
                    end
                end
                if r.ImGui_MenuItem(ctx, "Delete") then
                    local resource_path = r.GetResourcePath()
                    local fx_chains_path = resource_path .. "/FXChains"
                    local file_path = fx_chains_path .. "/" .. item .. extension
                    if os.remove(file_path) then
                        table.remove(tbl, i)
                        FX_LIST_TEST, CAT_TEST = MakeFXFiles() 
                        r.ShowMessageBox("FX Chain deleted", "Success", 0)
                        i = i - 1  -- Pas de index aan omdat we een element hebben verwijderd
                    else
                        r.ShowMessageBox("Could not delete FX Chain", "Error", 0)
                    end
                end
                r.ImGui_EndPopup(ctx)
            end
        end
        i = i + 1
    end
end
function LoadTemplate(template_path)
    local full_path = r.GetResourcePath() .. "/TrackTemplates" .. template_path
    if r.file_exists(full_path) then
        local track_count = r.CountTracks(0)
        r.PreventUIRefresh(1)
        r.Undo_BeginBlock()
        r.Main_openProject(full_path, 1)
        local new_track = r.GetTrack(0, track_count)
        if new_track then
            r.SetOnlyTrackSelected(new_track)
        end
        r.Undo_EndBlock("Load Track Template", -1)
        r.PreventUIRefresh(-1)
        r.UpdateArrange()
        r.TrackList_AdjustWindows(false)
        if config.close_after_adding_fx then
            SHOULD_CLOSE_SCRIPT = true
        end
    else
        r.ShowConsoleMsg("Template file not found: " .. full_path .. "\n")
    end
end

local function DrawTrackTemplates(tbl, path)
    local extension = ".RTrackTemplate"
    path = path or ""
    for i = 1, #tbl do
        if tbl[i].dir then
            if r.ImGui_BeginMenu(ctx, tbl[i].dir) then
                local cur_path = table.concat({ path, os_separator, tbl[i].dir })
                DrawTrackTemplates(tbl[i], cur_path)
                r.ImGui_EndMenu(ctx)
            end
        elseif type(tbl[i]) ~= "table" then
            if r.ImGui_Selectable(ctx, tbl[i]) then
                local template_str = table.concat({ path, os_separator, tbl[i], extension })
                LoadTemplate(template_str)
            end
        end
    end
end

local function DrawItems(tbl, main_cat_name)
    if menu_direction_right then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_SelectableTextAlign(), 1, 0.5)
    end

    

    local items = tbl or {}
    for i = 1, #items do
        r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
        r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3)      
        r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), config.background_color)
        r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
        r.ImGui_SetNextWindowSize(ctx, FX_LIST_WIDTH, 0)
        if r.ImGui_BeginMenu(ctx, tbl[i].name) then
            for j = 1, #tbl[i].fx do
                if tbl[i].fx[j] then
                    local name = tbl[i].fx[j]
                    if main_cat_name == "ALL PLUGINS" and tbl[i].name ~= "INSTRUMENTS" then
                        name = name:gsub("^(%S+:)", "")
                    elseif main_cat_name == "DEVELOPER" then
                        name = name:gsub(' %(' .. Literalize(tbl[i].name) .. '%)', "")
                    end
                    if r.ImGui_Selectable(ctx, name) then
                        if ADD_FX_TO_ITEM then
                            AddFXToItem(tbl[i].fx[j])
                        else
                            if TRACK then
                                r.TrackFX_AddByName(TRACK, tbl[i].fx[j], false, -1000 - r.TrackFX_GetCount(TRACK))
                            end
                        end
                        LAST_USED_FX = tbl[i].fx[j]
                        if config.close_after_adding_fx and not IS_COPYING_TO_ALL_TRACKS then
                            SHOULD_CLOSE_SCRIPT = true
                        end
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        if tbl[i].fx[j] ~= current_hovered_plugin then
                            current_hovered_plugin = tbl[i].fx[j]
                            LoadPluginScreenshot(current_hovered_plugin)
                        end
                        is_screenshot_visible = true
                       
                    end
                    if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtsklik
                        r.ImGui_OpenPopup(ctx, "DrawItemsPluginMenu_" .. i .. "_" .. j)
                    end
                   
                    if r.ImGui_BeginPopup(ctx, "DrawItemsPluginMenu_" .. i .. "_" .. j) then
                        if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                            MakeScreenshot(tbl[i].fx[j], nil, true)
                        end
                        if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                            AddPluginToSelectedTracks(tbl[i].fx[j], false)
                        end
                        if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                            AddPluginToAllTracks(tbl[i].fx[j], false)
                        end
                        if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                            AddToFavorites(tbl[i].fx[j])
                        end
                        if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                            RemoveFromFavorites(tbl[i].fx[j])
                        end
                        if config.hidden_names[tbl[i].fx[j]] then
                            if r.ImGui_MenuItem(ctx, "Show Name") then
                                config.hidden_names[tbl[i].fx[j]] = nil
                                SaveConfig()
                            end
                        else
                            if r.ImGui_MenuItem(ctx, "Hide Name") then
                                config.hidden_names[tbl[i].fx[j]] = true
                                SaveConfig()
                            end
                        end
                        r.ImGui_EndPopup(ctx)
                    end
                end
            end
            if not r.ImGui_IsWindowHovered(ctx) then
                is_screenshot_visible = false
                current_hovered_plugin = nil
            end
            r.ImGui_EndMenu(ctx)
        end
        reaper.ImGui_PopStyleVar(ctx, 2)
        reaper.ImGui_PopStyleColor(ctx)
    end
    if menu_direction_right then
        r.ImGui_PopStyleVar(ctx)
    end
end
local function DrawFavorites()
    for i, fav in ipairs(favorite_plugins) do
        if r.ImGui_Selectable(ctx, fav) then
            if TRACK then
                r.TrackFX_AddByName(TRACK, fav, false, -1000 - r.TrackFX_GetCount(TRACK))
            end
            LAST_USED_FX = fav
            if config.close_after_adding_fx and not IS_COPYING_TO_ALL_TRACKS then
                SHOULD_CLOSE_SCRIPT = true
            end
        end
        if r.ImGui_IsItemHovered(ctx) then
            if fav ~= current_hovered_plugin then
                current_hovered_plugin = fav
                LoadPluginScreenshot(current_hovered_plugin)
            end
            is_screenshot_visible = true
        end
        if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtsklik
            r.ImGui_OpenPopup(ctx, "FavoritePluginMenu_" .. i)
        end
        if r.ImGui_BeginPopup(ctx, "FavoritePluginMenu_" .. i) then
            if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                MakeScreenshot(fav, nil, true)
            end
            if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                AddPluginToSelectedTracks(fav, false)
            end
            if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                AddPluginToAllTracks(fav, false)
            end
            if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                RemoveFromFavorites(fav)
            end
            if config.hidden_names[fav] then
                if r.ImGui_MenuItem(ctx, "Show Name") then
                    config.hidden_names[fav] = nil
                    SaveConfig()
                end
            else
                if r.ImGui_MenuItem(ctx, "Hide Name") then
                    config.hidden_names[fav] = true
                    SaveConfig()
                end
            end
            r.ImGui_EndPopup(ctx)
        end
    end
    if not r.ImGui_IsWindowHovered(ctx) then
        is_screenshot_visible = false
        current_hovered_plugin = nil
    end
end

local function CalculateButtonWidths(total_width, num_buttons, spacing)
    local available_width = total_width - (spacing * (num_buttons - 1))
    return available_width / num_buttons
end

local function DrawBottomButtons()
    if not config.hideBottomButtons then
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then return end
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local track_info_width = math.max(window_width - 20, 125)
    local button_spacing = 3
    local windowHeight = r.ImGui_GetWindowHeight(ctx)
    local buttonHeight = 70
    r.ImGui_SetCursorPosY(ctx, windowHeight - buttonHeight - 20)
    -- volumeslider
    local volume = r.GetMediaTrackInfo_Value(TRACK, "D_VOL")
    local volume_db = math.floor(20 * math.log(volume, 10) + 0.5)
    r.ImGui_PushItemWidth(ctx, track_info_width)
    local changed, new_volume_db = r.ImGui_SliderInt(ctx, "##Volume", volume_db, -60, 12, "%d dB")

    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Rightclick 0db /double Rightclick -12db")
        if r.ImGui_IsMouseDoubleClicked(ctx, 1) then  -- Rechts dubbelklik
            new_volume_db = -12
            changed = true
        elseif r.ImGui_IsMouseClicked(ctx, 1) then  -- Rechts enkelklik
                new_volume_db = 0
                changed = true
        end
    end

    if changed then
        local new_volume = 10^(new_volume_db/20)
        r.SetMediaTrackInfo_Value(TRACK, "D_VOL", new_volume)
    end
    r.ImGui_PopItemWidth(ctx)


    r.ImGui_SetCursorPosY(ctx, windowHeight - buttonHeight)
    -- Eerste rij knoppen
    local num_buttons_row1 = 3
    local button_width_row1 = CalculateButtonWidths(track_info_width, num_buttons_row1, button_spacing)
    if r.ImGui_Button(ctx, "FXCH", button_width_row1) then
        CreateFXChain()
    end
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Make FXChain from Plugins on selected Track")
    end
    r.ImGui_SameLine(ctx, 0, button_spacing)
    if r.ImGui_Button(ctx, "CPY", button_width_row1) then
        r.Main_OnCommand(r.NamedCommandLookup("_S&M_SMART_CPY_FXCHAIN"), 0)
    end
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Copy All FX on the Selected Track")
    end
    r.ImGui_SameLine(ctx, 0, button_spacing)
    if r.ImGui_Button(ctx, "PST", button_width_row1) then
        r.Main_OnCommand(r.NamedCommandLookup("_S&M_SMART_PST_FXCHAIN"), 0)
    end
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Paste All FX to The selected Track")
    end
    
    -- Tweede rij knoppen
    local num_buttons_row2 = 3
    local button_width_row2 = CalculateButtonWidths(track_info_width, num_buttons_row2, button_spacing)
    local bypass_state = r.GetMediaTrackInfo_Value(TRACK, "I_FXEN") == 0
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), bypass_state and 0xFF0000FF or config.button_background_color)
    if r.ImGui_Button(ctx, "BYPS", button_width_row2) then
        local new_state = bypass_state and 1 or 0
        r.SetMediaTrackInfo_Value(TRACK, "I_FXEN", new_state)
    end
    r.ImGui_PopStyleColor(ctx)
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "ByPass All FX on the selected Track")
    end
    r.ImGui_SameLine(ctx, 0, button_spacing)
    if r.ImGui_Button(ctx, "KEYS", button_width_row2) then
        r.Main_OnCommand(40377, 0)
    end
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Show Virtual Keyboard")
    end
    r.ImGui_SameLine(ctx, 0, button_spacing)
    if r.ImGui_Button(ctx, "SNAP", button_width_row2) then
        CaptureFirstTrackFX()
    end
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Make screenshot of First FX on the selected Track (must be floating)")
    end
    

    -- Derde rij knoppen
    local num_buttons_row3 = 3
    local button_width_row3 = CalculateButtonWidths(track_info_width, num_buttons_row3, button_spacing)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), IsMuted(TRACK) and 0xFF0000FF or config.button_background_color)
    if r.ImGui_Button(ctx, "MUTE", button_width_row3) then
    ToggleMute(TRACK)
    end
    r.ImGui_PopStyleColor(ctx)
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Mute selected Track")
    end
    r.ImGui_SameLine(ctx, 0, button_spacing)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), IsSoloed(TRACK) and 0xFF0000FF or config.button_background_color)
    if r.ImGui_Button(ctx, "SOLO", button_width_row3) then
    ToggleSolo(TRACK)
    end
    r.ImGui_PopStyleColor(ctx)
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Solo selected Track")
    end
    r.ImGui_SameLine(ctx, 0, button_spacing)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), IsArmed(TRACK) and 0xFF0000FF or config.button_background_color)
    if r.ImGui_Button(ctx, "ARM", button_width_row3) then
    ToggleArm(TRACK)
    end
    r.ImGui_PopStyleColor(ctx)
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Arm selected Track")
    end
    
    end
end

local BUTTON_HEIGHT = 80
local function ShowTrackFX()
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then
        r.ImGui_Text(ctx, "No track selected")
        return
    end
    r.ImGui_Text(ctx, "FX on Track:")
    local availWidth, availHeight = r.ImGui_GetContentRegionAvail(ctx)
    local listHeight = availHeight - BUTTON_HEIGHT
    if r.ImGui_BeginChild(ctx, "TrackFXList", -1, listHeight) then
        local fx_count = r.TrackFX_GetCount(TRACK)
        if fx_count > 0 then
            local track_bypassed = r.GetMediaTrackInfo_Value(TRACK, "I_FXEN") == 0
            for i = 0, fx_count - 1 do
                local retval, fx_name = r.TrackFX_GetFXName(TRACK, i, "")
                local is_open = r.TrackFX_GetFloatingWindow(TRACK, i)
                local is_enabled = r.TrackFX_GetEnabled(TRACK, i)
                
                local display_name = is_enabled and fx_name or fx_name .. " (Bypassed)"
                
                r.ImGui_PushID(ctx, i)
                r.ImGui_BeginGroup(ctx)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00FF00FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00DD00FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF0000FF)
                if r.ImGui_Button(ctx, "##updown", 13, 13) then
                    if i > 0 then
                        r.TrackFX_CopyToTrack(TRACK, i, TRACK, i - 1, true)
                    end
                    r.ImGui_SetNextWindowFocus(ctx)
                end
                if r.ImGui_IsItemHovered(ctx) and config.show_tooltips then
                    r.ImGui_SetTooltip(ctx, "Left click up / Right click down")
                end
                if r.ImGui_IsItemClicked(ctx, 1) and i < fx_count - 1 then
                    r.TrackFX_CopyToTrack(TRACK, i, TRACK, i + 1, true)
                    r.ImGui_SetNextWindowFocus(ctx)
                end
                r.ImGui_PopStyleColor(ctx, 3)
                r.ImGui_SameLine(ctx)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
                r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) - 3)
                
                if not is_enabled or track_bypassed then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)  -- Grijze kleur voor gebypaste plugins
                end
                
                if r.ImGui_Button(ctx, display_name, 0, 13) then
                    if is_open then
                        r.TrackFX_Show(TRACK, i, 2)
                    else
                        r.TrackFX_Show(TRACK, i, 3)
                    end
                end
                
                if not is_enabled or track_bypassed then
                    r.ImGui_PopStyleColor(ctx)
                end
                
                r.ImGui_PopStyleColor(ctx, 3)
                if r.ImGui_BeginPopupContextItem(ctx) then
                    if r.ImGui_MenuItem(ctx, "Delete") then
                        r.TrackFX_Delete(TRACK, i)
                    end
                    if r.ImGui_MenuItem(ctx, "Copy to all tracks") then
                        IS_COPYING_TO_ALL_TRACKS = true
                        local track_count = r.CountTracks(0)
                        for j = 0, track_count - 1 do
                            local target_track = r.GetTrack(0, j)
                            if target_track ~= TRACK then
                                r.TrackFX_CopyToTrack(TRACK, i, target_track, r.TrackFX_GetCount(target_track), false)
                            end
                        end
                        IS_COPYING_TO_ALL_TRACKS = false
                    end
                    if r.ImGui_MenuItem(ctx, "Copy Plugin") then
                        copied_plugin = {track = TRACK, index = i}
                    end
                    
                    if r.ImGui_MenuItem(ctx, "Paste Plugin", nil, copied_plugin ~= nil) then
                        if copied_plugin then
                            local _, orig_name = r.TrackFX_GetFXName(copied_plugin.track, copied_plugin.index, "")
                            r.TrackFX_AddByName(TRACK, orig_name, false, -1000)
                        end
                    end
                    
                    if r.ImGui_MenuItem(ctx, is_enabled and "Bypass plugin" or "Unbypass plugin") then
                        r.TrackFX_SetEnabled(TRACK, i, not is_enabled)
                    end
                    if table.contains(favorite_plugins, fx_name) then
                        if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                            RemoveFromFavorites(fx_name)
                        end
                    else
                        if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                            AddToFavorites(fx_name)
                        end
                    end
                    r.ImGui_EndPopup(ctx)
                end
                
                r.ImGui_EndGroup(ctx)
                r.ImGui_PopID(ctx)
            end
        else
            r.ImGui_Text(ctx, "No FX on Track")
        end
        if copied_plugin then
            local is_empty_track = fx_count == 0
            local button_text = is_empty_track and "Paste Plugin" or "Paste Plugin at End"
            if r.ImGui_Button(ctx, button_text) then
                local _, orig_name = r.TrackFX_GetFXName(copied_plugin.track, copied_plugin.index, "")
                local insert_position = is_empty_track and 0 or fx_count
                r.TrackFX_CopyToTrack(copied_plugin.track, copied_plugin.index, TRACK, insert_position, false)
            end
        
            if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtermuisklik
                r.ImGui_OpenPopup(ctx, "PastePluginMenu")
            end
        
            if r.ImGui_BeginPopup(ctx, "PastePluginMenu") then
                if r.ImGui_MenuItem(ctx, "Paste Plugin at Beginning") then
                    local _, orig_name = r.TrackFX_GetFXName(copied_plugin.track, copied_plugin.index, "")
                    r.TrackFX_CopyToTrack(copied_plugin.track, copied_plugin.index, TRACK, 0, false)
                end
                r.ImGui_EndPopup(ctx)
            end
        end
        
        r.ImGui_EndChild(ctx)
    end
end

local function ShowItemFX()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then return end
    local take = r.GetActiveTake(item)
    if not take then return end
    r.ImGui_Text(ctx, "FX on Item:")
    local availWidth, availHeight = r.ImGui_GetContentRegionAvail(ctx)
    local listHeight = availHeight - BUTTON_HEIGHT
    if r.ImGui_BeginChild(ctx, "ItemFXList", -1, listHeight) then
        local fx_count = r.TakeFX_GetCount(take)
        if fx_count > 0 then
            for i = 0, fx_count - 1 do
                local retval, fx_name = r.TakeFX_GetFXName(take, i, "")
                local is_open = r.TakeFX_GetFloatingWindow(take, i)
                if r.ImGui_Selectable(ctx, fx_name) then
                    if is_open then
                        r.TakeFX_Show(take, i, 2)
                    else
                        r.TakeFX_Show(take, i, 3)
                    end
                end
                if r.ImGui_IsItemClicked(ctx, 1) then
                    r.TakeFX_Delete(take, i)
                    break
                end
            end
        else
            r.ImGui_Text(ctx, "No FX on Item")
        end
        r.ImGui_EndChild(ctx)
    end
end

local function GetTrackType(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return "No Track"
    end
    if track == r.GetMasterTrack(0) then return "Master" end
    local audio_count = 0
    local midi_count = 0
    local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0
    local is_child = r.GetParentTrack(track) ~= nil
    local item_count = r.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take then
            if r.TakeIsMIDI(take) then
                midi_count = midi_count + 1
            else
                audio_count = audio_count + 1
            end
        end
    end
    local track_type = ""
    if is_folder then
        track_type = "Folder "
    elseif is_child then
        track_type = "Child "
    end
    if audio_count > 0 and midi_count > 0 then
        return track_type .. "Mixed"
    elseif midi_count > 0 then
        return track_type .. "MIDI"
    elseif audio_count > 0 then
        return track_type .. "Audio"
    else
        return track_type .. "Empty"
    end
end
-------------------------------------------------------------------
function Frame()
    local search = FilterBox()
    if search then return end
    if config.show_favorites and #favorite_plugins > 0 then
        r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
        r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
        if r.ImGui_BeginMenu(ctx, "FAVORITES") then
            DrawFavorites()
            r.ImGui_EndMenu(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 3)
        r.ImGui_PopStyleColor(ctx, 2)
    end
    for i = 1, #CAT_TEST do
        local category_name = CAT_TEST[i].name
        if (category_name == "ALL PLUGINS" and config.show_all_plugins) or
           (category_name == "DEVELOPER" and config.show_developer) or
           (category_name == "FOLDERS" and config.show_folders) or
           (category_name == "FX CHAINS" and config.show_fx_chains) or
           (category_name == "TRACK TEMPLATES" and config.show_track_templates) or
           (category_name == "CATEGORY" and config.show_category) then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
            if r.ImGui_BeginMenu(ctx, CAT_TEST[i].name) then
                if CAT_TEST[i].name == "FX CHAINS" then
                    DrawFxChains(CAT_TEST[i].list)
                elseif CAT_TEST[i].name == "TRACK TEMPLATES" then
                    DrawTrackTemplates(CAT_TEST[i].list)
                else
                    DrawItems(CAT_TEST[i].list, CAT_TEST[i].name)
                 end
                r.ImGui_EndMenu(ctx)
            end
            r.ImGui_PopStyleVar(ctx, 3)
            r.ImGui_PopStyleColor(ctx, 2)
        end
    end
        if config.show_container then
            if r.ImGui_Selectable(ctx, "CONTAINER") then
                r.TrackFX_AddByName(TRACK, "Container", false,
                    -1000 - r.TrackFX_GetCount(TRACK))
                LAST_USED_FX = "Container"
                if config.close_after_adding_fx then
                    SHOULD_CLOSE_SCRIPT = true
                end
            end
        end
        if config.show_video_processor then
            if r.ImGui_Selectable(ctx, "VIDEO PROCESSOR") then
                r.TrackFX_AddByName(TRACK, "Video processor", false,
                    -1000 - r.TrackFX_GetCount(TRACK))
                LAST_USED_FX = "Video processor"
                if config.close_after_adding_fx then
                    SHOULD_CLOSE_SCRIPT = true
                end
            end
        end
        if config.show_projects then
            if r.ImGui_Selectable(ctx, "PROJECTS") then
                show_media_browser = not show_media_browser
                if show_media_browser then
                    LoadProjects()
                    ClearScreenshotCache()
                end
            end
        end
        if LAST_USED_FX then
            if r.ImGui_Selectable(ctx, "RECENT: " .. LAST_USED_FX) then
                r.TrackFX_AddByName(TRACK, LAST_USED_FX, false,
                    -1000 - r.TrackFX_GetCount(TRACK))
                if config.close_after_adding_fx then
                    SHOULD_CLOSE_SCRIPT = true
                end
            end
        end
    r.ImGui_Separator(ctx)
    if ADD_FX_TO_ITEM then
        ShowItemFX()
    else
        ShowTrackFX()
    end
    if not r.ImGui_IsAnyItemHovered(ctx) then
        current_hovered_plugin = nil
    end
end

local function get_sws_colors()
    local colors = {}
    local reaper_resource_path = reaper.GetResourcePath()
    local color_dir = reaper_resource_path .. "/Color/"

    local function read_color_file(filename)
        local file_path = color_dir .. filename
        if reaper.file_exists(file_path) then
            for line in io.lines(file_path) do
                local k, v = string.match(line, "^(custcolor%d+)=(%d+)$")
                if k and v then
                    table.insert(colors, tonumber(v))
                end
            end
        end
    end
    local i = 0
    local file = reaper.EnumerateFiles(color_dir, i)
    while file do
        if string.match(file, "%.SWSColor$") then
            read_color_file(file)
            break  
        end
        i = i + 1
        file = reaper.EnumerateFiles(color_dir, i)
    end

    return colors, #colors > 0
end
function moveTrackUp(track)
    local id = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    if id > 1 then
        r.SetOnlyTrackSelected(track)
        r.ReorderSelectedTracks(id - 2, 0)
        r.TrackList_AdjustWindows(false)
    end
end

local function getScriptsIniPath()
    return r.GetResourcePath() .. "/Scripts/user_scripts.ini"
end

local function createEmptyUserScriptsIni()
    local file = io.open(getScriptsIniPath(), "w")
    if file then
        file:write("# User defined scripts\n")
        file:close()
    end
end

local function loadUserScripts()
    local scripts = {}
    local file = io.open(getScriptsIniPath(), "r")
    if file then
        local currentScript = {}
        for line in file:lines() do
            if line:match("^%[Script%]") then
                if currentScript.name and currentScript.command_id then
                    table.insert(scripts, currentScript)
                end
                currentScript = {}
            elseif line:match("^name=") then
                currentScript.name = line:match("^name=(.*)")
            elseif line:match("^command_id=") then
                currentScript.command_id = line:match("^command_id=(.*)")
            end
        end
        if currentScript.name and currentScript.command_id then
            table.insert(scripts, currentScript)
        end
        file:close()
    end
    return scripts
end

local function saveUserScript(name, command_id)
    local file = io.open(getScriptsIniPath(), "a")
    if file then
        file:write(string.format("\n[Script]\nname=%s\ncommand_id=%s\n", name, command_id))
        file:close()
        userScripts = loadUserScripts()  -- Herlaad de scripts
        r.ShowMessageBox("Script added: " .. name, "Script added", 0)
    end
end


local show_add_script_popup = false
local new_script_name = ""
local new_command_id = ""

local function showAddScriptPopup()
    if r.ImGui_BeginPopupModal(ctx, "Add User Script", nil, r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar()) then
        r.ImGui_Text(ctx, "Enter script details:")
        _, new_script_name = r.ImGui_InputText(ctx, "Script Name", new_script_name)
        _, new_command_id = r.ImGui_InputText(ctx, "Command ID", new_command_id)
        if r.ImGui_Button(ctx, "Add") and new_script_name ~= "" and new_command_id ~= "" then
            saveUserScript(new_script_name, new_command_id)
            r.ImGui_CloseCurrentPopup(ctx)
            show_add_script_popup = false
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel") then
            r.ImGui_CloseCurrentPopup(ctx)
            show_add_script_popup = false
        end
        r.ImGui_EndPopup(ctx)
    end
end
local function removeUserScript(index)
    table.remove(userScripts, index)
    local file = io.open(getScriptsIniPath(), "w")
    if file then
        for _, script in ipairs(userScripts) do
            file:write(string.format("[Script]\nname=%s\ncommand_id=%s\n\n", script.name, script.command_id))
        end
        file:close()
    end
end
-----------------------------------------------------------------
function Main()
    userScripts = loadUserScripts()
    local prev_track = TRACK
    TRACK = is_master_track_selected and r.GetMasterTrack(0) or r.GetSelectedTrack(0, 0)
    if TRACK and TRACK ~= prev_track then
        if config.auto_refresh_fx_list then
            FX_LIST_TEST, CAT_TEST = MakeFXFiles()
        end
    end
    if TRACK ~= last_selected_track and selected_folder == "Current Track FX" then
        ClearScreenshotCache()
        update_search_screenshots = true
    end
    last_selected_track = TRACK
        ProcessTextureLoadQueue()
    if r.time_precise() % 300 < 1 then -- Elke 5 minuten
        ClearScreenshotCache(true)
    end
   
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 2)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 3, 3)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), config.button_background_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), config.button_hover_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Tab(), config.tab_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabHovered(), config.tab_hovered_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), config.frame_bg_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), config.frame_bg_hover_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), config.frame_bg_active_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.dropdown_bg_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), r.ImGui_ColorConvertDouble4ToU32(0.7, 0.7, 0.7, 1.0))
    r.ImGui_PushFont(ctx, NormalFont)
    r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
    r.ImGui_SetNextWindowSizeConstraints(ctx, 140, 200, 16384, 16384)   
    handleDocking() 
    local visible, open = r.ImGui_Begin(ctx, 'TK FX BROWSER', true, window_flags)
    dock = r.ImGui_GetWindowDockID(ctx)
    if visible then
        if config.show_screenshot_window then
            if screenshot_search_results and #screenshot_search_results > 0 then
                selected_folder = nil
            elseif config.default_folder and selected_folder == nil then
                selected_folder = config.default_folder
            end
            ShowScreenshotWindow()
        end
        if bulk_screenshot_progress > 0 and bulk_screenshot_progress < 1 then
            local progress_text = string.format("Loading %d/%d (%.1f%%)", loaded_fx_count, total_fx_count, bulk_screenshot_progress * 100)
            r.ImGui_ProgressBar(ctx, bulk_screenshot_progress, -1, 0, progress_text)
        end
        if TRACK then
            local track_color, text_color = GetTrackColorAndTextColor(TRACK)
            local track_name = GetTrackName(TRACK)
            local track_type = GetTrackType(TRACK)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 4)
            local window_width = r.ImGui_GetWindowWidth(ctx)
            local track_info_width = math.max(window_width - 20, 125)  -- Minimaal 125, of vensterbreedte - 20

            if r.ImGui_BeginChild(ctx, "TrackInfo", track_info_width, 50, r.ImGui_WindowFlags_NoScrollbar()) then
                -- Stel de stijlen voor de knoppen in
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)  -- Transparante knop
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3F3F3F7F)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x7F7F7F7F)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
            
                -- Voeg de '+' knop toe linksboven
                r.ImGui_SetCursorPos(ctx, 0, 0)
                r.ImGui_PushFont(ctx, IconFont)
                if r.ImGui_Button(ctx, '\u{0050}', 20, 20) then
                    config.show_screenshot_window = not config.show_screenshot_window
                    ClearScreenshotCache()
                    GetPluginsForFolder(selected_folder)
                end
                r.ImGui_PopFont(ctx)
            
                -- Voeg de 'M/T' knop toe in het midden
                local window_width = r.ImGui_GetWindowWidth(ctx)
                local button_width = 20  -- De breedte van de knop
                local pos_x = (window_width - button_width) * 0.5  -- Bereken de x-positie voor het midden
                r.ImGui_SetCursorPos(ctx, pos_x, 0)
                if r.ImGui_Button(ctx, is_master_track_selected and '##M' or '##T', button_width, 20) then
                    is_master_track_selected = not is_master_track_selected
                    TRACK = is_master_track_selected and r.GetMasterTrack(0) or r.GetSelectedTrack(0, 0)
                end

                r.ImGui_PushFont(ctx, IconFont)
                -- Voeg de instellingenknop toe rechtsboven
                r.ImGui_SetCursorPos(ctx, window_width - 20, 0)
                if r.ImGui_Button(ctx, show_settings and '\u{0047}' or '\u{0047}', 20, 20) then
                    show_settings = not show_settings
                end
            
                -- Herstel de stijlen
                r.ImGui_PopFont(ctx)
                r.ImGui_PopStyleColor(ctx, 4)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                r.ImGui_PushFont(ctx, LargeFont)
                local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                local window_width = r.ImGui_GetWindowWidth(ctx)
                local pos_x = (window_width - text_width -7) * 0.5
                local window_height = r.ImGui_GetWindowHeight(ctx)
                local text_height = r.ImGui_GetTextLineHeight(ctx)
                local pos_y = (window_height - text_height) * 0.3
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)  -- Volledig doorzichtige knop
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)  -- Licht grijs bij hover
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)  -- Donkerder grijs bij klik
                r.ImGui_SetCursorPos(ctx, pos_x, pos_y)
                if r.ImGui_Button(ctx, track_name) then
                    show_rename_popup = true
                    new_track_name = track_name
                end
                r.ImGui_PopStyleColor(ctx, 3)
                r.ImGui_PopFont(ctx)
                r.ImGui_PushFont(ctx, NormalFont)
                if r.ImGui_IsItemClicked(ctx, 1) then  -- Rechtermuisklik
                    r.ImGui_OpenPopup(ctx, "TrackContextMenu")
                end
                if not keep_context_menu_open then
                    pinned_menu_pos_x, pinned_menu_pos_y = nil, nil
                end
                
                if keep_context_menu_open and pinned_menu_pos_x then
                    r.ImGui_SetNextWindowPos(ctx, pinned_menu_pos_x, pinned_menu_pos_y)
                end
                
                if r.ImGui_BeginPopupContextItem(ctx, "TrackContextMenu") or (keep_context_menu_open and r.ImGui_BeginPopup(ctx, "TrackContextMenu")) then
                    if keep_context_menu_open and not pinned_menu_pos_x then
                        pinned_menu_pos_x, pinned_menu_pos_y = r.ImGui_GetWindowPos(ctx)
                    end
                    
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                    
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
                    r.ImGui_BeginGroup(ctx)
                    if r.ImGui_Button(ctx, keep_context_menu_open and "Close Menu " or "Lock Menu ") then
                        keep_context_menu_open = not keep_context_menu_open
                        if not keep_context_menu_open then
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    end
                    r.ImGui_SameLine(ctx)
                    r.ImGui_Text(ctx, "|")
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, " Add Script") then
                        show_add_script_popup = true
                        keep_context_menu_open = false
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                    r.ImGui_EndGroup(ctx)
                    r.ImGui_PopStyleVar(ctx)
            
                    if not config.hide_default_titlebar_menu_items then
                        if r.ImGui_MenuItem(ctx, "Color Picker") then
                            show_color_picker = true
                            keep_context_menu_open = false
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                        if r.ImGui_MenuItem(ctx, "Duplicate Track") then
                            r.Main_OnCommand(40062, 0)  -- Track: Duplicate tracks
                        end
                        if r.ImGui_MenuItem(ctx, "Delete Track") then
                            r.DeleteTrack(TRACK)
                        end
                        if r.ImGui_MenuItem(ctx, "Add New Track") then
                            r.InsertTrackAtIndex(r.GetNumTracks(), true)
                        end
                        if r.ImGui_MenuItem(ctx, "Show/Hide Envelope") then
                            r.Main_OnCommand(41151, 0)
                        end
                        if r.ImGui_MenuItem(ctx, "Move Track Up") then
                            moveTrackUp(TRACK)
                        end
                        if r.ImGui_MenuItem(ctx, "Move Track Down") then
                            r.ReorderSelectedTracks(r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER") + 1, 0)
                        end
                        
                        if r.ImGui_MenuItem(ctx, "Go to First Track") then
                            local first_track = r.GetTrack(0, 0)
                            if first_track then r.SetOnlyTrackSelected(first_track) end
                        end
                        if r.ImGui_MenuItem(ctx, "Go to Last Track") then
                            local last_track = r.GetTrack(0, r.GetNumTracks() - 1)
                            if last_track then r.SetOnlyTrackSelected(last_track) end
                        end
                        r.ImGui_Separator(ctx)
                        r.ImGui_Text(ctx, "3rd party: " )
                        local send_buddy_id = r.NamedCommandLookup("_RS39115aaa5f19081d275c9a8dbdf990de23d6d9fa")
                        
                        if r.ImGui_MenuItem(ctx, "Send Buddy (Oded)") then
                            if send_buddy_id ~= 0 then
                                r.Main_OnCommand(send_buddy_id, 0)
                            else
                                r.ShowMessageBox("Send Buddy (Oded) is not installed. Install this action to use this function.", "Action not found", 0)
                            end
                        end
                        local track_snapshot_id = r.NamedCommandLookup("_RSf9d888b66c9bb4971001d0788a38a00a930ad499")
                        if r.ImGui_MenuItem(ctx, "Track Snapshot (daniellumertz)") then
                            if track_snapshot_id ~= 0 then
                                r.Main_OnCommand(track_snapshot_id, 0)
                            else
                                r.ShowMessageBox("Track Snapshot (daniellumertz) is not installed. Install this action to use this function.", "Action not found", 0)
                            end
                        end
                        local track_icon_selector_id = r.NamedCommandLookup("_RSd166add798d24704e0ae7dfd5a50848258c1a3e9")
                        if r.ImGui_MenuItem(ctx, "Track Icon Selector (Reapertips)") then
                            if track_icon_selector_id ~= 0 then
                                r.Main_OnCommand(track_icon_selector_id, 0)
                            else
                                r.ShowMessageBox("Track Icon Selector (Reapertips) is not installed. Install this action to use this function.", "Action not found", 0)
                            end
                        end
                        local track_icon_selector_id = r.NamedCommandLookup("_RS4466532563f07c099f8ec22b9b79e819e0d3f3d4")
                        if r.ImGui_MenuItem(ctx, "Paranormal FX Router (Sexan)") then
                            if track_icon_selector_id ~= 0 then
                                r.Main_OnCommand(track_icon_selector_id, 0)
                            else
                                r.ShowMessageBox("Paranormal FX Router (Sexan) is not installed. Install this action to use this function.", "Action not found", 0)
                            end
                        end
                        r.ImGui_Separator(ctx)
                    end
                
                    for i, script in ipairs(userScripts) do
                        if r.ImGui_MenuItem(ctx, script.name) then
                            local script_id = r.NamedCommandLookup(script.command_id)
                            if script_id ~= 0 then
                                r.Main_OnCommand(script_id, 0)
                            else
                                r.ShowMessageBox(script.name .. " is not installed. Install this action to use this function.", "Action not found", 0)
                            end
                        end
                        if r.ImGui_BeginPopupContextItem(ctx) then
                            if r.ImGui_MenuItem(ctx, "Remove") then
                                removeUserScript(i)
                            end
                            r.ImGui_EndPopup(ctx)
                        end
                    end
                    
                    r.ImGui_PopStyleColor(ctx)
                    r.ImGui_EndPopup(ctx)
                end
                
                if keep_context_menu_open and not r.ImGui_IsPopupOpen(ctx, "TrackContextMenu") then
                    r.ImGui_OpenPopup(ctx, "TrackContextMenu")
                end
                if show_rename_popup then
                    local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                    r.ImGui_SetNextWindowPos(ctx, mouse_x, mouse_y, r.ImGui_Cond_Appearing())
                    r.ImGui_OpenPopup(ctx, "Rename Track")
                end
                if r.ImGui_BeginPopupModal(ctx, "Rename Track", nil, r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar()) then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                    r.ImGui_Text(ctx, "Enter new track name:")
                    r.ImGui_SetNextItemWidth(ctx, 200)
                    local changed, value = r.ImGui_InputText(ctx, "##NewTrackName", new_track_name)
                    if changed then
                        new_track_name = value
                    end
                
                    if r.ImGui_Button(ctx, "Use First Plugin Name") then
                        local fx_count = r.TrackFX_GetCount(TRACK)
                        if fx_count > 0 then
                            local retval, fx_name = r.TrackFX_GetFXName(TRACK, 0, "")
                            if retval then
                                new_track_name = fx_name:match("^[^:]+:%s*(.+)") or fx_name
                                new_track_name = new_track_name:gsub("%s*%(.*%)", "")
                            end
                        end
                    end
                
                    if r.ImGui_Button(ctx, "OK", 120, 0) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
                        if new_track_name ~= "" then
                            r.GetSetMediaTrackInfo_String(TRACK, "P_NAME", new_track_name, true)
                        end
                        show_rename_popup = false
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Cancel", 120, 0) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
                        show_rename_popup = false
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                    r.ImGui_PopStyleColor(ctx)
                    r.ImGui_EndPopup(ctx)
                end
                
                    local sws_colors, has_sws_colors = get_sws_colors()
                    if show_color_picker then
                        local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                        r.ImGui_SetNextWindowPos(ctx, mouse_x, mouse_y, r.ImGui_Cond_Appearing())
                        r.ImGui_OpenPopup(ctx, "Change Track Color")
                    end
                    if r.ImGui_BeginPopupModal(ctx, "Change Track Color", nil, r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar()) then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)  
                        local sws_colors, has_sws_colors = get_sws_colors()
                        if has_sws_colors then
                            local columns = 4
                            local color_count = #sws_colors
                            local rows = math.max(1, math.ceil(color_count / columns))
                            for row = 1, rows do
                                r.ImGui_PushID(ctx, row)
                                for col = 1, columns do
                                    local color_index = (row - 1) * columns + col
                                    if color_index <= color_count then
                                        local color = sws_colors[color_index]
                                        local red, g, b = reaper.ColorFromNative(color)
                                        local color_vec4 = r.ImGui_ColorConvertDouble4ToU32(red/255, g/255, b/255, 1.0)
                                        
                                        if r.ImGui_ColorButton(ctx, "##SWSColor" .. color_index, color_vec4, 0, 30, 30) then
                                            local native_color = reaper.ColorToNative(red, g, b)|0x1000000
                                            reaper.SetTrackColor(TRACK, native_color)
                                            show_color_picker = false
                                            r.ImGui_CloseCurrentPopup(ctx)
                                        end
                                        if col < columns then r.ImGui_SameLine(ctx) end
                                    end
                                end
                                r.ImGui_PopID(ctx)
                            end
                        else
                            r.ImGui_Text(ctx, "No SWS Colors Found...")
                            if r.ImGui_Button(ctx, "Open Reaper Color Picker") then
                                local current_color = r.GetTrackColor(TRACK)
                                local ok, new_color = r.GR_SelectColor(current_color)
                                if ok then
                                    r.SetTrackColor(TRACK, new_color)
                                end
                                show_color_picker = false
                                r.ImGui_CloseCurrentPopup(ctx)
                            end
                        end
                    
                        r.ImGui_Separator(ctx)
                    if r.ImGui_Button(ctx, "Cancel") or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
                        show_color_picker = false
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                    r.ImGui_PopStyleColor(ctx)
                    r.ImGui_EndPopup(ctx)
                end
                r.ImGui_PopFont(ctx)
                r.ImGui_PushFont(ctx, LargeFont)
                local type_text_width = r.ImGui_CalcTextSize(ctx, track_type)
                local type_pos_x = (window_width - type_text_width) * 0.5
                local type_pos_y = pos_y + text_height
                r.ImGui_SetCursorPos(ctx, type_pos_x, type_pos_y)
                r.ImGui_Text(ctx, track_type)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)  -- Doorzichtige knop
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3F3F3F7F)  -- Licht grijs bij hover
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x7F7F7F7F)  -- Donkerder grijs bij klik
                r.ImGui_SetCursorPos(ctx, -2, window_height - 20)
                if r.ImGui_Button(ctx, "<", 20, 20) then
                    local prev_track = r.GetTrack(0, r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER") - 2)
                    if prev_track then r.SetOnlyTrackSelected(prev_track) end
                end
                r.ImGui_SetCursorPos(ctx, window_width - 16, window_height - 20)
                if r.ImGui_Button(ctx, ">", 20, 20) then
                    local next_track = r.GetTrack(0, r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER"))
                    if next_track then r.SetOnlyTrackSelected(next_track) end
                end
                r.ImGui_PopStyleColor(ctx, 3)
                r.ImGui_PopFont(ctx)
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_PopStyleColor(ctx)

            if not config.hideTopButtons then
                local button_spacing = 3
                local button_width = (track_info_width - (2 * button_spacing)) / 3
                if r.ImGui_Button(ctx, "SCAN", button_width, 20) then
                    FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = MakeFXFiles()
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Scan for new Plugins")
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, SHOW_PREVIEW and "ON" or "OFF", button_width, 20) then
                    SHOW_PREVIEW = not SHOW_PREVIEW
                    if SHOW_PREVIEW and current_hovered_plugin then
                        LoadPluginScreenshot(current_hovered_plugin)
                    end
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Show or hide Plugin Preview in item list")
                end
                r.ImGui_SameLine(ctx)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF5555FF)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF0000FF)
                if r.ImGui_Button(ctx, 'QUIT', button_width, 20) then 
                    open = false 
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Quit the script (You can also use ESC)")
                end
                reaper.ImGui_PopStyleColor(ctx, 3)
                if r.ImGui_Button(ctx, ADD_FX_TO_ITEM and "ITEM" or "TRCK", button_width, 20) then
                    ADD_FX_TO_ITEM = not ADD_FX_TO_ITEM
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Switch between Track or Item")
                end
                reaper.ImGui_SameLine(ctx)
                if WANT_REFRESH then
                    WANT_REFRESH = nil
                    UpdateChainsTrackTemplates(CAT)
                end
                if r.ImGui_Button(ctx, is_master_track_selected and "MSTR" or "NORM", button_width, 20) then
                    is_master_track_selected = not is_master_track_selected
                    TRACK = is_master_track_selected and r.GetMasterTrack(0) or r.GetSelectedTrack(0, 0)
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Switch between normal and master Track")
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "DOCK", button_width, 20) then
                    change_dock = true 
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Dock/Undock the window")
                end
                if reaper.ImGui_Button(ctx, START and "STOP" or "BULK", button_width, 20) then
                    StartBulkScreenshot()
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Start or stop Bulk Screenshots")
                end
                r.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "CLRR", button_width, 20) then
                    show_confirm_clear = true
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Clear the Screenshot folder")
                end
                r.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "FLDR", button_width, 20) then
                    OpenScreenshotsFolder()
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Open Screenshot folder location")
                end
                if show_confirm_clear then
                    ShowConfirmClearPopup()
                end
            end
            Frame()
        else
            r.ImGui_Text(ctx, "NO TRACK SELECTED")
            r.ImGui_PushFont(ctx, IconFont)
            if r.ImGui_Button(ctx, show_settings and "\u{0047}" or "\u{0047}", 20, 20) then
                show_settings = not show_settings
            end
            r.ImGui_PopFont(ctx)
        end
        if SHOW_PREVIEW and current_hovered_plugin then 
            ShowPluginScreenshot() 
        end
        DrawBottomButtons()
        if show_settings then
            show_settings = ShowConfigWindow()
        end
        if show_add_script_popup then
            r.ImGui_OpenPopup(ctx, "Add User Script")
            showAddScriptPopup()
        end
        
        if check_esc_key() then open = false end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 3)
    r.ImGui_PopStyleColor(ctx, 11)
    if SHOULD_CLOSE_SCRIPT then
        return
    end
    if open then
        
        r.defer(Main)
    end
end
r.defer(Main)