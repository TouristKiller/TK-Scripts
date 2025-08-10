local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.5,
    rel_pos_y = 0.15,
    font_size = 12,
    show_background = false,
    widget_width = 350,
    widget_height = 40,
    use_tk_transport_theme = true,
    current_preset = "",
    window_rounding = 12.0,
    frame_rounding = 6.0,
    popup_rounding = 6.0,
    grab_rounding = 12.0,
    grab_min_size = 8.0,
    button_border_size = 1.0,
    border_size = 1.0,
    current_font = "Arial",
    background_color = 0x33333366,
    text_color = 0xFFFFFFFF,
    button_color = 0x44444477,
    button_hover_color = 0x55555588,
    button_active_color = 0x666666AA,
    border_color = 0x444444FF,
    frame_bg = 0x333333FF,
    frame_bg_hovered = 0x444444FF,
    frame_bg_active = 0x555555FF,
    slider_grab = 0x999999FF,
    slider_grab_active = 0xAAAAAAFF,
    check_mark = 0x999999FF,
    play_active = 0x00FF00FF,
    record_active = 0xFF0000FF,
    pause_active = 0xFFFF00FF,
    loop_active = 0x0088FFFF,
    last_pos_x = 100,
    last_pos_y = 100,
    
    use_graphic_buttons = true,
    custom_image_size = 1.0,
    transport_normal = 0x333333FF,
    
    use_custom_play_image = false,
    custom_play_image_path = "",
    custom_play_image_size = 1.0,
    use_custom_stop_image = false,
    custom_stop_image_path = "",
    custom_stop_image_size = 1.0,
    use_custom_pause_image = false, 
    custom_pause_image_path = "",
    custom_pause_image_size = 1.0,
    use_custom_record_image = false,
    custom_record_image_path = "",
    custom_record_image_size = 1.0,
    use_custom_loop_image = false,
    custom_loop_image_path = "",
    custom_loop_image_size = 1.0,
    use_custom_rewind_image = false,
    custom_rewind_image_path = "",
    custom_rewind_image_size = 1.0,
    use_custom_forward_image = false,
    custom_forward_image_path = "",
    custom_forward_image_size = 1.0,
    locked_button_folder_path = "",
    use_locked_button_folder = false,
}

local PLAY_COMMAND = 1007
local STOP_COMMAND = 1016
local PAUSE_COMMAND = 1008
local RECORD_COMMAND = 1013
local REPEAT_COMMAND = 1068
local GOTO_START = 40042
local GOTO_END = 40043

local widget = handler.init("Transport Controls Widget", default_settings)
widget.SetWidgetTitle("Transport Controls")
widget.LoadSettings("TRANSPORT_CONTROLS_WIDGET")
r.SetExtState("TK_WIDGET_STATUS", "TK_Widget_Transport.lua", "active", false)

local transport_custom_images = {
    play = nil,
    stop = nil,
    pause = nil,
    record = nil,
    loop = nil,
    rewind = nil,
    forward = nil
}

