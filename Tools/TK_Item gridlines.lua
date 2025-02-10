-- @description TK_Item gridlines
-- @author TouristKiller
-- @version 0.1.3
-- @changelog 
--[[
+ Credits to Etalon for the code to handle drawing focus...awesome!
+ Improved beat numbering
+ impoved overall behaviour
+ UI changes
]]--

local r = reaper
local ImGui
local script_running = true

if r.APIExists('ImGui_GetBuiltinPath') then
    if not r.ImGui_GetBuiltinPath then return r.MB('This script requires ReaImGui extension','',0) end
    package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
    ImGui = require 'imgui' '0.9'
else
    return r.MB('This script requires ReaImGui extension 0.9+','',0)
end

local ctx = r.ImGui_CreateContext('TK_Item_Gridlines')
local font = ImGui.CreateFont('Arial', 14)
local beat_font = ImGui.CreateFont('Arial', 10)
ImGui.Attach(ctx, font)
ImGui.Attach(ctx, beat_font)

local MIN_NUMBER_SPACING = 25

local LEFT, TOP, RIGHT, BOT = 0, 0, 0, 0
local OLD_VAL = 0
local scroll_size = 0
local screen_scale = nil
local ImGuiScale_saved = nil
local main = r.GetMainHwnd()
local arrange = r.JS_Window_FindChildByID(main, 0x3E8)

local last_tempo = 0
local last_numerator = 0
local last_denominator = 0
local cached_grid_positions = {}
local show_full_grid = false
local hasDrawingFocusBeenHandled = false
local manual_selection_mode = false

local config = {
    line_thickness = 1.0,
    opacity = 0.8,
    color = 0x000000FF,
    text_color = 0x000000FF,
    auto_grid = true,  
    numerator = 4,  
    denominator = 4,  
    show_beat_numbers = true,
    all_items_active = false,
    measure_only = false,
    show_horizontal_lines = true
}

local compound_time_signatures = {
    [6] = { [8] = {6, 6}, [4] = {6, 4} },
    [9] = { [8] = {9, 6}, [4] = {9, 4} },
    [12] = { [8] = {12, 6}, [4] = {12, 4} }
}

local colors = {
    {"Black", 0x000000FF},
    {"White", 0xFFFFFFFF},
    {"Red", 0xFF0000FF},
    {"Blue", 0x0000FFFF},
    {"Orange", 0xFF8C00FF},
    {"Green", 0x00FF00FF},
    {"Yellow", 0xFFFF00FF},
    {"Purple", 0x800080FF}
}

local flags = ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoResize | ImGui.WindowFlags_NoNav | ImGui.WindowFlags_NoScrollbar |
              ImGui.WindowFlags_NoDecoration | ImGui.WindowFlags_NoDocking | ImGui.WindowFlags_NoBackground | ImGui.WindowFlags_NoInputs |
              ImGui.WindowFlags_NoMove | ImGui.WindowFlags_NoSavedSettings | ImGui.WindowFlags_NoMouseInputs | ImGui.WindowFlags_NoFocusOnAppearing

