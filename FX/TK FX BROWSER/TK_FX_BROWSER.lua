-- @description TK FX BROWSER
-- @author TouristKiller
-- @version 1.0.8:
-- @changelog:
--[[        
+ Better positioning when showing main window again after hiding
+ Better positioning when left docking the screenshot window to main window

              ---------------------TODO-----------------------------------------
            - Auto tracks and send /recieve for multi output plugin 
            - Meter functionality (Pre/post Peak) -- vooralsnog niet haalbaar
            - Improve distribution of screenshots in current track and project
            - Expand project files
            - Etc......
            
]]--        
--------------------------------------------------------------------------
local r                 = reaper
local script_path       = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator      = package.config:sub(1, 1)
package.path            = script_path .. "?.lua;"
local json              = require("json")
local screenshot_path   = script_path .. "Screenshots" .. os_separator
StartBulkScreenshot     = function() end
local DrawMeterModule   = dofile(script_path .. "DrawMeter.lua")
local TKFXBVars         = dofile(script_path .. "TKFXBVariables.lua")
local window_flags      = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar()

-- MISC
local needs_font_update = false
local selected_plugin = nil
browser_search_term = ""
local current_open_folder = nil
local ITEMS_PER_BATCH = 30
local loaded_items_count = ITEMS_PER_BATCH
local last_scroll_position = 0
local current_filtered_fx = {} 
local was_hidden = false

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
-- ACTION BROWSER
local allActions = {}
local action_search_term = ""
local categories = {
    ["Appearance and Themes"] = {},
    ["Automation"] = {},
    ["Editing"] = {},
    ["Markers and Regions"] = {},
    ["MIDI"] = {},
    ["Miscellaneous"] = {},
    ["Mixing and Effects"] = {},
    ["Project Management"] = {},
    ["Recording and Playback"] = {},
    ["Scripting and Customization"] = {},
    ["Synchronization and Tempo"] = {},
    ["Track and Item Management"] = {},
    ["Transport"] = {},
    ["View and Zoom"] = {}
}

--------------------------------------------------------------------------
ctx = r.ImGui_CreateContext('TK FX BROWSER')
--------------------------------------------------------------------------
-- FX LIST
local TRACK, LAST_USED_FX, FILTER, ADDFX_Sel_Entry
local FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = ReadFXFile()
if not FX_LIST_TEST or not CAT_TEST or not FX_DEV_LIST_FILE then
    FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = MakeFXFiles()
end
local PLUGIN_LIST = GetFXTbl()

local function get_safe_name(name)
    return (name or ""):gsub("[^%w%s-]", "_")
end
-- LOG
local log_file_path = script_path .. "screenshot_log.txt"
local function log_to_file(message)
    local file = io.open(log_file_path, "a")
    if file then
        file:write(message .. "\n")
        file:close()
    end
end
function CheckPluginCrashHistory(plugin_name)
    local file = io.open(log_file_path, "r")
    if file then
        for line in file:lines() do
            if line:match("CRASH: " .. plugin_name) then
                file:close()
                return true -- Plugin heeft eerder een crash veroorzaakt
            end
        end
        file:close()
    end
    return false
end
--------------------------------------------------------------------------
-- CONFIG
local function SetDefaultConfig()
    return {
        srcx = 0,
        srcy = 27,
        capture_height_offset = 0,
        screenshot_display_size = 250,
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
        slider_grab_gray = 136,  -- Waarde 0x88
        slider_grab_color = r.ImGui_ColorConvertDouble4ToU32(136/255, 136/255, 136/255, 1),
        slider_active_gray = 170,  -- Waarde 0xAA
        slider_active_color = r.ImGui_ColorConvertDouble4ToU32(170/255, 170/255, 170/255, 1),
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
        show_sends = true,
        show_actions = true,
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
        screenshot_delay = 0.5,
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
        hideVolumeSlider = false,
        show_tags = true,
        hideMeter = false,
        show_screenshot_scrollbar = true,
        show_type_dividers = false,
        sort_alphabetically = false,
        screenshot_view_type = 1,
        show_screenshot_settings = true,
        show_only_dropdown = false,
        create_sends_folder = false,
        selected_font = 1,  -- 1 = Arial (eerste in de fonts array)
        show_notes = true,
        show_notes_widget =  false,
        track_notes_color = track_notes_color or 0xFFFFB366,  -- Default orange
        item_notes_color = item_notes_color or 0x6699FFFF,    -- Default blue
        last_used_project_location = last_used_project_location or PROJECTS_DIR,
        show_project_info = show_project_info or true,
        hide_main_window = false,
        show_browser_panel = true,
        browser_panel_width = browser_panel_width or 200,
        use_pagination = true,
        use_masonry_layout = false,
        show_favorites_on_top = true
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
PROJECTS_DIR = config.last_used_project_location

local function ResetConfig()
    config = SetDefaultConfig()
    SaveConfig()
end
----------------------------------------------------------------------------------
-- FONTS
local TKFXfonts = { 
    "Arial",
    "Helvetica",
    "Verdana",
    "Tahoma",
    "Times New Roman",
    "Georgia",
    "Courier New",
    "Trebuchet MS",
    "Impact",
    "Roboto",
    "Open Sans",
    "Ubuntu",
    "Segoe UI",
    "Noto Sans",
    "Liberation Sans",
    "DejaVu Sans"
}
local IconFont = r.ImGui_CreateFont(script_path .. 'Icons-Regular.otf', 12)
r.ImGui_Attach(ctx, IconFont)

function exit()
    if ctx then
        
        if r.ImGui_ValidatePtr(NormalFont, 'ImGui_Resource*') then
            r.ImGui_Detach(ctx, NormalFont)
        end
        if r.ImGui_ValidatePtr(LargeFont, 'ImGui_Resource*') then
            r.ImGui_Detach(ctx, LargeFont)
        end
        if r.ImGui_ValidatePtr(TinyFont, 'ImGui_Resource*') then
            r.ImGui_Detach(ctx, TinyFont)
        end
        if r.ImGui_ValidatePtr(IconFont, 'ImGui_Resource*') then
            r.ImGui_Detach(ctx, IconFont)
        end
    end
end
r.atexit(exit)

function UpdateFonts()
    -- Eerst detachen we de bestaande fonts
    if r.ImGui_ValidatePtr(NormalFont, 'ImGui_Resource*') then
        r.ImGui_Detach(ctx, NormalFont)
    end
    if r.ImGui_ValidatePtr(LargeFont, 'ImGui_Resource*') then
        r.ImGui_Detach(ctx, LargeFont)
    end
    if r.ImGui_ValidatePtr(TinyFont, 'ImGui_Resource*') then
        r.ImGui_Detach(ctx, TinyFont)
    end

    -- Dan maken we nieuwe fonts aan
    NormalFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 13, r.ImGui_FontFlags_Bold())
    TinyFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 10)
    LargeFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 16, r.ImGui_FontFlags_Bold())

    -- En attachen ze weer
    r.ImGui_Attach(ctx, NormalFont)
    r.ImGui_Attach(ctx, TinyFont)
    r.ImGui_Attach(ctx, LargeFont)
end

-- Maak de fonts aan
NormalFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 13, r.ImGui_FontFlags_Bold())
LargeFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 16, r.ImGui_FontFlags_Bold())
TinyFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 10)

-- Attach de fonts
r.ImGui_Attach(ctx, NormalFont)
r.ImGui_Attach(ctx, LargeFont)
r.ImGui_Attach(ctx, TinyFont)

---------------------------------------------------------------------
local function EnsureFileExists(filepath)
    local file = io.open(filepath, "r")
    if not file then
        file = io.open(filepath, "w")
        file:close()
    else
        file:close()
    end
end

EnsureFileExists(script_path .. "tknotes.txt")

local function load_projects_info()
    local file = io.open(PROJECTS_INFO_FILE, "r")
    if file then
        local section = ""
        for line in file:lines() do
            if line == "[SETTINGS]" then
                section = "settings"
            elseif line == "[LOCATIONS]" then
                section = "locations"
            elseif line == "[PROJECTS]" then
                section = "projects"
            
            else
                if section == "settings" and line:match("^DEPTH|") then
                    max_depth = tonumber(line:match("^DEPTH|(.*)")) or 2
                elseif section == "locations" and line:match("^LOC|") then
                    local location = line:match("^LOC|(.*)")
                    table.insert(project_locations, location)
                elseif section == "projects" then
                    local name, path = line:match("([^|]+)|(.+)")
                    if name and path then
                        table.insert(projects, {name = name, path = path})
                    end
                end
            end
        end
        file:close()
    end
end


local function get_all_projects()
    local projects = {}
    local current_project_dir = config.last_used_project_location or PROJECTS_DIR
    local stack = {{path = current_project_dir, depth = 0}}
    -- Verwijder de lokale max_depth declaratie en gebruik de globale max_depth variabele
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
        if depth < max_depth then  -- Gebruik hier de globale max_depth
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
        file:write("[SETTINGS]\n")
        file:write("DEPTH|" .. max_depth .. "\n")
        
        file:write("[LOCATIONS]\n")
        for _, location in ipairs(project_locations) do
            file:write("LOC|" .. location .. "\n")
        end
        
        file:write("[PROJECTS]\n")
        for _, project in ipairs(projects) do
            file:write(string.format("%s|%s\n", project.name, project.path))
        end
        
        
        
        file:close()
    end
end


local function LoadProjects()
    projects = {}  -- Maak de lijst leeg
    filtered_projects = {}  -- Maak ook de gefilterde lijst leeg
    projects = get_all_projects()  -- Laad nieuwe projecten met huidige max_depth
    filtered_projects = projects
    save_projects_info(projects)
end

load_projects_info()
if #project_locations == 0 then
    table.insert(project_locations, PROJECTS_DIR)
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

local function LoadNotes()
    local notes = {}
    local file = io.open(script_path .. "tknotes.txt", "r")
    if file then
        local content = file:read("*all")
        for guid, note in content:gmatch("START_NOTE:([^|]+)|(.-)END_NOTE") do
            notes[guid] = note
        end
        file:close()
    end
    return notes
end
notes = LoadNotes()

local function SaveNotes()
    local file = io.open(script_path .. "tknotes.txt", "w")
    if file then
        for guid, note in pairs(notes) do
            if guid and note then
                file:write("START_NOTE:" .. guid .. "|" .. note .. "END_NOTE\n")
            end
        end
        file:close()
    end
end


local function SaveTags()
    local tags_data = {
        tracks = track_tags,
        colors = tag_colors,
        filters = tag_filters,
        available = available_tags, 
    }
    
    local file = io.open(script_path .. "track_tags.json", "w")
    if file then
        local json_str = json.encode(tags_data)
        file:write(json_str)
        file:close()
    end
end

local function LoadTags()
    local file = io.open(script_path .. "track_tags.json", "r")
    if file then
        local content = file:read("*all")
        file:close()
        local data = json.decode(content) or {}
        
        track_tags = data.tracks or {}
        tag_colors = data.colors or {}
        tag_filters = data.filters or {}
        available_tags = data.available or {}
    end
end
LoadTags()
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
    if -- new_folder ~= "Current Project FX" and 
       new_folder ~= "Projects" and 
       new_folder ~= "Actions" and 
       new_folder ~= "Sends/Receives" then
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
    if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") then
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
        config.plugin_visibility[plugin_name] = true -- Zet alle plugins standaard op zichtbaar
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
    if r.ImGui_Button(ctx, "Update Plugin List", 110) then
        FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = MakeFXFiles()
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_PushItemWidth(ctx, 120)
    local changed, new_search_filter = r.ImGui_InputTextWithHint(ctx, "##Search plugins", "SEARCH PLUGINS", search_filter)
    r.ImGui_PopItemWidth(ctx)
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
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, string.format(" | Total plugins: %d", #PLUGIN_LIST))
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, string.format(" | Shown plugins: %d", #filtered_plugins))
    local window_width = r.ImGui_GetWindowWidth(ctx)
        local column1_width = 45  -- Voor "Bulk" checkbox
        local column2_width = 45  -- Voor "Search" checkbox
        local column3_width = window_width - column1_width - column2_width - 20  -- Voor plugin naam

        -- Koppen
        r.ImGui_SetCursorPosX(ctx, column1_width / 2 - r.ImGui_CalcTextSize(ctx, "Bulk") / 2)
        r.ImGui_Text(ctx, "Bulk*")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column1_width + column2_width / 2 - r.ImGui_CalcTextSize(ctx, "Search") / 2)
        r.ImGui_Text(ctx, "Search")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column1_width + column2_width + 10)
        r.ImGui_Text(ctx, "Plugin Name")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, column1_width + column2_width + 155)
        r.ImGui_Text(ctx, "(*also affects taking individual screenshots)")
        r.ImGui_Separator(ctx)
    if r.ImGui_BeginChild(ctx, "PluginList", 0, -25) then
        for i, plugin in ipairs(filtered_plugins) do
            r.ImGui_SetCursorPosX(ctx, (column1_width - 35) / 2)
            
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
            r.ImGui_SetCursorPosX(ctx, column1_width + (column2_width - 35) / 2)
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
            
            r.ImGui_SetCursorPosX(ctx, column1_width + column2_width + 2)
            r.ImGui_Text(ctx, plugin.name)
        end
        r.ImGui_EndChild(ctx)
    end
    local button_width = (r.ImGui_GetWindowWidth(ctx) -28) / 4
    if r.ImGui_Button(ctx, "Select Bulk", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.plugin_visibility[plugin.name] = true
        end
        SaveConfig()
    end

    r.ImGui_SameLine(ctx)

    if r.ImGui_Button(ctx, "Deselect Bulk", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.plugin_visibility[plugin.name] = false
        end
        SaveConfig()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Select Search", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.excluded_plugins[plugin.name] = nil
        end
        SaveConfig()
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, "Deselect Search", button_width, 20) then
        for _, plugin in ipairs(filtered_plugins) do
            config.excluded_plugins[plugin.name] = true
        end
        SaveConfig()
    end
end

function GetPluginsForFolder(folder_name)
 
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

local function ShowConfigWindow()
    local function NewSection(title)
        r.ImGui_Spacing(ctx)
        r.ImGui_PushFont(ctx, NormalFont)
        r.ImGui_Text(ctx, title)
        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            r.ImGui_PopFont(ctx)
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
    end
    local config_open = true
    local window_width = 480
    local window_height = 560
    local column1_width = 10
    local column2_width = 120
    local column3_width = 250
    local column4_width = 360
    local slider_width = 110
    r.ImGui_SetNextWindowSize(ctx, window_width, window_height, r.ImGui_Cond_Always())
    r.ImGui_SetNextWindowSizeConstraints(ctx, window_width, window_height, window_width, window_height)
    local visible, open = r.ImGui_Begin(ctx, "Settings", true, window_flags | r.ImGui_WindowFlags_NoResize())
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x666666FF)  -- normale staat
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x888888FF)  -- actieve staat
    if visible then
        r.ImGui_PushFont(ctx, LargeFont)
        r.ImGui_Text(ctx, "TK FX BROWSER SETTINGS")
        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            r.ImGui_PopFont(ctx)
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_BeginTabBar(ctx, "SettingsTabs") then
            if r.ImGui_BeginTabItem(ctx, "GUI & VIEW") then
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
            r.ImGui_SetCursorPosX(ctx, column1_width)
            r.ImGui_Text(ctx, "Slider Grab")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            r.ImGui_PushItemWidth(ctx, slider_width)
            local changed_slider, new_slider_gray = r.ImGui_SliderInt(ctx, "##Slider Grab", config.slider_grab_gray, 0, 255)
            if changed_slider then
                config.slider_grab_gray = new_slider_gray
                config.slider_grab_color = r.ImGui_ColorConvertDouble4ToU32(new_slider_gray/255, new_slider_gray/255, new_slider_gray/255, 1)
            end
            r.ImGui_PopItemWidth(ctx)

            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            r.ImGui_Text(ctx, "Slider Active")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            r.ImGui_PushItemWidth(ctx, slider_width)
            local changed_slider_active, new_slider_active_gray = r.ImGui_SliderInt(ctx, "##Slider Active", config.slider_active_gray, 0, 255)
            if changed_slider_active then
                config.slider_active_gray = new_slider_active_gray
                config.slider_active_color = r.ImGui_ColorConvertDouble4ToU32(new_slider_active_gray/255, new_slider_active_gray/255, new_slider_active_gray/255, 1)
            end
            r.ImGui_Dummy(ctx, 0, 5)
            NewSection("MAIN WINDOW (Effects Browser Panel as well):")
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

            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            changed, new_value = r.ImGui_Checkbox(ctx, "Sends/Receives", config.show_sends)
            if changed then config.show_sends = new_value end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            changed, new_value = r.ImGui_Checkbox(ctx, "Actions", config.show_actions)
            if changed then config.show_actions = new_value end

            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 5)
         
            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.show_tooltips = r.ImGui_Checkbox(ctx, "Show Tooltips", config.show_tooltips)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.show_name_in_main_window = r.ImGui_Checkbox(ctx, "Show Plugin Names", config.show_name_in_main_window)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.show_screenshot_in_search = r.ImGui_Checkbox(ctx, "Show screenshots in Search", config.show_screenshot_in_search)

            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.hideTopButtons = r.ImGui_Checkbox(ctx, "No Top Buttons", config.hideTopButtons)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.hideBottomButtons = r.ImGui_Checkbox(ctx, "No Bottom Buttons", config.hideBottomButtons)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.hideVolumeSlider = r.ImGui_Checkbox(ctx, "Hide Volume Slider", config.hideVolumeSlider)
          
            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.show_tags = r.ImGui_Checkbox(ctx, "Show Tags", config.show_tags)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.show_notes_widget = r.ImGui_Checkbox(ctx, "Show Notes", config.show_notes_widget)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.hideMeter = r.ImGui_Checkbox(ctx, "Hide Meter", config.hideMeter)
            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.hide_default_titlebar_menu_items = r.ImGui_Checkbox(ctx, "Hide Default Titlebar Menu Items", config.hide_default_titlebar_menu_items)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.show_favorites_on_top = r.ImGui_Checkbox(ctx, "Show Favorites On Top", config.show_favorites_on_top)
            r.ImGui_Dummy(ctx, 0, 5)
            NewSection("SCREENSHOT WINDOW:")
            r.ImGui_SetCursorPosX(ctx, column1_width)
            local changed, new_value = r.ImGui_Checkbox(ctx, "Show Window", config.show_screenshot_window)
            if changed then
                config.show_screenshot_window = new_value
                ClearScreenshotCache()
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.show_name_in_screenshot_window = r.ImGui_Checkbox(ctx, "Show Names", config.show_name_in_screenshot_window)
            r.ImGui_SameLine(ctx)
           
            r.ImGui_SetCursorPosX(ctx, column3_width)
            local dock_changed, new_dock_value = r.ImGui_Checkbox(ctx, "Dock", config.dock_screenshot_window)
            if dock_changed then
                local main_dock_id = r.ImGui_GetWindowDockID(ctx)
                if main_dock_id == 0 then
                    config.dock_screenshot_window = new_dock_value
                    config.show_screenshot_window = true
                else
                    config.dock_screenshot_window = false
                end
                SaveConfig()
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            local dock_side_changed, new_dock_side = r.ImGui_Checkbox(ctx, "Dock Left", config.dock_screenshot_left)
            if dock_side_changed then
                local main_dock_id = r.ImGui_GetWindowDockID(ctx)
                if main_dock_id == 0 then
                    config.dock_screenshot_left = new_dock_side
                    config.show_screenshot_window = true
                end
                SaveConfig()
            end            

            r.ImGui_Dummy(ctx, 0, 5)
            r.ImGui_SetCursorPosX(ctx, column1_width)
            r.ImGui_Text(ctx, "Default Folder:")
            r.ImGui_SameLine(ctx, 0, 10)
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
                if r.ImGui_Selectable(ctx, "Projects", config.default_folder == "Projects") then
                    config.default_folder = "Projects"
                end
                if r.ImGui_Selectable(ctx, "Sends/Receives", config.default_folder == "Sends/Receives") then
                    config.default_folder = "Sends/Receives" 
                end
                if r.ImGui_Selectable(ctx, "Actions", config.default_folder == "Actions") then
                    config.default_folder = "Actions"
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
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.resize_screenshots_with_window = r.ImGui_Checkbox(ctx, "Auto Resize Screenshots", config.resize_screenshots_with_window)
            
            r.ImGui_SetCursorPosX(ctx, column1_width)
            r.ImGui_Text(ctx, "Font:")
            r.ImGui_SameLine(ctx, 0, 10)
            if r.ImGui_BeginCombo(ctx, "##Font", TKFXfonts[config.selected_font]) then
                for i, font_name in ipairs(TKFXfonts) do
                    local is_selected = (config.selected_font == i)
                    if r.ImGui_Selectable(ctx, font_name, is_selected) then
                        config.selected_font = i
                        needs_font_update = true
                        SaveConfig()
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            
            -- Bottom Buttons (Save, Cancel, Reset)
            r.ImGui_SetCursorPosY(ctx, window_height - 30)
            r.ImGui_Separator(ctx)
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

            if r.ImGui_BeginTabItem(ctx, "SCREENSHOTS") then
            NewSection("SETTINGS:")
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
            r.ImGui_SetCursorPosX(ctx, column1_width)
            r.ImGui_Text(ctx, "Screenshot Delay")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            r.ImGui_PushItemWidth(ctx, slider_width)
            _, config.screenshot_delay = r.ImGui_SliderDouble(ctx, "##Screenshot Delay", config.screenshot_delay, 0.5, 5.0, "%.1f sec")
            r.ImGui_PopItemWidth(ctx)
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
            r.ImGui_Separator(ctx)
            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.close_after_adding_fx = r.ImGui_Checkbox(ctx, "Close script after adding FX", config.close_after_adding_fx)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.include_x86_bridged = r.ImGui_Checkbox(ctx, "Include x86 bridged plugins", config.include_x86_bridged)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 5)

            local button_width = (window_width - 20) / 2
            local button_color = (START or PROCESS) and 0xFF0000FF or config.button_background_color
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_color)
            if r.ImGui_Button(ctx, "BULK Screenshots", button_width, 20) then
                if START or PROCESS then
                    STOP_REQUESTED = true
                    START = false
                    PROCESS = false
                else
                    START = true
                    PROCESS = true
                    StartBulkScreenshot()
                end
            end
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Show Screenshots Folder", button_width, 20) then
                OpenScreenshotsFolder()
            end
            if reaper.ImGui_Button(ctx, "Empty Screenshots Folder", button_width, 20) then
                show_confirm_clear = true
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Clear Log File", button_width, 20) then
                local log_file = io.open(log_file_path, "w")
                if log_file then
                    log_file:close()
                end
            end
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
        r.ImGui_PopStyleColor(ctx, 2)
        r.ImGui_End(ctx)
    end
    return config_open
end



local function EnsureTrackIconsFolderExists()
    local track_icons_path = script_path .. "TrackIcons" .. os_separator
    if not r.file_exists(track_icons_path) then
        local success = r.RecursiveCreateDirectory(track_icons_path, 0)
        if success then
            --log_to_file("Made TrackIcons Folder: " .. track_icons_path)
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
            --log_to_file("Made screenshot Folder: " .. screenshot_path)
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
        ClearScreenshotCache()
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
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then return end
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
end  --

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

local function GetTagColorAndTextColor(tag_color)
    local red, g, b, a = r.ImGui_ColorConvertU32ToDouble4(tag_color)
    local brightness = (red * 299 + g * 587 + b * 114) / 1000
    local text_color = brightness > 0.5 
        and r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1) 
        or r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
    return tag_color, text_color
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
                            

------------
local wait_time = config.screenshot_delay 
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
-----------
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
            h = top - bottom
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
        Wait(function()
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
                    h = top - bottom -- Oval (feedback vragen of dit werkt?)
                    ScreenshotOSX(filename, left, top, w, h)
                end
            
            print("Screenshot Saved: " .. filename)
            else
            print("No Plugin Window for " .. fx_name)
            end
        end)
    end
end
local function CaptureFirstTrackFX()
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then return end
    
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

local function GetNextPlugin(current_plugin)
    for i, plugin in ipairs(FX_LIST_TEST) do
        if plugin == current_plugin then
            if i < #FX_LIST_TEST then
                return FX_LIST_TEST[i + 1]
            end
        end
    end
    return "None - This is the last plugin"
end

local function MakeScreenshot(plugin_name, callback, is_individual)
    if not plugin_name then
        log_to_file("Error: Attempted to make screenshot with nil plugin name")
        if callback then callback() end
        return false
    end
    
    log_to_file("Starting screenshot process for: " .. plugin_name .. " at " .. os.date("%Y-%m-%d %H:%M:%S"))
  
    
    log_to_file("Next Up: " .. GetNextPlugin(plugin_name))
    if CheckPluginCrashHistory(plugin_name) then
        log_to_file("Skipping previously crashed plugin: " .. plugin_name)
        if callback then callback() end
        return false
    end

    local success = pcall(function()
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
                    log_to_file("Screenshot Success: " .. plugin_name .. " (ARA)")
                else
                    CaptureScreenshot(plugin_name, fx_index)
                    log_to_file("Screenshot Success: " .. plugin_name)
                end
                r.TrackFX_Show(TRACK, fx_index, 2)
                r.TrackFX_Delete(TRACK, fx_index)
                EnsurePluginRemoved(fx_index, callback)
            end)
        else
            if callback then callback() end
        end
    end)

    if not success then
        log_to_file("CRASH: " .. plugin_name .. " at " .. os.date("%Y-%m-%d %H:%M:%S"))
        if callback then callback() end
        return false
    end

    return true
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

