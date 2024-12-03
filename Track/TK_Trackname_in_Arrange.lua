-- @description TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 0.2.9:
-- @changelog:
--[[            
+ Center Text /labels
]]----------------------------------------------------------------------------------       

local r = reaper
local ctx = r.ImGui_CreateContext('Track Names')
local settings_visible = false
local last_update_time = 0
local update_interval = 0.05 
local last_project = nil
local last_track_count = 0
-- Settings
local default_settings = {
    text_opacity = 1.0,
    show_parent_tracks = true,
    show_child_tracks = false,
    show_first_fx = false,
    horizontal_offset = 100,
    vertical_offset = 0,
    selected_font = 1,
    color_mode = 1,
    overlay_alpha = 0.1,
    show_track_colors = true, 
    grid_color = 0.0,  
    bg_brightness = 0.2,  
    custom_colors_enabled = false,
    show_label = true,
    label_alpha = 0.3,
    label_color_mode = 1,
    text_centered = false 
}
local settings = {}
for k, v in pairs(default_settings) do
    settings[k] = v
end



local fonts = {
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

local color_modes = {"White", "Black", "Track Color", "Complementary"}
local font_objects = {}
for _, font_name in ipairs(fonts) do
    local font = r.ImGui_CreateFont(font_name, 18)
    table.insert(font_objects, font)
    r.ImGui_Attach(ctx, font)
end
local settings_font = r.ImGui_CreateFont('sans-serif', 14)
r.ImGui_Attach(ctx, settings_font)

function SaveSettings()
    local section = "TK_TRACKNAMES"
    r.SetExtState(section, "text_opacity", tostring(settings.text_opacity), true)
    r.SetExtState(section, "show_parent_tracks", settings.show_parent_tracks and "1" or "0", true)
    r.SetExtState(section, "show_child_tracks", settings.show_child_tracks and "1" or "0", true)
    r.SetExtState(section, "show_first_fx", settings.show_first_fx and "1" or "0", true)
    r.SetExtState(section, "horizontal_offset", tostring(settings.horizontal_offset), true)
    r.SetExtState(section, "vertical_offset", tostring(settings.vertical_offset), true)
    r.SetExtState(section, "selected_font", tostring(settings.selected_font), true)
    r.SetExtState(section, "color_mode", tostring(settings.color_mode), true)
    r.SetExtState(section, "overlay_alpha", tostring(settings.overlay_alpha), true)
    r.SetExtState(section, "show_track_colors", settings.show_track_colors and "1" or "0", true)
    r.SetExtState(section, "grid_color", tostring(settings.grid_color), true)
    r.SetExtState(section, "bg_brightness", tostring(settings.bg_brightness), true)
    r.SetExtState(section, "custom_colors_enabled", settings.custom_colors_enabled and "1" or "0", true)
    r.SetExtState(section, "show_label", settings.show_label and "1" or "0", true)
    r.SetExtState(section, "label_alpha", tostring(settings.label_alpha), true)
    r.SetExtState(section, "label_color_mode", tostring(settings.label_color_mode), true)
end

function LoadSettings()
    local section = "TK_TRACKNAMES"
    settings.text_opacity = tonumber(r.GetExtState(section, "text_opacity")) or 1.0
    settings.show_parent_tracks = r.GetExtState(section, "show_parent_tracks") == "1"
    settings.show_child_tracks = r.GetExtState(section, "show_child_tracks") == "1"
    settings.show_first_fx = r.GetExtState(section, "show_first_fx") == "1"
    settings.horizontal_offset = tonumber(r.GetExtState(section, "horizontal_offset")) or 0
    settings.vertical_offset = tonumber(r.GetExtState(section, "vertical_offset")) or 0
    settings.selected_font = tonumber(r.GetExtState(section, "selected_font")) or 1
    settings.color_mode = tonumber(r.GetExtState(section, "color_mode")) or 1
    settings.overlay_alpha = tonumber(r.GetExtState(section, "overlay_alpha")) or 0.1
    settings.show_track_colors = r.GetExtState(section, "show_track_colors") == "1"
    settings.grid_color = tonumber(r.GetExtState(section, "grid_color")) or 0.0
    settings.bg_brightness = tonumber(r.GetExtState(section, "bg_brightness")) or 0.2
    settings.custom_colors_enabled = r.GetExtState(section, "custom_colors_enabled") == "1"
    settings.show_label = r.GetExtState(section, "show_label") == "1"
    settings.label_alpha = tonumber(r.GetExtState(section, "label_alpha")) or 0.3
    settings.label_color_mode = tonumber(r.GetExtState(section, "label_color_mode")) or 1
end

function cleanup()
    -- Reset alle kleuren
    reaper.SetThemeColor("col_gridlines", -1, 0)
    reaper.SetThemeColor("col_gridlines2", -1, 0)
    reaper.SetThemeColor("col_gridlines3", -1, 0)
    reaper.SetThemeColor("col_arrangebg", -1, 0)
    reaper.SetThemeColor("col_tr1_bg", -1, 0)
    reaper.SetThemeColor("col_tr2_bg", -1, 0)
    
    -- Reset tracknaam gerelateerde instellingen
    settings.text_opacity = default_settings.text_opacity
    settings.show_parent_tracks = default_settings.show_parent_tracks
    settings.show_child_tracks = default_settings.show_child_tracks
    settings.show_first_fx = default_settings.show_first_fx
    
    reaper.UpdateArrange()
end


function RefreshProjectState()
    LoadSettings()
    if settings.custom_colors_enabled then
        UpdateGridColors()
        UpdateBackgroundColors()
    end
    reaper.UpdateArrange()
end


function GetTextColor(track)
    if settings.color_mode == 1 then
        return 0xFFFFFFFF
    elseif settings.color_mode == 2 then
        return 0x000000FF  
    elseif settings.color_mode == 3 then
        local r_val, g_val, b_val = r.ColorFromNative(r.GetTrackColor(track))
        local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val, g_val, b_val)
        
        if h > 0 and s > 0 and v > 0 then
            if v/255 > 0.8 then
                v = v - 0.2*255
            else
                v = v + 0.2*255
            end
            
            if s > 0.9 then
                s = s - 0.1
            else
                s = s + 0.1
            end
        end
        
        local r_val, g_val, b_val = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
        return r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 1.0)
    else
        local r_val, g_val, b_val = r.ColorFromNative(r.GetTrackColor(track))
        local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val, g_val, b_val)
        
        h = (h + 0.5) % 1.0
        
        if v/255 > 0.8 then
            v = v - 0.2*255
        else
            v = v + 0.2*255
        end
        
        if s > 0.9 then
            s = s - 0.1
        else
            s = s + 0.1
        end
        
        local r_val, g_val, b_val = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
        return r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 1.0)
    end
