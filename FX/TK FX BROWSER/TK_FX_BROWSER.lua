-- @description TK FX BROWSER
-- @author TouristKiller
-- @version 1.8.7
-- @changelog:
--[[     
++ Fixed bug
            TODO (sometime in the future ;o) ):
            - Auto tracks and send /recieve for multi output plugin
            - Meter functionality (Pre/post Peak) -- vooralsnog niet haalbaar
            - Expand project files
            - Etc......
            
]]--        
--------------------------------------------------------------------------
local r                     = reaper
local script_path           = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator          = package.config:sub(1, 1)
package.path                = script_path .. "?.lua;"
local json                  = require("json")
if not r.APIExists or not r.APIExists("JS_Dialog_BrowseForFolder") then
    local msg = table.concat({
        "Missing dependency: 'js_ReaScriptAPI' (by Julian Sader).",
        "",
        "This script calls JS_Dialog_BrowseForFolder(), which is provided by that extension.",
        "",
        "Install via ReaPack:",
        "1) In REAPER: Extensions > ReaPack > Browse Packages",
        "2) Search for 'js_ReaScriptAPI' and install it",
        "3) Restart REAPER and run the script again."
    }, "\n")
    r.ShowMessageBox(msg, "TK FX BROWSER – Missing dependency", 0)
    return
end
local screenshot_path       = script_path .. "Screenshots" .. os_separator
StartBulkScreenshot         = function() end
local DrawMeterModule       = dofile(script_path .. "DrawMeter.lua")
local TKFXBVars             = dofile(script_path .. "TKFXBVariables.lua")
local window_flags          = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar()

local LAST_OPENED_SENTINEL  = "__LAST_OPENED__"

-- Ratings:
local plugin_ratings_path   = script_path .. "plugin_ratings.json"
local plugin_ratings        = {}
local DedupeByTypePriority

-- Performance caches
local favorite_set          = {}
local pinned_set            = {}
local pinned_norm_set       = {}
local plugin_lower_name     = {}
local normalized_name_cache = {}
local plugin_type_cache     = {}
local type_priority_cache   = nil


local function LaunchTKNotes()
    local notes_path = script_path .. "TK_NOTES.lua"
    if not r.file_exists(notes_path) then
        r.ShowMessageBox("TK_NOTES.lua not found.\nExpected path:\n" .. notes_path, "TK Notes Error", 0)
        return
    end

    local command_id = r.AddRemoveReaScript(true, 0, notes_path, false)
    if not command_id or command_id == 0 or command_id == "" then
        command_id = r.AddRemoveReaScript(true, 0, notes_path, true)
    end

    if type(command_id) == "string" then
        command_id = r.NamedCommandLookup(command_id)
    end

    if not command_id or command_id == 0 then
        r.ShowMessageBox("Unable to register TK_NOTES.lua as an action.", "TK Notes Error", 0)
        return
    end

    r.Main_OnCommand(command_id, 0)
end


local SCRIPT_VERSION
local function GetScriptVersion()
    if SCRIPT_VERSION then return SCRIPT_VERSION end
    local f = io.open(script_path .. "TK_FX_BROWSER.lua", "r")
    if f then
        for i = 1, 50 do
            local l = f:read("*l"); if not l then break end
            local v = l:match("^%-%-%s*@version%s+([%w%._%-]+)")
            if v then SCRIPT_VERSION = v; break end
        end
        f:close()
    end
    SCRIPT_VERSION = SCRIPT_VERSION or "dev"
    return SCRIPT_VERSION
end

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


function GetLowerName(name)
    if not name then return "" end
    local lower = plugin_lower_name[name]
    if lower then return lower end
    lower = name:lower()
    plugin_lower_name[name] = lower
    return lower
end

if not ClearScreenshotCache then function ClearScreenshotCache() end end

function _build_screenshot_signature()
    local cfg = rawget(_G, 'config') or {}
    local folder = tostring(selected_folder or "")
    local subgroup = tostring(browser_panel_selected or "")
    local term = tostring(browser_search_term or "")
    local mode = tostring(view_mode or "")
    local stype = tostring(cfg.screenshot_view_type or "")
    local page = tostring((screenshot_pagination and screenshot_pagination.current_page) or "")
    local priority = table.concat(cfg.plugin_type_priority or {}, ",")
    local apply = tostring(cfg.apply_type_priority or false)
    local respect = tostring(cfg.respect_search_exclusions_in_screenshots or false)
    return table.concat({folder, subgroup, term, mode, stype, page, priority, apply, respect}, "|")
end

local last_visibility_state = nil
local function CheckVisibilityState()
    local visibility_state = r.GetExtState("TK_FX_BROWSER", "visibility")
    local is_visible = visibility_state ~= "hidden"
    
  
    if last_visibility_state == "hidden" and visibility_state ~= "hidden" then
        ClearScreenshotCache()
        if selected_folder then
            GetPluginsForFolder(selected_folder)
        end
    end
    
    last_visibility_state = visibility_state
    return is_visible
end

local function ShouldShowMainWindow()
    local general_visibility = CheckVisibilityState()
    if not general_visibility then
        return false 
    end
    
    return not config.hide_main_window
end

local function SetRunningState(running)
    r.SetExtState("TK_FX_BROWSER", "running", running and "true" or "false", true)
end

local did_initial_refresh = false
local auto_expand_paths = nil 
local force_open_developer_header = false
local force_open_category_header  = false
local force_open_all_plugins_header = false
local force_open_folders_header = false
local force_headers_open_applied = false 
local initial_header_auto_expand_done = false 
local function BuildAutoExpandPaths(target)
    auto_expand_paths = nil
    if not target or target == '' then return end
    if not target:find('/') then return end 
    auto_expand_paths = {}
    local accum = ''
    for part in target:gmatch("[^/]+") do
        accum = (accum == '' and part) or (accum .. '/' .. part)
        auto_expand_paths[accum] = true
    end
end

local function MarkForcedHeaderForSubgroup(subgroup)
    if not subgroup or subgroup == '' or not CAT_TEST then return end
    for i = 1, #CAT_TEST do
        local cat = CAT_TEST[i]
        if cat and type(cat.list) == 'table' then
            if cat.name == 'DEVELOPER' or cat.name == 'CATEGORY' then
                for j = 1, #cat.list do
                    local entry = cat.list[j]
                    if entry and entry.name == subgroup then
                        if cat.name == 'DEVELOPER' then force_open_developer_header = true end
                        if cat.name == 'CATEGORY'  then force_open_category_header  = true end
                        return
                    end
                end
            elseif cat.name == 'ALL PLUGINS' then
                for j = 1, #cat.list do
                    local entry = cat.list[j]
                    if entry and entry.name == subgroup then
                        force_open_all_plugins_header = true
                        return
                    end
                end
            elseif cat.name == 'FOLDERS' then
                for j = 1, #cat.list do
                    local entry = cat.list[j]
                    if entry and entry.name == subgroup then
                        force_open_folders_header = true
                        return
                    end
                end
            end
        end
    end
end

-- Voorwaards mars ;o)
local SearchActions
local CreateSmartMarker

function RenderActionsSection()
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local button_h = r.ImGui_GetFrameHeight(ctx)
    local button_w = button_h
            r.ImGui_PushItemWidth(ctx, avail_w - (button_w * 2) - 10)
    local changed, new_term = r.ImGui_InputTextWithHint(ctx, "##ActionSearch", "SEARCH ACTIONS", action_search_term or "")
    if changed then action_search_term = new_term end
    r.ImGui_PopItemWidth(ctx)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, show_categories and "C" or "A", button_w, button_h) then
        show_categories = not show_categories
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, show_only_active and "O" or "F", button_w, button_h) then
        show_only_active = not show_only_active
    end

    local window_h = r.ImGui_GetWindowHeight(ctx)
    local cur_y = r.ImGui_GetCursorPosY(ctx)
    local footer = 50
    local list_h = window_h - cur_y - footer
    local action_child_open = r.ImGui_BeginChild(ctx, "ActionList", 0, list_h)
    if action_child_open then
        if show_categories then
            local filtered = SearchActions(action_search_term or "")
            for category, actions in pairs(filtered) do
                if #actions > 0 then
                    if r.ImGui_TreeNode(ctx, string.format("%s (%d)", category, #actions)) then
                        for _, action in ipairs(actions) do
                            if action.state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF4000FF) end
                            local prefix = action.state == 1 and "[ON] " or ""
                            if r.ImGui_Selectable(ctx, prefix .. action.name) then
                                r.Main_OnCommand(action.id, 0)
                            elseif r.ImGui_IsItemClicked(ctx, 1) then
                                CreateSmartMarker(action.id)
                            end
                            if action.state == 1 then r.ImGui_PopStyleColor(ctx) end
                        end
                        r.ImGui_TreePop(ctx)
                    end
                end
            end
        else
            for _, action in ipairs(allActions) do
                local state = r.GetToggleCommandState(action.id)
                local matches = (not action_search_term or action_search_term == "") or action.name:lower():find((action_search_term or ""):lower(), 1, true)
                if matches and (not show_only_active or state == 1) then
                    if state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF4000FF) end
                    local prefix = state == 1 and "[ON] " or ""
                    if r.ImGui_Selectable(ctx, prefix .. action.name) then
                        r.Main_OnCommand(action.id, 0)
                    elseif r.ImGui_IsItemClicked(ctx, 1) then
                        CreateSmartMarker(action.id)
                    end
                    if state == 1 then r.ImGui_PopStyleColor(ctx) end
                end
            end
        end
    end
    r.ImGui_EndChild(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_TextWrapped(ctx, "Left-click: Execute action. Right-click: Create smart marker.")
end

_last_screenshot_signature = nil
_screenshots_dirty = false
_pending_clear_cache = false
_last_search_input_time = 0.0
_search_debounce_ms = 120 

function MarkScreenshotsDirty()
    _screenshots_dirty = true
end

function RequestClearScreenshotCache()
    local cfg = rawget(_G, 'config') or {}
    if not cfg.flicker_guard_enabled then
        ClearScreenshotCache()
        return
    end
    _pending_clear_cache = true
    MarkScreenshotsDirty()
end

-- FW
local GetFxListForSubgroup

function RefreshCurrentScreenshotView()
    RequestClearScreenshotCache()
    search_warning_message = nil
    local term = (browser_search_term or "")

    if term ~= "" then
        local term_l = term:lower()
        if browser_panel_selected then
            current_filtered_fx = GetFxListForSubgroup(browser_panel_selected) or {}
            local filtered = {}
            for _, p in ipairs(current_filtered_fx) do
                if p:lower():find(term_l, 1, true) then filtered[#filtered+1] = p end
            end
            if config.apply_type_priority then
                filtered = DedupeByTypePriority(filtered)
            end
            current_filtered_fx = filtered
        elseif selected_folder then
            local base = GetPluginsForFolder(selected_folder) or {}
            local filtered = {}
            for _, p in ipairs(base) do
                if p:lower():find(term_l, 1, true) then filtered[#filtered+1] = p end
            end
            if config.apply_type_priority then
                filtered = DedupeByTypePriority(filtered)
            end
            current_filtered_fx = filtered
        else
           
            local matches = {}
            for _, plugin in ipairs(PLUGIN_LIST or {}) do
                if plugin:lower():find(term_l, 1, true) then matches[#matches+1] = plugin end
            end
            if config.apply_type_priority then
                matches = DedupeByTypePriority(matches)
            end
            screenshot_search_results = {}
            local MAX_RESULTS = 200
            for i = 1, math.min(MAX_RESULTS, #matches) do
                screenshot_search_results[#screenshot_search_results+1] = { name = matches[i] }
            end
            if #matches > MAX_RESULTS then
                search_warning_message = "Showing first " .. MAX_RESULTS .. " results. Please refine your search for more specific results."
            end
            SortScreenshotResults()
            new_search_performed = true
            return
        end
    else
        
        if browser_panel_selected then
            current_filtered_fx = GetFxListForSubgroup(browser_panel_selected) or {}
            if config.apply_type_priority then
                current_filtered_fx = DedupeByTypePriority(current_filtered_fx)
            end
        elseif selected_folder then
            current_filtered_fx = GetPluginsForFolder(selected_folder) or {}
        else
            return
        end
    end


    loaded_items_count = ITEMS_PER_BATCH or loaded_items_count or 30
    screenshot_search_results = {}
    if view_mode == "list" then
        for i = 1, #current_filtered_fx do
            screenshot_search_results[#screenshot_search_results+1] = { name = current_filtered_fx[i] }
        end
    else
        for i = 1, math.min(loaded_items_count, #current_filtered_fx) do
            screenshot_search_results[#screenshot_search_results+1] = { name = current_filtered_fx[i] }
        end
    end
  
    SortScreenshotResults()
    new_search_performed = true
end
if not BuildScreenshotIndex then function BuildScreenshotIndex() end end

dragging_fx_name = dragging_fx_name or nil
potential_drag_fx_name = potential_drag_fx_name or nil
drag_start_x, drag_start_y = drag_start_x or 0, drag_start_y or 0

-- Window state variables
was_hidden = was_hidden or false
was_docked_before_hide = was_docked_before_hide or false

screenshot_search_results = screenshot_search_results or {}
browser_panel_selected = browser_panel_selected or nil
last_selected_folder_before_global = nil

view_mode = view_mode or "screenshots" 

search_texture_cache = search_texture_cache or {}
texture_last_used    = texture_last_used    or {}
texture_load_queue   = texture_load_queue   or {}

function SelectBrowserPanelItem(name)
    browser_panel_selected = name
    if name ~= nil then selected_folder = nil end

    show_media_browser = false
    show_sends_window = false
    show_action_browser = false
    show_scripts_browser = false
end

function SelectFolderExclusive(name)
    selected_folder = name
    if name ~= nil then
        browser_panel_selected = nil
    
        local seeded = GetPluginsForFolder(name) or {}
        if config and config.apply_type_priority and type(seeded) == 'table' then
            seeded = DedupeByTypePriority(seeded)
        end
        current_filtered_fx = seeded
       
        screenshot_search_results = nil
    end
end

function GenerateUniqueID(base_name)
    unique_id_counter = unique_id_counter + 1
    local sanitized_name = base_name:gsub("[^%w%s-]", "_") 
    return "##" .. sanitized_name .. "_" .. unique_id_counter .. "_" .. os.time()
end

function CreateUniqueImageButton(ctx, base_name, texture, width, height)
    local id = GenerateUniqueID(base_name)
    return r.ImGui_ImageButton(ctx, id, texture, width, height), id
end

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

function get_safe_name(name)
    return (name or ""):gsub("[^%w%s-]", "_")
end
-- LOG
local log_file_path = script_path .. "screenshot_log.txt"
function log_to_file(message)
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
function SetDefaultConfig()
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
        show_scripts = true, 
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
        apply_type_priority = true,
        plugin_type_priority = { "CLAP", "VST3", "VST", "JS" },
        screenshot_delay = 0.5,
        close_after_adding_fx = false,
        folder_specific_sizes = {},
        include_x86_bridged = false,
        hide_default_titlebar_menu_items = false,
        add_instruments_on_top = false, 
        show_name_in_screenshot_window = true,
        show_name_in_main_window = true,
        clean_plugin_names = false, 
        remove_manufacturer_names = false, 
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
        
        last_used_project_location = last_used_project_location or PROJECTS_DIR,
        show_project_info = show_project_info or true,
        hide_main_window = false,
        show_browser_panel = true,
        browser_panel_width = browser_panel_width or 200,
        screenshot_section_width = screenshot_section_width or 600, 
        use_pagination = true,
        use_masonry_layout = false,
        show_favorites_on_top = true,
        show_pinned_on_top = true,
        show_pinned_overlay = true,
        show_favorite_overlay = true,
        open_floating_after_adding = false, 
        custom_folders = {},
        pinned_plugins = {},
        pinned_subgroups = {},
        pinned_custom_subfolders = {},
        show_custom_folders = true,
        hide_custom_dropdown = false,
        show_screenshot_search = true,
        show_browser_search = true, 
        enable_drag_add_fx = true, 
        show_missing_screenshots_only = false, 
        bulk_selected_folder = nil, 
        add_fx_with_double_click = false, 
        show_missing_list = true, 
        respect_search_exclusions_in_screenshots = false, 
        flicker_guard_enabled = true,
        last_viewed_folder = nil,
        -- Custom locations
        use_custom_fxchain_dir = false,
        custom_fxchain_dir = "",
        use_custom_template_dir = false,
        custom_template_dir = "",
    } 
end
local config = SetDefaultConfig()    
_G.config = config 
local window_alpha_int = math.floor(config.window_alpha * 100)  
function ClearPerformanceCaches()
    normalized_name_cache = {}
    plugin_type_cache = {}
    type_priority_cache = nil
    if config then
        config._current_version = (config._current_version or 0) + 1
    end
end


local cache_cleanup_counter = 0
function MaybeClearCaches()
    cache_cleanup_counter = cache_cleanup_counter + 1
    
    if cache_cleanup_counter > 1000 or 
       (normalized_name_cache and #normalized_name_cache > 5000) or
       (plugin_type_cache and #plugin_type_cache > 5000) then
        normalized_name_cache = {}
        plugin_type_cache = {}
        cache_cleanup_counter = 0
    end
end

function SaveConfig()
    local file = io.open(script_path .. "config.json", "w")
    if file then
        file:write(json.encode(config))
        file:close()
        ClearPerformanceCaches()
    end
end

function LoadConfig()
    local file = io.open(script_path .. "config.json", "r")
    if file then
        local content = file:read("*all")
        file:close()
        local loaded_config = json.decode(content)
        for k, v in pairs(loaded_config) do
            config[k] = v
        end
        if loaded_config.show_pinned_overlay == nil and config.show_pinned_overlay == nil then
            config.show_pinned_overlay = true
        end
        if loaded_config.show_favorite_overlay == nil and config.show_favorite_overlay == nil then
            config.show_favorite_overlay = true
        end
        config.folder_specific_sizes = loaded_config.folder_specific_sizes or {}
    
        config.pinned_plugins = loaded_config.pinned_plugins or config.pinned_plugins or {}
        pinned_set = {}
        for _, name in ipairs(config.pinned_plugins) do
            if type(name) == 'string' and name ~= '' then
                pinned_set[name] = true
            end
        end
        if type(NormalizePluginNameForMatch) == 'function' then
            pinned_norm_set = {}
            for name, v in pairs(pinned_set) do
                if v and type(name) == 'string' then
                    local k = NormalizePluginNameForMatch(name)
                    if k ~= '' then pinned_norm_set[k] = true end
                end
            end
        end

        config.pinned_subgroups = loaded_config.pinned_subgroups or {}
    
        config.pinned_custom_subfolders = loaded_config.pinned_custom_subfolders or {}
    
        if loaded_config.flicker_guard_enabled == nil then
            config.flicker_guard_enabled = false
        end
   
        legacy_scripts_launcher = loaded_config.scripts_launcher
    else
        SetDefaultConfig()
    end
end
LoadConfig()

if config and config.last_viewed_folder then
    last_viewed_folder = config.last_viewed_folder
end
PROJECTS_DIR = config.last_used_project_location

-- Helpers: resolve roots and scan folders for FX Chains / Track Templates
-- Lightweight path existence check that works for files or directories
local function PathExists(path)
    if not path or path == '' then return false end
    local ok, _, code = os.rename(path, path)
    if ok then return true end
    -- code 13 = permission denied (still exists)
    if code == 13 then return true end
    return false
end

local function ResolveFxChainsRoot()
    if config.use_custom_fxchain_dir and type(config.custom_fxchain_dir) == 'string' and config.custom_fxchain_dir ~= '' then
        return config.custom_fxchain_dir
    end
    return r.GetResourcePath() .. "/FXChains"
end

local function ResolveTrackTemplatesRoot()
    if config.use_custom_template_dir and type(config.custom_template_dir) == 'string' and config.custom_template_dir ~= '' then
        return config.custom_template_dir
    end
    return r.GetResourcePath() .. "/TrackTemplates"
end

local function PathJoin(a, b)
    if not a or a == '' then return b or '' end
    if not b or b == '' then return a end
    if a:sub(-1) == os_separator then return a .. b end
    return a .. os_separator .. b
end

local function BuildTreeFromFS(base_dir, ext)
    local function scan(dir)
        local node = { dir = dir:sub(#base_dir + 2) } -- relative dir name stored in .dir for UI menus
        -- subfolders
        for i = 0, math.huge do
            local sub = r.EnumerateSubdirectories(dir, i)
            if not sub then break end
            local child = scan(PathJoin(dir, sub))
            child.dir = sub
            node[#node + 1] = child
        end
        -- files
        for i = 0, math.huge do
            local file = r.EnumerateFiles(dir, i)
            if not file then break end
            if not ext or file:sub(-#ext):lower() == ext:lower() then
                node[#node + 1] = file:gsub(ext .. "$", "")
            end
        end
        return node
    end
    local root = {}
    -- top-level subdirs
    for i = 0, math.huge do
        local sub = r.EnumerateSubdirectories(base_dir, i)
        if not sub then break end
        local child = scan(PathJoin(base_dir, sub))
        child.dir = sub
        root[#root + 1] = child
    end
    -- top-level files
    for i = 0, math.huge do
        local file = r.EnumerateFiles(base_dir, i)
        if not file then break end
        if not ext or file:sub(-#ext):lower() == ext:lower() then
            root[#root + 1] = file:gsub(ext .. "$", "")
        end
    end
    return root
end

local function GetFxChainsTree()
    local root = ResolveFxChainsRoot()
    return BuildTreeFromFS(root, ".RfxChain"), root
end

local function GetTrackTemplatesTree()
    local root = ResolveTrackTemplatesRoot()
    return BuildTreeFromFS(root, ".RTrackTemplate"), root
end
do
    local function ApplyStartupDedupe()
        if not config.apply_type_priority then return end
        if browser_panel_selected and type(GetFxListForSubgroup) == 'function' then
            local list = GetFxListForSubgroup(browser_panel_selected) or {}
            current_filtered_fx = DedupeByTypePriority(list)
        elseif selected_folder and type(GetPluginsForFolder) == 'function' then
            current_filtered_fx = GetPluginsForFolder(selected_folder) or {}
        end
        if (not screenshot_search_results or #screenshot_search_results == 0) and current_filtered_fx and #current_filtered_fx > 0 then
            screenshot_search_results = {}
            local cap = loaded_items_count or ITEMS_PER_BATCH or 30
            for i = 1, math.min(cap, #current_filtered_fx) do
                screenshot_search_results[#screenshot_search_results+1] = { name = current_filtered_fx[i] }
            end
            if type(SortScreenshotResults) == 'function' then SortScreenshotResults() end
        end
    end
    ApplyStartupDedupe()
end

local scripts_launcher_path = script_path .. "scripts_launcher.json"
local scripts_launcher = {}

function LoadScriptsLauncher()
    local f = io.open(scripts_launcher_path, "r")
    if f then
        local content = f:read("*all"); f:close()
        local ok, data = pcall(function() return json.decode(content) end)
        if ok and type(data) == "table" then scripts_launcher = data end
    elseif legacy_scripts_launcher then
       
        scripts_launcher = legacy_scripts_launcher
        legacy_scripts_launcher = nil
        local mf = io.open(scripts_launcher_path, "w")
        if mf then mf:write(json.encode(scripts_launcher)); mf:close() end
        SaveConfig() 
    end
end

function SaveScriptsLauncher()
    local f = io.open(scripts_launcher_path, "w")
    if f then f:write(json.encode(scripts_launcher)); f:close() end
end

LoadScriptsLauncher()

function ResetConfig()
    config = SetDefaultConfig()
    _G.config = config
    SaveConfig()
end

-- CUSTOM FOLDERS HELPERS
function IsPluginArray(folder_content)
    if type(folder_content) ~= "table" then return false end
    if next(folder_content) == nil then return true end 
    
    for i, item in ipairs(folder_content) do
        if type(item) ~= "string" then return false end
    end
    
    for key, value in pairs(folder_content) do
        if type(key) ~= "number" then return false end
    end
    return true
end

function IsSubfolderStructure(folder_content)
    if type(folder_content) ~= "table" then return false end
    if next(folder_content) == nil then return false end 
    
    for key, value in pairs(folder_content) do
        if type(key) ~= "string" then return false end
        if type(value) ~= "table" then return false end
    end
    return true
end

function CleanPluginName(name)
    if not name or name == '' then return name end
    local original = name
   
    name = name:gsub('^VST3i?:%s*','')
               :gsub('^VSTi:%s*','')
               :gsub('^VST3:%s*','')
               :gsub('^VST:%s*','')
               :gsub('^CLAPi?:%s*','')
               :gsub('^JSFX:%s*','')
               :gsub('^JS:%s*','')
               :gsub('^AU:%s*','')
               :gsub('^LV2:%s*','')
    
    name = name:gsub('%s*%(%d+%s*ch%)$','')
               :gsub('%s*%(%d+in%s*%d+out%)$','')
   
    name = name:gsub('%s+$','')
    return name ~= '' and name or original
end

function RemoveManufacturerSuffix(name)
    if not name or name == '' then return name end
    local base = CleanPluginName(name)
    
    local patterns = { '%s*%(([^()]+)%)%s*$', '%s*%[([^%[%]]+)%]%s*$', '%s*%{([^{}]+)%}%s*$' }
    for _, pat in ipairs(patterns) do
        local before, manu = base:match('^(.*)'..pat)
        if before and manu then
            local trimmed_before = before:gsub('%s+$','')
            
            if #manu:gsub('%s','') >= 3 and not manu:match('^vst3?i?$') then
                base = trimmed_before
                break
            end
        end
    end
    return base
end

function GetDisplayPluginName(raw_name)
    if not raw_name then return raw_name end
    local name = raw_name
    if config.clean_plugin_names then
        name = CleanPluginName(name)
    end
    if config.remove_manufacturer_names then
        name = RemoveManufacturerSuffix(name)
    end
    return name
end

function StripX86Markers(name)
    if not name then return '' end
    
    name = name
        :gsub('%s*[%(%[]x86[^%]%)]*[%]%)]','')    
        :gsub('[%s%-]+x86[%s%-]*bridged',' ')      
        :gsub('[%s%-]x86[%s%-]',' ')               
        :gsub('x86%s*:%s*','')                     
    return name
end

function NormalizePluginNameForMatch(name)
    if not name then return '' end
    
    -- Check cache first
    local cached = normalized_name_cache[name]
    if cached then return cached end
    
    -- Perform normalization
    local result = name:lower()
    result = result:gsub('^vst3i?:%s*',''):gsub('^vsti?:%s*',''):gsub('^vst3:%s*',''):gsub('^vst:%s*',''):gsub('^js:%s*',''):gsub('^clapi?:%s*',''):gsub('^clap:%s*',''):gsub('^lv2:%s*','')
    result = result:gsub('%s*%(%d+%s*ch%)$',''):gsub('%s*%(%d+in%s*%d+out%)$','')
    result = StripX86Markers(result)
    result = CleanPluginName(result)
    result = result:gsub('%s+',' ')
    result = result:gsub('[^%w]+','')
    
    -- Cache the result
    normalized_name_cache[name] = result
    return result
end

function GetPluginType(name)
    if not name or name == '' then return 'OTHER' end
    
    -- Check cache first
    local cached = plugin_type_cache[name]
    if cached then return cached end
    
    -- Determine type
    local result = 'OTHER'
    if name:match('^VST3i?:') then 
        result = 'VST3' 
    elseif name:match('^VSTi?:') then 
        result = 'VST' 
    elseif name:match('^CLAPi?:') then 
        result = 'CLAP' 
    elseif name:match('^JSFX:') or name:match('^JS:') then 
        result = 'JS' 
    elseif name:match('^AU:') or name:match('^AUi:') then 
        result = 'AU' 
    elseif name:match('^LV2i?:') then 
        result = 'LV2' 
    end
    
    -- Cache the result
    plugin_type_cache[name] = result
    return result
end

-- Determine if a plugin is an instrument (VSTi/VST3i/CLAPi/AUi/LV2i)
function IsInstrumentPlugin(name)
    if not name or name == '' then return false end
    return name:match('^VSTi:')
        or name:match('^VST3i:')
        or name:match('^CLAPi:')
        or name:match('^AUi:')
        or name:match('^LV2i:')
        or false
end

-- Add FX with optional instrument-on-top behavior
function AddFXToTrack(track, plugin_name)
    if not track or not plugin_name or plugin_name == '' then return -1 end
    local dest_index = r.TrackFX_GetCount(track)
    local fx_index = r.TrackFX_AddByName(track, plugin_name, false, -1000 - dest_index)
    if fx_index and fx_index >= 0 and config and config.add_instruments_on_top and IsInstrumentPlugin(plugin_name) then
        r.TrackFX_CopyToTrack(track, fx_index, track, 0, true)
        fx_index = 0
    end
    return fx_index or -1
end

function BuildTypePriorityIndex()
    -- Use cached version if available and config hasn't changed
    if type_priority_cache and config._priority_cache_version == config._current_version then
        return type_priority_cache
    end
    
    local idx = {}
    if type(config.plugin_type_priority) == 'table' then
        for i, t in ipairs(config.plugin_type_priority) do
            idx[t] = i
        end
    end
    
    -- Cache the result
    type_priority_cache = idx
    config._priority_cache_version = config._current_version or 1
    return idx
end

DedupeByTypePriority = function(list)
    if not config.apply_type_priority or type(list) ~= 'table' or #list == 0 then 
        return list 
    end
    
    -- Early exit for small lists
    if #list <= 1 then return list end
    
    local priority = BuildTypePriorityIndex()
    local best_by_key = {}
    local order = {}
    local seen_keys = {}
    local has_duplicates = false
    
    for i = 1, #list do
        local fx = list[i]
        local key = NormalizePluginNameForMatch(fx)
        
        -- Skip empty keys
        if key ~= '' then
            if not seen_keys[key] then
                -- First occurrence of this key
                local t = GetPluginType(fx)
                local p = priority[t] or math.huge
                best_by_key[key] = {name = fx, prio = p, type = t}
                order[#order + 1] = key
                seen_keys[key] = true
            else
                -- We found a duplicate
                has_duplicates = true
                local t = GetPluginType(fx)
                local p = priority[t] or math.huge
                local cur = best_by_key[key]
                if p < cur.prio then
                    best_by_key[key] = {name = fx, prio = p, type = t}
                end
            end
        end
    end
    
    -- If no duplicates were found, return original list
    if not has_duplicates and #order == #list then
        return list
    end
    
    -- Build result list
    local out = {}
    for i = 1, #order do
        local key = order[i]
        out[#out + 1] = best_by_key[key].name
    end
    
    return out
end

local screenshot_index_norm = nil
function BuildScreenshotIndex(force)
    if screenshot_index_norm and not force then return end
    screenshot_index_norm = {}
    local i = 0
    while true do
        local fname = r.EnumerateFiles(screenshot_path, i)
        if not fname then break end
        local base = fname:match('(.+)%.png$') or fname:match('(.+)%.jpg$') or fname:match('(.+)%.jpeg$')
        if base then
            local norm = NormalizePluginNameForMatch(base)
            screenshot_index_norm[norm] = true
        end
        i = i + 1
    end
end

-- Pinned plugins helpers
function EnsurePinnedPluginsList()
    if type(config.pinned_plugins) ~= 'table' then config.pinned_plugins = {} end
end

function IsPluginPinned(name)
    if not name or name == '' then return false end
    if pinned_set[name] then return true end
    local key = (type(NormalizePluginNameForMatch) == 'function') and NormalizePluginNameForMatch(name) or ''
    return key ~= '' and pinned_norm_set[key] == true
end

function PinPlugin(name)
    if not name or name == '' then return end
    EnsurePinnedPluginsList()
    if not pinned_set[name] then
        pinned_set[name] = true
        table.insert(config.pinned_plugins, name)
        -- keep normalized pins in sync
        if type(NormalizePluginNameForMatch) == 'function' then
            local k = NormalizePluginNameForMatch(name)
            if k ~= '' then pinned_norm_set[k] = true end
        end
    SaveConfig()
    if RefreshCurrentScreenshotView then RefreshCurrentScreenshotView() end
    end
end

function UnpinPlugin(name)
    if not name or name == '' then return end
    if pinned_set[name] then
        pinned_set[name] = nil
        if type(config.pinned_plugins) == 'table' then
            for i = #config.pinned_plugins, 1, -1 do
                if config.pinned_plugins[i] == name then
                    table.remove(config.pinned_plugins, i)
                end
            end
        end
        -- keep normalized pins in sync
        if type(NormalizePluginNameForMatch) == 'function' then
            local k = NormalizePluginNameForMatch(name)
            if k ~= '' then pinned_norm_set[k] = nil end
        end
    SaveConfig()
    if RefreshCurrentScreenshotView then RefreshCurrentScreenshotView() end
    end
end

function HasScreenshot(plugin_name)
    BuildScreenshotIndex()
    local norm = NormalizePluginNameForMatch(plugin_name)
    if screenshot_index_norm[norm] then return true end
    
    local stripped_x86 = StripX86Markers(plugin_name)
    local variants = {
        plugin_name,
        CleanPluginName(plugin_name),
        (plugin_name or ''):gsub('[^%w%s-]','_'),
        CleanPluginName(plugin_name):gsub('[^%w%s-]','_'),
        stripped_x86,
        CleanPluginName(stripped_x86),
        StripX86Markers(CleanPluginName(plugin_name))
    }
    for _, base in ipairs(variants) do
        if base and base ~= '' then
            local png = screenshot_path .. base .. '.png'
            local jpg = screenshot_path .. base .. '.jpg'
            if r.file_exists(png) or r.file_exists(jpg) then return true end
        end
    end
    return false
end

function SplitPluginsByScreenshot(plugin_list)
    local with_shot, missing = {}, {}
    if not plugin_list then return with_shot, missing end
    for _, name in ipairs(plugin_list) do
        if config.respect_search_exclusions_in_screenshots and config.excluded_plugins and config.excluded_plugins[name] then
            goto continue_plugin
        end
        if name == "--Favorites End--" or name == "--Pinned End--" then
            table.insert(with_shot, name) 
        else
            if HasScreenshot(name) then
                table.insert(with_shot, name)
            else
                table.insert(missing, name)
            end
        end
        ::continue_plugin::
    end
    return with_shot, missing
end

-- FW
local GetStarsString

function RenderMissingList(missing)
    if not (config.show_missing_list ~= false) then return end 
    if missing and #missing > 0 then
        r.ImGui_Dummy(ctx, 0, 10)
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, string.format("Missing Screenshots (%d)", #missing))
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 2, 2)
            for i, name in ipairs(missing) do
                local display_name = GetDisplayPluginName(name)
                local stars = GetStarsString(name)
                local activated = r.ImGui_Selectable(ctx, display_name .. (stars ~= "" and "  " .. stars or "") .. "##missing_" .. i, false)
                local do_add = false
                if config.add_fx_with_double_click then
                    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        do_add = true
                    end
                else
                    if activated then do_add = true end
                end
                if do_add then
                    local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                    if target_track then
                        AddFXToTrack(target_track, name)
                        LAST_USED_FX = name
                        if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                    end
                end
                ShowPluginContextMenu(name, "missing_ctx_" .. i)
        end
        r.ImGui_PopStyleVar(ctx)
    end
end

local top_screenshot_spacing_applied = false
function ApplyTopScreenshotSpacing()
    if not top_screenshot_spacing_applied then
        r.ImGui_Dummy(ctx, 0, 6) 
        top_screenshot_spacing_applied = true
    end
end

function GetPluginsFromCustomFolder(folder_path)
    local parts = {}
    for part in folder_path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    
    local current = config.custom_folders
    for _, part in ipairs(parts) do
        if current[part] then
            current = current[part]
        else
            return {}
        end
    end
    
    if IsPluginArray(current) then
        return current
    else
        return {}
    end
end

function CreateNestedFolder(folder_path, is_subfolder_of)
    local parts = {}
    if is_subfolder_of then
        for part in is_subfolder_of:gmatch("[^/]+") do
            table.insert(parts, part)
        end
    end
    for part in folder_path:gmatch("[^/]+") do
        table.insert(parts, part)
    end
    
    local current = config.custom_folders
    for i, part in ipairs(parts) do
        if i == #parts then
           
            current[part] = current[part] or {}
        else
           
            current[part] = current[part] or {}
            current = current[part]
        end
    end
end

function SaveCustomFolders()
    
    local function convertForJSON(folders)
        local result = {}
        for folder_name, folder_content in pairs(folders) do
            if IsPluginArray(folder_content) then
                
                result[folder_name] = {
                    _type = "plugins",
                    plugins = folder_content
                }
            elseif IsSubfolderStructure(folder_content) then
            
                result[folder_name] = {
                    _type = "folder",
                    subfolders = convertForJSON(folder_content)
                }
            end
        end
        return result
    end
    
    local json_data = convertForJSON(config.custom_folders)
    
    local success, json_string = pcall(json.encode, json_data)
    
    if success then
        local file = io.open(script_path .. "custom_folders.json", "w")
        if file then
            file:write(json_string)
            file:close()
        else
            r.ShowConsoleMsg("Error: Could not open custom_folders.json for writing\n")
        end
    else
        r.ShowConsoleMsg("Error: Could not encode custom folders to JSON: " .. tostring(json_string) .. "\n")
    end
end

function LoadCustomFolders()
    local file = io.open(script_path .. "custom_folders.json", "r")
    if file then
        local content = file:read("*all")
        file:close()
        
        if not content or content == "" or content:match("^%s*$") then
           
            config.custom_folders = {}
            return
        end
        
        local success, loaded_data = pcall(json.decode, content)
        
        if success and loaded_data and type(loaded_data) == "table" then
           
            local function convertFromJSON(data)
                local result = {}
                for folder_name, folder_data in pairs(data) do
                    if type(folder_data) == "table" then
                        if folder_data._type == "plugins" then
                            
                            result[folder_name] = folder_data.plugins or {}
                        elseif folder_data._type == "folder" then
                            
                            result[folder_name] = convertFromJSON(folder_data.subfolders or {})
                        else
                            
                            if folder_data[1] and type(folder_data[1]) == "string" then
                               
                                result[folder_name] = folder_data
                            else
                                
                                result[folder_name] = convertFromJSON(folder_data)
                            end
                        end
                    end
                end
                return result
            end
            
            config.custom_folders = convertFromJSON(loaded_data)
        else
            
            r.ShowConsoleMsg("Warning: Could not parse custom_folders.json, initializing with empty folders\n")
            config.custom_folders = {}
            
            local backup_path = script_path .. "custom_folders_backup.json"
            local backup_file = io.open(backup_path, "w")
            if backup_file then
                backup_file:write(content)
                backup_file:close()
                r.ShowConsoleMsg("Backup of corrupt file saved as: " .. backup_path .. "\n")
            end
        end
    else
        config.custom_folders = {}
    end
end

LoadCustomFolders()

-------------------------------------------------------------
-- RATING
function LoadPluginRatings()
    local file = io.open(plugin_ratings_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        local ok, data = pcall(json.decode, content)
        if ok and type(data) == "table" then
            plugin_ratings = data
        else
            plugin_ratings = {}
        end
    else
        plugin_ratings = {}
    end
end

function SavePluginRatings()
    local file = io.open(plugin_ratings_path, "w")
    if file then
        file:write(json.encode(plugin_ratings))
        file:close()
    end
end

LoadPluginRatings()

function ShowPluginRatingUI(plugin_name)
    local rating = plugin_ratings[plugin_name] or 0
    local changed = false
    for i = 1, 5 do
        local star_label = (i <= rating and "★" or "☆") .. "##" .. plugin_name .. "_star_" .. i
        if r.ImGui_Button(ctx, star_label) then
            plugin_ratings[plugin_name] = i
            SavePluginRatings()
            changed = true
        end
        if i < 5 then r.ImGui_SameLine(ctx) end
    end
    if rating > 0 then
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Clear##" .. plugin_name) then
            plugin_ratings[plugin_name] = nil
            SavePluginRatings()
            changed = true
        end
    end
    return changed
end

function DrawPluginWithRating(plugin_name)
    local rating = plugin_ratings[plugin_name] or 0
    local stars = ""
    for i = 1, 5 do
        stars = stars .. (i <= rating and "★" or "☆")
    end
    r.ImGui_Text(ctx, plugin_name .. "  " .. stars)
end

GetStarsString = function(plugin_name)
    local rating = plugin_ratings[plugin_name] or 0
    local stars = ""
    for i = 1, 5 do
        stars = stars .. (i <= rating and "★" or "☆")
    end
    return stars
end

-- voor lijsten
function SortPluginsByRating(plugins)
    table.sort(plugins, function(a, b)
        local ra = plugin_ratings[a] or 0
        local rb = plugin_ratings[b] or 0
        if ra == rb then
            return a:lower() < b:lower()
        else
            return ra > rb
        end
    end)
end

-- voor tabellen
function SortPluginTableByRating(tbl)
    table.sort(tbl, function(a, b)
        local ra = plugin_ratings[a.name] or 0
        local rb = plugin_ratings[b.name] or 0
        if ra == rb then
            return a.name:lower() < b.name:lower()
        else
            return ra > rb
        end
    end)
end
--------------------------------------------------------------
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

function DrawDragOverlay()
    if dragging_fx_name then
        local imx, imy = r.ImGui_GetMousePos(ctx)
        local sx, sy = r.GetMousePosition()
        local t = select(1, r.GetTrackFromPoint(sx, sy))
        local track_name = "(geen track)"
        if t then
            local ok; ok, track_name = r.GetSetMediaTrackInfo_String(t, 'P_NAME', '', false)
            if not ok or track_name == '' then track_name = 'Track' end
        end
        local shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
        local vp = r.ImGui_GetMainViewport(ctx)
        local vp_x, vp_y = r.ImGui_Viewport_GetPos(vp)
        local rel_x = imx - vp_x + 18
        local rel_y = imy - vp_y + 18
        r.ImGui_SetNextWindowBgAlpha(ctx, 0.38)
        r.ImGui_SetNextWindowPos(ctx, rel_x, rel_y, r.ImGui_Cond_Always())
        local flags = r.ImGui_WindowFlags_NoDecoration() | r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_NoSavedSettings() | r.ImGui_WindowFlags_NoInputs()
        if r.ImGui_Begin(ctx, '##drag_overlay', true, flags) then
            r.ImGui_Text(ctx, '➡ ' .. dragging_fx_name)
            if shift then
                r.ImGui_Text(ctx, 'Add to Item (SHIFT)')
            else
                r.ImGui_Text(ctx, 'Track: ' .. track_name)
            end
            r.ImGui_Text(ctx, 'Release to add')
        end
        r.ImGui_End(ctx)
    end
end

function UpdateFonts()
   
    if r.ImGui_ValidatePtr(NormalFont, 'ImGui_Resource*') then
        r.ImGui_Detach(ctx, NormalFont)
    end
    if r.ImGui_ValidatePtr(LargeFont, 'ImGui_Resource*') then
        r.ImGui_Detach(ctx, LargeFont)
    end
    if r.ImGui_ValidatePtr(TinyFont, 'ImGui_Resource*') then
        r.ImGui_Detach(ctx, TinyFont)
    end

    
    NormalFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 11)
    TinyFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 9)
    LargeFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 15)

    r.ImGui_Attach(ctx, NormalFont)
    r.ImGui_Attach(ctx, TinyFont)
    r.ImGui_Attach(ctx, LargeFont)
end

NormalFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 11)
TinyFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 9)
LargeFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 15)
IconFont = r.ImGui_CreateFontFromFile(script_path .. 'Icons-Regular.otf', 0)

r.ImGui_Attach(ctx, NormalFont)
r.ImGui_Attach(ctx, LargeFont)
r.ImGui_Attach(ctx, TinyFont)
r.ImGui_Attach(ctx, IconFont)

---------------------------------------------------------------------
function EnsureFileExists(filepath)
    local file = io.open(filepath, "r")
    if not file then
        file = io.open(filepath, "w")
        file:close()
    else
        file:close()
    end
end


function load_projects_info()
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


function get_all_projects()
    local projects = {}
    local current_project_dir = config.last_used_project_location or PROJECTS_DIR
    local stack = {{path = current_project_dir, depth = 0}}
   
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
function open_project(project_path)
    r.Main_openProject(project_path)
end
function save_projects_info(projects)
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

function LoadProjects()
    projects = {}  
    filtered_projects = {} 
    projects = get_all_projects()  
    filtered_projects = projects
    save_projects_info(projects)
end

load_projects_info()
if #project_locations == 0 then
    table.insert(project_locations, PROJECTS_DIR)
end

function SaveFavorites()
    local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
    local file = io.open(script_path .. "favorite_plugins.txt", "w")
    if file then
        for _, fav in ipairs(favorite_plugins) do
            file:write(fav .. "\n")
        end
        file:close()
    end
end

function LoadFavorites()
    local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
    local file = io.open(script_path .. "favorite_plugins.txt", "r")
    if file then
        for line in file:lines() do
            table.insert(favorite_plugins, line)
            favorite_set[line] = true
        end
        file:close()
    end
end
LoadFavorites()


function SaveTags()
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

function LoadTags()
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
function ClearScreenshotCache(periodic_cleanup)
    local current_time = r.time_precise()
    
    if periodic_cleanup then
        local to_remove = {}
        for key, last_used in pairs(texture_last_used) do
            if current_time - last_used > 300 then 
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
function initFoldersCategory()
    for i = 1, #CAT_TEST do
        if CAT_TEST[i].name == "FOLDERS" then
            folders_category = CAT_TEST[i].list
            break
        end
    end
end
initFoldersCategory()

function UpdateLastViewedFolder(new_folder)
    if not new_folder or new_folder == "" then return end
    if 
       new_folder ~= "Projects" and 
        new_folder ~= "Actions" and 
        new_folder ~= "Sends/Receives" then
        last_viewed_folder = new_folder 
       
        config.last_viewed_folder = new_folder
        SaveConfig()
    end
end

function IsNonFoldersSubgroup(name)
    if not name or not CAT_TEST then return false end
    for i = 1, #CAT_TEST do
        local cat = CAT_TEST[i]
        if cat and (cat.name == "ALL PLUGINS" or cat.name == "DEVELOPER" or cat.name == "CATEGORY") then
            for j = 1, #cat.list do
                if cat.list[j] and cat.list[j].name == name then return true end
            end
        end
    end
    return false
end

GetFxListForSubgroup = function(name)
    if not name or not CAT_TEST then return nil end
    for i = 1, #CAT_TEST do
        local cat = CAT_TEST[i]
        if cat and (cat.name == "ALL PLUGINS" or cat.name == "DEVELOPER" or cat.name == "CATEGORY") then
            for j = 1, #cat.list do
                local subgroup = cat.list[j]
                if subgroup and subgroup.name == name then
                    return subgroup.fx
                end
            end
        end
    end
    return nil
end

function IsPluginVisible(plugin_name)
    return config.plugin_visibility[plugin_name] ~= false
end

function GetTrackName(track)
    if not track then return "No Track Selected" end
    if track == r.GetMasterTrack(0) then return "Master Track" end
    local _, name = r.GetTrackName(track)
    return name
end

function GetCurrentProjectFX()
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
                    track_color = track_color,
                    fx_index = j,  
                    unique_id = track_number .. "_" .. j
                })
            end
        end
    end
    return fx_list
end

function GetCurrentTrackFX()
    local fx_list = {}
    if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") then
        local fx_count = reaper.TrackFX_GetCount(TRACK)
        for j = 0, fx_count - 1 do
            local retval, fx_name = reaper.TrackFX_GetFXName(TRACK, j, "")
            if retval then
                table.insert(fx_list, {
                    fx_name = fx_name,  
                    fx_index = j,  
                    track_number = r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER")
                })
            end
        end
    end
    return fx_list
end


local search_filter = ""
local filtered_plugins = {}
function InitializeFilteredPlugins()
    filtered_plugins = {}
    if not config then return end
    config.plugin_visibility = config.plugin_visibility or {}
    config.excluded_plugins = config.excluded_plugins or {}

    if type(BuildScreenshotIndex) == 'function' then
        pcall(BuildScreenshotIndex) -- geen force, normale lazy build
    end

    for _, plugin_name in ipairs(PLUGIN_LIST or {}) do
        if config.plugin_visibility[plugin_name] == nil then
            config.plugin_visibility[plugin_name] = true
        end

        local has_shot = false
        if config.show_missing_screenshots_only then
            if type(HasScreenshot) == 'function' then
                local ok, res = pcall(HasScreenshot, plugin_name)
                if ok then has_shot = res end
            end
            if has_shot then goto continue end
        end

        table.insert(filtered_plugins, {
            name       = plugin_name,
            visible    = config.plugin_visibility[plugin_name] ~= false,
            searchable = not config.excluded_plugins[plugin_name]
        })
        ::continue::
    end

    table.sort(filtered_plugins, function(a, b) return a.name:lower() < b.name:lower() end)
end

if config.show_missing_screenshots_only then
    InitializeFilteredPlugins()
end

local CHECKBOX_WIDTH = 15
local last_clicked_plugin_index = nil
local last_clicked_column = nil 
function ShowPluginManagerTab()
    
    if #filtered_plugins == 0 or type(filtered_plugins[1]) ~= 'table' or not filtered_plugins[1].name then
        InitializeFilteredPlugins()
    end
    if r.ImGui_Button(ctx, "Update Plugin List", 110) then
        FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = MakeFXFiles()
    end
    r.ImGui_SameLine(ctx)

    local toggle_label = config.show_missing_screenshots_only and "show all" or "missing screenshots"
    if r.ImGui_Button(ctx, toggle_label, 120, 20) then
        config.show_missing_screenshots_only = not config.show_missing_screenshots_only

        filtered_plugins = {}

        BuildScreenshotIndex(true)
        for _, plugin in ipairs(PLUGIN_LIST) do
            local include = (not config.show_missing_screenshots_only) or (config.show_missing_screenshots_only and not HasScreenshot(plugin))
            if include and (search_filter == '' or string.find(string.lower(plugin), string.lower(search_filter))) then
                table.insert(filtered_plugins, {
                    name = plugin,
                    visible = config.plugin_visibility[plugin] ~= false,
                    searchable = not config.excluded_plugins[plugin]
                })
            end
        end
        table.sort(filtered_plugins, function(a,b) return a.name:lower() < b.name:lower() end)
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_PushItemWidth(ctx, 120)
            config.last_viewed_folder = new_folder
    r.ImGui_PopItemWidth(ctx)
    if changed then
        search_filter = new_search_filter
        filtered_plugins = {}
        BuildScreenshotIndex(true)
        for _, plugin in ipairs(PLUGIN_LIST) do
            if config.show_missing_screenshots_only and HasScreenshot(plugin) then goto continue_search end
            if search_filter == "" or string.find(string.lower(plugin), string.lower(search_filter)) then
                table.insert(filtered_plugins, {
                    name = plugin,
                    visible = config.plugin_visibility[plugin] ~= false,
                    searchable = not config.excluded_plugins[plugin]
                })
            end
            ::continue_search::
        end
        table.sort(filtered_plugins, function(a, b) return a.name:lower() < b.name:lower() end)
    end
    
    r.ImGui_Text(ctx, string.format(" | Total plugins: %d", #PLUGIN_LIST))
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, string.format(" | Shown plugins: %d", #filtered_plugins))
    if config.show_missing_screenshots_only then
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, START_SELECTED and "STOP" or "Make Shots (Selected)") then
            if START_SELECTED then
                STOP_SELECTED = true
            else
                StartSelectedMissingScreenshots()
            end
        end
    end
    local window_width = r.ImGui_GetWindowWidth(ctx)
        local column1_width = 45  -- Voor "Bulk" checkbox
        local column2_width = 45  -- Voor "Search" checkbox
        local column3_width = window_width - column1_width - column2_width - 20  -- Voor plugin naam

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
    local plugin_list_open = r.ImGui_BeginChild(ctx, "PluginList", 0, -25)
    if plugin_list_open then
        for i, plugin in ipairs(filtered_plugins) do
         
            if type(plugin) ~= 'table' or not plugin.name then
                local pname = (type(plugin) == 'string') and plugin or tostring(plugin or ("plugin_"..i))
                filtered_plugins[i] = {
                    name = pname,
                    visible = config.plugin_visibility[pname] ~= false,
                    searchable = not config.excluded_plugins[pname]
                }
                plugin = filtered_plugins[i]
            end
            r.ImGui_SetCursorPosX(ctx, (column1_width - 35) / 2)
        
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
            local disp = GetDisplayPluginName(plugin.name)
            r.ImGui_Text(ctx, disp)
        end
    end
    r.ImGui_EndChild(ctx)
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
    if not folder_name or folder_name == '' then return {} end

    if folder_name == "Favorites" then
        return DedupeByTypePriority(favorite_plugins or {})
    end
    if folder_name == "Current Track FX" then
        local list = {}
        local track_fx = GetCurrentTrackFX() or {}
        for _, fx in ipairs(track_fx) do
            table.insert(list, fx.fx_name)
        end
    return DedupeByTypePriority(list)
    end
    if folder_name == "Current Project FX" then
        local list = {}
        local proj_fx = GetCurrentProjectFX() or {}
        for _, fx in ipairs(proj_fx) do
            table.insert(list, fx.fx_name)
        end
    return DedupeByTypePriority(list)
    end

    if folder_name:find("/") then
    return DedupeByTypePriority(GetPluginsFromCustomFolder(folder_name))
    elseif config.custom_folders and config.custom_folders[folder_name] then
        local folder_content = config.custom_folders[folder_name]
    if IsPluginArray(folder_content) then return DedupeByTypePriority(folder_content) else return {} end
    end

    if folders_category and #folders_category > 0 then
        for i = 1, #folders_category do
            if folders_category[i].name == folder_name then
                return DedupeByTypePriority(folders_category[i].fx or {})
            end
        end
    else
        for i = 1, #CAT_TEST do
            if CAT_TEST[i].name == "FOLDERS" then
                for j = 1, #CAT_TEST[i].list do
                    if CAT_TEST[i].list[j].name == folder_name then
                        return DedupeByTypePriority(CAT_TEST[i].list[j].fx or {})
                    end
                end
                break
            end
        end
    end
    return {}
end

function OpenScreenshotsFolder()
    local os_name = reaper.GetOS()
    if os_name:match("Win") then
        os.execute('start "" "' .. screenshot_path .. '"')
    elseif os_name:match("OSX") then
        os.execute('open "' .. screenshot_path .. '"')
    else
        reaper.ShowMessageBox("Unsupported OS", "Error", 0)
    end
end

function ShowConfigWindow()
    local function NewSection(title)
        r.ImGui_Spacing(ctx)
        r.ImGui_PushFont(ctx, NormalFont, 11)
        r.ImGui_Text(ctx, title)
        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            r.ImGui_PopFont(ctx)
        end

        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
    end
    local config_open = true
    local window_width = 480
    local window_height = 780

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
        r.ImGui_PushFont(ctx, LargeFont, 15)
        r.ImGui_Text(ctx, "TK FX BROWSER SETTINGS  v" .. GetScriptVersion())
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
            NewSection("OVERALL VIEW OPTIONS:")
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
            r.ImGui_SetCursorPosX(ctx, column1_width)
            changed, new_value = r.ImGui_Checkbox(ctx, "Scripts", config.show_scripts)
            if changed then config.show_scripts = new_value end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.show_custom_folders = r.ImGui_Checkbox(ctx, "Custom Folders", config.show_custom_folders)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.show_tooltips = r.ImGui_Checkbox(ctx, "Show Tooltips", config.show_tooltips)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            _, config.show_notes_widget = r.ImGui_Checkbox(ctx, "Show Notes", config.show_notes_widget)

            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.add_instruments_on_top = r.ImGui_Checkbox(ctx, "Add instruments at top", config.add_instruments_on_top)
            r.ImGui_Dummy(ctx, 0, 5)

           NewSection("LOCATIONS:")
            -- FX Chains location
            r.ImGui_SetCursorPosX(ctx, column1_width)
            local changed_fx_use, use_fx_custom = r.ImGui_Checkbox(ctx, "custom FXChain folder", config.use_custom_fxchain_dir)
            if changed_fx_use then
                config.use_custom_fxchain_dir = use_fx_custom; SaveConfig()
            end
            r.ImGui_SameLine(ctx)
            -- r.ImGui_SetCursorPosX(ctx, column3_width)
            r.ImGui_PushItemWidth(ctx, 180)
            local fx_dir = config.custom_fxchain_dir or ""
            local changed_fx_dir, new_fx_dir = r.ImGui_InputText(ctx, "##fxchain_dir", fx_dir)
            if changed_fx_dir then config.custom_fxchain_dir = new_fx_dir end
            r.ImGui_PopItemWidth(ctx)
            -- Keep buttons on the same line as input
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse…##fxchain") then
                local rv, path = r.JS_Dialog_BrowseForFolder("Select FX Chains folder", ResolveFxChainsRoot())
                if rv == 1 and path and path ~= '' then
                    config.custom_fxchain_dir = path; SaveConfig()
                end
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Reset##fxchain_reset") then
                config.use_custom_fxchain_dir = false
                config.custom_fxchain_dir = ""
                SaveConfig()
            end
            if config.use_custom_fxchain_dir and (not config.custom_fxchain_dir or config.custom_fxchain_dir == '') then
                r.ImGui_TextColored(ctx, 0xFF5A5AFF, "Please set a valid FX Chains folder")
            end
            do
                local fx_root = ResolveFxChainsRoot()
                local exists = PathExists(fx_root)
                local color = exists and 0x55CC55FF or 0xFF5A5AFF
                r.ImGui_SetCursorPosX(ctx, column1_width)
                r.ImGui_Text(ctx, "FX Chains path:")
                r.ImGui_SameLine(ctx)
                r.ImGui_TextColored(ctx, color, exists and "OK" or "Not found")
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, fx_root)
            end

            -- Track Templates location
            r.ImGui_SetCursorPosX(ctx, column1_width)
            local changed_tt_use, use_tt_custom = r.ImGui_Checkbox(ctx, "custom TT Folder", config.use_custom_template_dir)
            if changed_tt_use then
                config.use_custom_template_dir = use_tt_custom; SaveConfig()
            end
            r.ImGui_SameLine(ctx)
            -- r.ImGui_SetCursorPosX(ctx, column3_width)
            r.ImGui_PushItemWidth(ctx, 180)
            local tt_dir = config.custom_template_dir or ""
            local changed_tt_dir, new_tt_dir = r.ImGui_InputText(ctx, "##templ_dir", tt_dir)
            if changed_tt_dir then config.custom_template_dir = new_tt_dir end
            r.ImGui_PopItemWidth(ctx)
            -- Keep buttons on the same line as input
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse…##templ") then
                local rv, path = r.JS_Dialog_BrowseForFolder("Select Track Templates folder", ResolveTrackTemplatesRoot())
                if rv == 1 and path and path ~= '' then
                    config.custom_template_dir = path; SaveConfig()
                end
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Reset##templ_reset") then
                config.use_custom_template_dir = false
                config.custom_template_dir = ""
                SaveConfig()
            end
            if config.use_custom_template_dir and (not config.custom_template_dir or config.custom_template_dir == '') then
                r.ImGui_TextColored(ctx, 0xFF5A5AFF, "Please set a valid Track Templates folder")
            end
            do
                local tt_root = ResolveTrackTemplatesRoot()
                local exists = PathExists(tt_root)
                local color = exists and 0x55CC55FF or 0xFF5A5AFF
                r.ImGui_SetCursorPosX(ctx, column1_width)
                r.ImGui_Text(ctx, "Track Templates path:")
                r.ImGui_SameLine(ctx)
                r.ImGui_TextColored(ctx, color, exists and "OK" or "Not found")
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, tt_root)
            end
            

             r.ImGui_Dummy(ctx, 0, 8)

            NewSection("MAIN WINDOW OPTIONS:")
            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.show_name_in_main_window = r.ImGui_Checkbox(ctx, "Show Plugin Names", config.show_name_in_main_window)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.hideTopButtons = r.ImGui_Checkbox(ctx, "No Top Buttons", config.hideTopButtons)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            _, config.hideBottomButtons = r.ImGui_Checkbox(ctx, "No Bottom Buttons", config.hideBottomButtons)
                        r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.show_screenshot_in_search = r.ImGui_Checkbox(ctx, "Show screenshots in Search", config.show_screenshot_in_search)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.show_tags = r.ImGui_Checkbox(ctx, "Show Tags", config.show_tags)
             r.ImGui_SetCursorPosX(ctx, column1_width)
             _, config.hideMeter = r.ImGui_Checkbox(ctx, "Hide Meter", config.hideMeter)
            
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.hideVolumeSlider = r.ImGui_Checkbox(ctx, "Hide Volume Slider", config.hideVolumeSlider)
            r.ImGui_SameLine(ctx)
            
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.hide_default_titlebar_menu_items = r.ImGui_Checkbox(ctx, "Hide Default Titlebar Menu Items", config.hide_default_titlebar_menu_items)

            
            
            r.ImGui_Dummy(ctx, 0, 5)
           
 
            NewSection("SCREENSHOT WINDOW:")
            r.ImGui_SetCursorPosX(ctx, column1_width)
            local changed, new_value = r.ImGui_Checkbox(ctx, "Show Window", config.show_screenshot_window)
            if changed then
                config.show_screenshot_window = new_value
                RequestClearScreenshotCache()
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
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
            r.ImGui_SetCursorPosX(ctx, column3_width)
            local dock_side_changed, new_dock_side = r.ImGui_Checkbox(ctx, "Dock Left", config.dock_screenshot_left)
            if dock_side_changed then
                local main_dock_id = r.ImGui_GetWindowDockID(ctx)
                if main_dock_id == 0 then
                    config.dock_screenshot_left = new_dock_side
                    config.show_screenshot_window = true
                end
                SaveConfig()
            end  
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            local single_selected = not config.add_fx_with_double_click
            if r.ImGui_RadioButton(ctx, "Single Click##AddFXMode", single_selected) then
                config.add_fx_with_double_click = false
                SaveConfig()
            end
            if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Choose whether adding a plugin requires a single or double click on its screenshot.")
            end

            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.show_name_in_screenshot_window = r.ImGui_Checkbox(ctx, "Show Names", config.show_name_in_screenshot_window)
            r.ImGui_SameLine(ctx)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.clean_plugin_names = r.ImGui_Checkbox(ctx, "Clean Plugin Names", config.clean_plugin_names)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.remove_manufacturer_names = r.ImGui_Checkbox(ctx, "Hide Developer", config.remove_manufacturer_names)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            if r.ImGui_RadioButton(ctx, "Double Click##AddFXMode", config.add_fx_with_double_click) then
                config.add_fx_with_double_click = true
                SaveConfig()
            end
             if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Choose whether adding a plugin requires a single or double click.")
            end
            -- r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column1_width)
            local fg_changed, fg_val = r.ImGui_Checkbox(ctx, "Flicker Guard", config.flicker_guard_enabled)
            if fg_changed then
                config.flicker_guard_enabled = fg_val
                RequestClearScreenshotCache()
                SaveConfig()
            end
            if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Reduces flicker by clearing/rebuilding caches only on real state changes and by debouncing typing.")
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            _, config.show_pinned_on_top = r.ImGui_Checkbox(ctx, "Pinned On Top", config.show_pinned_on_top)
            r.ImGui_SameLine(ctx)
             r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.show_favorites_on_top = r.ImGui_Checkbox(ctx, "Favorites On Top", config.show_favorites_on_top)



            --r.ImGui_Dummy(ctx, 0, 5)
            r.ImGui_SetCursorPosX(ctx, column1_width)
            local rses_changed, rses_val = r.ImGui_Checkbox(ctx, "Respect Plugin Manager Search Exclusions", config.respect_search_exclusions_in_screenshots)
            if rses_changed then
                config.respect_search_exclusions_in_screenshots = rses_val
                RequestClearScreenshotCache()
                SaveConfig()
            end
            if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "When enabled, plugins you excluded from search in Plugin Manager won't appear in the screenshot window.")
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.resize_screenshots_with_window = r.ImGui_Checkbox(ctx, "Auto Resize Screenshots", config.resize_screenshots_with_window)
            if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "When enabled, screenshots will automatically resize to fit the window.")
            end

            r.ImGui_Dummy(ctx, 0, 5)
            r.ImGui_SetCursorPosX(ctx, column1_width)
            r.ImGui_Text(ctx, "Default Folder:")
            r.ImGui_SameLine(ctx, 0, 10)
            r.ImGui_PushItemWidth(ctx, slider_width)
            r.ImGui_SetNextWindowSizeConstraints(ctx, 0, 0, FLT_MAX, config.dropdown_menu_length * r.ImGui_GetTextLineHeightWithSpacing(ctx))
            local current_default_label = config.default_folder
            if current_default_label == LAST_OPENED_SENTINEL then current_default_label = "Last opened folder" end
            if r.ImGui_BeginCombo(ctx, "##Default Folder", current_default_label or "None") then
                if r.ImGui_Selectable(ctx, "None", config.default_folder == nil) then
                    config.default_folder = nil
                    SaveConfig()
                end
                if r.ImGui_Selectable(ctx, "Last opened folder", config.default_folder == LAST_OPENED_SENTINEL) then
                    config.default_folder = LAST_OPENED_SENTINEL
                    SaveConfig()
                end
                if r.ImGui_Selectable(ctx, "Favorites", config.default_folder == "Favorites") then
                    config.default_folder = "Favorites"
                    SaveConfig()
                end
                if r.ImGui_Selectable(ctx, "Current Project FX", config.default_folder == "Current Project FX") then
                    config.default_folder = "Current Project FX"
                    SaveConfig()
                end
                if r.ImGui_Selectable(ctx, "Current Track FX", config.default_folder == "Current Track FX") then
                    config.default_folder = "Current Track FX"
                    SaveConfig()
                end
                if r.ImGui_Selectable(ctx, "Projects", config.default_folder == "Projects") then
                    config.default_folder = "Projects"
                    SaveConfig()
                end
                if r.ImGui_Selectable(ctx, "Sends/Receives", config.default_folder == "Sends/Receives") then
                    config.default_folder = "Sends/Receives" 
                    SaveConfig()
                end
                if r.ImGui_Selectable(ctx, "Actions", config.default_folder == "Actions") then
                    config.default_folder = "Actions"
                    SaveConfig()
                end
                for i = 1, #folders_category do
                    local is_selected = (config.default_folder == folders_category[i].name)
                    if r.ImGui_Selectable(ctx, folders_category[i].name, is_selected) then
                        config.default_folder = folders_category[i].name
                        SaveConfig()
                    end
                end
                r.ImGui_EndCombo(ctx)
            end  
            if r.ImGui_IsItemHovered(ctx) then
                local wheel_delta = r.ImGui_GetMouseWheel(ctx)
                if wheel_delta ~= 0 then
                    local options = { nil, LAST_OPENED_SENTINEL, "Favorites", "Current Project FX", "Current Track FX", "Projects", "Sends/Receives", "Actions" }
                    for i = 1, #folders_category do options[#options+1] = folders_category[i].name end
                    local current_index = 1
                    for i, opt in ipairs(options) do
                        if opt == config.default_folder then current_index = i; break end
                    end
                   
                    local new_index = current_index - wheel_delta
                    if new_index < 1 then new_index = 1 end
                    if new_index > #options then new_index = #options end
                    config.default_folder = options[new_index]
                    SaveConfig()
                end
            end

            r.ImGui_PopItemWidth(ctx)
            r.ImGui_SameLine(ctx)

            r.ImGui_SetCursorPosX(ctx, column3_width)
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


            r.ImGui_Dummy(ctx, 0, 5)
            r.ImGui_SetCursorPosX(ctx, column1_width)

            local function RefreshAfterTypePriorityChange()
                RequestClearScreenshotCache()
                search_warning_message = nil
                local term = (browser_search_term or "")
        
                if term ~= "" then
                    local term_l = term:lower()
                    if browser_panel_selected then
                        current_filtered_fx = GetFxListForSubgroup(browser_panel_selected) or {}
                        local filtered = {}
                        for _, p in ipairs(current_filtered_fx) do
                            if p:lower():find(term_l, 1, true) then filtered[#filtered+1] = p end
                        end
                        if config.apply_type_priority then
                            filtered = DedupeByTypePriority(filtered)
                        end
                        current_filtered_fx = filtered
                    elseif selected_folder then
                        local base = GetPluginsForFolder(selected_folder) or {}
                        local filtered = {}
                        for _, p in ipairs(base) do
                            if p:lower():find(term_l, 1, true) then filtered[#filtered+1] = p end
                        end
                        if config.apply_type_priority then
                            filtered = DedupeByTypePriority(filtered)
                        end
                        current_filtered_fx = filtered
                    else
                        local matches = {}
                        for _, plugin in ipairs(PLUGIN_LIST or {}) do
                            if plugin:lower():find(term_l, 1, true) then matches[#matches+1] = plugin end
                        end
                        if config.apply_type_priority then
                            matches = DedupeByTypePriority(matches)
                        end
                        screenshot_search_results = {}
                        local MAX_RESULTS = 200
                        for i = 1, math.min(MAX_RESULTS, #matches) do
                            screenshot_search_results[#screenshot_search_results+1] = { name = matches[i] }
                        end
                        if #matches > MAX_RESULTS then
                            search_warning_message = "Showing first " .. MAX_RESULTS .. " results. Please refine your search for more specific results."
                        end
                        SortScreenshotResults()
                        new_search_performed = true
                        return
                    end
                else
                    if browser_panel_selected then
                        current_filtered_fx = GetFxListForSubgroup(browser_panel_selected) or {}
                        if config.apply_type_priority then
                            current_filtered_fx = DedupeByTypePriority(current_filtered_fx)
                        end
                    elseif selected_folder then
                        current_filtered_fx = GetPluginsForFolder(selected_folder) or {}
                    else
                        return
                    end
                end
                loaded_items_count = ITEMS_PER_BATCH or loaded_items_count or 30
                screenshot_search_results = {}
                if view_mode == "list" then
                    for i = 1, #current_filtered_fx do
                        screenshot_search_results[#screenshot_search_results+1] = { name = current_filtered_fx[i] }
                    end
                else
                    for i = 1, math.min(loaded_items_count, #current_filtered_fx) do
                        screenshot_search_results[#screenshot_search_results+1] = { name = current_filtered_fx[i] }
                    end
                end
                new_search_performed = true
            end
            local ap_changed, ap_val = r.ImGui_Checkbox(ctx, "Type Priority:  ", config.apply_type_priority)
            if ap_changed then
                config.apply_type_priority = ap_val
                SaveConfig()
                RefreshAfterTypePriorityChange()
            end
            if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "When enabled, multiple formats of the same plugin are deduped by your chosen order.")
            end

            local types_all = {"CLAP","VST3","VST","JS","AU","LV2"}
            local function drawTypeComboInline(idx)
                r.ImGui_PushItemWidth(ctx, 83)
                local current = config.plugin_type_priority[idx] or types_all[idx]
                if r.ImGui_BeginCombo(ctx, "##TP"..idx, current) then
                    for _, t in ipairs(types_all) do
                        local is_sel = (current == t)
                        if r.ImGui_Selectable(ctx, t, is_sel) then
                            config.plugin_type_priority[idx] = t
                            SaveConfig()
                            RefreshAfterTypePriorityChange()
                        end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                r.ImGui_PopItemWidth(ctx)
            end
            r.ImGui_SameLine(ctx)
            drawTypeComboInline(1)
            r.ImGui_SameLine(ctx)
            drawTypeComboInline(2)
            r.ImGui_SameLine(ctx)
            drawTypeComboInline(3)
            r.ImGui_SameLine(ctx)
            drawTypeComboInline(4)
            

            
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
            r.ImGui_Text(ctx, "Bulk Folder")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column2_width)
            r.ImGui_PushItemWidth(ctx, slider_width * 2)
            local current_label
            do
                local sel = config.bulk_selected_folder
                if not sel or sel == "__ALL_PLUGINS" then
                    current_label = "All Plugins"
                elseif sel:match("^DEV::") then
                    current_label = "Developer: " .. sel:sub(6)
                elseif sel == "CUSTOM::ALL" then
                    current_label = "Custom (all)"
                elseif sel:match("^CUST::") then
                    current_label = "Custom: " .. sel:sub(7)
                else
                    current_label = sel 
                end
            end
            local popup_id = "BulkFolderPopup"
            local btn_w = slider_width * 2
            if r.ImGui_Button(ctx, current_label .. "##BulkFolderBtn", btn_w, 0) then
                r.ImGui_OpenPopup(ctx, popup_id)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Klik om map te kiezen (submenus openen bij hover)") end

            if r.ImGui_BeginPopup(ctx, popup_id) then
                local function SetAndClose(value)
                    config.bulk_selected_folder = value
                    r.ImGui_CloseCurrentPopup(ctx)
                end

                if r.ImGui_MenuItem(ctx, (config.bulk_selected_folder == "__ALL_PLUGINS" and "[All Plugins]" or "All Plugins")) then
                    SetAndClose("__ALL_PLUGINS")
                end
                r.ImGui_Separator(ctx)

                local function BeginGroupMenu(label)
                    return r.ImGui_BeginMenu(ctx, label)
                end

                -- FOLDERS submenu
                local folders_ref
                for i = 1, #CAT_TEST do
                    if CAT_TEST[i].name == "FOLDERS" then folders_ref = CAT_TEST[i].list break end
                end
                if folders_ref and #folders_ref > 0 then
                    if BeginGroupMenu("Folders") then
                        for j = 1, #folders_ref do
                            local fname = folders_ref[j].name
                            local label = (config.bulk_selected_folder == fname and ("["..fname.."]") or fname)
                            if r.ImGui_MenuItem(ctx, label) then SetAndClose(fname) end
                        end
                        r.ImGui_EndMenu(ctx)
                    end
                end

                -- Developers submenu (DEV/DEVS/DEVELOPER(S))
                local function IsDevCat(n)
                    n = (n or ""):upper()
                    return n == "DEV" or n == "DEVS" or n:find("DEVELOPER") ~= nil
                end
                local dev_list
                for i = 1, #CAT_TEST do
                    if IsDevCat(CAT_TEST[i].name) then dev_list = CAT_TEST[i].list break end
                end
                if dev_list and #dev_list > 0 then
                    if BeginGroupMenu("Developers") then
                        for j = 1, #dev_list do
                            local dname = dev_list[j].name
                            local value = "DEV::" .. dname
                            local label = (config.bulk_selected_folder == value and ("["..dname.."]") or dname)
                            if r.ImGui_MenuItem(ctx, label) then SetAndClose(value) end
                        end
                        r.ImGui_EndMenu(ctx)
                    end
                end

                -- Custom submenu (recursief)
                if config.custom_folders and next(config.custom_folders) then
                    if BeginGroupMenu("Custom") then
                        if r.ImGui_MenuItem(ctx, (config.bulk_selected_folder == "CUSTOM::ALL" and "[All Custom]" or "All Custom")) then
                            SetAndClose("CUSTOM::ALL")
                        end
                        local function TraverseCustomTree(tbl, prefix)
                            prefix = prefix or ""
                            local names = {}
                            for name,_ in pairs(tbl) do table.insert(names,name) end
                            table.sort(names, function(a,b) return a:lower()<b:lower() end)
                            for _, name in ipairs(names) do
                                local content = tbl[name]
                                local path = prefix == "" and name or (prefix .. "/" .. name)
                                if IsPluginArray(content) then
                                    local value = "CUST::" .. path
                                    local label = (config.bulk_selected_folder == value and ("["..path.."]") or path)
                                    if r.ImGui_MenuItem(ctx, label) then SetAndClose(value) end
                                elseif IsSubfolderStructure(content) then
                                    if r.ImGui_BeginMenu(ctx, name) then
                                        TraverseCustomTree(content, path)
                                        r.ImGui_EndMenu(ctx)
                                    end
                                end
                            end
                        end
                        TraverseCustomTree(config.custom_folders, "")
                        r.ImGui_EndMenu(ctx)
                    end
                end

                r.ImGui_EndPopup(ctx)
            end
            r.ImGui_PopItemWidth(ctx)
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Limit bulk screenshots to this (sub)folder. Custom folder paths are supported.") end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column4_width)
            if config.bulk_selected_folder then
                if r.ImGui_Button(ctx, "Clear##BulkFolderClear", 60, 20) then
                    config.bulk_selected_folder = nil
                end
            end
            r.ImGui_Separator(ctx)
            r.ImGui_SetCursorPosX(ctx, column1_width)
            _, config.close_after_adding_fx = r.ImGui_Checkbox(ctx, "Close script after adding FX", config.close_after_adding_fx)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, column3_width)
            _, config.open_floating_after_adding = r.ImGui_Checkbox(ctx, "Open FX floating after adding", config.open_floating_after_adding)
            r.ImGui_SetCursorPosX(ctx, column1_width)
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

if r.ImGui_BeginTabItem(ctx, "CUSTOM FOLDERS") then
    r.ImGui_Text(ctx, "Manage Custom Plugin Folders:")
    r.ImGui_Separator(ctx)
    
    -- Add new folder section
    r.ImGui_Text(ctx, "Add New Folder:")
    r.ImGui_PushItemWidth(ctx, 200)
    local changed, new_folder_name = r.ImGui_InputTextWithHint(ctx, "##NewFolderName", "Enter folder name", new_custom_folder_name or "")
    if changed then
        new_custom_folder_name = new_folder_name
    end
    r.ImGui_PopItemWidth(ctx)
    
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Add Folder") then
        if new_custom_folder_name and new_custom_folder_name ~= "" then
            CreateNestedFolder(new_custom_folder_name, current_folder_context)
            SaveCustomFolders()
            new_custom_folder_name = ""
        end
    end
    
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Add Subfolder") then
        if new_custom_folder_name and new_custom_folder_name ~= "" and current_folder_context then
            CreateNestedFolder(new_custom_folder_name, current_folder_context)
            SaveCustomFolders()
            new_custom_folder_name = ""
        end
    end
    
    -- Breadcrumb navigation
    if current_folder_context then
        r.ImGui_Text(ctx, "Current: " .. current_folder_context)
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Back to Root") then
            current_folder_context = nil
        end
    end
    
    r.ImGui_Separator(ctx)
    
function DisplayFolderTree(folders, path_prefix)
    path_prefix = path_prefix or ""
    
    -- SORTEER DE FOLDER NAMEN ALFABETISCH
    local sorted_folder_names = {}
    for folder_name, _ in pairs(folders) do
        table.insert(sorted_folder_names, folder_name)
    end
    table.sort(sorted_folder_names, function(a, b) 
        return a:lower() < b:lower() 
    end)
    
    -- GEBRUIK DE GESORTEERDE NAMEN
    for _, folder_name in ipairs(sorted_folder_names) do
        local folder_content = folders[folder_name]
        local full_path = path_prefix == "" and folder_name or (path_prefix .. "/" .. folder_name)
        r.ImGui_PushID(ctx, full_path)
            
            if IsPluginArray(folder_content) then
                -- Plugin folder
                if r.ImGui_CollapsingHeader(ctx, folder_name .. " (" .. #folder_content .. " plugins)") then
                    r.ImGui_Indent(ctx, 20)
                    
                    -- Set context for adding plugins
                    if r.ImGui_Button(ctx, "Set as Context##" .. full_path) then
                        current_folder_context = full_path
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Browse##" .. full_path) then
                        selected_custom_folder_for_browse = full_path
                        show_plugin_browser = true
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Rename##" .. full_path) then
                        rename_folder_path = full_path
                        rename_folder_new_name = folder_name
                        show_rename_folder_popup = true
                    end
                    
                    -- PLUGIN TOEVOEG SECTIE - HANDMATIG
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "Add Plugin:")
                    r.ImGui_PushItemWidth(ctx, 250)
                    if not plugin_input_text then
                        plugin_input_text = {}
                    end
                    if not plugin_input_text[full_path] then
                        plugin_input_text[full_path] = ""
                    end
                    local plugin_changed, new_plugin = r.ImGui_InputTextWithHint(ctx, "##AddPlugin" .. full_path, "Enter plugin name", plugin_input_text[full_path])
                    if plugin_changed then
                        plugin_input_text[full_path] = new_plugin
                    end
                    r.ImGui_PopItemWidth(ctx)

                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Add##" .. full_path) then
                        if plugin_input_text[full_path] and plugin_input_text[full_path] ~= "" then
                            -- Check if plugin exists in PLUGIN_LIST
                            local plugin_exists = false
                            local exact_plugin_name = nil
                            for _, existing_plugin in ipairs(PLUGIN_LIST) do
                                if existing_plugin:lower():find(plugin_input_text[full_path]:lower(), 1, true) then
                                    plugin_exists = true
                                    exact_plugin_name = existing_plugin
                                    break
                                end
                            end
                            
                            if plugin_exists then
                                if not table.contains(folder_content, exact_plugin_name) then
                                    table.insert(folder_content, exact_plugin_name)
                                    SaveCustomFolders()
                                    plugin_input_text[full_path] = ""  -- Clear input after successful add
                                else
                                    r.ShowMessageBox("Plugin already in folder!", "Info", 0)
                                end
                            else
                                r.ShowMessageBox("Plugin not found in installed plugins!\nTry typing part of the plugin name.", "Error", 0)
                            end
                        end
                    end
                    
                    r.ImGui_Separator(ctx)
                    
                    -- List plugins
                    for i, plugin in ipairs(folder_content) do
                        r.ImGui_Text(ctx, plugin)
                        r.ImGui_SameLine(ctx)
                        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetWindowWidth(ctx) - 80)
                        if r.ImGui_Button(ctx, "Remove##" .. i .. full_path) then
                            table.remove(folder_content, i)
                            SaveCustomFolders()
                        end
                    end
                    
                    r.ImGui_Separator(ctx)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
                    if r.ImGui_Button(ctx, "Delete Folder##" .. full_path) then
                        -- Remove from nested structure
                        local parts = {}
                        for part in full_path:gmatch("[^/]+") do
                            table.insert(parts, part)
                        end
                        
                        local current = config.custom_folders
                        for i = 1, #parts - 1 do
                            current = current[parts[i]]
                        end
                        current[parts[#parts]] = nil
                        
                        SaveCustomFolders()
                    end
                    r.ImGui_PopStyleColor(ctx)
                    
                    r.ImGui_Unindent(ctx, 20)
                end
                
            elseif IsSubfolderStructure(folder_content) then
                -- Parent folder with subfolders
                if r.ImGui_CollapsingHeader(ctx, folder_name .. " (folder)") then
                    r.ImGui_Indent(ctx, 20)
                    
                    if r.ImGui_Button(ctx, "Set as Context##" .. full_path) then
                        current_folder_context = full_path
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Rename##" .. full_path) then
                        rename_folder_path = full_path
                        rename_folder_new_name = folder_name
                        show_rename_folder_popup = true
                    end
                    
                    r.ImGui_Separator(ctx)
                    
                    -- Recursively display subfolders
                    DisplayFolderTree(folder_content, full_path)
                    
                    r.ImGui_Separator(ctx)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
                    if r.ImGui_Button(ctx, "Delete Folder##" .. full_path) then
                        local parts = {}
                        for part in full_path:gmatch("[^/]+") do
                            table.insert(parts, part)
                        end
                        
                        local current = config.custom_folders
                        for i = 1, #parts - 1 do
                            current = current[parts[i]]
                        end
                        current[parts[#parts]] = nil
                        
                        SaveCustomFolders()
                    end
                    r.ImGui_PopStyleColor(ctx)
                    
                    r.ImGui_Unindent(ctx, 20)
                end
            end
            
            r.ImGui_PopID(ctx)
        end
    end
    
    -- Display the folder tree
    local custom_folders_open = r.ImGui_BeginChild(ctx, "CustomFoldersList", -1, -50)
    if custom_folders_open then
        DisplayFolderTree(config.custom_folders)
    end
    r.ImGui_EndChild(ctx)
    
    -- Rename folder popup
    if show_rename_folder_popup then
        r.ImGui_OpenPopup(ctx, "Rename Folder")
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Rename Folder", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "Rename folder: " .. (rename_folder_path or ""))
        r.ImGui_Separator(ctx)
        
        r.ImGui_PushItemWidth(ctx, 300)
        local changed, new_name = r.ImGui_InputTextWithHint(ctx, "##RenameFolder", "Enter new name", rename_folder_new_name or "")
        if changed then
            rename_folder_new_name = new_name
        end
        r.ImGui_PopItemWidth(ctx)
        
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, "Rename", 100, 0) then
            if rename_folder_new_name and rename_folder_new_name ~= "" and rename_folder_path then
                local parts = {}
                for part in rename_folder_path:gmatch("[^/]+") do
                    table.insert(parts, part)
                end
                
                if #parts > 0 then
                    local current = config.custom_folders
                    for i = 1, #parts - 1 do
                        current = current[parts[i]]
                    end
                    
                    local old_name = parts[#parts]
                    local folder_content = current[old_name]
                    
                    current[old_name] = nil
                    current[rename_folder_new_name] = folder_content
                    
                    SaveCustomFolders()
                end
            end
            show_rename_folder_popup = false
            rename_folder_path = nil
            rename_folder_new_name = ""
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel", 100, 0) then
            show_rename_folder_popup = false
            rename_folder_path = nil
            rename_folder_new_name = ""
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    if show_plugin_browser then
        r.ImGui_OpenPopup(ctx, "Plugin Browser")
    end
    
    if r.ImGui_BeginPopupModal(ctx, "Plugin Browser", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "Select plugins to add to: " .. (selected_custom_folder_for_browse or ""))
        r.ImGui_Separator(ctx)
        
        r.ImGui_PushItemWidth(ctx, 300)
        local search_changed, search_text = r.ImGui_InputTextWithHint(ctx, "##SearchPlugins", "Search plugins...", plugin_search_text or "")
        if search_changed then
            plugin_search_text = search_text
        end
        r.ImGui_PopItemWidth(ctx)
        
    local plugin_browser_open = r.ImGui_BeginChild(ctx, "PluginBrowserList", 400, 300)
    if plugin_browser_open then
            for _, plugin in ipairs(PLUGIN_LIST) do
                if not plugin_search_text or plugin_search_text == "" or 
                plugin:lower():find(plugin_search_text:lower(), 1, true) then
                    
                    local already_in_folder = false
                    local folder_plugins = GetPluginsFromCustomFolder(selected_custom_folder_for_browse)
                    if folder_plugins then
                        already_in_folder = table.contains(folder_plugins, plugin)
                    end
                    
                    if not already_in_folder then
                        local display_plugin = GetDisplayPluginName(plugin)
                        if r.ImGui_Selectable(ctx, display_plugin .. "  " .. GetStarsString(plugin)) then
                            local parts = {}
                            for part in selected_custom_folder_for_browse:gmatch("[^/]+") do
                                table.insert(parts, part)
                            end
                            
                            local current = config.custom_folders
                            for _, part in ipairs(parts) do
                                if current[part] then
                                    current = current[part]
                                else
                                    return
                                end
                            end
                            
                            if IsPluginArray(current) then
                                table.insert(current, plugin)
                                SaveCustomFolders()
                            end
                        end
                    else
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                        r.ImGui_Text(ctx, plugin .. " (already added)")
                        r.ImGui_PopStyleColor(ctx)
                    end
                end
            end
        end
        r.ImGui_EndChild(ctx)
        
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, "Close", 100, 0) then
            show_plugin_browser = false
            selected_custom_folder_for_browse = nil
            plugin_search_text = ""
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel", 100, 0) then
            show_plugin_browser = false
            selected_custom_folder_for_browse = nil
            plugin_search_text = ""
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    r.ImGui_EndTabItem(ctx)
end

r.ImGui_EndTabBar(ctx)
end

r.ImGui_PopStyleColor(ctx, 2)
r.ImGui_End(ctx)
end
return config_open
end

function EnsureTrackIconsFolderExists()
    local track_icons_path = script_path .. "TrackIcons" .. os_separator
    if not r.file_exists(track_icons_path) then
        local success = r.RecursiveCreateDirectory(track_icons_path, 0)
        if success then
        else
            log_to_file("Error making TrackIcons Folder: " .. track_icons_path)
        end
    end
    return track_icons_path
end
EnsureTrackIconsFolderExists()

function EnsureScreenshotFolderExists()
    if not r.file_exists(screenshot_path) then
        local success = r.RecursiveCreateDirectory(screenshot_path, 0)
        if success then
        else
            log_to_file("Error making screenshot Folder: " .. screenshot_path)
        end
    end
end
EnsureScreenshotFolderExists()

function check_esc_key() 
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        return true
    end
    return false
end

function handleDocking()
    if change_dock then
        r.ImGui_SetNextWindowDockID(ctx, ~dock)
        change_dock = nil
        ClearScreenshotCache()
    end
end

function IsX86Bridged(plugin_name)
    if not plugin_name then return false end
    return (plugin_name:match('%(x86%)')
        or plugin_name:match('%[x86%]')
        or plugin_name:match('[%s%-]x86[%s%)]*$')
        or plugin_name:lower():match('x86%s*bridged')
        or plugin_name:match('x86:')) and true or false
end

function ScreenshotExists(plugin_name, size_option)
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
function IsMuted(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        return r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    end
    return false
end

function ToggleMute(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local mute = r.GetMediaTrackInfo_Value(track, "B_MUTE")
        r.SetMediaTrackInfo_Value(track, "B_MUTE", mute == 0 and 1 or 0)
    end
end

function IsSoloed(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        return r.GetMediaTrackInfo_Value(track, "I_SOLO") ~= 0
    end
    return false
end

function ToggleSolo(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO")
        r.SetMediaTrackInfo_Value(track, "I_SOLO", solo == 0 and 1 or 0)
    end
end

function ToggleArm(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        local armed = r.GetMediaTrackInfo_Value(track, "I_RECARM")
        r.SetMediaTrackInfo_Value(track, "I_RECARM", armed == 0 and 1 or 0)
    end
end

function IsArmed(track)
    if track and reaper.ValidatePtr(track, "MediaTrack*") then
        return r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
    end
    return false
end

function AddFXToItem(fx_name)
    local item = r.GetSelectedMediaItem(0, 0)
    if item then
        local take = r.GetActiveTake(item)
        if take then
            r.TakeFX_AddByName(take, fx_name, 1)
        end
    end
end

function CreateFXChain()
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then return end
    local fx_count = r.TrackFX_GetCount(TRACK)
    if fx_count == 0 then return end
    r.SetOnlyTrackSelected(TRACK)
    r.Main_OnCommand(r.NamedCommandLookup("_S&M_SAVE_FXCHAIN_SLOT1"), 0)
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
    r.ShowMessageBox("FX Chain created successfully!", "Success", 0)
end

-- Debug toggle for texture I/O logging (set true only for diagnostics)
local DEBUG_TEX_LOG = false
function tex_log(msg)
    if DEBUG_TEX_LOG then log_to_file(msg) end
end

function LoadTexture(file)
    local texture = r.ImGui_CreateImage(file)
    if texture == nil then
        tex_log("Failed to load texture: " .. file)
    end
    return texture
end
    
function LoadSearchTexture(file, plugin_name)
    local relative_path = file:gsub(screenshot_path, "")
    local unique_key = relative_path .. "_" .. (plugin_name or "unknown")
    local current_time = r.time_precise()
    if search_texture_cache[unique_key] then
        texture_last_used[unique_key] = current_time
        return search_texture_cache[unique_key]
    end
    if not r.file_exists(file) then
        tex_log("File does not exist: " .. file .. " for plugin: " .. (plugin_name or "unknown"))
        return nil
    end
    if not texture_load_queue[unique_key] then
        texture_load_queue[unique_key] = { file = file, queued_at = current_time, plugin = plugin_name }
        tex_log("Queued texture load: " .. file .. " for plugin: " .. (plugin_name or "unknown"))
    end
    return nil
end

    local function ProcessTextureLoadQueue()
    
    if not (config and config.show_screenshot_window) then return end
    if not texture_load_queue or next(texture_load_queue) == nil then return end
   
    local VISIBLE_BUFFER = 30
    local keep_set = {}
    local cap = (loaded_items_count or ITEMS_PER_BATCH or 30) + VISIBLE_BUFFER

    if selected_folder and type(current_filtered_fx) == 'table' and #current_filtered_fx > 0 then
        for i = 1, math.min(cap, #current_filtered_fx) do
            local name = current_filtered_fx[i]
            if type(name) == 'string' then keep_set[name] = true end
        end
    end
   
    if type(screenshot_search_results) == 'table' and #screenshot_search_results > 0 then
        local added = 0
        for _, fx in ipairs(screenshot_search_results) do
            if added >= cap then break end
            if fx and not fx.is_separator and not fx.is_message and fx.name then
                keep_set[fx.name] = true
                added = added + 1
            end
        end
    elseif (not selected_folder) and type(current_filtered_fx) == 'table' and #current_filtered_fx > 0 then
        
        for i = 1, math.min(cap, #current_filtered_fx) do
            local name = current_filtered_fx[i]
            if type(name) == 'string' then keep_set[name] = true end
        end
    end
    if next(keep_set) ~= nil then
        for key, info in pairs(texture_load_queue) do
            local pname = info and info.plugin
            if not pname or not keep_set[pname] then
                texture_load_queue[key] = nil
            end
        end
    end

    local original_max_per_frame = config.max_textures_per_frame
    local original_cache_max = config.max_cached_search_textures
    local original_min_cache = config.min_cached_textures
    local is_all_plugins_context = (not selected_folder and (browser_panel_selected == "ALL PLUGINS" or browser_panel_selected == nil))
    local visible_targets = loaded_items_count or ITEMS_PER_BATCH or 30
    if is_all_plugins_context and visible_targets > 60 then
        config.max_textures_per_frame = math.max(2, math.floor(original_max_per_frame * 0.5))
        config.max_cached_search_textures = math.max(40, math.floor(original_cache_max * 0.7))
        config.min_cached_textures = math.min(config.min_cached_textures, math.floor(config.max_cached_search_textures * 0.4))
    end

    local textures_loaded = 0
    local current_time = r.time_precise()
    for unique_key, info in pairs(texture_load_queue) do
        if textures_loaded >= config.max_textures_per_frame then break end
        local file = info.file
        if not search_texture_cache[unique_key] and r.file_exists(file) then
            local texture = r.ImGui_CreateImage(file)
            if texture then
                search_texture_cache[unique_key] = texture
                texture_last_used[unique_key] = current_time
                textures_loaded = textures_loaded + 1
                tex_log("Texture loaded (deferred): " .. file .. " for plugin: " .. (info.plugin or "unknown"))
            else
                tex_log("Error loading texture: " .. file)
            end
        end
        texture_load_queue[unique_key] = nil
    end
  
    local cache_size = 0
    for _ in pairs(search_texture_cache) do cache_size = cache_size + 1 end
    if cache_size > config.max_cached_search_textures then
        local textures_to_remove = {}
        for key, last_used in pairs(texture_last_used) do
            if current_time - last_used > config.texture_reload_delay and cache_size > config.min_cached_textures then
                table.insert(textures_to_remove, key)
                cache_size = cache_size - 1
            end
        end
        for _, key in ipairs(textures_to_remove) do
            if r.ImGui_DestroyImage and search_texture_cache[key] then
                r.ImGui_DestroyImage(ctx, search_texture_cache[key])
            end
            search_texture_cache[key] = nil
            texture_last_used[key] = nil
            tex_log("Texture removed: " .. key)
        end
    end
    
    if is_all_plugins_context and visible_targets > 60 then
        config.max_textures_per_frame = original_max_per_frame
        config.max_cached_search_textures = original_cache_max
        config.min_cached_textures = original_min_cache
    end
end  

function Lead_Trim_ws(s) return s:match '^%s*(.*)' end

function SetMinMax(Input, Min, Max)
    return math.max(Min, math.min(Input, Max))
end

function SortTable(tab, val1, val2)
    table.sort(tab, function(a, b)
        if (a[val1] < b[val1]) then return true
        elseif (a[val1] > b[val1]) then return false
        else return a[val2] < b[val2] end
    end)
end

function GetTrackColorAndTextColor(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return r.ImGui_ColorConvertDouble4ToU32(0.5, 0.5, 0.5, 1), 0xFFFFFFFF
    end
    local color = r.GetTrackColor(track)
    if color == 0 then
        return r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 0x000000FF
    else
        -- Convert from REAPER's native color encoding (platform-dependent) to RGB
        local rr, gg, bb = r.ColorFromNative(color)
        rr, gg, bb = rr or 128, gg or 128, bb or 128
        local red = rr / 255
        local green = gg / 255
        local blue = bb / 255
        local brightness = (red * 0.299 + green * 0.587 + blue * 0.114)
        local text_color = brightness > 0.5 and 0x000000FF or 0xFFFFFFFF
        return r.ImGui_ColorConvertDouble4ToU32(red, green, blue, 1), text_color
    end
end

function GetTagColorAndTextColor(tag_color)
    local red, g, b, a = r.ImGui_ColorConvertU32ToDouble4(tag_color)
    local brightness = (red * 299 + g * 587 + b * 114) / 1000
    local text_color = brightness > 0.5 
        and r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, 1) 
        or r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
    return tag_color, text_color
end

function GetBounds(hwnd)
    local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
    return left, top, right-left, bottom-top
end

function Literalize(str)
    return str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

function GetFileContext(filename)
    local file = io.open(filename, "r")
    if file then
        local content = file:read("*all")
        file:close()
        return content
    end
    return nil
end

function GetTrackName(track)
    if not track or not reaper.ValidatePtr(track, "MediaTrack*") then
        return "No Track Selected"
    end
    local _, name = r.GetTrackName(track)
    return name
end
function IsOSX()
    local platform = reaper.GetOS()
    return platform:match("OSX") or platform:match("macOS")
end

function ScreenshotOSX(path, x, y, w, h)
    x, y = r.ImGui_PointConvertNative(ctx, x, y, false)
    local command = 'screencapture -x -R %d,%d,%d,%d -t png "%s"'
    os.execute(command:format(x, y, w, h, path))
end
                            

------------
local wait_time = config.screenshot_delay 
function Wait(callback, start_time)
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
function IsPluginClosed(fx_index)
    return not r.TrackFX_GetFloatingWindow(TRACK, fx_index)
end

function EnsurePluginRemoved(fx_index, callback)
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

function CaptureScreenshot(plugin_name, fx_index)
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

function CaptureExistingFX(track, fx_index)
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
                    h = top - bottom 
                    ScreenshotOSX(filename, left, top, w, h)
                end
            
            print("Screenshot Saved: " .. filename)
            RequestClearScreenshotCache()
            BuildScreenshotIndex(true)
            if selected_folder then folder_changed = true end
            if search_texture_cache then
                for k, tex in pairs(search_texture_cache) do
                    if k:find(safe_name, 1, true) then
                        if r.ImGui_DestroyImage and r.ImGui_ValidatePtr(tex, 'ImGui_Image*') then r.ImGui_DestroyImage(ctx, tex) end
                        search_texture_cache[k] = nil
                        if texture_last_used then texture_last_used[k] = nil end
                        if texture_load_queue then texture_load_queue[k] = nil end
                    end
                end
            end
            else
            print("No Plugin Window for " .. fx_name)
            end
        end)
    end
end
function CaptureFirstTrackFX()
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then return end
    
    local fx_count = r.TrackFX_GetCount(TRACK)
    if fx_count > 0 then
        CaptureExistingFX(TRACK, 0)
    else
        r.ShowMessageBox("No FX on the selected track", "Info", 0)
    end
end

function IsARAPlugin(track, fx_index)
    return r.TrackFX_GetNamedConfigParm(track, fx_index, "ARA")
end

function CaptureARAScreenshot(track, fx_index, plugin_name)
    local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
    if hwnd then
        r.TrackFX_Show(track, fx_index, 3)
        r.defer(function()
            r.time_precise()
            r.defer(function()
                local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                local filename = screenshot_path .. safe_name .. ".png"
                local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
                local w, h = right - left, bottom - top
                
                local srcDC = r.JS_GDI_GetClientDC(hwnd)
                local srcBmp = r.JS_LICE_CreateBitmap(true, w, h)
                local srcDC_LICE = r.JS_LICE_GetDC(srcBmp)
                r.JS_GDI_Blit(srcDC_LICE, 0, 0, srcDC, config.srcx, config.srcy, w, h)
                r.JS_LICE_WritePNG(filename, srcBmp, false)
                r.JS_GDI_ReleaseDC(hwnd, srcDC)
                r.JS_LICE_DestroyBitmap(srcBmp)
                
                r.TrackFX_Show(track, fx_index, 2)
            end)
        end)
    end
end

function GetNextPlugin(current_plugin)
    for i, plugin in ipairs(FX_LIST_TEST) do
        if plugin == current_plugin then
            if i < #FX_LIST_TEST then
                return FX_LIST_TEST[i + 1]
            end
        end
    end
    return "None - This is the last plugin"
end

function MakeScreenshot(plugin_name, callback, is_individual)
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
            local fx_index = AddFXToTrack(TRACK, plugin_name)
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
function EnumerateInstalledFX()
    fx_list = {}
    total_fx_count = 0
    local default_folder_plugins = {}
    local bulk_folder_plugins = nil
    do
        local sel = config.bulk_selected_folder
        if sel and sel ~= "__ALL_PLUGINS" then
            bulk_folder_plugins = {}
            if sel:match("^DEV::") then
                local devname = sel:sub(6)
                local function IsDevCat(n)
                    n = (n or ""):upper()
                    return n == "DEV" or n == "DEVS" or n:find("DEVELOPER") ~= nil
                end
                for i = 1, #CAT_TEST do
                    if IsDevCat(CAT_TEST[i].name) then
                        for j = 1, #CAT_TEST[i].list do
                            if CAT_TEST[i].list[j].name == devname then
                                for k = 1, #CAT_TEST[i].list[j].fx do
                                    bulk_folder_plugins[CAT_TEST[i].list[j].fx[k]] = true
                                end
                                break
                            end
                        end
                        break
                    end
                end
            elseif sel == "CUSTOM::ALL" then
                local function CollectAll(tbl)
                    for _, content in pairs(tbl) do
                        if IsPluginArray(content) then
                            for _, plg in ipairs(content) do bulk_folder_plugins[plg] = true end
                        elseif IsSubfolderStructure(content) then
                            CollectAll(content)
                        end
                    end
                end
                CollectAll(config.custom_folders or {})
            elseif sel:match("^CUST::") then
                local path = sel:sub(7)
                local function FetchCustom(path_in)
                    local parts = {}
                    for part in path_in:gmatch("[^/]+") do table.insert(parts, part) end
                    local cur = config.custom_folders
                    for _, p in ipairs(parts) do
                        cur = cur and cur[p]
                        if not cur then return end
                    end
                    if cur and IsPluginArray(cur) then
                        for _, plg in ipairs(cur) do bulk_folder_plugins[plg] = true end
                    elseif cur and IsSubfolderStructure(cur) then
                        local function Recurse(tbl)
                            for _, v in pairs(tbl) do
                                if IsPluginArray(v) then
                                    for _, plg in ipairs(v) do bulk_folder_plugins[plg] = true end
                                elseif IsSubfolderStructure(v) then
                                    Recurse(v)
                                end
                            end
                        end
                        Recurse(cur)
                    end
                end
                FetchCustom(path)
            else
                for i = 1, #CAT_TEST do
                    if CAT_TEST[i].name == "FOLDERS" then
                        for j = 1, #CAT_TEST[i].list do
                            if CAT_TEST[i].list[j].name == sel then
                                for k = 1, #CAT_TEST[i].list[j].fx do
                                    bulk_folder_plugins[CAT_TEST[i].list[j].fx[k]] = true
                                end
                                break
                            end
                        end
                        break
                    end
                end
                if next(bulk_folder_plugins) == nil and config.custom_folders then
                    local function LegacyFetch(path_in)
                        local parts = {}
                        for part in path_in:gmatch("[^/]+") do table.insert(parts, part) end
                        local cur = config.custom_folders
                        for _, p in ipairs(parts) do
                            cur = cur and cur[p]
                            if not cur then return end
                        end
                        if cur and IsPluginArray(cur) then
                            for _, plg in ipairs(cur) do bulk_folder_plugins[plg] = true end
                        end
                    end
                    LegacyFetch(sel)
                    if next(bulk_folder_plugins) == nil then bulk_folder_plugins = nil end
                end
            end
            if bulk_folder_plugins and next(bulk_folder_plugins) == nil then
                bulk_folder_plugins = nil 
            end
        end
    end
    
    if config.screenshot_default_folder_only and config.default_folder then
        local target_name = config.default_folder
        if target_name == LAST_OPENED_SENTINEL then target_name = last_viewed_folder end
        if target_name then
            local function CollectFxByGroupName(cat_name_pred)
                for i = 1, #CAT_TEST do
                    local cat = CAT_TEST[i]
                    if cat_name_pred(cat.name) then
                        for j = 1, #cat.list do
                            local grp = cat.list[j]
                            if grp.name == target_name and grp.fx then
                                for k = 1, #grp.fx do
                                    default_folder_plugins[grp.fx[k]] = true
                                end
                                return true
                            end
                        end
                    end
                end
            end
            local found = CollectFxByGroupName(function(n) return (n or ""):upper() == "FOLDERS" end)
            if not found then
                local function IsAllPlugins(n) n = (n or ""):upper(); return n == "ALL PLUGINS" or n == "ALL" end
                local function IsCategory(n) n = (n or ""):upper(); return n == "CATEGORY" or n:find("CATEG") ~= nil end
                local function IsDev(n) n = (n or ""):upper(); return n == "DEVELOPER" or n:find("DEV") ~= nil end
                found = CollectFxByGroupName(IsAllPlugins) or CollectFxByGroupName(IsCategory) or CollectFxByGroupName(IsDev)
            end
        end
    end
    for i = 1, math.huge do
        local retval, fx_name = r.EnumInstalledFX(i)
        if not retval then break end
        
        local include_fx = false
    local passes_default = (not config.screenshot_default_folder_only) or default_folder_plugins[fx_name]
    local passes_bulk_folder = (not bulk_folder_plugins) or bulk_folder_plugins[fx_name]
    if passes_default and passes_bulk_folder then
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
        if include_fx and config.plugin_visibility and config.plugin_visibility[fx_name] == false then
            include_fx = false
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
function ProcessFX(index, start_time)
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
                            ProcessFX(total_fx_count + 1) 
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

function StartSingleScreenshotCapture(plugin_name, cb, force)
    if not plugin_name or plugin_name == '' then if cb then cb(false) end return end
    if IsX86Bridged(plugin_name) and config.include_x86_bridged == false then if cb then cb(false) end return end
    if not force then
        if config.screenshot_size_option ~= 1 and ScreenshotExists and ScreenshotExists(plugin_name, config.screenshot_size_option) then
            if cb then cb(true) end
            return
        end
    end
    local ok, err = pcall(function()
        MakeScreenshot(plugin_name, function()
            if cb then cb(true) end
        end, true)
    end)
    if not ok then
        log_to_file("Single screenshot crash/err: " .. tostring(err))
        if cb then cb(false) end
    end
end


function ClearScreenshots()
    for file in io.popen('dir "'..screenshot_path..'" /b'):lines() do
        os.remove(screenshot_path .. file)
    end
    print("All screenshots cleared.")
end

function ShowConfirmClearPopup()
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
        loaded_fx_count = 0  
        START = true
        PROCESS = true
        STOP_REQUESTED = false
        ProcessFX(1)
    else
        STOP_REQUESTED = true
    end
end

function StartSelectedMissingScreenshots()
    if START_SELECTED then
        STOP_SELECTED = true
        return
    end
    selected_missing_queue = {}
    for _, p in ipairs(filtered_plugins) do
        if config.show_missing_screenshots_only and config.plugin_visibility[p.name] ~= false and not HasScreenshot(p.name) then
            table.insert(selected_missing_queue, p.name)
        end
    end
    if #selected_missing_queue == 0 then return end
    START_SELECTED = true
    STOP_SELECTED = false
    current_selected_index = 1
    ProcessSelectedMissing()
end


function StartFolderScreenshots(folder_name, explicit_plugin_list)
    if not folder_name or folder_name == '' then return end

    local plugins = explicit_plugin_list

    if plugins == nil then
        plugins = GetPluginsForFolder(folder_name)
    end

    if (not plugins or #plugins == 0) and type(CAT_TEST) == 'table' then
        for i = 1, #CAT_TEST do
            local cat = CAT_TEST[i]
            if cat and (cat.name == "ALL PLUGINS" or cat.name == "CATEGORY" or cat.name == "DEVELOPER") and type(cat.list) == 'table' then
                for j = 1, #cat.list do
                    local grp = cat.list[j]
                    if grp and grp.name == folder_name then
                        plugins = grp.fx or {}
                        break
                    end
                end
            end
            if plugins and #plugins > 0 then break end
        end
    end

    if not plugins or #plugins == 0 then
        reaper.ShowMessageBox("Found no plugins in folder", "Folder screenshots", 0)
        return
    end

    plugins = DedupeByTypePriority(plugins)

    loaded_fx_count = 0
    total_fx_count = #plugins
    bulk_screenshot_progress = 0

    local idx = 1
    local function nextShot()
        if idx > #plugins then
            bulk_screenshot_progress = 0
            reaper.ShowMessageBox("Screenshots map klaar: " .. folder_name .. " (" .. loaded_fx_count .. "/" .. total_fx_count .. ")", "Map screenshots", 0)
            return
        end
        local plugin_name = plugins[idx]
        idx = idx + 1
        StartSingleScreenshotCapture(plugin_name, function(ok)
            if ok then
                loaded_fx_count = loaded_fx_count + 1
                bulk_screenshot_progress = loaded_fx_count / total_fx_count
            end
            r.defer(nextShot)
        end)
    end

    nextShot()
end


function ProcessSelectedMissing()
    if STOP_SELECTED then
        START_SELECTED = false
        STOP_SELECTED = false
        return
    end
    local plugin_name = selected_missing_queue and selected_missing_queue[current_selected_index]
    if not plugin_name then
        
        START_SELECTED = false
        BuildScreenshotIndex(true)
        
        if config.show_missing_screenshots_only then
            local refreshed = {}
            for _, p in ipairs(PLUGIN_LIST) do
                if not HasScreenshot(p) and (search_filter == '' or string.find(string.lower(p), string.lower(search_filter))) then
                    table.insert(refreshed, { name = p, visible = config.plugin_visibility[p] ~= false, searchable = not config.excluded_plugins[p] })
                end
            end
            table.sort(refreshed, function(a,b) return a.name:lower() < b.name:lower() end)
            filtered_plugins = refreshed
        end
        return
    end
    LAST_USED_FX = plugin_name
    StartSingleScreenshotCapture(plugin_name, function()
        if STOP_SELECTED then
            START_SELECTED = false
            STOP_SELECTED = false
            return
        end
        current_selected_index = current_selected_index + 1
        r.defer(ProcessSelectedMissing)
    end)
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
                
                local window_pos_x
                if is_left_docked then
                    window_pos_x = mouse_x + 20  -- Toon rechts
                else
                    window_pos_x = mouse_x - display_width - 20  -- Toon links
                end
                
                local window_pos_y = mouse_y + 20
                
                if window_pos_y + display_height > window_y + vp_height + 250 then
                    window_pos_y = mouse_y - display_height - 20
                end

                local show_name = config.show_name_in_main_window and not config.hidden_names[current_hovered_plugin]
                local window_height = display_height + (show_name and 40 or 0)
                
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
                        local text_pos_y = display_height + 1
                           
                        r.ImGui_SetCursorPos(ctx, text_pos_x, text_pos_y)
                        local display_name = GetDisplayPluginName(current_hovered_plugin)
                        r.ImGui_Text(ctx, display_name)
                        local stars = GetStarsString(current_hovered_plugin)
                        local stars_width = r.ImGui_CalcTextSize(ctx, stars)
                        local stars_pos_x = (display_width - stars_width) * 0.5
                        local stars_pos_y = text_pos_y + r.ImGui_GetTextLineHeight(ctx)
                        r.ImGui_SetCursorPos(ctx, stars_pos_x, stars_pos_y)
                        r.ImGui_Text(ctx, stars)
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

function GetCurrentProjectFX()
    local fx_list = {}
    local track_count = reaper.CountTracks(0)
    
    -- MASTER TRACK EERST
    local master_track = reaper.GetMasterTrack(0)
    local master_fx_count = reaper.TrackFX_GetCount(master_track)
    for j = 0, master_fx_count - 1 do
        local retval, fx_name = reaper.TrackFX_GetFXName(master_track, j, "")
        if retval then
            table.insert(fx_list, {
                fx_name = fx_name,
                track_name = "Master Track",
                track_number = 0,  -- Master track identifier
                track_color = 0x404040FF,
                fx_index = j,
                is_master = true,  -- Nieuwe flag voor master track
                unique_id = "master_" .. j
            })
        end
    end
    
    -- NORMALE TRACKS
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
                    track_color = track_color,
                    fx_index = j,  
                    is_master = false,
                    unique_id = track_number .. "_" .. j
                })
            end
        end
    end
    return fx_list
end

function AddPluginToSelectedTracks(plugin_name)
    local track_count = r.CountSelectedTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
    local fx_index = AddFXToTrack(track, plugin_name)
        r.TrackFX_Show(track, fx_index, 2)  
    end
end

function AddPluginToAllTracks(plugin_name)
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
    local fx_index = AddFXToTrack(track, plugin_name)
        r.TrackFX_Show(track, fx_index, 2)  
    end
end

function AddToFavorites(plugin_name)
    if favorite_set[plugin_name] then return end
    table.insert(favorite_plugins, plugin_name)
    favorite_set[plugin_name] = true
    SaveFavorites()
    if RefreshCurrentScreenshotView then RefreshCurrentScreenshotView() end
end

function RemoveFromFavorites(plugin_name)
    for i, fav in ipairs(favorite_plugins) do
        if fav == plugin_name then
            table.remove(favorite_plugins, i)
            favorite_set[plugin_name] = nil
            SaveFavorites()
            if RefreshCurrentScreenshotView then RefreshCurrentScreenshotView() end
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

function IsSendTrack(track)
    local parent = r.GetParentTrack(track)
    if parent then
        local _, name = r.GetTrackName(parent)
        return name == "SEND TRACK"
    end
    local _, name = r.GetTrackName(track)
    return name == "SEND TRACK"
end

function ShowRoutingMatrix()
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
    local routing_open = r.ImGui_BeginChild(ctx, "RoutingMatrix", matrix_width, matrix_height)
    if routing_open then
        for i = 0, track_count - 1 do
            local x = (i + 1) * cell_size + left_margin
            local y = 20
            r.ImGui_SetCursorPos(ctx, x + 5, y)
            r.ImGui_Text(ctx, tostring(i + 1))
        end
        
        for i = 0, track_count - 1 do
            local y = (i + 1) * cell_size + header_height
            r.ImGui_SetCursorPos(ctx, 15, y + 2)
            r.ImGui_Text(ctx, tostring(i + 1))
        end
        
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

        local legend_x = (track_count + 1) * cell_size + left_margin + 20
        r.ImGui_SetCursorPos(ctx, legend_x, 20)
        r.ImGui_Text(ctx, "Track Legend:")
        for i = 0, track_count - 1 do
            local track = r.GetTrack(0, i)
            local _, name = r.GetTrackName(track)
            r.ImGui_SetCursorPos(ctx, legend_x, 40 + (i * 20))
            r.ImGui_Text(ctx, string.format("%d: %s", i + 1, name))
        end
        
    end
    r.ImGui_EndChild(ctx)
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

function FilterActions()
    if #allActions == 0 then
        -- Check if SWS extension is available
        if reaper.CF_EnumerateActions then
            local i = 0
            repeat
                local retval, name = reaper.CF_EnumerateActions(0, i)
                if retval > 0 and name and name ~= "" then
                    table.insert(allActions, {name = name, id = retval})
                end
                i = i + 1
            until retval <= 0
        else
            -- Fallback: Add some basic actions manually if SWS is not available
            local basic_actions = {
                {name = "Transport: Play/stop", id = 40044},
                {name = "Transport: Record", id = 1013},
                {name = "Edit: Copy items/tracks/envelope points", id = 40698},
                {name = "Edit: Paste items/tracks", id = 40058},
                {name = "Track: Insert new track", id = 40001},
                {name = "Item: Split items at edit cursor", id = 40746},
                {name = "View: Zoom to fit all in window", id = 40031}
            }
            for _, action in ipairs(basic_actions) do
                table.insert(allActions, action)
            end
        end
    end
end
FilterActions()
function CategorizeActions()
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
function SearchActions(search_term)
    if not search_term or search_term == "" then
        return categories
    end
    
    local filteredActions = {}
    for category, actions in pairs(categories) do
        filteredActions[category] = {}
        for _, action in ipairs(actions) do
            if action and action.name and action.name:lower():find(search_term:lower(), 1, true) then
                local state = reaper.GetToggleCommandState(action.id)
                action.state = state
                table.insert(filteredActions[category], action)
            end
        end
    end
    return filteredActions
end

function CreateSmartMarker(action_id)
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


local old_ShowPluginContextMenu = ShowPluginContextMenu
function ShowPluginContextMenu(plugin_name, menu_id)
    if type(plugin_name) == "table" then
        plugin_name = plugin_name.fx_name or plugin_name.name
    end
    if not plugin_name or type(plugin_name) ~= "string" then return end

    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "PluginContextMenu_" .. menu_id)
    end

    if r.ImGui_BeginPopup(ctx, "PluginContextMenu_" .. menu_id) then
        -- Rating UI bovenaan
        r.ImGui_Text(ctx, "Rating:")
        ShowPluginRatingUI(plugin_name)
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Make Screenshot") then
            StartSingleScreenshotCapture(plugin_name, function()
                ClearScreenshotCache()
                BuildScreenshotIndex(true)
                folder_changed = true
            end, true)
        end
        
        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
            if r.ImGui_MenuItem(ctx, "Add to Selected Tracks") then
                AddPluginToSelectedTracks(plugin_name)
            end
            if r.ImGui_MenuItem(ctx, "Add to All Tracks") then
                AddPluginToAllTracks(plugin_name)
            end
        end
        
    local is_favorite = not not favorite_set[plugin_name]
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

        -- Pin/unpin plugin
        local is_pinned = IsPluginPinned(plugin_name)
        if is_pinned then
            if r.ImGui_MenuItem(ctx, "Unpin Plugin") then
                UnpinPlugin(plugin_name)
            end
        else
            if r.ImGui_MenuItem(ctx, "Pin Plugin") then
                PinPlugin(plugin_name)
            end
        end

        -- ADD TO CUSTOM FOLDER SECTIE
        if next(config.custom_folders) then
            r.ImGui_Separator(ctx)
            if r.ImGui_BeginMenu(ctx, "Add to Custom Folder") then
                local function ShowCustomFolderMenu(folders, path_prefix)
                    path_prefix = path_prefix or ""
                    
                    for folder_name, folder_content in pairs(folders) do
                        local full_path = path_prefix == "" and folder_name or (path_prefix .. "/" .. folder_name)
                        
                        if IsPluginArray(folder_content) then
                            if r.ImGui_MenuItem(ctx, folder_name .. " (" .. #folder_content .. ")") then
                                if not table.contains(folder_content, plugin_name) then
                                    table.insert(folder_content, plugin_name)
                                    SaveCustomFolders()
                                    r.ShowMessageBox("Plugin added to " .. folder_name, "Success", 0)
                                else
                                    r.ShowMessageBox("Plugin already exists in " .. folder_name, "Info", 0)
                                end
                            end
                        elseif IsSubfolderStructure(folder_content) then
                            if r.ImGui_BeginMenu(ctx, folder_name) then
                                ShowCustomFolderMenu(folder_content, full_path)
                                r.ImGui_EndMenu(ctx)
                            end
                        end
                    end
                end
                
                ShowCustomFolderMenu(config.custom_folders)
                
                r.ImGui_Separator(ctx)
                if r.ImGui_MenuItem(ctx, "Create New Folder...") then
                    show_create_folder_popup = true
                    new_folder_for_plugin = plugin_name
                end
                
                r.ImGui_EndMenu(ctx)
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
                
                AddFXToTrack(new_track, plugin_name)
                r.CreateTrackSend(TRACK, new_track)
                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", plugin_name .. " Send", true)
            end
        end

        if r.ImGui_MenuItem(ctx, "Add with Multi-Output Setup") then
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                AddFXToTrack(TRACK, plugin_name)
                
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


function RemoveFXFromAllTracksByName(fx_name, include_master)
    if not fx_name or fx_name == '' then return end
    r.Undo_BeginBlock()
    -- Optionally remove from master
    if include_master then
        local master = r.GetMasterTrack(0)
        if master and r.ValidatePtr(master, "MediaTrack*") then
            while true do
                local idx = r.TrackFX_GetByName(master, fx_name, false)
                if not idx or idx < 0 then break end
                r.TrackFX_Delete(master, idx)
            end
        end
    end
    -- Remove from all normal tracks
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            while true do
                local idx = r.TrackFX_GetByName(tr, fx_name, false)
                if not idx or idx < 0 then break end
                r.TrackFX_Delete(tr, idx)
            end
        end
    end
    r.Undo_EndBlock("Remove '" .. fx_name .. "' from all tracks", -1)
end

function ShowFXContextMenu(plugin, menu_id)
    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "FXContextMenu_" .. menu_id)
    end

    if r.ImGui_BeginPopup(ctx, "FXContextMenu_" .. menu_id) then
        local track
        local fx_index

            r.ImGui_Text(ctx, "Rating:")
            ShowPluginRatingUI(plugin.fx_name)
            r.ImGui_Separator(ctx)

        if not plugin or not plugin.fx_name then
            r.ImGui_Text(ctx, "Invalid plugin data")
            r.ImGui_EndPopup(ctx)
            return
        end

        if selected_folder == "Current Project FX" then
            if plugin.is_master then
                track = r.GetMasterTrack(0)
                fx_index = plugin.fx_index
            else
                track = r.GetTrack(0, plugin.track_number - 1)
                fx_index = plugin.fx_index
            end
        else
            track = TRACK
            if track and r.ValidatePtr(track, "MediaTrack*") then
                fx_index = r.TrackFX_GetByName(track, plugin.fx_name, false)
            end
        end

        if not track or not r.ValidatePtr(track, "MediaTrack*") then
            r.ImGui_Text(ctx, "No valid track selected")
            r.ImGui_EndPopup(ctx)
            return
        end

        if not fx_index or fx_index < 0 then
            r.ImGui_Text(ctx, "Plugin not found on track")
            r.ImGui_EndPopup(ctx)
            return
        end

        if r.ImGui_MenuItem(ctx, "Delete") then
            r.TrackFX_Delete(track, fx_index)
        end

        -- Remove this plugin from all tracks (and master if the clicked instance is on master)
        if r.ImGui_MenuItem(ctx, "Remove from all tracks") then
            local include_master = (selected_folder == "Current Project FX" and plugin.is_master) or false
            RemoveFXFromAllTracksByName(plugin.fx_name, include_master)
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
                AddFXToTrack(track, orig_name)
            end
        end

        local is_enabled = r.TrackFX_GetEnabled(track, fx_index)
        if r.ImGui_MenuItem(ctx, is_enabled and "Bypass plugin" or "Unbypass plugin") then
            r.TrackFX_SetEnabled(track, fx_index, not is_enabled)
        end

    local fx_name = plugin.fx_name
    if favorite_set[fx_name] then
            if r.ImGui_MenuItem(ctx, "Remove from Favorites") then
                RemoveFromFavorites(fx_name)
            end
        else
            if r.ImGui_MenuItem(ctx, "Add to Favorites") then
                AddToFavorites(fx_name)
            end
        end

        -- ADD TO CUSTOM FOLDER SECTIE
        if next(config.custom_folders) then
            r.ImGui_Separator(ctx)
            if r.ImGui_BeginMenu(ctx, "Add to Custom Folder") then
                local function ShowCustomFolderMenu(folders, path_prefix)
                    path_prefix = path_prefix or ""
                    
                    for folder_name, folder_content in pairs(folders) do
                        local full_path = path_prefix == "" and folder_name or (path_prefix .. "/" .. folder_name)
                        
                        if IsPluginArray(folder_content) then
                            if r.ImGui_MenuItem(ctx, folder_name .. " (" .. #folder_content .. ")") then
                                if not table.contains(folder_content, fx_name) then
                                    table.insert(folder_content, fx_name)
                                    SaveCustomFolders()
                                    r.ShowMessageBox("Plugin added to " .. folder_name, "Success", 0)
                                else
                                    r.ShowMessageBox("Plugin already exists in " .. folder_name, "Info", 0)
                                end
                            end
                        elseif IsSubfolderStructure(folder_content) then
                            if r.ImGui_BeginMenu(ctx, folder_name) then
                                ShowCustomFolderMenu(folder_content, full_path)
                                r.ImGui_EndMenu(ctx)
                            end
                        end
                    end
                end
                
                ShowCustomFolderMenu(config.custom_folders)
                
                r.ImGui_Separator(ctx)
                if r.ImGui_MenuItem(ctx, "Create New Folder...") then
                    show_create_folder_popup = true
                    new_folder_for_plugin = fx_name
                end
                
                r.ImGui_EndMenu(ctx)
            end
        end

        r.ImGui_EndPopup(ctx)
    end
end

function ShowFolderDropdown()
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
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)   
        
        if r.ImGui_BeginCombo(ctx, "##FolderDropdown", selected_folder or "Select Folder") then
        
                if r.ImGui_Selectable(ctx, "Select Folder", selected_folder == nil) then
                    SelectFolderExclusive(nil)
                    screenshot_search_results = nil
                    RequestClearScreenshotCache()
                end

            if config.show_favorites and r.ImGui_Selectable(ctx, "Favorites", selected_folder == "Favorites") then
                SelectFolderExclusive("Favorites")
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                screenshot_search_results = nil
                RequestClearScreenshotCache()
                GetPluginsForFolder(selected_folder)
            end
            if r.ImGui_Selectable(ctx, "Current Track FX", selected_folder == "Current Track FX") then
                SelectFolderExclusive("Current Track FX")
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                RequestClearScreenshotCache()
                GetPluginsForFolder("Current Track FX")
            end
            
            if r.ImGui_Selectable(ctx, "Current Project FX", selected_folder == "Current Project FX") then
                SelectFolderExclusive("Current Project FX")
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                RequestClearScreenshotCache()
                screenshot_search_results = nil
                GetPluginsForFolder("Current Project FX") -- Forceer het laden
                current_filtered_fx = nil -- Reset filtered fx
            end
            if config.show_projects and r.ImGui_Selectable(ctx, "Projects", selected_folder == "Projects") then
                SelectFolderExclusive("Projects")
                show_media_browser = true
                show_sends_window = false
                show_action_browser = false
                RequestClearScreenshotCache()
            end
            if config.show_sends and r.ImGui_Selectable(ctx, "Sends/Receives", selected_folder == "Sends/Receives") then
                SelectFolderExclusive("Sends/Receives")
                show_media_browser = false
                show_sends_window = true
                show_action_browser = false
                RequestClearScreenshotCache()
            end
            if config.show_actions and r.ImGui_Selectable(ctx, "Actions", selected_folder == "Actions") then
                SelectFolderExclusive("Actions")
                show_media_browser = false
                show_sends_window = false
                show_action_browser = true
                ClearScreenshotCache()
            end
            if config.show_scripts and r.ImGui_Selectable(ctx, "Scripts", selected_folder == "Scripts") then
                SelectFolderExclusive("Scripts")
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                show_scripts_browser = true
                ClearScreenshotCache()
            end

            
            r.ImGui_Separator(ctx)
          
            if config.show_folders then
                for i = 1, #folders_category do
                    local is_selected = (selected_folder == folders_category[i].name)
                    if r.ImGui_Selectable(ctx, folders_category[i].name .. "##folder_" .. i, is_selected) then
                        SelectFolderExclusive(folders_category[i].name)
                        browser_panel_selected = nil -- deselect category/developer/all plugins
                        UpdateLastViewedFolder(selected_folder)
                        screenshot_search_results = nil
                        show_media_browser = false
                        show_sends_window = false
                        show_action_browser = false
                        show_scripts_browser = false
                        ClearScreenshotCache()
                        GetPluginsForFolder(selected_folder)
                    end
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
                SelectFolderExclusive(folders_category[current_index].name)
                UpdateLastViewedFolder(selected_folder)
                screenshot_search_results = nil
                ClearScreenshotCache()
                GetPluginsForFolder(selected_folder)
            end
        end
    
    end
end

function ShowCustomFolderDropdown()
    if next(config.custom_folders) then
        r.ImGui_SameLine(ctx)
        r.ImGui_PushItemWidth(ctx, 110)
        r.ImGui_SetNextWindowSizeConstraints(ctx, 0, 0, FLT_MAX, config.dropdown_menu_length * r.ImGui_GetTextLineHeightWithSpacing(ctx))
        
        if r.ImGui_BeginCombo(ctx, "##CustomFolderDropdown", "Custom") then
            -- Recursive functie om nested folders te tonen (MET SORTERING)
            local function ShowNestedFolders(folders, prefix)
                -- SORTEER DE FOLDER NAMEN ALFABETISCH
                local sorted_folder_names = {}
                for folder_name, _ in pairs(folders) do
                    table.insert(sorted_folder_names, folder_name)
                end
                table.sort(sorted_folder_names, function(a, b) 
                    return a:lower() < b:lower() 
                end)
                
                -- GEBRUIK DE GESORTEERDE NAMEN
                for _, folder_name in ipairs(sorted_folder_names) do
                    local folder_content = folders[folder_name]
                    local full_path = prefix == "" and folder_name or (prefix .. "/" .. folder_name)
                    
                    if IsPluginArray(folder_content) then
                        local display_name = prefix == "" and folder_name or ("  " .. folder_name)
                        if r.ImGui_Selectable(ctx, display_name .. " (" .. #folder_content .. ")", selected_folder == full_path) then
                            SelectFolderExclusive(full_path)
                            show_media_browser = false
                            show_sends_window = false
                            show_action_browser = false
                            screenshot_search_results = {}
                            for _, plugin in ipairs(folder_content) do
                                table.insert(screenshot_search_results, {name = plugin})
                            end
                            ClearScreenshotCache()
                        end
                    elseif IsSubfolderStructure(folder_content) then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF)
                        r.ImGui_Text(ctx, (prefix == "" and "" or "  ") .. folder_name .. " >")
                        r.ImGui_PopStyleColor(ctx)
                        
                        ShowNestedFolders(folder_content, full_path)
                    end
                end
            end
            
            ShowNestedFolders(config.custom_folders, "")
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_PopItemWidth(ctx)
    end
end

-- Forward declare helper so functions above can reference it as a local upvalue
local SortPlainPluginList

function SortScreenshotResults()
    if screenshot_search_results and #screenshot_search_results > 0 then
        -- When browsing a non-folder subgroup (ALL/DEVELOPER/CATEGORY), keep pinned-first and optional favorites-on-top
        if browser_panel_selected then
            local mode = (config and config.sort_mode) or screenshot_sort_mode or "alphabet"
            local names = {}
            for _, e in ipairs(screenshot_search_results) do
                if type(e) == 'table' and e.name and not e.is_message then
                    names[#names+1] = e.name
                end
            end
            -- Partition
            local pinned, favorites, others = {}, {}, {}
            for _, n in ipairs(names) do
                if IsPluginPinned and IsPluginPinned(n) then
                    pinned[#pinned+1] = n
                elseif favorite_set and favorite_set[n] then
                    favorites[#favorites+1] = n
                else
                    others[#others+1] = n
                end
            end
            SortPlainPluginList(pinned, mode)
            if config and config.show_favorites_on_top then
                SortPlainPluginList(favorites, mode)
            end
            SortPlainPluginList(others, mode)
            local ordered = {}
            
            -- Add pinned plugins first if show_pinned_on_top is enabled
            if config and config.show_pinned_on_top then
                for _, n in ipairs(pinned) do ordered[#ordered+1] = {name = n} end
                if #pinned > 0 and ((config and config.show_favorites_on_top and (#favorites>0 or #others>0)) or (not (config and config.show_favorites_on_top) and #others>0)) then
                    ordered[#ordered+1] = { is_separator = true, kind = "pinned_end" }
                end
            end
            
            if config and config.show_favorites_on_top then
                for _, n in ipairs(favorites) do ordered[#ordered+1] = {name = n} end
                if #favorites > 0 and #others > 0 then
                    ordered[#ordered+1] = { is_separator = true, kind = "favorites_end" }
                end
            else
                for _, n in ipairs(favorites) do others[#others+1] = n end
            end
            
            -- Add pinned plugins to others if show_pinned_on_top is disabled
            if not (config and config.show_pinned_on_top) then
                for _, n in ipairs(pinned) do others[#others+1] = n end
            end
            
            for _, n in ipairs(others) do ordered[#ordered+1] = {name = n} end
            screenshot_search_results = ordered
            return
        end

        local mode = (config and config.sort_mode) or screenshot_sort_mode or "alphabet"
        if mode == "alphabet" then
            table.sort(screenshot_search_results, function(a, b)
                return a.name:lower() < b.name:lower()
            end)
        elseif mode == "rating" then
            table.sort(screenshot_search_results, function(a, b)
                local ra = plugin_ratings[a.name] or 0
                local rb = plugin_ratings[b.name] or 0
                if ra == rb then
                    return a.name:lower() < b.name:lower()
                else
                    return ra > rb
                end
            end)
        end
    end
end

function SortPlainPluginList(list, mode)
    if not list or #list == 0 then return end
    local effective_mode = mode or screenshot_sort_mode or "alphabet"
    if effective_mode == "rating" then
        table.sort(list, function(a,b)
            local ra = plugin_ratings[a] or 0
            local rb = plugin_ratings[b] or 0
            if ra == rb then
                return a:lower() < b:lower()
            else
                return ra > rb
            end
        end)
    else 
        table.sort(list, function(a,b) return a:lower() < b:lower() end)
    end
end

function ShowScreenshotControls()
    r.ImGui_SameLine(ctx)
    ShowFolderDropdown()
    if not config.hide_custom_dropdown then
        ShowCustomFolderDropdown()
    end
    show_screenshot_search = config.show_screenshot_search ~= false
    if show_screenshot_search then
        r.ImGui_SameLine(ctx)
        r.ImGui_PushItemWidth(ctx, 70)
    local changed, new_search = r.ImGui_InputTextWithHint(ctx, "##ScreenshotSearch", "Search...", browser_search_term)
        r.ImGui_PopItemWidth(ctx)
        r.ImGui_SameLine(ctx)

        screenshot_sort_mode = screenshot_sort_mode or "alphabet"
        local effective_mode = (config and config.sort_mode) or screenshot_sort_mode
        local sort_label = (effective_mode == "alphabet") and "A" or "R"
        if r.ImGui_Button(ctx, sort_label, 20, 20) then
            -- Toggle the main sort when available to keep UI in sync
            if config then
                config.sort_mode = (effective_mode == "alphabet") and "rating" or "alphabet"
                if SaveConfig then SaveConfig() end
            else
                screenshot_sort_mode = (effective_mode == "alphabet") and "rating" or "alphabet"
            end
            SortScreenshotResults()
        end
        if r.ImGui_IsItemHovered(ctx) then
            if effective_mode == "alphabet" then
                r.ImGui_SetTooltip(ctx, "Alphabetic sorting (click to switch to Rating)")
            else
                r.ImGui_SetTooltip(ctx, "Rating sorting (click to switch to Alphabetic)")
            end
        end

        r.ImGui_SameLine(ctx)
        if browser_search_term == "" then
            r.ImGui_BeginDisabled(ctx)
        end
    if r.ImGui_Button(ctx, "All", 20, 20) then
            screenshot_search_results = {}
            local MAX_RESULTS = 200
            local term = browser_search_term:lower()
            local matches = {}
            for _, plugin in ipairs(PLUGIN_LIST) do
                if plugin:lower():find(term, 1, true) then
                    table.insert(matches, plugin)
                end
            end
            if config.apply_type_priority then
                matches = DedupeByTypePriority(matches)
            end
            local total = #matches
            local limit = math.min(total, MAX_RESULTS)
            for i = 1, limit do
                table.insert(screenshot_search_results, { name = matches[i] })
            end

            SortScreenshotResults()
            if total > MAX_RESULTS then
                search_warning_message = "First " .. MAX_RESULTS .. " results. Refine your search for more results."
            end
            new_search_performed = true
            selected_folder = nil
            browser_panel_selected = nil
            last_selected_folder_before_global = nil
            RequestClearScreenshotCache()
        end
        if browser_search_term == "" then
            r.ImGui_EndDisabled(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Search all plugins (ignores folder selection)")
        end

        if changed then
            browser_search_term = new_search
            if config.flicker_guard_enabled then _last_search_input_time = r.time_precise() end
            if browser_search_term == "" then
                screenshot_search_results = {}
                search_warning_message = nil
                if current_filtered_fx and #current_filtered_fx > 0 then
                    for _, plugin in ipairs(current_filtered_fx) do
                        table.insert(screenshot_search_results, {name = plugin})
                    end
                elseif selected_folder then
                    local filtered_plugins = GetPluginsForFolder(selected_folder)
                    for _, plugin in ipairs(filtered_plugins) do
                        table.insert(screenshot_search_results, {name = plugin})
                    end
                end
                SortScreenshotResults()
                RequestClearScreenshotCache()
                new_search_performed = true
            else
                screenshot_search_results = {}
                loaded_items_count = ITEMS_PER_BATCH
                search_warning_message = nil

                local MAX_RESULTS = 200
                local too_many_results = false

                local source_list = nil
                if current_filtered_fx and #current_filtered_fx > 0 then
                    source_list = current_filtered_fx
                elseif selected_folder or browser_panel_selected then
                    local folder_to_search = browser_panel_selected or selected_folder
                    source_list = GetPluginsForFolder(folder_to_search)
                end
                if source_list then
                    local count = 0
                    local term_l = browser_search_term:lower()
                    local matches = {}
                    for _, plugin in ipairs(source_list) do
                        if plugin:lower():find(term_l, 1, true) then
                            matches[#matches+1] = plugin
                        end
                    end
                    if config.apply_type_priority then
                        matches = DedupeByTypePriority(matches)
                    end
                    -- When browsing a non-folder subgroup (ALL/DEVELOPER/CATEGORY), apply pinned/favorites-first ordering
                    if browser_panel_selected then
                        local pinned, favorites, others = {}, {}, {}
                        for _, p in ipairs(matches) do
                            if IsPluginPinned and IsPluginPinned(p) then
                                pinned[#pinned+1] = p
                            elseif favorite_set and favorite_set[p] then
                                favorites[#favorites+1] = p
                            else
                                others[#others+1] = p
                            end
                        end
                        SortPlainPluginList(pinned, (config and config.sort_mode) or screenshot_sort_mode or "alphabet")
                        if config and config.show_favorites_on_top then
                            SortPlainPluginList(favorites, (config and config.sort_mode) or screenshot_sort_mode or "alphabet")
                        end
                        SortPlainPluginList(others, (config and config.sort_mode) or screenshot_sort_mode or "alphabet")
                        local ordered = {}
                        
                        -- Add pinned plugins first if show_pinned_on_top is enabled
                        if config and config.show_pinned_on_top then
                            for _, p in ipairs(pinned) do ordered[#ordered+1] = p end
                            if #pinned > 0 and ((config and config.show_favorites_on_top and (#favorites>0 or #others>0)) or (not (config and config.show_favorites_on_top) and #others>0)) then
                                ordered[#ordered+1] = "--Pinned End--"
                            end
                        end
                        
                        if config and config.show_favorites_on_top then
                            for _, p in ipairs(favorites) do ordered[#ordered+1] = p end
                            if #favorites > 0 and #others > 0 then
                                ordered[#ordered+1] = "--Favorites End--"
                            end
                        else
                            for _, p in ipairs(favorites) do others[#others+1] = p end
                        end
                        
                        -- Add pinned plugins to others if show_pinned_on_top is disabled
                        if not (config and config.show_pinned_on_top) then
                            for _, p in ipairs(pinned) do others[#others+1] = p end
                        end
                        
                        for _, p in ipairs(others) do ordered[#ordered+1] = p end
                        matches = ordered
                    end

                    for i = 1, math.min(MAX_RESULTS, #matches) do
                        screenshot_search_results[#screenshot_search_results+1] = { name = matches[i] }
                    end
                    count = #matches
                    too_many_results = (count > MAX_RESULTS)
                end

                -- Keep explicit subgroup ordering; only apply generic sort when not in a subgroup
                if not browser_panel_selected then
                    SortScreenshotResults()
                end
                RequestClearScreenshotCache()
                if too_many_results then
                    search_warning_message = "Showing first " .. MAX_RESULTS .. " results. Please refine your search for more specific results."
                end

                new_search_performed = true
            end
        end
   
    end

    local window_width = r.ImGui_GetWindowWidth(ctx)
    local button_width = 20
    local button_height = 20

    r.ImGui_SetCursorPos(ctx, window_width - button_width - 2, -2)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    r.ImGui_PushFont(ctx, IconFont, 12)
    if r.ImGui_Button(ctx, "\u{0047}", button_height, button_width) then
        r.ImGui_OpenPopup(ctx, "ScreenshotControlsMenu")
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleColor(ctx, 3)

    if r.ImGui_BeginPopup(ctx, "ScreenshotControlsMenu") then
        -- Version header for the screenshot window settings
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
        r.ImGui_Text(ctx, "TK FX BROWSER  v" .. GetScriptVersion())
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_Separator(ctx)
        -- VISIBILITY SUBMENU
        if r.ImGui_BeginMenu(ctx, "Visibility") then
            if r.ImGui_MenuItem(ctx, config.show_name_in_screenshot_window and "Hide Names" or "Show Names") then
                config.show_name_in_screenshot_window = not config.show_name_in_screenshot_window; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, (config.show_screenshot_info_box and "Hide" or "Show") .. " Info Box") then
                config.show_screenshot_info_box = not config.show_screenshot_info_box; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, config.show_screenshot_scrollbar and "Hide Scrollbar" or "Show Scrollbar") then
                config.show_screenshot_scrollbar = not config.show_screenshot_scrollbar; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, config.show_browser_panel and "Hide Browser Panel" or "Show Browser Panel") then
                config.show_browser_panel = not config.show_browser_panel; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, config.hide_main_window and "Show Main Window" or "Hide Main Window") then
                config.hide_main_window = not config.hide_main_window; config.show_main_window = not config.hide_main_window; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, (config.show_missing_list ~= false) and "Hide Missing List" or "Show Missing List") then
                config.show_missing_list = not (config.show_missing_list ~= false); SaveConfig()
            end
            r.ImGui_EndMenu(ctx)
        end

        -- SEARCH & DROPDOWNS
        if r.ImGui_BeginMenu(ctx, "Search & Folders") then
            if r.ImGui_MenuItem(ctx, (config.show_screenshot_search and "Hide" or "Show") .. " Search Bar") then
                config.show_screenshot_search = not config.show_screenshot_search; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, (config.show_browser_search and "Hide" or "Show") .. " Browser Search") then
                config.show_browser_search = not config.show_browser_search; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, config.hide_custom_dropdown and "Show Custom Dropdown" or "Hide Custom Dropdown") then
                config.hide_custom_dropdown = not config.hide_custom_dropdown; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, config.screenshot_view_type == 3 and "Show Dropdown" or "Hide Dropdown") then
                config.screenshot_view_type = config.screenshot_view_type == 3 and 1 or 3
                if config.screenshot_view_type == 1 then
                    config.show_screenshot_settings = true; config.show_only_dropdown = false
                else
                    config.show_screenshot_settings = false; config.show_only_dropdown = false
                end; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, "Respect PM exclusion", "", config.respect_search_exclusions_in_screenshots) then
                config.respect_search_exclusions_in_screenshots = not config.respect_search_exclusions_in_screenshots
                ClearScreenshotCache()
                if screenshot_search_results and #screenshot_search_results > 0 and config.respect_search_exclusions_in_screenshots then
                    local filtered = {}
                    for i=1,#screenshot_search_results do
                        local entry = screenshot_search_results[i]
                        local pname = entry and entry.name or entry
                        if pname and not config.excluded_plugins[pname] then
                            filtered[#filtered+1] = entry
                        end
                    end
                    screenshot_search_results = filtered
                end
                SaveConfig()
            end
            r.ImGui_EndMenu(ctx)
        end

        -- LAYOUT MENU
        if r.ImGui_BeginMenu(ctx, "Layout") then
            if r.ImGui_MenuItem(ctx, config.use_masonry_layout and "Normal Layout" or "Masonry Layout") then
                config.use_masonry_layout = not config.use_masonry_layout; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, "Compact View", "", config.compact_screenshots) then
                config.compact_screenshots = not config.compact_screenshots; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, config.resize_screenshots_with_window and "Manual Size" or "Resize With Window") then
                config.resize_screenshots_with_window = not config.resize_screenshots_with_window; SaveConfig()
            end
            if r.ImGui_MenuItem(ctx, "Pagination", "", config.use_pagination) then
                config.use_pagination = not config.use_pagination; SaveConfig()
            end
            r.ImGui_EndMenu(ctx)
        end

        -- SIZE MENU
        if r.ImGui_BeginMenu(ctx, "Size") then
            if r.ImGui_MenuItem(ctx, "Use Global Size", "", config.use_global_screenshot_size) then
                config.use_global_screenshot_size = not config.use_global_screenshot_size; SaveConfig()
            end
            if config.use_global_screenshot_size then
                r.ImGui_PushItemWidth(ctx, 160)
                local changed, new_size = r.ImGui_SliderInt(ctx, "Global Size", config.global_screenshot_size, 100, 500)
                if changed then config.global_screenshot_size = new_size; display_size = new_size; SaveConfig() end
                r.ImGui_PopItemWidth(ctx)
                if r.ImGui_MenuItem(ctx, "Reset Global Size") then
                    config.global_screenshot_size = 200; display_size = 200; SaveConfig()
                end
            else
                if not config.resize_screenshots_with_window then
                    local folder_key = selected_folder or (screenshot_search_results and "SearchResults") or "Default"
                    local current_size = config.folder_specific_sizes[folder_key] or config.screenshot_window_size
                    r.ImGui_PushItemWidth(ctx, 160)
                    local changed, new_size = r.ImGui_SliderInt(ctx, "Folder Size", current_size, 100, 500)
                    if changed then config.folder_specific_sizes[folder_key] = new_size; display_size = new_size; SaveConfig() end
                    r.ImGui_PopItemWidth(ctx)
                    if r.ImGui_MenuItem(ctx, "Reset Folder Size") then
                        config.folder_specific_sizes[folder_key] = nil; display_size = config.screenshot_window_size; SaveConfig()
                    end
                end
            end
            r.ImGui_EndMenu(ctx)
        end

        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Open Main Settings") then show_settings = true end
        if r.ImGui_MenuItem(ctx, "Close Window") then config.show_screenshot_window = false; SaveConfig() end
        r.ImGui_EndPopup(ctx)
    end
end

function DrawFxChains(tbl, path)
    local extension = ".RfxChain"
    path = path or ""
    local i = 1
    while i <= #tbl do
        local item = tbl[i]
        if type(item) == "table" and item.dir then
            -- SUBMAPPEN HANDELEN
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)  
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), config.background_color) 
            if r.ImGui_BeginMenu(ctx, item.dir) then               
                -- RECURSIEF SUBMAPPEN DOORLOPEN
                DrawFxChains(item, table.concat({ path, os_separator, item.dir }))              
                r.ImGui_EndMenu(ctx)               
            end  
            reaper.ImGui_PopStyleColor(ctx)
        elseif type(item) == "string" then
            -- NORMALE FX CHAIN FILES
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
                        AddFXToTrack(TRACK, table.concat({ path, os_separator, item, extension }))
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
                        local fx_chains_path = ResolveFxChainsRoot()
                        local old_path = fx_chains_path .. path .. os_separator .. item .. extension
                        local new_path = fx_chains_path .. path .. os_separator .. new_name .. extension
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
                    local fx_chains_path = ResolveFxChainsRoot()
                    local file_path = fx_chains_path .. path .. os_separator .. item .. extension
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
        elseif type(item) == "table" and not item.dir then
            for j = 1, #item do
                if type(item[j]) == "string" then
                    if r.ImGui_Selectable(ctx, item[j] .. "##fxchain_" .. i .. "_" .. j) then
                        if ADD_FX_TO_ITEM then
                            local selected_item = r.GetSelectedMediaItem(0, 0)
                            if selected_item then
                                local take = r.GetActiveTake(selected_item)
                                if take then
                                    r.TakeFX_AddByName(take, table.concat({ path, os_separator, item[j], extension }), 1)
                                end
                            end
                        else
                            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                AddFXToTrack(TRACK, table.concat({ path, os_separator, item[j], extension }))
                                if config.close_after_adding_fx then
                                    SHOULD_CLOSE_SCRIPT = true
                                end
                            end
                        end
                    end
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        r.ImGui_OpenPopup(ctx, "FXChainOptions_" .. i .. "_" .. j)
                    end
                    if r.ImGui_BeginPopup(ctx, "FXChainOptions_" .. i .. "_" .. j) then
                        if r.ImGui_MenuItem(ctx, "Rename") then
                            local retval, new_name = r.GetUserInputs("Rename FX Chain", 1, "New name:", item[j])
                            if retval then
                                local fx_chains_path = ResolveFxChainsRoot()
                                local old_path = fx_chains_path .. path .. os_separator .. item[j] .. extension
                                local new_path = fx_chains_path .. path .. os_separator .. new_name .. extension
                                if os.rename(old_path, new_path) then
                                    item[j] = new_name
                                    FX_LIST_TEST, CAT_TEST = MakeFXFiles()  
                                    r.ShowMessageBox("FX Chain renamed", "Success", 0)
                                else
                                    r.ShowMessageBox("Could not rename FX Chain", "Error", 0)
                                end
                            end
                        end
                        if r.ImGui_MenuItem(ctx, "Delete") then
                            local fx_chains_path = ResolveFxChainsRoot()
                            local file_path = fx_chains_path .. path .. os_separator .. item[j] .. extension
                            if os.remove(file_path) then
                                table.remove(item, j)
                                FX_LIST_TEST, CAT_TEST = MakeFXFiles() 
                                r.ShowMessageBox("FX Chain deleted", "Success", 0)
                            else
                                r.ShowMessageBox("Could not delete FX Chain", "Error", 0)
                            end
                        end
                        r.ImGui_EndPopup(ctx)
                    end
                end
            end
        end
        i = i + 1
    end
end

function LoadTemplate(template_path)
    local full_path = ResolveTrackTemplatesRoot() .. template_path
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

function DrawTrackTemplates(tbl, path)
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
                        local templates_path = ResolveTrackTemplatesRoot()
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
                    local templates_path = ResolveTrackTemplatesRoot()
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

function DrawBrowserItems(tbl, main_cat_name)
    local function EnsurePinnedList(cat)
        if not config.pinned_subgroups then config.pinned_subgroups = {} end
        if not config.pinned_subgroups[cat] then config.pinned_subgroups[cat] = {} end
        return config.pinned_subgroups[cat]
    end
    local function IsSubgroupPinned(cat, name)
        local lst = EnsurePinnedList(cat)
        for _, n in ipairs(lst) do if n == name then return true end end
        return false
    end
    local function PinSubgroup(cat, name)
        local lst = EnsurePinnedList(cat)
        if not IsSubgroupPinned(cat, name) then table.insert(lst, name); SaveConfig() end
    end
    local function UnpinSubgroup(cat, name)
        local lst = EnsurePinnedList(cat)
        for i=#lst,1,-1 do if lst[i] == name then table.remove(lst, i); SaveConfig(); break end end
    end
    local function BuildSubgroupDrawOrder(cat, items)
        local index_by_name = {}
        for i = 1, #items do index_by_name[items[i].name] = i end
        local order = {}
        local pinned = EnsurePinnedList(cat)
        for _, name in ipairs(pinned) do
            local idx = index_by_name[name]
            if idx then table.insert(order, idx) end
        end
        local pinned_set = {}
        for _, name in ipairs(pinned) do pinned_set[name] = true end
        for i = 1, #items do
            local nm = items[i].name
            if not pinned_set[nm] then table.insert(order, i) end
        end
        return order
    end

    local draw_order = BuildSubgroupDrawOrder(main_cat_name or "", tbl)
    for _, i in ipairs(draw_order) do
        local filtered_fx = {}
        for _, fx in ipairs(tbl[i].fx) do
            if browser_search_term == "" or fx:lower():find(browser_search_term:lower(), 1, true) then
                table.insert(filtered_fx, fx)
            end
        end

    filtered_fx = DedupeByTypePriority(filtered_fx)

    -- Apply subgroup ordering: pinned first, then favorites (optional), then others
    do
        local pinned = {}
        local favorites = {}
        local others = {}
        for _, fx in ipairs(filtered_fx) do
            if IsPluginPinned and IsPluginPinned(fx) then
                pinned[#pinned+1] = fx
            elseif favorite_set and favorite_set[fx] then
                favorites[#favorites+1] = fx
            else
                others[#others+1] = fx
            end
        end
        -- Sort each bucket by current sort mode (alphabet or rating)
        SortPlainPluginList(pinned, (config and config.sort_mode) or sort_mode or "alphabet")
        if config and config.show_favorites_on_top then
            SortPlainPluginList(favorites, (config and config.sort_mode) or sort_mode or "alphabet")
        end
        SortPlainPluginList(others, (config and config.sort_mode) or sort_mode or "alphabet")

        local reordered = {}
        
        -- Add pinned plugins first if show_pinned_on_top is enabled
        if config and config.show_pinned_on_top then
            for _, fx in ipairs(pinned) do reordered[#reordered+1] = fx end
        end
        
        if config and config.show_favorites_on_top then
            for _, fx in ipairs(favorites) do reordered[#reordered+1] = fx end
        else
            -- If not showing favorites on top, merge favorites into others
            for _, fx in ipairs(favorites) do others[#others+1] = fx end
        end
        
        -- Add pinned plugins to others if show_pinned_on_top is disabled
        if not (config and config.show_pinned_on_top) then
            for _, fx in ipairs(pinned) do others[#others+1] = fx end
        end
        
        for _, fx in ipairs(others) do reordered[#reordered+1] = fx end
        filtered_fx = reordered
    end

        if #filtered_fx > 0 then
            r.ImGui_PushID(ctx, i)
            r.ImGui_Indent(ctx, 10)
            local subgroup_name = tbl[i].name
            local header_text = subgroup_name
            if IsSubgroupPinned(main_cat_name or "", subgroup_name) then
                header_text = "\xF0\x9F\x93\x8C " .. header_text  -- "📌 "
            end
            local is_selected = (browser_panel_selected == tbl[i].name)
            if is_selected then
                local dl = r.ImGui_GetWindowDrawList(ctx)
                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
            end
            if r.ImGui_Selectable(ctx, header_text .. "##browseritem_" .. i, is_selected) then
                SelectBrowserPanelItem(tbl[i].name)
                UpdateLastViewedFolder(tbl[i].name)
                loaded_items_count = ITEMS_PER_BATCH
                current_filtered_fx = filtered_fx 
                screenshot_search_results = {}
                if config.use_pagination then
                    local start_idx = (tbl[i].current_page - 1) * ITEMS_PER_PAGE + 1
                    local end_idx = math.min(start_idx + ITEMS_PER_PAGE - 1, #filtered_fx)
                    for j = start_idx, end_idx do
                        table.insert(screenshot_search_results, {name = filtered_fx[j]})
                    end
                    SortScreenshotResults()
                else
                    if view_mode == "list" then
                        for j = 1, #filtered_fx do
                            table.insert(screenshot_search_results, {name = filtered_fx[j]})
                        end
                    else
                        for j = 1, math.min(loaded_items_count, #filtered_fx) do
                            table.insert(screenshot_search_results, {name = filtered_fx[j]})
                        end
                    end
                    SortScreenshotResults()
                end
                ClearScreenshotCache()
            end
            r.ImGui_Unindent(ctx, 10)

            if not tbl[i].current_page then tbl[i].current_page = 1 end
            local total_pages = math.ceil(#filtered_fx / ITEMS_PER_PAGE)

            if r.ImGui_IsItemClicked(ctx, 1) then
                local popup_id = "browser_item_ctx_" .. tostring(main_cat_name or "") .. "_" .. i
                r.ImGui_OpenPopup(ctx, popup_id)
            end
            local popup_id = "browser_item_ctx_" .. tostring(main_cat_name or "") .. "_" .. i
            if r.ImGui_BeginPopup(ctx, popup_id) then
                local toggle_label = (view_mode == "screenshots" and "Show List" or "Show Screenshots")
                if r.ImGui_MenuItem(ctx, toggle_label) then
                    local previous_mode = view_mode
                    view_mode = (view_mode == "screenshots" and "list" or "screenshots")
                    if view_mode == "screenshots" then
                        if previous_mode ~= "screenshots" then RequestClearScreenshotCache() end
                    else
                        if current_filtered_fx and #current_filtered_fx > 0 then
                            screenshot_search_results = {}
                            for j = 1, #current_filtered_fx do
                                table.insert(screenshot_search_results, {name = current_filtered_fx[j]})
                            end
                        end
                    end
                end
                -- Pin / Unpin submenu
                if IsSubgroupPinned(main_cat_name or "", subgroup_name) then
                    if r.ImGui_MenuItem(ctx, "Unpin Subgroup") then
                        UnpinSubgroup(main_cat_name or "", subgroup_name)
                        if r.ImGui_CloseCurrentPopup then r.ImGui_CloseCurrentPopup(ctx) end
                    end
                else
                    if r.ImGui_MenuItem(ctx, "Pin Subgroup") then
                        PinSubgroup(main_cat_name or "", subgroup_name)
                        if r.ImGui_CloseCurrentPopup then r.ImGui_CloseCurrentPopup(ctx) end
                    end
                end
                if r.ImGui_MenuItem(ctx, "Capture Folder Screenshots") then
                    StartFolderScreenshots(subgroup_name)
                end
                r.ImGui_EndPopup(ctx)
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
                    SortScreenshotResults()
                    RequestClearScreenshotCache()
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
                    SortScreenshotResults()
                    RequestClearScreenshotCache()
                end
                r.ImGui_Unindent(ctx, 20)
            end

            if tbl[i].is_open then
                r.ImGui_Indent(ctx, 20)
                if config.use_pagination then
                    local start_idx = (tbl[i].current_page - 1) * ITEMS_PER_PAGE + 1
                    local end_idx = math.min(start_idx + ITEMS_PER_PAGE - 1, #filtered_fx)
                    for j = start_idx, end_idx do
                        local display_name = GetDisplayPluginName(filtered_fx[j])
                        if r.ImGui_Selectable(ctx, display_name .. "  " .. GetStarsString(filtered_fx[j])) then
                            selected_folder = nil
                            selected_individual_item = filtered_fx[j]
                            screenshot_search_results = {{name = filtered_fx[j]}}
                            RequestClearScreenshotCache()
                        end
                        ShowPluginContextMenu(filtered_fx[j], "unique_id_" .. i .. "_" .. j)
                    end
                else
                    for j = 1, #filtered_fx do
                        local display_name = GetDisplayPluginName(filtered_fx[j])
                        if r.ImGui_Selectable(ctx, display_name .. "  " .. GetStarsString(filtered_fx[j])) then
                            selected_folder = nil
                            selected_individual_item = filtered_fx[j]
                            screenshot_search_results = {{name = filtered_fx[j]}}
                            RequestClearScreenshotCache()
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



function ItemMatchesSearch(item_name, search_term)
    search_term = search_term or ""
    if search_term == "" then return true end
    return item_name:lower():find(search_term:lower(), 1, true)
end

-- CUSTOM FOLDERS (NESTED)
function DisplayCustomFoldersInBrowser(folders, path_prefix)
    path_prefix = path_prefix or ""
    local function IsCustomPinned(full_path)
        if not config.pinned_custom_subfolders then return false end
        for _, p in ipairs(config.pinned_custom_subfolders) do if p == full_path then return true end end
        return false
    end
    local function PinCustom(full_path)
        config.pinned_custom_subfolders = config.pinned_custom_subfolders or {}
        if not IsCustomPinned(full_path) then table.insert(config.pinned_custom_subfolders, full_path); SaveConfig() end
    end
    local function UnpinCustom(full_path)
        if not config.pinned_custom_subfolders then return end
        for i=#config.pinned_custom_subfolders,1,-1 do
            if config.pinned_custom_subfolders[i] == full_path then table.remove(config.pinned_custom_subfolders, i); SaveConfig(); break end
        end
    end
    
    local sorted_folder_names = {}
    for folder_name, _ in pairs(folders) do table.insert(sorted_folder_names, folder_name) end
    table.sort(sorted_folder_names, function(a, b)
        local pa = (path_prefix == "" and a or (path_prefix .. "/" .. a))
        local pb = (path_prefix == "" and b or (path_prefix .. "/" .. b))
        local ia = IsCustomPinned(pa)
        local ib = IsCustomPinned(pb)
        if ia ~= ib then return ia end -- pinned eerst
        return a:lower() < b:lower()
    end)
    
    -- GEBRUIK DE GESORTEERDE NAMEN
    for _, folder_name in ipairs(sorted_folder_names) do
        local folder_content = folders[folder_name]
        local full_path = path_prefix == "" and folder_name or (path_prefix .. "/" .. folder_name)
        
        if IsPluginArray(folder_content) then
            local is_selected = (selected_folder == full_path)
            local is_pinned = IsCustomPinned(full_path)
            if is_selected then
                local dl = r.ImGui_GetWindowDrawList(ctx)
                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                local text_w = r.ImGui_CalcTextSize(ctx, folder_name:upper())
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
            end
            local label = (is_pinned and "\xF0\x9F\x93\x8C " or "") .. folder_name:upper()
            if r.ImGui_Selectable(ctx, label, is_selected) then
                browser_panel_selected = nil
                selected_folder = full_path
                UpdateLastViewedFolder(full_path)
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                screenshot_search_results = {}
                local term_l = browser_search_term:lower()
                local matches = {}
                for _, plugin in ipairs(folder_content) do
                    if plugin:lower():find(term_l, 1, true) then
                        matches[#matches+1] = plugin
                    end
                end
                if config.apply_type_priority then
                    matches = DedupeByTypePriority(matches)
                end
                for i = 1, #matches do
                    screenshot_search_results[#screenshot_search_results+1] = { name = matches[i] }
                end
                ClearScreenshotCache()
            end

            if r.ImGui_IsItemClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "FolderContextMenu_" .. full_path)
            end
            if r.ImGui_BeginPopup(ctx, "FolderContextMenu_" .. full_path) then
                if r.ImGui_MenuItem(ctx, "Create Parent Folder Above") then
                    show_create_parent_folder_popup = true
                    selected_folder_for_parent = full_path
                    selected_folder_name = folder_name
                end
                local toggle_label = (view_mode == "screenshots" and "Show List" or "Show Screenshots")
                if r.ImGui_MenuItem(ctx, toggle_label) then
                    local prev = view_mode
                    view_mode = (view_mode == "screenshots" and "list" or "screenshots")
                    if view_mode == "screenshots" and prev ~= "screenshots" then ClearScreenshotCache() end
                end
                if is_pinned then
                    if r.ImGui_MenuItem(ctx, "Unpin Folder") then UnpinCustom(full_path) end
                else
                    if r.ImGui_MenuItem(ctx, "Pin Folder") then PinCustom(full_path) end
                end
                if r.ImGui_MenuItem(ctx, "Capture Folder Screenshots") then
                    StartFolderScreenshots(full_path)
                end
                r.ImGui_EndPopup(ctx)
            end
            
        else
            if custom_folders_open[full_path] then
                r.ImGui_Indent(ctx, 1)
                for i, plugin in ipairs(folder_content) do
                    local display_plugin = GetDisplayPluginName(plugin)
                    if r.ImGui_Selectable(ctx, display_plugin .. "  " .. GetStarsString(plugin)) then
                        selected_folder = nil
                        selected_individual_item = plugin
                        screenshot_search_results = {{name = plugin}}
                        ClearScreenshotCache()
                    end
                    ShowPluginContextMenu(plugin, "custom_" .. full_path .. "_" .. i)
                end
                r.ImGui_Unindent(ctx, 1)
            end
        end

        if IsSubfolderStructure(folder_content) then
            local original_cursor_x = r.ImGui_GetCursorPosX(ctx)
            r.ImGui_SetCursorPosX(ctx, math.max(original_cursor_x - 8, -2))
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemInnerSpacing(), 0, 0)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 3, 3)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
            local tree_is_selected = (selected_folder == full_path) or (selected_folder and selected_folder:sub(1, #full_path) == full_path and selected_folder:find("/", #full_path+1))
            local tree_flags = r.ImGui_TreeNodeFlags_Framed() | r.ImGui_TreeNodeFlags_SpanAvailWidth() | r.ImGui_TreeNodeFlags_FramePadding()
            if tree_is_selected then
                tree_flags = tree_flags | r.ImGui_TreeNodeFlags_Selected()
                local dl = r.ImGui_GetWindowDrawList(ctx)
                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                r.ImGui_DrawList_AddRectFilled(dl, x, y, x + avail_w, y + line_h, 0xFF704030, 3)
            end
            local display_label = ((IsCustomPinned(full_path) and "\xF0\x9F\x93\x8C ") or "") .. folder_name:upper()
            if auto_expand_paths and auto_expand_paths[full_path] then
                r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_Once())
            end
            local tree_id = full_path .. "##customTree"
            local open = r.ImGui_TreeNodeEx(ctx, tree_id, "", tree_flags)
            local item_min_x, item_min_y = r.ImGui_GetItemRectMin(ctx)
            local line_h = r.ImGui_GetTextLineHeight(ctx)
            local text_w, text_h = r.ImGui_CalcTextSize(ctx, display_label)
            local spacing = r.ImGui_GetTreeNodeToLabelSpacing(ctx)
            local text_x = item_min_x + math.max(spacing - 3, 0)
            local text_y = item_min_y + (line_h - text_h) * 0.5 + 3
            local text_col = r.ImGui_GetColor(ctx, r.ImGui_Col_Text())
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_col, display_label)
            if open then
                r.ImGui_Indent(ctx, 1)
                DisplayCustomFoldersInBrowser(folder_content, full_path)
                r.ImGui_Unindent(ctx, 1)
                r.ImGui_TreePop(ctx)
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_SetCursorPosX(ctx, original_cursor_x)
            r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) - 2)
        end
    end
end

footer_resize_active = footer_resize_active or false
footer_last_mouse_y  = footer_last_mouse_y or 0

function ShowBrowserPanel()
    if not config.show_browser_panel then return end

    if not initial_header_auto_expand_done
       and config.default_folder == LAST_OPENED_SENTINEL
       and last_viewed_folder
       and not (force_open_all_plugins_header or force_open_developer_header or force_open_category_header or force_open_folders_header) then
        MarkForcedHeaderForSubgroup(last_viewed_folder)
    end

    config.browser_footer_height = math.max(20, config.browser_footer_height or 150)
    local BROWSER_FOOTER_HEIGHT = config.browser_footer_height
    local browser_panel_start_y = r.ImGui_GetCursorPosY(ctx)
    browser_footer_text = browser_footer_text or "INFO BOX"
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    r.ImGui_BeginChild(ctx, "BrowserSection", config.browser_panel_width, -1)
    local section_pos_y = r.ImGui_GetCursorScreenPos(ctx)
    local section_start_y = section_pos_y 

    -- Header
    local header_open = r.ImGui_BeginChild(ctx, "BrowserHeader", -1, config.show_browser_search and 25 or 4)
    if header_open then
    if config.show_browser_search then
        r.ImGui_PushItemWidth(ctx, 70)
        local changed_browser_search, new_browser_search = r.ImGui_InputTextWithHint(ctx, "##BrowserSearch", "Search...", browser_search_term)
        r.ImGui_PopItemWidth(ctx)
        if changed_browser_search then
            browser_search_term = new_browser_search
        end
        r.ImGui_SameLine(ctx)
        screenshot_sort_mode = screenshot_sort_mode or "alphabet"
        local effective_mode = (config and config.sort_mode) or screenshot_sort_mode
        local sort_label = (effective_mode == "alphabet") and "A" or "R"
        if r.ImGui_Button(ctx, sort_label, 20, 20) then
            if config then
                config.sort_mode = (effective_mode == "alphabet") and "rating" or "alphabet"
                if SaveConfig then SaveConfig() end
            else
                screenshot_sort_mode = (effective_mode == "alphabet") and "rating" or "alphabet"
            end
            SortScreenshotResults()
        end
        if r.ImGui_IsItemHovered(ctx) then
            if effective_mode == "alphabet" then
                r.ImGui_SetTooltip(ctx, "Alphabetic sorting (click to switch to Rating)")
            else
                r.ImGui_SetTooltip(ctx, "Rating sorting (click to switch to Alphabetic)")
            end
        end
        r.ImGui_SameLine(ctx)
        if browser_search_term == "" then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx, "All", 20, 20) then
            local MAX_RESULTS = 250
            local too_many_results = false
            local term_l = browser_search_term:lower()
            local matches = {}
            for _, plugin in ipairs(PLUGIN_LIST) do
                if plugin:lower():find(term_l, 1, true) then
                    matches[#matches+1] = plugin
                end
            end
            if config.apply_type_priority then
                matches = DedupeByTypePriority(matches)
            end
            screenshot_search_results = {}
            for i = 1, math.min(MAX_RESULTS, #matches) do
                screenshot_search_results[#screenshot_search_results+1] = { name = matches[i] }
            end
            too_many_results = (#matches > MAX_RESULTS)
            SortScreenshotResults()
            if too_many_results then
                search_warning_message = "First " .. MAX_RESULTS .. " results. Refine your search for more results."
            end
            new_search_performed = true
            selected_folder = nil
            browser_panel_selected = nil
            last_selected_folder_before_global = nil
            RequestClearScreenshotCache()
        end
        if browser_search_term == "" then r.ImGui_EndDisabled(ctx) end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Search all plugins (ignores folder selection)") end
    else
        r.ImGui_Dummy(ctx, 0, 2)
    end
    end
    r.ImGui_EndChild(ctx)

    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local spacing_fudge = 20
    local footer_space = (config.show_screenshot_info_box and BROWSER_FOOTER_HEIGHT or 0)
    local content_h = math.max(0, avail_h - footer_space - spacing_fudge)

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    local content_open = r.ImGui_BeginChild(ctx, "BrowserContent", -1, content_h)
    if content_open then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)

        -- FAVORITES (respect config setting)
        if config.show_favorites then
            local fav_is_selected = (selected_folder == "Favorites")
            if fav_is_selected then
                local dl = r.ImGui_GetWindowDrawList(ctx)
                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
            end
            r.ImGui_Selectable(ctx, "FAVORITES", fav_is_selected)
            if r.ImGui_IsItemClicked(ctx, 1) then
                r.ImGui_OpenPopup(ctx, "folder_mode_ctx_favorites")
            end
            if r.ImGui_BeginPopup(ctx, "folder_mode_ctx_favorites") then
                local toggle_label = (view_mode == "screenshots" and "Show List" or "Show Screenshots")
                if r.ImGui_MenuItem(ctx, toggle_label) then
                    local prev = view_mode
                    view_mode = (view_mode == "screenshots" and "list" or "screenshots")
                    if view_mode == "screenshots" and prev ~= "screenshots" then RequestClearScreenshotCache() end
                end
                if r.ImGui_MenuItem(ctx, "Capture Folder Screenshots") then
                    StartFolderScreenshots("Favorites")
                end
                r.ImGui_EndPopup(ctx)
            end
            if r.ImGui_IsItemClicked(ctx, 0) then
                SelectFolderExclusive("Favorites")
                UpdateLastViewedFolder("Favorites")
                browser_panel_selected = nil
                show_media_browser = false
                show_sends_window = false
                show_action_browser = false
                screenshot_search_results = {}
                local term_l = GetLowerName(browser_search_term)
                local matches = {}
                for _, fav in ipairs(favorite_plugins) do
                    if GetLowerName(fav):find(term_l, 1, true) then
                        matches[#matches+1] = fav
                    end
                end
                if config.apply_type_priority then
                    matches = DedupeByTypePriority(matches)
                end
                for i = 1, #matches do
                    screenshot_search_results[#screenshot_search_results+1] = { name = matches[i] }
                end
                RequestClearScreenshotCache()
            end
        end
   
        -- CURRENT TRACK FX
        local ctrack_selected = (selected_folder == "Current Track FX")
    if ctrack_selected then
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local x,y = r.ImGui_GetCursorScreenPos(ctx)
            local avail_w = r.ImGui_GetContentRegionAvail(ctx)
            local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
            r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
        end
    r.ImGui_Selectable(ctx, "CURRENT TRACK FX", ctrack_selected)
    if r.ImGui_IsItemClicked(ctx, 0) then
         
            SelectFolderExclusive("Current Track FX")
            UpdateLastViewedFolder("Current Track FX")
            show_media_browser = false
            show_sends_window = false
            show_action_browser = false
            RequestClearScreenshotCache()
            screenshot_search_results = nil
            filtered_plugins = GetCurrentTrackFX()
            GetPluginsForFolder("Current Track FX")
        end

        -- CURRENT PROJECT FX
        local cproj_selected = (selected_folder == "Current Project FX")
        if cproj_selected then
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local x,y = r.ImGui_GetCursorScreenPos(ctx)
            local avail_w = r.ImGui_GetContentRegionAvail(ctx)
            local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
            r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
        end
    r.ImGui_Selectable(ctx, "CURRENT PROJECT FX", cproj_selected)
    if r.ImGui_IsItemClicked(ctx, 0) then
         
            SelectFolderExclusive("Current Project FX")
            UpdateLastViewedFolder("Current Project FX")
            show_media_browser = false
            show_sends_window = false
            show_action_browser = false
            ClearScreenshotCache()
            screenshot_search_results = {}
            local project_fx = GetCurrentProjectFX()
            current_filtered_fx = {}
            for _, fx in ipairs(project_fx) do
                table.insert(current_filtered_fx, fx.fx_name)
            end
            GetPluginsForFolder("Current Project FX")
        end

        r.ImGui_PopStyleColor(ctx, 3)
         r.ImGui_PopStyleVar(ctx)
        r.ImGui_Separator(ctx)

        if config.show_custom_folders then
            DisplayCustomFoldersInBrowser(config.custom_folders)
        end

        -- Categories / Folders / Chains / Templates
        for i = 1, #CAT_TEST do
            local category_name = CAT_TEST[i].name
            if category_name ~= "CUSTOM" then
                if (category_name == "ALL PLUGINS" and config.show_all_plugins) then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3F3F3F3F)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x3F3F3F3F)
                local header_label = "ALL PLUGINS"
               
                local all_has_selected = false
                for j = 1, #CAT_TEST[i].list do
                    if CAT_TEST[i].list[j].name == browser_panel_selected then all_has_selected = true break end
                end
                if all_has_selected then
                    local dl = r.ImGui_GetWindowDrawList(ctx)
                    local x,y = r.ImGui_GetCursorScreenPos(ctx)
                    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                    local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                    r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
                end
                if (not initial_header_auto_expand_done) and all_has_selected then
                    r.ImGui_SetNextItemOpen(ctx, true)
                    initial_header_auto_expand_done = true
                end
                if r.ImGui_CollapsingHeader(ctx, header_label) then
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
                local developer_has_selected = false
                for j = 1, #CAT_TEST[i].list do
                    if CAT_TEST[i].list[j].name == browser_panel_selected then developer_has_selected = true break end
                end
                if developer_has_selected then
                    local dl = r.ImGui_GetWindowDrawList(ctx)
                    local x,y = r.ImGui_GetCursorScreenPos(ctx)
                    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                    local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                    r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
                end
                if (not initial_header_auto_expand_done) and developer_has_selected then
                    r.ImGui_SetNextItemOpen(ctx, true)
                    initial_header_auto_expand_done = true
                end
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
                local category_has_selected = false
                for j = 1, #CAT_TEST[i].list do
                    if CAT_TEST[i].list[j].name == browser_panel_selected then category_has_selected = true break end
                end
                if category_has_selected then
                    local dl = r.ImGui_GetWindowDrawList(ctx)
                    local x,y = r.ImGui_GetCursorScreenPos(ctx)
                    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                    local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                    r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
                end
                if (not initial_header_auto_expand_done) and category_has_selected then
                    r.ImGui_SetNextItemOpen(ctx, true)
                    initial_header_auto_expand_done = true
                end
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
                local folders_has_selected = false
                for j = 1, #CAT_TEST[i].list do
                    if CAT_TEST[i].list[j].name == selected_folder then folders_has_selected = true break end
                end
                if folders_has_selected then
                    local dl = r.ImGui_GetWindowDrawList(ctx)
                    local x,y = r.ImGui_GetCursorScreenPos(ctx)
                    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                    local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                    r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
                end
                if (not initial_header_auto_expand_done) and folders_has_selected then
                    r.ImGui_SetNextItemOpen(ctx, true)
                    initial_header_auto_expand_done = true
                end
                if r.ImGui_CollapsingHeader(ctx, "FOLDERS") then
                    local function EnsurePinnedList()
                        if not config.pinned_subgroups then config.pinned_subgroups = {} end
                        if not config.pinned_subgroups["FOLDERS"] then config.pinned_subgroups["FOLDERS"] = {} end
                        return config.pinned_subgroups["FOLDERS"]
                    end
                    local function IsPinned(name)
                        local lst = EnsurePinnedList()
                        for _, n in ipairs(lst) do if n == name then return true end end
                        return false
                    end
                    local function Pin(name)
                        local lst = EnsurePinnedList()
                        if not IsPinned(name) then table.insert(lst, name); SaveConfig() end
                    end
                    local function Unpin(name)
                        local lst = EnsurePinnedList()
                        for k=#lst,1,-1 do if lst[k] == name then table.remove(lst, k); SaveConfig(); break end end
                    end
                    local index_by_name = {}
                    for idx=1,#CAT_TEST[i].list do index_by_name[CAT_TEST[i].list[idx].name] = idx end
                    local order = {}
                    local pinned = EnsurePinnedList()
                    local pinned_set = {}
                    for _, name in ipairs(pinned) do
                        local idx = index_by_name[name]
                        if idx then table.insert(order, idx); pinned_set[name] = true end
                    end
                    for idx=1,#CAT_TEST[i].list do
                        local nm = CAT_TEST[i].list[idx].name
                        if not pinned_set[nm] then table.insert(order, idx) end
                    end
                    for _, j in ipairs(order) do
                        local show_folder = browser_search_term == ""
                        if not show_folder then
                            for k = 1, #CAT_TEST[i].list[j].fx do
                                if CAT_TEST[i].list[j].fx[k]:lower():find(browser_search_term:lower(), 1, true) then
                                    show_folder = true; break
                                end
                            end
                        end
                        if show_folder then
                            r.ImGui_PushID(ctx, j)
                            r.ImGui_Indent(ctx, 10)
                            local folder_name = CAT_TEST[i].list[j].name
                            local is_pinned = IsPinned(folder_name)
                            local header_text = (is_pinned and "\xF0\x9F\x93\x8C " or "") .. folder_name
                            
                            local folder_is_selected = (selected_folder == folder_name)
                            if folder_is_selected then
                                local dl = r.ImGui_GetWindowDrawList(ctx)
                                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                                r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
                            end
                            r.ImGui_Selectable(ctx, header_text, folder_is_selected)
                            r.ImGui_Unindent(ctx, 10)
                            if r.ImGui_IsItemClicked(ctx, 0) then
                                selected_folder = folder_name
                                browser_panel_selected = nil 
                                selected_plugin = nil
                                UpdateLastViewedFolder(selected_folder)
                                screenshot_search_results = nil
                                show_media_browser = false
                                show_sends_window = false
                                show_action_browser = false
                                ClearScreenshotCache()
                                GetPluginsForFolder(folder_name)
                            elseif r.ImGui_IsItemClicked(ctx, 1) then
                                r.ImGui_OpenPopup(ctx, "folder_browser_ctx_" .. j)
                            end
                            if r.ImGui_BeginPopup(ctx, "folder_browser_ctx_" .. j) then
                                local toggle_label = (view_mode == 'screenshots' and 'Show List' or 'Show Screenshots')
                                if r.ImGui_MenuItem(ctx, toggle_label) then
                                    local prev = view_mode
                                    view_mode = (view_mode == 'screenshots' and 'list' or 'screenshots')
                                    if view_mode == 'screenshots' then
                                        if prev ~= 'screenshots' then ClearScreenshotCache() end
                                    else
                                        if selected_folder == folder_name then
                                            local folder_plugins = GetPluginsForFolder(folder_name)
                                            screenshot_search_results = {}
                                            for p = 1, #folder_plugins do
                                                table.insert(screenshot_search_results, { name = folder_plugins[p] })
                                            end
                                        end
                                    end
                                end
                                if is_pinned then
                                    if r.ImGui_MenuItem(ctx, 'Unpin Folder') then Unpin(folder_name) end
                                else
                                    if r.ImGui_MenuItem(ctx, 'Pin Folder') then Pin(folder_name) end
                                end
                                if r.ImGui_MenuItem(ctx, 'Capture Folder Screenshots') then
                                    StartFolderScreenshots(folder_name)
                                end
                                r.ImGui_EndPopup(ctx)
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
                    local tree = GetFxChainsTree()
                    DrawFxChains(tree)
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
                    local tree = GetTrackTemplatesTree()
                    DrawTrackTemplates(tree)
                    r.ImGui_Unindent(ctx, 10)
                end
                r.ImGui_PopStyleColor(ctx, 3)
                r.ImGui_PopStyleVar(ctx)
                end
            end
        end
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)

        if config.show_container then
            if r.ImGui_Selectable(ctx, "CONTAINER") then
                AddFXToTrack(TRACK, "Container")
                LAST_USED_FX = "Container"
                if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
            end
        end
        if config.show_video_processor then
            if r.ImGui_Selectable(ctx, "VIDEO PROCESSOR") then
                AddFXToTrack(TRACK, "Video processor")
                LAST_USED_FX = "Video processor"
                if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
            end
        end
        if config.show_projects then
            local is_sel = (selected_folder == "Projects" and show_media_browser)
            if is_sel then
                local dl = r.ImGui_GetWindowDrawList(ctx)
                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
            end
        if r.ImGui_Selectable(ctx, "PROJECTS", is_sel) then
                if not show_media_browser then
                    UpdateLastViewedFolder(selected_folder)
                    show_media_browser = true
                    show_sends_window = false
                    show_action_browser = false
                    show_scripts_browser = false
            SelectFolderExclusive("Projects")
                    LoadProjects()
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    show_scripts_browser = false
            SelectFolderExclusive(last_viewed_folder)
                    GetPluginsForFolder(last_viewed_folder)
                end
                ClearScreenshotCache()
            end
        end
        if config.show_sends then
            local is_sel = (selected_folder == "Sends/Receives" and show_sends_window)
            if is_sel then
                local dl = r.ImGui_GetWindowDrawList(ctx)
                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
            end
        if r.ImGui_Selectable(ctx, "SEND/RECEIVE", is_sel) then
                if not show_sends_window then
                    UpdateLastViewedFolder(selected_folder)
                    show_sends_window = true
                    show_media_browser = false
                    show_action_browser = false
                    show_scripts_browser = false
            SelectFolderExclusive("Sends/Receives")
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    show_scripts_browser = false
            SelectFolderExclusive(last_viewed_folder)
                    GetPluginsForFolder(last_viewed_folder)
                end
                ClearScreenshotCache()
            end
        end
        if config.show_actions then
            local is_sel = (selected_folder == "Actions" and show_action_browser)
            if is_sel then
                local dl = r.ImGui_GetWindowDrawList(ctx)
                local x,y = r.ImGui_GetCursorScreenPos(ctx)
                local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
            end
        if r.ImGui_Selectable(ctx, "ACTIONS", is_sel) then
                if not show_action_browser then
                    UpdateLastViewedFolder(selected_folder)
                    show_action_browser = true
                    show_media_browser = false
                    show_sends_window = false
                    show_scripts_browser = false
            SelectFolderExclusive("Actions")
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    show_scripts_browser = false
            SelectFolderExclusive(last_viewed_folder)
                    GetPluginsForFolder(last_viewed_folder)
                end
                ClearScreenshotCache()
            end
        end
        if config.show_notes_widget then
            if r.ImGui_Selectable(ctx, "NOTES", false) then
                LaunchTKNotes()
            end
        end
                if config.show_scripts then
                    local is_sel = (selected_folder == "Scripts" and show_scripts_browser)
                    if is_sel then
                        local dl = r.ImGui_GetWindowDrawList(ctx)
                        local x,y = r.ImGui_GetCursorScreenPos(ctx)
                        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                        local line_h = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                        r.ImGui_DrawList_AddRectFilled(dl, x-2, y, x + avail_w, y + line_h, 0xFF704030, 3)
                    end
            if r.ImGui_Selectable(ctx, "SCRIPTS", is_sel) then
                        if not show_scripts_browser then
                            UpdateLastViewedFolder(selected_folder)
                            show_scripts_browser = true
                            show_action_browser = false
                            show_media_browser = false
                            show_sends_window = false
                SelectFolderExclusive("Scripts")
                        else
                            show_scripts_browser = false
                            show_action_browser = false
                            show_media_browser = false
                            show_sends_window = false
                SelectFolderExclusive(last_viewed_folder)
                            GetPluginsForFolder(last_viewed_folder)
                        end
                        ClearScreenshotCache()
                    end
                end
        if LAST_USED_FX and r.ValidatePtr(TRACK, "MediaTrack*") then
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, "RECENT: " .. LAST_USED_FX) then
                AddFXToTrack(TRACK, LAST_USED_FX)
                if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
            end
        end

    end
    r.ImGui_EndChild(ctx) -- BrowserContent
    r.ImGui_PopStyleVar(ctx) -- ScrollbarSize

   
    if config.show_screenshot_info_box then
        do
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local x1, y1 = r.ImGui_GetCursorScreenPos(ctx)
            local avail_w = r.ImGui_GetContentRegionAvail(ctx)
            local x2 = x1 + avail_w
            local grab_h = 6
            local mid_y = y1 + math.floor(grab_h/2)
            r.ImGui_DrawList_AddLine(draw_list, x1, mid_y-1, x2, mid_y-1, 0x666666FF, 2.0)
            r.ImGui_DrawList_AddLine(draw_list, x1, mid_y+1, x2, mid_y+1, 0x222222FF, 1.0)
            r.ImGui_InvisibleButton(ctx, "##FooterResize", avail_w, grab_h)
            if r.ImGui_IsItemClicked(ctx, 1) then
                BROWSER_FOOTER_HEIGHT = 20
                config.browser_footer_height = 20
                SaveConfig()
            end
            local hovered = r.ImGui_IsItemHovered(ctx)
            local active  = r.ImGui_IsItemActive(ctx)
            if hovered or active then r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS()) end

            if active and not footer_resize_active then
                footer_resize_active = true
                local _, my = r.ImGui_GetMousePos(ctx)
                footer_last_mouse_y = my
            elseif not active and footer_resize_active then
                footer_resize_active = false
            end

            if footer_resize_active then
                local _, my = r.ImGui_GetMousePos(ctx)
                local delta = my - footer_last_mouse_y
                if delta ~= 0 then
                    local new_height = BROWSER_FOOTER_HEIGHT - delta
                    local window_h = r.ImGui_GetWindowHeight(ctx)
                    local max_h = math.floor(window_h * 0.7) 
                    new_height = math.max(20, math.min(new_height, max_h))
                    if new_height ~= BROWSER_FOOTER_HEIGHT then
                        config.browser_footer_height = new_height
                        BROWSER_FOOTER_HEIGHT = new_height
                        SaveConfig()
                    end
                    footer_last_mouse_y = my
                end
            end
            r.ImGui_Dummy(ctx, 0, 2)
        end
        local browser_footer_open = false
        if config.show_screenshot_info_box then
            browser_footer_open = r.ImGui_BeginChild(ctx, "BrowserFooter", -1, BROWSER_FOOTER_HEIGHT)
            if browser_footer_open then
            local proj = 0 
            local _, proj_name = r.EnumProjects(-1, "")
            if not proj_name or proj_name == "" then
                proj_name = "(Unsaved Project)"
            else
                proj_name = proj_name:match("[^/\\]+$") or proj_name
                proj_name = proj_name:gsub("%.RPP$","",1):gsub("%.rpp$","",1)
            end
            local sr = r.GetSetProjectInfo(proj, "PROJECT_SRATE", 0, false) or 0
            if sr == 0 then
                local dev_sr_ret, dev_sr = r.GetAudioDeviceInfo and r.GetAudioDeviceInfo("SRATE", "") or false, nil
                if dev_sr_ret then sr = tonumber(dev_sr) or 0 end
            end
            local bpm = r.Master_GetTempo() or 0
            local track_num_display = "-"
            local track_name = "(No track selected)"
            local item_count_display = "-"
            local item_type_suffix = ""
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                local track_num = r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER") or 0
                if track_num == 0 then
                    track_num_display = "Master"
                    track_name = "Master Track"
                else
                    track_num_display = tostring(math.floor(track_num))
                    local _, tn = r.GetTrackName(TRACK)
                    if tn and tn ~= "" then track_name = tn end
                end
                local ic = r.CountTrackMediaItems(TRACK) or 0
                item_count_display = tostring(ic)
                if ic > 0 and track_num_display ~= "Master" then
                    local has_midi, has_audio = false, false
                    for i = 0, ic - 1 do
                        local item = r.GetTrackMediaItem(TRACK, i)
                        if item then
                            local take = r.GetActiveTake(item)
                            if take then
                                local src = r.GetMediaItemTake_Source(take)
                                if src then
                                    local s_type = r.GetMediaSourceType(src, "") or ""
                                    if s_type:upper() == "MIDI" then
                                        has_midi = true
                                    else
                                        has_audio = true
                                    end
                                    if has_midi and has_audio then break end
                                end
                            end
                        end
                    end
                    if has_midi and not has_audio then
                        item_type_suffix = " (MIDI)"
                    elseif has_audio and not has_midi then
                        item_type_suffix = " (Audio)"
                    elseif has_audio and has_midi then
                        item_type_suffix = " (Mixed)"
                    end
                end
            end
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            r.ImGui_Text(ctx, "Project: " .. proj_name)
            r.ImGui_Text(ctx, string.format("Sample Rate: %s", sr > 0 and (tostring(math.floor(sr)) .. " Hz") or "Device"))
            r.ImGui_Text(ctx, string.format("BPM: %.2f", bpm))
            r.ImGui_Text(ctx, "Track #: " .. track_num_display)
            do
                local label = "Track Name: " .. track_name
                if r.ImGui_Selectable(ctx, label .. "##footer_track_name_sel", false, r.ImGui_SelectableFlags_AllowDoubleClick() ) then
                    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        new_track_name = track_name
                        show_rename_popup = true
                    end
                end
                if r.ImGui_IsItemClicked(ctx, 1) then
                    new_track_name = track_name
                    show_rename_popup = true
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Right-click or double-click to rename track")
                end
            end
            r.ImGui_Text(ctx, "Items: " .. item_count_display .. item_type_suffix)
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                local guid = r.GetTrackGUID(TRACK)
                local tags = guid and track_tags and track_tags[guid]
                r.ImGui_Text(ctx, "Tags:")
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+", 16, 16) then
                    r.ImGui_OpenPopup(ctx, "FooterAddTagPopup")
                end
                if r.ImGui_BeginPopup(ctx, "FooterAddTagPopup") then
                    local track_guid_footer = guid
                    track_tags[track_guid_footer] = track_tags[track_guid_footer] or {}
                    r.ImGui_PushItemWidth(ctx, 120)
                    local changed_footer, nt = r.ImGui_InputText(ctx, "##footer_new_tag", new_tag_buffer or "")
                    if changed_footer then new_tag_buffer = nt end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Add") and new_tag_buffer ~= "" then
                        if not table.contains(track_tags[track_guid_footer], new_tag_buffer) then
                            table.insert(track_tags[track_guid_footer], new_tag_buffer)
                            available_tags[new_tag_buffer] = true
                            SaveTags()
                        end
                        new_tag_buffer = ""
                    end
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "Beschikbare Tags:")
                    local avail_w_tags = select(1, r.ImGui_GetContentRegionAvail(ctx))
                    local line_w_tags = 0
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 4)
                    for tag_avail, _ in pairs(available_tags) do
                        local tag_w_btn = r.ImGui_CalcTextSize(ctx, tag_avail) + 14
                        if line_w_tags + tag_w_btn > avail_w_tags then
                            r.ImGui_NewLine(ctx)
                            line_w_tags = 0
                        elseif line_w_tags > 0 then
                            r.ImGui_SameLine(ctx)
                        end
                        local tag_color = tag_colors[tag_avail] or config.button_background_color
                        local _, text_color = GetTagColorAndTextColor(tag_color)
                        if tag_colors[tag_avail] then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), tag_colors[tag_avail])
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), tag_colors[tag_avail])
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                        end
                        if r.ImGui_Button(ctx, tag_avail) then
                            if not table.contains(track_tags[track_guid_footer], tag_avail) then
                                table.insert(track_tags[track_guid_footer], tag_avail)
                                SaveTags()
                            end
                        end
                        if tag_colors[tag_avail] then r.ImGui_PopStyleColor(ctx, 3) end
                        line_w_tags = line_w_tags + tag_w_btn
                    end
                    r.ImGui_PopStyleVar(ctx)
                    r.ImGui_EndPopup(ctx)
                end
                if tags and #tags > 0 then
                    r.ImGui_SameLine(ctx)
                    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                    local start_x = r.ImGui_GetCursorPosX(ctx)
                    local line_w = 0
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, -4)
                    for _, tag in ipairs(tags) do
                        local tag_w = r.ImGui_CalcTextSize(ctx, tag) + 14
                        if line_w + tag_w > avail_w then
                            r.ImGui_NewLine(ctx)
                            r.ImGui_SetCursorPosX(ctx, start_x)
                            line_w = 0
                        elseif line_w > 0 then
                            r.ImGui_SameLine(ctx)
                        end
                        local tag_color = tag_colors[tag] or config.button_background_color
                        local _, text_color = GetTagColorAndTextColor(tag_color)
                        if tag_colors[tag] then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), tag_colors[tag])
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), tag_colors[tag])
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                        end
                        local pressed = r.ImGui_Button(ctx, tag)
                        if tag_colors[tag] then r.ImGui_PopStyleColor(ctx, 3) end
                        if pressed then
                            local tagged_tracks = FilterTracksByTag(tag)
                            r.Main_OnCommand(40297, 0)
                            for _, tr in ipairs(tagged_tracks) do r.SetTrackSelected(tr, true) end
                        end
                        if r.ImGui_IsItemClicked(ctx, 1) then
                            r.ImGui_OpenPopup(ctx, "footer_tag_ctx_" .. tag)
                            selected_tag = tag
                        end
                        if r.ImGui_BeginPopup(ctx, "footer_tag_ctx_" .. tag) then
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 2)
                            if r.ImGui_MenuItem(ctx, "Remove Tag") then
                                for g, tag_list in pairs(track_tags) do
                                    for i = #tag_list, 1, -1 do
                                        if tag_list[i] == selected_tag then table.remove(tag_list, i) end
                                    end
                                end
                                available_tags[selected_tag] = nil
                                tag_colors[selected_tag] = nil
                                SaveTags()
                            end
                            if r.ImGui_MenuItem(ctx, "Add this tag to all selected tracks") then
                                local track_count = r.CountSelectedTracks(0)
                                for j = 0, track_count - 1 do
                                    local tr = r.GetSelectedTrack(0, j)
                                    local g = r.GetTrackGUID(tr)
                                    track_tags[g] = track_tags[g] or {}
                                    if not table.contains(track_tags[g], selected_tag) then table.insert(track_tags[g], selected_tag) end
                                end
                                SaveTags()
                            end
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                            r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                            r.ImGui_PopStyleVar(ctx)
                            r.ImGui_PopStyleColor(ctx)
                            if r.ImGui_MenuItem(ctx, "Select all tracks with this tag") then
                                local list = FilterTracksByTag(tag)
                                r.Main_OnCommand(40297, 0)
                                for _, tr in ipairs(list) do r.SetTrackSelected(tr, true) end
                            end
                            if r.ImGui_MenuItem(ctx, "Unselect all tracks") then
                                r.Main_OnCommand(40297, 0)
                            end
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                            r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                            r.ImGui_PopStyleVar(ctx)
                            r.ImGui_PopStyleColor(ctx)
                            if r.ImGui_MenuItem(ctx, "Hide all tracks with this tag") then
                                for _, tr in ipairs(FilterTracksByTag(tag)) do r.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0); r.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0) end
                                r.TrackList_AdjustWindows(false)
                            end
                            if r.ImGui_MenuItem(ctx, "Show all tracks with this tag") then
                                for _, tr in ipairs(FilterTracksByTag(tag)) do r.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 1); r.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 1) end
                                r.TrackList_AdjustWindows(false)
                            end
                            if r.ImGui_MenuItem(ctx, "Hide all tracks except with this tag") then
                                local tagged_tracks = FilterTracksByTag(tag)
                                for i2=0,r.CountTracks(0)-1 do
                                    local tr2 = r.GetTrack(0,i2)
                                    local hide = true
                                    for _, ttr in ipairs(tagged_tracks) do if tr2==ttr then hide=false break end end
                                    r.SetMediaTrackInfo_Value(tr2, "B_SHOWINTCP", hide and 0 or 1)
                                    r.SetMediaTrackInfo_Value(tr2, "B_SHOWINMIXER", hide and 0 or 1)
                                end
                                r.TrackList_AdjustWindows(false)
                            end
                            if r.ImGui_MenuItem(ctx, "Show all tracks") then
                                for i2=0,r.CountTracks(0)-1 do
                                    local tr2 = r.GetTrack(0,i2)
                                    r.SetMediaTrackInfo_Value(tr2, "B_SHOWINTCP", 1); r.SetMediaTrackInfo_Value(tr2, "B_SHOWINMIXER", 1)
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
                                for i2, tr2 in ipairs(tagged_tracks) do
                                    local new_name = (#tagged_tracks>1) and (tag .. " " .. i2) or tag
                                    r.GetSetMediaTrackInfo_String(tr2, "P_NAME", new_name, true)
                                end
                            end
                            if r.ImGui_MenuItem(ctx, "Rename current track with this tag") then
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then r.GetSetMediaTrackInfo_String(TRACK, "P_NAME", tag, true) end
                            end
                            if r.ImGui_MenuItem(ctx, "Rename tagged tracks to first plugin") then
                                local tagged_tracks = FilterTracksByTag(tag)
                                for _, tr2 in ipairs(tagged_tracks) do
                                    local fx_cnt = r.TrackFX_GetCount(tr2)
                                    if fx_cnt>0 then
                                        local _, fx_name = r.TrackFX_GetFXName(tr2, 0, "")
                                        fx_name = fx_name:gsub("^[^:]+:%s*", "")
                                        r.GetSetMediaTrackInfo_String(tr2, "P_NAME", fx_name, true)
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
                                if #tracks>0 then
                                    local first_idx = math.huge
                                    for _, tr2 in ipairs(tracks) do
                                        local idx = r.GetMediaTrackInfo_Value(tr2, "IP_TRACKNUMBER")-1
                                        if idx < first_idx then first_idx=idx end
                                    end
                                    r.InsertTrackAtIndex(first_idx, true)
                                    local folder_tr = r.GetTrack(0, first_idx)
                                    r.GetSetMediaTrackInfo_String(folder_tr, "P_NAME", tag .. " Folder", true)
                                    r.SetMediaTrackInfo_Value(folder_tr, "I_FOLDERDEPTH", 1)
                                    for _, tr2 in ipairs(tracks) do r.SetMediaTrackInfo_Value(tr2, "I_FOLDERDEPTH", 0) end
                                    r.SetMediaTrackInfo_Value(tracks[#tracks], "I_FOLDERDEPTH", -1)
                                end
                            end
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x666666FF)
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 1)
                            r.ImGui_Text(ctx, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -")
                            r.ImGui_PopStyleVar(ctx)
                            r.ImGui_PopStyleColor(ctx)
                            if r.ImGui_MenuItem(ctx, "Mute all tracks with this tag") then for _, tr2 in ipairs(FilterTracksByTag(tag)) do r.SetMediaTrackInfo_Value(tr2, "B_MUTE", 1) end end
                            if r.ImGui_MenuItem(ctx, "Unmute all tracks with this tag") then for _, tr2 in ipairs(FilterTracksByTag(tag)) do r.SetMediaTrackInfo_Value(tr2, "B_MUTE", 0) end end
                            if r.ImGui_MenuItem(ctx, "Solo tracks with this tag") then
                                for i2=0,r.CountTracks(0)-1 do r.SetMediaTrackInfo_Value(r.GetTrack(0,i2), "I_SOLO", 0) end
                                for _, tr2 in ipairs(FilterTracksByTag(tag)) do r.SetMediaTrackInfo_Value(tr2, "I_SOLO", 2) end
                            end
                            if r.ImGui_MenuItem(ctx, "Unsolo all tracks") then for i2=0,r.CountTracks(0)-1 do r.SetMediaTrackInfo_Value(r.GetTrack(0,i2), "I_SOLO", 0) end end
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
                                    local red,g,b = reaper.ColorFromNative(native_color)
                                    local color_vec4 = r.ImGui_ColorConvertDouble4ToU32(red/255,g/255,b/255,1.0)
                                    tag_colors[tag]=color_vec4; SaveTags()
                                end
                            end
                            if r.ImGui_MenuItem(ctx, "Remove Color") then tag_colors[tag]=nil; SaveTags() end
                            if r.ImGui_MenuItem(ctx, "Apply Tag Color to Tracks") and tag_colors[tag] then
                                local imgui_color = tag_colors[tag]
                                local red,g,b,a = r.ImGui_ColorConvertU32ToDouble4(imgui_color)
                                local native_color = reaper.ColorToNative(math.floor(red*255), math.floor(g*255), math.floor(b*255))|0x1000000
                                for i2=0,r.CountTracks(0)-1 do
                                    local tr2 = r.GetTrack(0,i2); local g2 = r.GetTrackGUID(tr2)
                                    if track_tags[g2] then for _,t in ipairs(track_tags[g2]) do if t==tag then reaper.SetTrackColor(tr2, native_color) break end end end
                                end
                            end
                            r.ImGui_PopStyleVar(ctx)
                            r.ImGui_EndPopup(ctx)
                        end
                        line_w = line_w + tag_w
                    end
                    r.ImGui_PopStyleVar(ctx)
                else
                    r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, "-")
                end
            else
                r.ImGui_Text(ctx, "Tags: -")
            end
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                local fx_count = r.TrackFX_GetCount(TRACK)
                r.ImGui_Dummy(ctx, 0, 6) 
                r.ImGui_Separator(ctx)
                if fx_count > 0 then
                    r.ImGui_Text(ctx, string.format("Track FX (%d):", fx_count))
                    local list_height = math.min(120, fx_count * 18 + 4)
                    -- Temporarily pop outer white text color to keep stacks balanced per child window
                    r.ImGui_PopStyleColor(ctx)
                    local footer_trackfx_open = r.ImGui_BeginChild(ctx, "FooterTrackFX", -1, list_height)
                    if footer_trackfx_open then
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 2)
                        for i = 0, fx_count - 1 do
                            local ok, fx_name = r.TrackFX_GetFXName(TRACK, i, "")
                            if ok and fx_name ~= "" then
                                if config.clean_plugin_names or config.remove_manufacturer_names then
                                    fx_name = GetDisplayPluginName(fx_name)
                                end
                local clicked = r.ImGui_Selectable(ctx, fx_name .. "##footerfx" .. i, false, r.ImGui_SelectableFlags_AllowDoubleClick())
                if clicked then
                                    if r.TrackFX_GetFloatingWindow(TRACK, i) then
                                        r.TrackFX_Show(TRACK, i, 2)
                                    else
                                        r.TrackFX_Show(TRACK, i, 3)
                                    end
                                end

                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Left: toggle floating | Right: menu") end

                                if r.ImGui_IsItemClicked(ctx, 1) then
                                    r.ImGui_OpenPopup(ctx, "footer_fx_ctx_" .. i)
                                end
                                if r.ImGui_BeginPopup(ctx, "footer_fx_ctx_" .. i) then
                                    fx_clipboard = fx_clipboard or {}
                                    local enabled = r.TrackFX_GetEnabled and r.TrackFX_GetEnabled(TRACK, i)
                                    local offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(TRACK, i)
                                    if r.ImGui_MenuItem(ctx, (enabled and "Bypass" or "Enable")) then
                                        if r.TrackFX_SetEnabled then r.TrackFX_SetEnabled(TRACK, i, not enabled) end
                                    end
                                    if r.ImGui_MenuItem(ctx, (offline and "Set Online" or "Set Offline")) then
                                        if r.TrackFX_SetOffline then r.TrackFX_SetOffline(TRACK, i, not offline) end
                                    end
                                    if r.ImGui_MenuItem(ctx, "Float / Unfloat") then
                                        if r.TrackFX_GetFloatingWindow(TRACK, i) then r.TrackFX_Show(TRACK, i, 2) else r.TrackFX_Show(TRACK, i, 3) end
                                    end
                                    r.ImGui_Separator(ctx)
                                    if r.ImGui_MenuItem(ctx, "Copy") then fx_clipboard.track = TRACK; fx_clipboard.index = i end
                                    local can_paste = fx_clipboard.track and r.ValidatePtr(fx_clipboard.track, "MediaTrack*") and fx_clipboard.index ~= nil
                                    if not can_paste then r.ImGui_BeginDisabled(ctx) end
                                    if r.ImGui_MenuItem(ctx, "Paste (after)") and can_paste then
                                        local dest_index = i + 1
                                        r.TrackFX_CopyToTrack(fx_clipboard.track, fx_clipboard.index, TRACK, dest_index, false)
                                    end
                                    if not can_paste then r.ImGui_EndDisabled(ctx) end
                                    r.ImGui_Separator(ctx)
                                    if i == 0 then r.ImGui_BeginDisabled(ctx) end
                                    if r.ImGui_MenuItem(ctx, "Move Up") and i > 0 then r.TrackFX_CopyToTrack(TRACK, i, TRACK, i-1, true) end
                                    if i == 0 then r.ImGui_EndDisabled(ctx) end
                                    if i == fx_count - 1 then r.ImGui_BeginDisabled(ctx) end
                                    if r.ImGui_MenuItem(ctx, "Move Down") and i < fx_count - 1 then r.TrackFX_CopyToTrack(TRACK, i, TRACK, i+2, true) end
                                    if i == fx_count - 1 then r.ImGui_EndDisabled(ctx) end
                                    r.ImGui_Separator(ctx)
                                    if r.ImGui_MenuItem(ctx, "Rename Track to this FX") then r.GetSetMediaTrackInfo_String(TRACK, "P_NAME", fx_name, true) end
                                    if r.ImGui_MenuItem(ctx, "Delete FX") then r.TrackFX_Delete(TRACK, i) end
                                    r.ImGui_EndPopup(ctx)
                                end
                            end
                        end
                        r.ImGui_PopStyleVar(ctx)
                        r.ImGui_EndChild(ctx)
                    end
                    -- Restore outer white text color after closing the child
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                else
                    r.ImGui_Text(ctx, "Track FX: (none)")
                end
            else
                r.ImGui_Dummy(ctx, 0, 6)
                r.ImGui_Separator(ctx)
                r.ImGui_Text(ctx, "Track FX: -")
            end

            do
                local sel_item = r.GetSelectedMediaItem(0, 0)
                local take = sel_item and r.GetActiveTake(sel_item) or nil
                r.ImGui_Dummy(ctx, 0, 4)
                r.ImGui_Separator(ctx)
                if take then
                    local ifx_count = r.TakeFX_GetCount(take)
                    if ifx_count > 0 then
                        r.ImGui_Text(ctx, string.format("Item FX (%d):", ifx_count))
                        local list_height = math.min(100, ifx_count * 18 + 4)
                        -- Temporarily pop outer white text color to keep stacks balanced per child window
                        r.ImGui_PopStyleColor(ctx)
                        local footer_itemfx_open = r.ImGui_BeginChild(ctx, "FooterItemFX", -1, list_height)
                        if footer_itemfx_open then
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 2)
                            for i = 0, ifx_count - 1 do
                                local ok, ifx_name = r.TakeFX_GetFXName(take, i, "")
                                if ok and ifx_name ~= "" then
                                    if config.clean_plugin_names or config.remove_manufacturer_names then
                                        ifx_name = GetDisplayPluginName(ifx_name)
                                    end
                                    local clicked = r.ImGui_Selectable(ctx, ifx_name .. "##footeritemfx" .. i, false, r.ImGui_SelectableFlags_AllowDoubleClick())
                                    if clicked then
                                        if r.TakeFX_GetFloatingWindow(take, i) then
                                            r.TakeFX_Show(take, i, 2)
                                        else
                                            r.TakeFX_Show(take, i, 3)
                                        end
                                    end
                                    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Left: toggle floating | Right: menu") end
                                    if r.ImGui_IsItemClicked(ctx, 1) then
                                        r.ImGui_OpenPopup(ctx, "footer_itemfx_ctx_" .. i)
                                    end
                                    if r.ImGui_BeginPopup(ctx, "footer_itemfx_ctx_" .. i) then
                                        item_fx_clipboard = item_fx_clipboard or {}
                                        local enabled = r.TakeFX_GetEnabled and r.TakeFX_GetEnabled(take, i)
                                        local offline = r.TakeFX_GetOffline and r.TakeFX_GetOffline(take, i)
                                        if r.ImGui_MenuItem(ctx, (enabled and "Bypass" or "Enable")) then
                                            if r.TakeFX_SetEnabled then r.TakeFX_SetEnabled(take, i, not enabled) end
                                        end
                                        if r.ImGui_MenuItem(ctx, (offline and "Set Online" or "Set Offline")) then
                                            if r.TakeFX_SetOffline then r.TakeFX_SetOffline(take, i, not offline) end
                                        end
                                        if r.ImGui_MenuItem(ctx, "Float / Unfloat") then
                                            if r.TakeFX_GetFloatingWindow(take, i) then r.TakeFX_Show(take, i, 2) else r.TakeFX_Show(take, i, 3) end
                                        end
                                        r.ImGui_Separator(ctx)
                                        if r.ImGui_MenuItem(ctx, "Copy") then item_fx_clipboard.take = take; item_fx_clipboard.index = i end
                                        local can_paste = item_fx_clipboard.take and item_fx_clipboard.index ~= nil
                                        if not can_paste then r.ImGui_BeginDisabled(ctx) end
                                        if r.ImGui_MenuItem(ctx, "Paste (after)") and can_paste then
                                            local dest_index = i + 1
                                            r.TakeFX_CopyToTake(item_fx_clipboard.take, item_fx_clipboard.index, take, dest_index, false)
                                        end
                                        if not can_paste then r.ImGui_EndDisabled(ctx) end
                                        r.ImGui_Separator(ctx)
                                        if i == 0 then r.ImGui_BeginDisabled(ctx) end
                                        if r.ImGui_MenuItem(ctx, "Move Up") and i > 0 then r.TakeFX_CopyToTake(take, i, take, i-1, true) end
                                        if i == 0 then r.ImGui_EndDisabled(ctx) end
                                        if i == ifx_count - 1 then r.ImGui_BeginDisabled(ctx) end
                                        if r.ImGui_MenuItem(ctx, "Move Down") and i < ifx_count - 1 then r.TakeFX_CopyToTake(take, i, take, i+2, true) end
                                        if i == ifx_count - 1 then r.ImGui_EndDisabled(ctx) end
                                        r.ImGui_Separator(ctx)
                                        if r.ImGui_MenuItem(ctx, "Delete FX") then r.TakeFX_Delete(take, i) end
                                        r.ImGui_EndPopup(ctx)
                                    end
                                end
                            end
                            r.ImGui_PopStyleVar(ctx)
                            r.ImGui_EndChild(ctx)
                        end
                        -- Restore outer white text color after closing the child
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                    else
                        r.ImGui_Text(ctx, "Item FX: (none)")
                    end
                else
                    r.ImGui_Text(ctx, "Item FX: - (no selected item with active take)")
                end
            end
            r.ImGui_PopStyleColor(ctx)
        end
        if browser_footer_open then
            r.ImGui_EndChild(ctx)  -- Close BrowserFooter
        end
        end
    end

    r.ImGui_EndChild(ctx) -- BrowserSection
    r.ImGui_PopStyleVar(ctx) -- outer ScrollbarSize

    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x666666FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x888888FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xAAAAAAFF)
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

function CheckScrollAndLoadMore(all_plugins)
    if not config.use_pagination and all_plugins and #all_plugins > ITEMS_PER_BATCH then
        local ss_open = r.ImGui_BeginChild(ctx, "ScreenshotList")
        if ss_open then
            local current_scroll = r.ImGui_GetScrollY(ctx)
            local max_scroll = r.ImGui_GetScrollMaxY(ctx)
            
            if current_scroll > 0 and current_scroll/max_scroll > 0.7 and loaded_items_count < #all_plugins then
                local new_count = math.min(loaded_items_count + ITEMS_PER_BATCH, #all_plugins)
                if new_count > loaded_items_count then
                    if not screenshot_search_results then
                        screenshot_search_results = {}
                    end
                    
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

function ScaleScreenshotSize(width, height, max_display_size)
    local max_height = max_display_size * 1.2 
    local display_width = max_display_size
    local display_height = display_width * (height / width)
    
    if display_height > max_height then
        display_height = max_height
        display_width = display_height * (width / height)
    end
    
    return display_width, display_height
end

function DrawPinnedOverlayAt(tlx, tly, w, h)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local size = (config and config.overlay_icon_size) or 14
    local pad = 5
    local x2 = tlx + w - pad
    local y1 = tly + pad
    local x1 = x2 - size
    local y2 = y1 + size
    local head_col = 0xFFD700FF -- gold
    local shadow_col = 0x00000088
    r.ImGui_DrawList_AddRectFilled(dl, x1+1, y1+1, x2+1, y2+1, shadow_col, 2)
    r.ImGui_DrawList_AddRectFilled(dl, x1,   y1,   x2,   y2,   head_col, 2)
    local stem_w = math.max(2, math.floor(size * 0.2))
    local stem_h = math.floor(size * 0.7)
    local sx1 = x1 + math.floor(size * 0.5) - math.floor(stem_w * 0.5)
    local sy1 = y2 - math.floor(stem_w * 0.5)
    local sx2 = sx1 + stem_w
    local sy2 = sy1 + stem_h
    r.ImGui_DrawList_AddRectFilled(dl, sx1+1, sy1+1, sx2+1, sy2+1, shadow_col, 1)
    r.ImGui_DrawList_AddRectFilled(dl, sx1,   sy1,   sx2,   sy2,   head_col, 1)
end


function DrawFavoriteOverlayAt(tlx, tly, w, h)
    if not config.show_favorite_overlay then return end
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local size = (config and config.overlay_icon_size) or 14
    local pad = 5
    local x1 = tlx + pad
    local y1 = tly + pad
    local x2 = x1 + size
    local y2 = y1 + size
    local badge_col = 0xFFD700FF 
    local shadow_col = 0x00000088
    
    local rounding = math.floor(size * 0.5)
    r.ImGui_DrawList_AddRectFilled(dl, x1+1, y1+1, x2+1, y2+1, shadow_col, rounding)
    r.ImGui_DrawList_AddRectFilled(dl, x1,   y1,   x2,   y2,   badge_col, rounding)
end

function DrawHorizontalSeparatorBar(thickness, color)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local x1 = sx + 2
    local x2 = sx + math.max(0, avail_w - 2)
    local t = thickness or ((config and config.compact_screenshots) and 2 or 3)
    local col = color or 0x606060FF
    r.ImGui_DrawList_AddRectFilled(dl, x1, sy, x2, sy + t, col, 2)
    r.ImGui_Dummy(ctx, 0, t + ((config and config.compact_screenshots) and 4 or 8))
end

function DrawMasonryLayout(screenshots)
    local initial_spacing = 0
    if not top_screenshot_spacing_applied then
        initial_spacing = 6 
        top_screenshot_spacing_applied = true
    end
    local available_width = r.ImGui_GetContentRegionAvail(ctx)
    local column_width = display_size + 10
    local num_columns = math.max(1, math.floor(available_width / column_width))
    local column_heights = {}
    local padding = config.compact_screenshots and 2 or 20

    for i = 1, num_columns do
        column_heights[i] = initial_spacing
    end

    for i, fx in ipairs(screenshots) do
        if fx.is_separator then
            local max_h = 0
            for c = 1, num_columns do if column_heights[c] > max_h then max_h = column_heights[c] end end
            r.ImGui_SetCursorPos(ctx, padding, max_h)
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
            local avail_w = r.ImGui_GetContentRegionAvail(ctx)
            local x1 = sx + 2
            local x2 = sx + math.max(0, avail_w - 2)
            local thickness = (config.compact_screenshots and 2) or 3
            local col = 0x606060FF
            r.ImGui_DrawList_AddRectFilled(dl, x1, sy, x2, sy + thickness, col, 2)
            if fx.kind == 'pinned_end' or fx.kind == 'favorites_end' then
                local glyph = (fx.kind == 'pinned_end') and '📌' or '★'
                r.ImGui_SetCursorPos(ctx, padding + 4, max_h - (config.compact_screenshots and 0 or 2))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                r.ImGui_Text(ctx, glyph)
                r.ImGui_PopStyleColor(ctx)
            end
            local sep_height = thickness + (config.compact_screenshots and 8 or 14)
            for c = 1, num_columns do column_heights[c] = max_h + sep_height end
            goto continue
        end
        if fx.is_message then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFF00FF)
            local display_name = GetDisplayPluginName(fx.name)
            r.ImGui_TextWrapped(ctx, display_name)
            r.ImGui_PopStyleColor(ctx)
            goto continue 
        end
        
        local shortest_column = 1
        for col = 2, num_columns do
            if column_heights[col] < column_heights[shortest_column] then
                shortest_column = col
            end
        end

        local pos_x = (shortest_column - 1) * column_width + padding
        local pos_y = column_heights[shortest_column]

    r.ImGui_SetCursorPos(ctx, pos_x, pos_y)
    local item_tlx, item_tly = r.ImGui_GetCursorScreenPos(ctx)

        local safe_name = fx.name:gsub("[^%w%s-]", "_")
        local screenshot_file = screenshot_path .. safe_name .. ".png"
        if r.file_exists(screenshot_file) then
            local texture = LoadSearchTexture(screenshot_file, fx.name)
            if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                local width, height = r.ImGui_Image_GetSize(texture)
                if width and height then
                    local display_width, display_height = ScaleScreenshotSize(width, height, display_size)

                    r.ImGui_BeginGroup(ctx)

                    local masonry_clicked = r.ImGui_ImageButton(ctx, "masonry_" .. i, texture, display_width, display_height)
                    if IsPluginPinned and IsPluginPinned(fx.name) then DrawPinnedOverlayAt(item_tlx, item_tly, display_width, display_height) end
                    if favorite_set and favorite_set[fx.name] then DrawFavoriteOverlayAt(item_tlx, item_tly, display_width, display_height) end

                    if config.enable_drag_add_fx then
                        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx,0) then
                            potential_drag_fx_name = fx.name
                            drag_start_x, drag_start_y = r.ImGui_GetMousePos(ctx)
                        end
                        if potential_drag_fx_name == fx.name and r.ImGui_IsMouseDown(ctx,0) then
                            local mx,my = r.ImGui_GetMousePos(ctx)
                            if math.abs(mx-drag_start_x) > 3 or math.abs(my-drag_start_y) > 3 then
                                dragging_fx_name = fx.name
                                potential_drag_fx_name = nil
                            end
                        end
                        if potential_drag_fx_name == fx.name and r.ImGui_IsMouseReleased(ctx,0) then
                            potential_drag_fx_name = nil
                        end
                    end

                    local should_add = false
                    if config.add_fx_with_double_click then
                        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx,0) and dragging_fx_name ~= fx.name then
                            should_add = true
                        end
                    else
                        if masonry_clicked and dragging_fx_name ~= fx.name then
                            should_add = true
                        end
                    end
                    if should_add then
                        local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                        if target_track then
                            AddFXToTrack(target_track, fx.name)
                            LAST_USED_FX = fx.name
                            if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                        end
                    end

                    if selected_folder == "Current Track FX" then
                        ShowFXContextMenu({
                            fx_name = fx.name,
                            track_number = TRACK and r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER") or 0,
                            fx_index = fx.fx_index
                        }, "masonry_track_" .. i)
                    else
                        ShowPluginContextMenu(fx.name, "masonry_" .. i)
                    end

                    local text_height = 0
                    if config.show_name_in_screenshot_window and not config.hidden_names[fx.name] then
                        local y_before = r.ImGui_GetCursorPosY(ctx)
                        r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                        local display_name = GetDisplayPluginName(fx.name)
                        r.ImGui_Text(ctx, display_name)
                        r.ImGui_PopTextWrapPos(ctx)
                        r.ImGui_Text(ctx, GetStarsString(fx.name)) 
                        local y_after = r.ImGui_GetCursorPosY(ctx)
                        text_height = y_after - y_before
                    end

                    r.ImGui_EndGroup(ctx)

                    local total_height = display_height + text_height + (config.compact_screenshots and 2 or 10)
                    column_heights[shortest_column] = column_heights[shortest_column] + total_height
                end
            end
        end
        ::continue:: 
    end
    local max_height = 0
    for i = 1, #column_heights do
        if column_heights[i] > max_height then max_height = column_heights[i] end
    end
    r.ImGui_SetCursorPosY(ctx, max_height + (config.compact_screenshots and 4 or 16))
end

function RenderScriptsLauncherSection(popped_view_stylevars)
    
    ShowScreenshotControls()
    r.ImGui_Separator(ctx)
    
    if not popped_view_stylevars then
        r.ImGui_PopStyleVar(ctx, 2); popped_view_stylevars = true
    end
    
    scripts_launcher = scripts_launcher or {}
  
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 14, 14)
    if r.ImGui_Button(ctx, "+##AddScriptLauncher", 20, 20) then
        show_add_script_popup = true
        new_script_name = ""
        new_script_cmd = ""
        new_script_thumb = ""
        r.ImGui_OpenPopup(ctx, "Add Script")
    end
    r.ImGui_PopStyleVar(ctx)
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add script or action") end

    if r.ImGui_BeginPopupModal(ctx, "Add Script", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        new_script_name = new_script_name or ""
        new_script_cmd = new_script_cmd or ""
        new_script_thumb = new_script_thumb or ""
        local changedName, inpName = r.ImGui_InputText(ctx, "Naam", new_script_name)
        if changedName then new_script_name = inpName end
        local changedCmd, inpCmd = r.ImGui_InputText(ctx, "Script / Action ID", new_script_cmd)
        if changedCmd then new_script_cmd = inpCmd end
        r.ImGui_Text(ctx, "Thumbnail (120x80 recommended)")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "choose...") then
            local ok, file = r.GetUserFileNameForRead("", "Choose Image", "png;bmp;jpg;jpeg")
            if ok and file and file ~= "" then new_script_thumb = file end
        end
        if new_script_thumb ~= "" then
            local short = new_script_thumb:match("[^/\\]+$") or new_script_thumb
            r.ImGui_Text(ctx, short)
        else
            r.ImGui_Text(ctx, "(no Image chosen)")
        end
        r.ImGui_Separator(ctx)
        local can_save = (new_script_name ~= "" and new_script_cmd ~= "")
        if not can_save then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx, "SAVE", 60, 25) then
            table.insert(scripts_launcher, {name=new_script_name, cmd=new_script_cmd, thumb=new_script_thumb})
            SaveScriptsLauncher()
            r.ImGui_CloseCurrentPopup(ctx)
        end
        if not can_save then r.ImGui_EndDisabled(ctx) end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "CANCEL", 60, 25) then r.ImGui_CloseCurrentPopup(ctx) end
        r.ImGui_EndPopup(ctx)
    end

    local window_height = r.ImGui_GetWindowHeight(ctx)
    local current_y = r.ImGui_GetCursorPosY(ctx)
    local footer_height = 0 
    local available_height = window_height - current_y - footer_height
    r.ImGui_BeginChild(ctx, "ScriptsLauncherList", -1, available_height)
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        local cell_w = 120
        local cell_h = 80
        local spacing = 12
        local start_x = r.ImGui_GetCursorPosX(ctx)
        local x = start_x
        local y = r.ImGui_GetCursorPosY(ctx)
    local cols = math.max(1, math.floor((avail_w + spacing) / (cell_w + spacing)))
    local col_index = 0
        for i, sc in ipairs(scripts_launcher) do
            if col_index >= cols then
                col_index = 0
                x = start_x
                y = y + cell_h + spacing + 30 
            end
            r.ImGui_SetCursorPos(ctx, x, y)
            local id = "script_cell_" .. i
            local cell_clicked = false
            if sc.thumb and sc.thumb ~= "" and r.file_exists(sc.thumb) then
                local tex = LoadSearchTexture(sc.thumb, sc.thumb)
                if tex and r.ImGui_ValidatePtr(tex, 'ImGui_Image*') then
                    if r.ImGui_ImageButton(ctx, id, tex, cell_w, cell_h) then cell_clicked = true end
                else
                    if r.ImGui_Button(ctx, sc.name .. "##btn" .. i, cell_w, cell_h) then cell_clicked = true end
                end
            else
                if r.ImGui_Button(ctx, sc.name .. "##btn" .. i, cell_w, cell_h) then cell_clicked = true end
            end

            if cell_clicked then
                local cmd = sc.cmd
                if cmd:match("^_") then
                    local cmd_id = r.NamedCommandLookup(cmd)
                    if cmd_id ~= 0 then r.Main_OnCommand(cmd_id, 0) end
                elseif tonumber(cmd) then
                    r.Main_OnCommand(tonumber(cmd), 0)
                end
            end

            if r.ImGui_IsItemClicked(ctx, 1) then
                edit_script_index = i
                edit_script_name = sc.name
                edit_script_cmd = sc.cmd
                edit_script_thumb = sc.thumb
            end
            local text_w = r.ImGui_CalcTextSize(ctx, sc.name)
            r.ImGui_SetCursorPos(ctx, x + (cell_w - text_w)/2, y + cell_h + 4)
            r.ImGui_Text(ctx, sc.name)
            col_index = col_index + 1
            x = x + cell_w + spacing
        end
        if edit_script_index then
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Edit Script:")
            local idx = edit_script_index
            local sc_edit = scripts_launcher[idx]
            edit_script_name = edit_script_name or sc_edit.name
            edit_script_cmd  = edit_script_cmd or sc_edit.cmd
            edit_script_thumb = edit_script_thumb or sc_edit.thumb
            local c1, n1 = r.ImGui_InputText(ctx, "Naam", edit_script_name)
            if c1 then edit_script_name = n1 end
            local c2, n2 = r.ImGui_InputText(ctx, "Script / Action ID", edit_script_cmd)
            if c2 then edit_script_cmd = n2 end
            r.ImGui_Text(ctx, "Thumbnail (120x80)")
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "choose...##EditThumb") then
                local ok, file = r.GetUserFileNameForRead("", "Choose Image", "png;bmp;jpg;jpeg")
                if ok and file and file ~= "" then edit_script_thumb = file end
            end
            if edit_script_thumb and edit_script_thumb ~= "" then
                local short = edit_script_thumb:match("[^/\\]+$") or edit_script_thumb
                r.ImGui_Text(ctx, short)
            else
                r.ImGui_Text(ctx, "(No Image Chosen)")
            end
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x228B22FF)
            if r.ImGui_Button(ctx, "SAVE", 60, 26) then
                scripts_launcher[idx].name  = (edit_script_name ~= "" and edit_script_name) or scripts_launcher[idx].name
                scripts_launcher[idx].cmd   = (edit_script_cmd ~= "" and edit_script_cmd) or scripts_launcher[idx].cmd
                scripts_launcher[idx].thumb = edit_script_thumb or scripts_launcher[idx].thumb
                SaveScriptsLauncher()
                edit_script_index = nil
                edit_script_name, edit_script_cmd, edit_script_thumb = nil, nil, nil
            end
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "CANCEL", 60, 26) then
                edit_script_index = nil
                edit_script_name, edit_script_cmd, edit_script_thumb = nil, nil, nil
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xAA2222FF)
            if r.ImGui_Button(ctx, "All", 20, 20) then
                screenshot_search_results = {}
                local MAX_RESULTS = 200
                local term = browser_search_term:lower()
                local matches = {}
                for _, plugin in ipairs(PLUGIN_LIST) do
                    if plugin:lower():find(term, 1, true) then
                        table.insert(matches, plugin)
                    end
                end
                if config.apply_type_priority then
                    matches = DedupeByTypePriority(matches)
                end
                local total = #matches
                local limit = math.min(total, MAX_RESULTS)
                for i = 1, limit do
                    table.insert(screenshot_search_results, { name = matches[i] })
                end

                SortScreenshotResults()
                ClearScreenshotCache()
                if total > MAX_RESULTS then
                    search_warning_message = "Showing first " .. MAX_RESULTS .. " results. Please refine your search for more specific results."
                end

                new_search_performed = true
            end
            r.ImGui_PopStyleColor(ctx)
        end 
    r.ImGui_EndChild(ctx)
    return popped_view_stylevars
end

function ShowScreenshotWindow()
    if not screenshot_search_results then
        screenshot_search_results = {}
    end

    local function FilterSearchResults()
        if not config.respect_search_exclusions_in_screenshots or not config.excluded_plugins then return end
        if not screenshot_search_results or #screenshot_search_results == 0 then return end
        local filtered = {}
        for i = 1, #screenshot_search_results do
            local entry = screenshot_search_results[i]
            local pname = entry and entry.name or entry
            if pname and not config.excluded_plugins[pname] then
                filtered[#filtered+1] = entry
            end
        end
        screenshot_search_results = filtered
    end

    FilterSearchResults()

    top_screenshot_spacing_applied = false

    local active_folder = browser_panel_selected or selected_folder

    if (not screenshot_search_results or #screenshot_search_results == 0) and (not active_folder) then
        if config.default_folder then
            if config.default_folder == LAST_OPENED_SENTINEL and last_viewed_folder then
                selected_folder = last_viewed_folder
            else
                selected_folder = config.default_folder
            end
        end
    end

    if config.default_folder and not initialized_default then
        local df = config.default_folder
        if df == LAST_OPENED_SENTINEL then
            if last_viewed_folder then
                if IsNonFoldersSubgroup(last_viewed_folder) then
                    browser_panel_selected = last_viewed_folder
                    selected_folder = nil
                    MarkForcedHeaderForSubgroup(last_viewed_folder)
                    current_filtered_fx = GetFxListForSubgroup(last_viewed_folder) or {}
                    if config.apply_type_priority then
                        current_filtered_fx = DedupeByTypePriority(current_filtered_fx)
                    end
                    screenshot_search_results = {}
                    local cap = loaded_items_count or ITEMS_PER_BATCH or 30
                    for j = 1, math.min(cap, #current_filtered_fx) do
                        table.insert(screenshot_search_results, {name = current_filtered_fx[j]})
                    end
                    if SortScreenshotResults then SortScreenshotResults() end
                    did_initial_refresh = true
                else
                    browser_panel_selected = nil
                    selected_folder = last_viewed_folder
                    did_initial_refresh = true
                    if RefreshCurrentScreenshotView then RefreshCurrentScreenshotView() end
                    if SortScreenshotResults then SortScreenshotResults() end
                end
                BuildAutoExpandPaths(last_viewed_folder)
            end
        elseif df == "Projects" then
            show_media_browser = true
            show_sends_window = false
            show_action_browser = false
            selected_folder = nil
            LoadProjects()
        elseif df == "Sends/Receives" then
            show_media_browser = false
            show_sends_window = true
            show_action_browser = false
            selected_folder = nil
        elseif df == "Actions" then
            show_media_browser = false
            show_sends_window = false
            show_action_browser = true
            selected_folder = nil
        else
            selected_folder = df
            did_initial_refresh = true
            if RefreshCurrentScreenshotView then RefreshCurrentScreenshotView() end
            if SortScreenshotResults then SortScreenshotResults() end
            BuildAutoExpandPaths(df)
        end
        initialized_default = true
    end

    if not did_initial_refresh and (selected_folder or browser_panel_selected) then
        if RefreshCurrentScreenshotView then RefreshCurrentScreenshotView() end
        did_initial_refresh = true
        if selected_folder then BuildAutoExpandPaths(selected_folder) end
    end
    
    local main_window_pos_x, main_window_pos_y = r.ImGui_GetWindowPos(ctx)
    local main_window_width = r.ImGui_GetWindowWidth(ctx)
    local main_window_height = r.ImGui_GetWindowHeight(ctx)

    local browser_panel_width = config.show_browser_panel and config.browser_panel_width or 0
    local screenshot_min_width = 145  
    local total_min_width = browser_panel_width + screenshot_min_width + 5 

    local min_width = config.show_browser_panel and total_min_width or screenshot_min_width
    local window_flags = r.ImGui_WindowFlags_NoTitleBar() |
                    r.ImGui_WindowFlags_NoFocusOnAppearing() |
                    
                    r.ImGui_WindowFlags_NoScrollbar()

    if config.dock_screenshot_window then
        local viewport = r.ImGui_GetMainViewport(ctx)
        local viewport_pos_x, viewport_pos_y = r.ImGui_Viewport_GetPos(viewport)
        local viewport_width = r.ImGui_Viewport_GetWorkSize(viewport)
        local gap = 10

        local is_main_window_left_docked = (main_window_pos_x - viewport_pos_x) < 20
        local is_main_window_right_docked = (main_window_pos_x + main_window_width) > (viewport_pos_x + viewport_width - 20)
        
        if is_main_window_left_docked then
            config.dock_screenshot_left = false
        elseif is_main_window_right_docked then
            config.dock_screenshot_left = true
        end
        
        if config.dock_screenshot_left then
            local browser_offset = (config.show_browser_panel and config.dock_screenshot_left) and (config.browser_panel_width + 5) or 0
            local left_pos = main_window_pos_x - config.screenshot_window_width - (2 * gap) - browser_offset
            r.ImGui_SetNextWindowPos(ctx, left_pos, main_window_pos_y, r.ImGui_Cond_Always())
        else
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
        local popped_view_stylevars = false
        r.ImGui_PushFont(ctx, NormalFont, 11)
    
        if show_media_browser and not popped_view_stylevars then
            r.ImGui_PopStyleVar(ctx, 2); popped_view_stylevars = true
            r.ImGui_SameLine(ctx)
        elseif show_sends_window and not popped_view_stylevars then
            r.ImGui_PopStyleVar(ctx, 2); popped_view_stylevars = true
            r.ImGui_SameLine(ctx)
        elseif show_action_browser and not popped_view_stylevars then
            r.ImGui_PopStyleVar(ctx, 2); popped_view_stylevars = true
            r.ImGui_SameLine(ctx)
        else
            r.ImGui_SameLine(ctx)
        end
        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            r.ImGui_PopFont(ctx)
        end

--------------------------------------------------------------------------------------
        -- PROJECTS GEDEELTE:
        local is_screenshot_branch = false
        if show_scripts_browser then
            popped_view_stylevars = RenderScriptsLauncherSection(popped_view_stylevars)
        elseif show_media_browser then
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
                    
                    if r.ImGui_IsItemClicked(ctx, 1) then 
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
            r.ImGui_BeginChild(ctx, "ProjectsList", -1, available_height)
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
                            has_preview = has_preview,
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
            if show_project_info then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x333333FF)
                r.ImGui_Separator(ctx)
                
                if current_project_info then
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
                r.ImGui_Separator(ctx)
                local window_height = r.ImGui_GetWindowHeight(ctx)
                local current_y = r.ImGui_GetCursorPosY(ctx)
                local footer_height = 40
                local available_height = window_height - current_y - footer_height

                r.ImGui_BeginChild(ctx, "SendsReceivesList", 0, available_height)
                    
                    if show_routing_matrix and show_matrix_exclusive then
                        ShowRoutingMatrix()
                    else
                    -- SENDS SECTIE
                    r.ImGui_Text(ctx, "SENDS:")
                    
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
                                                r.SetTrackSendInfo_Value(TRACK, 0, j, "B_MUTE", j == i and 0 or 1)
                                            else
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
                                                r.InsertTrackAtIndex(track_count, true)
                                                local folder_track = r.GetTrack(0, track_count)
                                                r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", "SEND TRACK", true)
                                                r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)
                                                
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
                        
                        r.ImGui_Dummy(ctx, 0, 10)  
                
                        -- RECEIVES SECTIE
                        r.ImGui_Separator(ctx)
                        r.ImGui_Text(ctx, "RECEIVES:")
                        
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
                                                r.SetTrackSendInfo_Value(TRACK, -1, j, "B_MUTE", j == i and 0 or 1)
                                            else
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
                    r.ImGui_Dummy(ctx, 0, 10) 
                
                if show_routing_matrix then
                    ShowRoutingMatrix()
                end
            r.ImGui_EndChild(ctx)
            r.ImGui_Separator(ctx)
            if r.ImGui_Button(ctx, "Matrix View") then
                  show_routing_matrix = not show_routing_matrix
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, show_matrix_exclusive and "Normal" or "Exclusive") then
                 show_matrix_exclusive = not show_matrix_exclusive
             end
                

    end
--------------------------------------------------------------------------------------
        -- ACTIONS GEDEELTE
        elseif show_action_browser then
            -- Keep the top controls (settings, dropdown, search) visible like other panels
            ShowScreenshotControls()
            r.ImGui_Separator(ctx)
            RenderActionsSection()

--------------------------------------------------------------------------------------
        -- SCREENSHOTS GEDEELTE    
        else
    is_screenshot_branch = true
        ShowScreenshotControls()
        local available_width = r.ImGui_GetContentRegionAvail(ctx)
        if config.use_global_screenshot_size then
            display_size = config.global_screenshot_size
        elseif config.resize_screenshots_with_window then
            display_size = available_width - 10
        else
        display_size = selected_folder and (config.folder_specific_sizes[selected_folder] or config.screenshot_window_size) or config.screenshot_window_size
        end
        local num_columns = math.max(1, math.floor(available_width / display_size))
        local column_width = available_width / num_columns 
        
        if search_warning_message then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFF00FF) -- Gele tekst
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x444400FF) -- Donkere achtergrond
            r.ImGui_BeginChild(ctx, "SearchWarning", -1, 25)
            local text_width = r.ImGui_CalcTextSize(ctx, search_warning_message)
            local window_width = r.ImGui_GetWindowWidth(ctx)
            local center_x = (window_width - text_width) * 0.5
            r.ImGui_SetCursorPosX(ctx, center_x)
            r.ImGui_Text(ctx, search_warning_message)
            r.ImGui_EndChild(ctx)
        r.ImGui_PopStyleColor(ctx, 2)
        end
   
    local folder_match_count = nil
    local active_folder_for_tip = browser_panel_selected or selected_folder
    if (not search_warning_message) and browser_search_term ~= "" and active_folder_for_tip then
        local folder_plugins = current_filtered_fx and #current_filtered_fx > 0 and current_filtered_fx or GetPluginsForFolder(active_folder_for_tip)
        if folder_plugins then
            local cnt = 0
            local term = browser_search_term:lower()
            for _, p in ipairs(folder_plugins) do
                if p:lower():find(term, 1, true) then
                    cnt = cnt + 1
                    if cnt >= 3 then break end -- we hoeven alleen te weten of het <3 blijft
                end
            end
            folder_match_count = cnt
        end
    end
    local show_folder_tip = (not search_warning_message) and folder_match_count and folder_match_count > 0 and folder_match_count < 3
        if show_folder_tip then
            local tip_text = "Tip: Press 'All' for a global search if you miss results."
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFAA00FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x332200FF)
            r.ImGui_BeginChild(ctx, "SearchFolderTip", -1, 22)
                local text_w = r.ImGui_CalcTextSize(ctx, tip_text)
                local win_w = r.ImGui_GetWindowWidth(ctx)
                r.ImGui_SetCursorPosX(ctx, (win_w - text_w) * 0.5)
                r.ImGui_Text(ctx, tip_text)
            r.ImGui_EndChild(ctx)
            r.ImGui_PopStyleColor(ctx, 2)
        end

    r.ImGui_BeginChild(ctx, "ScreenshotList", 0, 0)
            if config.flicker_guard_enabled then
                local now = r.time_precise()
                local sig = _build_screenshot_signature()
                local sig_changed = (sig ~= _last_screenshot_signature)
                local typed_recently = (now - _last_search_input_time) * 1000.0 < _search_debounce_ms
                if sig_changed and not typed_recently then
                    if _pending_clear_cache then
                        ClearScreenshotCache()
                        _pending_clear_cache = false
                    end
                    _last_screenshot_signature = sig
                end
            end
            local scroll_y = r.ImGui_GetScrollY(ctx)
            local scroll_max_y = r.ImGui_GetScrollMaxY(ctx)
            if current_filtered_fx and not config.use_pagination and scroll_y > 0 and scroll_y/scroll_max_y > 0.8 and #current_filtered_fx > loaded_items_count then
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
                    local pinned, others = {}, {}
                    local term = browser_search_term:lower()
                    for _, plugin in ipairs(filtered_plugins) do
                        if plugin:lower():find(term, 1, true) then
                            if IsPluginPinned and IsPluginPinned(plugin) then pinned[#pinned+1] = plugin else others[#others+1] = plugin end
                        end
                    end
                    if config.apply_type_priority then
                        pinned = DedupeByTypePriority(pinned)
                        others = DedupeByTypePriority(others)
                    end
                    SortPlainPluginList(pinned, config.sort_mode)
                    SortPlainPluginList(others, config.sort_mode)
                    local display_plugins = {}
                    
                    -- Add pinned plugins first if show_pinned_on_top is enabled
                    if config and config.show_pinned_on_top then
                        for _, p in ipairs(pinned) do display_plugins[#display_plugins+1] = p end
                        if #pinned > 0 and #others > 0 then display_plugins[#display_plugins+1] = "--Pinned End--" end
                    else
                        -- Add pinned plugins to others if show_pinned_on_top is disabled
                        for _, p in ipairs(pinned) do others[#others+1] = p end
                        SortPlainPluginList(others, config.sort_mode)
                    end
                    
                    for _, p in ipairs(others) do display_plugins[#display_plugins+1] = p end
                    filtered_plugins = display_plugins
                    -- Sync visible names for texture pruning (Current Track FX)
                    current_filtered_fx = {}
                    for _, fx in ipairs(display_plugins) do
                        if type(fx) == 'table' and fx.fx_name then
                            current_filtered_fx[#current_filtered_fx+1] = fx.fx_name
                        end
                    end
                    -- Sync visible list for texture pruning (custom folders)
                    current_filtered_fx = {}
                    for _, name in ipairs(display_plugins) do
                        if type(name) == 'string' and name ~= "--Favorites End--" and name ~= "--Pinned End--" then
                            current_filtered_fx[#current_filtered_fx+1] = name
                        end
                    end

                    if #filtered_plugins == 0 then
                        r.ImGui_Text(ctx, "No Favorites match search.")
                    else
                        if view_mode == "list" then
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 2, 2)
                            for i, plugin_name in ipairs(filtered_plugins) do
                                if plugin_name == "--Pinned End--" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                                    r.ImGui_Text(ctx, "--- Pinned End ---")
                                    r.ImGui_PopStyleColor(ctx)
                                else
                                    local display_name = GetDisplayPluginName(plugin_name)
                                    local stars = GetStarsString(plugin_name)
                                    local activated = r.ImGui_Selectable(ctx, display_name .. (stars ~= "" and "  " .. stars or "") .. "##fav_list_" .. i, false)
                                local do_add = false
                                if config.add_fx_with_double_click then
                                    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                        do_add = true
                                    end
                                else
                                    if activated then do_add = true end
                                end
                                if do_add then
                                    local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                                    if target_track then
                                        AddFXToTrack(target_track, plugin_name)
                                        LAST_USED_FX = plugin_name
                                        if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                    end
                                end
                                ShowPluginContextMenu(plugin_name, "favorites_list_ctx_" .. i)
                                end
                            end
                            r.ImGui_PopStyleVar(ctx)
                        elseif config.use_masonry_layout then
                            local with_shot, missing = SplitPluginsByScreenshot(filtered_plugins)
                            local masonry_data = {}
                            for _, plugin in ipairs(with_shot) do
                                if plugin == "--Favorites End--" then
                                    masonry_data[#masonry_data+1] = {is_separator = true, label = "--- Favorites End ---"}
                                elseif plugin == "--Pinned End--" then
                                    masonry_data[#masonry_data+1] = {is_separator = true, label = "--- Pinned End ---"}
                                else
                                    masonry_data[#masonry_data+1] = {name = plugin}
                                end
                            end
                            DrawMasonryLayout(masonry_data)
                            RenderMissingList(missing)
                        else
                            local with_shot, missing = SplitPluginsByScreenshot(filtered_plugins)
                            ApplyTopScreenshotSpacing()
                            for i, plugin_name in ipairs(with_shot) do
                                if plugin_name == "--Favorites End--" or plugin_name == "--Pinned End--" then
                                    DrawHorizontalSeparatorBar((config.compact_screenshots and 2 or 3), 0x606060FF)
                                    r.ImGui_Dummy(ctx, 0, (config.compact_screenshots and 6 or 10))
                                else
                                    local column = (i - 1) % num_columns
                                    if column > 0 then r.ImGui_SameLine(ctx) end
                                    r.ImGui_BeginGroup(ctx)
                                    local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                                    local screenshot_file = screenshot_path .. safe_name .. ".png"
                                    local texture = LoadSearchTexture(screenshot_file, plugin_name)
                                    if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                        local w, h = r.ImGui_Image_GetSize(texture)
                                        if w and h then
                                            local dw, dh = ScaleScreenshotSize(w, h, display_size)
                                            local clicked = r.ImGui_ImageButton(ctx, "fav_" .. i, texture, dw, dh)
                                            if IsPluginPinned and IsPluginPinned(plugin_name) then
                                                local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                                local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                                DrawPinnedOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                            end
                                            if favorite_set and favorite_set[plugin_name] then
                                                local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                                local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                                DrawFavoriteOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                            end
                                            if config.enable_drag_add_fx then
                                                if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx,0) then
                                                    potential_drag_fx_name = plugin_name
                                                    drag_start_x, drag_start_y = r.ImGui_GetMousePos(ctx)
                                                end
                                                if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseDown(ctx,0) then
                                                    local mx,my = r.ImGui_GetMousePos(ctx)
                                                    if math.abs(mx-drag_start_x) > 3 or math.abs(my-drag_start_y) > 3 then
                                                        dragging_fx_name = plugin_name
                                                        potential_drag_fx_name = nil
                                                    end
                                                end
                                                if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseReleased(ctx,0) then
                                                    potential_drag_fx_name = nil
                                                end
                                            end
                                            local do_add = false
                                            if config.add_fx_with_double_click then
                                                if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx,0) and dragging_fx_name ~= plugin_name then do_add = true end
                                            else
                                                if clicked and dragging_fx_name ~= plugin_name then do_add = true end
                                            end
                                            if do_add then
                                                local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                                                if target_track then
                                                    local fx_index = AddFXToTrack(target_track, plugin_name)
                                                    LAST_USED_FX = plugin_name
                                                    if config.open_floating_after_adding and fx_index >= 0 then
                                                        r.TrackFX_Show(target_track, fx_index, 3)
                                                    end
                                                    if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                                end
                                            end
                                            ShowPluginContextMenu(plugin_name, "favorites_win_" .. i)
                                            if config.show_name_in_screenshot_window and not config.hidden_names[plugin_name] then
                                                r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + dw)
                                                local display_name = GetDisplayPluginName(plugin_name)
                                                r.ImGui_Text(ctx, display_name)
                                                r.ImGui_PopTextWrapPos(ctx)
                                                r.ImGui_Text(ctx, GetStarsString(plugin_name))
                                            end
                                        end
                                    end
                                    r.ImGui_EndGroup(ctx)
                                    if not config.compact_screenshots and column == num_columns - 1 then
                                        r.ImGui_Dummy(ctx, 0, 5)
                                    end
                                end
                            end
                            RenderMissingList(missing)
                        end

                    end -- END favorites condition

                -- CUSTOM FOLDERS RENDERING
                elseif (selected_folder and next(GetPluginsFromCustomFolder(selected_folder) or {}) ~= nil) then
                    filtered_plugins = GetPluginsFromCustomFolder(selected_folder or "") or {}
                    local display_plugins = {}
                    if config.show_favorites_on_top then
                        local term_l = GetLowerName(browser_search_term)
                        local pinned, favorites, regular = {}, {}, {}
                        for _, plugin in ipairs(filtered_plugins) do
                            if GetLowerName(plugin):find(term_l, 1, true) then
                                if IsPluginPinned and IsPluginPinned(plugin) then
                                    pinned[#pinned+1] = plugin
                                elseif favorite_set[plugin] then
                                    favorites[#favorites+1] = plugin
                                else
                                    regular[#regular+1] = plugin
                                end
                            end
                        end
                        if config.apply_type_priority then
                            pinned = DedupeByTypePriority(pinned)
                            favorites = DedupeByTypePriority(favorites)
                            regular = DedupeByTypePriority(regular)
                        end
                        SortPlainPluginList(pinned, config.sort_mode)
                        SortPlainPluginList(favorites, config.sort_mode)
                        SortPlainPluginList(regular, config.sort_mode)
                        
                        -- Add pinned plugins first if show_pinned_on_top is enabled
                        if config and config.show_pinned_on_top then
                            for _, p in ipairs(pinned) do display_plugins[#display_plugins+1] = p end
                            if #pinned>0 and (#favorites>0 or #regular>0) then display_plugins[#display_plugins+1] = "--Pinned End--" end
                        else
                            -- Add pinned plugins to regular if show_pinned_on_top is disabled
                            for _, p in ipairs(pinned) do regular[#regular+1] = p end
                            SortPlainPluginList(regular, config.sort_mode)
                        end
                        
                        for _, p in ipairs(favorites) do display_plugins[#display_plugins+1] = p end
                        if #favorites>0 and #regular>0 then display_plugins[#display_plugins+1] = "--Favorites End--" end
                        for _, p in ipairs(regular) do display_plugins[#display_plugins+1] = p end
                    else
                        -- show_favorites_on_top is false: still check pinned-on-top setting
                        local term_l = GetLowerName(browser_search_term)
                        local pinned, others = {}, {}
                        for _, plugin in ipairs(filtered_plugins) do
                            if GetLowerName(plugin):find(term_l,1,true) then
                                if IsPluginPinned and IsPluginPinned(plugin) then pinned[#pinned+1] = plugin else others[#others+1] = plugin end
                            end
                        end
                        if config.apply_type_priority then
                            pinned = DedupeByTypePriority(pinned)
                            others = DedupeByTypePriority(others)
                        end
                        SortPlainPluginList(pinned, config.sort_mode)
                        SortPlainPluginList(others, config.sort_mode)
                        
                        -- Add pinned plugins first if show_pinned_on_top is enabled
                        if config and config.show_pinned_on_top then
                            for _, p in ipairs(pinned) do display_plugins[#display_plugins+1] = p end
                            if #pinned>0 and #others>0 then display_plugins[#display_plugins+1] = "--Pinned End--" end
                        else
                            -- Add pinned plugins to others if show_pinned_on_top is disabled
                            for _, p in ipairs(pinned) do others[#others+1] = p end
                            SortPlainPluginList(others, config.sort_mode)
                        end
                        
                        for _, p in ipairs(others) do display_plugins[#display_plugins+1] = p end
                    end
                    filtered_plugins = display_plugins
                    -- Sync visible names for texture pruning (Current Project FX)
                    current_filtered_fx = {}
                    for _, plugin in ipairs(display_plugins) do
                        if type(plugin) == 'table' and plugin.fx_name then
                            current_filtered_fx[#current_filtered_fx+1] = plugin.fx_name
                        end
                    end

                    if #filtered_plugins == 0 then
                        r.ImGui_Text(ctx, "No Custom Folder plugins match search.")
                    else
                        if view_mode == "list" then
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 2, 2)
                            for i, plugin_name in ipairs(filtered_plugins) do
                                if plugin_name == "--Favorites End--" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                                    r.ImGui_Text(ctx, "--- Favorites End ---")
                                    r.ImGui_PopStyleColor(ctx)
                                elseif plugin_name == "--Pinned End--" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                                    r.ImGui_Text(ctx, "--- Pinned End ---")
                                    r.ImGui_PopStyleColor(ctx)
                                else
                                    local display_name = GetDisplayPluginName(plugin_name)
                                    local stars = GetStarsString(plugin_name)
                                    local prefix = ""
                                    if config.show_pinned_overlay and IsPluginPinned and IsPluginPinned(plugin_name) then
                                        prefix = prefix .. "📌 "
                                    end
                                    if config.show_favorite_overlay and favorite_set and favorite_set[plugin_name] then
                                        prefix = prefix .. "★ "
                                    end
                                    local activated = r.ImGui_Selectable(ctx, prefix .. display_name .. (stars ~= "" and "  " .. stars or "") .. "##custom_list_" .. i, false)
                                    local do_add = false
                                    if config.add_fx_with_double_click then
                                        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx,0) then do_add = true end
                                    else
                                        if activated then do_add = true end
                                    end
                                    if do_add then
                                        local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                                        if target_track then
                                            AddFXToTrack(target_track, plugin_name)
                                            LAST_USED_FX = plugin_name
                                            if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                        end
                                    end
                                    ShowPluginContextMenu(plugin_name, "custom_list_ctx_" .. i)
                                end
                            end
                            r.ImGui_PopStyleVar(ctx)
                        elseif config.use_masonry_layout then
                            local with_shot, missing = SplitPluginsByScreenshot(filtered_plugins)
                            local masonry_data = {}
                            
                            for _, plugin in ipairs(with_shot) do
                                if plugin == "--Favorites End--" then
                                    masonry_data[#masonry_data+1] = { is_separator = true, kind = "favorites_end" }
                                elseif plugin == "--Pinned End--" then
                                    masonry_data[#masonry_data+1] = { is_separator = true, kind = "pinned_end" }
                                else
                                    masonry_data[#masonry_data+1] = { name = plugin }
                                end
                            end
                            DrawMasonryLayout(masonry_data)
                            RenderMissingList(missing)
                        else
                            local with_shot, missing = SplitPluginsByScreenshot(filtered_plugins)
                            ApplyTopScreenshotSpacing()
                            for i, plugin_name in ipairs(with_shot) do
                                if plugin_name == "--Favorites End--" or plugin_name == "--Pinned End--" then
                                    DrawHorizontalSeparatorBar((config.compact_screenshots and 2 or 3), 0x606060FF)
                                    r.ImGui_Dummy(ctx, 0, (config.compact_screenshots and 6 or 10))
                                else
                                    local column = (i - 1) % num_columns
                                    if column > 0 then r.ImGui_SameLine(ctx) end
                                    r.ImGui_BeginGroup(ctx)
                                    local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                                    local screenshot_file = screenshot_path .. safe_name .. ".png"
                                    local texture = LoadSearchTexture(screenshot_file, plugin_name)
                                    if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                        local w, h = r.ImGui_Image_GetSize(texture)
                                        if w and h then
                                            local dw, dh = ScaleScreenshotSize(w, h, display_size)
                                            local clicked = r.ImGui_ImageButton(ctx, "custom_" .. i, texture, dw, dh)
                                            if pinned_set and pinned_set[plugin_name] then
                                                local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                                local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                                DrawPinnedOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                            end
                                            if favorite_set and favorite_set[plugin_name] then
                                                local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                                local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                                DrawFavoriteOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                            end
                                            if config.enable_drag_add_fx then
                                                if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx,0) then
                                                    potential_drag_fx_name = plugin_name
                                                    drag_start_x, drag_start_y = r.ImGui_GetMousePos(ctx)
                                                end
                                                if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseDown(ctx,0) then
                                                    local mx,my = r.ImGui_GetMousePos(ctx)
                                                    if math.abs(mx-drag_start_x) > 3 or math.abs(my-drag_start_y) > 3 then
                                                        dragging_fx_name = plugin_name
                                                        potential_drag_fx_name = nil
                                                    end
                                                end
                                                if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseReleased(ctx,0) then
                                                    potential_drag_fx_name = nil
                                                end
                                            end
                                            local do_add = false
                                            if config.add_fx_with_double_click then
                                                if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx,0) and dragging_fx_name ~= plugin_name then do_add = true end
                                            else
                                                if clicked and dragging_fx_name ~= plugin_name then do_add = true end
                                            end
                                            if do_add then
                                                local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                                                if target_track then
                                                    local fx_index = AddFXToTrack(target_track, plugin_name)
                                                    LAST_USED_FX = plugin_name
                                                    if config.open_floating_after_adding and fx_index >= 0 then
                                                        r.TrackFX_Show(target_track, fx_index, 3)
                                                    end
                                                    if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                                end
                                            end
                                            ShowPluginContextMenu(plugin_name, "custom_win_" .. i)
                                            if config.show_name_in_screenshot_window and not config.hidden_names[plugin_name] then
                                                r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + dw)
                                                local display_name = GetDisplayPluginName(plugin_name)
                                                r.ImGui_Text(ctx, display_name)
                                                r.ImGui_PopTextWrapPos(ctx)
                                                r.ImGui_Text(ctx, GetStarsString(plugin_name))
                                            end
                                        end
                                    end
                                    r.ImGui_EndGroup(ctx)
                                    if not config.compact_screenshots and column == num_columns - 1 then
                                        r.ImGui_Dummy(ctx, 0, 5)
                                    end
                                end
                            end
                            RenderMissingList(missing)
                        end
                    end
                elseif selected_folder == "Current Project FX" then
                    filtered_plugins = GetCurrentProjectFX()
                    local display_plugins = {}
                    for _, fx in ipairs(filtered_plugins) do
                        if fx.fx_name:lower():find(browser_search_term:lower(), 1, true) then
                            table.insert(display_plugins, fx)
                        end
                    end
                    filtered_plugins = display_plugins
                    
                    if not screenshot_search_results then
                        screenshot_search_results = {}
                    end
                    
                    if #filtered_plugins > 0 then
                        local current_track_identifier = nil
                        local column_width = available_width / num_columns

                         for i, plugin in ipairs(filtered_plugins) do
                            local track_identifier
                            
                            if plugin.is_master then
                                track_identifier = "master_track"
                            else
                                track_identifier = (plugin.track_number or "Unknown") .. "_" .. (plugin.track_name or "Unnamed")
                            end
                            
                            if track_identifier ~= current_track_identifier then
                                current_track_identifier = track_identifier

                                if plugin.is_master then
                                    -- MASTER TRACK HEADER
                                    r.ImGui_Separator(ctx)
                                    -- Ensure no outstanding style vars are active while this child is open
                                    local _tmp_popped_stylevars_master = false
                                    if not popped_view_stylevars then r.ImGui_PopStyleVar(ctx, 2); _tmp_popped_stylevars_master = true end
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x404040FF)
                                    local _hdr_master_open = r.ImGui_BeginChild(ctx, "TrackHeaderMaster", -1, 20)
                                    r.ImGui_PopStyleColor(ctx) -- always pop ChildBg
                                    if _hdr_master_open then
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                                        
                                        local master_collapsed = master_track_collapsed or false
                                        if r.ImGui_Button(ctx, master_collapsed and "+" or "-", 20, 20) then
                                            master_track_collapsed = not master_collapsed
                                            ClearScreenshotCache()
                                        end
                                        
                                        r.ImGui_SameLine(ctx)
                                        if r.ImGui_Button(ctx, "Master Track") then
                                            r.SetOnlyTrackSelected(r.GetMasterTrack(0))
                                        end
                                        r.ImGui_PopStyleColor(ctx, 4)
                                        r.ImGui_EndChild(ctx)
                                    end
                                    r.ImGui_Dummy(ctx, 0, 0)
                                    if _tmp_popped_stylevars_master then
                                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), config.show_screenshot_scrollbar and 14 or 1)
                                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 0)
                                    end
                                else
                                    -- ANDERE TRACKS HEADER
                                    local track_color, text_color = GetTrackColorAndTextColor(reaper.GetTrack(0, plugin.track_number - 1))
                                    local track_number = plugin.track_number
                                    r.ImGui_Separator(ctx)
                                    -- Ensure no outstanding style vars are active while this child is open
                                    local _tmp_popped_stylevars_trkhdr = false
                                    if not popped_view_stylevars then r.ImGui_PopStyleVar(ctx, 2); _tmp_popped_stylevars_trkhdr = true end
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color)
                                    local _hdr_track_open = r.ImGui_BeginChild(ctx, "TrackHeader" .. track_number, -1, 20)
                                    r.ImGui_PopStyleColor(ctx) -- always pop ChildBg
                                    if _hdr_track_open then
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
                                            for j = 1, r.CountTracks(0) do
                                                collapsed_tracks[j] = all_tracks_collapsed
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
                                    r.ImGui_Dummy(ctx, 0, 0)
                                    if _tmp_popped_stylevars_trkhdr then
                                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), config.show_screenshot_scrollbar and 14 or 1)
                                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 0)
                                    end
                                end
                            end
                            
                            local should_show_fx = true
                            if plugin.is_master then
                                should_show_fx = not master_track_collapsed
                            else
                                should_show_fx = not collapsed_tracks[plugin.track_number]
                            end
                            
                            if should_show_fx then
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
                                        local texture = LoadSearchTexture(screenshot_file, plugin.fx_name)
                                        if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                            local width, height = r.ImGui_Image_GetSize(texture)
                                            if width and height then
                                                local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                                                                        
                                            local unique_id = "project_fx_" .. i .. "_" .. (plugin.track_number or 0) .. "_" .. (plugin.fx_index or 0)

                                            local clicked = r.ImGui_ImageButton(ctx, unique_id, texture, display_width, display_height)
                                            if clicked or (config.add_fx_with_double_click and r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0)) then
                                                if plugin.is_master then
                                                    local master_track = r.GetMasterTrack(0)
                                                    if plugin.fx_index ~= nil then
                                                        local is_open = r.TrackFX_GetFloatingWindow(master_track, plugin.fx_index)
                                                        r.TrackFX_Show(master_track, plugin.fx_index, is_open and 2 or 3)
                                                    end
                                                else
                                                    local track = r.GetTrack(0, plugin.track_number - 1)
                                                    if track and r.ValidatePtr(track, "MediaTrack*") and plugin.fx_index ~= nil then
                                                        local is_open = r.TrackFX_GetFloatingWindow(track, plugin.fx_index)
                                                        r.TrackFX_Show(track, plugin.fx_index, is_open and 2 or 3)
                                                    end
                                                end
                                            end

                                                ShowFXContextMenu({
                                                    fx_name = plugin.fx_name,
                                                    track_number = plugin.track_number,
                                                    fx_index = plugin.fx_index,
                                                    is_master = plugin.is_master
                                                }, "current_project_fx_" .. i)         
                                                if config.show_name_in_screenshot_window and not config.hidden_names[plugin.fx_name] then
                                                    local display_name = GetDisplayPluginName(plugin.fx_name)
                                                    r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                                    r.ImGui_Text(ctx, display_name)
                                                    r.ImGui_PopTextWrapPos(ctx)
                                                    r.ImGui_Text(ctx, GetStarsString(plugin.fx_name))
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
                    else
                        r.ImGui_Text(ctx, "No Plugins in Selected Folder.")
                    end

                elseif selected_folder == "Current Track FX" then
                    filtered_plugins = GetCurrentTrackFX()
                    local display_plugins = {}
                    for _, fx in ipairs(filtered_plugins) do
                        if fx.fx_name:lower():find(browser_search_term:lower(), 1, true) then
                            table.insert(display_plugins, fx)
                        end
                    end
                    filtered_plugins = display_plugins

                    if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") then
                        local track_color_u32, text_color_u32 = GetTrackColorAndTextColor(TRACK)
                        local track_number = r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER") or 0
                        local _, track_name = r.GetTrackName(TRACK, "")
                        r.ImGui_Separator(ctx)
                        -- Ensure no outstanding style vars are active while this child is open
                        local _tmp_popped_stylevars_curhdr = false
                        if not popped_view_stylevars then r.ImGui_PopStyleVar(ctx, 2); _tmp_popped_stylevars_curhdr = true end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color_u32)
                        local cur_header_open = r.ImGui_BeginChild(ctx, "CurrentTrackHeader", -1, 22)
                        r.ImGui_PopStyleColor(ctx) -- always pop ChildBg
                        if cur_header_open then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color_u32)
                            current_track_fx_collapsed = current_track_fx_collapsed or false
                            if r.ImGui_Button(ctx, (current_track_fx_collapsed and "+" or "-") .. "##CollapseCurrentTrack", 20, 20) then
                                current_track_fx_collapsed = not current_track_fx_collapsed
                                ClearScreenshotCache()
                            end
                            r.ImGui_SameLine(ctx)
                            if r.ImGui_Button(ctx, string.format("Track %d: %s", track_number, track_name ~= '' and track_name or 'Unnamed'), -1, 20) then
                                r.SetOnlyTrackSelected(TRACK)
                            end
                            r.ImGui_PopStyleColor(ctx, 4)
                            r.ImGui_EndChild(ctx)
                        end
                        if _tmp_popped_stylevars_curhdr then
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), config.show_screenshot_scrollbar and 14 or 1)
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 0)
                        end
                        if current_track_fx_collapsed then
                            goto skip_current_track_fx_render
                        end
                    end


                    -- NORMALE LAYOUT VOOR CURRENT TRACK FX (MASONRY UITGEZET)
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
                                    
                                    local button_id = "track_fx_" .. i .. "_" .. fx.fx_index
                                    local clicked = r.ImGui_ImageButton(ctx, button_id, texture, display_width, display_height)

                                    if clicked then
                                        if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                            local fx_index = fx.fx_index
                                            if fx_index and fx_index >= 0 then
                                                local is_open = r.TrackFX_GetFloatingWindow(TRACK, fx_index)
                                                r.TrackFX_Show(TRACK, fx_index, is_open and 2 or 3)
                                            end
                                        end
                                    end

                                    if r.ImGui_IsItemClicked(ctx, 1) then
                                        r.ImGui_OpenPopup(ctx, "CurrentTrackFXMenu_" .. i)
                                    end

                                    ShowFXContextMenu({
                                        fx_name = fx.fx_name,
                                        track_number = r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER")
                                    }, "current_track_" .. i)

                                    if config.show_name_in_screenshot_window and not config.hidden_names[fx.fx_name] then
                                        local display_name = GetDisplayPluginName(fx.fx_name)
                                        r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                        r.ImGui_Text(ctx, display_name)
                                        r.ImGui_PopTextWrapPos(ctx)
                                        r.ImGui_Text(ctx, GetStarsString(fx.fx_name))
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

                    ::skip_current_track_fx_render::

                else
                    -- NORMALE FOLDERS WEERGAVE
                    for i = 1, #CAT_TEST do
                        if CAT_TEST[i].name == "FOLDERS" then
                            for j = 1, #CAT_TEST[i].list do
                                if CAT_TEST[i].list[j].name == selected_folder then
                                    filtered_plugins = CAT_TEST[i].list[j].fx
                                    local display_plugins = {}
                                    
                                    if config.show_favorites_on_top then
                                        local pinned = {}
                                        local favorites = {}
                                        local regular = {}
                                        local term_l = GetLowerName(browser_search_term)
                                        for _, plugin in ipairs(filtered_plugins) do
                                            if GetLowerName(plugin):find(term_l, 1, true) then
                                                if pinned_set[plugin] then
                                                    pinned[#pinned+1] = plugin
                                                elseif favorite_set[plugin] then
                                                    favorites[#favorites+1] = plugin
                                                else
                                                    regular[#regular+1] = plugin
                                                end
                                            end
                                        end
                                        SortPlainPluginList(pinned, config.sort_mode)
                                        SortPlainPluginList(favorites, config.sort_mode)
                                        SortPlainPluginList(regular, config.sort_mode)
                                        
                                        -- Add pinned plugins first if show_pinned_on_top is enabled
                                        if config and config.show_pinned_on_top then
                                            for _, plugin in ipairs(pinned) do display_plugins[#display_plugins+1] = plugin end
                                            if #pinned>0 and (#favorites>0 or #regular>0) then display_plugins[#display_plugins+1] = "--Pinned End--" end
                                        else
                                            -- Add pinned plugins to regular if show_pinned_on_top is disabled
                                            for _, plugin in ipairs(pinned) do regular[#regular+1] = plugin end
                                            SortPlainPluginList(regular, config.sort_mode)
                                        end
                                        
                                        for _, plugin in ipairs(favorites) do display_plugins[#display_plugins+1] = plugin end
                                        if #favorites>0 and #regular>0 then display_plugins[#display_plugins+1] = "--Favorites End--" end
                                        for _, plugin in ipairs(regular) do display_plugins[#display_plugins+1] = plugin end
                                    else
                                        -- show_favorites_on_top is false: still check pinned-on-top setting
                                        local term_l = GetLowerName(browser_search_term)
                                        local pinned, others = {}, {}
                                        for _, plugin in ipairs(filtered_plugins) do
                                            if GetLowerName(plugin):find(term_l, 1, true) then
                                                if pinned_set[plugin] then pinned[#pinned+1] = plugin else others[#others+1] = plugin end
                                            end
                                        end
                                        if config.apply_type_priority then
                                            pinned = DedupeByTypePriority(pinned)
                                            others = DedupeByTypePriority(others)
                                        end
                                        SortPlainPluginList(pinned, config.sort_mode)
                                        SortPlainPluginList(others, config.sort_mode)
                                        
                                        -- Add pinned plugins first if show_pinned_on_top is enabled
                                        if config and config.show_pinned_on_top then
                                            for _, p in ipairs(pinned) do display_plugins[#display_plugins+1] = p end
                                            if #pinned>0 and #others>0 then display_plugins[#display_plugins+1] = "--Pinned End--" end
                                        else
                                            -- Add pinned plugins to others if show_pinned_on_top is disabled
                                            for _, p in ipairs(pinned) do others[#others+1] = p end
                                            SortPlainPluginList(others, config.sort_mode)
                                        end
                                        
                                        for _, p in ipairs(others) do display_plugins[#display_plugins+1] = p end
                                    end
                                    
                                    if config.apply_type_priority then
                                        display_plugins = DedupeByTypePriority(display_plugins)
                                    end
                                    filtered_plugins = display_plugins
                                    -- Keep the global visible list in sync so texture queue pruning includes folder items
                                    current_filtered_fx = {}
                                    for _, name in ipairs(display_plugins) do
                                        if type(name) == 'string' and name ~= "--Favorites End--" and name ~= "--Pinned End--" then
                                            current_filtered_fx[#current_filtered_fx+1] = name
                                        end
                                    end
                                    break
                                end
                            end
                            break
                        end
                    end
                    
                    if selected_folder and selected_folder ~= "Current Project FX" and selected_folder ~= "Current Track FX" then
                        if view_mode == "list" then
                            -- LIST MODE VOOR STANDAARD FOLDERS
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 2, 2)
                            for i, plugin_name in ipairs(filtered_plugins) do
                                if plugin_name == "--Favorites End--" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                                    r.ImGui_Text(ctx, "--- Favorites End ---")
                                    r.ImGui_PopStyleColor(ctx)
                                elseif plugin_name == "--Pinned End--" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                                    r.ImGui_Text(ctx, "--- Pinned End ---")
                                    r.ImGui_PopStyleColor(ctx)
                                else
                                    local display_name = GetDisplayPluginName(plugin_name)
                                    local stars = GetStarsString(plugin_name)
                                    local prefix = ""
                                    if config.show_pinned_overlay and IsPluginPinned and IsPluginPinned(plugin_name) then
                                        prefix = prefix .. "📌 "
                                    end
                                    if config.show_favorite_overlay and favorite_set and favorite_set[plugin_name] then
                                        prefix = prefix .. "★ "
                                    end
                                    local activated = r.ImGui_Selectable(ctx, prefix .. display_name .. (stars ~= "" and "  " .. stars or "") .. "##folder_list_" .. i, false)
                                    local do_add = false
                                    if config.add_fx_with_double_click then
                                        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                            do_add = true
                                        end
                                    else
                                        if activated then do_add = true end
                                    end
                                    if do_add then
                                        local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                                        if target_track then
                                            AddFXToTrack(target_track, plugin_name)
                                            LAST_USED_FX = plugin_name
                                            if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                        end
                                    end
                                    ShowPluginContextMenu(plugin_name, "folder_list_ctx_" .. i)
                                end
                            end
                            r.ImGui_PopStyleVar(ctx)
                        else
                            local min_columns = math.floor(available_width / display_size)
                            local actual_display_size = math.min(display_size, available_width / min_columns)
                            local num_columns = math.max(1, min_columns)
                            local column_width = available_width / num_columns

                            if config.use_masonry_layout then
                                if filtered_plugins then
                                    local with_shot, missing = SplitPluginsByScreenshot(filtered_plugins)
                                    local masonry_data = {}
                                    for _, plugin in ipairs(with_shot) do
                                        if plugin == "--Favorites End--" then
                                            masonry_data[#masonry_data+1] = {is_separator = true, label = "--- Favorites End ---"}
                                        elseif plugin == "--Pinned End--" then
                                            masonry_data[#masonry_data+1] = {is_separator = true, label = "--- Pinned End ---"}
                                        else
                                            masonry_data[#masonry_data+1] = {name = plugin}
                                        end
                                    end
                                    DrawMasonryLayout(masonry_data)
                                    RenderMissingList(missing)
                                end
                            else
                                local with_shot, missing = SplitPluginsByScreenshot(filtered_plugins)
                                ApplyTopScreenshotSpacing()
                                for i, plugin_name in ipairs(with_shot) do
                                    if plugin_name == "--Favorites End--" or plugin_name == "--Pinned End--" then
                                        DrawHorizontalSeparatorBar((config.compact_screenshots and 2 or 3), 0x606060FF)
                                        -- Extra breathing room below the divider in grid view for Folders
                                        r.ImGui_Dummy(ctx, 0, (config.compact_screenshots and 6 or 10))
                                    else
                                        local column = (i - 1) % num_columns
                                        if column > 0 then r.ImGui_SameLine(ctx) end
                                        r.ImGui_BeginGroup(ctx)
                                        local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                                        local screenshot_file = screenshot_path .. safe_name .. ".png"
                                        local texture = LoadSearchTexture(screenshot_file, plugin_name)
                                        if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                            local width, height = r.ImGui_Image_GetSize(texture)
                                            if width and height then
                                                local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                                local folder_clicked = r.ImGui_ImageButton(ctx, "folder_plugin_" .. i, texture, display_width, display_height)
                                                if IsPluginPinned and IsPluginPinned(plugin_name) then
                                                    local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                                    local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                                    DrawPinnedOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                                end
                                                if favorite_set and favorite_set[plugin_name] then
                                                    local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                                    local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                                    DrawFavoriteOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                                end
                                                local do_add = false
                                                if config.enable_drag_add_fx then
                                                    -- On initial mouse press over the image, mark as potential drag source
                                                    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx,0) then
                                                        potential_drag_fx_name = plugin_name
                                                        drag_start_x, drag_start_y = r.ImGui_GetMousePos(ctx)
                                                    end
                                                    if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseDown(ctx,0) then
                                                        local mx,my = r.ImGui_GetMousePos(ctx)
                                                        if math.abs(mx - drag_start_x) > 3 or math.abs(my - drag_start_y) > 3 then
                                                            dragging_fx_name = plugin_name
                                                            potential_drag_fx_name = nil
                                                        end
                                                    end
                                                    if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseReleased(ctx,0) then
                                                        potential_drag_fx_name = nil
                                                    end
                                                end
                                                if config.add_fx_with_double_click then
                                                    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx,0) and dragging_fx_name ~= plugin_name then do_add = true end
                                                else
                                                    if folder_clicked and dragging_fx_name ~= plugin_name then do_add = true end
                                                end
                                                if do_add then
                                                    local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                                                    if target_track then
                                                        local fx_index = AddFXToTrack(target_track, plugin_name)
                                                        LAST_USED_FX = plugin_name
                                                        if config.open_floating_after_adding and fx_index >= 0 then
                                                            r.TrackFX_Show(target_track, fx_index, 3)
                                                        end
                                                        if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                                    end
                                                end
                                                ShowPluginContextMenu(plugin_name, "folder_" .. i)
                                                if config.show_name_in_screenshot_window and not config.hidden_names[plugin_name] then
                                                    r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                                    local display_name = GetDisplayPluginName(plugin_name)
                                                    r.ImGui_Text(ctx, display_name)
                                                    r.ImGui_PopTextWrapPos(ctx)
                                                    r.ImGui_Text(ctx, GetStarsString(plugin_name))
                                                end
                                            end
                                        end
                                        r.ImGui_EndGroup(ctx)
                                        if not config.compact_screenshots and column == num_columns - 1 then
                                            r.ImGui_Dummy(ctx, 0, 5)
                                        end
                                    end
                                end
                                RenderMissingList(missing)
                            end
                        end
                    end
                end
    
            elseif screenshot_search_results and #screenshot_search_results > 0 then
                local available_width = r.ImGui_GetContentRegionAvail(ctx)
                if config.use_global_screenshot_size then
                    display_size = config.global_screenshot_size
                elseif config.resize_screenshots_with_window then
                    display_size = available_width - 10
                else
                    display_size = config.folder_specific_sizes["SearchResults"] or config.screenshot_window_size
                end
                if view_mode == "list" then
                    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 2, 2)
                    for i, fx in ipairs(screenshot_search_results) do
                        if fx.is_message then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFF00FF)
                            local msg_name = GetDisplayPluginName(fx.name)
                            r.ImGui_TextWrapped(ctx, msg_name)
                            r.ImGui_PopStyleColor(ctx)
                        elseif fx.is_separator then
                            local label = (fx.kind == 'pinned_end') and "--- Pinned End ---" or "--- Favorites End ---"
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
                            r.ImGui_Text(ctx, label)
                            r.ImGui_PopStyleColor(ctx)
                        else
                            local display_name = GetDisplayPluginName(fx.name)
                            local stars = GetStarsString(fx.name)
                            local prefix = ""
                            if config.show_pinned_overlay and IsPluginPinned and IsPluginPinned(fx.name) then
                                prefix = prefix .. "📌 "
                            end
                            if config.show_favorite_overlay and favorite_set and favorite_set[fx.name] then
                                prefix = prefix .. "★ "
                            end
                            local activated = r.ImGui_Selectable(ctx, prefix .. display_name .. (stars ~= "" and "  " .. stars or "") .. "##list_" .. i, false)
                            local do_add = false
                            if config.add_fx_with_double_click then
                                if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                                    do_add = true
                                end
                            else
                                if activated then do_add = true end
                            end
                            if do_add then
                                local plugin_name = fx.name
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    AddFXToTrack(TRACK, plugin_name)
                                    LAST_USED_FX = plugin_name
                                    if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                end
                            end
                            ShowPluginContextMenu(fx.name, "list_ctx_" .. i)
                        end
                    end
                    r.ImGui_PopStyleVar(ctx)
                else
                    if config.use_masonry_layout then
                        -- Build a list of names while preserving special separators for subgroup dividers
                        local plain_names = {}
                        local messages = {}
                        for _, fx in ipairs(screenshot_search_results) do
                            if fx.is_message then
                                messages[#messages+1] = fx -- behoud originele tabel (heeft is_message + name)
                            elseif fx.is_separator then
                                -- Convert structured separator to the string marker expected downstream
                                if fx.kind == 'pinned_end' then
                                    plain_names[#plain_names+1] = "--Pinned End--"
                                else
                                    plain_names[#plain_names+1] = "--Favorites End--"
                                end
                            else
                                plain_names[#plain_names+1] = fx.name
                            end
                        end
                        local with_shot, missing = SplitPluginsByScreenshot(plain_names)
                        local masonry_data = {}
                        for _, msg in ipairs(messages) do masonry_data[#masonry_data+1] = msg end
                        for _, plugin_name in ipairs(with_shot) do
                            if plugin_name == "--Favorites End--" then
                                masonry_data[#masonry_data+1] = {is_separator = true, kind = "favorites_end"}
                            elseif plugin_name == "--Pinned End--" then
                                masonry_data[#masonry_data+1] = {is_separator = true, kind = "pinned_end"}
                            else
                                masonry_data[#masonry_data+1] = {name = plugin_name}
                            end
                        end
                        DrawMasonryLayout(masonry_data)
                        RenderMissingList(missing)
                    else
                        local num_columns = math.max(1, math.floor(available_width / display_size))
                        -- Build a list of names while preserving special separators for subgroup dividers
                        local plain_names = {}
                        local messages = {}
                        for _, fx in ipairs(screenshot_search_results) do
                            if fx.is_message then
                                messages[#messages+1] = fx
                            elseif fx.is_separator then
                                if fx.kind == 'pinned_end' then
                                    plain_names[#plain_names+1] = "--Pinned End--"
                                else
                                    plain_names[#plain_names+1] = "--Favorites End--"
                                end
                            else
                                plain_names[#plain_names+1] = fx.name
                            end
                        end
                        local with_shot, missing = SplitPluginsByScreenshot(plain_names)
                        for _, msg in ipairs(messages) do
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFF00FF)
                            local display_name = GetDisplayPluginName(msg.name)
                            r.ImGui_TextWrapped(ctx, display_name)
                            r.ImGui_PopStyleColor(ctx)
                        end
                        if #with_shot > 0 then ApplyTopScreenshotSpacing() end
                        for i, plugin_name in ipairs(with_shot) do
                            if plugin_name == "--Favorites End--" or plugin_name == "--Pinned End--" then
                                -- Draw the divider line and add breathing room below it
                                DrawHorizontalSeparatorBar((config.compact_screenshots and 2 or 3), 0x606060FF)
                                r.ImGui_Dummy(ctx, 0, (config.compact_screenshots and 6 or 10))
                            else
                            local column = (i - 1) % num_columns
                            if column > 0 then r.ImGui_SameLine(ctx) end
                            r.ImGui_BeginGroup(ctx)
                            local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                            local screenshot_file = screenshot_path .. safe_name .. ".png"
                            if r.file_exists(screenshot_file) then
                                local texture = LoadSearchTexture(screenshot_file, plugin_name)
                                if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                    local width, height = r.ImGui_Image_GetSize(texture)
                                    if width and height then
                                        local display_width, display_height = ScaleScreenshotSize(width, height, display_size)
                                        local clicked = r.ImGui_ImageButton(ctx, "search_result_" .. i, texture, display_width, display_height)
                                        if pinned_set and pinned_set[plugin_name] then
                                            local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                            local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                            DrawPinnedOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                        end
                                        if favorite_set and favorite_set[plugin_name] then
                                            local tlx, tly = r.ImGui_GetItemRectMin(ctx)
                                            local brx, bry = r.ImGui_GetItemRectMax(ctx)
                                            DrawFavoriteOverlayAt(tlx, tly, brx - tlx, bry - tly)
                                        end
                                        if config.enable_drag_add_fx then
                                            if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx,0) then
                                                potential_drag_fx_name = plugin_name
                                                drag_start_x, drag_start_y = r.ImGui_GetMousePos(ctx)
                                            end
                                            if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseDown(ctx,0) then
                                                local mx,my = r.ImGui_GetMousePos(ctx)
                                                if math.abs(mx-drag_start_x) > 3 or math.abs(my-drag_start_y) > 3 then
                                                    dragging_fx_name = plugin_name
                                                    potential_drag_fx_name = nil
                                                end
                                            end
                                            if potential_drag_fx_name == plugin_name and r.ImGui_IsMouseReleased(ctx,0) then
                                                potential_drag_fx_name = nil
                                            end
                                        end
                                        local do_add = false
                                        if config.add_fx_with_double_click then
                                            if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx,0) and dragging_fx_name ~= plugin_name then do_add = true end
                                        else
                                            if clicked and dragging_fx_name ~= plugin_name then do_add = true end
                                        end
                                        if do_add then
                                            local target_track = r.GetSelectedTrack(0, 0) or r.GetTrack(0, 0) or r.GetMasterTrack(0)
                                            if target_track then
                                                local fx_index = AddFXToTrack(target_track, plugin_name)
                                                LAST_USED_FX = plugin_name
                                                if config.open_floating_after_adding and fx_index and fx_index >= 0 then
                                                    r.TrackFX_Show(target_track, fx_index, 3)
                                                end
                                                if config.close_after_adding_fx then SHOULD_CLOSE_SCRIPT = true end
                                            end
                                        end
                                        ShowPluginContextMenu(plugin_name, "search_" .. i)
                                        if config.show_name_in_screenshot_window and not config.hidden_names[plugin_name] then
                                            r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                            local display_name = GetDisplayPluginName(plugin_name)
                                            r.ImGui_Text(ctx, display_name)
                                            r.ImGui_PopTextWrapPos(ctx)
                                            r.ImGui_Text(ctx, GetStarsString(plugin_name))
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
                        RenderMissingList(missing)
                    end
                end
            else
                r.ImGui_Text(ctx, "Select a folder or enter a search term.")
            end
            r.ImGui_Dummy(ctx, 0, 0)
            if is_screenshot_branch then
                r.ImGui_EndChild(ctx) -- end ScreenshotList
            end
            -- Close the main section selector (scripts/media/sends/actions/screenshots)
            end
        if not popped_view_stylevars then r.ImGui_PopStyleVar(ctx, 2) end
        r.ImGui_EndChild(ctx) -- end ScreenshotSection
        config.screenshot_window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_End(ctx)
        return visible
    else
        r.ImGui_End(ctx)
        return visible
    end
end

function FilterTracksByTag(tag)
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

function Filter_actions(filter_text)
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

function FilterBox()
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local track_info_width = math.max(window_width - 10, 125)
    local x_button_width = 20
    local margin = 3
    local search_width = track_info_width - (x_button_width * 3) - (margin * 2)
   
    local sort_mode = config.sort_mode or "score" -- "score", "alphabet", "rating"

    local top_buttons_height = config.hideTopButtons and 5 or 30
    local tags_height = config.show_tags and current_tag_window_height or 0
    local meter_height = config.hideMeter and 0 or 90
    local meter_spacing = 5
    local bottom_buttons_height = config.hideBottomButtons and 0 or 70
    local volume_slider_height = config.hideVolumeSlider and 0 or 40
    
    local total_ui_elements = top_buttons_height + tags_height + meter_height + meter_spacing + bottom_buttons_height + volume_slider_height
    local search_results_max_height = window_height - total_ui_elements - 100
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
                r.ImGui_SetScrollY(ctx, 0)
                show_screenshot_window = true
                screenshot_window_interactive = true
                screenshot_search_results = {}
                ClearScreenshotCache()
                if IsNonFoldersSubgroup(last_viewed_folder) then
                    browser_panel_selected = last_viewed_folder
                    selected_folder = nil
                    current_filtered_fx = GetFxListForSubgroup(last_viewed_folder) or {}
                    local cap = loaded_items_count or ITEMS_PER_BATCH or 30
                    for j = 1, math.min(cap, #current_filtered_fx) do
                        table.insert(screenshot_search_results, {name = current_filtered_fx[j]})
                    end
                else
                    SelectFolderExclusive(last_viewed_folder)
                    GetPluginsForFolder(selected_folder)
                end
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
    local sort_label_main = (sort_mode == "alphabet") and "A" or ((sort_mode == "rating") and "R" or "A")
    if r.ImGui_Button(ctx, sort_label_main, x_button_width, button_height) then
        if sort_mode == "alphabet" then
            sort_mode = "rating"
        else
            sort_mode = "alphabet"
        end
        config.sort_mode = sort_mode
        SaveConfig()
    end
    if r.ImGui_IsItemHovered(ctx) then
        if sort_mode == "alphabet" then
            r.ImGui_SetTooltip(ctx, "Alphabetic sorting (click to switch to Rating)")
        elseif sort_mode == "rating" then
            r.ImGui_SetTooltip(ctx, "Rating sorting (click to switch to Alphabetic)")
        end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "X", x_button_width, button_height) then
        FILTER = ""
        screenshot_search_results = nil
        r.ImGui_SetScrollY(ctx, 0)
        show_screenshot_window = true
        show_media_browser = false
        if config.default_folder == LAST_OPENED_SENTINEL and last_viewed_folder then
            if IsNonFoldersSubgroup(last_viewed_folder) then
                browser_panel_selected = last_viewed_folder
                selected_folder = nil
                    current_filtered_fx = GetFxListForSubgroup(last_viewed_folder) or {}
                    if config.apply_type_priority then
                        current_filtered_fx = DedupeByTypePriority(current_filtered_fx)
                    end
                screenshot_search_results = {}
                local cap = loaded_items_count or ITEMS_PER_BATCH or 30
                for j = 1, math.min(cap, #current_filtered_fx) do
                    table.insert(screenshot_search_results, {name = current_filtered_fx[j]})
                end
            else
                browser_panel_selected = nil
                selected_folder = last_viewed_folder
            end
        else
            browser_panel_selected = nil
            selected_folder = config.default_folder
        end

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
            loaded_items_count = ITEMS_PER_BATCH or loaded_items_count or 30
            screenshot_search_results = {}
            for i = 1, math.min(loaded_items_count, #filtered_plugins) do
                local plugin_name = filtered_plugins[i]
                table.insert(screenshot_search_results, { name = plugin_name })
            end
            -- Prefetch only the first visible batch to avoid massive queue spikes in very large folders
            local prefetch_cap = math.min(#filtered_plugins, loaded_items_count or ITEMS_PER_BATCH or 30)
            for i = 1, prefetch_cap do
                local plugin_name = filtered_plugins[i]
                local safe_name = plugin_name:gsub("[^%w%s-]", "_")
                local screenshot_file = screenshot_path .. safe_name .. ".png"
                if r.file_exists(screenshot_file) then
                    local relative_path = screenshot_file:gsub(screenshot_path, "")
                    local unique_key = relative_path .. "_" .. (plugin_name or "unknown")
                    if not texture_load_queue[unique_key] and not search_texture_cache[unique_key] then
                        texture_load_queue[unique_key] = { file = screenshot_file, queued_at = r.time_precise(), plugin = plugin_name }
                    end
                end
            end
        end
    end
end
    local filtered_fx = Filter_actions(FILTER)
    if sort_mode == "alphabet" then
        table.sort(filtered_fx, function(a, b) 
            return a.name:lower() < b.name:lower() 
        end)
    elseif sort_mode == "rating" then
        table.sort(filtered_fx, function(a, b)
            local ra = plugin_ratings[a.name] or 0
            local rb = plugin_ratings[b.name] or 0
            if ra == rb then
                return a.name:lower() < b.name:lower()
            else
                return ra > rb
            end
        end)
    else -- default: score
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
    local popupp_open = r.ImGui_BeginChild(ctx, "##popupp", -1, search_results_max_height)
    if popupp_open then
            if config.show_type_dividers then
                
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
                        if sort_mode == "alphabet" then
                            table.sort(plugins, function(a, b) 
                                return a.name:lower() < b.name:lower() 
                            end)
                        elseif sort_mode == "rating" then
                            table.sort(plugins, function(a, b)
                                local ra = plugin_ratings[a.name] or 0
                                local rb = plugin_ratings[b.name] or 0
                                if ra == rb then
                                    return a.name:lower() < b.name:lower()
                                else
                                    return ra > rb
                                end
                            end)
                        else -- default: score
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
                            local display_name = GetDisplayPluginName(plugin.name)
                            if r.ImGui_Selectable(ctx, display_name .. "  " .. GetStarsString(plugin.name) .. "##search_" .. global_idx, global_idx == ADDFX_Sel_Entry) then
                                local fx_index = AddFXToTrack(TRACK, plugin.name)
                                r.ImGui_CloseCurrentPopup(ctx)
                                LAST_USED_FX = plugin.name
                                
                                -- OPEN FLOATING ALS OPTIE ENABLED IS
                                if config.open_floating_after_adding and fx_index >= 0 then
                                    r.TrackFX_Show(TRACK, fx_index, 3) -- 3 = open floating
                                end
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
                                    local disp = GetDisplayPluginName(plugin.name)
                                    r.ImGui_Text(ctx, disp)
                                    r.ImGui_EndTooltip(ctx)
                                end
                            end
    
                            if r.ImGui_IsItemClicked(ctx, 1) then
                                r.ImGui_OpenPopup(ctx, "DrawItemsPluginMenu_" .. global_idx)
                            end
    
                            ShowPluginContextMenu(plugin.name, "search_" .. global_idx)
                            global_idx = global_idx + 1
                        end
                    end
                end
            else
                -- Original view
                for i = 1, #filtered_fx do
                    local search_display = GetDisplayPluginName(filtered_fx[i].name)
                    if r.ImGui_Selectable(ctx, search_display .. "  " .. GetStarsString(filtered_fx[i].name) .. "##search_" .. i, i == ADDFX_Sel_Entry) then
                    local fx_index = AddFXToTrack(TRACK, filtered_fx[i].name)
                    r.ImGui_CloseCurrentPopup(ctx)
                    LAST_USED_FX = filtered_fx[i].name
                    
                        -- OPEN FLOATING ALS OPTIE ENABLED IS
                        if config.open_floating_after_adding and fx_index >= 0 then
                            r.TrackFX_Show(TRACK, fx_index, 3) -- 3 = open floating
                        end
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
    
                    ShowPluginContextMenu(filtered_fx[i].name, "search_" .. i)
                end
            end
    
            if not r.ImGui_IsWindowHovered(ctx) then
                is_screenshot_visible = false
                current_hovered_plugin = nil
            end
        end
        r.ImGui_EndChild(ctx)
    
    
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
            if ADDFX_Sel_Entry and ADDFX_Sel_Entry > 0 and ADDFX_Sel_Entry <= #filtered_fx then
                local fx_index = AddFXToTrack(TRACK, filtered_fx[ADDFX_Sel_Entry].name)
                LAST_USED_FX = filtered_fx[ADDFX_Sel_Entry].name
                
                -- OPEN FLOATING ALS OPTIE ENABLED IS
                if config.open_floating_after_adding and fx_index >= 0 then
                    r.TrackFX_Show(TRACK, fx_index, 3) -- 3 = open floating
                end
                
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

function DrawItems(tbl, main_cat_name)
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
                local pinned = {}
                local favorites = {}
                local regular = {}
                local all_unpinned = {}
           
                for j = 1, #tbl[i].fx do
                    local name = tbl[i].fx[j]
                    if pinned_set[name] then
                        table.insert(pinned, {index = j, name = name})
                    elseif favorite_set[name] then
                        table.insert(favorites, {index = j, name = name})
                        table.insert(all_unpinned, {index = j, name = name})
                    else
                        table.insert(regular, {index = j, name = name})
                        table.insert(all_unpinned, {index = j, name = name})
                    end
                end
           
                -- Sorteer helpers voor popuplijsten
                local function sort_group(group)
                    table.sort(group, function(a, b)
                        if config.sort_mode == "rating" then
                            local ra = plugin_ratings[a.name] or 0
                            local rb = plugin_ratings[b.name] or 0
                            if ra == rb then
                                return a.name:lower() < b.name:lower()
                            else
                                return ra > rb
                            end
                        else
                            return a.name:lower() < b.name:lower()
                        end
                    end)
                end

                sort_group(pinned)
                if config.show_favorites_on_top then
                    sort_group(favorites)
                    sort_group(regular)
                else
                    sort_group(all_unpinned)
                end

                local plugins_to_show
                if config.show_favorites_on_top then
                    plugins_to_show = {
                        {key = "pinned", list = pinned},
                        {key = "favorites", list = favorites},
                        {key = "regular", list = regular},
                    }
                else
                    plugins_to_show = {
                        {key = "pinned", list = pinned},
                        {key = "others", list = all_unpinned},
                    }
                end
       
                for group_idx, group in ipairs(plugins_to_show) do
                    local plugin_group = group.list
                    for _, plugin in ipairs(plugin_group) do
                        local list_display = GetDisplayPluginName(plugin.name)
                        if r.ImGui_Selectable(ctx, list_display .. "  " .. GetStarsString(plugin.name) .. "##plugin_list_" .. i .. "_" .. plugin.index) then
                            if ADD_FX_TO_ITEM then
                                AddFXToItem(plugin.name)
                            else
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    local fx_index = AddFXToTrack(TRACK, plugin.name)
                                    
                                    -- OPEN FLOATING ALS OPTIE ENABLED IS
                                    if config.open_floating_after_adding and fx_index >= 0 then
                                        r.TrackFX_Show(TRACK, fx_index, 3) -- 3 = open floating
                                    end
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
                       
                        ShowPluginContextMenu(plugin.name, "folders_" .. i .. "_" .. plugin.index)
                    end
                    -- separators between groups
                    if group.key == "pinned" and #plugin_group > 0 then
                        -- show pinned end if any following group has items
                        local has_following = false
                        for k = group_idx + 1, #plugins_to_show do
                            if #plugins_to_show[k].list > 0 then has_following = true break end
                        end
                        if has_following then
                            if r.ImGui_Selectable(ctx, "--Pinned End--", false, r.ImGui_SelectableFlags_Disabled()) then end
                        end
                    elseif group.key == "favorites" and #favorites > 0 and #regular > 0 then
                        if r.ImGui_Selectable(ctx, "--Favorites End--", false, r.ImGui_SelectableFlags_Disabled()) then end
                    end
                end
            else
                if tbl[i] and tbl[i].fx then
                    -- Bouw entries met display- en originele naam, met pinned eerst
                    local pinned_entries = {}
                    local other_entries = {}
                    for j = 1, #tbl[i].fx do
                        local original = tbl[i].fx[j]
                        if original then
                            local name_for_display = original
                            if main_cat_name == "ALL PLUGINS" and tbl[i].name ~= "INSTRUMENTS" then
                                name_for_display = name_for_display:gsub("^(%S+:)", "")
                            elseif main_cat_name == "DEVELOPER" then
                                name_for_display = name_for_display:gsub(' %(' .. Literalize(tbl[i].name) .. '%)', "")
                            end
                            local cat_display = GetDisplayPluginName(name_for_display)
                            local entry = { display = cat_display, original = original, index = j }
                            if pinned_set[original] then table.insert(pinned_entries, entry) else table.insert(other_entries, entry) end
                        end
                    end

                    local function sort_entries(entries)
                        table.sort(entries, function(a, b)
                        if config.sort_mode == "rating" then
                            local ra = plugin_ratings[a.original] or 0
                            local rb = plugin_ratings[b.original] or 0
                            if ra == rb then
                                return a.display:lower() < b.display:lower()
                            else
                                return ra > rb
                            end
                        else
                            return a.display:lower() < b.display:lower()
                        end
                    end)
                    end
                    sort_entries(pinned_entries)
                    sort_entries(other_entries)

                    for _, e in ipairs(pinned_entries) do
                        if r.ImGui_Selectable(ctx, e.display .. "  " .. GetStarsString(e.original) .. "##plugin_list_" .. i .. "_" .. e.index) then
                            if ADD_FX_TO_ITEM then
                                AddFXToItem(e.original)
                            else
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    local fx_index = AddFXToTrack(TRACK, e.original)
                                    if config.open_floating_after_adding and fx_index >= 0 then
                                        r.TrackFX_Show(TRACK, fx_index, 3)
                                    end
                                end
                            end
                            LAST_USED_FX = e.original
                            if config.close_after_adding_fx and not IS_COPYING_TO_ALL_TRACKS then
                                SHOULD_CLOSE_SCRIPT = true
                            end
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            if e.original ~= current_hovered_plugin then
                                current_hovered_plugin = e.original
                                LoadPluginScreenshot(current_hovered_plugin)
                            end
                            is_screenshot_visible = true
                        end
                        ShowPluginContextMenu(e.original, "category_" .. i .. "_" .. e.index)
                    end
                    -- Separator if we also have others
                    if #pinned_entries > 0 and #other_entries > 0 then
                        if r.ImGui_Selectable(ctx, "--Pinned End--", false, r.ImGui_SelectableFlags_Disabled()) then end
                    end
                    for _, e in ipairs(other_entries) do
                        if r.ImGui_Selectable(ctx, e.display .. "  " .. GetStarsString(e.original) .. "##plugin_list_" .. i .. "_" .. e.index) then
                            if ADD_FX_TO_ITEM then
                                AddFXToItem(e.original)
                            else
                                if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                    local fx_index = AddFXToTrack(TRACK, e.original)
                                    if config.open_floating_after_adding and fx_index >= 0 then
                                        r.TrackFX_Show(TRACK, fx_index, 3)
                                    end
                                end
                            end
                            LAST_USED_FX = e.original
                            if config.close_after_adding_fx and not IS_COPYING_TO_ALL_TRACKS then
                                SHOULD_CLOSE_SCRIPT = true
                            end
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            if e.original ~= current_hovered_plugin then
                                current_hovered_plugin = e.original
                                LoadPluginScreenshot(current_hovered_plugin)
                            end
                            is_screenshot_visible = true
                        end
                        ShowPluginContextMenu(e.original, "category_" .. i .. "_" .. e.index)
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

function DrawFavorites()
    -- Pinned-first ordering inside the favorites menu (if enabled)
    local pinned, others = {}, {}
    for _, fav in ipairs(favorite_plugins) do
        if pinned_set[fav] then pinned[#pinned+1] = fav else others[#others+1] = fav end
    end
    SortPlainPluginList(pinned, config.sort_mode)
    SortPlainPluginList(others, config.sort_mode)
    local merged = {}
    
    -- Add pinned plugins first if show_pinned_on_top is enabled
    if config and config.show_pinned_on_top then
        for _, p in ipairs(pinned) do merged[#merged+1] = p end
        if #pinned>0 and #others>0 then merged[#merged+1] = "--Pinned End--" end
    else
        -- Add pinned plugins to others if show_pinned_on_top is disabled
        for _, p in ipairs(pinned) do others[#others+1] = p end
        SortPlainPluginList(others, config.sort_mode)
    end
    
    for _, p in ipairs(others) do merged[#merged+1] = p end

    for i, fav in ipairs(merged) do
        if fav == "--Pinned End--" then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x808080FF)
            r.ImGui_Text(ctx, "--- Pinned End ---")
            r.ImGui_PopStyleColor(ctx)
        else
            local fav_display_global = GetDisplayPluginName(fav)
            if r.ImGui_Selectable(ctx, fav_display_global .. "  " .. GetStarsString(fav) .. "##favorites_" .. i) then
            if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                local fx_index = AddFXToTrack(TRACK, fav)
                
                -- OPEN FLOATING ALS OPTIE ENABLED IS
                if config.open_floating_after_adding and fx_index >= 0 then
                    r.TrackFX_Show(TRACK, fx_index, 3) -- 3 = open floating
                end
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
            ShowPluginContextMenu(fav, "favorites_" .. i)
        end
    end
    if not r.ImGui_IsWindowHovered(ctx) then
        is_screenshot_visible = false
        current_hovered_plugin = nil
        
    end
end

function CalculateButtonWidths(total_width, num_buttons, spacing)
    local available_width = total_width - (spacing * (num_buttons - 1))
    return available_width / num_buttons
end

function DrawBottomButtons()
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
        local half_width = (track_info_width - button_spacing) / 2
      
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
            r.ImGui_PopItemWidth(ctx)
        end
    end
    r.ImGui_PushFont(ctx, NormalFont, 10)
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
    if r.ImGui_Button(ctx, "PASTE", button_width_row1) then
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
    if r.ImGui_Button(ctx, "BYPASS", button_width_row2) then
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
            ClearScreenshotCache()
            BuildScreenshotIndex(true)
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
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleColor(ctx)
    if config.show_tooltips and r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Arm selected Track")
    end
    
    end
end

function ShowTrackFX()
    if not TRACK or not reaper.ValidatePtr(TRACK, "MediaTrack*") then
        r.ImGui_Text(ctx, "No track selected")
        return
    end
    local fx_list_height = (config.fx_track_list_height and config.fx_track_list_height > 40) and config.fx_track_list_height or 260
    local track_fxlist_open = r.ImGui_BeginChild(ctx, "TrackFXList", -1, fx_list_height)
    if track_fxlist_open then
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
                            AddFXToTrack(TRACK, orig_name)
                        end
                    end                   
                    if r.ImGui_MenuItem(ctx, is_enabled and "Bypass plugin" or "Unbypass plugin") then
                        r.TrackFX_SetEnabled(TRACK, i, not is_enabled)
                    end
                    if favorite_set[fx_name] then
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
    end
    r.ImGui_EndChild(ctx)
end

function ShowItemFX()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then return end
    local take = r.GetActiveTake(item)
    if not take then return end

    local min_height = r.ImGui_GetCursorPosY(ctx)
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local available_height = window_height - r.ImGui_GetCursorPosY(ctx)
    local fx_list_height = available_height - 25

    local item_fxlist_open = r.ImGui_BeginChild(ctx, "ItemFXList", -1, fx_list_height)
    if item_fxlist_open then
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
    end
    r.ImGui_EndChild(ctx)
end


function GetTrackType(track)
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
function CalculateTopHeight(config)
    local height = 0
    if not config.hideTopButtons then height = height + 30 end
    height = height + 50  -- track info header
    if config.show_tags then height = height + 65 end
    return height
end

function CalculateMenuHeight(config)
    local height = 18
    if config.show_favorites then height = height + 18 end
    if config.show_all_plugins then height = height + 18 end
    if config.show_developer then height = height + 18 end
    if config.show_folders then height = height + 18 end
    if config.show_fx_chains then height = height + 18 end
    if config.show_track_templates then height = height + 18 end
    if config.show_category then height = height + 18 end
    if config.show_container then height = height + 18 end
    if config.show_video_processor then height = height + 18 end
    if config.show_projects then height = height + 18 end
    if config.show_sends then height = height + 18 end
    if config.show_actions then height = height + 18 end
    if config.show_custom_folders and next(config.custom_folders) then height = height + 18 end  -- WIJZIG DEZE REGEL
    if LAST_USED_FX then height = height + 18 end
    return height
end

function CalculateBottomSectionHeight(config)
    local height = 0
    if not config.hideBottomButtons then height = height + 70 end
    if not config.hideVolumeSlider then
        height = height + 40
    end
    if not config.hideMeter then height = height + 90 end
    return height
end

function DrawCustomFoldersMenu(folders, path_prefix)
    path_prefix = path_prefix or ""
    
    -- SORTEER DE FOLDER NAMEN ALFABETISCH
    local sorted_folder_names = {}
    for folder_name, _ in pairs(folders) do
        table.insert(sorted_folder_names, folder_name)
    end
    table.sort(sorted_folder_names, function(a, b) 
        return a:lower() < b:lower() 
    end)
    
    -- GEBRUIK DE GESORTEERDE NAMEN
    for _, folder_name in ipairs(sorted_folder_names) do
        local folder_content = folders[folder_name]
        local full_path = path_prefix == "" and folder_name or (path_prefix .. "/" .. folder_name)
        
        if IsPluginArray(folder_content) then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 5)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
            
            if r.ImGui_BeginMenu(ctx, folder_name .. " (" .. #folder_content .. ")") then
                -- NIEUWE CONTEXT MENU VOOR FOLDERS
                if r.ImGui_IsItemClicked(ctx, 1) then
                    r.ImGui_OpenPopup(ctx, "FolderContextMenu_" .. full_path)
                end
                
                if r.ImGui_BeginPopup(ctx, "FolderContextMenu_" .. full_path) then
                    if r.ImGui_MenuItem(ctx, "Create Parent Folder Above") then
                        show_create_parent_folder_popup = true
                        selected_folder_for_parent = full_path
                        selected_folder_name = folder_name
                    end
                    if r.ImGui_MenuItem(ctx, "Capture Folder Screenshots") then
                        StartFolderScreenshots(full_path)
                    end
                    r.ImGui_EndPopup(ctx)
                end
                
                local favorites = {}
                local regular = {}
                
                for _, plugin_name in ipairs(folder_content) do
                    if favorite_set[plugin_name] then
                        table.insert(favorites, plugin_name)
                    else
                        table.insert(regular, plugin_name)
                    end
                end
                
                local plugins_to_show = config.show_favorites_on_top and {favorites, regular} or {folder_content}
                
                for group_idx, plugin_group in ipairs(plugins_to_show) do
                    for plugin_idx, plugin_name in ipairs(plugin_group) do
                        if type(plugin_name) == "string" then
                            local custom_display = GetDisplayPluginName(plugin_name)
                            if r.ImGui_Selectable(ctx, custom_display .. "  " .. GetStarsString(plugin_name) .. "##custom_" .. full_path .. "_" .. plugin_idx) then
                                if ADD_FX_TO_ITEM then
                                    AddFXToItem(plugin_name)
                                else
                                    if TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                                        local fx_index = AddFXToTrack(TRACK, plugin_name)
                                        
                                        if config.open_floating_after_adding and fx_index >= 0 then
                                            r.TrackFX_Show(TRACK, fx_index, 3)
                                        end
                                    end
                                end
                                LAST_USED_FX = plugin_name
                                if config.close_after_adding_fx and not IS_COPYING_TO_ALL_TRACKS then
                                    SHOULD_CLOSE_SCRIPT = true
                                end
                            end
                            
                            if r.ImGui_IsItemHovered(ctx) then
                                if plugin_name ~= current_hovered_plugin then
                                    current_hovered_plugin = plugin_name
                                    LoadPluginScreenshot(current_hovered_plugin)
                                end
                                is_screenshot_visible = true
                            end
                            
                            ShowPluginContextMenu(plugin_name, "custom_main_" .. full_path .. "_" .. plugin_idx)
                        end
                    end
                    
                    if config.show_favorites_on_top and group_idx == 1 and #favorites > 0 and #regular > 0 then
                        if r.ImGui_Selectable(ctx, "--Favorites End--", false, r.ImGui_SelectableFlags_Disabled()) then end
                    end
                end
                
                if not r.ImGui_IsAnyItemHovered(ctx) and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId()) then
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                r.ImGui_EndMenu(ctx)
            end
            
            r.ImGui_PopStyleVar(ctx, 4)
            r.ImGui_PopStyleColor(ctx, 2)
            
        elseif IsSubfolderStructure(folder_content) then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 5)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
            
            if r.ImGui_BeginMenu(ctx, folder_name) then
                DrawCustomFoldersMenu(folder_content, full_path)
                if not r.ImGui_IsAnyItemHovered(ctx) and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId()) then
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                r.ImGui_EndMenu(ctx)
            end
            
            r.ImGui_PopStyleVar(ctx, 4)
            r.ImGui_PopStyleColor(ctx, 2)
        end
    end
end

-----------------------------------------------------------------
function Frame()
    local search = FilterBox()
    if search then return end
    
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local menu_items_height = CalculateMenuHeight(config)
    local bottom_section_height = CalculateBottomSectionHeight(config)
    -- Initial rough estimate (not used directly for final child size; we recompute later to avoid negative heights)
    local initial_available_height = window_height - r.ImGui_GetCursorPosY(ctx) - bottom_section_height - menu_items_height + 10
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
    -- CUSTOM FOLDERS SECTIE
if config.show_custom_folders and next(config.custom_folders) then  -- VOEG show_custom_folders CHECK TOE
    r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
    r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 5, 5)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)

    if r.ImGui_BeginMenu(ctx, "CUSTOM") then
        DrawCustomFoldersMenu(config.custom_folders, "")
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
                        local tree = GetFxChainsTree()
                        DrawFxChains(tree)
                        if not r.ImGui_IsAnyItemHovered(ctx) and not r.ImGui_IsPopupOpen(ctx, "", r.ImGui_PopupFlags_AnyPopupId()) then
                    if has_selected then r.ImGui_SetNextItemOpen(ctx, true) end -- auto-expand FOLDERS header on startup when last opened was inside
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    elseif CAT_TEST[i].name == "TRACK TEMPLATES" then
                        local tree = GetTrackTemplatesTree()
                        DrawTrackTemplates(tree)
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
                AddFXToTrack(TRACK, "Container")
                LAST_USED_FX = "Container"
                if config.close_after_adding_fx then
                    SHOULD_CLOSE_SCRIPT = true
                end
            end
        end
        if config.show_video_processor then
            if r.ImGui_Selectable(ctx, "VIDEO PROCESSOR") then
                AddFXToTrack(TRACK, "Video processor")
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
                    SelectFolderExclusive("Projects")
                    LoadProjects()
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    SelectFolderExclusive(last_viewed_folder)
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
                    SelectFolderExclusive("Sends/Receives")
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    SelectFolderExclusive(last_viewed_folder)
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
                    SelectFolderExclusive("Actions")
                else
                    show_action_browser = false
                    show_media_browser = false
                    show_sends_window = false
                    SelectFolderExclusive(last_viewed_folder)
                    GetPluginsForFolder(last_viewed_folder)
                end
                ClearScreenshotCache()
            end
        end
        if config.show_notes_widget then
            if r.ImGui_Selectable(ctx, "NOTES", false) then
                LaunchTKNotes()
            end
        end

        if LAST_USED_FX and r.ValidatePtr(TRACK, "MediaTrack*") then
            if r.ImGui_Selectable(ctx, "RECENT: " .. LAST_USED_FX) then
                AddFXToTrack(TRACK, LAST_USED_FX)
                   
                if config.close_after_adding_fx then
                    SHOULD_CLOSE_SCRIPT = true
                end
            end
        end
    r.ImGui_Separator(ctx)
    
    -- Recompute available height AFTER drawing dynamic menu sections to avoid negative or tiny values
    local current_y = r.ImGui_GetCursorPosY(ctx)
    local window_h_now = r.ImGui_GetWindowHeight(ctx)
    local available_height = window_h_now - current_y - bottom_section_height - 5
    if available_height < 50 then available_height = 50 end

    if ADD_FX_TO_ITEM then
        local popup2_open = r.ImGui_BeginChild(ctx, "MainItemFXPanel", -1, available_height)
        if popup2_open then
            ShowItemFX()
        end
        r.ImGui_EndChild(ctx)
    else
        local popupp3_open = r.ImGui_BeginChild(ctx, "MainTrackFXPanel", -1, available_height)
        if popupp3_open then
            ShowTrackFX()
        end
        r.ImGui_EndChild(ctx)
    end
        if not r.ImGui_IsAnyItemHovered(ctx) then
            current_hovered_plugin = nil
        end
    end

function get_sws_colors()
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

function getScriptsIniPath()
    return r.GetResourcePath() .. "/Scripts/user_scripts.ini"
end

function createEmptyUserScriptsIni()
    local file = io.open(getScriptsIniPath(), "w")
    if file then
        file:write("# User defined scripts\n")
        file:close()
    end
end

function loadUserScripts()
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

function saveUserScript(name, command_id)
    local file = io.open(getScriptsIniPath(), "a")
    if file then
        file:write(string.format("\n[Script]\nname=%s\ncommand_id=%s\n", name, command_id))
        file:close()
        userScripts = loadUserScripts()  -- Herlaad de scripts
        r.ShowMessageBox("Script added: " .. name, "Script added", 0)
    end
end

show_add_script_popup = false
new_script_name = ""
new_command_id = ""
function showAddScriptPopup()
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
function removeUserScript(index)
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
        
        NormalFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 11)
        TinyFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 9)
        LargeFont = r.ImGui_CreateFont(TKFXfonts[config.selected_font], 15)
        IconFont = r.ImGui_CreateFontFromFile(script_path .. 'Icons-Regular.otf', 0)

        r.ImGui_Attach(ctx, NormalFont)
        r.ImGui_Attach(ctx, TinyFont)
        r.ImGui_Attach(ctx, LargeFont)
        r.ImGui_Attach(ctx, IconFont)
        
    end
end

function EnsureWindowVisible()
    if config.hide_main_window then
        if not was_hidden then
            was_docked_before_hide = (dock and dock ~= 0)
        end
        config.dock_screenshot_window = false
        config.show_screenshot_window = true
        was_hidden = true
    else
        if was_hidden then
            -- Only restore position/size if window was NOT docked before hiding
            if not was_docked_before_hide then
                local viewport = r.ImGui_GetMainViewport(ctx)
                local vp_x, vp_y = r.ImGui_Viewport_GetPos(viewport)
                local vp_w, vp_h = r.ImGui_Viewport_GetWorkSize(viewport)
                
                local window_w = 200
                local window_h = 600
                local center_x = vp_x + (vp_w - window_w) * 0.5
                local center_y = vp_y + (vp_h - window_h) * 0.5
                
                r.ImGui_SetNextWindowPos(ctx, center_x, center_y, r.ImGui_Cond_Always())
                r.ImGui_SetNextWindowSize(ctx, window_w, window_h, r.ImGui_Cond_Always())
            end
            -- If it was docked, let ImGui restore the docking automatically
            
            was_hidden = false
            was_docked_before_hide = false
        end
    end
end

-- Centralized drag & drop handling function
function HandleDragAndDrop()
    if config.enable_drag_add_fx and dragging_fx_name and r.ImGui_IsMouseReleased(ctx,0) then
        local shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
        if shift then
            local item = r.GetSelectedMediaItem(0,0)
            if item then
                local take = r.GetActiveTake(item)
                if take then
                    r.TakeFX_AddByName(take, dragging_fx_name, 1)
                    LAST_USED_FX = dragging_fx_name
                end
            end
        else
            local sx, sy = r.GetMousePosition()
            local track = select(1, r.GetTrackFromPoint(sx, sy))
            if not track then
                local ix, iy = r.ImGui_GetMousePos(ctx)
                track = select(1, r.GetTrackFromPoint(ix, iy))
            end
            if not track then
                track = r.GetSelectedTrack(0,0) or r.GetTrack(0,0) or r.GetMasterTrack(0)
            end
            if track then
                local fx_index = AddFXToTrack(track, dragging_fx_name)
                LAST_USED_FX = dragging_fx_name
                if config.open_floating_after_adding and fx_index and fx_index >= 0 then
                    r.TrackFX_Show(track, fx_index, 3)
                end
            end
        end
        dragging_fx_name = nil
        potential_drag_fx_name = nil
    end
end

-----------------------------------------------------------------------------------------
function Main()
    SetRunningState(true)
    MaybeClearCaches()
    
    if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        InitializeImGuiContext()
        return r.defer(Main)
    end   
        if not TRACK or not r.ValidatePtr(TRACK, "MediaTrack*") then
        local selected_track = r.GetSelectedTrack(0, 0)
        local master_track = r.GetMasterTrack(0)
        if r.IsTrackSelected(master_track) then
            TRACK = master_track
        elseif selected_track then
            TRACK = selected_track
        else
            local first_track = r.GetTrack(0, 0)
            TRACK = first_track or master_track
        end
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
            pushed_main_styles = true
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
            r.ImGui_PushFont(ctx, NormalFont, 11)
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
        else
            pushed_main_styles = false
            InitializeImGuiContext()
        end

local fx_list_height = 0
if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") then
    local fx_count = r.TrackFX_GetCount(TRACK)
    fx_list_height = fx_count * 15
end

local min_window_height = CalculateTopHeight(config) + CalculateMenuHeight(config) + fx_list_height + CalculateBottomSectionHeight(config) + 60

r.ImGui_SetNextWindowSizeConstraints(ctx, 140, min_window_height, 16384, 16384)
----------------------------------------------------------------------------------   
handleDocking()
EnsureWindowVisible()

-- Check visibility states
local general_visibility = CheckVisibilityState()
local should_show_main_window = ShouldShowMainWindow()

-- If whole script is hidden (TOGGLE_VISIBILITY), show hidden window
if not general_visibility then
    -- Window is hidden but script keeps running
    -- Clean up any pushed styles before creating hidden window
    if pushed_main_styles then
        r.ImGui_PopFont(ctx)
        r.ImGui_PopStyleColor(ctx, 13) -- 13 StyleColors
        r.ImGui_PopStyleVar(ctx, 6)    -- 6 StyleVars
    end
    
    -- Create a minimal invisible window to keep the script active
    local invisible_flags = r.ImGui_WindowFlags_NoTitleBar() | 
                           r.ImGui_WindowFlags_NoResize() | 
                           r.ImGui_WindowFlags_NoMove() | 
                           r.ImGui_WindowFlags_NoScrollbar() | 
                           r.ImGui_WindowFlags_NoScrollWithMouse() | 
                           r.ImGui_WindowFlags_NoCollapse() | 
                           r.ImGui_WindowFlags_NoFocusOnAppearing()
    
    r.ImGui_SetNextWindowPos(ctx, -1000, -1000)
    r.ImGui_SetNextWindowSize(ctx, 1, 1)
    local hidden_visible, hidden_open = r.ImGui_Begin(ctx, 'TK FX BROWSER (Hidden)', true, invisible_flags)
    if hidden_visible then
        r.ImGui_Text(ctx, "") -- Empty content
    end
    r.ImGui_End(ctx)
    
    if hidden_open then
        r.defer(Main)
    end
    return
end

if not should_show_main_window then
    config.show_screenshot_window = true
    
    if config.show_screenshot_window then
        ShowScreenshotWindow()
    end
    
    if show_settings then
        show_settings = ShowConfigWindow()
    end
    
    if config.enable_drag_add_fx then
        DrawDragOverlay()
    end
    
    -- Handle drag & drop completion when main window is hidden
    HandleDragAndDrop()
    
    if pushed_main_styles then
        r.ImGui_PopFont(ctx)
        r.ImGui_PopStyleColor(ctx, 13) -- 13 StyleColors
        r.ImGui_PopStyleVar(ctx, 6)    -- 6 StyleVars
    end
    
    r.defer(Main)
    return
end

local visible, open = r.ImGui_Begin(ctx, 'TK FX BROWSER', true, window_flags | r.ImGui_WindowFlags_NoScrollWithMouse() | r.ImGui_WindowFlags_NoScrollbar())
dock = r.ImGui_GetWindowDockID(ctx)

if visible then
    local main_window_pos_x, main_window_pos_y = r.ImGui_GetWindowPos(ctx)
    local main_window_width = r.ImGui_GetWindowWidth(ctx)
    if config.show_screenshot_window then
        ShowScreenshotWindow()
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
            local track_num_val = r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER") or 0
            local track_num = math.floor(track_num_val)
            local header_label = (track_num > 0) and (tostring(track_num) .. ": " .. (track_name or "")) or (track_name or "")
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 4)
            local window_width = r.ImGui_GetWindowWidth(ctx)
            local track_info_width = math.max(window_width - 10, 125)  -- Minimaal 125, of vensterbreedte - 20
            
            local trackinfo_open = r.ImGui_BeginChild(ctx, "TrackInfo", track_info_width, 50)
            if trackinfo_open then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)  -- Transparante knop
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3F3F3F7F)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x7F7F7F7F)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                r.ImGui_SetCursorPos(ctx, 0, 0)
                r.ImGui_PushFont(ctx, IconFont, 12)
                if r.ImGui_Button(ctx, '\u{0050}', 20, 20) then
                    config.show_screenshot_window = not config.show_screenshot_window
                    ClearScreenshotCache()
                    GetPluginsForFolder(selected_folder)
                end             
                local window_width = r.ImGui_GetWindowWidth(ctx)                          
                
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPos(ctx, window_width - 20, 0)
                if r.ImGui_Button(ctx, show_settings and '\u{0047}' or '\u{0047}', 20, 20) then
                    show_settings = not show_settings
                end
                
                if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                    r.ImGui_PopFont(ctx)
                end
                
                r.ImGui_PopStyleColor(ctx, 4)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                r.ImGui_PushFont(ctx, LargeFont, 15)
                local text_width = r.ImGui_CalcTextSize(ctx, header_label)
                local window_width = r.ImGui_GetWindowWidth(ctx)
                local pos_x = (window_width - text_width -7) * 0.5
                local window_height = r.ImGui_GetWindowHeight(ctx)
                local text_height = r.ImGui_GetTextLineHeight(ctx)
                local pos_y = (window_height - text_height) * 0.4
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)  -- Volledig doorzichtige knop
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)  -- Licht grijs bij hover
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)  -- Donkerder grijs bij klik
                r.ImGui_SetCursorPos(ctx, pos_x, pos_y)
                if r.ImGui_Button(ctx, header_label) then
                    show_rename_popup = true
                    new_track_name = track_name
                end
                r.ImGui_PopStyleColor(ctx, 3)
                if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                    r.ImGui_PopFont(ctx)
                end

                r.ImGui_PushFont(ctx, NormalFont, 11)
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
                r.ImGui_PushFont(ctx, NormalFont, 11)
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
                        r.SetOnlyTrackSelected(r.GetMasterTrack(0))
                    elseif r.IsTrackSelected(r.GetMasterTrack(0)) then
                        local last_track = r.GetTrack(0, r.GetNumTracks() - 1)
                        if last_track then r.SetOnlyTrackSelected(last_track) end
                    else
                        local prev_track = r.GetTrack(0, current_track_number - 2)
                        if prev_track then r.SetOnlyTrackSelected(prev_track) end
                    end
                end

                r.ImGui_SetCursorPos(ctx, window_width - 16, window_height - 20)
                if r.ImGui_Button(ctx, ">", 20, 20) then
                    if r.IsTrackSelected(r.GetMasterTrack(0)) then
                        local first_track = r.GetTrack(0, 0)
                        if first_track then r.SetOnlyTrackSelected(first_track) end
                    else
                        local next_track = r.GetTrack(0, r.GetMediaTrackInfo_Value(TRACK, "IP_TRACKNUMBER"))
                        if next_track then 
                            r.SetOnlyTrackSelected(next_track)
                        else
                            r.SetOnlyTrackSelected(r.GetMasterTrack(0))
                        end
                    end
                end
                r.ImGui_PopStyleColor(ctx, 3)
                if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
                    r.ImGui_PopFont(ctx)
                end
                r.ImGui_PopStyleColor(ctx)
            end
            if trackinfo_open then r.ImGui_EndChild(ctx) end
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_PopStyleColor(ctx)
            
            if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") and config.show_tags then
                local tagsection_open = r.ImGui_BeginChild(ctx, "TagSection", track_info_width, 45)
                if tagsection_open then
                    current_tag_window_height = r.ImGui_GetWindowHeight(ctx) + 20

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
                            if button_pressed then

                                local tagged_tracks = FilterTracksByTag(tag)
                                
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
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                                    end
                                elseif hide_mode == 1 then
                                    for _, track in ipairs(tagged_tracks) do
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
                                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
                                    end
                                elseif hide_mode == 3 then
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
                                if r.ImGui_MenuItem(ctx, "Add this tag to all selected tracks") then
                                    local track_count = r.CountSelectedTracks(0)
                                    for j = 0, track_count - 1 do
                                        local track = r.GetSelectedTrack(0, j)
                                        local guid = r.GetTrackGUID(track)
                                        track_tags[guid] = track_tags[guid] or {}
                                        local already = false
                                        for _, t in ipairs(track_tags[guid]) do
                                            if t == tag then already = true break end
                                        end
                                        if not already then
                                            table.insert(track_tags[guid], tag)
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
                                    for i = 0, all_tracks - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                                    end
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
                                    for i = 0, all_tracks - 1 do
                                        local track = r.GetTrack(0, i)
                                        r.SetMediaTrackInfo_Value(track, "I_SOLO", 0)
                                    end
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
                    
                                        if tagsection_open then r.ImGui_EndChild(ctx) end
                  
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
                if r.ImGui_Button(ctx, ADD_FX_TO_ITEM and "ITEM" or "TRACK", button_width, 20) then
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
            r.ImGui_PushFont(ctx, IconFont, 12)
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
        
        if show_create_folder_popup then
    r.ImGui_OpenPopup(ctx, "Create New Folder")
        end

        if r.ImGui_BeginPopupModal(ctx, "Create New Folder", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "Create new folder for: " .. (new_folder_for_plugin or ""))
            r.ImGui_Separator(ctx)
            
            r.ImGui_PushItemWidth(ctx, 250)
            local changed, new_name = r.ImGui_InputTextWithHint(ctx, "##NewFolderName", "Enter folder name", new_folder_name_input)
            if changed then
                new_folder_name_input = new_name
            end
            r.ImGui_PopItemWidth(ctx)
            
            r.ImGui_Separator(ctx)
            if r.ImGui_Button(ctx, "Create", 100, 0) then
                if new_folder_name_input and new_folder_name_input ~= "" and new_folder_for_plugin and new_folder_for_plugin ~= "" then
                    config.custom_folders[new_folder_name_input] = {new_folder_for_plugin}
                    SaveCustomFolders()
                    r.ShowMessageBox("Folder '" .. new_folder_name_input .. "' created with plugin", "Success", 0)
                end
                show_create_folder_popup = false
                new_folder_for_plugin = ""
                new_folder_name_input = ""
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Cancel", 100, 0) then
                show_create_folder_popup = false
                new_folder_for_plugin = ""
                new_folder_name_input = ""
                r.ImGui_CloseCurrentPopup(ctx)
            end
            
            r.ImGui_EndPopup(ctx)
        end

        -- CREATE PARENT FOLDER POPUP
        if show_create_parent_folder_popup then
            r.ImGui_OpenPopup(ctx, "Create Parent Folder")
        end

        if r.ImGui_BeginPopupModal(ctx, "Create Parent Folder", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "Create parent folder above: " .. (selected_folder_name or ""))
            r.ImGui_Separator(ctx)
            
            r.ImGui_PushItemWidth(ctx, 250)
            local changed, new_name = r.ImGui_InputTextWithHint(ctx, "##ParentFolderName", "Enter parent folder name", new_parent_folder_name or "")
            if changed then
                new_parent_folder_name = new_name
            end
            r.ImGui_PopItemWidth(ctx)
            
            r.ImGui_Separator(ctx)
            if r.ImGui_Button(ctx, "Create", 100, 0) then
                if new_parent_folder_name and new_parent_folder_name ~= "" and selected_folder_for_parent then
                    local parts = {}
                    for part in selected_folder_for_parent:gmatch("[^/]+") do
                        table.insert(parts, part)
                    end
                    
                    if #parts > 0 then
                        local folder_name = parts[#parts]
                        
                        local current = config.custom_folders
                        for i = 1, #parts - 1 do
                            current = current[parts[i]]
                        end
                        
                        local old_content = current[folder_name]
                        current[folder_name] = nil
                        
                        current[new_parent_folder_name] = {
                            [folder_name] = old_content
                        }
                        
                        SaveCustomFolders()
                        r.ShowMessageBox("Parent folder '" .. new_parent_folder_name .. "' created successfully!", "Success", 0)
                    end
                end
                show_create_parent_folder_popup = false
                selected_folder_for_parent = nil
                selected_folder_name = nil
                new_parent_folder_name = ""
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Cancel", 100, 0) then
                show_create_parent_folder_popup = false
                selected_folder_for_parent = nil
                selected_folder_name = nil
                new_parent_folder_name = ""
                r.ImGui_CloseCurrentPopup(ctx)
            end
            
            r.ImGui_EndPopup(ctx)
        end
        
    if check_esc_key() then open = false end
    r.ImGui_End(ctx)
        if config.enable_drag_add_fx then
            DrawDragOverlay()
        end
        end
        
        if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
            r.ImGui_PopFont(ctx)
        end
    if pushed_main_styles then
    r.ImGui_PopStyleVar(ctx, 6)
        r.ImGui_PopStyleColor(ctx, 13)
    end
    
    if SHOULD_CLOSE_SCRIPT then
        SetRunningState(false)
        return
    end
    
    HandleDragAndDrop()
    
    if open then        
        r.defer(Main)
    end
    
end
local initial_visibility = r.GetExtState("TK_FX_BROWSER", "visibility")
if initial_visibility == "" then
    r.SetExtState("TK_FX_BROWSER", "visibility", "visible", true)
end

InitializeImGuiContext()
Main()