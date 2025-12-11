-- @description TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 1.7.2
-- @changelog 
--[[
v1.7.2:
+ New Time Selection tab with integration for TK_time selection loop color script
+ Overlay Grid: Added Adaptive grid division mode (zooms with arrange view)
+ Overlay Grid: Added "Avoid Items" option to hide grid lines behind items
+ Overlay Grid: Added 1/16 and 1/32 subdivisions
+ Performance optimizations for Settings window
+ Track Visibility list uses cached ListClipper for virtual scrolling

v1.7.1:
+ Added audio, MIDI, bus, folder track type filters to Icons tab

v1.7.0:
+ Icons tab: New built-in folder browser (replaces native OS dialog)
+ Icons tab: Quick access buttons for Pictures, Downloads, Documents folders
+ Icons tab: Drive selection buttons for Windows
+ Folder browser always opens on top (fixes z-order issues)

v1.6.0:
+ Track Visibility tab: Replaced dropdown with individual checkboxes (Label, Color, Border)
+ Track Visibility tab: Added "Toplevel" preset mode (hides toplevel and closed folder tracks)
+ Track Visibility tab: Added "Reverse" checkbox to invert exclusion logic
+ Track Visibility tab: Dark Parent is now hidden for all excluded tracks
+ Track Visibility tab: Improved 5-column UI layout
+ Track Visibility tab: Track list shows colored backgrounds and folder icons

v1.5.0:
+ Settings window reorganized with 4-column layout
+ Labels tab: Added Label Border with thickness/opacity settings
+ Labels tab: Added Label Height padding control
+ Labels tab: Moved Label BG and Label Border sections together
+ Icons tab: Embedded icon browser directly in tab (no popup)
+ Icons tab: Reorganized layout with 4-column grid
+ Track Visibility tab: Added "Exclude by name" filter with Hide/Show buttons
+ Track Visibility tab: Added "Hide in TCP" toggle to sync with REAPER TCP/MCP visibility
+ Track Visibility tab: Added visible track counter (X/Y)
+ Track Visibility tab: Track colors now respect Inherit/Deep Inherit settings
+ Swapped Grid & BG tab with Icons tab (Grid & BG is now tab 3, Icons is tab 4)
+ Tab styling: Inactive tabs are gray, active tab is red
+ Removed Autosave toggle and Save button (autosave always on)
+ Fixed inherit parent label positioning for all alignment modes (center/left/right)
+ Fixed icon and inherit parent label overlap issues
+ Track labels now stay vertically aligned regardless of icons or parent labels
+ Window height increased to accommodate new controls

v1.3.0:
+ Binary search optimization for visible tracks (significant performance improvement for large projects)
+ Improved pinned tracks detection stability
+ Fixed pinned tracks overlay issues with master track
]]--

local function GetScriptVersion()
    local file = io.open(debug.getinfo(1,'S').source:match[[^@?(.*)$]], "r")
    if file then
        for line in file:lines() do
            local version = line:match("^%-%- @version%s+(.+)$")
            if version then
                file:close()
                return version
            end
        end
        file:close()
    end
    return "unknown"
end

local SCRIPT_VERSION = GetScriptVersion()

local r                  = reaper
-- OS detectie + Linux pass-through overlay (voorkomt click-capture op Linux window managers)
local OS                 = r.GetOS()
local IS_LINUX           = OS:lower():find("linux") ~= nil
local script_path        = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
local preset_path        = script_path .. "TK_Trackname_Presets/"
local json               = dofile(script_path .. "json.lua")
local track_icon_browser = dofile(script_path .. "track_icon_browser.lua")
local track_icon_manager = dofile(script_path .. "track_icon_manager.lua")
package.path             = r.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local im                 = require 'imgui' '0.9.3'
local ctx                = im.CreateContext('Track Names')


local script_active      = true
local settings_visible   = false
local last_update_time   = 0
local last_project       = nil
local last_track_count   = 0
local overlay_enabled    = false
local needs_font_update  = false
local ImGuiScale_saved   = nil
local screen_scale       = nil
local grid_divide_state  = 0
local overlay_hwnd = nil               -- Store overlay window handle
local zorder_handled_at_startup = false -- Only fix z-order once at startup

local color_cache        = {}
local cached_bg_color    = nil

local excluded_tracks    = {}
local exclude_filter     = ""
local tcp_synced         = false
local mcp_synced         = false
local settings_tab       = 1
local track_visibility_clipper = nil

local folder_browser_open = false
local folder_browser_path = ""
local folder_browser_drives = {}
local folder_browser_quick_paths = {}

local function GetQuickPaths()
    local paths = {}
    if OS:match("Win") then
        local userprofile = os.getenv("USERPROFILE")
        if userprofile then
            local pictures = userprofile .. "\\Pictures"
            if r.EnumerateSubdirectories(pictures .. "\\", 0) or r.EnumerateFiles(pictures .. "\\", 0) then
                table.insert(paths, {name = "📷 Pictures", path = pictures})
            end
            local downloads = userprofile .. "\\Downloads"
            if r.EnumerateSubdirectories(downloads .. "\\", 0) or r.EnumerateFiles(downloads .. "\\", 0) then
                table.insert(paths, {name = "📥 Downloads", path = downloads})
            end
            local documents = userprofile .. "\\Documents"
            if r.EnumerateSubdirectories(documents .. "\\", 0) or r.EnumerateFiles(documents .. "\\", 0) then
                table.insert(paths, {name = "📄 Documents", path = documents})
            end
        end
    elseif OS:match("OSX") or OS:match("macOS") then
        local home = os.getenv("HOME")
        if home then
            table.insert(paths, {name = "📷 Pictures", path = home .. "/Pictures"})
            table.insert(paths, {name = "📥 Downloads", path = home .. "/Downloads"})
            table.insert(paths, {name = "📄 Documents", path = home .. "/Documents"})
        end
    else
        local home = os.getenv("HOME")
        if home then
            table.insert(paths, {name = "📷 Pictures", path = home .. "/Pictures"})
            table.insert(paths, {name = "📥 Downloads", path = home .. "/Downloads"})
            table.insert(paths, {name = "📄 Documents", path = home .. "/Documents"})
        end
    end
    return paths
end

local function GetDrives()
    local drives = {}
    if OS:match("Win") then
        for i = 65, 90 do
            local drive = string.char(i) .. ":"
            local test_path = drive .. "\\"
            local subdir = r.EnumerateSubdirectories(test_path, 0)
            local file = r.EnumerateFiles(test_path, 0)
            if subdir or file or r.file_exists(test_path .. "desktop.ini") then
                table.insert(drives, drive)
            end
        end
        if #drives == 0 then
            table.insert(drives, "C:")
            table.insert(drives, "D:")
        end
    else
        table.insert(drives, "/")
    end
    return drives
end

local function GetSubdirectories(path)
    local dirs = {}
    local idx = 0
    local subdir = r.EnumerateSubdirectories(path, idx)
    while subdir do
        if subdir ~= "." and subdir ~= ".." then
            table.insert(dirs, subdir)
        end
        idx = idx + 1
        subdir = r.EnumerateSubdirectories(path, idx)
    end
    table.sort(dirs, function(a, b) return a:lower() < b:lower() end)
    return dirs
end

local function DrawFolderBrowserPopup(ctx)
    local selected_folder = nil
    local popup_flags = r.ImGui_WindowFlags_AlwaysAutoResize()
    
    r.ImGui_SetNextWindowSize(ctx, 400, 500, r.ImGui_Cond_FirstUseEver())
    
    if r.ImGui_BeginPopupModal(ctx, "TK FOLDER BROWSER##FolderBrowser", nil, 0) then
        if #folder_browser_drives == 0 then
            folder_browser_drives = GetDrives()
        end
        if #folder_browser_quick_paths == 0 then
            folder_browser_quick_paths = GetQuickPaths()
        end
        
        r.ImGui_Text(ctx, "Current folder:")
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x88AAFFFF)
        r.ImGui_TextWrapped(ctx, folder_browser_path ~= "" and folder_browser_path or "(none)")
        r.ImGui_PopStyleColor(ctx)
        
        r.ImGui_Separator(ctx)
        
        if #folder_browser_quick_paths > 0 then
            r.ImGui_Text(ctx, "Quick Access:")
            for _, qp in ipairs(folder_browser_quick_paths) do
                if r.ImGui_Button(ctx, qp.name) then
                    folder_browser_path = qp.path
                end
                r.ImGui_SameLine(ctx)
            end
            r.ImGui_Dummy(ctx, 0, 0)
            r.ImGui_Separator(ctx)
        end
        
        if OS:match("Win") then
            r.ImGui_Text(ctx, "Drives:")
            for _, drive in ipairs(folder_browser_drives) do
                if r.ImGui_Button(ctx, drive, 40) then
                    folder_browser_path = drive
                end
                r.ImGui_SameLine(ctx)
            end
            r.ImGui_Dummy(ctx, 0, 0)
            r.ImGui_Separator(ctx)
        end
        
        if folder_browser_path ~= "" then
            if r.ImGui_Button(ctx, "^ Parent Folder") then
                local parent = folder_browser_path:match("(.+)[/\\][^/\\]+$")
                if parent then
                    if OS:match("Win") and #parent == 2 then
                        folder_browser_path = parent
                    elseif parent ~= "" then
                        folder_browser_path = parent
                    end
                elseif OS:match("Win") then
                    if #folder_browser_path <= 3 then
                        folder_browser_path = ""
                    else
                        folder_browser_path = folder_browser_path:sub(1, 2)
                    end
                else
                    folder_browser_path = "/"
                end
            end
        end
        
        r.ImGui_Dummy(ctx, 0, 5)
        
        local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
        local list_height = avail_h - 45
        if list_height < 100 then list_height = 100 end
        
        if r.ImGui_BeginChild(ctx, "FolderList", 0, list_height, 1) then
            if folder_browser_path ~= "" then
                local path_with_sep = folder_browser_path
                if not path_with_sep:match("[/\\]$") then
                    path_with_sep = path_with_sep .. (OS:match("Win") and "\\" or "/")
                end
                
                local subdirs = GetSubdirectories(path_with_sep)
                
                for _, dir in ipairs(subdirs) do
                    local icon = "📁 "
                    if r.ImGui_Selectable(ctx, icon .. dir, false, r.ImGui_SelectableFlags_DontClosePopups()) then
                        local sep = OS:match("Win") and "\\" or "/"
                        if folder_browser_path:match("[/\\]$") then
                            folder_browser_path = folder_browser_path .. dir
                        else
                            folder_browser_path = folder_browser_path .. sep .. dir
                        end
                    end
                end
                
                if #subdirs == 0 then
                    r.ImGui_TextDisabled(ctx, "(no subfolders)")
                end
            else
                r.ImGui_TextDisabled(ctx, "Select a drive above")
            end
            r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_Separator(ctx)
        
        local btn_width = 120
        local spacing = 10
        local total_width = btn_width * 2 + spacing
        local avail_width = r.ImGui_GetContentRegionAvail(ctx)
        r.ImGui_SetCursorPosX(ctx, (avail_width - total_width) / 2 + r.ImGui_GetCursorPosX(ctx))
        
        if folder_browser_path ~= "" then
            if r.ImGui_Button(ctx, "Select This Folder", btn_width) then
                selected_folder = folder_browser_path
                folder_browser_open = false
                r.ImGui_CloseCurrentPopup(ctx)
            end
        else
            r.ImGui_BeginDisabled(ctx)
            r.ImGui_Button(ctx, "Select This Folder", btn_width)
            r.ImGui_EndDisabled(ctx)
        end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel", btn_width) then
            folder_browser_open = false
            r.ImGui_CloseCurrentPopup(ctx)
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    return selected_folder
end

local flags              = r.ImGui_WindowFlags_NoTitleBar() |
                           r.ImGui_WindowFlags_NoResize() |
                           r.ImGui_WindowFlags_NoNav() |
                           r.ImGui_WindowFlags_NoScrollbar() |
                           r.ImGui_WindowFlags_NoDecoration() |
                           r.ImGui_WindowFlags_NoDocking() | 
                           r.ImGui_WindowFlags_NoBackground()

local window_flags       = flags | 
                           r.ImGui_WindowFlags_NoInputs() |
                           r.ImGui_WindowFlags_NoMove() |
                           r.ImGui_WindowFlags_NoSavedSettings() |
                           r.ImGui_WindowFlags_NoMouseInputs() |
                           r.ImGui_WindowFlags_NoFocusOnAppearing() 
                          

local settings_flags     = r.ImGui_WindowFlags_NoTitleBar() | 
                           r.ImGui_WindowFlags_TopMost() |
                           r.ImGui_WindowFlags_NoResize() 



-- Sexan's positioning system
local LEFT, TOP, RIGHT, BOT = 0, 0, 0, 0
local WX, WY = 0, 0
local draw_list, scroll_size = nil, 0
local OLD_VAL = 0

-- Window setup using Sexan's method
local main = r.GetMainHwnd()
local arrange = r.JS_Window_FindChildByID(main, 0x3E8)

local function DrawOverArrange(force_update)
    local _, DPI_RPR = r.get_config_var_string("uiscale")
    scroll_size = 15 * DPI_RPR
    
    local _, orig_LEFT, orig_TOP, orig_RIGHT, orig_BOT = r.JS_Window_GetRect(arrange)
    local current_val = orig_TOP + orig_BOT + orig_LEFT + orig_RIGHT
    
    if current_val ~= OLD_VAL or force_update then
        OLD_VAL = current_val
        LEFT, TOP = im.PointConvertNative(ctx, orig_LEFT, orig_TOP)
        RIGHT, BOT = im.PointConvertNative(ctx, orig_RIGHT, orig_BOT)
    end
    r.ImGui_SetNextWindowPos(ctx, LEFT, TOP)
    r.ImGui_SetNextWindowSize(ctx, (RIGHT - LEFT) - scroll_size, (BOT - TOP) - scroll_size)
end

local function GetArrangeViewBounds()
    local _, scroll_y = r.JS_Window_GetScrollInfo(arrange, "v")
    local _, _, _, _, view_height = r.JS_Window_GetClientRect(arrange)
    return scroll_y, view_height
end

local function FindFirstVisibleTrack(track_count, view_top, view_bottom)
    if track_count == 0 then return -1 end
    
    local low, high = 0, track_count - 1
    local result = -1
    
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local track = r.GetTrack(0, mid)
        local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
        local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
        local track_bottom = track_y + track_height
        
        if track_bottom >= 0 and track_y < view_bottom then
            result = mid
            high = mid - 1
        elseif track_bottom < 0 then
            low = mid + 1
        else
            high = mid - 1
        end
    end
    
    if result > 0 then result = result - 1 end
    
    return result
end

local function FindLastVisibleTrack(track_count, view_top, view_bottom)
    if track_count == 0 then return -1 end
    
    local low, high = 0, track_count - 1
    local result = -1
    
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local track = r.GetTrack(0, mid)
        local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
        local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
        
        if track_y <= view_bottom then
            result = mid
            low = mid + 1
        else
            high = mid - 1
        end
    end
    
    if result >= 0 and result < track_count - 1 then result = result + 1 end
    
    return result
end

local function ensureOverlayBehindWindows()
    -- Get overlay window handle if we don't have it yet
    if not overlay_hwnd then
        overlay_hwnd = r.JS_Window_Find("Track Names Display", true)
        if not overlay_hwnd then return end
    end
    
    -- Collect all visible REAPER child windows that should be above overlay
    local windowsToReorder = {}
    local arr = r.new_array({}, 1024)
    local ret = r.JS_Window_ArrayAllTop(arr)
    
    if ret >= 1 then
        local childs = arr.table()
        for j = 1, #childs do
            local hwnd = r.JS_Window_HandleFromAddress(childs[j])
            
            -- Skip the overlay itself and the main window
            if hwnd ~= overlay_hwnd and hwnd ~= main and r.JS_Window_IsVisible(hwnd) then
                local className = r.JS_Window_GetClassName(hwnd)
                local title = r.JS_Window_GetTitle(hwnd)
                
                -- Check if this is a REAPER window that should be above overlay
                if className:match("^REAPER") or      -- All REAPER windows
                   className == "#32770" or           -- Dialogs (Actions, Preferences, etc)
                   className:match("Lua_LICE") or    -- Lua GUIs
                   className:match("^WDL") or        -- WDL windows
                   title:match("Media Explorer") or   -- Media Explorer by title
                   title:match("FX Browser") then     -- FX Browser by title
                    
                    -- Verify it's a child of REAPER main window or is a top-level REAPER window
                    local parent = r.JS_Window_GetParent(hwnd)
                    if parent == main or parent == 0 or parent == nil then
                        table.insert(windowsToReorder, hwnd)
                    end
                end
            end
        end
    end
    
    -- Also check for floating FX windows
    local trackCount = r.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = r.GetTrack(0, i)
        if track then
            local fxCount = r.TrackFX_GetCount(track)
            for fx = 0, fxCount - 1 do
                local floatingHwnd = r.TrackFX_GetFloatingWindow(track, fx)
                if floatingHwnd and r.JS_Window_IsVisible(floatingHwnd) then
                    table.insert(windowsToReorder, floatingHwnd)
                end
            end
        end
    end
    
    -- Bring these windows above overlay using SetZOrder with HWND_TOP
    -- This doesn't change focus, just ensures they're above the overlay
    for _, hwnd in ipairs(windowsToReorder) do
        r.JS_Window_SetZOrder(hwnd, "TOP")
    end
end
                                              
local default_settings              = {
    text_opacity                    = 1.0,
    show_parent_tracks              = true,
    show_child_tracks               = true,
    show_normal_tracks              = true,
    show_first_fx                   = false,
    show_parent_label               = false,
    show_record_color               = true,
    horizontal_offset               = 100,
    vertical_offset                 = 0,
    selected_font                   = 1,
    color_mode                      = 1,
    overlay_alpha                   = 0.1,
    show_track_colors               = true,
    grid_color                      = 0.0,
    bg_brightness                   = 0.2,
    envelope_color_intensity        = 1.0,
    custom_colors_enabled           = false,
    show_label                      = true,
    label_alpha                     = 0.3,
    label_color_mode                = 1,
    text_centered                   = false,
    show_settings_button            = false,
    text_size                       = 14,
    inherit_parent_color            = false,
    deep_inherit_color              = false,
    right_align                     = false,
    show_parent_colors              = true,
    show_child_colors               = true,
    show_normal_colors              = true,
    show_envelope_colors            = true,
    blend_mode                      = 1,
    show_track_numbers              = false,
    track_number_style              = 1,
    autosave_enabled                = true,
    gradient_enabled                = false,
    gradient_direction              = 1,
    gradient_start_alpha            = 1.0,
    gradient_end_alpha              = 0.0,
    track_name_length               = 1,
    fixed_label_length              = 10,
    fixed_length_padding_char       = "·",  
    all_text_enabled                = true,
    label_border                    = false,
    label_border_thickness          = 1.0,
    label_border_opacity            = 1.0,
    label_height_padding            = 1,
    folder_border                   = false,
    folder_border_left              = true,
    folder_border_right             = true,
    folder_border_top               = true,
    folder_border_bottom            = true,
    track_border                    = false,
    track_border_left               = true,
    track_border_right              = true,
    track_border_top                = true,
    track_border_bottom             = true,
    border_thickness                = 2.0,
    border_opacity                  = 1.0,
    button_x                        = 100,
    button_y                        = 100,
    gradient_start_alpha_cached     = 0,
    gradient_end_alpha_cached       = 0,
    darker_parent_tracks            = false,
    hide_dark_parent_for_excluded   = false,
    parent_darkness                 = 0.7,
    darker_parent_opacity           = 1.0,
    nested_parents_darker           = false,
    show_info_line                  = false,
    color_gradient_enabled          = false,
    bg_brightness_tr1               = 0.2,
    bg_brightness_tr2               = 0.2,
    sel_brightness_tr1              = 0.3,  
    sel_brightness_tr2              = 0.3,
    show_envelope_names             = false,
    envelope_text_opacity           = 0.8,
    grid_color_enabled              = true,
    bg_brightness_enabled           = true,
    master_track_color              = 0x6699FFFF,
    use_custom_master_color         = true,
    master_overlay_alpha            = 1.0,  
    master_gradient_enabled         = true,  
    master_gradient_start_alpha     = 1.0,
    master_gradient_end_alpha       = 0.0,
    text_hover_hide                 = false,
    text_hover_enabled              = false,
    auto_center                     = false,
    fx_name_length                  = 1,
    fx_fixed_label_length           = 10,
    pass_through_overlay            = IS_LINUX,
    -- Track Icon Settings
    show_track_icons                = true,
    icon_size                       = 24,
    icon_position                   = 1,  -- 1=left, 2=right
    icon_spacing                    = 8,
    icon_opacity                    = 1.0,
    exclude_hide_label             = true,
    exclude_hide_color              = true,
    exclude_hide_border             = true,
    folders_only_mode               = false,
    toplevel_mode                   = false,
    reversed_mode                   = false,
    filter_hide_audio               = false,
    filter_hide_midi                = false,
    filter_hide_bus                 = false,
    filter_hide_folder              = false,
    overlay_grid_enabled            = false,
    overlay_grid_color              = 0x000000FF,
    overlay_grid_beat_color         = 0x000000FF,
    overlay_grid_bar_color          = 0x000000FF,
    overlay_grid_thickness          = 1.0,
    overlay_grid_bar_thickness      = 2.0,
    overlay_grid_beat_thickness     = 1.0,
    overlay_grid_opacity            = 1.0,
    overlay_grid_vertical           = true,
    overlay_grid_horizontal         = false,
    overlay_grid_division           = 1,
    overlay_grid_avoid_items        = false,
}

