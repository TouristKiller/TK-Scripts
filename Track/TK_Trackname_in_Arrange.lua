-- @description TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 0.1.7:
-- @changelog:
--[[            
* Impelement Edgemeal's suggestion for users with tcp on the right
* Grid + Background adjustments 
* Settings does not open when starting script /open with S button bottom right corner

TODO (for version 0.1.7):


            
]]-- --------------------------------------------------------------------------------       

local r = reaper
local ctx = r.ImGui_CreateContext('Track Names')
local settings_visible = false

-- Settings
local settings = {
    show_all_tracks = false,
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
}

local fonts = {
    "Arial",
    "Helvetica",
    "Verdana",
    "Tahoma",
    "Times New Roman",
    "Georgia",
    "Courier New",
    "Trebuchet MS",
    "Impact"
}

local color_modes = {
    "White",
    "Black",
    "Track Color"
}

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
    -- Bestaande settings
    r.SetExtState(section, "show_all_tracks", settings.show_all_tracks and "1" or "0", true)
    r.SetExtState(section, "show_first_fx", settings.show_first_fx and "1" or "0", true)
    r.SetExtState(section, "horizontal_offset", tostring(settings.horizontal_offset), true)
    r.SetExtState(section, "vertical_offset", tostring(settings.vertical_offset), true)
    r.SetExtState(section, "selected_font", tostring(settings.selected_font), true)
    r.SetExtState(section, "color_mode", tostring(settings.color_mode), true)
    r.SetExtState(section, "overlay_alpha", tostring(settings.overlay_alpha), true)
    r.SetExtState(section, "show_track_colors", settings.show_track_colors and "1" or "0", true)
    
    -- Nieuwe grid settings
    r.SetExtState(section, "grid_color", tostring(settings.grid_color), true)
    r.SetExtState(section, "bg_brightness", tostring(settings.bg_brightness), true)
    r.SetExtState(section, "custom_colors_enabled", settings.custom_colors_enabled and "1" or "0", true)
end

function LoadSettings()
    local section = "TK_TRACKNAMES"
    -- Bestaande settings
    settings.show_all_tracks = r.GetExtState(section, "show_all_tracks") == "1"
    settings.show_first_fx = r.GetExtState(section, "show_first_fx") == "1"
    settings.horizontal_offset = tonumber(r.GetExtState(section, "horizontal_offset")) or 0
    settings.vertical_offset = tonumber(r.GetExtState(section, "vertical_offset")) or 0
    settings.selected_font = tonumber(r.GetExtState(section, "selected_font")) or 1
    settings.color_mode = tonumber(r.GetExtState(section, "color_mode")) or 1
    settings.overlay_alpha = tonumber(r.GetExtState(section, "overlay_alpha")) or 0.1
    settings.show_track_colors = r.GetExtState(section, "show_track_colors") == "1"
    
    -- Nieuwe grid settings
    settings.grid_color = tonumber(r.GetExtState(section, "grid_color")) or 0.0
    settings.bg_brightness = tonumber(r.GetExtState(section, "bg_brightness")) or 0.2
    settings.custom_colors_enabled = r.GetExtState(section, "custom_colors_enabled") == "1"
end


function GetTextColor(track)
    if settings.color_mode == 1 then
        return 0xFFFFFFFF 
    elseif settings.color_mode == 2 then
        return 0x000000FF  
    else
        local color = r.GetTrackColor(track)
        local r_val = (color & 0xFF) / 255
        local g_val = ((color >> 8) & 0xFF) / 255
        local b_val = ((color >> 16) & 0xFF) / 255
        return r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, 1.0)
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

function ShowSettingsWindow()
    if not settings_visible then return end
        local window_flags = r.ImGui_WindowFlags_NoTitleBar()
        r.ImGui_PushFont(ctx, settings_font)
        
        local visible, open = r.ImGui_Begin(ctx, 'Track Names Settings', true, window_flags)
        if visible then
            if r.ImGui_Button(ctx, "X") then
                settings_visible = false
            end
            local changed
            r.ImGui_SameLine(ctx)
            -- Checkboxes
            changed, settings.show_all_tracks = r.ImGui_Checkbox(ctx, "Show all", settings.show_all_tracks)
            r.ImGui_SameLine(ctx)
            changed, settings.show_first_fx = r.ImGui_Checkbox(ctx, "Show first FX", settings.show_first_fx)
            r.ImGui_SameLine(ctx)
            changed, settings.show_track_colors = r.ImGui_Checkbox(ctx, "Show track colors", settings.show_track_colors)
        
            -- Alleen alpha slider tonen als track colors aan staat
            if settings.show_track_colors then
                changed, settings.overlay_alpha = r.ImGui_SliderDouble(ctx, "Color Intensity", settings.overlay_alpha, 0.0, 1.0)
            end
            local main_hwnd = r.GetMainHwnd()
            local arrange = r.JS_Window_FindChildByID(main_hwnd, 1000)
            local _, _, arrange_w, _ = GetBounds(arrange)
            -- Sliders
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
            if settings.custom_colors_enabled then
                local changed_grid
                local changed_bg
                
                changed_grid, settings.grid_color = r.ImGui_SliderDouble(ctx, "Grid Color", settings.grid_color, 0.0, 1.0)
                changed_bg, settings.bg_brightness = r.ImGui_SliderDouble(ctx, "Background Brightness", settings.bg_brightness, 0.0, 1.0)
                
                if changed_grid then UpdateGridColors() end
                if changed_bg then UpdateBackgroundColors() end
            end
            
            
            if r.ImGui_Button(ctx, settings.custom_colors_enabled and "Reset Colors" or "Enable Custom Colors") then
                reaper.Undo_BeginBlock()
                ToggleColors()
                reaper.Undo_EndBlock("Toggle Custom Grid and Background Colors", -1)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Save Settings") then
                SaveSettings()
            end
            
            r.ImGui_End(ctx)
        end
        r.ImGui_PopFont(ctx)
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