StartBulkScreenshot = function()
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
                local window_x, window_y = r.ImGui_GetWindowPos(ctx)
                local vp_width, vp_height = r.ImGui_GetWindowSize(ctx)
                
                local viewport = r.ImGui_GetMainViewport(ctx)
                local viewport_pos_x = r.ImGui_Viewport_GetPos(viewport)
                local is_left_docked = (window_x - viewport_pos_x) < 20
                
                -- Bepaal positie op basis van dock status
                local window_pos_x
                if is_left_docked then
                    window_pos_x = mouse_x + 20  -- Toon rechts
                else
                    window_pos_x = mouse_x - display_width - 20  -- Toon links
                end
                
                local window_pos_y = mouse_y + 20
                
                -- Check voor verticale ruimte
                if window_pos_y + display_height > window_y + vp_height + 250 then
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

function GetFileSize(file_path)
    local file = io.open(file_path, "rb")
    if file then
        local size = file:seek("end")
        file:close()
        return size
    end
    return 0
end
function CountProjectFolderFiles(project_path)
    local folder = project_path:match("(.*[/\\])")
    local count = 0
    if folder then
        local handle = r.EnumerateFiles(folder, 0)
        while handle do
            count = count + 1
            handle = r.EnumerateFiles(folder, count)
        end
    end
    return count - 1  -- -1 omdat de eerste tel 0 is
end

-- Functie om send tracks te identificeren
local function IsSendTrack(track)
    local parent = r.GetParentTrack(track)
    if parent then
        local _, name = r.GetTrackName(parent)
        return name == "SEND TRACK"
    end
    local _, name = r.GetTrackName(track)
    return name == "SEND TRACK"
end

function ShowRoutingMatrix()
    -- Bereken de maximale breedte voor de legenda
    local max_name_width = 0
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local _, name = r.GetTrackName(track)
        local text_width = r.ImGui_CalcTextSize(ctx, i+1 .. ": " .. name)
        max_name_width = math.max(max_name_width, text_width)
    end

    local cell_size = 20
    local header_height = 20
    local left_margin = 20
    local legend_width = max_name_width + 20  -- Extra ruimte voor padding
    local matrix_width = (track_count + 1) * cell_size + left_margin + legend_width
    local matrix_height = (track_count + 1) * cell_size + header_height
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginChild(ctx, "RoutingMatrix", matrix_width, matrix_height) then
        -- Kolom headers (alleen nummers)
        for i = 0, track_count - 1 do
            local x = (i + 1) * cell_size + left_margin
            local y = 20
            r.ImGui_SetCursorPos(ctx, x + 5, y)
            r.ImGui_Text(ctx, tostring(i + 1))
        end
        
        -- Rij headers (alleen nummers)
        for i = 0, track_count - 1 do
            local y = (i + 1) * cell_size + header_height
            r.ImGui_SetCursorPos(ctx, 15, y + 2)
            r.ImGui_Text(ctx, tostring(i + 1))
        end
        
        -- Matrix cellen
        for src = 0, track_count - 1 do
            local src_track = r.GetTrack(0, src)
            for dst = 0, track_count - 1 do
                if src ~= dst then
                    local dst_track = r.GetTrack(0, dst)
                    local x = (dst + 1) * cell_size + left_margin
                    local y = (src + 1) * cell_size + header_height
                    
                    r.ImGui_SetCursorPos(ctx, x, y)
                    r.ImGui_PushID(ctx, string.format("cell_%d_%d", src, dst))
                    
                    local send_idx = GetSendIndex(src_track, dst_track)
                    local has_send = send_idx >= 0
                    
                    if has_send then
                        if IsSendTrack(dst_track) or IsSendTrack(src_track) then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00BFFFFF)  -- Lichtblauw voor send tracks
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x33CCFFFF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x0099CCFF)
                        else
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)  -- Rood vlak
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)  -- Lichter rood bij hover
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xCC0000FF)   -- Donkerder rood bij klik
                        end
                        
                        if r.ImGui_Button(ctx, "##send", cell_size-4, cell_size-4) then
                            r.RemoveTrackSend(src_track, 0, send_idx)
                        end
                        r.ImGui_PopStyleColor(ctx, 3)
                    else
                        if IsSendTrack(dst_track) or IsSendTrack(src_track) then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00BFFF33)  -- Lichtere lichtblauw voor lege send track cellen
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x33CCFF66)
                        else
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x333333FF)  -- Donkergrijs vlak
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x666666FF)
                        end
                        
                        if r.ImGui_Button(ctx, "##empty", cell_size-4, cell_size-4) then
                            r.CreateTrackSend(src_track, dst_track)
                        end
                        r.ImGui_PopStyleColor(ctx, 2)
                    end
                    
                    r.ImGui_PopID(ctx)
                end
            end
        end

        
        -- Legenda
        local legend_x = (track_count + 1) * cell_size + left_margin + 20
        r.ImGui_SetCursorPos(ctx, legend_x, 20)
        r.ImGui_Text(ctx, "Track Legend:")
        for i = 0, track_count - 1 do
            local track = r.GetTrack(0, i)
            local _, name = r.GetTrackName(track)
            r.ImGui_SetCursorPos(ctx, legend_x, 40 + (i * 20))
            r.ImGui_Text(ctx, string.format("%d: %s", i + 1, name))
        end
        
        r.ImGui_EndChild(ctx)
    end
end
function GetSendIndex(src_track, dst_track)
    local num_sends = r.GetTrackNumSends(src_track, 0)
    for i = 0, num_sends - 1 do
        local dest = r.GetTrackSendInfo_Value(src_track, 0, i, "P_DESTTRACK")
        if dest == dst_track then
            return i
        end
    end
    return -1
end

local function FilterActions()
    if #allActions == 0 then
        local i = 0
        repeat
            local retval, name = reaper.CF_EnumerateActions(0, i)
            if retval > 0 and name and name ~= "" then
                table.insert(allActions, {name = name, id = retval})
            end
            i = i + 1
        until retval <= 0
    end
end
FilterActions()
local function CategorizeActions()
    for _, action in ipairs(allActions) do
        local name = action.name:lower()
        if name:find("project") or name:find("file") or name:find("save") or name:find("open") then
            table.insert(categories["Project Management"], action)
        elseif name:find("edit") or name:find("cut") or name:find("copy") or name:find("paste") then
            table.insert(categories["Editing"], action)
        elseif name:find("track") or name:find("item") then
            table.insert(categories["Track and Item Management"], action)
        elseif name:find("record") or name:find("play") then
            table.insert(categories["Recording and Playback"], action)
        elseif name:find("mix") or name:find("fx") or name:find("effect") then
            table.insert(categories["Mixing and Effects"], action)
        elseif name:find("midi") then
            table.insert(categories["MIDI"], action)
        elseif name:find("marker") or name:find("region") then
            table.insert(categories["Markers and Regions"], action)
        elseif name:find("view") or name:find("zoom") then
            table.insert(categories["View and Zoom"], action)
        elseif name:find("automation") or name:find("envelope") then
            table.insert(categories["Automation"], action)
        elseif name:find("sync") or name:find("tempo") then
            table.insert(categories["Synchronization and Tempo"], action)
        elseif name:find("script") or name:find("action") then
            table.insert(categories["Scripting and Customization"], action)
        elseif name:find("theme") or name:find("color") then
            table.insert(categories["Appearance and Themes"], action)
        elseif name:find("play") or name:find("stop") or name:find("pause") or name:find("rewind") or name:find("forward") or name:find("transport") then
            table.insert(categories["Transport"], action)
        else
            table.insert(categories["Miscellaneous"], action)
        end
    end
end
CategorizeActions()
local function SearchActions(search_term)
    local filteredActions = {}
    for category, actions in pairs(categories) do
        filteredActions[category] = {}
        for _, action in ipairs(actions) do
            if action.name:lower():find(search_term:lower()) then
                local state = reaper.GetToggleCommandState(action.id)
                action.state = state
                table.insert(filteredActions[category], action)
            end
        end
    end
    return filteredActions
end

local function CreateSmartMarker(action_id)
    local cur_pos = reaper.GetCursorPosition()
    local marker_name = "!" .. action_id
    local _, num_markers, num_regions = reaper.CountProjectMarkers(0)
    local new_marker_id = num_markers + num_regions
    local red_color = reaper.ColorToNative(255, 0, 0)|0x1000000 -- Rood met alpha
    local result = reaper.AddProjectMarker2(0, false, cur_pos, 0, marker_name, new_marker_id, red_color)
    if result then
        reaper.UpdateTimeline()
    end
end 


local function ShowPluginContextMenu(plugin_name, menu_id)
    if type(plugin_name) == "table" then
        plugin_name = plugin_name.fx_name or plugin_name.name
    end
    
    if not plugin_name or type(plugin_name) ~= "string" then
        return
    end
    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "PluginContextMenu_" .. menu_id)
    end

    if r.ImGui_BeginPopup(ctx, "PluginContextMenu_" .. menu_id) then
        if r.ImGui_MenuItem(ctx, "Make Screenshot") then
            MakeScreenshot(plugin_name, nil, true)
        end
        
        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
            if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                AddPluginToSelectedTracks(plugin_name)
            end
            if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                AddPluginToAllTracks(plugin_name)
            end
        end
        
        local is_favorite = table.contains(favorite_plugins, plugin_name)
        if is_favorite then
            if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                RemoveFromFavorites(plugin_name)
                GetPluginsForFolder(selected_folder)
                ClearScreenshotCache()
            end
        else
            if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                AddToFavorites(plugin_name)
                GetPluginsForFolder(selected_folder)
                ClearScreenshotCache()
            end
        end
        
        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
            if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                local track_idx = r.CountTracks(0)
                r.InsertTrackAtIndex(track_idx, true)
                local new_track = r.GetTrack(0, track_idx)
                
                if config.create_sends_folder then
                    -- Existing send folder code
                    local folder_idx = -1
                    for k = 0, track_idx - 1 do
                        local track = r.GetTrack(0, k)
                        local _, name = r.GetTrackName(track)
                        if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                            folder_idx = k
                            break
                        end
                    end
                    
                    if folder_idx == -1 then
                        r.InsertTrackAtIndex(track_idx, true)
                        local folder_track = r.GetTrack(0, track_idx)
                        r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                        r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                        folder_idx = track_idx
                        track_idx = track_idx + 1
                        new_track = r.GetTrack(0, track_idx)
                    else
                        local last_track_in_folder
                        for k = folder_idx + 1, track_idx - 1 do
                            local track = r.GetTrack(0, k)
                            if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                last_track_in_folder = track
                            end
                        end
                        if last_track_in_folder then
                            r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                        end
                    end
                    
                    r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                end
                
                r.TrackFX_AddByName(new_track, plugin_name, false, -1000)
                r.CreateTrackSend(TRACK, new_track)
                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", plugin_name .. " Send", true)
            end
        end

        if r.ImGui_MenuItem(ctx, "Add with Multi-Output Setup") then
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                r.TrackFX_AddByName(TRACK, plugin_name, false, -1000)
                
                local num_outputs = tonumber(plugin_name:match("%((%d+)%s+out%)")) or 0
                local num_receives = math.floor(num_outputs / 2) - 1
                
                r.SetMediaTrackInfo_Value(TRACK, "I_NCHAN", num_outputs)
                
                for k = 1, num_receives do
                    local track_idx = r.CountTracks(0)
                    r.InsertTrackAtIndex(track_idx, true)
                    local new_track = r.GetTrack(0, track_idx)
                    
                    r.CreateTrackSend(TRACK, new_track)
                    local send_idx = r.GetTrackNumSends(TRACK, 0) - 1
                    
                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SRCCHAN", k*2)
                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_DSTCHAN", 0)
                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SENDMODE", 3)
                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_MIDIFLAGS", 0)
                    
                    local output_num = (k * 2) + 1
                    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", plugin_name .. " Out " .. output_num .. "-" .. (output_num + 1), true)
                end
            end
        end

        if config.hidden_names[plugin_name] then
            if r.ImGui_MenuItem(ctx, "Show Name") then
                config.hidden_names[plugin_name] = nil
                SaveConfig()
            end
        else
            if r.ImGui_MenuItem(ctx, "Hide Name") then
                config.hidden_names[plugin_name] = true
                SaveConfig()
            end
        end
        
        r.ImGui_EndPopup(ctx)
    end
end

local function ShowFXContextMenu(plugin, i)
    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "FXContextMenu_" .. i)
    end

    if r.ImGui_BeginPopup(ctx, "FXContextMenu_" .. i) then
        local track
        local fx_index

        if selected_folder == "Current Project FX" then
            track = r.GetTrack(0, plugin.track_number - 1)
            fx_index = (function()
                local fx_count = r.TrackFX_GetCount(track)
                for j = 0, fx_count - 1 do
                    local retval, fx_name = r.TrackFX_GetFXName(track, j, "")
                    if retval and fx_name == plugin.fx_name then
                        return j
                    end
                end
            end)()
        else
            track = TRACK
            fx_index = r.TrackFX_GetByName(TRACK, plugin.fx_name, false)
        end

        if r.ImGui_MenuItem(ctx, "Delete") then
            r.TrackFX_Delete(track, fx_index)
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
end


local function ShowFolderDropdown()
    if config.screenshot_view_type == 3 then return end
    
    local folders_category
    for i = 1, #CAT_TEST do
        if CAT_TEST[i].name == "FOLDERS" then
            folders_category = CAT_TEST[i].list
            break
        end
    end

    if folders_category and #folders_category > 0 then
        r.ImGui_SetNextWindowSizeConstraints(ctx, 0, 0, FLT_MAX, config.dropdown_menu_length * r.ImGui_GetTextLineHeightWithSpacing(ctx))
        local window_width = r.ImGui_GetContentRegionAvail(ctx)
        local dropdown_width = 110  
        r.ImGui_PushItemWidth(ctx, dropdown_width)
        --r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 2, 2)  
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)   
        
        if r.ImGui_BeginCombo(ctx, "##FolderDropdown", selected_folder or "Select Folder") then
            --[[if r.ImGui_Selectable(ctx, "No Folder", selected_folder == nil) then
                selected_folder = nil
            end]]--

            if r.ImGui_Selectable(ctx, "Favorites", selected_folder == "Favorites") then
                selected_folder = "Favorites"
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                screenshot_search_results = nil
                ClearScreenshotCache()
                GetPluginsForFolder(selected_folder)
            end
            if r.ImGui_Selectable(ctx, "Current Track FX", selected_folder == "Current Track FX") then
                selected_folder = "Current Track FX"
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                ClearScreenshotCache()
                r.ShowConsoleMsg("Selected folder set to: " .. tostring(selected_folder) .. "\n")
            end
            
            
            
            
            if r.ImGui_Selectable(ctx, "Current Project FX", selected_folder == "Current Project FX") then
                selected_folder = "Current Project FX"
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                ClearScreenshotCache()
                screenshot_search_results = nil
                GetPluginsForFolder("Current Project FX") -- Forceer het laden
                current_filtered_fx = nil -- Reset filtered fx
            end

            if r.ImGui_Selectable(ctx, "Projects", selected_folder == "Projects") then
                selected_folder = "Projects"
                show_media_browser = true
                show_sends_window = false
                show_action_browser = false
                ClearScreenshotCache()
            end
            if r.ImGui_Selectable(ctx, "Sends/Receives", selected_folder == "Sends/Receives") then
                selected_folder = "Sends/Receives"
                show_media_browser = false
                show_sends_window = true
                show_action_browser = false
                ClearScreenshotCache()
            end
            if r.ImGui_Selectable(ctx, "Actions", selected_folder == "Actions") then
                selected_folder = "Actions"
                show_media_browser = false
                show_sends_window = false
                show_action_browser = true
                ClearScreenshotCache()
            end

            
            r.ImGui_Separator(ctx)
          
            for i = 1, #folders_category do
                local is_selected = (selected_folder == folders_category[i].name)
                if r.ImGui_Selectable(ctx, folders_category[i].name .. "##folder_" .. i, is_selected) then
                    selected_folder = folders_category[i].name
                    UpdateLastViewedFolder(selected_folder)
                    screenshot_search_results = nil
                    show_media_browser = false
                    show_sends_window = false
                    show_action_browser = false
                    ClearScreenshotCache()
                    GetPluginsForFolder(selected_folder)
                end
            end
            r.ImGui_EndCombo(ctx)
     
        end
        r.ImGui_PopStyleVar(ctx)  
        r.ImGui_PopItemWidth(ctx)
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
    
    end
end

local function ShowScreenshotControls()
    r.ImGui_SameLine(ctx)
    ShowFolderDropdown()
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local button_width = 20
    local button_height = 20

    r.ImGui_SetCursorPos(ctx, window_width - button_width - 2, -2)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    
    r.ImGui_PushFont(ctx, IconFont)
    if r.ImGui_Button(ctx, "\u{0047}", button_height, button_width) then
        r.ImGui_OpenPopup(ctx, "ScreenshotControlsMenu")
    end
    r.ImGui_PopFont(ctx)
    
    r.ImGui_PopStyleColor(ctx, 3)

    if r.ImGui_BeginPopup(ctx, "ScreenshotControlsMenu") then
        if r.ImGui_MenuItem(ctx, config.show_screenshot_scrollbar and "Hide Scrollbar" or "Show Scrollbar") then
            config.show_screenshot_scrollbar = not config.show_screenshot_scrollbar
            SaveConfig()
        end

        if r.ImGui_MenuItem(ctx, config.screenshot_view_type == 3 and "Show Dropdown" or "Hide Dropdown") then
            config.screenshot_view_type = config.screenshot_view_type == 3 and 1 or 3
            
            if config.screenshot_view_type == 1 then
                config.show_screenshot_settings = true
                config.show_only_dropdown = false
            else
                config.show_screenshot_settings = false
                config.show_only_dropdown = false
            end
            SaveConfig()
        end
        if r.ImGui_MenuItem(ctx, config.show_name_in_screenshot_window and "Hide Names" or "Show Names") then
            config.show_name_in_screenshot_window = not config.show_name_in_screenshot_window
            SaveConfig()
        end

        r.ImGui_Separator(ctx)
        
        -- Screenshot size settings
        if r.ImGui_MenuItem(ctx, "Use Global Size", "", config.use_global_screenshot_size) then
            config.use_global_screenshot_size = not config.use_global_screenshot_size
            SaveConfig()
        end

        if config.use_global_screenshot_size then
            r.ImGui_PushItemWidth(ctx, 150)
            local changed, new_size = r.ImGui_SliderInt(ctx, "Global Size", config.global_screenshot_size, 100, 500)
            if changed then
                config.global_screenshot_size = new_size
                display_size = new_size
                SaveConfig()
            end
            r.ImGui_PopItemWidth(ctx)
            
            if r.ImGui_MenuItem(ctx, "Reset Global Size") then
                config.global_screenshot_size = 200
                display_size = 200
                SaveConfig()
            end
        else
            if not config.resize_screenshots_with_window then
                local folder_key = selected_folder or (screenshot_search_results and "SearchResults") or "Default"
                local current_size = config.folder_specific_sizes[folder_key] or config.screenshot_window_size
                
                r.ImGui_PushItemWidth(ctx, 140)
                local changed, new_size = r.ImGui_SliderInt(ctx, "Folder Size", current_size, 100, 500)
                if changed then
                    config.folder_specific_sizes[folder_key] = new_size
                    display_size = new_size
                    SaveConfig()
                end
                r.ImGui_PopItemWidth(ctx)
                
                if r.ImGui_MenuItem(ctx, "Reset Folder Size") then
                    config.folder_specific_sizes[folder_key] = nil
                    display_size = config.screenshot_window_size
                    SaveConfig()
                end
            end
        end
        if r.ImGui_MenuItem(ctx, config.use_masonry_layout and "Normal Layout" or "Masonry Layout") then
            config.use_masonry_layout = not config.use_masonry_layout
            SaveConfig()
        end

        if r.ImGui_MenuItem(ctx, "Compact View", "", config.compact_screenshots) then
            config.compact_screenshots = not config.compact_screenshots
            SaveConfig()
        end
        if r.ImGui_Checkbox(ctx, "Paginering Browser Panel", config.use_pagination) then
            config.use_pagination = not config.use_pagination 
            SaveConfig()           
         end   
        

        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, config.show_browser_panel and "Hide Browser Panel" or "Show Browser Panel") then
            config.show_browser_panel = not config.show_browser_panel
            SaveConfig()
        end
        if r.ImGui_MenuItem(ctx, config.hide_main_window and "Show Main Window" or "Hide Main Window") then
            config.hide_main_window = not config.hide_main_window
            config.show_main_window = not config.hide_main_window
            SaveConfig()
        end
        if r.ImGui_MenuItem(ctx, "Close Window") then
            config.show_screenshot_window = false
            SaveConfig()
        end

        r.ImGui_EndPopup(ctx)
    end
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
            if r.ImGui_Selectable(ctx, item .. "##fxchain_" .. i) then
                if ADD_FX_TO_ITEM then
                    local selected_item = r.GetSelectedMediaItem(0, 0)
                    if selected_item then
                        local take = r.GetActiveTake(selected_item)
                        if take then
                            r.TakeFX_AddByName(take, table.concat({ path, os_separator, item, extension }), 1)
                        end
                    end
                else
                    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
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
    local deleted = false
    
    for i = 1, #tbl do
        if deleted then break end
        
        if tbl[i].dir then
            if r.ImGui_BeginMenu(ctx, tbl[i].dir) then
                local cur_path = table.concat({ path, os_separator, tbl[i].dir })
                DrawTrackTemplates(tbl[i], cur_path)
                r.ImGui_EndMenu(ctx)
            end
        elseif type(tbl[i]) ~= "table" then
            if r.ImGui_Selectable(ctx, tbl[i] .. "##template_" .. i) then
                local template_str = table.concat({ path, os_separator, tbl[i], extension })
                LoadTemplate(template_str)
            end
            
            if r.ImGui_IsItemClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "TrackTemplateOptions_" .. i)
            end
            
            if r.ImGui_BeginPopup(ctx, "TrackTemplateOptions_" .. i) then
                if r.ImGui_MenuItem(ctx, "Rename") then
                    local retval, new_name = r.GetUserInputs("Rename Track Template", 1, "New name:", tbl[i])
                    if retval then
                        local resource_path = r.GetResourcePath()
                        local templates_path = resource_path .. "/TrackTemplates"
                        local old_path = templates_path .. path .. os_separator .. tbl[i] .. extension
                        local new_path = templates_path .. path .. os_separator .. new_name .. extension
                        if os.rename(old_path, new_path) then
                            tbl[i] = new_name
                            FX_LIST_TEST, CAT_TEST = MakeFXFiles()
                            r.ShowMessageBox("Track Template renamed", "Success", 0)
                        else
                            r.ShowMessageBox("Could not rename Track Template", "Error", 0)
                        end
                    end
                end
                
                if r.ImGui_MenuItem(ctx, "Delete") then
                    local resource_path = r.GetResourcePath()
                    local templates_path = resource_path .. "/TrackTemplates"
                    local file_path = templates_path .. path .. os_separator .. tbl[i] .. extension
                    if os.remove(file_path) then
                        table.remove(tbl, i)
                        deleted = true
                        FX_LIST_TEST, CAT_TEST = MakeFXFiles()
                        r.ShowMessageBox("Track Template deleted", "Success", 0)
                    else
                        r.ShowMessageBox("Could not delete Track Template", "Error", 0)
                    end
                end
                r.ImGui_EndPopup(ctx)
            end
        end
    end
end


local ITEMS_PER_PAGE = 30