function UpdateCustomImages()
    if widget.settings.use_custom_play_image and widget.settings.custom_play_image_path ~= "" then
        if r.file_exists(widget.settings.custom_play_image_path) then
            transport_custom_images.play = r.ImGui_CreateImage(widget.settings.custom_play_image_path)
        else
            widget.settings.custom_play_image_path = ""
            transport_custom_images.play = nil
        end
    end
    
    if widget.settings.use_custom_stop_image and widget.settings.custom_stop_image_path ~= "" then
        if r.file_exists(widget.settings.custom_stop_image_path) then
            transport_custom_images.stop = r.ImGui_CreateImage(widget.settings.custom_stop_image_path)
        else
            widget.settings.custom_stop_image_path = ""
            transport_custom_images.stop = nil
        end
    end
    
    if widget.settings.use_custom_pause_image and widget.settings.custom_pause_image_path ~= "" then
        if r.file_exists(widget.settings.custom_pause_image_path) then
            transport_custom_images.pause = r.ImGui_CreateImage(widget.settings.custom_pause_image_path)
        else
            widget.settings.custom_pause_image_path = ""
            transport_custom_images.pause = nil
        end
    end
    
    if widget.settings.use_custom_record_image and widget.settings.custom_record_image_path ~= "" then
        if r.file_exists(widget.settings.custom_record_image_path) then
            transport_custom_images.record = r.ImGui_CreateImage(widget.settings.custom_record_image_path)
        else
            widget.settings.custom_record_image_path = ""
            transport_custom_images.record = nil
        end
    end

    if widget.settings.use_custom_loop_image and widget.settings.custom_loop_image_path ~= "" then
        if r.file_exists(widget.settings.custom_loop_image_path) then
            transport_custom_images.loop = r.ImGui_CreateImage(widget.settings.custom_loop_image_path)
        else
            widget.settings.custom_loop_image_path = ""
            transport_custom_images.loop = nil
        end
    end
    
    if widget.settings.use_custom_rewind_image and widget.settings.custom_rewind_image_path ~= "" then
        if r.file_exists(widget.settings.custom_rewind_image_path) then
            transport_custom_images.rewind = r.ImGui_CreateImage(widget.settings.custom_rewind_image_path)
        else
            widget.settings.custom_rewind_image_path = ""
            transport_custom_images.rewind = nil
        end
    end
    
    if widget.settings.use_custom_forward_image and widget.settings.custom_forward_image_path ~= "" then
        if r.file_exists(widget.settings.custom_forward_image_path) then
            transport_custom_images.forward = r.ImGui_CreateImage(widget.settings.custom_forward_image_path)
        else
            widget.settings.custom_forward_image_path = ""
            transport_custom_images.forward = nil
        end
    end
end

UpdateCustomImages()