local settings = {}
for k, v in pairs(default_settings) do
    settings[k] = v
end

local blend_modes = {
    " Normal", " Multiply", " Screen", " Overlay", " Darken",
    " Lighten", " Color Dodge", " Color Burn", " Hard Light", " Soft Light"
}

local text_sizes = {8, 10, 12, 14, 16, 18, 20, 24, 28, 32}
local fonts = {
    "Arial", "Helvetica", "Verdana", "Tahoma", "Times New Roman",
    "Georgia", "Courier New", "Consolas", "Trebuchet MS", "Impact", "Roboto",
    "Open Sans", "Ubuntu", "Segoe UI", "Noto Sans", "Liberation Sans",
    "DejaVu Sans"
}

local color_modes = {"White", "Black", "Track Color", "Complementary"}
local font_objects = {}
local settings_font

function CreateFonts()
    font_objects = {}
    for _, font_name in ipairs(fonts) do
        local font = r.ImGui_CreateFont(font_name, settings.text_size)
        table.insert(font_objects, font)
        r.ImGui_Attach(ctx, font)
    end
    settings_font = r.ImGui_CreateFont('Arial', 12)
    r.ImGui_Attach(ctx, settings_font)
end
if old_text_size ~= settings.text_size then CreateFonts()end 

function GetTextColor(track, is_child, is_parent_label)
    if is_parent_label then
        if settings.show_label then
            return 0xFFFFFFFF 
        else
            if settings.color_mode == 1 then
                return 0xFFFFFFFF 
            elseif settings.color_mode == 2 then
                return 0x000000FF 
            elseif settings.color_mode == 3 then
                local track_color = r.GetTrackColor(track)
                return track_color == 0 and 0xFFFFFFFF or GetCachedColor(track_color, 1.0)
            else 
                local track_color = r.GetTrackColor(track)
                if track_color == 0 then return 0xFFFFFFFF end
                
                local r_val, g_val, b_val = r.ColorFromNative(track_color)
                local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val/255, g_val/255, b_val/255)
                h = (h + 0.5) % 1.0
                local r_comp, g_comp, b_comp = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
                return r.ColorToNative(
                    math.floor(r_comp * 255 + 0.5),
                    math.floor(g_comp * 255 + 0.5),
                    math.floor(b_comp * 255 + 0.5)
                ) | 0xFF
            end
        end
    end

    if is_child and settings.inherit_parent_color then
        local parent_track = r.GetParentTrack(track)
        if parent_track then track = parent_track end
    end
    if not settings.show_label then
        if settings.color_mode == 1 then
            return 0xFFFFFFFF 
        elseif settings.color_mode == 2 then
            return 0x000000FF
        elseif settings.color_mode == 3 then
            local track_color = r.GetTrackColor(track)
            return track_color == 0 and 0xFFFFFFFF or GetCachedColor(track_color, 1.0)
        else 
            local track_color = r.GetTrackColor(track)
            if track_color == 0 then return 0xFFFFFFFF end
            
            local r_val, g_val, b_val = r.ColorFromNative(track_color)
            local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val/255, g_val/255, b_val/255)
            h = (h + 0.5) % 1.0
            local r_comp, g_comp, b_comp = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
            return r.ColorToNative(
                math.floor(r_comp * 255 + 0.5),
                math.floor(g_comp * 255 + 0.5),
                math.floor(b_comp * 255 + 0.5)
            ) | 0xFF
        end
    end

    local label_color
    if settings.label_color_mode == 1 then
        label_color = 0xFFFFFF
    elseif settings.label_color_mode == 2 then
        label_color = 0x000000
    elseif settings.label_color_mode == 3 then
        label_color = r.GetTrackColor(track)
    else
        local track_color = r.GetTrackColor(track)
        local r_val, g_val, b_val = r.ColorFromNative(track_color)
        local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val/255, g_val/255, b_val/255)
        h = (h + 0.5) % 1.0
        local r_comp, g_comp, b_comp = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
        label_color = r.ColorToNative(
            math.floor(r_comp * 255 + 0.5),
            math.floor(g_comp * 255 + 0.5),
            math.floor(b_comp * 255 + 0.5)
        )
    end

    local text_color
    if settings.color_mode == 3 and is_parent_label then 
        text_color = 0xFFFFFFFF
    elseif settings.color_mode == 1 then 
        text_color = (label_color == 0xFFFFFF) and 0x000000FF or 0xFFFFFFFF
    elseif settings.color_mode == 2 then
        text_color = (label_color == 0x000000) and 0xFFFFFFFF or 0x000000FF
    elseif settings.color_mode == 3 then
        local track_color = r.GetTrackColor(track)
        if label_color == 0xFFFFFF then
            text_color = GetCachedColor(track_color, 1.0)
        elseif track_color == 0 or track_color == label_color then
            text_color = 0xFFFFFFFF
        else
            text_color = GetCachedColor(track_color, 1.0)
        end
    else
        local track_color = r.GetTrackColor(track)
        if track_color == 0 and (label_color == 0x000000 or settings.label_color_mode == 3) then
            text_color = 0xFFFFFFFF
        elseif label_color == 0xFFFFFF then
            local r_val, g_val, b_val = r.ColorFromNative(track_color)
            local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val/255, g_val/255, b_val/255)
            h = (h + 0.5) % 1.0
            local r_comp, g_comp, b_comp = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
            text_color = r.ColorToNative(
                math.floor(r_comp * 255 + 0.5),
                math.floor(g_comp * 255 + 0.5),
                math.floor(b_comp * 255 + 0.5)
            ) | 0xFF
        elseif settings.label_color_mode == 4 then
            text_color = 0xFFFFFFFF
        else
            local r_val, g_val, b_val = r.ColorFromNative(track_color)
            local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val/255, g_val/255, b_val/255)
            h = (h + 0.5) % 1.0
            local r_comp, g_comp, b_comp = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
            text_color = r.ColorToNative(
                math.floor(r_comp * 255 + 0.5),
                math.floor(g_comp * 255 + 0.5),
                math.floor(b_comp * 255 + 0.5)
            ) | 0xFF
        end
    end

    return text_color
end

function GetLabelColor(track)
    if settings.label_color_mode == 1 then
        return r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, settings.label_alpha)
    elseif settings.label_color_mode == 2 then
        return r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, settings.label_alpha)
    elseif settings.label_color_mode == 3 then
        return GetCachedColor(r.GetTrackColor(track), settings.label_alpha)
    else
        local track_color = r.GetTrackColor(track)
        local cache_key = "label_complementary_" .. track_color .. "_" .. settings.label_alpha
        if not color_cache[cache_key] then
            local r_val, g_val, b_val = r.ColorFromNative(track_color)
            local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val/255, g_val/255, b_val/255)
            h = (h + 0.5) % 1.0
            local r_val, g_val, b_val = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
            color_cache[cache_key] = r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, settings.label_alpha)
        end
        return color_cache[cache_key]
    end
end

function UpdateBgColorCache()
    cached_bg_color = reaper.GetThemeColor("col_arrangebg", 0)
end

function GetCachedColor(native_color, alpha)
    if not native_color then 
        native_color = settings.master_track_color 
    end
    
    local cache_key = tostring(native_color) .. "_" .. tostring(alpha)
    
    if not color_cache[cache_key] then
        local r, g, b = reaper.ColorFromNative(native_color)
        color_cache[cache_key] = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, alpha)
    end
    
    return color_cache[cache_key]
end