local function DrawBrowserItems(tbl, main_cat_name)
    for i = 1, #tbl do
        local filtered_fx = {}
        for _, fx in ipairs(tbl[i].fx) do
            if browser_search_term == "" or fx:lower():find(browser_search_term:lower(), 1, true) then
                table.insert(filtered_fx, fx)
            end
        end

        if #filtered_fx > 0 then
            r.ImGui_PushID(ctx, i)
            
            r.ImGui_Indent(ctx, 10)
            local header_text = tbl[i].name
            r.ImGui_Selectable(ctx, header_text)
            r.ImGui_Unindent(ctx, 10)
            
            if not tbl[i].current_page then tbl[i].current_page = 1 end
            local total_pages = math.ceil(#filtered_fx / ITEMS_PER_PAGE)
            
            if r.ImGui_IsItemClicked(ctx, 0) then
                selected_folder = tbl[i].name
                loaded_items_count = ITEMS_PER_BATCH
                current_filtered_fx = filtered_fx  
                if config.use_pagination then
                    local start_idx = (tbl[i].current_page - 1) * ITEMS_PER_PAGE + 1
                    local end_idx = math.min(start_idx + ITEMS_PER_PAGE - 1, #filtered_fx)
                    
                    screenshot_search_results = {}
                    for j = start_idx, end_idx do
                        table.insert(screenshot_search_results, {name = filtered_fx[j]})
                    end
                else
                    screenshot_search_results = {}
                    for j = 1, math.min(loaded_items_count, #filtered_fx) do
                        table.insert(screenshot_search_results, {name = filtered_fx[j]})
                    end
                end
                ClearScreenshotCache()
            end
            
            
            if r.ImGui_IsItemClicked(ctx, 1) then
                if current_open_folder == i then
                    tbl[i].is_open = false
                    current_open_folder = nil
                else
                    if current_open_folder then
                        tbl[current_open_folder].is_open = false
                    end
                    tbl[i].is_open = true
                    current_open_folder = i
                end
            end

            if config.use_pagination and total_pages > 1 then
                r.ImGui_Indent(ctx, 20)
                if r.ImGui_Button(ctx, "<", 15, 15) then
                    if tbl[i].current_page > 1 then
                        tbl[i].current_page = tbl[i].current_page - 1
                    else
                        tbl[i].current_page = total_pages
                    end
                    local new_start = (tbl[i].current_page - 1) * ITEMS_PER_PAGE + 1
                    local new_end = math.min(new_start + ITEMS_PER_PAGE - 1, #filtered_fx)
                    screenshot_search_results = {}
                    for j = new_start, new_end do
                        table.insert(screenshot_search_results, {name = filtered_fx[j]})
                    end
                    ClearScreenshotCache()
                end
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, string.format("%d/%d", tbl[i].current_page, total_pages))
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, ">", 15, 15) then
                    if tbl[i].current_page < total_pages then
                        tbl[i].current_page = tbl[i].current_page + 1
                    else
                        tbl[i].current_page = 1
                    end
                    local new_start = (tbl[i].current_page - 1) * ITEMS_PER_PAGE + 1
                    local new_end = math.min(new_start + ITEMS_PER_PAGE - 1, #filtered_fx)
                    screenshot_search_results = {}
                    for j = new_start, new_end do
                        table.insert(screenshot_search_results, {name = filtered_fx[j]})
                    end
                    ClearScreenshotCache()
                end
                r.ImGui_Unindent(ctx, 20)
            end
            
            if tbl[i].is_open then
                r.ImGui_Indent(ctx, 20)
                if config.use_pagination then
                    local start_idx = (tbl[i].current_page - 1) * ITEMS_PER_PAGE + 1
                    local end_idx = math.min(start_idx + ITEMS_PER_PAGE - 1, #filtered_fx)
                    
                    for j = start_idx, end_idx do
                        if r.ImGui_Selectable(ctx, filtered_fx[j]) then
                            selected_folder = nil
                            selected_individual_item = filtered_fx[j]
                            screenshot_search_results = {{name = filtered_fx[j]}}
                            ClearScreenshotCache()
                        end
                        ShowPluginContextMenu(filtered_fx[j], "unique_id_" .. i .. "_" .. j)
                    end
                else
                    for j = 1, #filtered_fx do
                        if r.ImGui_Selectable(ctx, filtered_fx[j]) then
                            selected_folder = nil
                            selected_individual_item = filtered_fx[j]
                            screenshot_search_results = {{name = filtered_fx[j]}}
                            ClearScreenshotCache()
                        end
                        ShowPluginContextMenu(filtered_fx[j], "unique_id_" .. i .. "_" .. j)
                    end
                end
                r.ImGui_Unindent(ctx, 20)
            end
            
            r.ImGui_PopID(ctx)
        end
    end
end



local function ItemMatchesSearch(item_name, search_term)
    search_term = search_term or ""
    if search_term == "" then return true end
    return item_name:lower():find(search_term:lower(), 1, true)
end

local function ShowBrowserPanel()
    if not config.show_browser_panel then return end
    
    r.ImGui_BeginChild(ctx, "BrowserSection", config.browser_panel_width, -1)
    
    -- Header binnen BrowserSection
    r.ImGui_BeginChild(ctx, "BrowserHeader", -1, 25)
    r.ImGui_PushItemWidth(ctx, config.browser_panel_width - 3)
    local changed, new_search = r.ImGui_InputTextWithHint(ctx, "##BrowserSearch", "Search...", browser_search_term)
    if changed then
        browser_search_term = new_search
    end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_EndChild(ctx)

    -- Browserinhoud
    r.ImGui_BeginChild(ctx, "BrowserContent", -1, -1)

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)

    -- FAVORITES
    r.ImGui_Selectable(ctx, "FAVORITES")
    if r.ImGui_IsItemClicked(ctx, 0) then
        selected_folder = "Favorites"
        show_media_browser = false
        show_sends_window = false
        show_action_browser = false
        screenshot_search_results = {}
        for _, fav in ipairs(favorite_plugins) do
            if fav:lower():find(browser_search_term:lower(), 1, true) then
                table.insert(screenshot_search_results, {name = fav})
            end
        end
        ClearScreenshotCache()
    end
    
    if r.ImGui_IsItemClicked(ctx, 1) then
        favorites_is_open = not favorites_is_open
    end
    
    if favorites_is_open then
        r.ImGui_Indent(ctx, 10)
        for i, fav in ipairs(favorite_plugins) do
            if ItemMatchesSearch(fav, browser_search_term) then    
                if r.ImGui_Selectable(ctx, fav) then
                    selected_folder = "Favorites"
                    screenshot_search_results = {{name = fav}}
                    ClearScreenshotCache()
                end
                ShowPluginContextMenu(fav, "favorites_" .. i)
            end
        end
        r.ImGui_Unindent(ctx, 10)
    end
    
-- CURRENT TRACK FX
r.ImGui_Selectable(ctx, "CURRENT TRACK FX")
if r.ImGui_IsItemClicked(ctx, 0) then
    selected_folder = "Current Track FX"
    show_media_browser = false
    show_sends_window = false
    show_action_browser = false
    ClearScreenshotCache()
    screenshot_search_results = nil
    filtered_plugins = GetCurrentTrackFX()
    -- Filter alleen voor weergave
    local display_plugins = {}
    for _, fx in ipairs(filtered_plugins) do
        if fx.fx_name:lower():find(browser_search_term:lower(), 1, true) then
            table.insert(display_plugins, fx)
        end
    end
    GetPluginsForFolder("Current Track FX")
end

if r.ImGui_IsItemClicked(ctx, 1) then
    current_track_fx_is_open = not current_track_fx_is_open
end

if current_track_fx_is_open then
    r.ImGui_Indent(ctx, 10)
    local current_track_fx = GetCurrentTrackFX()
    for i, fx in ipairs(current_track_fx) do
        if ItemMatchesSearch(fx.fx_name, browser_search_term) then
            if r.ImGui_Selectable(ctx, fx.fx_name) then
                selected_folder = "Current Track FX"
                screenshot_search_results = {{name = fx.fx_name}}
                ClearScreenshotCache()
            end
            ShowFXContextMenu({
                fx_name = fx.fx_name,
                track_number = fx.track_number
            }, "track_" .. i)  -- Unieke prefix toegevoegd
        end
    end
    r.ImGui_Unindent(ctx, 10)
end


    
-- CURRENT PROJECT FX
r.ImGui_Selectable(ctx, "CURRENT PROJECT FX")
if r.ImGui_IsItemClicked(ctx, 0) then
    selected_folder = "Current Project FX"
    show_media_browser = false
    show_sends_window = false
    show_action_browser = false
    ClearScreenshotCache()
    screenshot_search_results = nil
    local project_fx = GetCurrentProjectFX()
    current_filtered_fx = {}
    for _, fx in ipairs(project_fx) do
        table.insert(current_filtered_fx, fx.fx_name)
    end
    GetPluginsForFolder("Current Project FX")
end

if r.ImGui_IsItemClicked(ctx, 1) then
    current_project_fx_is_open = not current_project_fx_is_open
end

if current_project_fx_is_open then
    r.ImGui_Indent(ctx, 10)
    local project_fx = GetCurrentProjectFX()
    for i, fx in ipairs(project_fx) do
        if fx.fx_name:lower():find(browser_search_term:lower(), 1, true) then
            if r.ImGui_Selectable(ctx, fx.fx_name) then
                selected_folder = "Current Project FX"  
                screenshot_search_results = {{name = fx.fx_name}}
                ClearScreenshotCache()
            end
            ShowFXContextMenu({
                fx_name = fx.fx_name,
                track_number = fx.track_number
            }, "project_" .. i)  -- Unieke prefix toegevoegd
        end
    end
    r.ImGui_Unindent(ctx, 10)
end

r.ImGui_PopStyleColor(ctx, 3)
r.ImGui_PopStyleVar(ctx)

r.ImGui_Separator(ctx)

    
    for i = 1, #CAT_TEST do
        local category_name = CAT_TEST[i].name
        if (category_name == "ALL PLUGINS" and config.show_all_plugins) then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
            if r.ImGui_CollapsingHeader(ctx, "ALL PLUGINS") then
                DrawBrowserItems(CAT_TEST[i].list, CAT_TEST[i].name)
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleVar(ctx)
        end
        
        if (category_name == "DEVELOPER" and config.show_developer) then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
            if r.ImGui_CollapsingHeader(ctx, "DEVELOPER") then
                DrawBrowserItems(CAT_TEST[i].list, CAT_TEST[i].name)
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleVar(ctx)
        end
        
        if (category_name == "CATEGORY" and config.show_category) then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
            if r.ImGui_CollapsingHeader(ctx, "CATEGORY") then
                DrawBrowserItems(CAT_TEST[i].list, CAT_TEST[i].name)
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleVar(ctx)
        end
        
        
        if (category_name == "FOLDERS" and config.show_folders) then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
            
            if r.ImGui_CollapsingHeader(ctx, "FOLDERS") then
                for j = 1, #CAT_TEST[i].list do
                    local show_folder = browser_search_term == ""
                    for k = 1, #CAT_TEST[i].list[j].fx do
                        if CAT_TEST[i].list[j].fx[k]:lower():find(browser_search_term:lower(), 1, true) then
                            show_folder = true
                            break
                        end
                    end
                    
                    if show_folder then
                        r.ImGui_PushID(ctx, j)
                        r.ImGui_Indent(ctx, 10)
                        local header_text = CAT_TEST[i].list[j].name
                        r.ImGui_Selectable(ctx, header_text)
                        r.ImGui_Unindent(ctx, 10)
                        
                        if r.ImGui_IsItemClicked(ctx, 0) then
                            selected_folder = CAT_TEST[i].list[j].name
                            selected_plugin = nil
                            UpdateLastViewedFolder(selected_folder)
                            screenshot_search_results = nil
                            show_media_browser = false
                            show_sends_window = false
                            show_action_browser = false
                            ClearScreenshotCache()
                            GetPluginsForFolder(selected_folder)
                        end
                        
                        if r.ImGui_IsItemClicked(ctx, 1) then
                            if current_open_folder == j then
                                CAT_TEST[i].list[j].is_open = false
                                current_open_folder = nil
                            else
                                if current_open_folder then
                                    CAT_TEST[i].list[current_open_folder].is_open = false
                                end
                                CAT_TEST[i].list[j].is_open = true
                                current_open_folder = j
                            end
                        end
                        
                        if CAT_TEST[i].list[j].is_open then
                            r.ImGui_Indent(ctx, 20)
                            
                            local favorites = {}
                            local regular_plugins = {}
                            local all_plugins = {}
                            
                            -- Collect all plugins that match the search term
                            for k = 1, #CAT_TEST[i].list[j].fx do
                                local plugin_name = CAT_TEST[i].list[j].fx[k]
                                if plugin_name:lower():find(browser_search_term:lower(), 1, true) then
                                    if table.contains(favorite_plugins, plugin_name) then
                                        table.insert(favorites, plugin_name)
                                    else
                                        table.insert(regular_plugins, plugin_name)
                                    end
                                    table.insert(all_plugins, {
                                        name = plugin_name,
                                        is_favorite = table.contains(favorite_plugins, plugin_name)
                                    })
                                end
                            end
                            
                            if config.show_favorites_on_top then
                                -- Show favorites first
                                if #favorites > 0 then
                                    for _, plugin_name in ipairs(favorites) do
                                        if r.ImGui_Selectable(ctx, plugin_name) then
                                            selected_plugin = plugin_name
                                            selected_folder = nil
                                            screenshot_search_results = {{name = plugin_name}}
                                            ClearScreenshotCache()
                                            LoadPluginScreenshot(plugin_name)
                                        end
                                        ShowPluginContextMenu(plugin_name, "folders_favorites_" .. _)
                                    end
                                    
                                    -- Add separator if there are both favorites and regular plugins
                                    if #regular_plugins > 0 then
                                        if r.ImGui_Selectable(ctx, "--Favorites End--", false, r.ImGui_SelectableFlags_Disabled()) then end
                                    end
                                end
                                
                                -- Show regular plugins
                                for _, plugin_name in ipairs(regular_plugins) do
                                    if r.ImGui_Selectable(ctx, plugin_name) then
                                        selected_plugin = plugin_name
                                        selected_folder = nil
                                        screenshot_search_results = {{name = plugin_name}}
                                        ClearScreenshotCache()
                                        LoadPluginScreenshot(plugin_name)
                                    end
                                    ShowPluginContextMenu(plugin_name, "folders_regular_" .. _)
                                end
                            else
                                -- Show all plugins mixed together
                                for _, plugin in ipairs(all_plugins) do
                                    if r.ImGui_Selectable(ctx, plugin.name) then
                                        selected_plugin = plugin.name
                                        selected_folder = nil
                                        screenshot_search_results = {{name = plugin.name}}
                                        ClearScreenshotCache()
                                        LoadPluginScreenshot(plugin.name)
                                    end
                                    ShowPluginContextMenu(plugin.name, "folders_mixed_" .. _)
                                end
                            end
                            
                            r.ImGui_Unindent(ctx, 20)
                        end
                        
                        r.ImGui_PopID(ctx)
                    end
                end
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleVar(ctx)
        end
        

        if (category_name == "FX CHAINS" and config.show_fx_chains) then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1) 
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
            if r.ImGui_CollapsingHeader(ctx, "FX CHAINS") then
                r.ImGui_Indent(ctx, 10)
                DrawFxChains(CAT_TEST[i].list)
                r.ImGui_Unindent(ctx, 10)
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleVar(ctx)
        end
        
        if (category_name == "TRACK TEMPLATES" and config.show_track_templates) then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1) 
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
            if r.ImGui_CollapsingHeader(ctx, "TRACK TEMPLATES") then
                r.ImGui_Indent(ctx, 10)
                DrawTrackTemplates(CAT_TEST[i].list)
                r.ImGui_Unindent(ctx, 10)
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleVar(ctx)
        end  
    end
    r.ImGui_Separator(ctx)
    -- Extra opties
    if config.show_container then
        if r.ImGui_Selectable(ctx, "CONTAINER") then
            r.TrackFX_AddByName(TRACK, "Container", false, -1000 - r.TrackFX_GetCount(TRACK))
            LAST_USED_FX = "Container"
            if config.close_after_adding_fx then
                SHOULD_CLOSE_SCRIPT = true
            end
        end
    end
    
    if config.show_video_processor then
        if r.ImGui_Selectable(ctx, "VIDEO PROCESSOR") then
            r.TrackFX_AddByName(TRACK, "Video processor", false, -1000 - r.TrackFX_GetCount(TRACK))
            LAST_USED_FX = "Video processor"
            if config.close_after_adding_fx then
                SHOULD_CLOSE_SCRIPT = true
            end
        end
    end
    
    if config.show_projects then
        if r.ImGui_Selectable(ctx, "PROJECTS") then
            if not show_media_browser then
                UpdateLastViewedFolder(selected_folder)
                show_media_browser = true
                show_sends_window = false
                show_action_browser = false
                selected_folder = "Projects"
                LoadProjects()
            else
                show_action_browser = false
                show_media_browser = false
                show_sends_window = false
                selected_folder = last_viewed_folder
                GetPluginsForFolder(last_viewed_folder)
            end
            ClearScreenshotCache()
        end
    end
    
    if config.show_sends then
        if r.ImGui_Selectable(ctx, "SEND/RECEIVE") then
            if not show_sends_window then
                UpdateLastViewedFolder(selected_folder)
                show_sends_window = true
                show_media_browser = false
                show_action_browser = false
                selected_folder = "Sends/Receives"
            else
                show_action_browser = false
                show_media_browser = false
                show_sends_window = false
                selected_folder = last_viewed_folder
                GetPluginsForFolder(last_viewed_folder)
            end
            ClearScreenshotCache()
        end
    end
    
    if config.show_actions then
        if r.ImGui_Selectable(ctx, "ACTIONS") then
            if not show_action_browser then
                UpdateLastViewedFolder(selected_folder)
                show_action_browser = true
                show_media_browser = false
                show_sends_window = false
                selected_folder = "Actions"
            else
                show_action_browser = false
                show_media_browser = false
                show_sends_window = false
                selected_folder = last_viewed_folder
                GetPluginsForFolder(last_viewed_folder)
            end
            ClearScreenshotCache()
        end
    end
    
    if LAST_USED_FX and r.ValidatePtr(TRACK, "MediaTrack*") then
        if r.ImGui_Selectable(ctx, "RECENT: " .. LAST_USED_FX) then
            r.TrackFX_AddByName(TRACK, LAST_USED_FX, false, -1000 - r.TrackFX_GetCount(TRACK))
            if config.close_after_adding_fx then
                SHOULD_CLOSE_SCRIPT = true
            end
        end
    end
    r.ImGui_EndChild(ctx)
    r.ImGui_EndChild(ctx)
    
    -- Splitter
    r.ImGui_SameLine(ctx)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x666666FF)         -- Donkerder grijs
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x888888FF)  -- Lichter bij hover
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xAAAAAAFF)   -- Nog lichter bij klikken


    r.ImGui_Button(ctx, "##splitter", 2, -1)  
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local max_width = window_width - 150  

    if r.ImGui_IsItemActive(ctx) then
        config.browser_panel_width = config.browser_panel_width + r.ImGui_GetMouseDragDelta(ctx)
        r.ImGui_ResetMouseDragDelta(ctx)
        config.browser_panel_width = math.max(130, math.min(config.browser_panel_width, max_width))
        SaveConfig()
    end
        r.ImGui_PopStyleColor(ctx, 3)
        
        r.ImGui_SameLine(ctx)
end

local function CheckScrollAndLoadMore(all_plugins)
    if not config.use_pagination and all_plugins and #all_plugins > ITEMS_PER_BATCH then
        if r.ImGui_BeginChild(ctx, "ScreenshotList") then
            local current_scroll = r.ImGui_GetScrollY(ctx)
            local max_scroll = r.ImGui_GetScrollMaxY(ctx)
            
            if current_scroll > 0 and current_scroll/max_scroll > 0.7 and loaded_items_count < #all_plugins then
                local new_count = math.min(loaded_items_count + ITEMS_PER_BATCH, #all_plugins)
                if new_count > loaded_items_count then
                    for i = loaded_items_count + 1, new_count do
                        if all_plugins[i] then
                            table.insert(screenshot_search_results, {name = all_plugins[i]})
                        end
                    end
                    loaded_items_count = new_count
                end
            end
            r.ImGui_EndChild(ctx)
        end
    end
end

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

local function DrawMasonryLayout(screenshots)
    
    local available_width = r.ImGui_GetContentRegionAvail(ctx)
    local column_width = display_size + 10
    local num_columns = math.max(1, math.floor(available_width / column_width))
    local column_heights = {}
    local padding = config.compact_screenshots and 2 or 20
    
    for i = 1, num_columns do
        column_heights[i] = 0
    end
    
    for i, fx in ipairs(screenshots) do
        local shortest_column = 1
        for col = 2, num_columns do
            if column_heights[col] < column_heights[shortest_column] then
                shortest_column = col
            end
        end
        
        local pos_x = (shortest_column - 1) * column_width + padding
        local pos_y = column_heights[shortest_column]
        
        r.ImGui_SetCursorPos(ctx, pos_x, pos_y)
        
        local safe_name = fx.name:gsub("[^%w%s-]", "_")
        local screenshot_file = screenshot_path .. safe_name .. ".png"
        if r.file_exists(screenshot_file) then
            local texture = LoadSearchTexture(screenshot_file, fx.name)
            if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                local width, height = r.ImGui_Image_GetSize(texture)
                if width and height then
                    local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                    
                    r.ImGui_BeginGroup(ctx)
                    if r.ImGui_ImageButton(ctx, "##"..fx.name, texture, display_width, display_height) then
                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
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
                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                            if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                AddPluginToSelectedTracks(fx.name)
                            end
                            if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                AddPluginToAllTracks(fx.name)
                            end
                        end
                        if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                            AddToFavorites(fx.name)
                        end
                        if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                            RemoveFromFavorites(fx.name)
                        end
                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                            if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                                local track_idx = r.CountTracks(0)
                                r.InsertTrackAtIndex(track_idx, true)
                                local new_track = r.GetTrack(0, track_idx)
                                
                                if config.create_sends_folder then
                                    -- Zoek bestaande SEND TRACK folder of maak nieuwe
                                    local folder_idx = -1
                                    for i = 0, track_idx - 1 do
                                        local track = r.GetTrack(0, i)
                                        local _, name = r.GetTrackName(track)
                                        if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                            folder_idx = i
                                            break
                                        end
                                    end
                                    
                                    if folder_idx == -1 then
                                        -- Maak nieuwe folder
                                        r.InsertTrackAtIndex(track_idx, true)
                                        local folder_track = r.GetTrack(0, track_idx)
                                        r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                        r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                        folder_idx = track_idx
                                        track_idx = track_idx + 1
                                        new_track = r.GetTrack(0, track_idx)
                                    else
                                        -- Pas folder depth aan van huidige laatste track in folder
                                        local last_track_in_folder
                                        for i = folder_idx + 1, track_idx - 1 do
                                            local track = r.GetTrack(0, i)
                                            if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                last_track_in_folder = track
                                            end
                                        end
                                        if last_track_in_folder then
                                            r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                        end
                                    end
                                    
                                    -- Zet nieuwe track als laatste in de folder
                                    r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                                end
                                
                                
                                -- Gebruik de juiste plugin identifier voor elk menu
                                r.TrackFX_AddByName(new_track, fx.name, false, -1000)
                                r.CreateTrackSend(TRACK, new_track)
                                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", fx.name .. " Send", true)
                            end
                        end
                                                    
                        if r.ImGui_MenuItem(ctx, "Add with Multi-Output Setup") then
                            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                r.TrackFX_AddByName(TRACK, fx.name, false, -1000)
                                
                                local num_outputs = tonumber(fx.name:match("%((%d+)%s+out%)")) or 0
                                local num_receives = math.floor(num_outputs / 2) - 1
                                
                                r.SetMediaTrackInfo_Value(TRACK, "I_NCHAN", num_outputs)
                                
                                for k = 1, num_receives do
                                    local track_idx = r.CountTracks(0)
                                    r.InsertTrackAtIndex(track_idx, true)
                                    local new_track = r.GetTrack(0, track_idx)
                                    
                                    r.CreateTrackSend(TRACK, new_track)
                                    local send_idx = r.GetTrackNumSends(TRACK, 0) - 1
                                    
                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SRCCHAN", k*2)
                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_DSTCHAN", 0)
                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SENDMODE", 3)
                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_MIDIFLAGS", 0)
                                    
                                    local output_num = (k * 2) + 1
                                    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", fx.name .. " Out " .. output_num .. "-" .. (output_num + 1), true)
                                end
                            end
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
                        local max_name_length = 20  -- Maximum aantal karakters
                        local display_name = fx.name
                        if #display_name > max_name_length then
                            display_name = display_name:sub(1, max_name_length) .. "..."
                        end
                        local text_width = r.ImGui_CalcTextSize(ctx, display_name)
                        local text_x = (display_width - text_width) * 0.5
                        r.ImGui_SetCursorPosX(ctx, pos_x + text_x)
                        r.ImGui_Text(ctx, display_name)
                    end
                    r.ImGui_EndGroup(ctx)
                    
                    local total_height = display_height + 
                        (config.show_name_in_screenshot_window and not config.hidden_names[fx.name] and 20 or 0) + 
                        (config.compact_screenshots and 2 or 10)
                    
                    column_heights[shortest_column] = column_heights[shortest_column] + total_height
                end
            end
        end
    end
end





local function ShowScreenshotWindow()

    if config.default_folder and not initialized_default then
        if config.default_folder == "Projects" then
            show_media_browser = true
            show_sends_window = false
            show_action_browser = false
            selected_folder = nil
            LoadProjects()
        elseif config.default_folder == "Sends/Receives" then
            show_media_browser = false
            show_sends_window = true
            show_action_browser = false
            selected_folder = nil
        elseif config.default_folder == "Actions" then
            show_media_browser = false
            show_sends_window = false
            show_action_browser = true
            selected_folder = nil
        else
            selected_folder = config.default_folder
        end
        initialized_default = true
    end


    if screenshot_search_results and #screenshot_search_results > 0 then
        selected_folder = nil
    elseif config.default_folder and selected_folder == nil then
        selected_folder = config.default_folder
    end
    
    local main_window_pos_x, main_window_pos_y = r.ImGui_GetWindowPos(ctx)
    local main_window_width = r.ImGui_GetWindowWidth(ctx)
    local main_window_height = r.ImGui_GetWindowHeight(ctx)

    local browser_panel_width = config.show_browser_panel and config.browser_panel_width or 0
    local screenshot_min_width = 145  -- Minimum width for screenshot section
    local total_min_width = browser_panel_width + screenshot_min_width + 5  -- Add padding

    local min_width = config.show_browser_panel and total_min_width or screenshot_min_width
    local window_flags = r.ImGui_WindowFlags_NoTitleBar() |
                    r.ImGui_WindowFlags_NoFocusOnAppearing() |
                    
                    r.ImGui_WindowFlags_NoScrollbar()

    if config.dock_screenshot_window then
        local viewport = r.ImGui_GetMainViewport(ctx)
        local viewport_pos_x, viewport_pos_y = r.ImGui_Viewport_GetPos(viewport)
        local viewport_width = r.ImGui_Viewport_GetWorkSize(viewport)
        local gap = 10

        -- Check dock positie hoofdvenster
        local is_main_window_left_docked = (main_window_pos_x - viewport_pos_x) < 20
        local is_main_window_right_docked = (main_window_pos_x + main_window_width) > (viewport_pos_x + viewport_width - 20)
        
        -- Forceer tegenovergestelde dock positie
        if is_main_window_left_docked then
            config.dock_screenshot_left = false
        elseif is_main_window_right_docked then
            config.dock_screenshot_left = true
        end
        
        if config.dock_screenshot_left then
            -- Links docken: compenseer voor browser panel indien actief
            local browser_offset = (config.show_browser_panel and config.dock_screenshot_left) and (config.browser_panel_width + 5) or 0
            local left_pos = main_window_pos_x - config.screenshot_window_width - (2 * gap) - browser_offset
            r.ImGui_SetNextWindowPos(ctx, left_pos, main_window_pos_y, r.ImGui_Cond_Always())
        else
            -- Rechts docken: gebruik de volledige rechterkant van het hoofdvenster
            local right_pos = main_window_pos_x + main_window_width + (gap / 2)
            r.ImGui_SetNextWindowPos(ctx, right_pos, main_window_pos_y, r.ImGui_Cond_Always())
        end
    end

                    
    r.ImGui_SetNextWindowSizeConstraints(ctx, min_width, 200, FLT_MAX, FLT_MAX)
    r.ImGui_SetNextWindowSize(ctx, math.max(min_width, config.screenshot_window_width), config.screenshot_window_height or 600, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, "Screenshots##NoTitle", true, window_flags)
    if visible then
        ShowBrowserPanel()
        r.ImGui_SameLine(ctx)
        r.ImGui_BeginChild(ctx, "ScreenshotSection", -1, -1)
       
      
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), config.show_screenshot_scrollbar and 14 or 1)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 0)
        r.ImGui_PushFont(ctx, NormalFont)
        --r.ImGui_SetCursorPosY(ctx, 5)
    
        if show_media_browser then
            r.ImGui_PopStyleVar(ctx, 2)
            --r.ImGui_Text(ctx, "PROJECTS:")
            r.ImGui_SameLine(ctx)
            --ShowFolderDropdown()
        elseif show_sends_window then
            r.ImGui_PopStyleVar(ctx, 2)
           -- r.ImGui_Text(ctx, "SENDS /RECEIVES:")
            r.ImGui_SameLine(ctx)
            --ShowFolderDropdown()
        elseif show_action_browser then
            r.ImGui_PopStyleVar(ctx, 2)
            --r.ImGui_Text(ctx, "ACTIONS:")
            r.ImGui_SameLine(ctx)
           -- ShowFolderDropdown()
        else
           -- r.ImGui_Text(ctx, "SCREENSHOTS: " .. (FILTER or ""))
            r.ImGui_SameLine(ctx)
            --ShowFolderDropdown()

        end
        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            r.ImGui_PopFont(ctx)
        end


        --r.ImGui_Separator(ctx)