function WidgetSpecificSettings(ctx)
    local rv
    r.ImGui_Text(ctx, "Transport Controls Display")
    rv, widget.settings.use_graphic_buttons = r.ImGui_Checkbox(ctx, "Use Graphic Buttons", widget.settings.use_graphic_buttons)

    if r.ImGui_CollapsingHeader(ctx, "Custom Transport Button Images") then
        local changed = false
        rv, widget.settings.custom_image_size = r.ImGui_SliderDouble(ctx, "Global Image Scale", widget.settings.custom_image_size or 1.0, 0.5, 2.0, "%.2fx")
        rv, widget.settings.use_locked_button_folder = r.ImGui_Checkbox(ctx, "Use last image folder for all buttons", widget.settings.use_locked_button_folder)
        
        if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
            r.ImGui_Text(ctx, "Current folder: " .. widget.settings.locked_button_folder_path)
        end
        
        r.ImGui_Separator(ctx)
        
        rv, widget.settings.use_custom_play_image = r.ImGui_Checkbox(ctx, "Use Custom Play Button", widget.settings.use_custom_play_image)
        changed = changed or rv
        if widget.settings.use_custom_play_image then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse##Play") then
                local start_dir = ""
                if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
                    start_dir = widget.settings.locked_button_folder_path
                end
                
                local retval, file = r.GetUserFileNameForRead(start_dir, "Select Play Button Image", ".png")
                if retval then
                    widget.settings.custom_play_image_path = file
                    changed = true

                    if widget.settings.use_locked_button_folder then
                        widget.settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                    end
                end
            end
        end
        rv, widget.settings.custom_play_image_size = r.ImGui_SliderDouble(ctx, "Play Image Scale", widget.settings.custom_play_image_size, 0.5, 2.0, "%.2fx")

        rv, widget.settings.use_custom_stop_image = r.ImGui_Checkbox(ctx, "Use Custom Stop Button", widget.settings.use_custom_stop_image)
        changed = changed or rv
        if widget.settings.use_custom_stop_image then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse##Stop") then
                local start_dir = ""
                if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
                    start_dir = widget.settings.locked_button_folder_path
                end
                
                local retval, file = r.GetUserFileNameForRead(start_dir, "Select Stop Button Image", ".png")
                if retval then
                    widget.settings.custom_stop_image_path = file
                    changed = true
                    
                    if widget.settings.use_locked_button_folder then
                        widget.settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                    end
                end
            end
        end
        rv, widget.settings.custom_stop_image_size = r.ImGui_SliderDouble(ctx, "Stop Image Scale", widget.settings.custom_stop_image_size, 0.5, 2.0, "%.2fx")

        rv, widget.settings.use_custom_pause_image = r.ImGui_Checkbox(ctx, "Use Custom Pause Button", widget.settings.use_custom_pause_image)
        changed = changed or rv
        if widget.settings.use_custom_pause_image then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse##Pause") then
                local start_dir = ""
                if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
                    start_dir = widget.settings.locked_button_folder_path
                end
                
                local retval, file = r.GetUserFileNameForRead(start_dir, "Select Pause Button Image", ".png")
                if retval then
                    widget.settings.custom_pause_image_path = file
                    changed = true
                    
                    if widget.settings.use_locked_button_folder then
                        widget.settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                    end
                end
            end
        end
        rv, widget.settings.custom_pause_image_size = r.ImGui_SliderDouble(ctx, "Pause Image Scale", widget.settings.custom_pause_image_size, 0.5, 2.0, "%.2fx")

        rv, widget.settings.use_custom_record_image = r.ImGui_Checkbox(ctx, "Use Custom Record Button", widget.settings.use_custom_record_image)
        changed = changed or rv
        if widget.settings.use_custom_record_image then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse##Record") then
                local start_dir = ""
                if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
                    start_dir = widget.settings.locked_button_folder_path
                end
                
                local retval, file = r.GetUserFileNameForRead(start_dir, "Select Record Button Image", ".png")
                if retval then
                    widget.settings.custom_record_image_path = file
                    changed = true
                    
                    if widget.settings.use_locked_button_folder then
                        widget.settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                    end
                end
            end
        end
        rv, widget.settings.custom_record_image_size = r.ImGui_SliderDouble(ctx, "Record Image Scale", widget.settings.custom_record_image_size, 0.5, 2.0, "%.2fx")
        
        rv, widget.settings.use_custom_loop_image = r.ImGui_Checkbox(ctx, "Use Custom Loop Button", widget.settings.use_custom_loop_image)
        changed = changed or rv
        if widget.settings.use_custom_loop_image then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse##Loop") then
                local start_dir = ""
                if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
                    start_dir = widget.settings.locked_button_folder_path
                end
                
                local retval, file = r.GetUserFileNameForRead(start_dir, "Select Loop Button Image", ".png")
                if retval then
                    widget.settings.custom_loop_image_path = file
                    changed = true
                    
                    if widget.settings.use_locked_button_folder then
                        widget.settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                    end
                end
            end
        end
        rv, widget.settings.custom_loop_image_size = r.ImGui_SliderDouble(ctx, "Loop Image Scale", widget.settings.custom_loop_image_size, 0.5, 2.0, "%.2fx")
        
        rv, widget.settings.use_custom_rewind_image = r.ImGui_Checkbox(ctx, "Use Custom Rewind Button", widget.settings.use_custom_rewind_image)
        changed = changed or rv
        if widget.settings.use_custom_rewind_image then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse##Rewind") then
                local start_dir = ""
                if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
                    start_dir = widget.settings.locked_button_folder_path
                end
                
                local retval, file = r.GetUserFileNameForRead(start_dir, "Select Rewind Button Image", ".png")
                if retval then
                    widget.settings.custom_rewind_image_path = file
                    changed = true
                    
                    if widget.settings.use_locked_button_folder then
                        widget.settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                    end
                end
            end
        end
        rv, widget.settings.custom_rewind_image_size = r.ImGui_SliderDouble(ctx, "Rewind Image Scale", widget.settings.custom_rewind_image_size, 0.5, 2.0, "%.2fx")
        
        rv, widget.settings.use_custom_forward_image = r.ImGui_Checkbox(ctx, "Use Custom Forward Button", widget.settings.use_custom_forward_image)
        changed = changed or rv
        if widget.settings.use_custom_forward_image then
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Browse##Forward") then
                local start_dir = ""
                if widget.settings.use_locked_button_folder and widget.settings.locked_button_folder_path ~= "" then
                    start_dir = widget.settings.locked_button_folder_path
                end
                
                local retval, file = r.GetUserFileNameForRead(start_dir, "Select Forward Button Image", ".png")
                if retval then
                    widget.settings.custom_forward_image_path = file
                    changed = true
                    
                    if widget.settings.use_locked_button_folder then
                        widget.settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                    end
                end
            end
        end
        rv, widget.settings.custom_forward_image_size = r.ImGui_SliderDouble(ctx, "Forward Image Scale", widget.settings.custom_forward_image_size, 0.5, 2.0, "%.2fx")
        
        if changed then
            UpdateCustomImages()
        end
    end