end

function UpdateGridColors()
    local grid_value = math.floor(settings.grid_color * 255)
    
    -- Grid lijnen
    reaper.SetThemeColor("col_gridlines", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines2", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines3", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr1_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr2_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.UpdateArrange()
end

function UpdateBackgroundColors()
    local bg_value = math.floor(settings.bg_brightness * 128)
    -- Achtergrond kleuren
    reaper.SetThemeColor("col_arrangebg", reaper.ColorToNative(bg_value, bg_value, bg_value), 0)
    reaper.SetThemeColor("col_tr1_bg", reaper.ColorToNative(bg_value + 10, bg_value + 10, bg_value + 10), 0)
    reaper.SetThemeColor("col_tr2_bg", reaper.ColorToNative(bg_value + 5, bg_value + 5, bg_value + 5), 0)
    reaper.SetThemeColor("selcol_tr1_bg", reaper.ColorToNative(bg_value + 20, bg_value + 20, bg_value + 20), 0)
    reaper.SetThemeColor("selcol_tr2_bg", reaper.ColorToNative(bg_value + 15, bg_value + 15, bg_value + 15), 0)
    reaper.UpdateArrange()
end

function ToggleColors()
    settings.custom_colors_enabled = not settings.custom_colors_enabled
    if settings.custom_colors_enabled then
        UpdateGridColors()
        UpdateBackgroundColors()
    else
        -- Reset naar originele kleuren
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
    end
    reaper.UpdateArrange()
end

function ResetSettings()
    -- Reset naar default waardes
    for k, v in pairs(default_settings) do
        settings[k] = v
    end
    
    -- Reset de custom colors als die aan stonden
    if settings.custom_colors_enabled then
        ToggleColors()
    end
    
    SaveSettings()
end

function ShowSettingsWindow()
    if not settings_visible then return end
    r.ImGui_SetNextWindowSize(ctx, 460, 310)
    -- Style aanpassingen
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 8.0)
    -- Donkerdere kleur aanpassingen
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x333333FF)        
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x444444FF) 
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x555555FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x999999FF)     
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xAAAAAAFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0x999999FF)      
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x333333FF)         
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x444444FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x555555FF)   
    local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoFocusOnAppearing()


    r.ImGui_PushFont(ctx, settings_font)
    local visible, open = r.ImGui_Begin(ctx, 'Track Names Settings', true, window_flags)
    if visible then
        if r.ImGui_Button(ctx, "X") then
            r.SetExtState("TK_TRACKNAMES", "settings_visible", "0", false)
        end
    
        local changed
        r.ImGui_SameLine(ctx)
        changed, settings.show_parent_tracks = r.ImGui_Checkbox(ctx, "Parent", settings.show_parent_tracks)
        r.ImGui_SameLine(ctx)
        changed, settings.show_child_tracks = r.ImGui_Checkbox(ctx, "Child", settings.show_child_tracks)
        r.ImGui_SameLine(ctx)
        changed, settings.show_first_fx = r.ImGui_Checkbox(ctx, "first FX", settings.show_first_fx)
        r.ImGui_SameLine(ctx)
        changed, settings.show_track_colors = r.ImGui_Checkbox(ctx, "track colors", settings.show_track_colors)
        r.ImGui_SameLine(ctx)
        changed, settings.show_label = r.ImGui_Checkbox(ctx, "label", settings.show_label)
        r.ImGui_SameLine(ctx)
        changed, settings.text_centered = r.ImGui_Checkbox(ctx, "Center", settings.text_centered)
        r.ImGui_Separator(ctx)
        r.ImGui_PushItemWidth(ctx, 340)
        if not settings.show_track_colors then
            r.ImGui_BeginDisabled(ctx)
        end
        changed, settings.overlay_alpha = r.ImGui_SliderDouble(ctx, "Color Intensity", settings.overlay_alpha, 0.0, 1.0)
        if not settings.show_track_colors then
            r.ImGui_EndDisabled(ctx)
        end
        if not settings.show_label then
            r.ImGui_BeginDisabled(ctx)
        end
        changed, settings.label_alpha = r.ImGui_SliderDouble(ctx, "Label opacity", settings.label_alpha, 0.0, 1.0)
        
        if r.ImGui_BeginCombo(ctx, "Label color", settings.label_color_mode == 1 and "Black" or "White") then
            if r.ImGui_Selectable(ctx, "Black", settings.label_color_mode == 1) then
                settings.label_color_mode = 1
            end
            if r.ImGui_Selectable(ctx, "White", settings.label_color_mode == 2) then
                settings.label_color_mode = 2
            end
            r.ImGui_EndCombo(ctx)
        end
        if not settings.show_label then
            r.ImGui_EndDisabled(ctx)
        end
        local main_hwnd = r.GetMainHwnd()
        local arrange = r.JS_Window_FindChildByID(main_hwnd, 1000)
        local _, _, arrange_w, _ = GetBounds(arrange)
        changed, settings.horizontal_offset = r.ImGui_SliderInt(ctx, "Horizontal offset", settings.horizontal_offset, 0, arrange_w)
        changed, settings.vertical_offset = r.ImGui_SliderInt(ctx, "Vertical offset", settings.vertical_offset, -200, 200)
        if r.ImGui_BeginCombo(ctx, "Font", fonts[settings.selected_font]) then
            for i, font_name in ipairs(fonts) do
                local is_selected = (settings.selected_font == i)
                if r.ImGui_Selectable(ctx, font_name, is_selected) then
                    settings.selected_font = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_BeginCombo(ctx, "Text color", color_modes[settings.color_mode]) then
            for i, color_name in ipairs(color_modes) do
                local is_selected = (settings.color_mode == i)
                if r.ImGui_Selectable(ctx, color_name, is_selected) then
                    settings.color_mode = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        changed, settings.text_opacity = r.ImGui_SliderDouble(ctx, "Text opacity", settings.text_opacity, 0.0, 1.0)
        if settings.custom_colors_enabled then
            changed_grid, settings.grid_color = r.ImGui_SliderDouble(ctx, "Grid Color", settings.grid_color, 0.0, 1.0)
            changed_bg, settings.bg_brightness = r.ImGui_SliderDouble(ctx, "Bg Brightness", settings.bg_brightness, 0.0, 1.0)
            
            if changed_grid then UpdateGridColors() end
            if changed_bg then UpdateBackgroundColors() end
        end 
        r.ImGui_PopItemWidth(ctx)
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, settings.custom_colors_enabled and "Reset Colors" or "Enable Custom Colors") then
            reaper.Undo_BeginBlock()
            ToggleColors()
            reaper.Undo_EndBlock("Toggle Custom Grid and Background Colors", -1)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Reset All Settings") then
            ResetSettings()
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Save Settings") then
            SaveSettings()
        end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 5)
    r.ImGui_PopStyleColor(ctx, 9)