--------------------------------------------------------------------------------------
        -- PROJECTS GEDEELTE:
        if show_media_browser then
            ShowScreenshotControls()
            r.ImGui_Separator(ctx)
            local window_width = r.ImGui_GetContentRegionAvail(ctx)

            r.ImGui_PushItemWidth(ctx, window_width - 55)
            local changed, new_search_term = r.ImGui_InputTextWithHint(ctx, "##ProjectSearch", "SEARCH PROJECTS", project_search_term)
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
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "D", button_width, button_height) then
                show_project_dates = not show_project_dates
            end

            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "P", button_width, button_height) then
                show_project_paths = not show_project_paths
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "i", button_width, button_height) then
                show_project_info = not show_project_info
            end
            local window_width = r.ImGui_GetWindowWidth(ctx)
            r.ImGui_PushItemWidth(ctx, window_width - 55) 
            if r.ImGui_BeginCombo(ctx, "##Project Locations", PROJECTS_DIR) then
                for i, location in ipairs(project_locations) do
                    if r.ImGui_Selectable(ctx, location) then
                        PROJECTS_DIR = location
                        config.last_used_project_location = location
                        SaveConfig()
                        LoadProjects()
                    end
                    
                    if r.ImGui_IsItemClicked(ctx, 1) then  -- rechtermuisknop
                        r.ImGui_OpenPopup(ctx, "location_menu_" .. i)
                    end
                    
                    if r.ImGui_BeginPopup(ctx, "location_menu_" .. i) then
                        if r.ImGui_MenuItem(ctx, "Remove") then
                            table.remove(project_locations, i)
                            save_projects_info(projects)
                            LoadProjects()
                        end
                        r.ImGui_EndPopup(ctx)
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_PopItemWidth(ctx)

            r.ImGui_SameLine(ctx)
            r.ImGui_PushItemWidth(ctx, 35)
            if r.ImGui_BeginCombo(ctx, "##depth", tostring(max_depth)) then
                for i = 0, 4 do
                    if r.ImGui_Selectable(ctx, tostring(i)) then
                        max_depth = i
                        LoadProjects()
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_PopItemWidth(ctx)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "+", 12, 18) then
                local rv, path = r.JS_Dialog_BrowseForFolder("Select Project Folder", r.GetProjectPath())
                if rv and path then
                    path = path .. "\\"
                    table.insert(project_locations, path)
                    save_projects_info(projects)
                    LoadProjects()
                end
            end
            
            local window_height = r.ImGui_GetWindowHeight(ctx)
            local current_y = r.ImGui_GetCursorPosY(ctx)
            local footer_height = show_project_info and 175 or 1
            local available_height = window_height - current_y - footer_height
            -- Project List
            if r.ImGui_BeginChild(ctx, "ProjectsList", -1, available_height) then
                for i, project in ipairs(filtered_projects) do
                    local has_preview = r.file_exists(project.path .. "-PROX")
                    local display_name = project.name
                    
                    if has_preview then
                        display_name = display_name .. " [P]"
                    end
                    
                    if show_project_paths then
                        display_name = display_name .. " - [" .. project.path .. "]"
                    end
                    if show_project_dates and reaper.JS_File_Stat then
                        local retval, _, _, _, datetime = reaper.JS_File_Stat(project.path)
                        if retval and datetime then
                            display_name = display_name .. " - [" .. datetime .. "]"
                        end
                    end
                    
                    local is_selected = (selected_project and selected_project.path == project.path)
                    
                    if r.ImGui_Selectable(ctx, display_name, is_selected) then
                        selected_project = project
                        
                        if has_preview then
                            local source = r.PCM_Source_CreateFromFile(project.path .. "-PROX")
                            current_preview = r.CF_CreatePreview(source)
                            r.CF_Preview_SetValue(current_preview, "D_VOLUME", preview_volume)
                            current_source = source
                        else
                            current_preview = nil
                            current_source = nil
                        end
                        
                        current_project_info = {
                            path = project.path,
                            name = project.name,
                            has_preview = has_preview,  -- Add this line
                            length = has_preview and r.GetMediaSourceLength(current_source) or 0,
                            size = GetFileSize(project.path),
                            folder_files = CountProjectFolderFiles(project.path)
                        }
                    end
                                
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        r.ImGui_OpenPopup(ctx, "ProjectContextMenu_" .. i)
                    end
                    
                    if r.ImGui_BeginPopup(ctx, "ProjectContextMenu_" .. i) then
                        if r.ImGui_MenuItem(ctx, "Open Project") then
                            open_project(project.path)
                        end
                        
                        if r.ImGui_MenuItem(ctx, "Open in New Tab") then
                            r.Main_OnCommand(41929, 0)
                            r.Main_openProject(project.path)
                        end
                        
                        if r.ImGui_MenuItem(ctx, "Make Preview") then
                            local project_already_open = false
                            local proj_idx = 0
                            repeat
                                local proj = r.EnumProjects(proj_idx)
                                if proj then
                                    local path = r.GetProjectPathEx(proj)
                                    if path == project.path then
                                        project_already_open = true
                                        break
                                    end
                                end
                                proj_idx = proj_idx + 1
                            until not proj
                            
                            if not project_already_open then
                                r.Main_OnCommand(41929, 0)
                                r.Main_openProject(project.path)
                                r.Main_OnCommand(42332, 0)
                                r.Main_OnCommand(40860, 0)
                            else
                                r.Main_OnCommand(42332, 0)
                            end
                        end
                    
                        if r.ImGui_BeginMenu(ctx, "Play Project Audio") then
                            local project_directory = project.path:match("(.*[/\\])")
                            local audio_files = {}
                            
                            local idx = 0
                            local file = r.EnumerateFiles(project_directory, idx)
                            while file do
                                if file:match("%.wav$") or file:match("%.mp3$") or 
                                   file:match("%.aiff$") or file:match("%.ogg$") or 
                                   file:match("%.flac$") then
                                    table.insert(audio_files, file)
                                end
                                idx = idx + 1
                                file = r.EnumerateFiles(project_directory, idx)
                            end
                            
                            for _, filename in ipairs(audio_files) do
                                if r.ImGui_MenuItem(ctx, filename) then
                                    if current_preview then
                                        r.CF_Preview_StopAll()
                                    end
                                    local source = r.PCM_Source_CreateFromFile(project_directory .. filename)
                                    if source then
                                        current_preview = r.CF_CreatePreview(source)
                                        r.CF_Preview_SetValue(current_preview, "D_VOLUME", preview_volume)
                                        r.CF_Preview_Play(current_preview)
                                    end
                                end
                            end
                            
                            r.ImGui_EndMenu(ctx)
                        end
                        
                        
                        
                    
                        r.ImGui_EndPopup(ctx)
                    end
                    
                end
                r.ImGui_EndChild(ctx)
            end
            if show_project_info then
                -- Info Panel
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x333333FF)
                r.ImGui_Separator(ctx)
                
                if current_project_info then
                    -- Project Info
                    r.ImGui_Text(ctx, "Project Info:")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "Name: " .. current_project_info.name)
                    r.ImGui_Text(ctx, "Preview: " .. (current_project_info.has_preview and "Available" or "No Preview"))
                    r.ImGui_Text(ctx, "Length: " .. string.format("%.2f", current_project_info.length) .. " seconds")
                    r.ImGui_Text(ctx, "Size: " .. string.format("%.2f", current_project_info.size/1024/1024) .. " MB")
                    r.ImGui_Text(ctx, "Media files: " .. tostring(current_project_info.folder_files))
                    
                    local is_playing = current_preview and select(2, r.CF_Preview_GetValue(current_preview, "B_PLAY"))
                    if r.ImGui_Button(ctx, is_playing and "Stop" or "Play") then
                        if is_playing then
                            r.CF_Preview_StopAll()
                            current_preview = nil
                        else
                            if selected_project then
                                local source = r.PCM_Source_CreateFromFile(selected_project.path .. "-PROX")
                                current_preview = r.CF_CreatePreview(source)
                                r.CF_Preview_SetValue(current_preview, "D_VOLUME", preview_volume)
                                r.CF_Preview_Play(current_preview)
                            end
                        end
                    end
                    r.ImGui_SameLine(ctx)
                    r.ImGui_PushItemWidth(ctx, -1)
                    local rv, new_vol = r.ImGui_SliderDouble(ctx, "##Volume", preview_volume or 1.0, 0, 2, "%.1f")
                    if rv then
                        preview_volume = new_vol
                        if current_preview then
                            r.CF_Preview_SetValue(current_preview, "D_VOLUME", preview_volume)
                        end
                    end
                    r.ImGui_PopItemWidth(ctx)
                end
            
                --r.ImGui_SameLine(ctx)
                -- Progress Bar
                local rv, position = r.CF_Preview_GetValue(current_preview, "D_POSITION")
                local rv2, length = r.CF_Preview_GetValue(current_preview, "D_LENGTH")
                if position and length then
                    local progress = position / length
                    r.ImGui_ProgressBar(ctx, progress, -1, 20, string.format("%.1fs/%.1fs", position, length))
                end
                r.ImGui_Text(ctx, "Project:")
                r.ImGui_SameLine(ctx)
                r.ImGui_PushItemWidth(ctx, 75)
                if r.ImGui_BeginCombo(ctx, "##SaveOptions", "Save") then
                    if r.ImGui_Selectable(ctx, "Save") then
                        r.Main_OnCommand(40026, 0)
                    end
                    if r.ImGui_Selectable(ctx, "Save As") then
                        r.Main_OnCommand(40022, 0)
                    end
                    if r.ImGui_Selectable(ctx, "Save Template") then
                        r.Main_OnCommand(40394, 0)
                    end
                    r.ImGui_EndCombo(ctx)
                end
                r.ImGui_PopItemWidth(ctx)
                r.ImGui_PopStyleColor(ctx)   
            end
    -----------------------------------------------------------------------------------        
            -- SEND/RECEIVE GEDEELTE:
            elseif show_sends_window then
                ShowScreenshotControls()
                --ShowFolderDropdown()
                r.ImGui_Separator(ctx)
                      -- Calculate available height
                local window_height = r.ImGui_GetWindowHeight(ctx)
                local current_y = r.ImGui_GetCursorPosY(ctx)
                local footer_height = 40
                local available_height = window_height - current_y - footer_height

                if r.ImGui_BeginChild(ctx, "SendsReceivesList", 0, available_height) then
                    
                    if show_routing_matrix and show_matrix_exclusive then
                        ShowRoutingMatrix()
                    else
                    -- SENDS SECTIE
                    r.ImGui_Text(ctx, "SENDS:")
                    --r.ImGui_Separator(ctx)
                    
                    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                        local num_sends = r.GetTrackNumSends(TRACK, 0)
                        for i = 0, num_sends - 1 do
                            local send_track = r.GetTrackSendInfo_Value(TRACK, 0, i, "P_DESTTRACK")
                            if r.ValidatePtr(send_track, "MediaTrack*") then
                                local _, send_name = r.GetTrackName(send_track)
                                
                                r.ImGui_PushID(ctx, "send_" .. i)
                                local window_width = r.ImGui_GetWindowWidth(ctx)
                                
                
                                r.ImGui_PushItemWidth(ctx, window_width - 20)
                                if r.ImGui_TreeNode(ctx, send_name) then
                                    -- Volume slider
                                    r.ImGui_PushItemWidth(ctx, window_width - 60)
                                    local vol = r.GetTrackSendInfo_Value(TRACK, 0, i, "D_VOL")
                                    local vol_db = 20 * math.log(vol, 10)
                                    local changed, new_vol_db = r.ImGui_SliderDouble(ctx, "Vol", vol_db, -60, 12, "%.1f dB")
                                    if changed then
                                        local new_vol = math.exp(new_vol_db * math.log(10) / 20)
                                        r.SetTrackSendInfo_Value(TRACK, 0, i, "D_VOL", new_vol)
                                    end
                
                                    -- Pan slider
                                    local pan = r.GetTrackSendInfo_Value(TRACK, 0, i, "D_PAN")
                                    local changed_pan, new_pan = r.ImGui_SliderDouble(ctx, "Pan", pan, -1, 1, "%.2f")
                                    if changed_pan then
                                        r.SetTrackSendInfo_Value(TRACK, 0, i, "D_PAN", new_pan)
                                    end
                                    r.ImGui_PopItemWidth(ctx)
                
                                    -- Mute/Solo knoppen
                                    local mute = r.GetTrackSendInfo_Value(TRACK, 0, i, "B_MUTE") == 1
                                    local changed_mute, new_mute = r.ImGui_Checkbox(ctx, "Mute", mute)
                                    if changed_mute then
                                        r.SetTrackSendInfo_Value(TRACK, 0, i, "B_MUTE", new_mute and 1 or 0)
                                    end
                                    r.ImGui_SameLine(ctx)
                                    -- Check of alle andere sends gemute zijn
                                    local all_others_muted = true
                                    local num_sends = r.GetTrackNumSends(TRACK, 0)
                                    for j = 0, num_sends - 1 do
                                        if j ~= i and r.GetTrackSendInfo_Value(TRACK, 0, j, "B_MUTE") == 0 then
                                            all_others_muted = false
                                            break
                                        end
                                    end
                                    local is_soloed = r.GetTrackSendInfo_Value(TRACK, 0, i, "B_MUTE") == 0 and all_others_muted
                                    local changed_solo, new_solo = r.ImGui_Checkbox(ctx, "Solo", is_soloed)
                                    if changed_solo then
                                        for j = 0, num_sends - 1 do
                                            if new_solo then
                                                -- Als we solo-en, mute alle andere sends
                                                r.SetTrackSendInfo_Value(TRACK, 0, j, "B_MUTE", j == i and 0 or 1)
                                            else
                                                -- Als we unsolo-en, unmute alles
                                                r.SetTrackSendInfo_Value(TRACK, 0, j, "B_MUTE", 0)
                                            end
                                        end
                                    end
                                    r.ImGui_SameLine(ctx)
                                    local phase = r.GetTrackSendInfo_Value(TRACK, 0, i, "B_PHASE") == 1
                                    local changed_phase, new_phase = r.ImGui_Checkbox(ctx, "Phase", phase)
                                    if changed_phase then
                                        r.SetTrackSendInfo_Value(TRACK, 0, i, "B_PHASE", new_phase and 1 or 0)
                                    end
                                    r.ImGui_SameLine(ctx)
                                    local mono = r.GetTrackSendInfo_Value(TRACK, 0, i, "B_MONO") == 1
                                    local changed_mono, new_mono = r.ImGui_Checkbox(ctx, "Mono", mono)
                                    if changed_mono then
                                        r.SetTrackSendInfo_Value(TRACK, 0, i, "B_MONO", new_mono and 1 or 0)
                                    end
                                    --r.ImGui_SameLine(ctx)
                                    local current_mode = r.GetTrackSendInfo_Value(TRACK, 0, i, "I_SENDMODE")
                                    local mode_names = {
                                        "Post-Fader/Post-Pan",  -- mode 0
                                        "Pre-Fader/Post-FX",    -- mode 3
                                        "Pre-Fader/Pre-FX"      -- mode 1
                                    }
                                    local mode_values = {0, 3, 1}
                                    local current_idx = 1
                                    for i, value in ipairs(mode_values) do
                                        if value == current_mode then
                                            current_idx = i
                                            break
                                        end
                                    end

                                    r.ImGui_PushItemWidth(ctx, 100)
                                    if r.ImGui_BeginCombo(ctx, "##sendmode" .. i, mode_names[current_idx]) then
                                        for idx, name in ipairs(mode_names) do
                                            if r.ImGui_Selectable(ctx, name, current_idx == idx) then
                                                r.SetTrackSendInfo_Value(TRACK, 0, i, "I_SENDMODE", mode_values[idx])
                                            end
                                        end
                                        r.ImGui_EndCombo(ctx)
                                    end
                                    r.ImGui_PopItemWidth(ctx)
                                    r.ImGui_SameLine(ctx)
                                    if r.ImGui_Button(ctx, "Delete Send") then
                                        r.RemoveTrackSend(TRACK, 0, i)
                                    end
                                    
                                    r.ImGui_TreePop(ctx)
                                end
                                r.ImGui_PopID(ctx)
                            end
                        end
                
                        if r.ImGui_Button(ctx, "New Send") then
                            r.ImGui_OpenPopup(ctx, "SelectSendDestination")
                        end
                        
                        if r.ImGui_BeginPopup(ctx, "SelectSendDestination") then
                            r.ImGui_Text(ctx, "Select destination track:")
                            r.ImGui_Separator(ctx)
                            
                            local track_count = r.CountTracks(0)
                            for i = 0, track_count - 1 do
                                local dest_track = r.GetTrack(0, i)
                                if dest_track and dest_track ~= TRACK then
                                    local _, track_name = r.GetTrackName(dest_track)
                                    if r.ImGui_Selectable(ctx, track_name) then
                                        if config.create_sends_folder then
                                            -- Zoek bestaande SEND TRACK folder of maak nieuwe
                                            local folder_idx = -1
                                            for j = 0, track_count - 1 do
                                                local track = r.GetTrack(0, j)
                                                local _, name = r.GetTrackName(track)
                                                if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                                    folder_idx = j
                                                    break
                                                end
                                            end
                                            
                                            if folder_idx == -1 then
                                                -- Maak nieuwe folder
                                                r.InsertTrackAtIndex(track_count, true)
                                                local folder_track = r.GetTrack(0, track_count)
                                                r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                                r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                                
                                                -- Verplaats de destination track naar de folder als laatste item
                                                local last_track_in_folder = nil
                                                for j = folder_idx + 1, track_count - 1 do
                                                    local track = r.GetTrack(0, j)
                                                    if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                        last_track_in_folder = track
                                                    end
                                                end
                                                if last_track_in_folder then
                                                    r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                                end
                                                r.SetMediaTrackInfo_Value(dest_track, "I_FOLDERDEPTH", -1)
                                            end
                                        end
                                        
                                        r.CreateTrackSend(TRACK, dest_track)
                                        r.ImGui_CloseCurrentPopup(ctx)
                                    end
                                end
                            end
                            r.ImGui_EndPopup(ctx)
                        end
                        
                        if r.ImGui_Checkbox(ctx, "Create sends in folder", config.create_sends_folder) then
                            config.create_sends_folder = not config.create_sends_folder
                            SaveConfig()
                        end
                        
                        r.ImGui_Dummy(ctx, 0, 10)  -- Spacing tussen secties
                
                        -- RECEIVES SECTIE
                        r.ImGui_Separator(ctx)
                        r.ImGui_Text(ctx, "RECEIVES:")
                        -- r.ImGui_Separator(ctx)
                        
                        local num_receives = r.GetTrackNumSends(TRACK, -1)
                        for i = 0, num_receives - 1 do

                            local src_track = r.GetTrackSendInfo_Value(TRACK, -1, i, "P_SRCTRACK")
                            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                local _, src_name = r.GetTrackName(src_track)
                                
                                r.ImGui_PushID(ctx, "receive_" .. i)
                                local window_width = r.ImGui_GetWindowWidth(ctx)
                
                                r.ImGui_PushItemWidth(ctx, window_width - 20)
                                if r.ImGui_TreeNode(ctx, src_name) then
                                    -- Volume slider
                                    r.ImGui_PushItemWidth(ctx, window_width - 60)
                                    local vol = r.GetTrackSendInfo_Value(TRACK, -1, i, "D_VOL")
                                    local vol_db = 20 * math.log(vol, 10)
                                    local changed, new_vol_db = r.ImGui_SliderDouble(ctx, "Vol", vol_db, -60, 12, "%.1f dB")
                                    if changed then
                                        local new_vol = math.exp(new_vol_db * math.log(10) / 20)
                                        r.SetTrackSendInfo_Value(TRACK, -1, i, "D_VOL", new_vol)
                                    end
                
                                    -- Pan slider
                                    local pan = r.GetTrackSendInfo_Value(TRACK, -1, i, "D_PAN")
                                    local changed_pan, new_pan = r.ImGui_SliderDouble(ctx, "Pan", pan, -1, 1, "%.2f")
                                    if changed_pan then
                                        r.SetTrackSendInfo_Value(TRACK, -1, i, "D_PAN", new_pan)
                                    end
                                    r.ImGui_PopItemWidth(ctx)
                
                                    -- Mute knop
                                    local mute = r.GetTrackSendInfo_Value(TRACK, -1, i, "B_MUTE") == 1
                                    local changed_mute, new_mute = r.ImGui_Checkbox(ctx, "Mute", mute)
                                    if changed_mute then
                                        r.SetTrackSendInfo_Value(TRACK, -1, i, "B_MUTE", new_mute and 1 or 0)
                                    end
                        
                                    r.ImGui_SameLine(ctx)
                                    -- Check of alle andere receives gemute zijn
                                    local all_others_muted = true
                                    local num_receives = r.GetTrackNumSends(TRACK, -1)
                                    for j = 0, num_receives - 1 do
                                        if j ~= i and r.GetTrackSendInfo_Value(TRACK, -1, j, "B_MUTE") == 0 then
                                            all_others_muted = false
                                            break
                                        end
                                    end
                                    local is_soloed = r.GetTrackSendInfo_Value(TRACK, -1, i, "B_MUTE") == 0 and all_others_muted
                                    local changed_solo, new_solo = r.ImGui_Checkbox(ctx, "Solo", is_soloed)
                                    if changed_solo then
                                        for j = 0, num_receives - 1 do
                                            if new_solo then
                                                -- Als we solo-en, mute alle andere receives
                                                r.SetTrackSendInfo_Value(TRACK, -1, j, "B_MUTE", j == i and 0 or 1)
                                            else
                                                -- Als we unsolo-en, unmute alles
                                                r.SetTrackSendInfo_Value(TRACK, -1, j, "B_MUTE", 0)
                                            end
                                        end
                                    end
                                    r.ImGui_SameLine(ctx)
                                    local phase = r.GetTrackSendInfo_Value(TRACK, -1, i, "B_PHASE") == 1
                                    local changed_phase, new_phase = r.ImGui_Checkbox(ctx, "Phase", phase)
                                    if changed_phase then
                                        r.SetTrackSendInfo_Value(TRACK, -1, i, "B_PHASE", new_phase and 1 or 0)
                                    end
                                    r.ImGui_SameLine(ctx)
                                    local mono = r.GetTrackSendInfo_Value(TRACK, -1, i, "B_MONO") == 1
                                    local changed_mono, new_mono = r.ImGui_Checkbox(ctx, "Mono", mono)
                                    if changed_mono then
                                        r.SetTrackSendInfo_Value(TRACK, -1, i, "B_MONO", new_mono and 1 or 0)
                                    end

                                    --r.ImGui_SameLine(ctx)
                                    local current_mode = r.GetTrackSendInfo_Value(TRACK, -1, i, "I_SENDMODE")
                                    local mode_names = {
                                        "Post-Fader/Post-Pan",  -- mode 0
                                        "Pre-Fader/Post-FX",    -- mode 3
                                        "Pre-Fader/Pre-FX"      -- mode 1
                                    }
                                    local mode_values = {0, 3, 1}
                                    local current_idx = 1
                                    for i, value in ipairs(mode_values) do
                                        if value == current_mode then
                                            current_idx = i
                                            break
                                        end
                                    end

                                    r.ImGui_PushItemWidth(ctx, 100)
                                    if r.ImGui_BeginCombo(ctx, "##receivemode" .. i, mode_names[current_idx]) then
                                        for idx, name in ipairs(mode_names) do
                                            if r.ImGui_Selectable(ctx, name, current_idx == idx) then
                                                r.SetTrackSendInfo_Value(TRACK, -1, i, "I_SENDMODE", mode_values[idx])
                                            end
                                        end
                                        r.ImGui_EndCombo(ctx)
                                    end
                                    r.ImGui_PopItemWidth(ctx)
                                    r.ImGui_SameLine(ctx)
                                    -- Delete knop
                                    if r.ImGui_Button(ctx, "Delete Receive") then
                                        r.RemoveTrackSend(src_track, 0, r.GetTrackSendInfo_Value(TRACK, -1, i, "P_SRCIDX"))
                                    end
                                    
                                    r.ImGui_TreePop(ctx)
                                end
                                r.ImGui_PopID(ctx)
                            end
                        end
                        if r.ImGui_Button(ctx, "New Receive") then
                            r.ImGui_OpenPopup(ctx, "SelectReceiveSource")
                        end
                        
                        if r.ImGui_BeginPopup(ctx, "SelectReceiveSource") then
                            r.ImGui_Text(ctx, "Select source track:")
                            r.ImGui_Separator(ctx)
                            
                            local track_count = r.CountTracks(0)
                            for i = 0, track_count - 1 do
                                local source_track = r.GetTrack(0, i)
                                if source_track and source_track ~= TRACK then
                                    local _, track_name = r.GetTrackName(source_track)
                                    if r.ImGui_Selectable(ctx, track_name) then
                                        r.CreateTrackSend(source_track, TRACK)
                                        r.ImGui_CloseCurrentPopup(ctx)
                                    end
                                end
                            end
                            r.ImGui_EndPopup(ctx)
                        end
                    end
                    r.ImGui_Dummy(ctx, 0, 10)  -- Spacing tussen secties
                    
                    
                        
                       
                if show_routing_matrix then
                    ShowRoutingMatrix()
                end
            end
            r.ImGui_Separator(ctx)
            if r.ImGui_Button(ctx, "Matrix View") then
                  show_routing_matrix = not show_routing_matrix
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, show_matrix_exclusive and "Normal" or "Exclusive") then
                 show_matrix_exclusive = not show_matrix_exclusive
             end
                

        r.ImGui_EndChild(ctx)
    end