end

widget.RegisterWidgetSettings(WidgetSpecificSettings)

function ShowPlaySyncMenu(h)
    if r.ImGui_IsItemClicked(h.ctx, 1) then 
        r.ImGui_OpenPopup(h.ctx, "SyncMenu")
    end
    if r.ImGui_BeginPopup(h.ctx, "SyncMenu") then
        if r.ImGui_MenuItem(h.ctx, "Timecode Sync Settings") then
            r.Main_OnCommand(40619, 0)
        end
        if r.ImGui_MenuItem(h.ctx, "Toggle Timecode Sync") then
            r.Main_OnCommand(40620, 0)
        end
        r.ImGui_EndPopup(h.ctx)
    end
end

function ShowRecordMenu(h)
    if r.ImGui_IsItemClicked(h.ctx, 1) then 
        r.ImGui_OpenPopup(h.ctx, "RecordMenu")
    end
    
    if r.ImGui_BeginPopup(h.ctx, "RecordMenu") then
        if r.ImGui_MenuItem(h.ctx, "Normal Record Mode") then
            r.Main_OnCommand(40252, 0)
        end
        if r.ImGui_MenuItem(h.ctx, "Selected Item Auto-Punch") then
            r.Main_OnCommand(40253, 0)
        end
        if r.ImGui_MenuItem(h.ctx, "Time Selection Auto-Punch") then
            r.Main_OnCommand(40076, 0)
        end
        r.ImGui_EndPopup(h.ctx)
    end
end

function DrawTransportGraphics(drawList, x, y, size, color)
   
    local function DrawPlay(x, y, size)
        local adjustedSize = size  
        local points = {
            x + size*0.1, y + size*0.1,  
            x + size*0.1, y + adjustedSize,
            x + adjustedSize, y + size/2
        }
        r.ImGui_DrawList_AddTriangleFilled(drawList, 
            points[1], points[2],
            points[3], points[4],
            points[5], points[6],
            color)
    end

    local function DrawStop(x, y, size)
        local adjustedSize = size 
        r.ImGui_DrawList_AddRectFilled(drawList, 
            x + size*0.1, y + size*0.1,
            x + adjustedSize, y + adjustedSize,
            color)
    end

    local function DrawPause(x, y, size)
        local adjustedSize = size 
        local barWidth = adjustedSize/3
        r.ImGui_DrawList_AddRectFilled(drawList, 
            x + size*0.1, y + size*0.1,
            x + size*0.1 + barWidth, y + adjustedSize,
            color)
        r.ImGui_DrawList_AddRectFilled(drawList,
            x + adjustedSize - barWidth, y + size*0.1,
            x + adjustedSize, y + adjustedSize,
            color)
    end

    local function DrawRecord(x, y, size)
        local adjustedSize = size *1.1
        r.ImGui_DrawList_AddCircleFilled(drawList,
            x + size/2, y + size/2,
            adjustedSize/2,
            color)
    end

    local function DrawLoop(x, y, size)
        local adjustedSize = size 
        r.ImGui_DrawList_AddCircle(drawList,
            x + size/2, y + size/2,
            adjustedSize/2,
            color, 32, 2)
        
        local arrowSize = adjustedSize/4
        local ax = x + size/12
        local ay = y + size/2
        r.ImGui_DrawList_AddTriangleFilled(drawList,
            ax, ay,
            ax - arrowSize/2, ay + arrowSize/2,
            ax + arrowSize/2, ay + arrowSize/2,
            color)
    end

    local function DrawArrows(x, y, size, forward)
        local arrowSize = size/1.8
        local spacing = size/6
        local yCenter = y + size/2
        
        for i = 0,1 do
            local startX = x + (i * (arrowSize + spacing))
            local points
            
            if forward then
                points = {
                    startX, yCenter - arrowSize/2.2,
                    startX, yCenter + arrowSize/2.2,
                    startX + arrowSize, yCenter
                }
            else
                points = {
                    startX + arrowSize, yCenter - arrowSize/2,
                    startX + arrowSize, yCenter + arrowSize/2,
                    startX, yCenter
                }
            end
            
            r.ImGui_DrawList_AddTriangleFilled(drawList,
                points[1], points[2],
                points[3], points[4],
                points[5], points[6],
                color)
        end
    end

    return {
        DrawPlay = DrawPlay,
        DrawStop = DrawStop,
        DrawPause = DrawPause,
        DrawRecord = DrawRecord,
        DrawArrows = DrawArrows,
        DrawLoop = DrawLoop
    }