function UpdateGradientAlphaCache()
    settings.gradient_start_alpha_cached = (settings.gradient_start_alpha//0.00392156862745098)
    settings.gradient_end_alpha_cached = (settings.gradient_end_alpha//0.00392156862745098)
end

function SaveSettings()
    local section = "TK_TRACKNAMES"
    local settings_json = json.encode(settings)
    r.SetExtState(section, "settings", settings_json, true)
end

function LoadSettings()
    local section = "TK_TRACKNAMES"
    local settings_json = r.GetExtState(section, "settings")
    if settings_json ~= "" then
        local old_text_size = settings.text_size
        local loaded_settings = json.decode(settings_json)
        for k, v in pairs(loaded_settings) do
            settings[k] = v
        end
        if old_text_size ~= settings.text_size then
            needs_font_update = true
        end
        UpdateGradientAlphaCache()
    end
end

function SavePreset(name)
    local preset_data = {}
    for k, v in pairs(settings) do
        if k ~= "manual_scaling" then
            preset_data[k] = v
        end
    end
    r.RecursiveCreateDirectory(preset_path, 0)
    local file = io.open(preset_path .. name .. '.json', 'w')
    if file then
        file:write(json.encode(preset_data))
        file:close()
    end
end

function LoadPreset(name)
    local file = io.open(preset_path .. name .. '.json', 'r')
    if file then
        local content = file:read('*all')
        file:close()
        local old_text_size = settings.text_size
        local preset_data = json.decode(content)
        
        for key, value in pairs(preset_data) do
            settings[key] = value
        end
        
        if settings.custom_colors_enabled then
            UpdateGridColors()   
            UpdateArrangeBG()
    	    UpdateTrackColors() 
        end
        
        if old_text_size ~= settings.text_size then
            needs_font_update = true
        end
        SaveSettings()
    end
end

function GetPresetList()
    local presets = {}
    local idx = 0
    local filename = r.EnumerateFiles(preset_path, idx)
    
    while filename do
        if filename:match('%.json$') then
            presets[#presets + 1] = filename:gsub('%.json$', '')
        end
        idx = idx + 1
        filename = r.EnumerateFiles(preset_path, idx)
    end   
    return presets
end

function UpdateGridColors()
    if not settings.grid_color_enabled then
        reaper.SetThemeColor("col_gridlines", -1, 0)
        reaper.SetThemeColor("col_gridlines2", -1, 0)
        reaper.SetThemeColor("col_gridlines3", -1, 0)
        reaper.SetThemeColor("col_tr1_divline", -1, 0)
        reaper.SetThemeColor("col_tr2_divline", -1, 0)
        return
    end
    local grid_value = (settings.grid_color * 255)//1
    reaper.SetThemeColor("col_gridlines", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines2", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines3", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr1_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr2_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.UpdateArrange()
end

function UpdateArrangeBG()
    if not settings.bg_brightness_enabled then
        reaper.SetThemeColor("col_arrangebg", -1, 0)
    else
        local MIN_BG_VALUE = 13
        local bg_value = math.max((settings.bg_brightness * 255)//1, MIN_BG_VALUE)
        reaper.SetThemeColor("col_arrangebg", reaper.ColorToNative(bg_value, bg_value, bg_value), 0)
    end
    reaper.UpdateArrange()
end

function DrawOverlayGrid(draw_list, WY)
    if not settings.overlay_grid_enabled then return end
    
    local viewport_start, viewport_end = r.GetSet_ArrangeView2(0, false, 0, 0)
    local arrange_width = RIGHT - LEFT
    if arrange_width <= 0 then return end
    
    local alpha = math.floor(settings.overlay_grid_opacity * 255)
    local h_color = (settings.overlay_grid_color & 0xFFFFFF00) | alpha
    
    local item_regions = {}
    if settings.overlay_grid_avoid_items then
        local num_items = r.CountMediaItems(0)
        for i = 0, num_items - 1 do
            local item = r.GetMediaItem(0, i)
            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
            local item_end = item_pos + item_len
            
            if item_end > viewport_start and item_pos < viewport_end then
                local track = r.GetMediaItem_Track(item)
                local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
                local track_h = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
                
                local item_y_top = WY + track_y
                local item_y_bot = WY + track_y + track_h
                
                if item_y_bot > WY and item_y_top < BOT - scroll_size then
                    table.insert(item_regions, {
                        x_start = item_pos,
                        x_end = item_end,
                        y_top = math.max(item_y_top, WY),
                        y_bot = math.min(item_y_bot, BOT - scroll_size)
                    })
                end
            end
        end
    end
    
    if settings.overlay_grid_horizontal then
        local num_tracks = r.CountTracks(0)
        for i = 0, num_tracks - 1 do
            local track = r.GetTrack(0, i)
            local y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
            local h = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
            local line_y = WY + y + h
            if line_y >= WY and line_y <= BOT - scroll_size then
                r.ImGui_DrawList_AddLine(draw_list,
                    LEFT, line_y,
                    RIGHT - scroll_size, line_y,
                    h_color, settings.overlay_grid_thickness)
            end
        end
    end
    
    if not settings.overlay_grid_vertical then return end
    
    local line_count = 0
    local max_lines = 5000
    
    local _, start_measures, start_cml = r.TimeMap2_timeToBeats(0, viewport_start)
    local start_measure = math.floor(start_measures)
    
    local division = settings.overlay_grid_division or 1
    local show_beats = true
    local bar_interval = 1
    
    if division == 0 then
        local tempo = r.Master_GetTempo()
        local seconds_per_beat = 60 / tempo
        local viewport_duration = viewport_end - viewport_start
        local pixels_per_beat = arrange_width * seconds_per_beat / viewport_duration
        
        if pixels_per_beat > 400 then
            division = 32
        elseif pixels_per_beat > 200 then
            division = 16
        elseif pixels_per_beat > 100 then
            division = 8
        elseif pixels_per_beat > 50 then
            division = 4
        elseif pixels_per_beat > 25 then
            division = 2
        elseif pixels_per_beat > 10 then
            division = 1
        elseif pixels_per_beat > 3 then
            division = 1
            show_beats = false
        elseif pixels_per_beat > 0.8 then
            division = 1
            show_beats = false
            bar_interval = 4
        elseif pixels_per_beat > 0.2 then
            division = 1
            show_beats = false
            bar_interval = 8
        elseif pixels_per_beat > 0.05 then
            division = 1
            show_beats = false
            bar_interval = 16
        elseif pixels_per_beat > 0.01 then
            division = 1
            show_beats = false
            bar_interval = 32
        else
            division = 1
            show_beats = false
            bar_interval = 64
        end
    end
    
    local measure = start_measure
    while line_count < max_lines do
        if bar_interval > 1 and measure % bar_interval ~= 0 then
            measure = measure + 1
            goto continue_measure
        end
        
        local measure_start = r.TimeMap2_beatsToTime(0, 0, measure)
        if measure_start > viewport_end then break end
        
        local timesig_num, timesig_denom = r.TimeMap_GetTimeSigAtTime(0, measure_start)
        
        local qn_per_beat = 4 / timesig_denom
        local beats_in_measure = timesig_num
        
        for beat = 0, beats_in_measure do
            local qn_in_measure = beat * qn_per_beat
            local beat_time = r.TimeMap2_beatsToTime(0, qn_in_measure, measure)
            
            local next_qn_in_measure
            if beat < beats_in_measure then
                next_qn_in_measure = (beat + 1) * qn_per_beat
            else
                next_qn_in_measure = beats_in_measure * qn_per_beat
            end
            local next_beat_time = r.TimeMap2_beatsToTime(0, next_qn_in_measure, measure)
            
            for sub = 0, division - 1 do
                if beat == beats_in_measure and sub > 0 then break end
                
                local is_bar = (beat == 0 and sub == 0)
                local is_beat = (sub == 0)
                
                if not show_beats and not is_bar then goto continue_sub end
                
                local time = beat_time + (next_beat_time - beat_time) * sub / division
                if time < viewport_start then goto continue_sub end
                if time > viewport_end then break end
                
                local pixels = arrange_width * (time - viewport_start) / (viewport_end - viewport_start)
                local screen_x = LEFT + pixels
                
                local base_color, thickness
                if is_bar then
                    base_color = settings.overlay_grid_bar_color & 0xFFFFFF00
                    thickness = settings.overlay_grid_bar_thickness
                elseif is_beat then
                    base_color = settings.overlay_grid_beat_color & 0xFFFFFF00
                    thickness = settings.overlay_grid_beat_thickness
                else
                    base_color = settings.overlay_grid_color & 0xFFFFFF00
                    thickness = settings.overlay_grid_thickness
                end
                
                local color = base_color | alpha
                
                if settings.overlay_grid_avoid_items and #item_regions > 0 then
                    local blocked = {}
                    for _, region in ipairs(item_regions) do
                        if time >= region.x_start and time <= region.x_end then
                            table.insert(blocked, { y_top = region.y_top, y_bot = region.y_bot })
                        end
                    end
                    
                    table.sort(blocked, function(a, b) return a.y_top < b.y_top end)
                    
                    local y_cursor = WY
                    for _, block in ipairs(blocked) do
                        if block.y_top > y_cursor then
                            r.ImGui_DrawList_AddLine(draw_list, screen_x, y_cursor, screen_x, block.y_top, color, thickness)
                        end
                        y_cursor = math.max(y_cursor, block.y_bot)
                    end
                    if y_cursor < BOT - scroll_size then
                        r.ImGui_DrawList_AddLine(draw_list, screen_x, y_cursor, screen_x, BOT - scroll_size, color, thickness)
                    end
                else
                    r.ImGui_DrawList_AddLine(
                        draw_list,
                        screen_x, WY,
                        screen_x, BOT - scroll_size,
                        color,
                        thickness
                    )
                end
                
                line_count = line_count + 1
                ::continue_sub::
            end
        end
        
        measure = measure + 1
        ::continue_measure::
    end
end

function UpdateTrackColors()
    local MIN_BG_VALUE = 13
    local bg_value_tr1 = math.max((settings.bg_brightness_tr1 * 255)//1, MIN_BG_VALUE)
    local bg_value_tr2 = math.max((settings.bg_brightness_tr2 * 255)//1, MIN_BG_VALUE)
    local sel_value_tr1 = math.max((settings.sel_brightness_tr1 * 255)//1, MIN_BG_VALUE)
    local sel_value_tr2 = math.max((settings.sel_brightness_tr2 * 255)//1, MIN_BG_VALUE)
    
    reaper.SetThemeColor("col_tr1_bg", reaper.ColorToNative(bg_value_tr1, bg_value_tr1, bg_value_tr1), 0)
    reaper.SetThemeColor("col_tr2_bg", reaper.ColorToNative(bg_value_tr2, bg_value_tr2, bg_value_tr2), 0)
    reaper.SetThemeColor("selcol_tr1_bg", reaper.ColorToNative(sel_value_tr1, sel_value_tr1, sel_value_tr1), 0)
    reaper.SetThemeColor("selcol_tr2_bg", reaper.ColorToNative(sel_value_tr2, sel_value_tr2, sel_value_tr2), 0)
    reaper.UpdateArrange()
end

function LoadExcludedTracks()
    local proj = r.EnumProjects(-1)
    local retval, data = r.GetProjExtState(proj, "TK_TRACKNAMES", "excluded_tracks")
    if retval == 1 and data ~= "" then
        local loaded = json.decode(data)
        if loaded then
            excluded_tracks = loaded
        end
    else
        excluded_tracks = {}
    end
end

function SaveExcludedTracks()
    local proj = r.EnumProjects(-1)
    r.SetProjExtState(proj, "TK_TRACKNAMES", "excluded_tracks", json.encode(excluded_tracks))
end

function GetTrackGUID(track)
    return r.GetTrackGUID(track)
end

function IsTrackExcluded(track)
    local guid = GetTrackGUID(track)
    return excluded_tracks[guid] == true
end

function SetTrackExcluded(track, excluded)
    local guid = GetTrackGUID(track)
    if excluded then
        excluded_tracks[guid] = true
    else
        excluded_tracks[guid] = nil
    end
    SaveExcludedTracks()
end

function RefreshProjectState()
    UpdateBgColorCache()
    track_icon_manager.RefreshAllIcons()
    LoadExcludedTracks()
    if settings.custom_colors_enabled then
        UpdateGridColors()
        UpdateArrangeBG()
        UpdateTrackColors()
    end
    reaper.UpdateArrange()
    last_update_time = 0
end

function ToggleColors()
    settings.custom_colors_enabled = not settings.custom_colors_enabled
    if settings.custom_colors_enabled then
        grid_divide_state = r.GetToggleCommandState(42331)
        if grid_divide_state == 1 then             
            r.Main_OnCommand(42331, 0)
        end
        UpdateGridColors()
        UpdateArrangeBG()
        UpdateTrackColors()
    else
        reaper.SetThemeColor("col_gridlines", -1, 0)
        reaper.SetThemeColor("col_gridlines2", -1, 0)
        reaper.SetThemeColor("col_gridlines3", -1, 0)
        reaper.SetThemeColor("col_arrangebg", -1, 0)
        reaper.SetThemeColor("col_tr1_bg", -1, 0)
        reaper.SetThemeColor("col_tr2_bg", -1, 0)
        reaper.SetThemeColor("selcol_tr1_bg", -1, 0)
        reaper.SetThemeColor("selcol_tr2_bg", -1, 0)
        reaper.SetThemeColor("col_tr1_divline", -1, 0)
        reaper.SetThemeColor("col_tr2_divline", -1, 0)
        
        if grid_divide_state == 1 then
            r.Main_OnCommand(42331, 0)
        end
    end
    reaper.UpdateArrange()
end

function ResetSettings()
    for k, v in pairs(default_settings) do
        settings[k] = v
    end
    if settings.custom_colors_enabled then
        ToggleColors()
    end   
    SaveSettings()
end

function BlendColor(track, blend, mode)
    local track_number = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local is_selected = r.IsTrackSelected(track)
    local base
    if is_selected then
        base = track_number % 2 == 0 
            and r.ColorToNative((settings.sel_brightness_tr2 * 255)//1, (settings.sel_brightness_tr2 * 255)//1, (settings.sel_brightness_tr2 * 255)//1)
            or r.ColorToNative((settings.sel_brightness_tr1 * 255)//1, (settings.sel_brightness_tr1 * 255)//1, (settings.sel_brightness_tr1 * 255)//1)
    else
        base = track_number % 2 == 0 
            and r.ColorToNative((settings.bg_brightness_tr2 * 255)//1, (settings.bg_brightness_tr2 * 255)//1, (settings.bg_brightness_tr2 * 255)//1)
            or r.ColorToNative((settings.bg_brightness_tr1 * 255)//1, (settings.bg_brightness_tr1 * 255)//1, (settings.bg_brightness_tr1 * 255)//1)
    end

    local cache_key = "blend_" .. base .. "_" .. blend .. "_" .. mode
    if color_cache[cache_key] then return color_cache[cache_key] end

    local base_r, base_g, base_b = reaper.ColorFromNative(base)
    local blend_r, blend_g, blend_b = reaper.ColorFromNative(blend)
    local result_r, result_g, result_b
    
    local function normalize(value) return value / 255.0 end
    local function denormalize(value) return math.floor(value * 255 + 0.5) end
    local function clamp(value) return math.max(0, math.min(255, value)) end

    local nb_r, nb_g, nb_b = normalize(base_r), normalize(base_g), normalize(base_b)
    local nbl_r, nbl_g, nbl_b = normalize(blend_r), normalize(blend_g), normalize(blend_b)

    if mode == 1 then 
        return blend
    elseif mode == 2 then -- Multiply
        result_r = denormalize(nb_r * nbl_r)
        result_g = denormalize(nb_g * nbl_g)
        result_b = denormalize(nb_b * nbl_b)
    elseif mode == 3 then -- Screen
        result_r = denormalize(1 - (1 - nb_r) * (1 - nbl_r))
        result_g = denormalize(1 - (1 - nb_g) * (1 - nbl_g))
        result_b = denormalize(1 - (1 - nb_b) * (1 - nbl_b))
    elseif mode == 4 then -- Overlay
        result_r = denormalize(nb_r < 0.5 and (2 * nb_r * nbl_r) or (1 - 2 * (1 - nb_r) * (1 - nbl_r)))
        result_g = denormalize(nb_g < 0.5 and (2 * nb_g * nbl_g) or (1 - 2 * (1 - nb_g) * (1 - nbl_g)))
        result_b = denormalize(nb_b < 0.5 and (2 * nb_b * nbl_b) or (1 - 2 * (1 - nb_b) * (1 - nbl_b)))
    elseif mode == 5 then -- Darken
        result_r = denormalize(math.min(nb_r, nbl_r))
        result_g = denormalize(math.min(nb_g, nbl_g))
        result_b = denormalize(math.min(nb_b, nbl_b))
    elseif mode == 6 then -- Lighten
        result_r = denormalize(math.max(nb_r, nbl_r))
        result_g = denormalize(math.max(nb_g, nbl_g))
        result_b = denormalize(math.max(nb_b, nbl_b))
    elseif mode == 7 then -- Color Dodge
        result_r = denormalize(nb_r == 0 and 0 or nbl_r == 1 and 1 or math.min(1, nb_r / (1 - nbl_r)))
        result_g = denormalize(nb_g == 0 and 0 or nbl_g == 1 and 1 or math.min(1, nb_g / (1 - nbl_g)))
        result_b = denormalize(nb_b == 0 and 0 or nbl_b == 1 and 1 or math.min(1, nb_b / (1 - nbl_b)))
    elseif mode == 8 then -- Color Burn
        result_r = denormalize(nb_r == 1 and 1 or nbl_r == 0 and 0 or 1 - math.min(1, (1 - nb_r) / nbl_r))
        result_g = denormalize(nb_g == 1 and 1 or nbl_g == 0 and 0 or 1 - math.min(1, (1 - nb_g) / nbl_g))
        result_b = denormalize(nb_b == 1 and 1 or nbl_b == 0 and 0 or 1 - math.min(1, (1 - nb_b) / nbl_b))
    elseif mode == 9 then -- Hard Light
        result_r = denormalize(nbl_r < 0.5 and (2 * nb_r * nbl_r) or (1 - 2 * (1 - nb_r) * (1 - nbl_r)))
        result_g = denormalize(nbl_g < 0.5 and (2 * nb_g * nbl_g) or (1 - 2 * (1 - nb_g) * (1 - nbl_g)))
        result_b = denormalize(nbl_b < 0.5 and (2 * nb_b * nbl_b) or (1 - 2 * (1 - nb_b) * (1 - nbl_b)))
    elseif mode == 10 then -- Soft Light
        local function softlight(a, b)
            if b < 0.5 then
                return 2 * a * b + a * a * (1 - 2 * b)
            else
                return 2 * a * (1 - b) + math.sqrt(a) * (2 * b - 1)
            end
        end
        result_r = denormalize(softlight(nb_r, nbl_r))
        result_g = denormalize(softlight(nb_g, nbl_g))
        result_b = denormalize(softlight(nb_b, nbl_b))
    end

    local result = reaper.ColorToNative(clamp(result_r), clamp(result_g), clamp(result_b))
    color_cache[cache_key] = result
    return result
end

function GetReaperMousePosition()
    local x, y = reaper.GetMousePosition()
    x, y = reaper.JS_Window_ScreenToClient(arrange, x, y)
    return x, y
end

function GetFolderBoundaries(track)
    if not track then return nil end
    if r.GetParentTrack(track) then return nil end
    
    local folder_depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if folder_depth ~= 1 then return nil end
    
    local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local current_depth = 1
    local end_idx = track_idx
    local total_tracks = r.CountTracks(0)
    
    while current_depth > 0 and end_idx < total_tracks - 1 do
        end_idx = end_idx + 1
        local child_track = r.GetTrack(0, end_idx)
        if not child_track then break end
        
        local child_depth = r.GetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH")
        current_depth = current_depth + child_depth
    end
    
    return track_idx, end_idx
end

function GetMasterTrackColor()
    local master = r.GetMasterTrack(0)
    local color = r.GetTrackColor(master)
    
    if color == 0 and settings.use_custom_master_color then
        return settings.master_native_color
    end
    
    return color
end

local function GetTimeSelScriptPath()
    local resource_path = r.GetResourcePath()
    local sep = package.config:sub(1,1)
    return resource_path .. sep .. "Scripts" .. sep .. "TK Scripts" .. sep .. "Tools" .. sep .. "TK_time selection loop color.lua"
end

local cached_timesel_cmd_id = nil
local function GetTimeSelCommandID()
    if cached_timesel_cmd_id then return cached_timesel_cmd_id end
    local main_script_path = GetTimeSelScriptPath()
    local file = io.open(main_script_path, "r")
    if file then
        file:close()
        cached_timesel_cmd_id = r.AddRemoveReaScript(true, 0, main_script_path, true)
        return cached_timesel_cmd_id
    end
    return nil
end

local function IsWindowsOS()
    return package.config:sub(1,1) == '\\'
end

local cached_is_windows = nil
local function ProcessTimeSelColor(color)
    if cached_is_windows == nil then cached_is_windows = IsWindowsOS() end
    if cached_is_windows then
        local rv = (color >> 16) & 0xFF
        local g = (color >> 8) & 0xFF
        local b = color & 0xFF
        return (b << 16) | (g << 8) | rv
    end
    return color
end

local function GetTimeSelSettings()
    local loop_color = tonumber(r.GetExtState("TK_time selection loop color", "loop_color")) or r.ColorToNative(0, 0, 255)
    local default_color = tonumber(r.GetExtState("TK_time selection loop color", "default_color")) or r.ColorToNative(255, 255, 255)
    local midi_color = tonumber(r.GetExtState("TK_time selection loop color", "midi_color")) or r.ColorToNative(255, 0, 0)
    local only_loop = r.GetExtState("TK_time selection loop color", "only_loop") == "1"
    local only_arrange = r.GetExtState("TK_time selection loop color", "only_arrange") == "1"
    local enable_midi = r.GetExtState("TK_time selection loop color", "enable_midi") == "1"
    local disco_mode = r.GetExtState("TK_time selection loop color", "disco_mode") == "1"
    return loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi, disco_mode
end

local function SaveTimeSelSettings(loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi, disco_mode)
    r.SetExtState("TK_time selection loop color", "loop_color", tostring(loop_color), true)
    r.SetExtState("TK_time selection loop color", "default_color", tostring(default_color), true)
    r.SetExtState("TK_time selection loop color", "midi_color", tostring(midi_color), true)
    r.SetExtState("TK_time selection loop color", "only_loop", only_loop and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "only_arrange", only_arrange and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "enable_midi", enable_midi and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "disco_mode", disco_mode and "1" or "0", true)
end

local track_visibility_cache = nil
local track_visibility_cache_count = -1

local function InvalidateTrackVisibilityCache()
    track_visibility_cache = nil
    track_visibility_cache_count = -1
end

local function GetTrackVisibilityData()
    local track_count = r.CountTracks(0)
    if track_visibility_cache and track_visibility_cache_count == track_count then
        return track_visibility_cache
    end
    
    local data = {}
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        local _, track_name = r.GetTrackName(track)
        local depth = 0
        local parent = r.GetParentTrack(track)
        while parent do
            depth = depth + 1
            parent = r.GetParentTrack(parent)
        end
        
        local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
        local is_child = depth > 0 and not is_folder
        
        data[i] = {
            track = track,
            name = track_name,
            depth = depth,
            is_folder = is_folder,
            is_child = is_child
        }
    end
    
    track_visibility_cache = data
    track_visibility_cache_count = track_count
    return data
end

function ShowSettingsWindow()
    if not settings_visible then return end
    
    -- Use Sexan's positioning
    local _, DPI_RPR = r.get_config_var_string("uiscale")
    local window_x = LEFT + (RIGHT - LEFT - 520) / 2  
    local window_y = TOP + (BOT - TOP - 520) / 2      
    
    r.ImGui_SetNextWindowPos(ctx, window_x, window_y, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSize(ctx, 520, 565)
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 8.0)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x111111FF) 
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x333333FF)        
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x444444FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x555555FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x999999FF)     
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xAAAAAAFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0x999999FF)      
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x333333FF)         
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x444444FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x555555FF)   
    r.ImGui_PushFont(ctx, settings_font)
    local visible, open = r.ImGui_Begin(ctx, 'Track Names Settings', true, settings_flags)
    
    if visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF) 
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "ARRANGE READECORATOR")
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF)
        r.ImGui_Text(ctx, "v" .. SCRIPT_VERSION)
        r.ImGui_PopStyleColor(ctx)
        
        local window_width = r.ImGui_GetWindowWidth(ctx)
        local padding = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_WindowPadding())
        local item_spacing = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
        local content_width = window_width - (padding * 2)
        local column_width = content_width / 4
        local slider_width = column_width - item_spacing
        local col2 = column_width + 8
        local col3 = column_width * 2
        local col4 = col3 + slider_width + item_spacing

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 25)
        r.ImGui_SetCursorPosY(ctx, 6)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
        
        if r.ImGui_Button(ctx, "##close", 14, 14) then
            SaveSettings()
            r.SetExtState("TK_TRACKNAMES", "settings_visible", "0", false)
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)

        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Tab(), 0x404040FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabHovered(), 0xFF5555FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TabSelected(), 0xFF0000FF)
        
        if r.ImGui_BeginTabBar(ctx, "SettingsTabs") then
            if r.ImGui_BeginTabItem(ctx, "Labels") then
                settings_tab = 1
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Colors") then
                settings_tab = 2
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Grid & BG") then
                settings_tab = 3
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Icons") then
                settings_tab = 4
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Track Visibility") then
                settings_tab = 5
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Time Selection") then
                settings_tab = 6
                r.ImGui_EndTabItem(ctx)
            end
            r.ImGui_EndTabBar(ctx)
        end
        
        r.ImGui_PopStyleColor(ctx, 3)
        
        r.ImGui_Separator(ctx)

        if settings_tab == 1 then
        -- ═══════════════════════════════════════════════════════════════════
        -- LABELS TAB - tekst, fonts, posities, lengtes, nummers, visibility
        -- ═══════════════════════════════════════════════════════════════════
        local changed
        
        r.ImGui_Text(ctx, "Label Visibility:")
        if r.ImGui_RadioButton(ctx, "Parent", settings.show_parent_tracks) then
            settings.show_parent_tracks = not settings.show_parent_tracks
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width)
        
        if r.ImGui_RadioButton(ctx, "Child", settings.show_child_tracks) then
            settings.show_child_tracks = not settings.show_child_tracks
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        
        if r.ImGui_RadioButton(ctx, "Normal", settings.show_normal_tracks) then
            settings.show_normal_tracks = not settings.show_normal_tracks
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width * 3)
        
        if r.ImGui_RadioButton(ctx, "Env Names", settings.show_envelope_names) then
            settings.show_envelope_names = not settings.show_envelope_names
        end
        
        if r.ImGui_RadioButton(ctx, "First FX", settings.show_first_fx) then
            settings.show_first_fx = not settings.show_first_fx
        end
        r.ImGui_SameLine(ctx, column_width)
        if r.ImGui_RadioButton(ctx, "Info Line", settings.show_info_line) then
            settings.show_info_line = not settings.show_info_line
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_RadioButton(ctx, "Track #", settings.show_track_numbers) then
            settings.show_track_numbers = not settings.show_track_numbers
        end
        r.ImGui_BeginDisabled(ctx, not settings.show_track_numbers)
        r.ImGui_SameLine(ctx, column_width * 3)
        r.ImGui_SetNextItemWidth(ctx, 90)
        if r.ImGui_BeginCombo(ctx, "##Number Style", 
            settings.track_number_style == 1 and " Before Name" or
            settings.track_number_style == 2 and " After Name" or
            "Above Name") then
            if r.ImGui_Selectable(ctx, " Before Name", settings.track_number_style == 1) then
                settings.track_number_style = 1
            end
            if r.ImGui_Selectable(ctx, " After Name", settings.track_number_style == 2) then
                settings.track_number_style = 2
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_EndDisabled(ctx)
        
        if r.ImGui_RadioButton(ctx, "Inherit parent", settings.show_parent_label) then
            settings.show_parent_label = not settings.show_parent_label
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width)
        if r.ImGui_RadioButton(ctx, "Hide selected", settings.text_hover_hide) then
            settings.text_hover_hide = not settings.text_hover_hide
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_RadioButton(ctx, "Hide on hover", settings.text_hover_enabled) then
            settings.text_hover_enabled = not settings.text_hover_enabled
        end
        
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_Text(ctx, "Label BG:")

        if r.ImGui_RadioButton(ctx, "Show Label BG", settings.show_label) then
            settings.show_label = not settings.show_label
        end

        if settings.show_label then
            r.ImGui_SetNextItemWidth(ctx, slider_width)
            changed, settings.label_alpha = r.ImGui_SliderDouble(ctx, "##LabelOpacity", settings.label_alpha, 0.0, 1.0)
            r.ImGui_SameLine(ctx, col2)
            r.ImGui_Text(ctx, "Opacity")
            r.ImGui_SameLine(ctx, col3)
            r.ImGui_SetNextItemWidth(ctx, slider_width)
            if r.ImGui_BeginCombo(ctx, "##LabelColor", color_modes[settings.label_color_mode]) then
                for i, color_name in ipairs(color_modes) do
                    if r.ImGui_Selectable(ctx, color_name, settings.label_color_mode == i) then
                        settings.label_color_mode = i
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_SameLine(ctx, col4)
            r.ImGui_Text(ctx, "Color")
            
            r.ImGui_SetNextItemWidth(ctx, slider_width)
            changed, settings.label_height_padding = r.ImGui_SliderInt(ctx, "##LabelHeight", settings.label_height_padding, 0, 10)
            r.ImGui_SameLine(ctx, col2)
            r.ImGui_Text(ctx, "Height")
        end
        
        if r.ImGui_RadioButton(ctx, "Border", settings.label_border) then
            settings.label_border = not settings.label_border
        end
        r.ImGui_BeginDisabled(ctx, not settings.label_border)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.label_border_thickness = r.ImGui_SliderDouble(ctx, "##LabelBorderThickness", settings.label_border_thickness, 0.5, 4.0)
        r.ImGui_SameLine(ctx, col2)
        r.ImGui_Text(ctx, "Thickness")
        r.ImGui_SameLine(ctx, col3)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.label_border_opacity = r.ImGui_SliderDouble(ctx, "##LabelBorderOpacity", settings.label_border_opacity, 0.0, 1.0)
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_Text(ctx, "Opacity")
        r.ImGui_EndDisabled(ctx)
        
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_Text(ctx, "Label Text:")
        
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        if r.ImGui_BeginCombo(ctx, "##Font", fonts[settings.selected_font]) then
            for i, font_name in ipairs(fonts) do
                if r.ImGui_Selectable(ctx, font_name, settings.selected_font == i) then
                    settings.selected_font = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx, col2)
        r.ImGui_Text(ctx, "Font")
        r.ImGui_SameLine(ctx, col3)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        if r.ImGui_BeginCombo(ctx, "##Size", tostring(settings.text_size)) then
            for _, size in ipairs(text_sizes) do
                if r.ImGui_Selectable(ctx, tostring(size), settings.text_size == size) then
                    settings.text_size = size
                    needs_font_update = true
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_Text(ctx, "Size")
        
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        if r.ImGui_BeginCombo(ctx, "##Color", color_modes[settings.color_mode]) then
            for i, color_name in ipairs(color_modes) do
                if r.ImGui_Selectable(ctx, color_name, settings.color_mode == i) then
                    settings.color_mode = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx, col2)
        r.ImGui_Text(ctx, "Color")
        r.ImGui_SameLine(ctx, col3)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.text_opacity = r.ImGui_SliderDouble(ctx, "##TextOpacity", settings.text_opacity, 0.0, 1.0)
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_Text(ctx, "Opacity")
        
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.envelope_text_opacity = r.ImGui_SliderDouble(ctx, "##EnvOpacity", settings.envelope_text_opacity, 0.0, 1.0)
        r.ImGui_SameLine(ctx, col2)
        r.ImGui_Text(ctx, "Env Opacity")

        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        
        r.ImGui_Text(ctx, "Name length:")
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_SetNextItemWidth(ctx, 140)
        if r.ImGui_BeginCombo(ctx, "##Track name length", 
            settings.track_name_length == 1 and " Full length" or
            settings.track_name_length == 2 and " Max 16 chars" or 
            settings.track_name_length == 3 and " Max 32 chars" or " Fixed length") then
            if r.ImGui_Selectable(ctx, " Full length", settings.track_name_length == 1) then
                settings.track_name_length = 1
            end
            if r.ImGui_Selectable(ctx, " Max 16 chars", settings.track_name_length == 2) then
                settings.track_name_length = 2
            end
            if r.ImGui_Selectable(ctx, " Max 32 chars", settings.track_name_length == 3) then
                settings.track_name_length = 3
            end
            if r.ImGui_Selectable(ctx, " Fixed length", settings.track_name_length == 4) then
                settings.track_name_length = 4
            end
            r.ImGui_EndCombo(ctx)
        end
        if settings.track_name_length == 4 then
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 80)  
            local changed, new_length = r.ImGui_InputInt(ctx, "##FixedLength", settings.fixed_label_length)
            if changed then
                settings.fixed_label_length = math.max(1, math.min(100, new_length)) 
            end
        end
        
        r.ImGui_Text(ctx, "FX length:")
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_SetNextItemWidth(ctx, 140)
        if r.ImGui_BeginCombo(ctx, "##FX name length", 
            settings.fx_name_length == 1 and " Full length" or
            settings.fx_name_length == 2 and " Max 16 chars" or 
            settings.fx_name_length == 3 and " Max 32 chars" or " Fixed length") then
            if r.ImGui_Selectable(ctx, " Full length", settings.fx_name_length == 1) then
                settings.fx_name_length = 1
            end
            if r.ImGui_Selectable(ctx, " Max 16 chars", settings.fx_name_length == 2) then
                settings.fx_name_length = 2
            end
            if r.ImGui_Selectable(ctx, " Max 32 chars", settings.fx_name_length == 3) then
                settings.fx_name_length = 3
            end
            if r.ImGui_Selectable(ctx, " Fixed length", settings.fx_name_length == 4) then
                settings.fx_name_length = 4
            end
            r.ImGui_EndCombo(ctx)
        end
        if settings.fx_name_length == 4 then
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 80)
            local changed, new_fx_length = r.ImGui_InputInt(ctx, "##FixedFXLength", settings.fx_fixed_label_length)
            if changed then
                settings.fx_fixed_label_length = math.max(1, math.min(100, new_fx_length))
            end
        end
        
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_Text(ctx, "Label Positioning:")
        
        if r.ImGui_RadioButton(ctx, "Center", settings.text_centered) then
            settings.text_centered = not settings.text_centered
            settings.auto_center = settings.text_centered
            if settings.text_centered then
                settings.right_align = false
            end
        end
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_BeginDisabled(ctx, settings.text_centered)
        if r.ImGui_RadioButton(ctx, "Right align", settings.right_align) then
            settings.right_align = not settings.right_align
        end
        r.ImGui_EndDisabled(ctx)
        
        r.ImGui_BeginDisabled(ctx, settings.text_centered)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.horizontal_offset = r.ImGui_SliderInt(ctx, "##HOffset", settings.horizontal_offset, 0, RIGHT - LEFT)
        r.ImGui_EndDisabled(ctx)
        r.ImGui_SameLine(ctx, col2)
        r.ImGui_Text(ctx, "H Offset")
        r.ImGui_SameLine(ctx, col3)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.vertical_offset = r.ImGui_SliderInt(ctx, "##VOffset", settings.vertical_offset, -50, 50)
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_Text(ctx, "V Offset")

        elseif settings_tab == 2 then
        -- ═══════════════════════════════════════════════════════════════════
        -- COLORS TAB - track kleuren, gradients, borders, master
        -- ═══════════════════════════════════════════════════════════════════
        local changed
        local Slider_Collumn_2 = 270
        r.ImGui_PushItemWidth(ctx, 140)
        
        -- Rij 1: Parent Color, Child Color, Normal Color, Env Color
        if r.ImGui_RadioButton(ctx, "Parent Color", settings.show_parent_colors) then
            settings.show_parent_colors = not settings.show_parent_colors
            needs_font_update = CheckTrackColorUpdate()
        end
        r.ImGui_SameLine(ctx, column_width)
        if r.ImGui_RadioButton(ctx, "Child Color", settings.show_child_colors) then
            settings.show_child_colors = not settings.show_child_colors
            needs_font_update = CheckTrackColorUpdate()
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_RadioButton(ctx, "Normal Color", settings.show_normal_colors) then
            settings.show_normal_colors = not settings.show_normal_colors
            needs_font_update = CheckTrackColorUpdate()
        end
        r.ImGui_SameLine(ctx, column_width * 3)
        if r.ImGui_RadioButton(ctx, "Env Color", settings.show_envelope_colors) then
            settings.show_envelope_colors = not settings.show_envelope_colors
        end
        
        -- Rij 2: Dark Parent, Dark Nested, Inherit, Deep Inherit
        if r.ImGui_RadioButton(ctx, "Dark Parent", settings.darker_parent_tracks) then
            settings.darker_parent_tracks = not settings.darker_parent_tracks
        end
        r.ImGui_SameLine(ctx, column_width)
        if r.ImGui_RadioButton(ctx, "Dark Nested", settings.nested_parents_darker) then
            settings.nested_parents_darker = not settings.nested_parents_darker
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_RadioButton(ctx, "Inherit", settings.inherit_parent_color) then
            settings.inherit_parent_color = not settings.inherit_parent_color
            if settings.inherit_parent_color then
                settings.deep_inherit_color = false
            end
        end
        r.ImGui_SameLine(ctx, column_width * 3)
        if r.ImGui_RadioButton(ctx, "Deep Inherit", settings.deep_inherit_color) then
            settings.deep_inherit_color = not settings.deep_inherit_color
            if settings.deep_inherit_color then
                settings.inherit_parent_color = false
            end
        end
        
        -- Rij 3: Gradual, Master Color + ColorPicker, Master Grad, Rec Color
        if r.ImGui_RadioButton(ctx, "Gradual", settings.color_gradient_enabled) then
            settings.color_gradient_enabled = not settings.color_gradient_enabled
        end
        r.ImGui_SameLine(ctx, column_width)
        if r.ImGui_RadioButton(ctx, "Master Color", settings.use_custom_master_color) then
            settings.use_custom_master_color = not settings.use_custom_master_color
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_BeginDisabled(ctx, not settings.use_custom_master_color)
        if r.ImGui_ColorButton(ctx, "##MasterColor", settings.master_track_color) then
            r.ImGui_OpenPopup(ctx, "MasterColorPopup")
        end
        r.ImGui_EndDisabled(ctx)
        if r.ImGui_BeginPopup(ctx, "MasterColorPopup") then
            local changed, new_color = r.ImGui_ColorEdit4(ctx, "Master Color", settings.master_track_color)
            if changed then settings.master_track_color = new_color end
            r.ImGui_EndPopup(ctx)
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        r.ImGui_BeginDisabled(ctx, not settings.use_custom_master_color)
        if r.ImGui_RadioButton(ctx, "Master Gradual", settings.master_gradient_enabled) then
            settings.master_gradient_enabled = not settings.master_gradient_enabled
        end
        r.ImGui_EndDisabled(ctx)
        r.ImGui_SameLine(ctx, column_width * 3)
        if r.ImGui_RadioButton(ctx, "Rec Color", settings.show_record_color) then
            settings.show_record_color = not settings.show_record_color
        end
        
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        
        -- Rij 4: Track colors, dropdown, Gradient, dropdown
        if r.ImGui_RadioButton(ctx, "Track colors", settings.show_track_colors) then
            settings.show_track_colors = not settings.show_track_colors
            needs_font_update = true
        end
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        if r.ImGui_BeginCombo(ctx, "##Blend Mode", blend_modes[settings.blend_mode]) then
            for i, mode in ipairs(blend_modes) do
                if r.ImGui_Selectable(ctx, mode, settings.blend_mode == i) then
                    settings.blend_mode = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx, col3)
        if r.ImGui_RadioButton(ctx, "Gradient", settings.gradient_enabled) then
            settings.gradient_enabled = not settings.gradient_enabled
        end
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        if r.ImGui_BeginCombo(ctx, "##Gradient Direction", 
            settings.gradient_direction == 1 and " Horizontal" or " Vertical") then
            if r.ImGui_Selectable(ctx, " Horizontal", settings.gradient_direction == 1) then
                settings.gradient_direction = 1
            end
            if r.ImGui_Selectable(ctx, " Vertical", settings.gradient_direction == 2) then
                settings.gradient_direction = 2
            end
            r.ImGui_EndCombo(ctx)
        end
        
        -- Rij 5: F Border, dropdown, T Border, dropdown
        if r.ImGui_RadioButton(ctx, "Folder Border", settings.folder_border) then
            settings.folder_border = not settings.folder_border
        end
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_BeginDisabled(ctx, not settings.folder_border)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        if r.ImGui_BeginCombo(ctx, "##Folder Border Options", " Sel Borders") then
            local clicked, new_state = r.ImGui_Checkbox(ctx, "All Borders", 
                settings.folder_border_left and
                settings.folder_border_right and
                settings.folder_border_top and
                settings.folder_border_bottom)
            if clicked then
                settings.folder_border_left = new_state
                settings.folder_border_right = new_state
                settings.folder_border_top = new_state
                settings.folder_border_bottom = new_state
            end
            clicked, settings.folder_border_left = r.ImGui_Checkbox(ctx, "Left Border", settings.folder_border_left)
            clicked, settings.folder_border_right = r.ImGui_Checkbox(ctx, "Right Border", settings.folder_border_right)
            clicked, settings.folder_border_top = r.ImGui_Checkbox(ctx, "Top Border", settings.folder_border_top)
            clicked, settings.folder_border_bottom = r.ImGui_Checkbox(ctx, "Bottom Border", settings.folder_border_bottom)
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_EndDisabled(ctx)
        r.ImGui_SameLine(ctx, col3)
        if r.ImGui_RadioButton(ctx, "Track Border", settings.track_border) then
            settings.track_border = not settings.track_border
        end
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_BeginDisabled(ctx, not settings.track_border)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        if r.ImGui_BeginCombo(ctx, "##Track Border Options", " Sel Borders") then
            local clicked, new_state = r.ImGui_Checkbox(ctx, "All Borders",
                settings.track_border_left and
                settings.track_border_right and
                settings.track_border_top and
                settings.track_border_bottom)
            if clicked then
                settings.track_border_left = new_state
                settings.track_border_right = new_state
                settings.track_border_top = new_state
                settings.track_border_bottom = new_state
            end
            clicked, settings.track_border_left = r.ImGui_Checkbox(ctx, "Left Border", settings.track_border_left)
            clicked, settings.track_border_right = r.ImGui_Checkbox(ctx, "Right Border", settings.track_border_right)
            clicked, settings.track_border_top = r.ImGui_Checkbox(ctx, "Top Border", settings.track_border_top)
            clicked, settings.track_border_bottom = r.ImGui_Checkbox(ctx, "Bottom Border", settings.track_border_bottom)
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_EndDisabled(ctx)
        
        r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        local Slider_Collumn_2 = 270 
        r.ImGui_PushItemWidth(ctx, 140)
        if settings.show_track_colors then
            if not settings.gradient_enabled then    
                changed, settings.overlay_alpha = r.ImGui_SliderDouble(ctx, "Color Intensity", settings.overlay_alpha, 0.0, 1.0)
            end
            if settings.gradient_enabled then
                changed, settings.gradient_start_alpha = r.ImGui_SliderDouble(ctx, "Start Gradient", settings.gradient_start_alpha, 0.0, 1.0)
                if changed then UpdateGradientAlphaCache() end
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                changed, settings.gradient_end_alpha = r.ImGui_SliderDouble(ctx, "End Gradient", settings.gradient_end_alpha, 0.0, 1.0)
                if changed then UpdateGradientAlphaCache() end
            end
            
            if settings.darker_parent_tracks then
                changed, settings.parent_darkness = r.ImGui_SliderDouble(ctx, "Parent Darkness", settings.parent_darkness, 0.1, 1.0)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                changed, settings.darker_parent_opacity = r.ImGui_SliderDouble(ctx, "Parent Opacity", settings.darker_parent_opacity, 0.0, 1.0)
            end
            
            if (settings.folder_border and settings.show_parent_colors) or 
            (settings.track_border and settings.show_normal_colors) then    
                changed, settings.border_thickness = r.ImGui_SliderDouble(ctx, "Border Thickness", settings.border_thickness, 1, 20.0)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                changed, settings.border_opacity = r.ImGui_SliderDouble(ctx, "Border Opacity", settings.border_opacity, 0.0, 1.0)     
            end
            
            if settings.use_custom_master_color then
                if not settings.master_gradient_enabled then
                    changed, settings.master_overlay_alpha = r.ImGui_SliderDouble(ctx, "Master Intensity", settings.master_overlay_alpha, 0.0, 1.0)
                end
                if settings.master_gradient_enabled then
                    changed, settings.master_gradient_start_alpha = r.ImGui_SliderDouble(ctx, "Master Start", settings.master_gradient_start_alpha, 0.0, 1.0)
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                    changed, settings.master_gradient_end_alpha = r.ImGui_SliderDouble(ctx, "Master End", settings.master_gradient_end_alpha, 0.0, 1.0)
                end
            end
            
            if settings.show_envelope_colors then
                changed, settings.envelope_color_intensity = r.ImGui_SliderDouble(ctx, "Env Intensity", settings.envelope_color_intensity, 0.0, 1.0)
            end
        end
        
        r.ImGui_PopItemWidth(ctx)

        elseif settings_tab == 4 then
        -- ═══════════════════════════════════════════════════════════════════
        -- ICONS TAB - icon settings
        -- ═══════════════════════════════════════════════════════════════════
        local changed
        
        -- Rij 1: Show Icons, Clear Icons
        if r.ImGui_RadioButton(ctx, "Show Icons", settings.show_track_icons) then
            settings.show_track_icons = not settings.show_track_icons
        end
        r.ImGui_SameLine(ctx, col3)
        if r.ImGui_Button(ctx, "Clear Icons", slider_width) then
            for i = 0, r.CountSelectedTracks(0) - 1 do
                local track = r.GetSelectedTrack(0, i)
                track_icon_manager.ClearTrackIcon(track)
            end
        end
        
        -- Rij 2: Size slider + label, Spacing slider + label
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.icon_size = r.ImGui_SliderInt(ctx, "##IconSize", settings.icon_size, 12, 64)
        r.ImGui_SameLine(ctx, col2)
        r.ImGui_Text(ctx, "Size")
        r.ImGui_SameLine(ctx, col3)
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.icon_spacing = r.ImGui_SliderInt(ctx, "##IconSpacing", settings.icon_spacing, 0, 40)
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_Text(ctx, "Spacing")
        
        -- Rij 3: Opacity slider + label, Position radio buttons + label
        r.ImGui_SetNextItemWidth(ctx, slider_width)
        changed, settings.icon_opacity = r.ImGui_SliderDouble(ctx, "##IconOpacity", settings.icon_opacity, 0.0, 1.0)
        r.ImGui_SameLine(ctx, col2)
        r.ImGui_Text(ctx, "Opacity")
        r.ImGui_SameLine(ctx, col3)
        if r.ImGui_RadioButton(ctx, "Left", settings.icon_position == 1) then
            settings.icon_position = 1
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "Right", settings.icon_position == 2) then
            settings.icon_position = 2
        end
        r.ImGui_SameLine(ctx, col4)
        r.ImGui_Text(ctx, "Position")
        
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        
        -- Embedded Icon Browser
        -- Mode selection row
        if r.ImGui_RadioButton(ctx, "REAPER", track_icon_browser.browse_mode == "icons") then
            if track_icon_browser.browse_mode ~= "icons" then
                track_icon_browser.SetBrowseMode("icons")
            end
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "Custom", track_icon_browser.browse_mode == "images") then
            if track_icon_browser.browse_mode ~= "images" then
                track_icon_browser.SetBrowseMode("images", track_icon_browser.custom_image_folder)
            end
        end
        r.ImGui_SameLine(ctx, col3)
        r.ImGui_SetNextItemWidth(ctx, slider_width + column_width)
        local rv
        rv, track_icon_browser.search_text = r.ImGui_InputTextWithHint(ctx, "##IconSearch", "Search...", track_icon_browser.search_text)
        if rv then
            track_icon_browser.FilterIcons()
        end
        
        -- Scale/Folder selection row
        if track_icon_browser.browse_mode == "icons" then
            if r.ImGui_RadioButton(ctx, "100%", track_icon_browser.icon_scale == 100) then
                if track_icon_browser.icon_scale ~= 100 then
                    track_icon_browser.icon_scale = 100
                    track_icon_browser.ReloadIcons()
                end
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "150%", track_icon_browser.icon_scale == 150) then
                if track_icon_browser.icon_scale ~= 150 then
                    track_icon_browser.icon_scale = 150
                    track_icon_browser.ReloadIcons()
                end
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "200%", track_icon_browser.icon_scale == 200) then
                if track_icon_browser.icon_scale ~= 200 then
                    track_icon_browser.icon_scale = 200
                    track_icon_browser.ReloadIcons()
                end
            end
            r.ImGui_SameLine(ctx, col3)
            r.ImGui_Text(ctx, string.format("(%d icons)", #track_icon_browser.filtered_icons))
        else
            if r.ImGui_Button(ctx, "Select Folder", slider_width) then
                folder_browser_path = track_icon_browser.custom_image_folder ~= "" and track_icon_browser.custom_image_folder or ""
                folder_browser_open = true
                r.ImGui_OpenPopup(ctx, "TK FOLDER BROWSER##FolderBrowser")
            end
            
            local selected = DrawFolderBrowserPopup(ctx)
            if selected then
                track_icon_browser.custom_image_folder = selected
                track_icon_browser.SaveLastImageFolder()
                track_icon_browser.ReloadIcons()
            end
            
            r.ImGui_SameLine(ctx, col3)
            r.ImGui_Text(ctx, string.format("(%d icons)", #track_icon_browser.filtered_icons))
        end
        
        r.ImGui_Dummy(ctx, 0, 2)
        
        -- Load icons if not loaded
        if #track_icon_browser.icons == 0 then
            if track_icon_browser.browse_mode == "images" and track_icon_browser.custom_image_folder == "" then
                track_icon_browser.LoadLastImageFolder()
            end
            track_icon_browser.LoadIcons()
            track_icon_browser.FilterIcons()
        end
        
        -- Icon grid (fills remaining space before footer)
        local footer_height = 32
        local _, avail_height = r.ImGui_GetContentRegionAvail(ctx)
        local available_height = avail_height - footer_height - 8
        if available_height < 50 then available_height = 50 end
        
        if r.ImGui_BeginChild(ctx, "EmbeddedIconGrid", 0, available_height, 1) then
            local child_width = r.ImGui_GetContentRegionAvail(ctx)
            local icon_size = 32
            local icon_spacing = 4
            local columns = math.floor(child_width / (icon_size + icon_spacing))
            if columns < 1 then columns = 1 end
            
            local total_icons = #track_icon_browser.filtered_icons
            
            for idx, icon in ipairs(track_icon_browser.filtered_icons) do
                if idx > 1 and ((idx - 1) % columns) ~= 0 then
                    r.ImGui_SameLine(ctx)
                end
                
                local has_image = track_icon_browser.image_cache[icon.name] and 
                                r.ImGui_ValidatePtr(track_icon_browser.image_cache[icon.name], 'ImGui_Image*')
                
                if has_image then
                    local uv_u2 = (track_icon_browser.browse_mode == "icons") and 0.33 or 1.0
                    
                    if r.ImGui_ImageButton(ctx, "##embicon" .. idx, track_icon_browser.image_cache[icon.name],
                        icon_size, icon_size, 0, 0, uv_u2, 1) then
                        -- Assign icon to selected tracks
                        for i = 0, r.CountSelectedTracks(0) - 1 do
                            local track = r.GetSelectedTrack(0, i)
                            if track then
                                track_icon_manager.SetTrackIcon(track, icon.path)
                            end
                        end
                    end
                else
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x404040FF)
                    if r.ImGui_Button(ctx, "##embicon" .. idx, icon_size, icon_size) then
                        for i = 0, r.CountSelectedTracks(0) - 1 do
                            local track = r.GetSelectedTrack(0, i)
                            if track then
                                track_icon_manager.SetTrackIcon(track, icon.path)
                            end
                        end
                    end
                    r.ImGui_PopStyleColor(ctx)
                    
                    if r.ImGui_IsItemVisible(ctx) then
                        local ok, img = pcall(r.ImGui_CreateImage, icon.path)
                        if ok and img then
                            track_icon_browser.image_cache[icon.name] = img
                        end
                    end
                end
                
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_BeginTooltip(ctx)
                    r.ImGui_Text(ctx, icon.name)
                    r.ImGui_EndTooltip(ctx)
                end
            end
            
            r.ImGui_EndChild(ctx)
        end

        elseif settings_tab == 3 then
        -- ═══════════════════════════════════════════════════════════════════
        -- GRID & BG TAB - custom colors grid/background
        -- ═══════════════════════════════════════════════════════════════════
        local changed
        local Slider_Collumn_2 = 270
        r.ImGui_PushItemWidth(ctx, 140)
        
        if r.ImGui_Button(ctx, settings.custom_colors_enabled and "Disable Custom Colors" or "Enable Custom Colors", 180) then
            reaper.Undo_BeginBlock()
            ToggleColors()
            reaper.Undo_EndBlock("Toggle Custom Grid and Background Colors", -1)
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        
        if settings.custom_colors_enabled then
            r.ImGui_Text(ctx, "Grid Settings:")
            r.ImGui_BeginDisabled(ctx, not settings.grid_color_enabled)
            r.ImGui_SetNextItemWidth(ctx, 140)
            local changed_grid, new_grid = r.ImGui_SliderDouble(ctx, "Grid Color", settings.grid_color, 0.0, 1.0)
            if changed_grid then settings.grid_color = new_grid end
            r.ImGui_EndDisabled(ctx)
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Grid##toggle", settings.grid_color_enabled) then
                settings.grid_color_enabled = not settings.grid_color_enabled
                if not settings.grid_color_enabled then
                    r.SetThemeColor("col_gridlines", -1, 0)
                    r.SetThemeColor("col_gridlines2", -1, 0)
                    r.SetThemeColor("col_gridlines3", -1, 0)
                    r.SetThemeColor("col_tr1_divline", -1, 0)
                    r.SetThemeColor("col_tr2_divline", -1, 0)
                    r.UpdateArrange()
                else
                    UpdateGridColors()
                end
            end
            
            if changed_grid and settings.grid_color_enabled then
                UpdateGridColors()
            end
            
            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 2)
            r.ImGui_Text(ctx, "Background Settings:")
            
            r.ImGui_BeginDisabled(ctx, not settings.bg_brightness_enabled)
            r.ImGui_SetNextItemWidth(ctx, 140)
            local changed_bg, new_bg = r.ImGui_SliderDouble(ctx, "Bg Brightness", settings.bg_brightness, 0.0, 1.0)
            if changed_bg then settings.bg_brightness = new_bg end
            r.ImGui_EndDisabled(ctx)
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "BG##toggle", settings.bg_brightness_enabled) then
                settings.bg_brightness_enabled = not settings.bg_brightness_enabled
                if not settings.bg_brightness_enabled then
                    r.SetThemeColor("col_arrangebg", -1, 0)
                    r.UpdateArrange()
                else
                    UpdateArrangeBG()
                end
            end
            
            if changed_bg and settings.bg_brightness_enabled then
                UpdateArrangeBG()
            end
            
            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 2)
            r.ImGui_Text(ctx, "Track Background Colors:")
            
            local changed_bg_tr1, new_bg_tr1 = r.ImGui_SliderDouble(ctx, "Track (odd) ", settings.bg_brightness_tr1, 0.0, 1.0)
            if changed_bg_tr1 then settings.bg_brightness_tr1 = new_bg_tr1 end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            local changed_sel_tr1, new_sel_tr1 = r.ImGui_SliderDouble(ctx, "Sel Track (odd)", settings.sel_brightness_tr1, 0.0, 1.0)
            if changed_sel_tr1 then settings.sel_brightness_tr1 = new_sel_tr1 end
            
            local changed_bg_tr2, new_bg_tr2 = r.ImGui_SliderDouble(ctx, "Track (even) ", settings.bg_brightness_tr2, 0.0, 1.0)
            if changed_bg_tr2 then settings.bg_brightness_tr2 = new_bg_tr2 end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            local changed_sel_tr2, new_sel_tr2 = r.ImGui_SliderDouble(ctx, "Sel Track (even)", settings.sel_brightness_tr2, 0.0, 1.0)
            if changed_sel_tr2 then settings.sel_brightness_tr2 = new_sel_tr2 end
            
            if changed_bg_tr1 or changed_bg_tr2 or changed_sel_tr1 or changed_sel_tr2 then
                UpdateTrackColors()
            end
        else
            r.ImGui_TextWrapped(ctx, "Custom colors are disabled. Click the button above to enable custom grid and background colors.")
        end
        
        r.ImGui_Dummy(ctx, 0, 8)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Text(ctx, "Overlay Grid:")
        
        if r.ImGui_Checkbox(ctx, "Show Overlay Grid", settings.overlay_grid_enabled) then
            settings.overlay_grid_enabled = not settings.overlay_grid_enabled
        end
        
        r.ImGui_BeginDisabled(ctx, not settings.overlay_grid_enabled)
        
        if r.ImGui_Checkbox(ctx, "Vertical", settings.overlay_grid_vertical) then
            settings.overlay_grid_vertical = not settings.overlay_grid_vertical
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, 120)
        if r.ImGui_Checkbox(ctx, "Horizontal", settings.overlay_grid_horizontal) then
            settings.overlay_grid_horizontal = not settings.overlay_grid_horizontal
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
        if r.ImGui_Checkbox(ctx, "Avoid Items", settings.overlay_grid_avoid_items) then
            settings.overlay_grid_avoid_items = not settings.overlay_grid_avoid_items
        end
        
        local grid_divisions = { "Adaptive", "1 (Beat)", "1/2", "1/4", "1/8", "1/16", "1/32" }
        local grid_div_values = { 0, 1, 2, 4, 8, 16, 32 }
        local current_div_idx = 2
        for i, v in ipairs(grid_div_values) do
            if settings.overlay_grid_division == v then current_div_idx = i break end
        end
        r.ImGui_SetNextItemWidth(ctx, 140)
        if r.ImGui_BeginCombo(ctx, "Grid Division", grid_divisions[current_div_idx]) then
            for i, label in ipairs(grid_divisions) do
                if r.ImGui_Selectable(ctx, label, i == current_div_idx) then
                    settings.overlay_grid_division = grid_div_values[i]
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
        r.ImGui_SetNextItemWidth(ctx, 140)
        local changed_opac, new_opac = r.ImGui_SliderDouble(ctx, "Grid Opacity", settings.overlay_grid_opacity, 0.0, 1.0)
        if changed_opac then settings.overlay_grid_opacity = new_opac end
        
        r.ImGui_SetNextItemWidth(ctx, 140)
        local changed_bar_thick, new_bar_thick = r.ImGui_SliderDouble(ctx, "Bar Thickness", settings.overlay_grid_bar_thickness, 0.5, 5.0)
        if changed_bar_thick then settings.overlay_grid_bar_thickness = new_bar_thick end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
        r.ImGui_SetNextItemWidth(ctx, 140)
        local changed_beat_thick, new_beat_thick = r.ImGui_SliderDouble(ctx, "Beat Thickness", settings.overlay_grid_beat_thickness, 0.5, 3.0)
        if changed_beat_thick then settings.overlay_grid_beat_thickness = new_beat_thick end
        
        r.ImGui_SetNextItemWidth(ctx, 140)
        local changed_grid_thick, new_grid_thick = r.ImGui_SliderDouble(ctx, "Grid Thickness", settings.overlay_grid_thickness, 0.5, 2.0)
        if changed_grid_thick then settings.overlay_grid_thickness = new_grid_thick end
        
        local btn_flags = r.ImGui_ColorEditFlags_NoAlpha()
        if r.ImGui_ColorButton(ctx, "##OverlayBarColor", settings.overlay_grid_bar_color, btn_flags) then
            r.ImGui_OpenPopup(ctx, "OverlayBarColorPopup")
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "Bar")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, 120)
        if r.ImGui_ColorButton(ctx, "##OverlayBeatColor", settings.overlay_grid_beat_color, btn_flags) then
            r.ImGui_OpenPopup(ctx, "OverlayBeatColorPopup")
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "Beat")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
        if r.ImGui_ColorButton(ctx, "##OverlayGridColor", settings.overlay_grid_color, btn_flags) then
            r.ImGui_OpenPopup(ctx, "OverlayGridColorPopup")
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "Grid")
        
        if r.ImGui_BeginPopup(ctx, "OverlayGridColorPopup") then
            local chg, new_color = r.ImGui_ColorPicker4(ctx, "##gridpick", settings.overlay_grid_color)
            if chg then settings.overlay_grid_color = new_color end
            r.ImGui_EndPopup(ctx)
        end
        if r.ImGui_BeginPopup(ctx, "OverlayBeatColorPopup") then
            local chg, new_color = r.ImGui_ColorPicker4(ctx, "##beatpick", settings.overlay_grid_beat_color)
            if chg then settings.overlay_grid_beat_color = new_color end
            r.ImGui_EndPopup(ctx)
        end
        if r.ImGui_BeginPopup(ctx, "OverlayBarColorPopup") then
            local chg, new_color = r.ImGui_ColorPicker4(ctx, "##barpick", settings.overlay_grid_bar_color)
            if chg then settings.overlay_grid_bar_color = new_color end
            r.ImGui_EndPopup(ctx)
        end
        
        r.ImGui_EndDisabled(ctx)
        
        r.ImGui_PopItemWidth(ctx)

        elseif settings_tab == 5 then
        -- ═══════════════════════════════════════════════════════════════════
        -- TRACK VISIBILITY TAB
        -- ═══════════════════════════════════════════════════════════════════
        
            local track_count = r.CountTracks(0)
            
            if settings.toplevel_mode and not settings.reversed_mode then
                local needs_update = false
                for i = 0, track_count - 1 do
                    local track = r.GetTrack(0, i)
                    local guid = GetTrackGUID(track)
                    local is_toplevel = IsToplevelOrClosedFolder(track)
                    local should_exclude = is_toplevel and not settings.dark_parent
                    local is_excluded = excluded_tracks[guid] ~= nil
                    if should_exclude ~= is_excluded then
                        needs_update = true
                        break
                    end
                end
                if needs_update then
                    excluded_tracks = {}
                    for i = 0, track_count - 1 do
                        local track = r.GetTrack(0, i)
                        if IsToplevelOrClosedFolder(track) and not settings.dark_parent then
                            excluded_tracks[GetTrackGUID(track)] = true
                        end
                    end
                    SaveExcludedTracks()
                end
            end
            
            local visible_count = 0
            for i = 0, track_count - 1 do
                local track = r.GetTrack(0, i)
                if not IsTrackExcluded(track) then
                    visible_count = visible_count + 1
                end
            end
            
            local col1 = 0
            local col2 = 104
            local col3 = 208
            local col4 = 312
            local col5 = 416
            local btn_width = 95
            
            local changed
            changed, settings.exclude_hide_label = r.ImGui_Checkbox(ctx, "Label", settings.exclude_hide_label)
            r.ImGui_SameLine(ctx, col2)
            changed, settings.exclude_hide_color = r.ImGui_Checkbox(ctx, "Color", settings.exclude_hide_color)
            r.ImGui_SameLine(ctx, col3)
            changed, settings.exclude_hide_border = r.ImGui_Checkbox(ctx, "Border", settings.exclude_hide_border)
            r.ImGui_SameLine(ctx, col4)
            if r.ImGui_Button(ctx, "Check All", btn_width) then
                excluded_tracks = {}
                settings.reversed_mode = false
                settings.toplevel_mode = false
                settings.folders_only_mode = false
                SaveExcludedTracks()
            end
            r.ImGui_SameLine(ctx, col5)
            if r.ImGui_Button(ctx, "Uncheck All", btn_width) then
                for i = 0, r.CountTracks(0) - 1 do
                    local track = r.GetTrack(0, i)
                    excluded_tracks[GetTrackGUID(track)] = true
                end
                settings.reversed_mode = false
                settings.toplevel_mode = false
                settings.folders_only_mode = false
                SaveExcludedTracks()
            end
            
            r.ImGui_Text(ctx, "Name:")
            r.ImGui_SameLine(ctx, 45)
            r.ImGui_SetNextItemWidth(ctx, col3 - 55)
            local changed
            changed, exclude_filter = r.ImGui_InputText(ctx, "##exclude_filter", exclude_filter)
            r.ImGui_SameLine(ctx, col3)
            if r.ImGui_Button(ctx, "Check", btn_width) and exclude_filter ~= "" then
                local filter_lower = exclude_filter:lower()
                for i = 0, r.CountTracks(0) - 1 do
                    local track = r.GetTrack(0, i)
                    local _, track_name = r.GetTrackName(track)
                    if track_name:lower():find(filter_lower, 1, true) then
                        excluded_tracks[GetTrackGUID(track)] = nil
                    end
                end
                SaveExcludedTracks()
            end
            r.ImGui_SameLine(ctx, col4)
            if r.ImGui_Button(ctx, "Uncheck", btn_width) and exclude_filter ~= "" then
                local filter_lower = exclude_filter:lower()
                for i = 0, r.CountTracks(0) - 1 do
                    local track = r.GetTrack(0, i)
                    local _, track_name = r.GetTrackName(track)
                    if track_name:lower():find(filter_lower, 1, true) then
                        excluded_tracks[GetTrackGUID(track)] = true
                    end
                end
                SaveExcludedTracks()
            end
            r.ImGui_SameLine(ctx, col5)
            if r.ImGui_Checkbox(ctx, "Reverse", settings.reversed_mode) then
                local new_excluded = {}
                for i = 0, r.CountTracks(0) - 1 do
                    local track = r.GetTrack(0, i)
                    local guid = GetTrackGUID(track)
                    if not excluded_tracks[guid] then
                        new_excluded[guid] = true
                    end
                end
                excluded_tracks = new_excluded
                settings.reversed_mode = not settings.reversed_mode
                SaveExcludedTracks()
            end
            
            if r.ImGui_Checkbox(ctx, "Folder", settings.folders_only_mode) then
                settings.folders_only_mode = not settings.folders_only_mode
                if settings.folders_only_mode then
                    settings.toplevel_mode = false
                    settings.reversed_mode = false
                    excluded_tracks = {}
                    for i = 0, r.CountTracks(0) - 1 do
                        local track = r.GetTrack(0, i)
                        local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                        if not is_folder then
                            excluded_tracks[GetTrackGUID(track)] = true
                        end
                    end
                    SaveExcludedTracks()
                else
                    settings.reversed_mode = false
                    excluded_tracks = {}
                    SaveExcludedTracks()
                end
            end
            r.ImGui_SameLine(ctx, col2)
            if r.ImGui_Checkbox(ctx, "Toplevel", settings.toplevel_mode) then
                settings.toplevel_mode = not settings.toplevel_mode
                if settings.toplevel_mode then
                    settings.folders_only_mode = false
                    settings.reversed_mode = false
                    excluded_tracks = {}
                    for i = 0, r.CountTracks(0) - 1 do
                        local track = r.GetTrack(0, i)
                        if IsToplevelOrClosedFolder(track) and not settings.dark_parent then
                            excluded_tracks[GetTrackGUID(track)] = true
                        end
                    end
                    SaveExcludedTracks()
                else
                    settings.reversed_mode = false
                    excluded_tracks = {}
                    SaveExcludedTracks()
                end
            end
            r.ImGui_SameLine(ctx, col3)
            local tcp_label = tcp_synced and "Show TCP" or "Hide TCP"
            if r.ImGui_Button(ctx, tcp_label, btn_width) then
                r.Undo_BeginBlock()
                r.PreventUIRefresh(1)
                if tcp_synced then
                    for i = 0, r.CountTracks(0) - 1 do
                        local track = r.GetTrack(0, i)
                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
                    end
                    tcp_synced = false
                else
                    for i = 0, r.CountTracks(0) - 1 do
                        local track = r.GetTrack(0, i)
                        local is_visible = not IsTrackExcluded(track)
                        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", is_visible and 1 or 0)
                    end
                    tcp_synced = true
                end
                r.TrackList_AdjustWindows(true)
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock(tcp_synced and "Hide unchecked in TCP" or "Show all in TCP", -1)
            end
            r.ImGui_SameLine(ctx, col4)
            local mcp_label = mcp_synced and "Show MCP" or "Hide MCP"
            if r.ImGui_Button(ctx, mcp_label, btn_width) then
                r.Undo_BeginBlock()
                r.PreventUIRefresh(1)
                if mcp_synced then
                    for i = 0, r.CountTracks(0) - 1 do
                        local track = r.GetTrack(0, i)
                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
                    end
                    mcp_synced = false
                else
                    for i = 0, r.CountTracks(0) - 1 do
                        local track = r.GetTrack(0, i)
                        local is_visible = not IsTrackExcluded(track)
                        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", is_visible and 1 or 0)
                    end
                    mcp_synced = true
                end
                r.TrackList_AdjustWindows(true)
                r.PreventUIRefresh(-1)
                r.Undo_EndBlock(mcp_synced and "Hide unchecked in MCP" or "Show all in MCP", -1)
            end
            r.ImGui_SameLine(ctx, col5)
            r.ImGui_SetNextItemWidth(ctx, btn_width)
            if r.ImGui_BeginCombo(ctx, "##TrackTypeFilter", "Filter") then
                local changed_filter = false
                local _, new_audio = r.ImGui_Checkbox(ctx, "Hide Audio", settings.filter_hide_audio)
                if new_audio ~= settings.filter_hide_audio then
                    settings.filter_hide_audio = new_audio
                    changed_filter = true
                end
                local _, new_midi = r.ImGui_Checkbox(ctx, "Hide MIDI", settings.filter_hide_midi)
                if new_midi ~= settings.filter_hide_midi then
                    settings.filter_hide_midi = new_midi
                    changed_filter = true
                end
                local _, new_bus = r.ImGui_Checkbox(ctx, "Hide Bus/Aux", settings.filter_hide_bus)
                if new_bus ~= settings.filter_hide_bus then
                    settings.filter_hide_bus = new_bus
                    changed_filter = true
                end
                local _, new_folder = r.ImGui_Checkbox(ctx, "Hide Folders", settings.filter_hide_folder)
                if new_folder ~= settings.filter_hide_folder then
                    settings.filter_hide_folder = new_folder
                    changed_filter = true
                end
                if changed_filter then
                    for i = 0, r.CountTracks(0) - 1 do
                        local track = r.GetTrack(0, i)
                        local guid = GetTrackGUID(track)
                        local num_items = r.CountTrackMediaItems(track)
                        local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                        local has_audio = false
                        local has_midi = false
                        for j = 0, num_items - 1 do
                            local item = r.GetTrackMediaItem(track, j)
                            local take = r.GetActiveTake(item)
                            if take then
                                if r.TakeIsMIDI(take) then
                                    has_midi = true
                                else
                                    has_audio = true
                                end
                            end
                        end
                        local is_bus = num_items == 0 and not is_folder and r.GetTrackNumSends(track, -1) > 0
                        
                        local dominated_by_audio = has_audio and not has_midi
                        local dominated_by_midi = has_midi and not has_audio
                        
                        local should_hide = false
                        if settings.filter_hide_audio and dominated_by_audio then should_hide = true end
                        if settings.filter_hide_midi and dominated_by_midi then should_hide = true end
                        if settings.filter_hide_bus and is_bus then should_hide = true end
                        if settings.filter_hide_folder and is_folder then should_hide = true end
                        
                        local dominated_by_audio_filter = dominated_by_audio and not settings.filter_hide_audio
                        local dominated_by_midi_filter = dominated_by_midi and not settings.filter_hide_midi
                        local is_bus_filter = is_bus and not settings.filter_hide_bus
                        local is_folder_filter = is_folder and not settings.filter_hide_folder
                        
                        local should_show = dominated_by_audio_filter or dominated_by_midi_filter or is_bus_filter or is_folder_filter
                        
                        if should_hide then
                            excluded_tracks[guid] = true
                        elseif should_show then
                            excluded_tracks[guid] = nil
                        end
                    end
                    SaveExcludedTracks()
                end
                r.ImGui_EndCombo(ctx)
            end
            
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 2)
            
            local footer_height = 32
            local _, avail_height = r.ImGui_GetContentRegionAvail(ctx)
            local list_height = avail_height - footer_height - 8
            
            r.ImGui_BeginChild(ctx, "TrackVisibilityList", 0, list_height, 1)
            
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local content_width = r.ImGui_GetContentRegionAvail(ctx)
            local indent_pixels = 20
            local line_height = r.ImGui_GetTextLineHeightWithSpacing(ctx)
            
            if not track_visibility_clipper or not r.ImGui_ValidatePtr(track_visibility_clipper, 'ImGui_ListClipper*') then
                track_visibility_clipper = r.ImGui_CreateListClipper(ctx)
            end
            r.ImGui_ListClipper_Begin(track_visibility_clipper, track_count)
            
            while r.ImGui_ListClipper_Step(track_visibility_clipper) do
                local display_start, display_end = r.ImGui_ListClipper_GetDisplayRange(track_visibility_clipper)
                for i = display_start, display_end - 1 do
                    local track = r.GetTrack(0, i)
                    if track then
                        local _, track_name = r.GetTrackName(track)
                        local depth = 0
                        local parent = r.GetParentTrack(track)
                        while parent do
                            depth = depth + 1
                            parent = r.GetParentTrack(parent)
                        end
                        
                        local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                        local is_child = depth > 0 and not is_folder
                        local folder_space = is_folder and "     " or ""
                        local child_indent = is_child and "          " or ""
                        local display_name = child_indent .. folder_space .. track_name
                        
                        local show_label = not IsTrackExcluded(track)
                
                local display_color = r.GetTrackColor(track)
                
                if settings.deep_inherit_color then
                    local current = track
                    local main_parent = nil
                    while r.GetParentTrack(current) do
                        current = r.GetParentTrack(current)
                        if not r.GetParentTrack(current) then
                            main_parent = current
                        end
                    end
                    if main_parent then
                        display_color = r.GetTrackColor(main_parent)
                    end
                elseif settings.inherit_parent_color then
                    local parent_track = r.GetParentTrack(track)
                    if parent_track then
                        display_color = r.GetTrackColor(parent_track)
                    end
                end
                
                local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
                local item_indent = is_child and indent_pixels or 0
                
                local has_color = display_color ~= 0
                local text_color = 0xFFFFFFFF
                local icon_color = 0xAAAAAAFF
                
                if has_color then
                    local b = (display_color >> 16) & 0xFF
                    local g = (display_color >> 8) & 0xFF
                    local rb = display_color & 0xFF
                    
                    local luminance = (0.299 * rb + 0.587 * g + 0.114 * b) / 255
                    text_color = luminance > 0.5 and 0x000000FF or 0xFFFFFFFF
                    icon_color = text_color
                    
                    local bg_color = (rb << 24) | (g << 16) | (b << 8) | 0xDD
                    
                    local bg_start_x = cursor_x + 20 + item_indent
                    r.ImGui_DrawList_AddRectFilled(draw_list, bg_start_x, cursor_y, cursor_x + content_width, cursor_y + line_height - 2, bg_color, 2)
                    
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                end
                
                r.ImGui_PushID(ctx, i)
                local changed, new_value = r.ImGui_Checkbox(ctx, display_name, show_label)
                if changed then
                    SetTrackExcluded(track, not new_value)
                end
                r.ImGui_PopID(ctx)
                
                if is_folder then
                    local icon_x = cursor_x + 24
                    local icon_y = cursor_y + 2
                    
                    r.ImGui_DrawList_AddRectFilled(draw_list, icon_x, icon_y + 3, icon_x + 12, icon_y + 11, icon_color, 1)
                    r.ImGui_DrawList_AddRectFilled(draw_list, icon_x, icon_y, icon_x + 6, icon_y + 4, icon_color, 1)
                end
                
                if has_color then
                    r.ImGui_PopStyleColor(ctx, 1)
                end
                    end
                end
            end
            
            local child_draw_list = r.ImGui_GetWindowDrawList(ctx)
            local child_pos_x, child_pos_y = r.ImGui_GetWindowPos(ctx)
            local child_size_x, child_size_y = r.ImGui_GetWindowSize(ctx)
            
            local count_text = string.format(" %d / %d ", visible_count, track_count)
            local text_width = r.ImGui_CalcTextSize(ctx, count_text)
            local box_padding = 6
            local box_width = text_width + box_padding * 2
            local box_height = 22
            local box_x = child_pos_x + child_size_x - box_width - 10
            local box_y = child_pos_y + child_size_y - box_height - 6
            
            r.ImGui_DrawList_AddRectFilled(child_draw_list, box_x, box_y, box_x + box_width, box_y + box_height, 0x1A1A1ACC, 4)
            r.ImGui_DrawList_AddRect(child_draw_list, box_x, box_y, box_x + box_width, box_y + box_height, 0x666666FF, 4, 0, 1)
            r.ImGui_DrawList_AddText(child_draw_list, box_x + box_padding, box_y + 4, 0xFFFFFFFF, count_text)
            
            r.ImGui_EndChild(ctx)
        
        elseif settings_tab == 6 then
        -- ═══════════════════════════════════════════════════════════════════
        -- TIME SELECTION TAB - time selection/loop color settings
        -- ═══════════════════════════════════════════════════════════════════
        
        local timesel_cmd_id = GetTimeSelCommandID()
        
        if not timesel_cmd_id then
            r.ImGui_TextColored(ctx, 0xFF6666FF, "TK_time selection loop color.lua not found!")
            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_TextWrapped(ctx, "Please install the script from:")
            r.ImGui_TextWrapped(ctx, "TK Scripts/Tools/TK_time selection loop color.lua")
            r.ImGui_Dummy(ctx, 0, 8)
            r.ImGui_TextWrapped(ctx, "This script allows you to change the time selection and loop colors dynamically.")
        else
            local is_enabled = r.GetToggleCommandState(timesel_cmd_id) == 1
            local loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi, disco_mode = GetTimeSelSettings()
            
            r.ImGui_PushItemWidth(ctx, 140)
            
            if r.ImGui_Button(ctx, is_enabled and "Disable Time Selection Colors" or "Enable Time Selection Colors", 220) then
                r.Main_OnCommand(timesel_cmd_id, 0)
            end
            
            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 4)
            
            r.ImGui_Text(ctx, "Loop Color")
            r.ImGui_SameLine(ctx, 120)
            local rv1, new_loop = r.ImGui_ColorEdit3(ctx, "##timesel_loop_color", ProcessTimeSelColor(loop_color))
            if rv1 then
                SaveTimeSelSettings(ProcessTimeSelColor(new_loop), default_color, midi_color, only_loop, only_arrange, enable_midi, disco_mode)
            end
            
            r.ImGui_Text(ctx, "Default Color")
            r.ImGui_SameLine(ctx, 120)
            local rv2, new_default = r.ImGui_ColorEdit3(ctx, "##timesel_default_color", ProcessTimeSelColor(default_color))
            if rv2 then
                SaveTimeSelSettings(loop_color, ProcessTimeSelColor(new_default), midi_color, only_loop, only_arrange, enable_midi, disco_mode)
            end
            
            r.ImGui_Text(ctx, "MIDI Color")
            r.ImGui_SameLine(ctx, 120)
            local rv3, new_midi = r.ImGui_ColorEdit3(ctx, "##timesel_midi_color", ProcessTimeSelColor(midi_color))
            if rv3 then
                SaveTimeSelSettings(loop_color, default_color, ProcessTimeSelColor(new_midi), only_loop, only_arrange, enable_midi, disco_mode)
            end
            
            r.ImGui_Dummy(ctx, 0, 4)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 4)
            
            local link_state = r.GetToggleCommandState(40621) == 1
            if r.ImGui_Checkbox(ctx, "Link loop points to time selection", link_state) then
                r.Main_OnCommand(40621, 0)
            end
            
            local new_only_loop = only_loop
            local new_only_arrange = only_arrange
            
            if r.ImGui_Checkbox(ctx, "Only loop color", only_loop) then
                new_only_loop = not only_loop
                if new_only_loop then new_only_arrange = false end
                SaveTimeSelSettings(loop_color, default_color, midi_color, new_only_loop, new_only_arrange, enable_midi, disco_mode)
            end
            
            if r.ImGui_Checkbox(ctx, "Only arrange color", only_arrange) then
                new_only_arrange = not only_arrange
                if new_only_arrange then new_only_loop = false end
                SaveTimeSelSettings(loop_color, default_color, midi_color, new_only_loop, new_only_arrange, enable_midi, disco_mode)
            end
            
            if r.ImGui_Checkbox(ctx, "Enable MIDI editor colors", enable_midi) then
                SaveTimeSelSettings(loop_color, default_color, midi_color, only_loop, only_arrange, not enable_midi, disco_mode)
            end
            
            if r.ImGui_Checkbox(ctx, "Disco mode", disco_mode) then
                SaveTimeSelSettings(loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi, not disco_mode)
            end
            
            r.ImGui_PopItemWidth(ctx)
        end
        
        end
        
        -- ═══════════════════════════════════════════════════════════════════
        -- FOOTER - presets, autosave, save/reset (altijd zichtbaar)
        -- ═══════════════════════════════════════════════════════════════════
        local footer_height = 32
        local window_height = r.ImGui_GetWindowHeight(ctx)
        
        r.ImGui_SetCursorPosY(ctx, window_height - footer_height)
        r.ImGui_Separator(ctx)
        
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x1A1A1AFF)
        r.ImGui_BeginChild(ctx, "Footer", 0, 0, 0)
        r.ImGui_PopStyleVar(ctx)
        
        local footer_btn_width = column_width - item_spacing
        
        if r.ImGui_Button(ctx, "Save Preset", footer_btn_width) then
            r.ImGui_OpenPopup(ctx, "Save Preset##popup")
        end
        r.ImGui_SameLine(ctx, column_width)
        local presets = GetPresetList()
        r.ImGui_SetNextItemWidth(ctx, footer_btn_width)
        if r.ImGui_BeginCombo(ctx, "##Load Preset", "Load Preset") then
            for _, preset_name in ipairs(presets) do
                local is_clicked = r.ImGui_Selectable(ctx, preset_name)
                if r.ImGui_BeginPopupContextItem(ctx) then
                    if r.ImGui_MenuItem(ctx, "Delete") then
                        os.remove(preset_path .. preset_name .. '.json')
                    end
                    r.ImGui_EndPopup(ctx)
                end
                if is_clicked then
                    LoadPreset(preset_name)
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_Button(ctx, "Reset", footer_btn_width) then
            ResetSettings()
        end
        
        r.ImGui_SameLine(ctx, column_width * 3)
        if r.ImGui_RadioButton(ctx, "Show button", settings.show_settings_button) then
            settings.show_settings_button = not settings.show_settings_button
        end
        
        if r.ImGui_BeginPopup(ctx, "Save Preset##popup") then
            r.ImGui_Text(ctx, "Enter preset name:")
            local changed, new_name = r.ImGui_InputText(ctx, "##preset_name", preset_name)
            if changed then preset_name = new_name end
            
            if r.ImGui_Button(ctx, "Save") then
                if preset_name ~= "" then
                    SavePreset(preset_name)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            end
            r.ImGui_EndPopup(ctx)
        end
        
        r.ImGui_EndChild(ctx)
        r.ImGui_PopStyleColor(ctx)
        
    end
    
    r.ImGui_End(ctx)
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 5)
    r.ImGui_PopStyleColor(ctx, 10)