--------------------------------------------------------------------------------------
        -- ACTIONS GEDEELTE
        elseif show_action_browser then
            ShowScreenshotControls()
            --ShowFolderDropdown()
            r.ImGui_Separator(ctx) 
            local window_width = r.ImGui_GetWindowWidth(ctx)
            r.ImGui_PushItemWidth(ctx, window_width - 37)
            local changed, new_search_term = r.ImGui_InputTextWithHint(ctx, "##ActionSearch", "SEARCH ACTIONS", action_search_term)
            if changed then 
                action_search_term = new_search_term 
            end
            r.ImGui_PopItemWidth(ctx)
            r.ImGui_SameLine(ctx)
            -- Toggle Categories knop
            --r.ImGui_SetCursorPos(ctx, window_width - button_width * 2 - 10, 5)
            if r.ImGui_Button(ctx, show_categories and "C" or "A", button_width, button_height) then
                show_categories = not show_categories
            end
            r.ImGui_SameLine(ctx)
            -- r.ImGui_SetCursorPos(ctx, window_width - button_width * 2 - 10, 5)
            if r.ImGui_Button(ctx, show_only_active and "O" or "F", button_width, button_height) then
                show_only_active = not show_only_active
            end
            -- Bereken beschikbare hoogte voor scrollbaar gedeelte
            local window_height = r.ImGui_GetWindowHeight(ctx)
            local current_y = r.ImGui_GetCursorPosY(ctx)
            local footer_height = 50 -- Hoogte voor separator en tekst onderaan
            local available_height = window_height - current_y - footer_height
            
            if r.ImGui_BeginChild(ctx, "ActionList", 0, available_height) then
                local filteredActions = SearchActions(action_search_term)
                
                if show_categories then
                    -- Weergave met categorieën
                    for category, actions in pairs(filteredActions) do
                        if #actions > 0 then
                            if r.ImGui_TreeNode(ctx, category .. " (" .. #actions .. ")") then
                                for _, action in ipairs(actions) do
                                    if action.state == 1 then
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF4000FF)
                                    end
                                    
                                    local prefix = action.state == 1 and "[ON] " or ""
                                    if r.ImGui_Selectable(ctx, prefix .. action.name) then
                                        r.Main_OnCommand(action.id, 0)
                                    elseif r.ImGui_IsItemClicked(ctx, 1) then
                                        CreateSmartMarker(action.id)
                                    end
                                    
                                    if action.state == 1 then
                                        r.ImGui_PopStyleColor(ctx)
                                    end
                                end
                                r.ImGui_TreePop(ctx)
                            end
                        end
                    end
                else
                        -- Weergave van alle acties in één lijst
                        for _, action in ipairs(allActions) do
                            local state = r.GetToggleCommandState(action.id)
                            if (action_search_term == "" or action.name:lower():find(action_search_term:lower())) 
                            and (not show_only_active or state == 1) then
                                if state == 1 then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF4000FF)
                                end
                                
                                local prefix = state == 1 and "[ON] " or ""
                                if r.ImGui_Selectable(ctx, prefix .. action.name) then
                                    r.Main_OnCommand(action.id, 0)
                                elseif r.ImGui_IsItemClicked(ctx, 1) then
                                    CreateSmartMarker(action.id)
                                end
                                
                                if state == 1 then
                                    r.ImGui_PopStyleColor(ctx)
                                end
                            end
                        end
                    end
                    r.ImGui_EndChild(ctx)
                end

                r.ImGui_Separator(ctx)
                r.ImGui_TextWrapped(ctx, "Left-click: Execute action. Right-click: Create smart marker.")

--------------------------------------------------------------------------------------
        -- SCREENSHOTS GEDEELTE    
        else
        ShowScreenshotControls()
        local available_width = r.ImGui_GetContentRegionAvail(ctx)
        --local display_size
        if config.use_global_screenshot_size then
            display_size = config.global_screenshot_size
        elseif config.resize_screenshots_with_window then
            display_size = available_width - 10
        else
        display_size = selected_folder and (config.folder_specific_sizes[selected_folder] or config.screenshot_window_size) or config.screenshot_window_size
        end
        local num_columns = math.max(1, math.floor(available_width / display_size))
        local column_width = available_width / num_columns 

        if r.ImGui_BeginChild(ctx, "ScreenshotList", 0, 0) then
            local scroll_y = r.ImGui_GetScrollY(ctx)
            local scroll_max_y = r.ImGui_GetScrollMaxY(ctx)
            if not config.use_pagination and scroll_y > 0 and scroll_y/scroll_max_y > 0.8 and #current_filtered_fx > loaded_items_count then
                loaded_items_count = loaded_items_count + ITEMS_PER_BATCH
                for i = #screenshot_search_results + 1, math.min(loaded_items_count, #current_filtered_fx) do
                    table.insert(screenshot_search_results, {name = current_filtered_fx[i]})
                end
            end
            if folder_changed or new_search_performed then
                r.ImGui_SetScrollY(ctx, 0)
                folder_changed = false
                new_search_performed = false
            end
            if selected_folder ~= last_selected_folder and selected_folder then
                folder_changed = true
                last_selected_folder = selected_folder
            end
            if selected_folder then
                    local filtered_plugins = {}
                    
                    if selected_folder == "Favorites" then
                        filtered_plugins = favorite_plugins
                        -- Filter alleen voor weergave
                        local display_plugins = {}
                        for _, plugin in ipairs(filtered_plugins) do
                            if plugin:lower():find(browser_search_term:lower(), 1, true) then
                                table.insert(display_plugins, plugin)
                            end
                        end
                        filtered_plugins = display_plugins
                        
                    elseif selected_folder == "Current Project FX" then
                        filtered_plugins = GetCurrentProjectFX()
                        --Filter alleen voor weergave
                        local display_plugins = {}
                        for _, fx in ipairs(filtered_plugins) do
                        if fx.fx_name:lower():find(browser_search_term:lower(), 1, true) then
                               table.insert(display_plugins, fx)
                            end
                        end
                        filtered_plugins = display_plugins
                        
                    elseif selected_folder == "Current Track FX" then
                        filtered_plugins = GetCurrentTrackFX()
                        -- Filter alleen voor weergave
                        local display_plugins = {}
                        for _, fx in ipairs(filtered_plugins) do
                            if fx.fx_name:lower():find(browser_search_term:lower(), 1, true) then
                                table.insert(display_plugins, fx)
                            end
                        end
                        filtered_plugins = display_plugins
                    
                        if config.use_masonry_layout then
                            local masonry_data = {}
                            for _, fx in ipairs(filtered_plugins) do
                                table.insert(masonry_data, {name = fx.fx_name})
                            end
                            DrawMasonryLayout(masonry_data)
                        else
                            local available_width = r.ImGui_GetContentRegionAvail(ctx)
                            local num_columns = math.max(1, math.floor(available_width / display_size))
                            local column_width = available_width / num_columns
                    
                            for i, fx in ipairs(filtered_plugins) do
                                local column = (i - 1) % num_columns
                                if column > 0 then
                                    r.ImGui_SameLine(ctx)
                                end
                    
                                r.ImGui_BeginGroup(ctx)
                                local safe_name = fx.fx_name:gsub("[^%w%s-]", "_")
                                local screenshot_file = screenshot_path .. safe_name .. ".png"
                                
                                if r.file_exists(screenshot_file) then
                                    local texture = LoadSearchTexture(screenshot_file, fx.fx_name)
                                    if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                        local width, height = r.ImGui_Image_GetSize(texture)
                                        if width and height then
                                            local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                            
                                            if r.ImGui_ImageButton(ctx, "##"..fx.fx_name, texture, display_width, display_height) then
                                                local fx_index = r.TrackFX_GetByName(TRACK, fx.fx_name, false)
                                                if fx_index >= 0 then
                                                    local is_open = r.TrackFX_GetFloatingWindow(TRACK, fx_index)
                                                    r.TrackFX_Show(TRACK, fx_index, is_open and 2 or 3)
                                                end
                                            end
                                            
                                            if config.show_name_in_screenshot_window and not config.hidden_names[fx.fx_name] then
                                                r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                                r.ImGui_Text(ctx, fx.fx_name)
                                                r.ImGui_PopTextWrapPos(ctx)
                                            end
                                        end
                                    end
                                end
                                r.ImGui_EndGroup(ctx)
                                
                                if not config.compact_screenshots then
                                    if column == num_columns - 1 then
                                        r.ImGui_Dummy(ctx, 0, 5)
                                    end
                                end
                            end
                        end
                    
                    else
                        for i = 1, #CAT_TEST do
                            if CAT_TEST[i].name == "FOLDERS" then
                                for j = 1, #CAT_TEST[i].list do
                                    if CAT_TEST[i].list[j].name == selected_folder then
                                        filtered_plugins = CAT_TEST[i].list[j].fx
                                        local display_plugins = {}
                                        
                                        if config.show_favorites_on_top then
                                            -- Favorites eerst
                                            local favorites = {}
                                            local regular = {}
                                            
                                            for _, plugin in ipairs(filtered_plugins) do
                                                if plugin:lower():find(browser_search_term:lower(), 1, true) then
                                                    if table.contains(favorite_plugins, plugin) then
                                                        table.insert(favorites, plugin)
                                                    else
                                                        table.insert(regular, plugin)
                                                    end
                                                end
                                            end
                                            
                                            -- Voeg favorites toe
                                            for _, plugin in ipairs(favorites) do
                                                table.insert(display_plugins, plugin)
                                            end
                                            
                                            -- Voeg separator toe als er zowel favorites als regular plugins zijn
                                            if #favorites > 0 and #regular > 0 then
                                                table.insert(display_plugins, "--Favorites End--")
                                            end
                                            
                                            -- Voeg regular plugins toe
                                            for _, plugin in ipairs(regular) do
                                                table.insert(display_plugins, plugin)
                                            end
                                        else
                                            -- Toon alle plugins door elkaar
                                            for _, plugin in ipairs(filtered_plugins) do
                                                if plugin:lower():find(browser_search_term:lower(), 1, true) then
                                                    table.insert(display_plugins, plugin)
                                                end
                                            end
                                        end
                                        
                                        filtered_plugins = display_plugins
                                        break
                                    end
                                end
                                break
                            end
                        end
                        
                    end
                    

                if selected_folder and selected_folder ~= "Current Project FX" and selected_folder ~= "Current Track FX" then
                    local min_columns = math.floor(available_width / display_size)
                    local actual_display_size = math.min(display_size, available_width / min_columns)
                    local num_columns = math.max(1, min_columns)
                    local column_width = available_width / num_columns

                    if config.use_masonry_layout then
                        if filtered_plugins then
                            local masonry_data = {}
                            for _, plugin in ipairs(filtered_plugins) do
                                table.insert(masonry_data, {name = plugin})
                            end
                            DrawMasonryLayout(masonry_data)
                      
                        end
                
                    else
                        

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
                                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
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
                                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                            if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                                AddPluginToSelectedTracks(plugin_name)
                                            end
                                            if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                                AddPluginToAllTracks(plugin_name)
                                            end
                                        end
                                        if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                            AddToFavorites(plugin_name)
                                        end
                                        if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                            RemoveFromFavorites(plugin_name)
                                        end
                                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                            if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                                                local track_idx = r.CountTracks(0)
                                                r.InsertTrackAtIndex(track_idx, true)
                                                local new_track = r.GetTrack(0, track_idx)
                                                
                                                if config.create_sends_folder then
                                                    -- Zoek bestaande SEND TRACK folder of maak nieuwe
                                                    local folder_idx = -1
                                                    for i = 0, track_idx - 1 do
                                                        local track = r.GetTrack(0, i)
                                                        local _, name = r.GetTrackName(track)
                                                        if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                                            folder_idx = i
                                                            break
                                                        end
                                                    end
                                                    
                                                    if folder_idx == -1 then
                                                        -- Maak nieuwe folder
                                                        r.InsertTrackAtIndex(track_idx, true)
                                                        local folder_track = r.GetTrack(0, track_idx)
                                                        r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                                        r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                                        folder_idx = track_idx
                                                        track_idx = track_idx + 1
                                                        new_track = r.GetTrack(0, track_idx)
                                                    else
                                                        -- Pas folder depth aan van huidige laatste track in folder
                                                        local last_track_in_folder
                                                        for i = folder_idx + 1, track_idx - 1 do
                                                            local track = r.GetTrack(0, i)
                                                            if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                                last_track_in_folder = track
                                                            end
                                                        end
                                                        if last_track_in_folder then
                                                            r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                                        end
                                                    end
                                                    
                                                    -- Zet nieuwe track als laatste in de folder
                                                    r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                                                end
                                                
                                                
                                                -- Gebruik de juiste plugin identifier voor elk menu
                                                r.TrackFX_AddByName(new_track, plugin_name, false, -1000)
                                                r.CreateTrackSend(TRACK, new_track)
                                                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", plugin_name .. " Send", true)
                                            end
                                        end
                                        if r.ImGui_MenuItem(ctx, "Add with Multi-Output Setup") then
                                            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                                -- Plugin toevoegen op hoofdtrack
                                                r.TrackFX_AddByName(TRACK, plugin_name, false, -1000)
                                                
                                                -- Aantal outputs bepalen
                                                local num_outputs = tonumber(plugin_name:match("%((%d+)%s+out%)")) or 0
                                                local num_receives = math.floor(num_outputs / 2) - 1  -- -1 omdat 1/2 op hoofdtrack blijft
                                                
                                                -- Hoofdtrack configureren voor juiste aantal kanalen
                                                r.SetMediaTrackInfo_Value(TRACK, "I_NCHAN", num_outputs)
                                                
                                                -- Receive tracks maken
                                                for i = 1, num_receives do
                                                    local track_idx = r.CountTracks(0)
                                                    r.InsertTrackAtIndex(track_idx, true)
                                                    local new_track = r.GetTrack(0, track_idx)
                                                    
                                                    -- Send maken van hoofdtrack naar nieuwe track
                                                    r.CreateTrackSend(TRACK, new_track)
                                                    local send_idx = r.GetTrackNumSends(TRACK, 0) - 1
                                                    
                                                    -- Kanaal routing instellen
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SRCCHAN", i*2)  -- 2,4,6 etc
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_DSTCHAN", 0)    -- Altijd naar 1/2
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SENDMODE", 3)   -- Pre-fader
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_MIDIFLAGS", 0)  -- MIDI uit
                                                    
                                                    -- Track naam instellen met juiste output paar
                                                    local output_num = (i * 2) + 1
                                                    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", plugin_name .. " Out " .. output_num .. "-" .. (output_num + 1), true)
                                                end
                                            end
                                        end
                           
                                        if config.hidden_names[plugin_name] then
                                            if r.ImGui_MenuItem(ctx, "Show Name") then
                                                config.hidden_names[plugin_name] = nil
                                                SaveConfig()  
                                            end
                                        else
                                            if r.ImGui_MenuItem(ctx, "Hide Name") then
                                                config.hidden_names[plugin_name] = true
                                                SaveConfig()  
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
                        if not config.compact_screenshots then
                            if column == num_columns - 1 then
                                r.ImGui_Dummy(ctx, 0, 5)  -- Voeg wat ruimte toe tussen de rijen
                            end
                        end
                    end
                end
            end
                if #filtered_plugins > 0 then
                    local current_track_identifier = nil
                    local column_width = available_width / num_columns

                    -- Master track header
                    if selected_folder == "Current Project FX" then
                    local master_track = r.GetMasterTrack(0)
                    local master_fx_count = r.TrackFX_GetCount(master_track)
                    if master_fx_count > 0 then
                        r.ImGui_Separator(ctx)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x404040FF)
                        if r.ImGui_BeginChild(ctx, "TrackHeaderMaster", -1, 20) then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                            
                            local master_collapsed = master_track_collapsed or false  -- nieuwe globale variabele
                            if r.ImGui_Button(ctx, master_collapsed and "M" or "M", 20, 20) then
                                master_track_collapsed = not master_collapsed
                                ClearScreenshotCache()
                            end
                            
                            r.ImGui_SameLine(ctx)
                            if r.ImGui_Button(ctx, "Master Track") then
                                r.SetOnlyTrackSelected(master_track)
                            end
                            r.ImGui_PopStyleColor(ctx, 4)
                            r.ImGui_EndChild(ctx)
                        end
                        r.ImGui_PopStyleColor(ctx)
                        r.ImGui_Dummy(ctx, 0, 0)

                        -- Master track FX weergave
                        if not master_track_collapsed then
                            for i = 0, master_fx_count - 1 do
                                local retval, fx_name = r.TrackFX_GetFXName(master_track, i, "")
                                local safe_name = fx_name:gsub("[^%w%s-]", "_")
                                local screenshot_file = screenshot_path .. safe_name .. ".png"
                                
                                if r.file_exists(screenshot_file) then
                                    local texture = LoadSearchTexture(screenshot_file, fx_name)
                                    if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                        local width, height = r.ImGui_Image_GetSize(texture)
                                        if width and height then
                                            local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                            
                                            if r.ImGui_ImageButton(ctx, "##"..fx_name.."_master", texture, display_width, display_height) then
                                                local is_open = r.TrackFX_GetFloatingWindow(master_track, i)
                                                r.TrackFX_Show(master_track, i, is_open and 2 or 3)
                                            end
                                            
                                            if r.ImGui_IsItemClicked(ctx, 1) then
                                                r.ImGui_OpenPopup(ctx, "FXContextMenu_master_" .. i)
                                            end
                                            
                                            if r.ImGui_BeginPopup(ctx, "FXContextMenu_master_" .. i) then
                                                if r.ImGui_MenuItem(ctx, "Delete") then
                                                    r.TrackFX_Delete(master_track, i)
                                                end
                                                
                                                if r.ImGui_MenuItem(ctx, "Copy Plugin") then
                                                    copied_plugin = {track = master_track, index = i}
                                                end
                                                
                                                if r.ImGui_MenuItem(ctx, "Paste Plugin", nil, copied_plugin ~= nil) then
                                                    if copied_plugin then
                                                        local _, orig_name = r.TrackFX_GetFXName(copied_plugin.track, copied_plugin.index, "")
                                                        r.TrackFX_AddByName(master_track, orig_name, false, -1000)
                                                    end
                                                end
                                                
                                                local is_enabled = r.TrackFX_GetEnabled(master_track, i)
                                                if r.ImGui_MenuItem(ctx, is_enabled and "Bypass plugin" or "Unbypass plugin") then
                                                    r.TrackFX_SetEnabled(master_track, i, not is_enabled)
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
                                            
                                            if config.show_name_in_screenshot_window and not config.hidden_names[fx_name] then
                                                r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                                r.ImGui_Text(ctx, fx_name)
                                                r.ImGui_PopTextWrapPos(ctx)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                
            
                    for i, plugin in ipairs(filtered_plugins) do
                        local track_identifier = (plugin.track_number or "Unknown") .. "_" .. (plugin.track_name or "Unnamed")
                        if selected_folder == "Current Project FX" and track_identifier ~= current_track_identifier then
                            current_track_identifier = track_identifier

                            -- ANDERE TRACKS
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
                                                    if track and r.ValidatePtr(track, "MediaTrack*") then
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
                                                    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                                        r.TrackFX_AddByName(TRACK, plugin.fx_name, false, -1000 - r.TrackFX_GetCount(TRACK))
                                                        if config.close_after_adding_fx then
                                                            SHOULD_CLOSE_SCRIPT = true
                                                        end
                                                    end
                                                end
                                            end                          
                                            --ShowFXContextMenu(plugin, i)
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
                            
                            if not config.compact_screenshots then
                                if column == num_columns - 1 then
                                    r.ImGui_Dummy(ctx, 0, 5)
                                end
                            end
                        end
                    end
                end
            
                else
                    r.ImGui_Text(ctx, "No Plugins in Selected Folder.")
                end
            
            elseif screenshot_search_results and #screenshot_search_results > 0 then
                local available_width = r.ImGui_GetContentRegionAvail(ctx)
                --local display_size
                if config.use_global_screenshot_size then
                    display_size = config.global_screenshot_size
                elseif config.resize_screenshots_with_window then
                    display_size = available_width - 10
                else
                    display_size = config.folder_specific_sizes["SearchResults"] or config.screenshot_window_size
                end

                if config.use_masonry_layout then
                    DrawMasonryLayout(screenshot_search_results)
              
                else
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
                                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
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
                                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                            if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                                AddPluginToSelectedTracks(fx.name)
                                            end
                                            if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                                AddPluginToAllTracks(fx.name)
                                            end
                                        end
                                        if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                            AddToFavorites(fx.name)
                                        end
                                        if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                            RemoveFromFavorites(fx.name)
                                        end
                                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                            if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                                                local track_idx = r.CountTracks(0)
                                                r.InsertTrackAtIndex(track_idx, true)
                                                local new_track = r.GetTrack(0, track_idx)
                                                
                                                if config.create_sends_folder then
                                                    -- Zoek bestaande SEND TRACK folder of maak nieuwe
                                                    local folder_idx = -1
                                                    for i = 0, track_idx - 1 do
                                                        local track = r.GetTrack(0, i)
                                                        local _, name = r.GetTrackName(track)
                                                        if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                                            folder_idx = i
                                                            break
                                                        end
                                                    end
                                                    
                                                    if folder_idx == -1 then
                                                        -- Maak nieuwe folder
                                                        r.InsertTrackAtIndex(track_idx, true)
                                                        local folder_track = r.GetTrack(0, track_idx)
                                                        r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                                        r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                                        folder_idx = track_idx
                                                        track_idx = track_idx + 1
                                                        new_track = r.GetTrack(0, track_idx)
                                                    else
                                                        -- Pas folder depth aan van huidige laatste track in folder
                                                        local last_track_in_folder
                                                        for i = folder_idx + 1, track_idx - 1 do
                                                            local track = r.GetTrack(0, i)
                                                            if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                                last_track_in_folder = track
                                                            end
                                                        end
                                                        if last_track_in_folder then
                                                            r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                                        end
                                                    end
                                                    
                                                    -- Zet nieuwe track als laatste in de folder
                                                    r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                                                end
                                                
                                                
                                                -- Gebruik de juiste plugin identifier voor elk menu
                                                r.TrackFX_AddByName(new_track, fx.name, false, -1000)
                                                r.CreateTrackSend(TRACK, new_track)
                                                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", fx.name .. " Send", true)
                                            end
                                        end
                                                                    
                                        if r.ImGui_MenuItem(ctx, "Add with Multi-Output Setup") then
                                            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                                r.TrackFX_AddByName(TRACK, fx.name, false, -1000)
                                                
                                                local num_outputs = tonumber(fx.name:match("%((%d+)%s+out%)")) or 0
                                                local num_receives = math.floor(num_outputs / 2) - 1
                                                
                                                r.SetMediaTrackInfo_Value(TRACK, "I_NCHAN", num_outputs)
                                                
                                                for k = 1, num_receives do
                                                    local track_idx = r.CountTracks(0)
                                                    r.InsertTrackAtIndex(track_idx, true)
                                                    local new_track = r.GetTrack(0, track_idx)
                                                    
                                                    r.CreateTrackSend(TRACK, new_track)
                                                    local send_idx = r.GetTrackNumSends(TRACK, 0) - 1
                                                    
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SRCCHAN", k*2)
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_DSTCHAN", 0)
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_SENDMODE", 3)
                                                    r.SetTrackSendInfo_Value(TRACK, 0, send_idx, "I_MIDIFLAGS", 0)
                                                    
                                                    local output_num = (k * 2) + 1
                                                    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", fx.name .. " Out " .. output_num .. "-" .. (output_num + 1), true)
                                                end
                                            end
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
                    
                    if column == num_columns - 1 and not config.compact_screenshots then
                        r.ImGui_Dummy(ctx, 0, 5)
                    end
                end
                end
            else
                r.ImGui_Text(ctx, "Select a folder or enter a search term.")
            end
            r.ImGui_Dummy(ctx, 0, 0)
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 2)
    end
    config.screenshot_window_width = r.ImGui_GetWindowWidth(ctx)
    
    return visible 
    end
