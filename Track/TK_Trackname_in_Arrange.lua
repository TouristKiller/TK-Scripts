-- @description TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 0.1.1:
-- @changelog:
--[[        * Bugfix: Fixed vertical offset for Linux (Sorry, can not test it myself)
            * Extra layer of transparency for the text background
]]-- --------------------------------------------------------------------------------       


local r = reaper
local ctx = r.ImGui_CreateContext('Track Names')

-- Settings
local settings = {
    show_all_tracks = false,
    show_first_fx = false,  -- nieuwe instelling
    horizontal_offset = 100,
    vertical_offset = 0,
    selected_font = 1,
    color_mode = 1
}


-- Lists
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

-- Font objects
local font_objects = {}
for _, font_name in ipairs(fonts) do
    local font = r.ImGui_CreateFont(font_name, 18)
    table.insert(font_objects, font)
    r.ImGui_Attach(ctx, font)
end

-- Settings font
local settings_font = r.ImGui_CreateFont('sans-serif', 14)
r.ImGui_Attach(ctx, settings_font)

function SaveSettings()
    local section = "TK_TRACKNAMES"
    r.SetExtState(section, "show_all_tracks", settings.show_all_tracks and "1" or "0", true)
    r.SetExtState(section, "show_first_fx", settings.show_first_fx and "1" or "0", true)  -- nieuwe regel
    r.SetExtState(section, "horizontal_offset", tostring(settings.horizontal_offset), true)
    r.SetExtState(section, "vertical_offset", tostring(settings.vertical_offset), true)
    r.SetExtState(section, "selected_font", tostring(settings.selected_font), true)
    r.SetExtState(section, "color_mode", tostring(settings.color_mode), true)
end

function LoadSettings()
    local section = "TK_TRACKNAMES"
    settings.show_all_tracks = r.GetExtState(section, "show_all_tracks") == "1"
    settings.show_first_fx = r.GetExtState(section, "show_first_fx") == "1"  -- nieuwe regel
    settings.horizontal_offset = tonumber(r.GetExtState(section, "horizontal_offset")) or 100
    settings.vertical_offset = tonumber(r.GetExtState(section, "vertical_offset")) or 0
    settings.selected_font = tonumber(r.GetExtState(section, "selected_font")) or 1
    settings.color_mode = tonumber(r.GetExtState(section, "color_mode")) or 1
end


function GetTextColor(track)
    if settings.color_mode == 1 then
        return 0xFFFFFFFF  -- White
    elseif settings.color_mode == 2 then
        return 0x000000FF  -- Black
    else
        local color = r.GetTrackColor(track)
        local r_val = (color & 0xFF) / 255
        local g_val = ((color >> 8) & 0xFF) / 255
        local b_val = ((color >> 16) & 0xFF) / 255
        return r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, 1.0)
    end
end

function ShowSettingsWindow()
    local window_flags = r.ImGui_WindowFlags_NoTitleBar()
    r.ImGui_PushFont(ctx, settings_font)
    
    local visible, open = r.ImGui_Begin(ctx, 'Track Names Settings', true, window_flags)
    if visible then
        local changed
        
        -- Checkboxes
        changed, settings.show_all_tracks = r.ImGui_Checkbox(ctx, "Show all tracks", settings.show_all_tracks)
        r.ImGui_SameLine(ctx)
        changed, settings.show_first_fx = r.ImGui_Checkbox(ctx, "Show first FX", settings.show_first_fx)
        
        -- Sliders
        changed, settings.horizontal_offset = r.ImGui_SliderInt(ctx, "Horizontal offset", settings.horizontal_offset, 100, 600)
        changed, settings.vertical_offset = r.ImGui_SliderInt(ctx, "Vertical offset", settings.vertical_offset, -100, 100)
        
        -- Dropdowns
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

        -- Save button
        if r.ImGui_Button(ctx, "Save Settings") then
            SaveSettings()
        end
        
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
end

local function getArrangeViewHeight()
    local arrange_hwnd = reaper.JS_Window_FindChildByID(main_hwnd, 1000)
    if arrange_hwnd then
        local retval, left, top, right, bottom = reaper.JS_Window_GetClientRect(arrange_hwnd)
        if retval then
            return bottom - top
        end
    end
    return nil
end

function loop()
    local flags = r.ImGui_WindowFlags_NoTitleBar() | 
                 r.ImGui_WindowFlags_NoResize() | 
                 r.ImGui_WindowFlags_NoMove() | 
                 r.ImGui_WindowFlags_NoScrollbar() | 
                 r.ImGui_WindowFlags_NoBackground() |
                 r.ImGui_WindowFlags_NoInputs() |
                 r.ImGui_WindowFlags_NoDecoration() |
                 r.ImGui_WindowFlags_NoNav()
    
                 local main_hwnd = r.GetMainHwnd()
                 local arrange = r.JS_Window_FindChildByID(main_hwnd, 1000)
                 local retval, left, top, right, bottom = r.JS_Window_GetClientRect(arrange)
                 local arrange_height = bottom - top
                 local scale = r.ImGui_GetWindowDpiScale(ctx)
                 local base_y = 75
                 if r.GetOS():match("Linux") then
                     base_y = base_y * scale
                 end
                 base_y = base_y + settings.vertical_offset
                 local h_offset = settings.horizontal_offset / scale
                 
                 ShowSettingsWindow()
                 
                 r.ImGui_SetNextWindowPos(ctx, h_offset, base_y)
                 r.ImGui_SetNextWindowSize(ctx, 1200 / scale, arrange_height / scale)
    
    r.ImGui_PushFont(ctx, font_objects[settings.selected_font])
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
    local visible, open = r.ImGui_Begin(ctx, 'Track Names Display', true, flags)
    
    if visible then
        local track_count = r.CountTracks(0)
        
        for i = 0, track_count - 1 do
            local track = r.GetTrack(0, i)
            local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
            
            -- In de loop functie, waar we de track naam weergeven:
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
                
                local text_y = track_y + (track_height * 0.75)
                r.ImGui_SetCursorPos(ctx, settings.horizontal_offset / scale, text_y / scale)
                r.ImGui_Text(ctx, display_name)
                
                r.ImGui_PopStyleColor(ctx)
            end

        end
        
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 2)
    r.ImGui_PopFont(ctx)
    
    if open then
        r.defer(loop)
    end
end

LoadSettings()
r.defer(loop)