function GetBounds(hwnd)
    local _, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
    return left, top, right-left, bottom-top
end

function loop()
    local main_hwnd = r.GetMainHwnd()
    local arrange = r.JS_Window_FindChildByID(main_hwnd, 1000)
    local arrange_x, arrange_y, arrange_w, arrange_height = GetBounds(arrange)
    local scale = r.ImGui_GetWindowDpiScale(ctx)
    
   
    local adjusted_width = arrange_w - 20
    local adjusted_height = arrange_height 
    local left = arrange_x
    local top = arrange_y
    local bottom
    
    if scale == 1.0 then
        right = arrange_x + (adjusted_width * scale)
        bottom = arrange_y + (adjusted_height * scale)
    else
        right = arrange_x + adjusted_width
        bottom = arrange_y + adjusted_height 
    end

    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_S()) and r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) then
        settings_visible = not settings_visible
    end
    
    local flags = r.ImGui_WindowFlags_NoTitleBar() | 
                 r.ImGui_WindowFlags_NoResize() | 
                 r.ImGui_WindowFlags_NoMove() | 
                 r.ImGui_WindowFlags_NoScrollbar() | 
                 r.ImGui_WindowFlags_NoBackground() |
                 r.ImGui_WindowFlags_NoInputs() |
                 r.ImGui_WindowFlags_NoDecoration() |
                 r.ImGui_WindowFlags_NoNav()
                 
    -- Settings knop
    local button_flags = r.ImGui_WindowFlags_NoTitleBar() |
                        r.ImGui_WindowFlags_NoResize() |
                        r.ImGui_WindowFlags_NoMove() |
                        r.ImGui_WindowFlags_NoMove() | 
                        r.ImGui_WindowFlags_NoScrollbar() | 
                        r.ImGui_WindowFlags_NoBackground() |
                        r.ImGui_WindowFlags_NoDecoration() 
                        r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
                        r.ImGui_SetNextWindowPos(ctx, (arrange_x + arrange_w - 100) / scale, (arrange_y + arrange_height - 100) / scale)
                        r.ImGui_SetNextWindowSize(ctx, 20 / scale, 20 / scale)
                        local button_visible = r.ImGui_Begin(ctx, '##Settings Button', true, button_flags)
                        if button_visible then
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 10.0)
                            r.ImGui_PushFont(ctx, settings_font)
                            if r.ImGui_Button(ctx, "S") then
                                settings_visible = not settings_visible
                            end
                            r.ImGui_PopFont(ctx)
                            r.ImGui_PopStyleVar(ctx)
                            r.ImGui_End(ctx)
                        end

                        if settings_visible then
                            ShowSettingsWindow()
                        end

                        if settings.show_track_colors then
                            -- Overlay window voor gekleurde tracks
                            local overlay_flags = flags | 
                            r.ImGui_WindowFlags_NoFocusOnAppearing() |
                            r.ImGui_WindowFlags_NoDocking() |
                            r.ImGui_WindowFlags_NoNav() |
                            r.ImGui_WindowFlags_NoSavedSettings()

                            r.ImGui_SetNextWindowPos(ctx, 0, 0)
                            r.ImGui_SetNextWindowSize(ctx, right, arrange_height + 100)
                            r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)

                            local overlay_visible, _ = r.ImGui_Begin(ctx, 'Track Overlay', true, overlay_flags)
                            if overlay_visible then
                            local draw_list = r.ImGui_GetWindowDrawList(ctx)
                            local track_count = r.CountTracks(0)
                            local header_height = r.GetMainHwnd() and 0

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

                r.ImGui_SetNextWindowPos(ctx, arrange_x / scale, arrange_y / scale)
                r.ImGui_SetNextWindowSize(ctx, adjusted_width / scale, adjusted_height / scale)                 
                 
                r.ImGui_PushFont(ctx, font_objects[settings.selected_font])
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0.0)
                r.ImGui_SetNextWindowBgAlpha(ctx, 0.0)
                local visible, open = r.ImGui_Begin(ctx, 'Track Names Display', true, flags)
                
                if visible then
                    local track_count = r.CountTracks(0)
                    
                    for i = 0, track_count - 1 do
                        local track = r.GetTrack(0, i)
                        local track_visible = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1
                        
                        if track_visible and IsTrackVisible(track) then
                            local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                            
                            if settings.show_all_tracks or is_folder then
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
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)

                                local text_y = track_y + (track_height * 0.5) + settings.vertical_offset
                                r.ImGui_SetCursorPos(ctx, settings.horizontal_offset, text_y / scale)

                                r.ImGui_Text(ctx, display_name)                            
                                r.ImGui_PopStyleColor(ctx)                            
                            end
                        end
                    end                    
                    r.ImGui_End(ctx)
                end
                
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_PopStyleColor(ctx, 2)
         r.ImGui_PopFont(ctx)    
    if open then
        r.defer(loop)
    end
end

LoadSettings()
r.defer(loop)