end

function IsTrackVisible(track)
    local MIN_TRACK_HEIGHT = 10
    local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
    return track_height > MIN_TRACK_HEIGHT
end

-- Thanx Smandrap
local function IsRecording(track)
    if r.GetMediaTrackInfo_Value(track, "I_RECARM") == 0 then return false end
    if r.GetMediaTrackInfo_Value(track, "I_RECINPUT") < 0 then return false end
    if r.GetMediaTrackInfo_Value(track, "I_RECMODE") == 2 then return false end
    return true
end

function GetAllParentTracks(track)
    local parents = {}
    local current = track
    while true do
        local parent = r.GetParentTrack(current)
        if not parent then break end
        table.insert(parents, parent)
        current = parent
    end
    return parents
end

function TruncateTrackName(name, mode, fixed_len_override)
    if mode == 1 then
        return name 
    elseif mode == 2 and #name > 16 then
        return name:sub(1, 13) .. "..."
    elseif mode == 3 and #name > 32 then
        return name:sub(1, 29) .. "..."
    elseif mode == 4 then
    local fixed_length = fixed_len_override or settings.fixed_label_length
        local reference_string = string.rep("n", fixed_length)
        
        local target_width = 0
        local current_width = 0
        
        if ctx then
            target_width = r.ImGui_CalcTextSize(ctx, reference_string)
            current_width = r.ImGui_CalcTextSize(ctx, name)
        end
        
        if target_width == 0 or current_width == 0 then
            if #name > fixed_length then
                return name:sub(1, fixed_length)
            elseif #name < fixed_length then
                return name .. string.rep(" ", fixed_length - #name)
            else
                return name
            end
        end
        
        if current_width > target_width then
            local truncated = name
            local truncated_width = current_width
            local attempts = 0
            while truncated_width > target_width and #truncated > 1 and attempts < 100 do
                truncated = truncated:sub(1, #truncated - 1)
                truncated_width = r.ImGui_CalcTextSize(ctx, truncated)
                attempts = attempts + 1
            end
            return truncated
        elseif current_width < target_width then
            local padded = name
            local padded_width = current_width
            local attempts = 0
            while padded_width < target_width and attempts < 100 do
                padded = padded .. " "
                padded_width = r.ImGui_CalcTextSize(ctx, padded)
                attempts = attempts + 1
            end
            return padded
        else
            return name
        end
    end
    return name
end

function RenderTrackIcon(draw_list, track, track_y, track_height, text_x, text_width, vertical_offset, WY, is_pinned, pinned_tracks_height, keep_text_aligned)
    if not settings.show_track_icons then return text_x end
    
    local icon_path = track_icon_manager.GetTrackIcon(track)
    if not icon_path then return text_x end
    
    local icon_img = track_icon_manager.GetIconImage(icon_path)
    if not icon_img or not r.ImGui_ValidatePtr(icon_img, 'ImGui_Image*') then 
        return text_x 
    end
    
    local icon_size = settings.icon_size
    local icon_spacing = settings.icon_spacing
    
    local icon_y = WY + track_y + (track_height * 0.5) - (icon_size * 0.5) + vertical_offset
    
    if not is_pinned and icon_y < WY + pinned_tracks_height then 
        return text_x 
    end
    
    local icon_x
    local adjusted_text_x = text_x
    
    if settings.icon_position == 1 then 
        if keep_text_aligned then
            icon_x = text_x - icon_size - icon_spacing
        else
            icon_x = text_x
            adjusted_text_x = text_x + icon_size + icon_spacing
        end
    else 
        icon_x = text_x + text_width + icon_spacing
    end
    
    local uv0_x, uv0_y = 0, 0
    local uv1_x, uv1_y = icon_path:find("toolbar_icons") and 0.33 or 1, 1
    local tint_col = r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, settings.icon_opacity)
    
    r.ImGui_DrawList_AddImage(
        draw_list, icon_img,
        icon_x, icon_y,
        icon_x + icon_size, icon_y + icon_size,
        uv0_x, uv0_y, uv1_x, uv1_y,
        tint_col
    )
    
    return adjusted_text_x
end

function DrawTrackIcon(track, x, y)
    local retval, icon_data = r.GetTrackIcon(track)
    if retval > 0 and icon_data then
        local icon_texture = r.ImGui_CreateImage(icon_data)
        if icon_texture then
            r.ImGui_DrawList_AddImage(draw_list, icon_texture, x, y, x + 16, y + 16)
            r.ImGui_Image_Destroy(icon_texture)
        end
    end
end

function SetButtonState(set)
    local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
    reaper.SetToggleCommandState(sec, cmd, set or 0)
    reaper.RefreshToolbar2(sec, cmd)
end

function CheckNeedsUpdate()
    return not (settings.show_child_tracks or 
                settings.show_normal_tracks or
                settings.show_parent_tracks or 
                settings.show_parent_label)
end

function CheckTrackColorUpdate()
    return not (settings.show_parent_colors or 
                settings.show_child_colors or 
                settings.show_normal_colors)
end

function ResetRenderContext()
    ctx = r.ImGui_CreateContext('Track Names')
    r.ImGui_Attach(ctx, settings_font)
    for _, font in ipairs(font_objects) do
        r.ImGui_Attach(ctx, font)
    end
end

function RenderSolidOverlay(draw_list, track, track_y, track_height, color, window_y, pinned_height)
    local window_draw_list = r.ImGui_GetWindowDrawList(ctx)
    
    pinned_height = pinned_height or 0
    
    if pinned_height > 0 and track_y < pinned_height then
        if track_y + track_height <= pinned_height then
            return
        end
        local actual_y = window_y + pinned_height
        local actual_height = track_height - (pinned_height - track_y)
        
        r.ImGui_DrawList_AddRectFilled(
            window_draw_list,
            LEFT,
            actual_y,
            RIGHT - scroll_size,
            actual_y + actual_height,
            color
        )
    else
        r.ImGui_DrawList_AddRectFilled(
            window_draw_list,
            LEFT,
            window_y + track_y,
            RIGHT - scroll_size,
            window_y + track_y + track_height,
            color
        )
    end
    
    local track_env_cnt = r.CountTrackEnvelopes(track)
    if track_env_cnt > 0 and settings.show_envelope_colors and not settings.disable_all_color_overlays then
        local env_y = track_y + track_height
        local env_height = (r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale) - track_height
        local env_color = (color & 0xFFFFFF00) | ((settings.envelope_color_intensity * settings.overlay_alpha * 255)//1)
        
        if pinned_height > 0 and env_y < pinned_height then
            if env_y + env_height <= pinned_height then
                return
            end
            local actual_env_y = window_y + pinned_height
            local actual_env_height = env_height - (pinned_height - env_y)
            r.ImGui_DrawList_AddRectFilled(
                window_draw_list,
                LEFT,
                actual_env_y,
                RIGHT - scroll_size,
                actual_env_y + actual_env_height,
                env_color
            )
        else
            r.ImGui_DrawList_AddRectFilled(
                window_draw_list,
                LEFT,
                window_y + env_y,
                RIGHT - scroll_size,
                window_y + env_y + env_height,
                env_color
            )
        end
    end
end

function RenderGradientRect(draw_list, x1, y1, x2, y2, color, intensity)
    local alpha_start = intensity and (settings.gradient_start_alpha_cached * intensity)//1 or settings.gradient_start_alpha_cached
    local alpha_end = intensity and (settings.gradient_end_alpha_cached * intensity)//1 or settings.gradient_end_alpha_cached

    if settings.gradient_direction == 1 then
        r.ImGui_DrawList_AddRectFilledMultiColor(
            draw_list, x1, y1, x2, y2,
            (color & 0xFFFFFF00) | alpha_start,
            (color & 0xFFFFFF00) | alpha_end,
            (color & 0xFFFFFF00) | alpha_end,
            (color & 0xFFFFFF00) | alpha_start
        )
    else
        r.ImGui_DrawList_AddRectFilledMultiColor(
            draw_list, x1, y1, x2, y2,
            (color & 0xFFFFFF00) | alpha_start,
            (color & 0xFFFFFF00) | alpha_start,
            (color & 0xFFFFFF00) | alpha_end,
            (color & 0xFFFFFF00) | alpha_end
        )
    end
end
  
function RenderGradientOverlay(draw_list, track, track_y, track_height, color, window_y, is_parent, pinned_height)    
    local window_draw_list = r.ImGui_GetWindowDrawList(ctx)
    
    pinned_height = pinned_height or 0
    
    if pinned_height > 0 and track_y < pinned_height then
        if track_y + track_height <= pinned_height then
            return
        end
        local actual_y = window_y + pinned_height
        local actual_height = track_height - (pinned_height - track_y)
        
        if is_parent and settings.darker_parent_tracks and 
           (not r.GetParentTrack(track) or settings.nested_parents_darker) and
           not (settings.exclude_hide_color and IsTrackExcluded(track)) then
            r.ImGui_DrawList_AddRectFilled(
                window_draw_list,
                LEFT,
                actual_y,
                RIGHT - scroll_size,
                actual_y + actual_height,
                color
            )
        else
            RenderGradientRect(
                window_draw_list,
                LEFT,
                actual_y,
                RIGHT - scroll_size,
                actual_y + actual_height,
                color
            )
        end
    else
        if is_parent and settings.darker_parent_tracks and 
           (not r.GetParentTrack(track) or settings.nested_parents_darker) and
           not (settings.exclude_hide_color and IsTrackExcluded(track)) then
            r.ImGui_DrawList_AddRectFilled(
                window_draw_list,
                LEFT,
                window_y + track_y,
                RIGHT - scroll_size,
                window_y + track_y + track_height,
                color
            )
        else
            RenderGradientRect(
                window_draw_list,
                LEFT,
                window_y + track_y,
                RIGHT - scroll_size,
                window_y + track_y + track_height,
                color
            )
        end
    end
    
    local track_env_cnt = r.CountTrackEnvelopes(track)
    if track_env_cnt > 0 and settings.show_envelope_colors and not settings.disable_all_color_overlays then
        local env_y = track_y + track_height
        local env_height = (r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale) - track_height
        
        if pinned_height > 0 and env_y < pinned_height then
            if env_y + env_height <= pinned_height then
                return
            end
            local actual_env_y = window_y + pinned_height
            local actual_env_height = env_height - (pinned_height - env_y)
            RenderGradientRect(
                window_draw_list,
                LEFT,
                actual_env_y,
                RIGHT - scroll_size,
                actual_env_y + actual_env_height,
                color,
                settings.envelope_color_intensity
            )
        else
            RenderGradientRect(
                window_draw_list,
                LEFT,
                window_y + env_y,
                RIGHT - scroll_size,
                window_y + env_y + env_height,
                color,
                settings.envelope_color_intensity
            )
        end
    end
end

function DrawFolderBorderLine(draw_list,x1,y1,x2,y2,color,thickness)
    r.ImGui_DrawList_AddLine(draw_list,x1,y1,x2,y2,color,thickness)
end

function DrawTrackBorderLine(draw_list,x1,y1,x2,y2,color,thickness)
    r.ImGui_DrawList_AddLine(draw_list,x1, y1, x2, y2,color,thickness)
end

function DrawTrackBorders(draw_list, track, track_y, track_height, border_color, WY, is_pinned, pinned_tracks_height)
    is_pinned = is_pinned or false
    pinned_tracks_height = pinned_tracks_height or 0
    
    if pinned_tracks_height > 0 and not is_pinned and track_y < pinned_tracks_height then
        if track_y + track_height <= pinned_tracks_height then
            goto draw_envelope_borders
        end
        local actual_y = pinned_tracks_height
        local actual_height = track_height - (pinned_tracks_height - track_y)
        
        if settings.track_border_left then
            DrawTrackBorderLine(draw_list, LEFT + settings.border_thickness/2, WY + actual_y,
                LEFT + settings.border_thickness/2, WY + actual_y + actual_height,
                border_color, settings.border_thickness)
        end
        if settings.track_border_right then
            DrawTrackBorderLine(draw_list, RIGHT - scroll_size - settings.border_thickness/2, WY + actual_y,
                RIGHT - scroll_size - settings.border_thickness/2, WY + actual_y + actual_height,
                border_color, settings.border_thickness)
        end
        if settings.track_border_bottom then
            DrawTrackBorderLine(draw_list, LEFT, WY + track_y + track_height - settings.border_thickness/2,
                RIGHT - scroll_size, WY + track_y + track_height - settings.border_thickness/2,
                border_color, settings.border_thickness)
        end
    else
        if settings.track_border_left then
            DrawTrackBorderLine(draw_list, LEFT + settings.border_thickness/2, WY + track_y,
                LEFT + settings.border_thickness/2, WY + track_y + track_height,
                border_color, settings.border_thickness)
        end
        if settings.track_border_right then
            DrawTrackBorderLine(draw_list, RIGHT - scroll_size - settings.border_thickness/2, WY + track_y,
                RIGHT - scroll_size - settings.border_thickness/2, WY + track_y + track_height,
                border_color, settings.border_thickness)
        end
        if settings.track_border_top then
            DrawTrackBorderLine(draw_list, LEFT, WY + track_y + settings.border_thickness/2,
                RIGHT - scroll_size, WY + track_y + settings.border_thickness/2,
                border_color, settings.border_thickness)
        end
        if settings.track_border_bottom then
            DrawTrackBorderLine(draw_list, LEFT, WY + track_y + track_height - settings.border_thickness/2,
                RIGHT - scroll_size, WY + track_y + track_height - settings.border_thickness/2,
                border_color, settings.border_thickness)
        end
    end
    
    ::draw_envelope_borders::
    local track_env_cnt = r.CountTrackEnvelopes(track)
    if track_env_cnt > 0 then
        local env_y = track_y + track_height
        local env_height = (r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale) - track_height
        
        if pinned_tracks_height > 0 and not is_pinned and env_y < pinned_tracks_height then
            if env_y + env_height <= pinned_tracks_height then
                return 
            end
            local actual_env_y = pinned_tracks_height
            local actual_env_height = env_height - (pinned_tracks_height - env_y)
            
            if settings.track_border_left then
                DrawTrackBorderLine(draw_list, LEFT + settings.border_thickness/2, WY + actual_env_y,
                    LEFT + settings.border_thickness/2, WY + actual_env_y + actual_env_height,
                    border_color, settings.border_thickness)
            end
            if settings.track_border_right then
                DrawTrackBorderLine(draw_list, RIGHT - scroll_size - settings.border_thickness/2, WY + actual_env_y,
                    RIGHT - scroll_size - settings.border_thickness/2, WY + actual_env_y + actual_env_height,
                    border_color, settings.border_thickness)
            end
            if settings.track_border_bottom then
                DrawTrackBorderLine(draw_list, LEFT, WY + env_y + env_height - settings.border_thickness/2,
                    RIGHT - scroll_size, WY + env_y + env_height - settings.border_thickness/2,
                    border_color, settings.border_thickness)
            end
        else
            if settings.track_border_left then
                DrawTrackBorderLine(draw_list, LEFT + settings.border_thickness/2, WY + env_y,
                    LEFT + settings.border_thickness/2, WY + env_y + env_height,
                    border_color, settings.border_thickness)
            end
            if settings.track_border_right then
                DrawTrackBorderLine(draw_list, RIGHT - scroll_size - settings.border_thickness/2, WY + env_y,
                    RIGHT - scroll_size - settings.border_thickness/2, WY + env_y + env_height,
                    border_color, settings.border_thickness)
            end
            if settings.track_border_bottom then
                DrawTrackBorderLine(draw_list, LEFT, WY + env_y + env_height - settings.border_thickness/2,
                    RIGHT - scroll_size, WY + env_y + env_height - settings.border_thickness/2,
                    border_color, settings.border_thickness)
            end
        end
    end
end

function DrawFolderBorders(draw_list, track, track_y, track_height, border_color, WY, is_pinned, pinned_tracks_height)
    is_pinned = is_pinned or false
    pinned_tracks_height = pinned_tracks_height or 0
    
    local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if depth == 1 then
        local start_idx, end_idx = GetFolderBoundaries(track)
        if start_idx and end_idx then
            local has_visible_children = false
            for i = start_idx + 1, end_idx do
                local child = r.GetTrack(0, i)
                local child_height = r.GetMediaTrackInfo_Value(child, "I_TCPH") / screen_scale
                if child_height > 0 then
                    has_visible_children = true
                    break
                end
            end
            
            if has_visible_children then
                local end_track = r.GetTrack(0, end_idx)
                local end_y = r.GetMediaTrackInfo_Value(end_track, "I_TCPY") /screen_scale
                
                local end_total_height = r.GetMediaTrackInfo_Value(end_track, "I_WNDH") / screen_scale
                local total_height = (end_y + end_total_height) - track_y
                
                if not is_pinned and track_y + total_height <= pinned_tracks_height then
                    return
                end
                
                local actual_track_y = track_y
                local actual_total_height = total_height
                
                if not is_pinned and track_y < pinned_tracks_height then
                    if track_y + total_height <= pinned_tracks_height then
                        return
                    end
                    local overlap = pinned_tracks_height - track_y
                    actual_track_y = pinned_tracks_height
                    actual_total_height = total_height - overlap
                    
                    if actual_total_height <= 0 then
                        return
                    end
                end
                
                if settings.folder_border_top then
                    if actual_track_y == track_y or is_pinned then
                        DrawFolderBorderLine(
                            draw_list,
                            LEFT,
                            WY + actual_track_y + settings.border_thickness/2,
                            RIGHT - scroll_size,
                            WY + actual_track_y + settings.border_thickness/2,
                            border_color,
                            settings.border_thickness
                        )
                    end
                end

                if settings.folder_border_left then
                    DrawFolderBorderLine(
                        draw_list,
                        LEFT + settings.border_thickness/2,
                        WY + actual_track_y,
                        LEFT + settings.border_thickness/2,
                        WY + actual_track_y + actual_total_height,
                        border_color,
                        settings.border_thickness
                    )
                end
                
                if settings.folder_border_right then
                    DrawFolderBorderLine(
                        draw_list,
                        RIGHT - scroll_size - settings.border_thickness/2,
                        WY + actual_track_y,
                        RIGHT - scroll_size - settings.border_thickness/2,
                        WY + actual_track_y + actual_total_height,
                        border_color,
                        settings.border_thickness
                    )
                end
                
                if settings.folder_border_bottom then
                    DrawFolderBorderLine(
                        draw_list,
                        LEFT,
                        WY + track_y + total_height - settings.border_thickness/2,
                        RIGHT - scroll_size,
                        WY + track_y + total_height - settings.border_thickness/2,
                        border_color,
                        settings.border_thickness
                    )
                end
            else
                local total_visual_height = r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale
                
                if not is_pinned and track_y + total_visual_height <= pinned_tracks_height then
                    return
                end
                
                local actual_track_y = track_y
                local actual_track_height = track_height
                
                if not is_pinned and track_y < pinned_tracks_height then
                    if track_y + total_visual_height <= pinned_tracks_height then
                        return
                    end
                    local overlap = pinned_tracks_height - track_y
                    actual_track_y = pinned_tracks_height
                    actual_track_height = track_height - overlap
                    
                    if actual_track_height <= 0 then
                        return
                    end
                end
                
                if settings.folder_border_top then
                    if actual_track_y == track_y or is_pinned then
                        DrawFolderBorderLine(
                            draw_list,
                            LEFT,
                            WY + actual_track_y + settings.border_thickness/2,
                            RIGHT - scroll_size,
                            WY + actual_track_y + settings.border_thickness/2,
                            border_color,
                            settings.border_thickness
                        )
                    end
                end

                if settings.folder_border_left then
                    DrawFolderBorderLine(
                        draw_list,
                        LEFT + settings.border_thickness/2,
                        WY + actual_track_y,
                        LEFT + settings.border_thickness/2,
                        WY + actual_track_y + actual_track_height,
                        border_color,
                        settings.border_thickness
                    )
                end
                
                if settings.folder_border_right then
                    DrawFolderBorderLine(
                        draw_list,
                        RIGHT - scroll_size - settings.border_thickness/2,
                        WY + actual_track_y,
                        RIGHT - scroll_size - settings.border_thickness/2,
                        WY + actual_track_y + actual_track_height,
                        border_color,
                        settings.border_thickness
                    )
                end
                
                if settings.folder_border_bottom then
                    DrawFolderBorderLine(
                        draw_list,
                        LEFT,
                        WY + track_y + track_height - settings.border_thickness/2,
                        RIGHT - scroll_size,
                        WY + track_y + track_height - settings.border_thickness/2,
                        border_color,
                        settings.border_thickness
                    )
                end
            end
        end
    end
end


function GetDarkerColor(color)
    local r_val, g_val, b_val = r.ColorFromNative(color)
    return r.ColorToNative(
        (r_val * settings.parent_darkness)//1,
        (g_val * settings.parent_darkness)//1,
        (b_val * settings.parent_darkness)//1
    )
end

function IsToplevelOrClosedFolder(track)
    local parent = r.GetParentTrack(track)
    if parent then
        return false
    end
    
    local folder_depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if folder_depth ~= 1 then
        return true
    end
    
    local folder_state = r.GetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT")
    if folder_state == 2 then
        return true
    end
    
    local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local next_track = r.GetTrack(0, track_idx + 1)
    if not next_track then
        return true
    end
    
    local next_height = r.GetMediaTrackInfo_Value(next_track, "I_TCPH")
    local next_is_child = r.GetParentTrack(next_track) == track
    
    if next_is_child and next_height == 0 then
        return true
    end
    
    return false
end

function GetLighterColor(color, step, total_steps)
    local red, g, b = reaper.ColorFromNative(color)
    local h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(red/255, g/255, b/255)
    local v_step = (1.0 - v) / (total_steps * 0.5)  
    local s_step = (s * 0.8) / total_steps         
    v = v + (v_step * step)
    s = s - (s_step * step)
    v = math.min(v, 1.0)
    s = math.max(s, 0.0)
    local red, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)
    return reaper.ColorToNative(
        math.floor(red * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5)
    )
end

function GetFolderInfo(track)
    local totals = {
        fx = r.TrackFX_GetCount(track),
        sends = r.GetTrackNumSends(track, 0),
        receives = r.GetTrackNumSends(track, -1),
        envelopes = r.CountTrackEnvelopes(track),
        items = r.GetTrackNumMediaItems(track),
        armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1 and 1 or 0,
        muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1 and 1 or 0,
        soloed = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0 and 1 or 0,
        tracks = 1,
        folder_tracks = 0
    }
    
    local idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local depth = 1
    
    while depth > 0 and idx < r.CountTracks(0) - 1 do
        local child = r.GetTrack(0, idx + 1)
        depth = depth + r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
        totals.tracks = totals.tracks + 1
        totals.folder_tracks = totals.folder_tracks + 1
        totals.fx = totals.fx + r.TrackFX_GetCount(child)
        totals.sends = totals.sends + r.GetTrackNumSends(child, 0)
        totals.receives = totals.receives + r.GetTrackNumSends(child, -1)
        totals.envelopes = totals.envelopes + r.CountTrackEnvelopes(child)
        totals.items = totals.items + r.GetTrackNumMediaItems(child)
        totals.armed = totals.armed + (r.GetMediaTrackInfo_Value(child, "I_RECARM") == 1 and 1 or 0)
        totals.muted = totals.muted + (r.GetMediaTrackInfo_Value(child, "B_MUTE") == 1 and 1 or 0)
        totals.soloed = totals.soloed + (r.GetMediaTrackInfo_Value(child, "I_SOLO") > 0 and 1 or 0)
        idx = idx + 1
    end
    
    return string.format("Total Tracks: %d(%d) | FX: %d | Sends/Rec: %d | Env: %d | Items: %d | %s | Rec: %d | Mute: %d | Solo: %d",
        totals.tracks, totals.folder_tracks, totals.fx, totals.sends + totals.receives, totals.envelopes, totals.items,
        has_automation and "Auto" or "No Auto", totals.armed, totals.muted, totals.soloed)
end

-- Scaling by OLSHALOM!
function SetWindowScale(ImGuiScale)
    local OS = reaper.GetOS()
    if OS:find("Win") then
        screen_scale = ImGuiScale  -- Voor Windows
    else
        screen_scale = 1
    end
end

function ShouldHideTrackElements(track)
    return settings.text_hover_hide and r.IsTrackSelected(track)
end


function IsMouseOverTrack(track_y, track_height, WY)
    local x, y = r.GetMousePosition()
    local window = r.JS_Window_FromPoint(x, y)
    
    if window and r.JS_Window_GetTitle(window) == "trackview" then
        x, y = r.JS_Window_ScreenToClient(arrange, x, y)
        y = y / screen_scale
        return y >= track_y and y <= track_y + track_height
    end
    return false
end


--[[profiler.attachToWorld()
profiler.run()
profiler.start()]]--
function loop()
    if r.GetExtState("TK_TRACKNAMES", "reload_settings") == "1" then
        LoadSettings()
        r.SetExtState("TK_TRACKNAMES", "reload_settings", "0", false)
    end
    
    -- Handle startup z-order fix (only once, ever)
    if not zorder_handled_at_startup then
        ensureOverlayBehindWindows()
        zorder_handled_at_startup = true
    end

    settings_visible = r.GetExtState("TK_TRACKNAMES", "settings_visible") == "1"
    if not (ctx and r.ImGui_ValidatePtr(ctx, 'ImGui_Context*')) then
        ctx = r.ImGui_CreateContext('Track Names')
        CreateFonts()
    end

    local current_project = reaper.EnumProjects(-1)
    local track_count = reaper.CountTracks(0)
    if current_project ~= last_project or track_count ~= last_track_count then
        RefreshProjectState()
        last_project = current_project
        last_track_count = track_count
    end
    if settings.custom_colors_enabled then
        local current_grid_divide = r.GetToggleCommandState(42331)
        if current_grid_divide == 1 then
            r.Main_OnCommand(42331, 0)
        end
    end

    DrawOverArrange(false)
    r.ImGui_PushFont(ctx, font_objects[settings.selected_font])
    local ImGuiScale = reaper.ImGui_GetWindowDpiScale(ctx)
    if ImGuiScale ~= ImGuiScale_saved then
      SetWindowScale(ImGuiScale)
      ImGuiScale_saved = ImGuiScale
    end

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0.0)

    -- Pass-through overlay implementatie (Linux: off-screen micro host + ForegroundDrawList)
    local use_pass_through = settings.pass_through_overlay
    local draw_list, WX, WY
    local visible, open

    if use_pass_through then
        r.ImGui_SetNextWindowPos(ctx, -10000, -10000, r.ImGui_Cond_Always())
        r.ImGui_SetNextWindowSize(ctx, 4, 4, r.ImGui_Cond_Always())
        visible, open = r.ImGui_Begin(ctx, '##TK_TrackNames_LinuxHost', true,
            r.ImGui_WindowFlags_NoDecoration() |
            r.ImGui_WindowFlags_NoInputs() |
            r.ImGui_WindowFlags_NoNav() |
            r.ImGui_WindowFlags_NoMove() |
            r.ImGui_WindowFlags_NoSavedSettings() |
            r.ImGui_WindowFlags_NoBackground()
        )
        draw_list = r.ImGui_GetForegroundDrawList(ctx)
        WX, WY = 0, 0
        visible = true 
    else
        visible, open = r.ImGui_Begin(ctx, 'Track Names Display', true, window_flags)
        if visible then
            draw_list = r.ImGui_GetWindowDrawList(ctx)
            WX, WY = r.ImGui_GetWindowPos(ctx)
        end
    end
    if visible then
        local max_width = 0

        if not cached_bg_color then
            UpdateBgColorCache()
        end
        
        DrawOverlayGrid(draw_list, WY)

        local pinned_override = r.GetToggleCommandState(42595) == 1
        
        local _, view_height = GetArrangeViewBounds()
        local view_bottom = view_height / screen_scale
        local first_visible_idx = FindFirstVisibleTrack(track_count, 0, view_bottom)
        local last_visible_idx = FindLastVisibleTrack(track_count, 0, view_bottom)
        if first_visible_idx < 0 then first_visible_idx = 0 end
        if last_visible_idx < 0 then last_visible_idx = track_count - 1 end

        local pinned_tracks_height = 0  
        local pinned_status = {}  
        
        for i = 0, track_count - 1 do
            pinned_status[i] = false
        end
        
        pinned_status[-1] = false  
        if not pinned_override then
            local master_track = r.GetMasterTrack(0)
            local master_visible = r.GetMasterTrackVisibility() & (1<<0) ~= 0
            
            if master_visible then
                local master_y = r.GetMediaTrackInfo_Value(master_track, "I_TCPY") / screen_scale
                local master_height = r.GetMediaTrackInfo_Value(master_track, "I_WNDH") / screen_scale
                
                if math.abs(master_y) < 1 then
                    pinned_status[-1] = true
                    pinned_tracks_height = master_height
                end
            end
            
            local all_tracks = {}
            for i = 0, track_count - 1 do
                local track = r.GetTrack(0, i)
                if track then
                    local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
                    local track_height = r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale
                    all_tracks[#all_tracks + 1] = {
                        index = i,
                        y = track_y,
                        height = track_height,
                        bottom = track_y + track_height
                    }
                end
            end
            
            table.sort(all_tracks, function(a, b) return a.y < b.y end)
            
            local expected_y = pinned_tracks_height
            for _, track_info in ipairs(all_tracks) do
                local gap = track_info.y - expected_y
                if gap >= -3 and gap < 10 then
                    pinned_status[track_info.index] = true
                    expected_y = track_info.bottom
                end
            end
            
            pinned_tracks_height = expected_y
            
            if pinned_tracks_height > 0 then
                pinned_tracks_height = pinned_tracks_height + 8
            end
        end

        for pass = 1, 2 do
            local current_height = 0  
            
            do
                local i = -1
                local track = r.GetMasterTrack(0)
                local is_master = true
                local is_pinned = pinned_status[-1] or false
                
                local clip_height_for_this_track = current_height
                
                if is_pinned then
                    local track_height = r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale
                    current_height = current_height + track_height
                end
                
                if (pass == 1 and not is_pinned) or (pass == 2 and is_pinned) then
                    local master_visible = r.GetMasterTrackVisibility() & (1<<0) ~= 0
                    if master_visible then
                        local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") /screen_scale
                        local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") /screen_scale
                        
                        local clip_height = is_pinned and 0 or pinned_tracks_height
                        
                        if settings.show_track_colors and settings.use_custom_master_color then
                            if settings.master_gradient_enabled then
                                local start_alpha = (settings.master_gradient_start_alpha * 255)//1
                                local end_alpha = (settings.master_gradient_end_alpha * 255)//1
                                
                                local start_color = (settings.master_track_color & 0xFFFFFF00) | start_alpha
                                local end_color = (settings.master_track_color & 0xFFFFFF00) | end_alpha
                                
                                local actual_y = track_y
                                local actual_height = track_height
                                
                                if clip_height > 0 and track_y < clip_height then
                                    if track_y + track_height <= clip_height then
                                        goto skip_master_gradient
                                    end
                                    local overlap = clip_height - track_y
                                    actual_y = clip_height
                                    actual_height = track_height - overlap
                                end
                                
                                r.ImGui_DrawList_AddRectFilledMultiColor(
                                    draw_list, 
                                    LEFT, 
                                    WY + actual_y,
                                    RIGHT - scroll_size,
                                    WY + actual_y + actual_height,
                                    start_color,
                                    settings.gradient_direction == 1 and end_color or start_color,
                                    settings.gradient_direction == 1 and end_color or start_color,
                                    start_color
                                )
                                ::skip_master_gradient::
                            else
                                local red, green, blue, _ = r.ImGui_ColorConvertU32ToDouble4(settings.master_track_color)
                                local color_with_alpha = r.ImGui_ColorConvertDouble4ToU32(red, green, blue, settings.master_overlay_alpha)
                                RenderSolidOverlay(draw_list, track, track_y, track_height, color_with_alpha, WY, clip_height)
                            end
                        end
                        
                        local text = "MASTER"
                        local text_width = r.ImGui_CalcTextSize(ctx, text)
                        local text_y = WY + track_y + (track_height * 0.5) - (settings.text_size * 0.5)
                        local text_x
                        
                        if settings.text_centered then
                            if settings.auto_center then
                                local window_width = RIGHT - LEFT - scroll_size
                                text_x = LEFT + (window_width / 2) - (text_width / 2)
                            else                      
                                local offset = (max_width - text_width) / 2
                                text_x = WX + settings.horizontal_offset + offset
                            end
                        elseif settings.right_align then
                            text_x = RIGHT - scroll_size - text_width - 20 - settings.horizontal_offset
                        else
                            text_x = WX + settings.horizontal_offset
                        end
                        
                        if is_pinned or text_y >= WY + pinned_tracks_height then
                            local text_color = GetTextColor(track)
                            text_color = (text_color & 0xFFFFFF00) | ((settings.text_opacity * 255)//1)
                            r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, text)
                        end
                    end
                end
            end
            
            for i = 0, track_count - 1 do 
                local is_pinned = pinned_status[i] or false
                local in_visible_range = (i >= first_visible_idx and i <= last_visible_idx)
                
                if not is_pinned and not in_visible_range then
                    goto continue_track_loop
                end
                
                local track = r.GetTrack(0, i)
                
                local clip_height_for_this_track = current_height
                
                if is_pinned then
                    local track_height = r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale
                    current_height = current_height + track_height
                end
                
                if (pass == 1 and not is_pinned) or (pass == 2 and is_pinned) then
            
             
                local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") /screen_scale
                local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") /screen_scale
                local is_parent = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                local is_child = r.GetParentTrack(track) ~= nil
                local track_color = r.GetTrackColor(track)
                
                if settings.show_track_colors and settings.folder_border and (is_parent or is_child) then
                    local hide_folder_border = settings.exclude_hide_border and IsTrackExcluded(track)
                    if not hide_folder_border then
                        local border_base_color = r.GetTrackColor(track)
                        if is_child then
                            local parent = r.GetParentTrack(track)
                            if parent then
                                border_base_color = r.GetTrackColor(parent)
                            end
                        end
                        local darker_color = GetDarkerColor(border_base_color)
                        local border_color = GetCachedColor(darker_color, settings.border_opacity)
                        local border_clip_height = is_pinned and 0 or pinned_tracks_height
                        DrawFolderBorders(draw_list, track, track_y, track_height, border_color, WY, is_pinned, border_clip_height)
                    end
                end
                
                local track_visible = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1
                if track_visible and IsTrackVisible(track) then
                    local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
                    local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
                    local is_soloed = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
                    local track_number = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
            
                    local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                    max_width = math.max(max_width, text_width)
            
                    if settings.show_track_colors then
                        local hide_color = settings.exclude_hide_color and IsTrackExcluded(track)
                        
                        if not hide_color and ((is_parent and settings.show_parent_colors) or
                            (is_child and settings.show_child_colors) or
                            (not is_parent and not is_child and settings.show_normal_colors)) then
                            
                            local base_color = track_color
                            local main_parent = nil
                            
                            if settings.deep_inherit_color then
                                local current = track
                                while r.GetParentTrack(current) do
                                    current = r.GetParentTrack(current)
                                    if not r.GetParentTrack(current) then
                                        main_parent = current
                                    end
                                end
                                if main_parent then
                                    base_color = r.GetTrackColor(main_parent)
                                    
                                    if settings.color_gradient_enabled then
                                        local main_parent_idx = r.GetMediaTrackInfo_Value(main_parent, "IP_TRACKNUMBER") - 1
                                        local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
                                        local position = track_idx - main_parent_idx
                                        track_color = GetLighterColor(base_color, position, 5)
                                    else
                                        track_color = base_color
                                    end
                                end
                            elseif settings.color_gradient_enabled and not is_parent then
                                local parent = r.GetParentTrack(track)
                                if parent then
                                    base_color = r.GetTrackColor(parent)
                                    if base_color == 0 then base_color = track_color end
                                    
                                    local track_position = 0
                                    local parent_idx = r.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER") - 1
                                    local current_idx = parent_idx
                                    local current_depth = 0
                                    
                                    while current_depth >= 0 and current_idx < r.CountTracks(0) do
                                        local current_track = r.GetTrack(0, current_idx)
                                        local depth = r.GetMediaTrackInfo_Value(current_track, "I_FOLDERDEPTH")
                                        
                                        if current_track == track then
                                            track_color = GetLighterColor(base_color, track_position, 5)
                                            break
                                        end
                                        
                                        current_depth = current_depth + depth
                                        track_position = track_position + 1
                                        current_idx = current_idx + 1
                                    end
                                end
                            elseif settings.inherit_parent_color and not is_parent then
                                local parent = r.GetParentTrack(track)
                                if parent then
                                    track_color = r.GetTrackColor(parent)
                                end
                            end
                            
                            if settings.show_record_color and IsRecording(track) and r.GetPlayState() == 5 then
                                track_color = r.ColorToNative(255, 0, 0)
                            end
            
                            if track_color ~= 0 then
                                local total_height = track_height
                                local env_count = r.CountTrackEnvelopes(track)
                                
                                if env_count > 0 then
                                    for i = 0, env_count - 1 do
                                        total_height = total_height + r.GetEnvelopeInfo_Value(r.GetTrackEnvelope(track, i), "I_TCPH") / screen_scale
                                    end
                                end
                                
                                if track_y < (BOT - TOP) - scroll_size or (track_y + total_height) > 0 then
                                    local blended_color = BlendColor(track, track_color, settings.blend_mode)
                                    local color
                                    
                                    if is_parent and settings.darker_parent_tracks and 
                                    (not r.GetParentTrack(track) or settings.nested_parents_darker) and
                                    not (settings.exclude_hide_color and IsTrackExcluded(track)) then
                                    local darker_color = GetDarkerColor(blended_color)
                                    color = GetCachedColor(darker_color, settings.darker_parent_opacity)
                                    else
                                    color = GetCachedColor(blended_color, settings.overlay_alpha)
                                    end
                                    
                                    local clip_height = is_pinned and 0 or pinned_tracks_height
                                    
                                    if settings.gradient_enabled then
                                        RenderGradientOverlay(draw_list, track, track_y, track_height, color, WY, is_parent, clip_height)
                                    else
                                        RenderSolidOverlay(draw_list, track, track_y, track_height, color, WY, clip_height)
                                    end
                                end
                            end
                        end
                        
                        if settings.track_border and not is_parent and not is_child and track_color ~= 0 then
                            local hide_border = settings.exclude_hide_border and IsTrackExcluded(track)
                            if not hide_border then
                                local blended_color = BlendColor(track, track_color, settings.blend_mode)

                                local border_color = GetCachedColor(blended_color, settings.border_opacity)
                                local border_clip_height = is_pinned and 0 or pinned_tracks_height
                                DrawTrackBorders(draw_list, track, track_y, track_height, border_color, WY, is_pinned, border_clip_height)
                            end
                        end
                    end

                    local should_show_track = false
                    local should_show_name = false
                    
                    local hide_label = settings.exclude_hide_label and IsTrackExcluded(track)

                    if hide_label then
                        should_show_track = false
                        should_show_name = false
                    elseif settings.show_parent_tracks and is_parent then
                        should_show_track = true
                        should_show_name = true
                    end
                    if not hide_label and settings.show_child_tracks and is_child then
                        should_show_track = true
                        should_show_name = true
                    end
                    if not hide_label and settings.show_normal_tracks and (not is_parent and not is_child) then
                        should_show_track = true
                        should_show_name = true
                    end
                    if not hide_label and settings.show_parent_label and is_child then
                        should_show_track = true
                    end

                    if (settings.text_hover_enabled and IsMouseOverTrack(track_y, track_height, WY)) or
                    (settings.text_hover_hide and r.IsTrackSelected(track)) then
                     should_show_track = false
                     should_show_name = false
                    end

                    if should_show_track then
                        local _, track_name = r.GetTrackName(track)
                        local display_name

                        local track_display = TruncateTrackName(track_name, settings.track_name_length, settings.fixed_label_length)
                        local fx_display = nil
                        if settings.show_first_fx then
                            local fx_count = r.TrackFX_GetCount(track)
                            if fx_count > 0 then
                                local _, fx_name = r.TrackFX_GetFXName(track, 0, "")
                                fx_name = fx_name:gsub("^[^:]+:%s*", "")
                                fx_display = TruncateTrackName(fx_name, settings.fx_name_length, settings.fx_fixed_label_length)
                            end
                        end
                        if fx_display then
                            display_name = track_display .. " - " .. fx_display
                        else
                            display_name = track_display
                        end

                        local vertical_offset = (track_height * settings.vertical_offset) / 100
                        local text_y = WY + track_y + (track_height * 0.5) - (settings.text_size * 0.5) + vertical_offset

                        if is_child and settings.show_parent_label then
                            local parents = GetAllParentTracks(track)
                            if #parents > 0 then
                                local combined_name = ""
                                for i = #parents, 1, -1 do
                                    local _, parent_name = r.GetTrackName(parents[i])
                                    parent_name = TruncateTrackName(parent_name, settings.track_name_length)
                                    combined_name = combined_name .. parent_name .. " / "
                                end

                                local parent_text_width = r.ImGui_CalcTextSize(ctx, combined_name)
                                local track_text_width = r.ImGui_CalcTextSize(ctx, display_name)
                                local parent_text_pos = WX + settings.horizontal_offset
                                local label_x = parent_text_pos
                                
                                local BASE_SPACING = 20
                                local NUMBER_SPACING = 20
                                local TEXT_SIZE_FACTOR = settings.text_size
                                
                                if settings.text_centered then
                                    if settings.auto_center then
                                        local window_width = RIGHT - LEFT - scroll_size
                                        local total_spacing = BASE_SPACING + TEXT_SIZE_FACTOR
                                        if settings.show_track_numbers then
                                            total_spacing = total_spacing + NUMBER_SPACING / 2
                                        end
                                        
                                        if should_show_track then
                                            local center_x = LEFT + (window_width / 2) - (track_text_width / 2)
                                            if settings.icon_position == 1 then
                                                parent_text_pos = center_x + track_text_width + total_spacing
                                            else
                                                parent_text_pos = center_x - total_spacing - parent_text_width
                                            end
                                        else
                                            parent_text_pos = LEFT + (window_width / 2) - (parent_text_width / 2)
                                        end
                                    end
                                elseif settings.right_align then
                                    local right_margin = 20
                                    local total_spacing = BASE_SPACING + TEXT_SIZE_FACTOR
                                    if settings.show_track_numbers then
                                        total_spacing = total_spacing + NUMBER_SPACING
                                    end
                                    
                                    local icon_offset = 0
                                    if settings.show_track_icons and track_icon_manager.GetTrackIcon(track) and settings.icon_position == 1 then
                                        icon_offset = settings.icon_size + settings.icon_spacing
                                    end
                                    
                                    parent_text_pos = RIGHT - scroll_size - parent_text_width - right_margin - settings.horizontal_offset
                                    if should_show_name then
                                        parent_text_pos = parent_text_pos - track_text_width - total_spacing - icon_offset
                                    end
                                else
                                    if should_show_name then
                                        local total_spacing = BASE_SPACING + TEXT_SIZE_FACTOR
                                        if settings.show_track_numbers then
                                            total_spacing = total_spacing + NUMBER_SPACING
                                        end
                                        
                                        local actual_text_width = track_text_width
                                        if settings.show_track_numbers then
                                            local temp_name = display_name
                                            if settings.track_number_style == 1 then
                                                temp_name = string.format("%02d. %s", track_number, display_name)
                                            elseif settings.track_number_style == 2 then
                                                temp_name = string.format("%s -%02d", display_name, track_number)
                                            end
                                            actual_text_width = r.ImGui_CalcTextSize(ctx, temp_name)
                                        end
                                        
                                        local icon_offset = 0
                                        if settings.show_track_icons and track_icon_manager.GetTrackIcon(track) and settings.icon_position == 2 then
                                            icon_offset = settings.icon_size + settings.icon_spacing
                                        end
                                        
                                        parent_text_pos = WX + settings.horizontal_offset + actual_text_width + total_spacing + icon_offset
                                    end
                                end
                                
                                label_x = parent_text_pos
                                
                                if settings.show_label then
                                    local parent_color = r.GetTrackColor(parents[#parents])
                                    local r_val, g_val, b_val = r.ColorFromNative(parent_color)
                                    local parent_label_color = r.ImGui_ColorConvertDouble4ToU32(
                                        r_val/255, g_val/255, b_val/255,
                                        settings.label_alpha
                                    )
                                    
                                    if is_pinned or text_y >= WY + pinned_tracks_height then
                                        r.ImGui_DrawList_AddRectFilled(
                                            draw_list,
                                            label_x - 10,
                                            text_y - settings.label_height_padding,
                                            label_x + parent_text_width + 10,
                                            text_y + settings.text_size + settings.label_height_padding,
                                            parent_label_color,
                                            4.0
                                        )
                                        if settings.label_border then
                                            local parent_text_color = GetTextColor(parents[#parents], false, true)
                                            local border_color = (parent_text_color & 0xFFFFFF00) | ((settings.label_border_opacity * 255)//1)
                                            r.ImGui_DrawList_AddRect(
                                                draw_list,
                                                label_x - 10,
                                                text_y - settings.label_height_padding,
                                                label_x + parent_text_width + 10,
                                                text_y + settings.text_size + settings.label_height_padding,
                                                border_color,
                                                4.0,
                                                0,
                                                settings.label_border_thickness
                                            )
                                        end
                                    end
                                end

                                if is_pinned or text_y >= WY + pinned_tracks_height then
                                    local parent_text_color = GetTextColor(parents[#parents], false, true)
                                    r.ImGui_DrawList_AddText(
                                        draw_list,
                                        parent_text_pos,
                                        text_y,
                                        parent_text_color,
                                        combined_name
                                    )
                                end
                            end
                        end

                        if should_show_name then
                            local modified_display_name = display_name
                            
                            if settings.show_track_numbers then
                                if settings.track_number_style == 1 then
                                    modified_display_name = string.format("%02d. %s", track_number, display_name)
                                elseif settings.track_number_style == 2 then
                                    modified_display_name = string.format("%s -%02d", display_name, track_number)
                                end
                            end
                            
                            local text_width = r.ImGui_CalcTextSize(ctx, modified_display_name)
                            local text_x
                            local keep_text_aligned = false

                            if settings.text_centered then
                                keep_text_aligned = true
                                if settings.auto_center then
                                    local window_width = RIGHT - LEFT - scroll_size
                                    text_x = LEFT + (window_width / 2) - (text_width / 2)
                                else
                                    local offset = (max_width - text_width) / 2
                                    text_x = WX + settings.horizontal_offset + offset
                                end
                            elseif settings.right_align then
                                keep_text_aligned = true
                                text_x = RIGHT - scroll_size - text_width - 20 - settings.horizontal_offset
                            else
                                keep_text_aligned = true
                                text_x = WX + settings.horizontal_offset
                            end

                            text_x = RenderTrackIcon(draw_list, track, track_y, track_height, text_x, text_width, vertical_offset, WY, is_pinned, pinned_tracks_height, keep_text_aligned)

                            if settings.show_label then
                                local label_color = GetLabelColor(track)
                                if is_pinned or text_y >= WY + pinned_tracks_height then
                                    r.ImGui_DrawList_AddRectFilled(
                                        draw_list,
                                        text_x - 10,
                                        text_y - settings.label_height_padding,
                                        text_x + text_width + 10,
                                        text_y + settings.text_size + settings.label_height_padding,
                                        label_color,
                                        4.0
                                    )
                                    if settings.label_border then
                                        local border_color = GetTextColor(track, is_child)
                                        border_color = (border_color & 0xFFFFFF00) | ((settings.label_border_opacity * 255)//1)
                                        r.ImGui_DrawList_AddRect(
                                            draw_list,
                                            text_x - 10,
                                            text_y - settings.label_height_padding,
                                            text_x + text_width + 10,
                                            text_y + settings.text_size + settings.label_height_padding,
                                            border_color,
                                            4.0,
                                            0,
                                            settings.label_border_thickness
                                        )
                                    end
                                end
                            end
                        
                            local text_color = GetTextColor(track, is_child)
                            text_color = (text_color & 0xFFFFFF00) | ((settings.text_opacity * 255)//1)
                            
                            if is_pinned or text_y >= WY + pinned_tracks_height then
                                r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, modified_display_name)
                            end
                          
                            if settings.show_info_line and not r.GetParentTrack(track) then
                                local info_text = GetFolderInfo(track)
                                local track_text_width = r.ImGui_CalcTextSize(ctx, modified_display_name)
                                local info_text_x
                                
                                -- Calculate extra offset if icon is shown
                                local icon_offset = 0
                                if settings.show_track_icons and track_icon_manager.GetTrackIcon(track) then
                                    if settings.icon_position == 2 then -- Icon right of text
                                        icon_offset = settings.icon_size + settings.icon_spacing
                                    end
                                end
                                
                                if settings.right_align then
                                    info_text_x = text_x - r.ImGui_CalcTextSize(ctx, info_text) - 20
                                else
                                    info_text_x = text_x + track_text_width + icon_offset + 20
                                end
                                
                                if is_pinned or text_y >= WY + pinned_tracks_height then
                                    r.ImGui_DrawList_AddText(draw_list, info_text_x, text_y, text_color, info_text)
                                end
                            end

                            local dot_size = 4
                            local dot_spacing = 1
                            local total_dots_height = (dot_size * 3) + (dot_spacing * 2)
                            local track_center = text_y + (settings.text_size / 2)
                            local dots_start_y = track_center - (total_dots_height / 2)
                            local dot_x = text_x + text_width + 5
                        
                            if (is_pinned or text_y >= WY + pinned_tracks_height) and is_armed then
                                r.ImGui_DrawList_AddCircleFilled(
                                    draw_list,
                                    dot_x,
                                    dots_start_y + dot_size/2,
                                    dot_size/2,
                                    0xFF0000FF
                                )
                            end
                            
                            if (is_pinned or text_y >= WY + pinned_tracks_height) and is_soloed then
                                r.ImGui_DrawList_AddCircleFilled(
                                    draw_list,
                                    dot_x,
                                    dots_start_y + dot_size + dot_spacing + dot_size/2,
                                    dot_size/2,
                                    0x0000FFFF
                                )
                            end
                            
                            if (is_pinned or text_y >= WY + pinned_tracks_height) and is_muted then
                                r.ImGui_DrawList_AddCircleFilled(
                                    draw_list,
                                    dot_x,
                                    dots_start_y + (dot_size * 2) + (dot_spacing * 2) + dot_size/2,
                                    dot_size/2,
                                    0xFF8C00FF
                                )
                            end
                        end
                    end
                    if settings.show_envelope_names then
                        local env_count = r.CountTrackEnvelopes(track)
                        for i = 0, env_count - 1 do
                            local env = r.GetTrackEnvelope(track, i)
                            local env_height = r.GetEnvelopeInfo_Value(env, "I_TCPH") / screen_scale
                            local env_y = r.GetEnvelopeInfo_Value(env, "I_TCPY") / screen_scale
                            local env_used_height = r.GetEnvelopeInfo_Value(env, "I_TCPH_USED")
                            local in_lane = env_used_height > 0 and env_height > 0 and env_y > 0
                            
                            if in_lane then
                                local retval, env_name = r.GetEnvelopeName(env)
                                local text_width = r.ImGui_CalcTextSize(ctx, env_name)
                                local env_text_x
                                
                                if settings.text_centered then
                                    if settings.auto_center then
                                        local window_width = RIGHT - LEFT - scroll_size
                                        env_text_x = LEFT + (window_width / 2) - (text_width / 2)
                                    else
                                        local offset = (max_width - text_width) / 2
                                        env_text_x = WX + settings.horizontal_offset + offset
                                    end
                                elseif settings.right_align then
                                    env_text_x = RIGHT - scroll_size - text_width - 20 - settings.horizontal_offset
                                else
                                    env_text_x = WX + settings.horizontal_offset
                                end
                                
                                local absolute_env_y = track_y + env_y
                                local text_y = WY + absolute_env_y + (env_height/2) - (settings.text_size/2)
                                
                                if is_pinned or text_y >= WY + pinned_tracks_height then
                                    local env_color = GetTextColor(track, is_child)
                                    env_color = (env_color & 0xFFFFFF00) | ((settings.envelope_text_opacity * 255)//1)
                                    r.ImGui_DrawList_AddText(draw_list, env_text_x, text_y, env_color, env_name)
                                end
                            end
                        end
                    end
                end 
                end 
            ::continue_track_loop::
            end 
        end 
        
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 2)
    r.ImGui_PopFont(ctx)


    if settings.show_settings_button then
        r.ImGui_SetNextWindowPos(ctx, settings.button_x, settings.button_y, r.ImGui_Cond_Once())
        local button_flags = r.ImGui_WindowFlags_NoTitleBar() | 
                            r.ImGui_WindowFlags_TopMost() |
                            r.ImGui_WindowFlags_NoResize() |
                            r.ImGui_WindowFlags_AlwaysAutoResize()
        
        local button_visible = r.ImGui_Begin(ctx, '##Settings Button', true, button_flags)
        if button_visible then
            settings.button_x, settings.button_y = r.ImGui_GetWindowPos(ctx)
            
             r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4.0)
            r.ImGui_PushFont(ctx, settings_font)
            if r.ImGui_Button(ctx, "S") then
                settings_visible = not settings_visible
                r.SetExtState("TK_TRACKNAMES", "settings_visible", settings_visible and "1" or "0", false)
            end
            r.ImGui_PopFont(ctx)
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_End(ctx)
        end
    end

    if settings_visible then
        ShowSettingsWindow()
    end

    -- Track Icon Browser
    if track_icon_browser.show_window then
        track_icon_browser.Show(ctx)
        
        -- Als een icon is geselecteerd, apply to alle geselecteerde tracks
        if track_icon_browser.selected_icon then
            local sel_track_count = r.CountSelectedTracks(0)
            if sel_track_count > 0 then
                for i = 0, sel_track_count - 1 do
                    local track = r.GetSelectedTrack(0, i)
                    track_icon_manager.SetTrackIcon(track, track_icon_browser.selected_icon)
                end
            end
            track_icon_browser.selected_icon = nil
        end
    end

    if needs_font_update then
        ctx = r.ImGui_CreateContext('Track Names')
        CreateFonts()
        needs_font_update = false
    end

    if open then
        script_active = true
        r.defer(loop)
    else
        if script_active then
            SaveSettings()
            script_active = false
        end
    end
end

local success = pcall(function()
    color_cache = {}
    cached_bg_color = nil
    
    LoadSettings()
    LoadExcludedTracks()
    CreateFonts()

    if settings.custom_colors_enabled then
        grid_divide_state = r.GetToggleCommandState(42331)
        if grid_divide_state == 1 then
            r.Main_OnCommand(42331, 0)
        end

        if settings.grid_color_enabled then
            UpdateGridColors()
        else
            r.SetThemeColor("col_gridlines", -1, 0)
            r.SetThemeColor("col_gridlines2", -1, 0)
            r.SetThemeColor("col_gridlines3", -1, 0)
            r.SetThemeColor("col_tr1_divline", -1, 0)
            r.SetThemeColor("col_tr2_divline", -1, 0)
        end

        if settings.bg_brightness_enabled then
            UpdateArrangeBG()
        UpdateTrackColors()
        else
            r.SetThemeColor("col_arrangebg", -1, 0)
        end
    end

    SetButtonState(1)
    r.defer(loop)
end)



r.atexit(function() 
    SetButtonState(0) 
    SaveSettings()
    
    r.SetThemeColor("col_gridlines", -1, 0)
    r.SetThemeColor("col_gridlines2", -1, 0)
    r.SetThemeColor("col_gridlines3", -1, 0)
    r.SetThemeColor("col_arrangebg", -1, 0)
    r.SetThemeColor("col_tr1_bg", -1, 0)
    r.SetThemeColor("col_tr2_bg", -1, 0)
    r.SetThemeColor("selcol_tr1_bg", -1, 0)
    r.SetThemeColor("selcol_tr2_bg", -1, 0)
    r.SetThemeColor("col_tr1_divline", -1, 0)
    r.SetThemeColor("col_tr2_divline", -1, 0)
    
    if grid_divide_state == 1 then
        r.Main_OnCommand(42331, 0)
    end
    
    r.UpdateArrange()
    r.TrackList_AdjustWindows(false)
end)

if not success then
    r.ShowConsoleMsg("Script error occurred\n")
end