end

local function FilterTracksByTag(tag)
    local matching_tracks = {}
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local guid = r.GetTrackGUID(track)
        if track_tags[guid] then
            for _, track_tag in ipairs(track_tags[guid]) do
                if track_tag == tag then
                    table.insert(matching_tracks, track)
                    break
                end
            end
        end
    end
    return matching_tracks
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
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local track_info_width = math.max(window_width - 10, 125)
    local x_button_width = 20
    local margin = 3
    local search_width = track_info_width - (x_button_width * 3) - (margin * 3)
   

    -- Bereken hoogte van alle UI elementen
    local top_buttons_height = config.hideTopButtons and 5 or 30
    local tags_height = config.show_tags and current_tag_window_height or 0
    local meter_height = config.hideMeter and 0 or 90
    local meter_spacing = 5
    local bottom_buttons_height = config.hideBottomButtons and 0 or 70
    local volume_slider_height = (config.hideBottomButtons or config.hideVolumeSlider) and 0 or 40
    
    local total_ui_elements = top_buttons_height + tags_height + meter_height + meter_spacing + bottom_buttons_height + volume_slider_height
    local search_results_max_height = window_height - total_ui_elements - 80
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
    if r.ImGui_Button(ctx, "T", x_button_width, button_height) then
        config.show_type_dividers = not config.show_type_dividers
        SaveConfig()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "A", x_button_width, button_height) then
        config.sort_alphabetically = not config.sort_alphabetically
        SaveConfig()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "X", x_button_width, button_height) then
        FILTER = ""
        screenshot_search_results = nil
        r.ImGui_SetScrollY(ctx, 0)
        show_screenshot_window = true
        show_media_browser = false
        --show_sends_window = false
        --show_action_browser = false
        selected_folder = config.default_folder

    -- Voeg deze logica toe voor de speciale folders
    if config.default_folder == "Projects" then
        show_media_browser = true
        show_sends_window = false
        show_action_browser = false
        selected_folder = nil
    elseif config.default_folder == "Sends/Receives" then
        show_media_browser = false
        show_sends_window = true
        show_action_browser = false
        selected_folder = nil
    elseif config.default_folder == "Actions" then
        show_media_browser = false
        show_sends_window = false
        show_action_browser = true
        selected_folder = nil
    else
        show_media_browser = false
        show_sends_window = false
        show_action_browser = false
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
end
    local filtered_fx = Filter_actions(FILTER)
    if config.sort_alphabetically then
        table.sort(filtered_fx, function(a, b) 
            return a.name:lower() < b.name:lower() 
        end)
    else
        table.sort(filtered_fx, function(a, b)
            if a.score == b.score then
                return a.name:lower() < b.name:lower()
            end
            return a.score < b.score
        end)
    end

    local window_height = r.ImGui_GetWindowHeight(ctx)
    local bottom_buttons_height = config.hideBottomButtons and 0 or 70
    local available_height = window_height - r.ImGui_GetCursorPosY(ctx) - bottom_buttons_height - 10
    if #filtered_fx ~= 0 then
        if r.ImGui_BeginChild(ctx, "##popupp", -1, search_results_max_height) then
            if config.show_type_dividers then
                
                -- Organized view with type dividers
                local types = {
                    VST = {}, VSTi = {}, 
                    VST3 = {}, VST3i = {}, 
                    JS = {}, JSi = {}, 
                    AU = {}, AUi = {}, 
                    CLAP = {}, CLAPi = {}, 
                    LV2 = {}, LV2i = {}
                }
                
                local global_idx = 1
                for i = 1, #filtered_fx do
                    local name = filtered_fx[i].name
                    if name:match("^VST3i:") then
                        table.insert(types.VST3i, filtered_fx[i])
                    elseif name:match("^VST3:") then
                        table.insert(types.VST3, filtered_fx[i])
                    elseif name:match("^VSTi:") then
                        table.insert(types.VSTi, filtered_fx[i])
                    elseif name:match("^VST:") then
                        table.insert(types.VST, filtered_fx[i])
                    elseif name:match("^CLAPi:") then
                        table.insert(types.CLAPi, filtered_fx[i])
                    elseif name:match("^CLAP:") then
                        table.insert(types.CLAP, filtered_fx[i])
                    elseif name:match("^JSi:") then
                        table.insert(types.JSi, filtered_fx[i])
                    elseif name:match("^JS:") then
                        table.insert(types.JS, filtered_fx[i])
                    elseif name:match("^AUi:") then
                        table.insert(types.AUi, filtered_fx[i])
                    elseif name:match("^AU:") then
                        table.insert(types.AU, filtered_fx[i])
                    elseif name:match("^LV2i:") then
                        table.insert(types.LV2i, filtered_fx[i])
                    elseif name:match("^LV2:") then
                        table.insert(types.LV2, filtered_fx[i])
                    end
                end
    
                for type, plugins in pairs(types) do
                    if #plugins > 0 then
                        if config.sort_alphabetically then
                            table.sort(plugins, function(a, b) 
                                return a.name:lower() < b.name:lower() 
                            end)
                        else
                            table.sort(plugins, function(a, b)
                                if a.score == b.score then
                                    return a.name:lower() < b.name:lower()
                                end
                                return a.score < b.score
                            end)
                            
                        end
                        r.ImGui_Dummy(ctx, 0, 5)
                        r.ImGui_Separator(ctx)
                        r.ImGui_Text(ctx, type .. " Plugins")
                        r.ImGui_Separator(ctx)
                        
                        for _, plugin in ipairs(plugins) do
                            local display_name = plugin.name:gsub("^(%S+:)", "")
                            if r.ImGui_Selectable(ctx, display_name .. "##search_" .. global_idx, global_idx == ADDFX_Sel_Entry) then
                                r.TrackFX_AddByName(TRACK, plugin.name, false, -1000 - r.TrackFX_GetCount(TRACK))
                                r.ImGui_CloseCurrentPopup(ctx)
                                LAST_USED_FX = plugin.name
                            end
    
                            if r.ImGui_IsItemHovered(ctx) then
                                if plugin.name ~= current_hovered_plugin then
                                    current_hovered_plugin = plugin.name
                                    if config.show_screenshot_in_search then
                                        LoadPluginScreenshot(current_hovered_plugin)
                                    end
                                end
                                is_screenshot_visible = true
                                if not config.show_screenshot_in_search or not ScreenshotExists(plugin.name) then
                                    r.ImGui_BeginTooltip(ctx)
                                    r.ImGui_Text(ctx, plugin.name)
                                    r.ImGui_EndTooltip(ctx)
                                end
                            end
    
                            if r.ImGui_IsItemClicked(ctx, 1) then
                                r.ImGui_OpenPopup(ctx, "DrawItemsPluginMenu_" .. global_idx)
                            end
    
                            if r.ImGui_BeginPopup(ctx, "DrawItemsPluginMenu_" .. global_idx) then
                                if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                                    MakeScreenshot(plugin.name, nil, true)
                                end
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                        AddPluginToSelectedTracks(plugin.name, false)
                                    end
                                    if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                        AddPluginToAllTracks(plugin.name, false)
                                    end
                                end
                                if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                    AddToFavorites(plugin.name)
                                end
                                if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                    RemoveFromFavorites(plugin.name)
                                end
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                                        local track_idx = r.CountTracks(0)
                                        r.InsertTrackAtIndex(track_idx, true)
                                        local new_track = r.GetTrack(0, track_idx)
                                        
                                        if config.create_sends_folder then
                                            -- Zoek bestaande SEND TRACK folder of maak nieuwe
                                            local folder_idx = -1
                                            for i = 0, track_idx - 1 do
                                                local track = r.GetTrack(0, i)
                                                local _, name = r.GetTrackName(track)
                                                if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                                    folder_idx = i
                                                    break
                                                end
                                            end
                                            
                                            if folder_idx == -1 then
                                                -- Maak nieuwe folder
                                                r.InsertTrackAtIndex(track_idx, true)
                                                local folder_track = r.GetTrack(0, track_idx)
                                                r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                                r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                                folder_idx = track_idx
                                                track_idx = track_idx + 1
                                                new_track = r.GetTrack(0, track_idx)
                                            else
                                                -- Pas folder depth aan van huidige laatste track in folder
                                                local last_track_in_folder
                                                for i = folder_idx + 1, track_idx - 1 do
                                                    local track = r.GetTrack(0, i)
                                                    if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                        last_track_in_folder = track
                                                    end
                                                end
                                                if last_track_in_folder then
                                                    r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                                end
                                            end
                                            
                                            -- Zet nieuwe track als laatste in de folder
                                            r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                                        end
                                        
                                        -- Gebruik de juiste plugin identifier voor elk menu
                                        r.TrackFX_AddByName(new_track, plugin.name, false, -1000)
                                        r.CreateTrackSend(TRACK, new_track)
                                        r.GetSetMediaTrackInfo_String(new_track, "P_NAME", plugin.name .. " Send", true)
                                    end
                                end
                                
                                if config.hidden_names[plugin.name] then
                                    if r.ImGui_MenuItem(ctx, "Show Name") then
                                        config.hidden_names[plugin.name] = nil
                                        SaveConfig()
                                    end
                                else
                                    if r.ImGui_MenuItem(ctx, "Hide Name") then
                                        config.hidden_names[plugin.name] = true
                                        SaveConfig()
                                    end
                                end
                                r.ImGui_EndPopup(ctx)
                            end
                            global_idx = global_idx + 1
                        end
                    end
                end
            else
                -- Original view
                for i = 1, #filtered_fx do
                    if r.ImGui_Selectable(ctx, filtered_fx[i].name .. "##search_" .. i, i == ADDFX_Sel_Entry) then
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
    
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        r.ImGui_OpenPopup(ctx, "DrawItemsPluginMenu_" .. i)
                    end
    
                    if r.ImGui_BeginPopup(ctx, "DrawItemsPluginMenu_" .. i) then
                        if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                            MakeScreenshot(filtered_fx[i].name, nil, true)
                        end
                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                            if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                AddPluginToSelectedTracks(filtered_fx[i].name, false)
                            end
                            if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                AddPluginToAllTracks(filtered_fx[i].name, false)
                            end
                        end
                        if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                            AddToFavorites(filtered_fx[i].name)
                        end
                        if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                            RemoveFromFavorites(filtered_fx[i].name)
                        end
                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                            if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                                local track_idx = r.CountTracks(0)
                                r.InsertTrackAtIndex(track_idx, true)
                                local new_track = r.GetTrack(0, track_idx)
                                
                                if config.create_sends_folder then
                                    -- Zoek bestaande SEND TRACK folder of maak nieuwe
                                    local folder_idx = -1
                                    for i = 0, track_idx - 1 do
                                        local track = r.GetTrack(0, i)
                                        local _, name = r.GetTrackName(track)
                                        if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                            folder_idx = i
                                            break
                                        end
                                    end
                                    
                                    if folder_idx == -1 then
                                        -- Maak nieuwe folder
                                        r.InsertTrackAtIndex(track_idx, true)
                                        local folder_track = r.GetTrack(0, track_idx)
                                        r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                        r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                        folder_idx = track_idx
                                        track_idx = track_idx + 1
                                        new_track = r.GetTrack(0, track_idx)
                                    else
                                        -- Pas folder depth aan van huidige laatste track in folder
                                        local last_track_in_folder
                                        for i = folder_idx + 1, track_idx - 1 do
                                            local track = r.GetTrack(0, i)
                                            if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                last_track_in_folder = track
                                            end
                                        end
                                        if last_track_in_folder then
                                            r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                        end
                                    end
                                    
                                    -- Zet nieuwe track als laatste in de folder
                                    r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                                end
                                
                                -- Gebruik de juiste plugin identifier voor elk menu
                                r.TrackFX_AddByName(new_track, filtered_fx[i].name, false, -1000)
                                r.CreateTrackSend(TRACK, new_track)
                                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", filtered_fx[i].name .. " Send", true)
                            end
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
            if main_cat_name == "FOLDERS" then
                -- Sorteer plugins in favorites en reguliere items
                local favorites = {}
                local regular = {}
                local all_plugins = {}
           
                for j = 1, #tbl[i].fx do
                    if table.contains(favorite_plugins, tbl[i].fx[j]) then
                        table.insert(favorites, {index = j, name = tbl[i].fx[j]})
                    else
                        table.insert(regular, {index = j, name = tbl[i].fx[j]})
                    end
                    table.insert(all_plugins, {index = j, name = tbl[i].fx[j], is_favorite = table.contains(favorite_plugins, tbl[i].fx[j])})
                end
           
                local plugins_to_show = config.show_favorites_on_top and {favorites, regular} or {all_plugins}
       
                for _, plugin_group in ipairs(plugins_to_show) do
                    for _, plugin in ipairs(plugin_group) do
                        if r.ImGui_Selectable(ctx, plugin.name .. "##plugin_list_" .. i .. "_" .. plugin.index) then
                            if ADD_FX_TO_ITEM then
                                AddFXToItem(plugin.name)
                            else
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    r.TrackFX_AddByName(TRACK, plugin.name, false, -1000 - r.TrackFX_GetCount(TRACK))
                                end
                            end
                            LAST_USED_FX = plugin.name
                            if config.close_after_adding_fx and not IS_COPYING_TO_ALL_TRACKS then
                                SHOULD_CLOSE_SCRIPT = true
                            end
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            if plugin.name ~= current_hovered_plugin then
                                current_hovered_plugin = plugin.name
                                LoadPluginScreenshot(current_hovered_plugin)
                            end
                            is_screenshot_visible = true
                        end
                       
                        if r.ImGui_IsItemClicked(ctx, 1) then
                            r.ImGui_OpenPopup(ctx, "DrawItemsPluginMenu_" .. i .. "_" .. plugin.index)
                        end
                   
                        if r.ImGui_BeginPopup(ctx, "DrawItemsPluginMenu_" .. i .. "_" .. plugin.index) then
                            if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                                MakeScreenshot(plugin.name, nil, true)
                            end
                           
                            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                    AddPluginToSelectedTracks(plugin.name, false)
                                end
                                if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                    AddPluginToAllTracks(plugin.name, false)
                                end
                            end
                       
                            -- Vervang de huidige favorites optie code met:
                            local is_favorite = table.contains(favorite_plugins, plugin.name)
                            if is_favorite then
                                if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                    RemoveFromFavorites(plugin.name)
                                    GetPluginsForFolder(selected_folder)
                                end
                            else
                                if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                    AddToFavorites(plugin.name)
                                    GetPluginsForFolder(selected_folder)
                                end
                            end

                       
                            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                                    local track_idx = r.CountTracks(0)
                                    r.InsertTrackAtIndex(track_idx, true)
                                    local new_track = r.GetTrack(0, track_idx)
                               
                                    if config.create_sends_folder then
                                        local folder_idx = -1
                                        for k = 0, track_idx - 1 do
                                            local track = r.GetTrack(0, k)
                                            local _, name = r.GetTrackName(track)
                                            if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                                folder_idx = k
                                                break
                                            end
                                        end
                                       
                                        if folder_idx == -1 then
                                            r.InsertTrackAtIndex(track_idx, true)
                                            local folder_track = r.GetTrack(0, track_idx)
                                            r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                            r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                            folder_idx = track_idx
                                            track_idx = track_idx + 1
                                            new_track = r.GetTrack(0, track_idx)
                                        else
                                            local last_track_in_folder
                                            for k = folder_idx + 1, track_idx - 1 do
                                                local track = r.GetTrack(0, k)
                                                if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                    last_track_in_folder = track
                                                end
                                            end
                                            if last_track_in_folder then
                                                r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                            end
                                        end
                                       
                                        r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                                    end
                                   
                                    r.TrackFX_AddByName(new_track, plugin.name, false, -1000)
                                    r.CreateTrackSend(TRACK, new_track)
                                    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", plugin.name .. " Send", true)
                                end
                            end
                       
                            if config.hidden_names[plugin.name] then
                                if r.ImGui_MenuItem(ctx, "Show Name") then
                                    config.hidden_names[plugin.name] = nil
                                    SaveConfig()
                                end
                            else
                                if r.ImGui_MenuItem(ctx, "Hide Name") then
                                    config.hidden_names[plugin.name] = true
                                    SaveConfig()
                                end
                            end
                           
                            r.ImGui_EndPopup(ctx)
                        end
                    end
                   
                    if config.show_favorites_on_top and _ == 1 and #favorites > 0 and #regular > 0 then
                        if r.ImGui_Selectable(ctx, "--Favorites End--", false, r.ImGui_SelectableFlags_Disabled()) then end
                    end
                end
            else
                -- Originele implementatie voor andere categorieën
                if tbl[i] and tbl[i].fx then
                    for j = 1, #tbl[i].fx do
                        if tbl[i].fx[j] then
                            local name = tbl[i].fx[j]
                            if main_cat_name == "ALL PLUGINS" and tbl[i].name ~= "INSTRUMENTS" then
                                name = name:gsub("^(%S+:)", "")
                            elseif main_cat_name == "DEVELOPER" then
                                name = name:gsub(' %(' .. Literalize(tbl[i].name) .. '%)', "")
                            end
                           
                            if r.ImGui_Selectable(ctx, name .. "##plugin_list_" .. i .. "_" .. j) then
                                if ADD_FX_TO_ITEM then
                                    AddFXToItem(tbl[i].fx[j])
                                else
                                    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
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
                           
                            if r.ImGui_IsItemClicked(ctx, 1) then
                                r.ImGui_OpenPopup(ctx, "DrawItemsPluginMenu_" .. i .. "_" .. j)
                            end
                           
                            if r.ImGui_BeginPopup(ctx, "DrawItemsPluginMenu_" .. i .. "_" .. j) then
                                if r.ImGui_MenuItem(ctx, "Make Screenshot") then
                                    MakeScreenshot(tbl[i].fx[j], nil, true)
                                end
                               
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                                        AddPluginToSelectedTracks(tbl[i].fx[j], false)
                                    end
                                    if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                                        AddPluginToAllTracks(tbl[i].fx[j], false)
                                    end
                                end
                               
                            
                                local is_favorite = table.contains(favorite_plugins, tbl[i].fx[j])
                                if is_favorite then
                                    if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                                        RemoveFromFavorites(tbl[i].fx[j])
                                        GetPluginsForFolder(selected_folder)
                                    end
                                else
                                    if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                                        AddToFavorites(tbl[i].fx[j])
                                        GetPluginsForFolder(selected_folder)
                                    end
                                end


                               
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                                        local track_idx = r.CountTracks(0)
                                        r.InsertTrackAtIndex(track_idx, true)
                                        local new_track = r.GetTrack(0, track_idx)
                                       
                                        if config.create_sends_folder then
                                            local folder_idx = -1
                                            for k = 0, track_idx - 1 do
                                                local track = r.GetTrack(0, k)
                                                local _, name = r.GetTrackName(track)
                                                if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                                    folder_idx = k
                                                    break
                                                end
                                            end
                                           
                                            if folder_idx == -1 then
                                                r.InsertTrackAtIndex(track_idx, true)
                                                local folder_track = r.GetTrack(0, track_idx)
                                                r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                                r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                                folder_idx = track_idx
                                                track_idx = track_idx + 1
                                                new_track = r.GetTrack(0, track_idx)
                                            else
                                                local last_track_in_folder
                                                for k = folder_idx + 1, track_idx - 1 do
                                                    local track = r.GetTrack(0, k)
                                                    if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                                        last_track_in_folder = track
                                                    end
                                                end
                                                if last_track_in_folder then
                                                    r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                                                end
                                            end
                                           
                                            r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                                        end
                                       
                                        r.TrackFX_AddByName(new_track, tbl[i].fx[j], false, -1000)
                                        r.CreateTrackSend(TRACK, new_track)
                                        r.GetSetMediaTrackInfo_String(new_track, "P_NAME", tbl[i].fx[j] .. " Send", true)
                                    end
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
                end
            end
           
            if not r.ImGui_IsAnyItemHovered(ctx) and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId()) then
                r.ImGui_CloseCurrentPopup(ctx)
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
        if r.ImGui_Selectable(ctx, fav .. "##favorites_" .. i) then
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
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
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                    AddPluginToSelectedTracks(fav, false)
                end
                if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                    AddPluginToAllTracks(fav, false)
                end
            end
            if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                RemoveFromFavorites(fav)
            end
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                if r.ImGui_MenuItem(ctx, "Add to new track as send") then
                    local track_idx = r.CountTracks(0)
                    r.InsertTrackAtIndex(track_idx, true)
                    local new_track = r.GetTrack(0, track_idx)
                    
                    if config.create_sends_folder then
                        -- Zoek bestaande SEND TRACK folder of maak nieuwe
                        local folder_idx = -1
                        for i = 0, track_idx - 1 do
                            local track = r.GetTrack(0, i)
                            local _, name = r.GetTrackName(track)
                            if name == "SEND TRACK" and r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1 then
                                folder_idx = i
                                break
                            end
                        end
                        
                        if folder_idx == -1 then
                            -- Maak nieuwe folder
                            r.InsertTrackAtIndex(track_idx, true)
                            local folder_track = r.GetTrack(0, track_idx)
                            r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                            r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                            folder_idx = track_idx
                            track_idx = track_idx + 1
                            new_track = r.GetTrack(0, track_idx)
                        else
                            -- Pas folder depth aan van huidige laatste track in folder
                            local last_track_in_folder
                            for i = folder_idx + 1, track_idx - 1 do
                                local track = r.GetTrack(0, i)
                                if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == -1 then
                                    last_track_in_folder = track
                                end
                            end
                            if last_track_in_folder then
                                r.SetMediaTrackInfo_Value(last_track_in_folder, "I_FOLDERDEPTH", 0)
                            end
                        end
                        
                        -- Zet nieuwe track als laatste in de folder
                        r.SetMediaTrackInfo_Value(new_track, "I_FOLDERDEPTH", -1)
                    end
                    
                    
                    -- Gebruik de juiste plugin identifier voor elk menu
                    r.TrackFX_AddByName(new_track, fav, false, -1000)
                    r.CreateTrackSend(TRACK, new_track)
                    r.GetSetMediaTrackInfo_String(new_track, "P_NAME", fav .. " Send", true)
                end
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
    local track_info_width = math.max(window_width - 10, 125)
    local button_spacing = 3
    local windowHeight = r.ImGui_GetWindowHeight(ctx)
    local buttonHeight = 65
    r.ImGui_SetCursorPosY(ctx, windowHeight - buttonHeight - 42)
    -- volumeslider
    if not config.hideVolumeSlider then
        -- Pan en Width sliders naast elkaar
        local half_width = (track_info_width - button_spacing) / 2
        --r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), config.slider_grab_color)
        --r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), config.slider_active_color)
        --r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 4)
        --r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3)
        
        -- Pan slider met context menu
        r.ImGui_PushItemWidth(ctx, half_width)
        local pan_mode = r.GetMediaTrackInfo_Value(TRACK, "I_PANMODE")

        if pan_mode == 6 then -- Dual Pan mode
            -- Linker pan slider
            r.ImGui_PushItemWidth(ctx, half_width/2 - 2)
            local pan_L = r.GetMediaTrackInfo_Value(TRACK, "D_DUALPANL")
            local pan_L_changed, new_pan_L = r.ImGui_SliderDouble(ctx, "##PanL", pan_L, -1, 1, "L: %.2f")
            if r.ImGui_IsItemClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "PanModeMenu")
            end
            
            if pan_L_changed then
                r.SetMediaTrackInfo_Value(TRACK, "D_DUALPANL", new_pan_L)
            end
            
            -- Rechter pan slider
            r.ImGui_SameLine(ctx)
            r.ImGui_PushItemWidth(ctx, half_width/2 - 2)
            local pan_R = r.GetMediaTrackInfo_Value(TRACK, "D_DUALPANR")
            local pan_R_changed, new_pan_R = r.ImGui_SliderDouble(ctx, "##PanR", pan_R, -1, 1, "R: %.2f")
            if r.ImGui_IsItemClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "PanModeMenu")
            end
            if pan_R_changed then
                r.SetMediaTrackInfo_Value(TRACK, "D_DUALPANR", new_pan_R)
            end
        else
            -- Normale pan slider
            local pan = r.GetMediaTrackInfo_Value(TRACK, "D_PAN")
            local pan_changed, new_pan = r.ImGui_SliderDouble(ctx, "##Pan", pan, -1, 1, "Pan: %.2f")
            if r.ImGui_IsItemClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "PanModeMenu")
            end
            if pan_changed then
                r.SetMediaTrackInfo_Value(TRACK, "D_PAN", new_pan)
            end
        end

        if r.ImGui_BeginPopup(ctx, "PanModeMenu") then
            if r.ImGui_MenuItem(ctx, "Reset Pan") then
                if pan_mode == 6 then
                    r.SetMediaTrackInfo_Value(TRACK, "D_DUALPANL", 0.0)
                    r.SetMediaTrackInfo_Value(TRACK, "D_DUALPANR", 0.0)
                else
                    r.SetMediaTrackInfo_Value(TRACK, "D_PAN", 0.0)
                end
            end
            if r.ImGui_MenuItem(ctx, "Stereo Pan") then
                r.Main_OnCommand(r.NamedCommandLookup("_SWS_AWPANSTEREOPAN"), 0)
            end
            if r.ImGui_MenuItem(ctx, "Stereo Balance") then
                r.Main_OnCommand(r.NamedCommandLookup("_SWS_AWPANBALANCENEW"), 0)
            end
            if r.ImGui_MenuItem(ctx, "Dual Pan") then
                r.Main_OnCommand(r.NamedCommandLookup("_SWS_AWPANDUALPAN"), 0)
            end
            if r.ImGui_MenuItem(ctx, "3x Balance") then
                r.Main_OnCommand(r.NamedCommandLookup("_SWS_AWPANBALANCEOLD"), 0)
            end
            r.ImGui_EndPopup(ctx)
        end


        -- Width slider
        r.ImGui_SameLine(ctx)
        r.ImGui_PushItemWidth(ctx, half_width)
        local width = r.GetMediaTrackInfo_Value(TRACK, "D_WIDTH")
        local display_width = width * 100
        local width_changed, new_width = r.ImGui_SliderDouble(ctx, "##Width", display_width, -100, 100, "Width: %.0f%%")
        if r.ImGui_IsItemClicked(ctx, 1) then  -- rechtsklik
            r.SetMediaTrackInfo_Value(TRACK, "D_WIDTH", 1.0)  -- reset naar 100%
        end
        if width_changed then
            r.SetMediaTrackInfo_Value(TRACK, "D_WIDTH", new_width / 100)
        end
        

        -- volume slider
        local volume = r.GetMediaTrackInfo_Value(TRACK, "D_VOL")
        if volume and volume > 0 then
            local volume_db = math.floor(20 * math.log(volume, 10) + 0.5)
            r.ImGui_PushItemWidth(ctx, track_info_width)
            
            local changed, new_volume_db = r.ImGui_SliderInt(ctx, "##Volume", volume_db, -60, 12, "%d dB")
    
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Rightclick 0db /double Rightclick -12db")
                if r.ImGui_IsMouseDoubleClicked(ctx, 1) then
                    new_volume_db = -12
                    changed = true
                elseif r.ImGui_IsMouseClicked(ctx, 1) then
                    new_volume_db = 0
                    changed = true
                end
            end
    
            if changed then
                local new_volume = 10^(new_volume_db/20)
                r.SetMediaTrackInfo_Value(TRACK, "D_VOL", new_volume)
            end
            --r.ImGui_PopStyleColor(ctx, 4)
            r.ImGui_PopItemWidth(ctx)
        end
    end
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
    if r.ImGui_Button(ctx, "COPY", button_width_row1) then
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
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), bypass_state and 0x0080FFFF or config.button_background_color)
    if r.ImGui_Button(ctx, "BYPS", button_width_row2) then
        local new_state = bypass_state and 1 or 0
        r.SetMediaTrackInfo_Value(TRACK, "I_FXEN", new_state)
    end
    r.ImGui_PopStyleColor(ctx)
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "ByPass All FX on the selected Track")
    end
    r.ImGui_SameLine(ctx, 0, button_spacing)
    if r.ImGui_Button(ctx, "SNAP", button_width_row2) then
        r.ImGui_OpenPopup(ctx, "SnapConfirmation")
    end
    if r.ImGui_BeginPopup(ctx, "SnapConfirmation") then
        r.ImGui_Text(ctx, "Open first FX on track (floating) and click OK")
        if r.ImGui_Button(ctx, "OK") then
            CaptureFirstTrackFX()
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel") then
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end
    
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Make screenshot of First FX on the selected Track (must be floating)")
    end  
    r.ImGui_SameLine(ctx, 0, button_spacing)
    local vkb_active = r.GetToggleCommandStateEx(0, 40377)
    if vkb_active == 1 then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x0080FFFF)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), config.button_background_color)
    end
    if r.ImGui_Button(ctx, "VKB", button_width_row2) then
        r.Main_OnCommand(40377, 0)
    end
    r.ImGui_PopStyleColor(ctx)
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Show Virtual Keyboard")
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
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), IsSoloed(TRACK) and 0xFFFF00FF or config.button_background_color)
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