end

function IsTrackVisible(track)
    local MIN_TRACK_HEIGHT = 10
    local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH")
    
    if track_height <= MIN_TRACK_HEIGHT then
        return false
    end
    
    local parent = r.GetParentTrack(track)
    while parent do
        local parent_height = r.GetMediaTrackInfo_Value(parent, "I_TCPH")
        if parent_height <= MIN_TRACK_HEIGHT then
            return false
        end
        parent = r.GetParentTrack(parent)
    end
    return true
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

function GetBounds(hwnd)
    local _, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
    
    -- Check voor MacOS
    if reaper.GetOS():match("^OSX") then
        local screen_height = r.ImGui_GetMainViewport(ctx).WorkSize.y
        top = screen_height - bottom
        bottom = screen_height - top
    end
    
    return left, top, right-left, bottom-top
end

function loop()
    settings_visible = r.GetExtState("TK_TRACKNAMES", "settings_visible") == "1"
    if not (ctx and r.ImGui_ValidatePtr(ctx, 'ImGui_Context*')) then
        ctx = r.ImGui_CreateContext('Track Names')
        font_objects = {}
        for _, font_name in ipairs(fonts) do
            local font = r.ImGui_CreateFont(font_name, 18)
            table.insert(font_objects, font)
            r.ImGui_Attach(ctx, font)
        end
        settings_font = r.ImGui_CreateFont('sans-serif', 14)
        r.ImGui_Attach(ctx, settings_font)
    end
    
    local current_project = reaper.EnumProjects(-1)
    if current_project ~= last_project then
        RefreshProjectState()
        last_project = current_project
    end
    local track_count = reaper.CountTracks(0)
    
    if current_project ~= last_project or track_count ~= last_track_count then
        RefreshProjectState()
        last_project = current_project
        last_track_count = track_count
    end

    local current_time = reaper.time_precise()
    local main_hwnd = r.GetMainHwnd()
    local arrange = r.JS_Window_FindChildByID(main_hwnd, 1000)
    local arrange_x, arrange_y, arrange_w, arrange_height = GetBounds(arrange)
    local scale = r.ImGui_GetWindowDpiScale(ctx)

    
    local adjusted_width = arrange_w - 20
    local adjusted_height = arrange_height
    
    if current_time - last_update_time >= update_interval then
        if arrange and arrange_w > 0 and arrange_height > 0 then
            left = arrange_x
            top = arrange_y
            if scale == 1.0 then
                right = arrange_x + (adjusted_width * scale)
                bottom = arrange_y + (adjusted_height * scale)
            else
                right = arrange_x + adjusted_width
                bottom = arrange_y + adjusted_height
            end
        end
        last_update_time = current_time
    end
       
                    local flags = 
                        r.ImGui_WindowFlags_NoTitleBar() |
                        r.ImGui_WindowFlags_NoResize() |
                        r.ImGui_WindowFlags_NoNav() |
                        r.ImGui_WindowFlags_NoScrollbar() | 
                        r.ImGui_WindowFlags_NoBackground() |
                        r.ImGui_WindowFlags_NoDecoration() | 
                        r.ImGui_WindowFlags_NoFocusOnAppearing() |
                        r.ImGui_WindowFlags_NoDocking() 

                        if settings.show_track_colors then
                            local overlay_flags = flags |
                            r.ImGui_WindowFlags_NoInputs() |
                            r.ImGui_WindowFlags_NoMove() | 
                            r.ImGui_WindowFlags_NoSavedSettings() |
                            r.ImGui_WindowFlags_AlwaysAutoResize()           
                       
                            r.ImGui_SetNextWindowPos(ctx, 0, 0)
                            
                            -- Window size aanpassing voor macOS
                            local window_width
                            if reaper.GetOS():match("^OSX") then
                                window_width = arrange_w
                            else
                                window_width = right
                            end
                            r.ImGui_SetNextWindowSize(ctx, window_width, arrange_height + 100)
                            
                            r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
                            local header_height = r.GetMainHwnd() and 0
                            local overlay_visible, _ = r.ImGui_Begin(ctx, 'Track Overlay', true, overlay_flags)
                            if overlay_visible then
                                local draw_list = r.ImGui_GetWindowDrawList(ctx)
                                local track_count = r.CountTracks(0)

                            for i = 0, track_count - 1 do
                                local track = r.GetTrack(0, i)
                                local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY")
                                local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH")
                                
                                local color = r.GetTrackColor(track)
                                if color ~= 0 then
                                    local r_val = (color & 0xFF) / 255
                                    local g_val = ((color >> 8) & 0xFF) / 255
                                    local b_val = ((color >> 16) & 0xFF) / 255
                                    local overlay_color = r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, settings.overlay_alpha)

                                    if track_y < arrange_height and track_y + track_height > 0 then
                                        local overlay_top = math.max((top + track_y + header_height) / scale, arrange_y / scale)
                                        local overlay_bottom = math.min((top + track_y + track_height + header_height) / scale, (arrange_y + arrange_height) / scale)
                                        
                                        r.ImGui_DrawList_AddRectFilled(draw_list,
                                            left / scale,
                                            overlay_top,
                                            right / scale,
                                            overlay_bottom,
                                            overlay_color)
                                    end    
                                end
                            end
                            r.ImGui_End(ctx)
                        end
                    end
            

                local text_flags = flags | r.ImGui_WindowFlags_NoInputs() 
                r.ImGui_SetNextWindowPos(ctx, arrange_x / scale, arrange_y / scale)
                r.ImGui_SetNextWindowSize(ctx, adjusted_width / scale, adjusted_height / scale)                  
                r.ImGui_PushFont(ctx, font_objects[settings.selected_font])
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0.0)
                r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
                local visible, open = r.ImGui_Begin(ctx, 'Track Names Display', true, text_flags)
                
                if visible then
                    local draw_list = r.ImGui_GetWindowDrawList(ctx)
                    local track_count = r.CountTracks(0)
                    local max_width = 0
                    for i = 0, track_count - 1 do
                        local track = r.GetTrack(0, i)
                        local _, track_name = r.GetTrackName(track)
                        local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                        max_width = math.max(max_width, text_width)
                    end
                    for i = 0, track_count - 1 do
                        local track = r.GetTrack(0, i)
                        local track_visible = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1
                        
                        if track_visible and IsTrackVisible(track) then
                            local is_parent = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                            local is_child = r.GetParentTrack(track) ~= nil
                            
                            if (is_parent and settings.show_parent_tracks) or
                               (is_child and settings.show_child_tracks) or
                               (not is_parent and not is_child) then
                               
                                local _, track_name = r.GetTrackName(track)
                                local display_name = track_name
                                    
                                if settings.show_first_fx then
                                    local fx_count = r.TrackFX_GetCount(track)
                                    if fx_count > 0 then
                                        local _, fx_name = r.TrackFX_GetFXName(track, 0, "")
                                        fx_name = fx_name:gsub("^[^:]+:%s*", "")
                                        display_name = display_name .. " - " .. fx_name .. ""
                                    end
                                end
                                    
                                local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY")
                                local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH")
                                local text_color = GetTextColor(track)
                                text_color = (text_color & 0xFFFFFF00) | (math.floor(settings.text_opacity * 255))
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                                local scale_offset = -5 * ((scale - 1) / 0.5)
                                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)
                                local text_y = track_y + (track_height * 0.5) - (18 * 0.5) + settings.vertical_offset + scale_offset
                                if settings.text_centered then
                                    local current_width = r.ImGui_CalcTextSize(ctx, display_name)
                                    local offset = (max_width - current_width) / 2
                                    r.ImGui_SetCursorPos(ctx, settings.horizontal_offset + offset, text_y / scale)
                                else
                                    r.ImGui_SetCursorPos(ctx, settings.horizontal_offset, text_y / scale)
                                end
                                
                
                                if settings.show_label then
                                    local text_width = r.ImGui_CalcTextSize(ctx, display_name)
                                    local label_padding = 10
                                    local label_color = settings.label_color_mode == 1
                                        and r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, settings.label_alpha)
                                        or r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, settings.label_alpha)
                                    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
                                    
                                    r.ImGui_DrawList_AddRectFilled(
                                        draw_list,
                                        cursor_x - label_padding,
                                        cursor_y - 1,
                                        cursor_x + text_width + label_padding,
                                        cursor_y + 19,
                                        label_color,
                                        4.0
                                    )
                                end              
                                if settings.text_centered then
                                    local current_width = r.ImGui_CalcTextSize(ctx, display_name)
                                    local offset = (max_width - current_width) / 2
                                    r.ImGui_SetCursorPos(ctx, settings.horizontal_offset + offset, text_y / scale)
                                else
                                    r.ImGui_SetCursorPos(ctx, settings.horizontal_offset, text_y / scale)
                                end
                                
                                r.ImGui_Text(ctx, display_name)
                                r.ImGui_PopStyleVar(ctx)              
                                r.ImGui_PopStyleColor(ctx)
                            end
                        end
                    end                    
                    r.ImGui_End(ctx)
                end              
                r.ImGui_PopStyleVar(ctx)
                r.ImGui_PopStyleColor(ctx, 2)
                r.ImGui_PopFont(ctx)
    if settings_visible then
        ShowSettingsWindow()
    end            
    if open then
        r.defer(loop)
    end
end

local success = pcall(function()
    LoadSettings()
    if settings.custom_colors_enabled then
        UpdateGridColors()
        UpdateBackgroundColors()
    end
    r.defer(loop)
end)
if not success then
    r.ShowConsoleMsg("Script error occurred\n")
end