function ShowConfigWindow()
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 12.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_PopupRounding, 6.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabRounding, 12.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_GrabMinSize, 8.0)
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x111111D9)  -- D9 = 85% opaque
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x333333FF)        
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x444444FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x555555FF)  
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrab, 0x999999FF)    
    ImGui.PushStyleColor(ctx, ImGui.Col_SliderGrabActive, 0xAAAAAAFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, 0x999999FF)      
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x333333FF)        
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x444444FF)  
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x555555FF)
    ImGui.PushFont(ctx, font)
    local window_flags = ImGui.WindowFlags_NoResize | ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_TopMost
    local config_visible, config_open = ImGui.Begin(ctx, 'TK Item Gridlines', true, window_flags)    
    if config_visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)  -- Helder rood
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "ITEM GRIDLINES")
        local window_width = r.ImGui_GetWindowWidth(ctx)
        local column_width = window_width / 5
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 25)
        r.ImGui_SetCursorPosY(ctx, 6)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
        if ImGui.Button(ctx, "##close", 14, 14) then
            script_running = false  -- Dit stopt het hele script
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)
        ImGui.PushItemWidth(ctx, 250)
        changed, config.line_thickness = ImGui.SliderDouble(ctx, 'Thickness', config.line_thickness, 0.1, 5.0, '%.3f')
        changed, config.opacity = ImGui.SliderDouble(ctx, 'Opacity', config.opacity, 0.0, 1.0, '%.3f')       
        ImGui.PopItemWidth(ctx)
        local current_color = "Black"
        local current_text_color = "Black"
        for _, color_data in ipairs(colors) do
            if color_data[2] == config.color then
                current_color = color_data[1]
                break
            end
        end
        for _, color_data in ipairs(colors) do
            if color_data[2] == config.text_color then
                current_text_color = color_data[1]
                break
            end
        end
        ImGui.PushItemWidth(ctx, 122)
        if ImGui.BeginCombo(ctx, "Grid", current_color) then
            for _, color_data in ipairs(colors) do
                local is_selected = (config.color == color_data[2])
                if ImGui.Selectable(ctx, color_data[1], is_selected) then
                    config.color = color_data[2]
                end
            end
            ImGui.EndCombo(ctx)
        end
        ImGui.SameLine(ctx)
        if ImGui.BeginCombo(ctx, "Text", current_text_color) then
            for _, color_data in ipairs(colors) do
                local is_selected = (config.text_color == color_data[2])
                if ImGui.Selectable(ctx, color_data[1], is_selected) then
                    config.text_color = color_data[2]
                end
            end
            ImGui.EndCombo(ctx)
        end
        ImGui.PopItemWidth(ctx)
        ImGui.Separator(ctx)
        ImGui.PushItemWidth(ctx, 80)
        local display_numerator = config.denominator
        local display_denominator = config.numerator             
        local changed_num, new_num = ImGui.InputInt(ctx, 'Numerator##num', display_numerator)
        ImGui.SameLine(ctx)
        local changed_den, new_den = ImGui.InputInt(ctx, 'Denominator##den', display_denominator)       
        if changed_num then config.denominator = new_num end
        if changed_den then config.numerator = new_den end
        ImGui.PopItemWidth(ctx)
        ImGui.Separator(ctx)        
        if all_items_active then
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x00FF00FF)
            if ImGui.Button(ctx, "All Items", 60) then 
                all_items_active = false
                r.Main_OnCommand(40289, 0)  -- Unselect all items
                
            end
            ImGui.PopStyleColor(ctx)
        else
            if ImGui.Button(ctx, "All Items", 60) then 
                all_items_active = true
                show_full_grid = false  -- Zet full grid uit als all items aan gaat
                local start_time, end_time = r.GetSet_ArrangeView2(0, false, 0, 0)
                local num_items = r.CountMediaItems(0)
                if num_items > 0 then
                    for i = 0, num_items - 1 do
                        local item = r.GetMediaItem(0, i)
                        if item then
                            local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                            local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
                            local item_end = item_pos + item_len
                            if (item_pos <= end_time and item_end >= start_time) then
                                r.SetMediaItemSelected(item, true)
                            end
                        end
                    end
                    r.UpdateArrange()
                    hasDrawingFocusBeenHandled = false
                end
            end
        end
        ImGui.SameLine(ctx)   
        if show_full_grid then
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x00FF00FF)
            if ImGui.Button(ctx, "Full Grid", 60) then 
                show_full_grid = false
            end
            ImGui.PopStyleColor(ctx)
        else
            if ImGui.Button(ctx, "Full Grid", 60) then 
                show_full_grid = true
                all_items_active = false 
                r.Main_OnCommand(40289, 0) 
                hasDrawingFocusBeenHandled = false
            end
        end
        if show_full_grid then
            local changed, new_value = ImGui.Checkbox(ctx, "horizontal Lines", config.show_horizontal_lines)
            if changed then
                config.show_horizontal_lines = new_value
            end
        end
        ImGui.SameLine(ctx)           
        local changed, new_value = ImGui.Checkbox(ctx, "Measure Only", config.measure_only)
        if changed then
                config.measure_only = new_value
        end
        ImGui.SameLine(ctx)
        local changed, new_value = ImGui.Checkbox(ctx, "Numbers", config.show_beat_numbers)
        if changed then
                config.show_beat_numbers = new_value
        end
        ImGui.End(ctx)
    end    
    ImGui.PopStyleColor(ctx, 10)
    ImGui.PopStyleVar(ctx, 5)
    ImGui.PopFont(ctx)   
    return config_open