local function ShowTrackFX()
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then
        r.ImGui_Text(ctx, "No track selected")
        return
    end
    local min_height = r.ImGui_GetCursorPosY(ctx)
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local available_height = window_height - r.ImGui_GetCursorPosY(ctx)
    local notes_section_height = config.show_notes and notes_height or 0
    local fx_list_height = available_height - notes_section_height - 25
    
    if r.ImGui_BeginChild(ctx, "TrackFXList", -1, fx_list_height) then
        r.ImGui_Dummy(ctx, 0, 5)
        r.ImGui_Text(ctx, "FX on Track:")
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
                if r.ImGui_Button(ctx, "##updown", 14, 14) then
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
                if r.ImGui_Button(ctx, display_name, 0, 14) then
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

        -- Notation:
        if config.show_notes_widget then
            r.ImGui_Separator(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)

            -- Eerst de kleurknop
            if r.ImGui_ColorButton(ctx, "##notes_color", config.track_notes_color, 0, 13, 13) then
                r.ImGui_OpenPopup(ctx, "NotesColorPopup")
            end

            r.ImGui_SameLine(ctx)

            if r.ImGui_Selectable(ctx, config.show_notes and " - " or " + ") then
                config.show_notes = not config.show_notes
                SaveConfig()
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Notes:")

            -- Save knop rechts uitlijnen
            local window_width = r.ImGui_GetWindowWidth(ctx)
            local text_width = r.ImGui_CalcTextSize(ctx, "Save")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, window_width - text_width - 5)
            if r.ImGui_Selectable(ctx, "Save", false, r.ImGui_SelectableFlags_None()) then
                SaveNotes()
            end

            -- Color picker popup
            if r.ImGui_BeginPopup(ctx, "NotesColorPopup") then
                local changed, new_color = r.ImGui_ColorEdit4(ctx, "Notes Color", config.track_notes_color)
                if changed then
                    config.track_notes_color = new_color
                    SaveConfig()
                end
                r.ImGui_EndPopup(ctx)
            end

            r.ImGui_PopStyleColor(ctx, 2)

            -- Notes section
            if config.show_notes then
                local track_guid = r.GetTrackGUID(TRACK)
                if not notes[track_guid] then
                    notes[track_guid] = LoadNotes()[track_guid] or ""
                end

                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), config.track_notes_color)
                if r.ImGui_BeginChild(ctx, "NotesSection", -1, notes_height) then
                    local changed, new_note = r.ImGui_InputTextMultiline(ctx, "##tracknotes", notes[track_guid], -1, notes_height - 10)
                    if changed then
                        notes[track_guid] = new_note
                        SaveNotes()
                    end
                    r.ImGui_EndChild(ctx)
                end
            r.ImGui_PopStyleColor(ctx)       
        end
    end
end

local function ShowItemFX()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then return end
    local take = r.GetActiveTake(item)
    if not take then return end

    local min_height = r.ImGui_GetCursorPosY(ctx)
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local available_height = window_height - r.ImGui_GetCursorPosY(ctx)
    local notes_section_height = config.show_notes and notes_height or 0
    local fx_list_height = available_height - notes_section_height - 25

    if r.ImGui_BeginChild(ctx, "ItemFXList", -1, fx_list_height) then
        r.ImGui_Dummy(ctx, 0, 5)
        r.ImGui_Text(ctx, "FX on Item:")
        local fx_count = r.TakeFX_GetCount(take)
        if fx_count > 0 then
            for i = 0, fx_count - 1 do
                local retval, fx_name = r.TakeFX_GetFXName(take, i, "")
                local is_open = r.TakeFX_GetFloatingWindow(take, i)
                local is_enabled = r.TakeFX_GetEnabled(take, i)
                local display_name = is_enabled and fx_name or fx_name .. " (Bypassed)"

                r.ImGui_PushID(ctx, i)
                r.ImGui_BeginGroup(ctx)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00FF00FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00DD00FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF0000FF)
                if r.ImGui_Button(ctx, "##updown", 13, 13) then
                    if i > 0 then
                        r.TakeFX_CopyToTake(take, i, take, i - 1, true)
                    end
                    r.ImGui_SetNextWindowFocus(ctx)
                end
                if r.ImGui_IsItemHovered(ctx) and config.show_tooltips then
                    r.ImGui_SetTooltip(ctx, "Left click up / Right click down")
                end
                if r.ImGui_IsItemClicked(ctx, 1) and i < fx_count - 1 then
                    r.TakeFX_CopyToTake(take, i, take, i + 1, true)
                    r.ImGui_SetNextWindowFocus(ctx)
                end
                r.ImGui_PopStyleColor(ctx, 3)

                r.ImGui_SameLine(ctx)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
                r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) - 3)

                if not is_enabled then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                end

                if r.ImGui_Button(ctx, display_name, 0, 13) then
                    if is_open then
                        r.TakeFX_Show(take, i, 2)
                    else
                        r.TakeFX_Show(take, i, 3)
                    end
                end

                if not is_enabled then
                    r.ImGui_PopStyleColor(ctx)
                end
                r.ImGui_PopStyleColor(ctx, 3)

                if r.ImGui_BeginPopupContextItem(ctx) then
                    if r.ImGui_MenuItem(ctx, "Delete") then
                        r.TakeFX_Delete(take, i)
                    end
                    if r.ImGui_MenuItem(ctx, "Copy Plugin") then
                        copied_plugin = {take = take, index = i}
                    end
                    if r.ImGui_MenuItem(ctx, "Paste Plugin", nil, copied_plugin ~= nil) then
                        if copied_plugin then
                            local _, orig_name = r.TakeFX_GetFXName(copied_plugin.take, copied_plugin.index, "")
                            r.TakeFX_AddByName(take, orig_name, -1000)
                        end
                    end
                    if r.ImGui_MenuItem(ctx, is_enabled and "Bypass plugin" or "Unbypass plugin") then
                        r.TakeFX_SetEnabled(take, i, not is_enabled)
                    end
                    r.ImGui_EndPopup(ctx)
                end

                r.ImGui_EndGroup(ctx)
                r.ImGui_PopID(ctx)
            end
        else
            r.ImGui_Text(ctx, "No FX on Item")
        end

        if copied_plugin then
            local is_empty = fx_count == 0
            local button_text = is_empty and "Paste Plugin" or "Paste Plugin at End"
            if r.ImGui_Button(ctx, button_text) then
                local _, orig_name = r.TakeFX_GetFXName(copied_plugin.take, copied_plugin.index, "")
                local insert_position = is_empty and 0 or fx_count
                r.TakeFX_CopyToTake(copied_plugin.take, copied_plugin.index, take, insert_position, false)
            end
        end
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Separator(ctx)
    -- Notation:
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)

    -- Eerst de kleurknop
    if r.ImGui_ColorButton(ctx, "##notes_color", config.item_notes_color, 0, 13, 13) then
        r.ImGui_OpenPopup(ctx, "NotesColorPopup")
    end
    r.ImGui_SameLine(ctx)

    if r.ImGui_Selectable(ctx, config.show_notes and " - " or " + ") then
        config.show_notes = not config.show_notes
        SaveConfig()
    end
    
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "Notes:")

    -- Save knop rechts uitlijnen
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local text_width = r.ImGui_CalcTextSize(ctx, "Save")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, window_width - text_width - 5)
    if r.ImGui_Selectable(ctx, "Save", false, r.ImGui_SelectableFlags_None()) then
        SaveNotes()
    end

    if r.ImGui_BeginPopup(ctx, "NotesColorPopup") then
        local changed, new_color = r.ImGui_ColorEdit4(ctx, "Notes Color", config.item_notes_color)
        if changed then
            config.item_notes_color = new_color
            SaveConfig()
        end
        r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 2)

    if config.show_notes then
        local item_guid = r.BR_GetMediaItemGUID(item)
        if not notes[item_guid] then
            notes[item_guid] = LoadNotes()[item_guid] or ""
        end

        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), config.item_notes_color) 
        if r.ImGui_BeginChild(ctx, "NotesSection", -1, notes_height) then
            -- Rechtsklik check eerst
            if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "NotesColorPopup")
            end
            
            -- Color picker popup
            if r.ImGui_BeginPopup(ctx, "NotesColorPopup") then
                local changed, new_color = r.ImGui_ColorEdit4(ctx, "Notes Color", is_item and config.item_notes_color or config.track_notes_color)
                if changed then
                    if is_item then
                        config.item_notes_color = new_color
                    else
                        config.track_notes_color = new_color
                    end
                    SaveConfig()
                end
                r.ImGui_EndPopup(ctx)
            end
        
            -- Dan pas de InputTextMultiline
            local changed, new_note = r.ImGui_InputTextMultiline(ctx, "##itemnotes", notes[item_guid], -1, notes_height - 10)
            if changed then
                notes[item_guid] = new_note
                SaveNotes()
            end
        
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_PopStyleColor(ctx)
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



----------------------------------------------------
local function CalculateTopHeight(config)
    local height = 0
    if not config.hideTopButtons then height = height + 30 end
    height = height + 50  -- track info header
    if config.show_tags then height = height + 65 end
    return height
end

local function CalculateMenuHeight(config)
    local height = 16
    if config.show_favorites then height = height + 16 end
    if config.show_all_plugins then height = height + 16 end
    if config.show_developer then height = height + 16 end
    if config.show_folders then height = height + 16 end
    if config.show_fx_chains then height = height + 16 end
    if config.show_track_templates then height = height + 16 end
    if config.show_category then height = height + 16 end
    if config.show_container then height = height + 16 end
    if config.show_video_processor then height = height + 16 end
    if config.show_projects then height = height + 16 end
    if config.show_sends then height = height + 16 end
    if config.show_action then height = height + 16 end
    if LAST_USED_FX then height = height + 16 end
    return height
end

local function CalculateBottomSectionHeight(config)
    local height = 0
    if not config.hideBottomButtons then height = height + 70 end
    if not config.hideVolumeSlider then
        height = height + 40
    end
    if not config.hideMeter then height = height + 90 end
    return height
end

-----------------------------------------------------------------
function Frame()
    local search = FilterBox()
    if search then return end
    
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local menu_items_height = CalculateMenuHeight(config)
    local bottom_section_height = CalculateBottomSectionHeight(config)
    local available_height = window_height - r.ImGui_GetCursorPosY(ctx) - bottom_section_height - menu_items_height + 10
    if config.show_favorites and #favorite_plugins > 0 then
        r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
        r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 5)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
      
        if r.ImGui_BeginMenu(ctx, "FAVORITES") then
            DrawFavorites()
            if not r.ImGui_IsAnyItemHovered(ctx) and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId()) then
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_EndMenu(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 4)
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
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 5)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
         
                if r.ImGui_BeginMenu(ctx, CAT_TEST[i].name) then
                    if CAT_TEST[i].name == "FX CHAINS" then
                        DrawFxChains(CAT_TEST[i].list)
                        if not r.ImGui_IsAnyItemHovered(ctx) and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId()) then
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    elseif CAT_TEST[i].name == "TRACK TEMPLATES" then
                        DrawTrackTemplates(CAT_TEST[i].list)
                        if not r.ImGui_IsAnyItemHovered(ctx) and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId()) then
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    else
                        DrawItems(CAT_TEST[i].list, CAT_TEST[i].name)
                    end
                    r.ImGui_EndMenu(ctx)
                end
                
            
            r.ImGui_PopStyleVar(ctx, 4)
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
                if not show_media_browser then
                    UpdateLastViewedFolder(selected_folder)
                    show_media_browser = true
                    show_sends_window = false
                    show_action_browser = false
                    selected_folder = "Projects"
                    LoadProjects()
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    selected_folder = last_viewed_folder
                    GetPluginsForFolder(last_viewed_folder)
                end
                ClearScreenshotCache()
            end
        end
        
        if config.show_sends then
            if r.ImGui_Selectable(ctx, "SEND/RECEIVE") then
                if not show_sends_window then
                    UpdateLastViewedFolder(selected_folder)
                    show_sends_window = true
                    show_media_browser = false
                    show_action_browser = false
                    selected_folder = "Sends/Receives"
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    selected_folder = last_viewed_folder
                    GetPluginsForFolder(last_viewed_folder)
                end
                ClearScreenshotCache()
            end
        end
        
        if config.show_actions then
            if r.ImGui_Selectable(ctx, "ACTIONS") then
                if not show_action_browser then
                    UpdateLastViewedFolder(selected_folder)
                    show_action_browser = true
                    show_media_browser = false
                    show_sends_window = false
                    selected_folder = "Actions"
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    selected_folder = last_viewed_folder
                    GetPluginsForFolder(last_viewed_folder)
                end
                ClearScreenshotCache()
            end
        end

        if LAST_USED_FX and r.ValidatePtr(TRACK, "MediaTrack*") then
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
        if r.ImGui_BeginChild(ctx, "##popup2", -1, available_height) then
            ShowItemFX()
            r.ImGui_EndChild(ctx)
        end
    else
        if r.ImGui_BeginChild(ctx, "##popupp3", -1, available_height) then
            ShowTrackFX()
            r.ImGui_EndChild(ctx)
        end
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

function InitializeImGuiContext()
    if not ctx then
        ctx = r.ImGui_CreateContext('TK FX Browser')
        
        NormalFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 13, r.ImGui_FontFlags_Bold())
        TinyFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 10)
        LargeFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 16, r.ImGui_FontFlags_Bold())
        IconFont = r.ImGui_CreateFont(script_path .. 'Icons-Regular.otf', 12)
       
        r.ImGui_Attach(ctx, NormalFont)
        r.ImGui_Attach(ctx, TinyFont)
        r.ImGui_Attach(ctx, LargeFont)
        r.ImGui_Attach(ctx, IconFont)
        
    end
end

function EnsureWindowVisible()
    if config.hide_main_window then
        config.dock_screenshot_window = false
        config.show_screenshot_window = true
        r.ImGui_SetNextWindowPos(ctx, 10000, 10000)
        was_hidden = true
    else
        if was_hidden then
            local viewport = r.ImGui_GetMainViewport(ctx)
            local vp_x, vp_y = r.ImGui_Viewport_GetPos(viewport)
            local vp_w, vp_h = r.ImGui_Viewport_GetWorkSize(viewport)
            
            -- Aangepaste breedte naar 200
            local window_w = 200
            local window_h = 600
            local center_x = vp_x + (vp_w - window_w) * 0.5
            local center_y = vp_y + (vp_h - window_h) * 0.5
            
            r.ImGui_SetNextWindowPos(ctx, center_x, center_y, r.ImGui_Cond_Always())
            r.ImGui_SetNextWindowSize(ctx, window_w, window_h, r.ImGui_Cond_Always())
            
            was_hidden = false
        end
    end
end

-----------------------------------------------------------------------------------------
function Main()
    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        InitializeImGuiContext()
        return r.defer(Main)
    end   
    if needs_font_update then
        UpdateFonts()
        needs_font_update = false
    end
    local currentProjectPath = r.EnumProjects(-1, '')
    if lastProjectPath ~= currentProjectPath then
        InitializeImGuiContext()
        lastProjectPath = currentProjectPath
        if not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            return r.defer(Main)
        end
    end
        userScripts = loadUserScripts()
        local prev_track = TRACK
        local selected_track = r.GetSelectedTrack(0, 0)
        local master_track = r.GetMasterTrack(0)
        if r.IsTrackSelected(master_track) then
            TRACK = master_track
            is_master_track_selected = true
        elseif selected_track then
            TRACK = selected_track
            is_master_track_selected = false
        end
        if TRACK ~= last_selected_track and selected_folder == "Current Track FX" then
            ClearScreenshotCache()

        end
        
        last_selected_track = TRACK
        
        ProcessTextureLoadQueue()
        if r.time_precise() % 300 < 1 then
            ClearScreenshotCache(true)
        end
        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 3, 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 5)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 8)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), config.button_background_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), config.button_hover_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Tab(), config.tab_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabHovered(), config.tab_hovered_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), config.frame_bg_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), config.frame_bg_hover_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), config.frame_bg_active_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), config.slider_grab_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), config.slider_active_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.dropdown_bg_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), r.ImGui_ColorConvertDouble4ToU32(0.7, 0.7, 0.7, 1.0))
        r.ImGui_PushFont(ctx, NormalFont)
        r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
        else
            InitializeImGuiContext()
        end

-- FX lijst hoogte berekenen
local fx_list_height = 0
if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") then
    local fx_count = r.TrackFX_GetCount(TRACK)
    fx_list_height = fx_count * 15
end

-- Totale minimale hoogte berekenen met nieuwe functies
local min_window_height = CalculateTopHeight(config) + CalculateMenuHeight(config) + fx_list_height + CalculateBottomSectionHeight(config) + 60

-- Window constraints toepassen
r.ImGui_SetNextWindowSizeConstraints(ctx, 140, min_window_height, 16384, 16384)
----------------------------------------------------------------------------------   
handleDocking()
EnsureWindowVisible()

local visible, open = r.ImGui_Begin(ctx, 'TK FX BROWSER', true, window_flags | r.ImGui_WindowFlags_NoScrollWithMouse() | r.ImGui_WindowFlags_NoScrollbar())
dock = r.ImGui_GetWindowDockID(ctx)