end

function ShowTransportControls(h)
    local buttonSize = h.settings.font_size * 1.1
    local drawList = r.ImGui_GetWindowDrawList(h.ctx)
    
    if h.settings.use_graphic_buttons then
        local pos_x, pos_y = r.ImGui_GetCursorScreenPos(h.ctx)
        
        if r.ImGui_InvisibleButton(h.ctx, "<<", buttonSize, buttonSize) then
            r.Main_OnCommand(GOTO_START, 0)
        end
        
        if h.settings.use_custom_rewind_image and transport_custom_images.rewind and r.ImGui_ValidatePtr(transport_custom_images.rewind, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(h.ctx) then
                uv_x = 0.33
            end
            
            local scaled_size = buttonSize * h.settings.custom_rewind_image_size * h.settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.rewind,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, h.settings.transport_normal)
            graphics.DrawArrows(pos_x-10, pos_y, buttonSize, false)
        end
        
        r.ImGui_SameLine(h.ctx)
        local play_state = r.GetPlayState() & 1 == 1
        local play_color = play_state and h.settings.play_active or h.settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(h.ctx)
        if r.ImGui_InvisibleButton(h.ctx, "PLAY", buttonSize, buttonSize) then
            r.Main_OnCommand(PLAY_COMMAND, 0)
        end
        ShowPlaySyncMenu(h)
        
        if h.settings.use_custom_play_image and transport_custom_images.play and r.ImGui_ValidatePtr(transport_custom_images.play, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(h.ctx) then
                uv_x = 0.33
            end
            if play_state then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * h.settings.custom_play_image_size * h.settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.play,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local play_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, play_color)
            play_graphics.DrawPlay(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(h.ctx)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(h.ctx)
        if r.ImGui_InvisibleButton(h.ctx, "STOP", buttonSize, buttonSize) then
            r.Main_OnCommand(STOP_COMMAND, 0)
        end

        if h.settings.use_custom_stop_image and transport_custom_images.stop and r.ImGui_ValidatePtr(transport_custom_images.stop, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(h.ctx) then
                uv_x = 0.33
            end
            
            local scaled_size = buttonSize * h.settings.custom_stop_image_size * h.settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.stop,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, h.settings.transport_normal)
            graphics.DrawStop(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(h.ctx)
        local pause_state = r.GetPlayState() & 2 == 2
        local pause_color = pause_state and h.settings.pause_active or h.settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(h.ctx)
        if r.ImGui_InvisibleButton(h.ctx, "PAUSE", buttonSize, buttonSize) then
            r.Main_OnCommand(PAUSE_COMMAND, 0)
        end
        
        if h.settings.use_custom_pause_image and transport_custom_images.pause and r.ImGui_ValidatePtr(transport_custom_images.pause, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(h.ctx) then
                uv_x = 0.33
            end
            if pause_state then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * h.settings.custom_pause_image_size * h.settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.pause,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local pause_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, pause_color)
            pause_graphics.DrawPause(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(h.ctx)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        local rec_color = (rec_state == 1) and h.settings.record_active or h.settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(h.ctx)
        if r.ImGui_InvisibleButton(h.ctx, "REC", buttonSize, buttonSize) then
            r.Main_OnCommand(RECORD_COMMAND, 0)
        end
        ShowRecordMenu(h)
        
        if h.settings.use_custom_record_image and transport_custom_images.record and r.ImGui_ValidatePtr(transport_custom_images.record, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(h.ctx) then
                uv_x = 0.33
            end
            if rec_state == 1 then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * h.settings.custom_record_image_size * h.settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.record,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local rec_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, rec_color)
            rec_graphics.DrawRecord(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(h.ctx)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        local loop_color = (repeat_state == 1) and h.settings.loop_active or h.settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(h.ctx)
        if r.ImGui_InvisibleButton(h.ctx, "LOOP", buttonSize, buttonSize) then
            r.Main_OnCommand(REPEAT_COMMAND, 0)
        end
        
        if h.settings.use_custom_loop_image and transport_custom_images.loop and r.ImGui_ValidatePtr(transport_custom_images.loop, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(h.ctx) then
                uv_x = 0.33
            end
            if repeat_state == 1 then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * h.settings.custom_loop_image_size * h.settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.loop,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local loop_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, loop_color)
            loop_graphics.DrawLoop(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(h.ctx)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(h.ctx)
        if r.ImGui_InvisibleButton(h.ctx, ">>", buttonSize, buttonSize) then
            r.Main_OnCommand(GOTO_END, 0)
        end
        
        if h.settings.use_custom_forward_image and transport_custom_images.forward and r.ImGui_ValidatePtr(transport_custom_images.forward, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(h.ctx) then
                uv_x = 0.33
            end
            
            local scaled_size = buttonSize * h.settings.custom_forward_image_size * h.settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.forward,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, h.settings.transport_normal)
            graphics.DrawArrows(pos_x+5, pos_y, buttonSize, true)
        end
    else
        if r.ImGui_Button(h.ctx, "<<") then
            r.Main_OnCommand(GOTO_START, 0)
        end
        
        r.ImGui_SameLine(h.ctx)
        local play_state = r.GetPlayState() & 1 == 1
        if play_state then
            r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), h.settings.play_active)
        end
        if r.ImGui_Button(h.ctx, "PLAY") then
            r.Main_OnCommand(PLAY_COMMAND, 0)
        end
        if play_state then r.ImGui_PopStyleColor(h.ctx) end
        ShowPlaySyncMenu(h)

        r.ImGui_SameLine(h.ctx)
        if r.ImGui_Button(h.ctx, "STOP") then
            r.Main_OnCommand(STOP_COMMAND, 0)
        end
        
        r.ImGui_SameLine(h.ctx)
        local pause_state = r.GetPlayState() & 2 == 2
        if pause_state then
            r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), h.settings.pause_active)
        end
        if r.ImGui_Button(h.ctx, "PAUSE") then
            r.Main_OnCommand(PAUSE_COMMAND, 0)
        end
        if pause_state then r.ImGui_PopStyleColor(h.ctx) end
        
        r.ImGui_SameLine(h.ctx)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        if rec_state == 1 then
            r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), h.settings.record_active)
        end
        if r.ImGui_Button(h.ctx, "REC") then
            r.Main_OnCommand(RECORD_COMMAND, 0)
        end
        if rec_state == 1 then r.ImGui_PopStyleColor(h.ctx) end
        ShowRecordMenu(h)
        
        r.ImGui_SameLine(h.ctx)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        if repeat_state == 1 then
            r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), h.settings.loop_active)
        end
        if r.ImGui_Button(h.ctx, "LOOP") then
            r.Main_OnCommand(REPEAT_COMMAND, 0)
        end
        if repeat_state == 1 then r.ImGui_PopStyleColor(h.ctx) end
        
        r.ImGui_SameLine(h.ctx)
        if r.ImGui_Button(h.ctx, ">>") then
            r.Main_OnCommand(GOTO_END, 0)
        end
    end
end

function MainLoop()
    local open = widget.RunLoop(ShowTransportControls)

    local close_command = r.GetExtState("TK_WIDGET_COMMAND", "TK_Widget_Transport.lua")
    if close_command == "close" then
        r.DeleteExtState("TK_WIDGET_COMMAND", "TK_Widget_Transport.lua", false)
        r.DeleteExtState("TK_WIDGET_STATUS", "TK_Widget_Transport.lua", false)
        open = false
    end

    if open then
        r.defer(MainLoop)
    end
end

MainLoop()