end

function GetArrangeView()
    local _, DPI_RPR = r.get_config_var_string("uiscale")
    scroll_size = 15 * DPI_RPR
    local _, orig_LEFT, orig_TOP, orig_RIGHT, orig_BOT = r.JS_Window_GetRect(arrange)
    local current_val = orig_TOP + orig_BOT + orig_LEFT + orig_RIGHT
    if current_val ~= OLD_VAL then
        OLD_VAL = current_val
        LEFT, TOP = ImGui.PointConvertNative(ctx, orig_LEFT, orig_TOP)
        RIGHT, BOT = ImGui.PointConvertNative(ctx, orig_RIGHT, orig_BOT)
    end
end

function SetWindowScale(ImGuiScale)
    screen_scale = r.GetOS():find("Win") and ImGuiScale or 1
end

function DrawOverArrange()
    GetArrangeView()
    ImGui.SetNextWindowPos(ctx, LEFT, TOP)
    ImGui.SetNextWindowSize(ctx, RIGHT - LEFT - scroll_size, BOT - TOP)
end

local function handleDrawingFocus() -- THANX Etalon for this code ;0) !!!
    if hasDrawingFocusBeenHandled then return end
    if ImGui.IsWindowAppearing(ctx) then return end
    local windowsToFocus = {}
    local arr = r.new_array({}, 1024)
    local ret = r.JS_Window_ArrayAllTop(arr)
    if ret >= 1 then
        local childs = arr.table()
        for j = 1, #childs do
            local hwnd = r.JS_Window_HandleFromAddress(childs[j])
            if r.JS_Window_GetClassName(hwnd) == "RPTopmostButton" and r.JS_Window_IsVisible(hwnd) then
                table.insert(windowsToFocus, hwnd)
            end
        end
    end
    local trackCount = r.CountTracks(0)
    for i = 0, trackCount - 1 do
        local track = r.GetTrack(0, i)
        if track then
            local fxCount = r.TrackFX_GetCount(track)
            for fx = 0, fxCount - 1 do
                local floatingHwnd = r.TrackFX_GetFloatingWindow(track, fx)
                if floatingHwnd and r.JS_Window_IsVisible(floatingHwnd) then
                    table.insert(windowsToFocus, floatingHwnd)
                end
            end
        end
    end
    local retval, tracknum, itemnum, fxnum = r.GetFocusedFX()
    if retval == 1 then
        local track = r.GetTrack(0, tracknum-1)
        local floatingHwnd = r.TrackFX_GetFloatingWindow(track, fxnum)
        if floatingHwnd and r.JS_Window_IsVisible(floatingHwnd) then
            table.insert(windowsToFocus, floatingHwnd)
        end
    end
    local retval, tracknum, fxnum = r.GetLastTouchedFX()
    if retval then
        local track = r.GetTrack(0, tracknum-1)
        local floatingHwnd = r.TrackFX_GetFloatingWindow(track, fxnum)
        if floatingHwnd and r.JS_Window_IsVisible(floatingHwnd) then
            table.insert(windowsToFocus, floatingHwnd)
        end
    end
    
    r.defer(function()
        for _, hwnd in ipairs(windowsToFocus) do
            r.JS_Window_Show(hwnd, "HIDE")
            r.defer(function() 
                r.JS_Window_Show(hwnd, "SHOW")
                r.JS_Window_SetForeground(hwnd)
                r.JS_Window_SetFocus(hwnd)
            end)
        end
        hasDrawingFocusBeenHandled = true
    end)  
end