if visible then
    local main_window_pos_x, main_window_pos_y = r.ImGui_GetWindowPos(ctx)
    local main_window_width = r.ImGui_GetWindowWidth(ctx)
    if config.show_screenshot_window then
        r.ImGui_PushID(ctx, "ScreenshotWindow")
        local screenshot_visible = ShowScreenshotWindow()
        if screenshot_visible then
            r.ImGui_EndChild(ctx)  -- Sluit ScreenshotSection
            r.ImGui_End(ctx)
        end
        r.ImGui_PopID(ctx)
    end
    if bulk_screenshot_progress > 0 and bulk_screenshot_progress < 1 then
        local progress_text = string.format("Loading %d/%d (%.1f%%)", loaded_fx_count, total_fx_count, bulk_screenshot_progress * 100)
        r.ImGui_ProgressBar(ctx, bulk_screenshot_progress, -1, 0, progress_text)
    end
    local before_pos = r.ImGui_GetCursorPosY(ctx)
    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
            local track_color, text_color = GetTrackColorAndTextColor(TRACK)
            local track_name = GetTrackName(TRACK)
            local track_type = GetTrackType(TRACK)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 4)
            local window_width = r.ImGui_GetWindowWidth(ctx)
            local track_info_width = math.max(window_width - 10, 125)  -- Minimaal 125, of vensterbreedte - 20
            
            if r.ImGui_BeginChild(ctx, "TrackInfo", track_info_width, 60) then
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
                local window_width = r.ImGui_GetWindowWidth(ctx)                          
                r.ImGui_SetCursorPos(ctx, 20, 0)
                if r.ImGui_Button(ctx, show_settings and '\u{0047}' or '\u{0047}', 20, 20) then
                    show_settings = not show_settings
                end

                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPos(ctx, window_width - 40, 0)
                if r.ImGui_Button(ctx, "\u{0048}", 20, 20) then
                    local command_id = r.NamedCommandLookup("_RS288e3cc7228dd8b05c5cd6394578cc42ca6b4940")  
                    r.Main_OnCommand(command_id, 0)
                end
                
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPos(ctx, window_width - 20, 0)
                if r.ImGui_Button(ctx, "\u{0045}", 20, 20) then
                    change_dock = true 
                    ClearScreenshotCache()
                    ShowPluginScreenshot()
                end
                
                -- Herstel de stijlen
                if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                    r.ImGui_PopFont(ctx)
                end
                
                r.ImGui_PopStyleColor(ctx, 4)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                r.ImGui_PushFont(ctx, LargeFont)
                local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                local window_width = r.ImGui_GetWindowWidth(ctx)
                local pos_x = (window_width - text_width -7) * 0.5
                local window_height = r.ImGui_GetWindowHeight(ctx)
                local text_height = r.ImGui_GetTextLineHeight(ctx)
                local pos_y = (window_height - text_height) * 0.4
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)  -- Volledig doorzichtige knop
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)  -- Licht grijs bij hover
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)  -- Donkerder grijs bij klik
                r.ImGui_SetCursorPos(ctx, pos_x, pos_y)
                if r.ImGui_Button(ctx, track_name) then
                    show_rename_popup = true
                    new_track_name = track_name
                end
                r.ImGui_PopStyleColor(ctx, 3)
                if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                    r.ImGui_PopFont(ctx)
                end

                r.ImGui_PushFont(ctx, NormalFont)
                if r.ImGui_IsItemClicked(ctx, 1) then 
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
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.dropdown_bg_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1))
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), config.button_background_color)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), config.button_hover_color)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 4)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 4, 4)
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 4)
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
                    if r.ImGui_Button(ctx, " Add Script ") then
                        show_add_script_popup = true
                        keep_context_menu_open = false
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                    r.ImGui_EndGroup(ctx)
                    --r.ImGui_PopStyleVar(ctx)
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
                    r.ImGui_PopStyleVar(ctx, 3)
                    r.ImGui_PopStyleColor(ctx, 4)
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
                if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                    r.ImGui_PopFont(ctx)
                end
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
                    local current_track_number = r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER")
                    if current_track_number == 1 then
                        -- Bij eerste track, ga naar master
                        r.SetOnlyTrackSelected(r.GetMasterTrack(0))
                    elseif r.IsTrackSelected(r.GetMasterTrack(0)) then
                        -- Bij master track, ga naar laatste track
                        local last_track = r.GetTrack(0, r.GetNumTracks() - 1)
                        if last_track then r.SetOnlyTrackSelected(last_track) end
                    else
                        -- Anders ga naar vorige track
                        local prev_track = r.GetTrack(0, current_track_number - 2)
                        if prev_track then r.SetOnlyTrackSelected(prev_track) end
                    end
                end

                r.ImGui_SetCursorPos(ctx, window_width - 16, window_height - 20)
                if r.ImGui_Button(ctx, ">", 20, 20) then
                    if r.IsTrackSelected(r.GetMasterTrack(0)) then
                        -- Bij master track, ga naar eerste track
                        local first_track = r.GetTrack(0, 0)
                        if first_track then r.SetOnlyTrackSelected(first_track) end
                    else
                        local next_track = r.GetTrack(0, r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER"))
                        if next_track then 
                            r.SetOnlyTrackSelected(next_track)
                        else
                            -- Bij laatste track, ga naar master
                            r.SetOnlyTrackSelected(r.GetMasterTrack(0))
                        end
                    end
                end
                r.ImGui_PopStyleColor(ctx, 3)
                if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                    r.ImGui_PopFont(ctx)
                end
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_PopStyleColor(ctx)
            
            -- tag sectie
            if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") and config.show_tags then
                if r.ImGui_BeginChild(ctx, "TagSection", track_info_width, 45) then
                    current_tag_window_height = r.ImGui_GetWindowHeight(ctx) 
                    
                    if r.ImGui_Button(ctx, "+", 16, 16) then
                        r.ImGui_OpenPopup(ctx, "TagManager")
                    end
                    r.ImGui_SameLine(ctx)
                    local track_guid = r.GetTrackGUID(TRACK)
                    if track_tags[track_guid] and #track_tags[track_guid] > 0 then
                        local available_width = track_info_width - 10
                        local current_line_width = 0
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, -5)
                        
                        for i, tag in ipairs(track_tags[track_guid]) do
                            local tag_width = r.ImGui_CalcTextSize(ctx, tag) + 10
                            
                            if current_line_width + tag_width > available_width then
                                r.ImGui_NewLine(ctx)
                                current_line_width = 0
                            end
                            
                            if current_line_width > 0 then
                                r.ImGui_SameLine(ctx)
                            end
                            
                            -- Style and button rendering
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 2, 2)
                            local button_pressed = false
                            local tag_color = tag_colors[tag] or config.button_background_color
                            local _, text_color = GetTagColorAndTextColor(tag_color)
                            if tag_colors[tag] then
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), tag_colors[tag])
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), tag_colors[tag])
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                                button_pressed = r.ImGui_Button(ctx, tag)
                                r.ImGui_PopStyleColor(ctx, 3)
                            else
                                button_pressed = r.ImGui_Button(ctx, tag)
                            end
                            r.ImGui_PopStyleVar(ctx)
                            -- Handle button click
                            if button_pressed then

                                local tagged_tracks = FilterTracksByTag(tag)
                                
                                -- Check welke knop actief is en voer de bijbehorende actie uit
                                if mute_mode then
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_MUTE", 1)
                                    end
                                else
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
                                    end
                                end
                            
                                if solo_mode then
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
                                    end
                                else
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                                    end
                                end
                                if select_mode then
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetTrackSelected(track, true)
                                    end
                                else
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetTrackSelected(track, false)
                                    end
                                end

                                if color_mode then
                                    for _, track in ipairs(tagged_tracks) do
                                        local tag_color = tag_colors[tag] or 0
                                        local red = (tag_color >> 24) & 0xFF
                                        local g = (tag_color >> 16) & 0xFF
                                        local b = (tag_color >> 8) & 0xFF
                                        local native_color = r.ColorToNative(red, g, b) | 0x1000000
                                        r.SetTrackColor(track, native_color)
                                    end
                                end

                                local tagged_tracks = FilterTracksByTag(tag)

                                if hide_mode == 0 then
                                    -- Show tagged tracks
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                                    end
                                elseif hide_mode == 1 then
                                    -- Hide tagged tracks
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
                                    end
                                elseif hide_mode == 3 then
                                    -- Verberg alle tracks behalve die met deze tag
                                    for i = 0, r.CountTracks(0) - 1 do
                                        local track = r.GetTrack(0, i)
                                        local has_tag = false
                                        for _, tagged_track in ipairs(tagged_tracks) do
                                            if track == tagged_track then
                                                has_tag = true
                                                break
                                            end
                                        end
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", has_tag and 1 or 0)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", has_tag and 1 or 0)
                                    end
                                else
                                    -- Show all tracks
                                    for i = 0, r.CountTracks(0) - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                                    end
                                end
                                r.TrackList_AdjustWindows(false)
                                r.UpdateArrange()
                                
                            end

                         -- Context menu
                            if r.ImGui_IsItemClicked(ctx, 1) then
                                r.ImGui_OpenPopup(ctx, "TagOptions_" .. i)
                            end
                            
                            if r.ImGui_BeginPopup(ctx, "TagOptions_" .. i) then
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                
                                if r.ImGui_MenuItem(ctx, "Remove Tag") then
                                    local track_guid = r.GetTrackGUID(TRACK)
                                    if track_tags[track_guid] then
                                        table.remove(track_tags[track_guid], i)
                                        SaveTags()
                                    end
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)

                                if r.ImGui_MenuItem(ctx, "Select all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    r.Main_OnCommand(40297, 0) -- Unselect all tracks
                                    for _, track in ipairs(tracks) do
                                        r.SetTrackSelected(track, true)
                                    end
                                end
                                if r.ImGui_MenuItem(ctx, "Unselect all tracks") then
                                    r.Main_OnCommand(40297, 0) -- Unselect all tracks
                                end                                
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)

                                if r.ImGui_MenuItem(ctx, "Hide all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
                                    end
                                    r.TrackList_AdjustWindows(false)  -- false voor mixer view update
                                end
                                
                                if r.ImGui_MenuItem(ctx, "Show all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                                    end
                                    r.TrackList_AdjustWindows(false)  -- false voor mixer view update
                                end
                                if r.ImGui_MenuItem(ctx, "Hide all tracks except with this tag") then
                                    local tagged_tracks = FilterTracksByTag(tag)
                                    local track_count = r.CountTracks(0)
                                    for i = 0, track_count - 1 do
                                        local track = r.GetTrack(0, i)
                                        local should_hide = true
                                        for _, tagged_track in ipairs(tagged_tracks) do
                                            if track == tagged_track then
                                                should_hide = false
                                                break
                                            end
                                        end
                                        if should_hide then
                                            r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
                                            r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
                                        end
                                    end
                                    r.TrackList_AdjustWindows(false)
                                end
                                
                                if r.ImGui_MenuItem(ctx, "Show all tracks") then
                                    local track_count = r.CountTracks(0)
                                    for i = 0, track_count - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                                    end
                                    r.TrackList_AdjustWindows(false)
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)

                                if r.ImGui_MenuItem(ctx, "Rename all tracks with this tag") then
                                        local tagged_tracks = FilterTracksByTag(tag)
                                    for i, track in ipairs(tagged_tracks) do
                                            local new_name = tag
                                        if #tagged_tracks > 1 then
                                            new_name = tag .. " " .. i
                                        end
                                        r.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
                                    end
                                end                            
                                if r.ImGui_MenuItem(ctx, "Rename current track with this tag") then
                                    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                            r.GetSetMediaTrackInfo_String(TRACK, "P_NAME", tag, true)
                                    end
                                end
                                
                                if r.ImGui_MenuItem(ctx, "Rename tagged tracks to first plugin") then
                                        local tagged_tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tagged_tracks) do
                                            local fx_count = r.TrackFX_GetCount(track)
                                        if fx_count > 0 then
                                                local _, fx_name = r.TrackFX_GetFXName(track, 0, "")
                                                fx_name = fx_name:gsub("^[^:]+:%s*", "")
                                                r.GetSetMediaTrackInfo_String(track, "P_NAME", fx_name, true)
                                        end
                                    end
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)

                                if r.ImGui_MenuItem(ctx, "Move to new folder") then
                                    local tracks = FilterTracksByTag(tag)
                                    if #tracks > 0 then
                                        local first_track_idx = math.huge
                                        for _, track in ipairs(tracks) do
                                            local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
                                            first_track_idx = math.min(first_track_idx, track_idx)
                                        end
                                        r.InsertTrackAtIndex(first_track_idx, true)
                                        local folder_track = r.GetTrack(0, first_track_idx)
                                        r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", tag .. " Folder", true)
                                        r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                        for _, track in ipairs(tracks) do
                                            r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
                                        end
                                        r.SetMediaTrackInfo_Value(tracks[#tracks], "I_FOLDERDEPTH", -1)
                                    end
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)
                                
                                if r.ImGui_MenuItem(ctx, "Mute all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_MUTE", 1)
                                    end
                                end
                                if r.ImGui_MenuItem(ctx, "Unmute all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
                                    end
                                end

                                if r.ImGui_MenuItem(ctx, "Solo tracks with this tag") then
                                    local all_tracks = r.CountTracks(0)
                                    -- Eerst unsolo alle tracks
                                    for i = 0, all_tracks - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                                    end
                                    -- Dan solo de tagged tracks
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 2) -- 2 = Solo
                                    end
                                end
                                if r.ImGui_MenuItem(ctx, "Unsolo all tracks") then
                                    local all_tracks = r.CountTracks(0)
                                    for i = 0, all_tracks - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                                    end
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)
                                if r.ImGui_MenuItem(ctx, "Set Color") then
                                    local current_color = tag_colors[tag] or 0xFFFFFFFF
                                    local ok, new_color = r.GR_SelectColor(current_color)
                                    if ok then
                                        local native_color = new_color|0x1000000
                                        local red, g, b = reaper.ColorFromNative(native_color)
                                        local color_vec4 = r.ImGui_ColorConvertDouble4ToU32(red/255, g/255, b/255, 1.0)
                                        tag_colors[tag] = color_vec4
                                        SaveTags()
                                    end
                                end

                                if r.ImGui_MenuItem(ctx, "Apply Tag Color to Tracks") and tag_colors[tag] then
                                    local track_count = r.CountTracks(0)
                                    local imgui_color = tag_colors[tag]
                                    local red, g, b, a = r.ImGui_ColorConvertU32ToDouble4(imgui_color)
                                    local native_color = reaper.ColorToNative(math.floor(red*255), math.floor(g*255), math.floor(b*255))|0x1000000
                                    
                                    for i = 0, track_count - 1 do
                                        local tr = r.GetTrack(0, i)
                                        local tr_guid = r.GetTrackGUID(tr)
                                        if track_tags[tr_guid] then
                                            for _, t in ipairs(track_tags[tr_guid]) do
                                                if t == tag then
                                                    reaper.SetTrackColor(tr, native_color)
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end
                                
                                
                                if r.ImGui_MenuItem(ctx, "Remove Color") then
                                    tag_colors[tag] = nil
                                    SaveTags()
                                end
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_EndPopup(ctx)
                            end
                            
                            current_line_width = current_line_width + tag_width
                        end
                        
                        r.ImGui_PopStyleVar(ctx)
                    end
                    
                    if r.ImGui_BeginPopup(ctx, "TagManager") then
                        --r.ImGui_SetNextWindowSize(ctx, 150, 0)
                        r.ImGui_PushItemWidth(ctx, 110)
                        local changed, new_tag = r.ImGui_InputText(ctx, "##AddTag", new_tag_buffer)
                        if changed then
                            new_tag_buffer = new_tag
                        end
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, "+") and new_tag_buffer ~= "" then
                            local track_guid = r.GetTrackGUID(TRACK)
                            track_tags[track_guid] = track_tags[track_guid] or {}
                            table.insert(track_tags[track_guid], new_tag_buffer)
                            available_tags[new_tag_buffer] = true  -- Voeg toe aan available tags
                            SaveTags()
                            new_tag_buffer = ""
                        end
                        local all_tags = {}
                        for guid, tags in pairs(track_tags) do
                            for _, tag in ipairs(tags) do
                                all_tags[tag] = true
                            end
                        end
                        r.ImGui_Separator(ctx)
                        r.ImGui_Text(ctx, "Available Tags:")
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, -4)  -- Add this line
                        local available_width = select(1, r.ImGui_GetContentRegionAvail(ctx))
                        local current_line_width = 0

                        for tag, _ in pairs(available_tags) do
                            local tag_width = r.ImGui_CalcTextSize(ctx, tag) + 10
                            
                            if current_line_width + tag_width > available_width then
                                r.ImGui_NewLine(ctx)
                                current_line_width = 0
                            elseif current_line_width > 0 then
                                r.ImGui_SameLine(ctx)
                            end

                            local tag_color = tag_colors[tag] or config.button_background_color
                            local _, text_color = GetTagColorAndTextColor(tag_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), tag_colors[tag] or config.button_background_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), tag_colors[tag] or config.button_background_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                            if r.ImGui_Button(ctx, tag) then
                                local track_guid = r.GetTrackGUID(TRACK)
                                track_tags[track_guid] = track_tags[track_guid] or {}
                                if not table.contains(track_tags[track_guid], tag) then
                                    table.insert(track_tags[track_guid], tag)
                                    SaveTags()
                                end
                            end
                            if r.ImGui_IsItemClicked(ctx, 1) then 
                                r.ImGui_OpenPopup(ctx, "tag_context_menu_" .. tag)
                                selected_tag = tag
                            end
                            current_line_width = current_line_width + tag_width
                            r.ImGui_PopStyleColor(ctx, 3)
                            if r.ImGui_BeginPopup(ctx, "tag_context_menu_" .. tag) then
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 2)
                                if r.ImGui_MenuItem(ctx, "Delete") then
                                    for guid, track_tag_list in pairs(track_tags) do
                                        for i = #track_tag_list, 1, -1 do
                                            if track_tag_list[i] == selected_tag then table.remove(track_tag_list, i) end
                                        end
                                    end
                                    available_tags[selected_tag] = nil
                                    tag_colors[selected_tag] = nil
                                    SaveTags()
                                end
                                if r.ImGui_MenuItem(ctx, "Add to current selected tracks") then
                                    local track_count = r.CountSelectedTracks(0)
                                    for i = 0, track_count - 1 do
                                        local track = r.GetSelectedTrack(0, i)
                                        local track_guid = r.GetTrackGUID(track)
                                        track_tags[track_guid] = track_tags[track_guid] or {}
                                        if not table.contains(track_tags[track_guid], selected_tag) then
                                            table.insert(track_tags[track_guid], selected_tag)
                                        end
                                    end
                                    SaveTags()
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)

                                if r.ImGui_MenuItem(ctx, "Select all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    r.Main_OnCommand(40297, 0) -- Unselect all tracks
                                    for _, track in ipairs(tracks) do
                                        r.SetTrackSelected(track, true)
                                    end
                                end
                                if r.ImGui_MenuItem(ctx, "Unselect all tracks") then
                                    r.Main_OnCommand(40297, 0) -- Unselect all tracks
                                end                                
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)
                                
                                if r.ImGui_MenuItem(ctx, "Hide all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
                                    end
                                    r.TrackList_AdjustWindows(false)  -- false voor mixer view update
                                end
                                
                                if r.ImGui_MenuItem(ctx, "Show all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                                    end
                                    r.TrackList_AdjustWindows(false)  -- false voor mixer view update
                                end
                                if r.ImGui_MenuItem(ctx, "Hide all tracks except with this tag") then
                                    local tagged_tracks = FilterTracksByTag(tag)
                                    local track_count = r.CountTracks(0)
                                    for i = 0, track_count - 1 do
                                        local track = r.GetTrack(0, i)
                                        local should_hide = true
                                        for _, tagged_track in ipairs(tagged_tracks) do
                                            if track == tagged_track then
                                                should_hide = false
                                                break
                                            end
                                        end
                                        if should_hide then
                                            r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
                                            r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
                                        end
                                    end
                                    r.TrackList_AdjustWindows(false)
                                end
                                
                                if r.ImGui_MenuItem(ctx, "Show all tracks") then
                                    local track_count = r.CountTracks(0)
                                    for i = 0, track_count - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                                    end
                                    r.TrackList_AdjustWindows(false)
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)

                                if r.ImGui_MenuItem(ctx, "Rename all tracks with this tag") then
                                        local tagged_tracks = FilterTracksByTag(tag)
                                    for i, track in ipairs(tagged_tracks) do
                                            local new_name = tag
                                        if #tagged_tracks > 1 then
                                            new_name = tag .. " " .. i
                                        end
                                        r.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
                                    end
                                end                            
                                if r.ImGui_MenuItem(ctx, "Rename current track with this tag") then
                                    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                            r.GetSetMediaTrackInfo_String(TRACK, "P_NAME", tag, true)
                                    end
                                end
                                
                                if r.ImGui_MenuItem(ctx, "Rename tagged tracks to first plugin") then
                                        local tagged_tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tagged_tracks) do
                                            local fx_count = r.TrackFX_GetCount(track)
                                        if fx_count > 0 then
                                                local _, fx_name = r.TrackFX_GetFXName(track, 0, "")
                                                fx_name = fx_name:gsub("^[^:]+:%s*", "")
                                                r.GetSetMediaTrackInfo_String(track, "P_NAME", fx_name, true)
                                        end
                                    end
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)

                                if r.ImGui_MenuItem(ctx, "Move to new folder") then
                                    local tracks = FilterTracksByTag(tag)
                                    if #tracks > 0 then
                                        local first_track_idx = math.huge
                                        for _, track in ipairs(tracks) do
                                            local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
                                            first_track_idx = math.min(first_track_idx, track_idx)
                                        end
                                        r.InsertTrackAtIndex(first_track_idx, true)
                                        local folder_track = r.GetTrack(0, first_track_idx)
                                        r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", tag .. " Folder", true)
                                        r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                        for _, track in ipairs(tracks) do
                                            r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
                                        end
                                        r.SetMediaTrackInfo_Value(tracks[#tracks], "I_FOLDERDEPTH", -1)
                                    end
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)
                                
                                if r.ImGui_MenuItem(ctx, "Mute all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_MUTE", 1)
                                    end
                                end
                                if r.ImGui_MenuItem(ctx, "Unmute all tracks with this tag") then
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_MUTE", 0)
                                    end
                                end

                                if r.ImGui_MenuItem(ctx, "Solo tracks with this tag") then
                                    local all_tracks = r.CountTracks(0)
                                    -- Eerst unsolo alle tracks
                                    for i = 0, all_tracks - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                                    end
                                    -- Dan solo de tagged tracks
                                    local tracks = FilterTracksByTag(tag)
                                    for _, track in ipairs(tracks) do
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 2) -- 2 = Solo
                                    end
                                end
                                if r.ImGui_MenuItem(ctx, "Unsolo all tracks") then
                                    local all_tracks = r.CountTracks(0)
                                    for i = 0, all_tracks - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                                    end
                                end
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                                r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_PopStyleColor(ctx)
                                if r.ImGui_MenuItem(ctx, "Set Color") then
                                    local current_color = tag_colors[tag] or 0xFFFFFFFF
                                    local ok, new_color = r.GR_SelectColor(current_color)
                                    if ok then
                                        local native_color = new_color|0x1000000
                                        local red, g, b = reaper.ColorFromNative(native_color)
                                        local color_vec4 = r.ImGui_ColorConvertDouble4ToU32(red/255, g/255, b/255, 1.0)
                                        tag_colors[tag] = color_vec4
                                        SaveTags()
                                    end
                                end

                                if r.ImGui_MenuItem(ctx, "Apply Tag Color to Tracks") and tag_colors[tag] then
                                    local track_count = r.CountTracks(0)
                                    local imgui_color = tag_colors[tag]
                                    local red, g, b, a = r.ImGui_ColorConvertU32ToDouble4(imgui_color)
                                    local native_color = reaper.ColorToNative(math.floor(red*255), math.floor(g*255), math.floor(b*255))|0x1000000
                                    
                                    for i = 0, track_count - 1 do
                                        local tr = r.GetTrack(0, i)
                                        local tr_guid = r.GetTrackGUID(tr)
                                        if track_tags[tr_guid] then
                                            for _, t in ipairs(track_tags[tr_guid]) do
                                                if t == tag then
                                                    reaper.SetTrackColor(tr, native_color)
                                                    break
                                                end
                                            end
                                        end
                                    end
                                end
                                
                                
                                if r.ImGui_MenuItem(ctx, "Remove Color") then
                                    tag_colors[tag] = nil
                                    SaveTags()
                                end

                                
                                r.ImGui_PopStyleVar(ctx)
                                r.ImGui_EndPopup(ctx)
                            end
                        end
                        r.ImGui_PopStyleVar(ctx)
                        r.ImGui_EndPopup(ctx)
                    end
                    
                    r.ImGui_EndChild(ctx)
                  
                    
                    -- Mute knop
                    local mute_color_active = mute_mode
                    if mute_color_active then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
                    end

                    if r.ImGui_Button(ctx, "M") then
                        mute_mode = not mute_mode
                    end

                    if mute_color_active then
                        r.ImGui_PopStyleColor(ctx, 3)
                    end

                    r.ImGui_SameLine(ctx)

                    -- Solo knop
                    local solo_color_active = solo_mode
                    if solo_color_active then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
                    end

                    if r.ImGui_Button(ctx, "S") then
                        solo_mode = not solo_mode
                    end

                    if solo_color_active then
                        r.ImGui_PopStyleColor(ctx, 3)
                    end
                    r.ImGui_SameLine(ctx)
                    -- Select knop
                    local select_color_active = select_mode
                    if select_color_active then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
                    end
                    
                    if r.ImGui_Button(ctx, "SL") then
                        select_mode = not select_mode
                    end
                    
                    if select_color_active then
                        r.ImGui_PopStyleColor(ctx, 3)
                    end
                    r.ImGui_SameLine(ctx)
                    -- Color knop
                    local color_color_active = color_mode
                    if color_color_active then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
                    end

                    if r.ImGui_Button(ctx, "CL") then
                        color_mode = not color_mode
                    end

                    if color_color_active then
                        r.ImGui_PopStyleColor(ctx, 3)
                    end
                    r.ImGui_SameLine(ctx)

                    -- Hide/Show knop
                    local button_labels = {"SHOW", "HIDE", "ALL", "INV"}
                    local is_red = hide_mode == 1  

                    if is_red then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
                    end

                    if r.ImGui_Button(ctx, button_labels[hide_mode + 1], 40, 18) then
                        hide_mode = (hide_mode + 1) % 4
                    end

                    if is_red then
                        r.ImGui_PopStyleColor(ctx, 3)
                    end

                    r.ImGui_Separator(ctx)  
                end
            
            end
            if not config.hideTopButtons then
                local button_spacing = 3
                local button_width = (track_info_width - (2 * button_spacing)) / 3           
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
                if r.ImGui_Button(ctx, ADD_FX_TO_ITEM and "ITEM" or "TRCK", button_width, 20) then
                    ADD_FX_TO_ITEM = not ADD_FX_TO_ITEM
                end
                if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Switch between Track or Item")
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
                r.ImGui_PopStyleColor(ctx, 3)
                -- reaper.ImGui_SameLine(ctx)
                if WANT_REFRESH then
                    WANT_REFRESH = nil
                    UpdateChainsTrackTemplates(CAT)
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
            if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                r.ImGui_PopFont(ctx)
            end
        end
        if SHOW_PREVIEW and current_hovered_plugin then 
            ShowPluginScreenshot() 
        end
        if TRACK and not config.hideMeter then
            DrawMeterModule.DrawMeter(r, ctx, config, TRACK, TinyFont)
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
 
       

        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            r.ImGui_PopFont(ctx)
        end
    r.ImGui_PopStyleVar(ctx, 6)
    r.ImGui_PopStyleColor(ctx, 13)
    
    if SHOULD_CLOSE_SCRIPT then
        return
    end
    if open then        
        r.defer(Main)
    end
    
end
InitializeImGuiContext()
Main()