function RenderGridLines(draw_list, track_y, track_height, window_y, item_pos, item_end)
    local base_color = config.color & 0xFFFFFF00
    local alpha = math.floor(config.opacity * 255)
    local color = base_color | alpha
    
    if show_full_grid then
        item_pos, item_end = r.GetSet_ArrangeView2(0, false, 0, 0)
        track_y = 0
        track_height = BOT - TOP - scroll_size 
        if config.show_horizontal_lines then
            local num_tracks = r.CountTracks(0)
            for i = 0, num_tracks - 1 do
                local track = r.GetTrack(0, i)
                local y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
                local h = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
                ImGui.DrawList_AddLine(draw_list,
                    LEFT, window_y + y + h,
                    RIGHT - scroll_size, window_y + y + h,
                    color, config.line_thickness)
            end
        end
    end
    local tempo = r.Master_GetTempo()
    local actual_numerator = config.numerator
    local actual_denominator = config.denominator
    if compound_time_signatures[config.denominator] and
       compound_time_signatures[config.denominator][config.numerator] then
        actual_numerator = compound_time_signatures[config.denominator][config.numerator][2]
        actual_denominator = compound_time_signatures[config.denominator][config.numerator][1]
    end
    local beat_duration = (60 / tempo) * (4 / actual_numerator)
    local beats_per_measure = actual_denominator
    local first_grid = math.floor(item_pos / beat_duration) * beat_duration
    local viewport_start, viewport_end = r.GetSet_ArrangeView2(0, false, 0, 0)
    local arrange_width = RIGHT - LEFT
    local last_drawn_x = nil

    for i = 0, math.ceil((item_end - first_grid) / beat_duration) do
        local grid_pos = first_grid + (i * beat_duration)
        if grid_pos < viewport_start or grid_pos > viewport_end then goto continue end
        if grid_pos < item_pos or grid_pos > item_end then goto continue end

        local pixels = arrange_width * (grid_pos - viewport_start) / (viewport_end - viewport_start)
        local screen_x = LEFT + pixels
        local beat_index = math.floor((grid_pos / beat_duration) + 0.5)
        local isMeasureBoundary = (beat_index % beats_per_measure == 0)
        
        if not config.measure_only or isMeasureBoundary then
            local line_thickness = isMeasureBoundary and config.line_thickness * 2 or config.line_thickness
            ImGui.DrawList_AddLine(draw_list,
                screen_x, window_y + track_y,
                screen_x, window_y + track_y + track_height,
                color, line_thickness)
        end
        if config.show_beat_numbers then
            local beat_in_measure = (beat_index % beats_per_measure) + 1
            if (not config.measure_only and (beat_in_measure == 1 or (last_drawn_x == nil or (screen_x - last_drawn_x) >= MIN_NUMBER_SPACING)))
               or (config.measure_only and beat_in_measure == 1) then
                local measure_number = math.floor(beat_index / beats_per_measure) + 1
                local number_text = string.format("%d.%d", measure_number, beat_in_measure)
                ImGui.PushFont(ctx, beat_font)
                ImGui.DrawList_AddText(draw_list, screen_x + 2, window_y + track_y, config.text_color, number_text)
                ImGui.PopFont(ctx)
                last_drawn_x = screen_x
            end
        end
        ::continue::
    end
end

function main()
    if not script_running then return end
    if not all_items_active and not show_full_grid and r.CountSelectedMediaItems(0) > 0 then
        if not manual_selection_mode then
            manual_selection_mode = true
            hasDrawingFocusBeenHandled = false
        end
    else
        manual_selection_mode = false
    end
    handleDrawingFocus()
    local ImGuiScale = ImGui.GetWindowDpiScale(ctx)    
    if ImGuiScale ~= ImGuiScale_saved then
        SetWindowScale(ImGuiScale)
        ImGuiScale_saved = ImGuiScale
    end    
    ShowConfigWindow()
    if show_full_grid or all_items_active or r.CountSelectedMediaItems(0) > 0 then
        DrawOverArrange()
        local visible, open = ImGui.Begin(ctx, 'Grid Lines##Overlay', true, flags)
        if visible then
            local draw_list = ImGui.GetWindowDrawList(ctx)
            local window_x, window_y = ImGui.GetWindowPos(ctx)            
            if show_full_grid then
                RenderGridLines(draw_list, 0, BOT - TOP - scroll_size, window_y, 0, 0)
            else
                local num_items = all_items_active and r.CountMediaItems(0) or r.CountSelectedMediaItems(0)
                for i = 0, num_items - 1 do
                    local item = all_items_active and r.GetMediaItem(0, i) or r.GetSelectedMediaItem(0, i)
                    if item then
                        local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                        local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
                        local item_end = item_pos + item_len
                        local track = r.GetMediaItemTrack(item)
                        local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
                        local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
                        RenderGridLines(draw_list, track_y, track_height, window_y, item_pos, item_end)
                    end
                end
            end
            ImGui.End(ctx)
        end
    end
    r.defer(main)
end
main()