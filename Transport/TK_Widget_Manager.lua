local r = reaper

local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
package.path = script_path .. "?.lua;" .. package.path

local json_status, json = pcall(require, "json")
if not json_status then
    r.ShowConsoleMsg("can not load json\n")
end

local ctx = r.ImGui_CreateContext('TK Widget Manager')
local font = r.ImGui_CreateFont('arial', 12)
r.ImGui_Attach(ctx, font)

local widgets = {
    {
        name = "Transport Controls",
        script = "TK_Widget_Transport.lua",
        description = "Transport control buttons (play, stop, record, etc.)",
        command_id = "",
        is_open = false
    },
    {
        name = "Time Selection",
        script = "TK_Widget_TimeSelection.lua",
        description = "Displays current time selection information",
        command_id = "",
        is_open = false
    },
    {
        name = "Tempo & Time Signature",
        script = "TK_Widget_Tempo.lua",
        description = "Controls for tempo and time signature",
        command_id = "",
        is_open = false
    },
    {
        name = "Playback Rate",
        script = "TK_Widget_PlayRate.lua",
        description = "Controls playback speed",
        command_id = "",
        is_open = false
    },
    {
        name = "Visual Metronome",
        script = "TK_Widget_Metronome.lua",
        description = "Visual metronome that pulses with the beat",
        command_id = "",
        is_open = false
    },
    {
        name = "Cursor Position",
        script = "TK_Widget_CursorPosition.lua",
        description = "Displays current cursor position (time and bars/beats)",
        command_id = "",
        is_open = false
    },
    {
        name = "Tap Tempo",
        script = "TK_Widget_TapTempo.lua",
        description = "Tap to set the tempo",
        command_id = "",
        is_open = false
    },
    {
        name = "FX Search",
        script = "TK_Widget_FXSearch.lua",
        description = "Quick search for FX plugins to add to selected track",
        command_id = "",
        is_open = false
    }
}

local showing_setup = false
local settings = {
    window_rounding = 12.0,
    frame_rounding = 6.0,
    popup_rounding = 6.0,
    grab_rounding = 12.0,
    grab_min_size = 8.0,
    button_border_size = 1.0,
    border_size = 1.0,
    background = 0x000000FF,
    button_normal = 0x333333FF,
    play_active = 0x00FF00FF,    
    record_active = 0xFF0000FF,  
    pause_active = 0xFFFF00FF,  
    loop_active = 0x0088FFFF,    
    text_normal = 0xFFFFFFFF,
    frame_bg = 0x333333FF,
    frame_bg_hovered = 0x444444FF,
    frame_bg_active = 0x555555FF,
    slider_grab = 0x999999FF,
    slider_grab_active = 0xAAAAAAFF,
    check_mark = 0x999999FF,
    button_hovered = 0x444444FF,
    button_active = 0x555555FF,
    border = 0x444444FF,
    transport_normal = 0x333333FF,
    metronome_active = 0x00FF00FF,
    metronome_enabled = 0x00FF00FF,
}

function SetStyle()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.frame_rounding)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), settings.popup_rounding)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), settings.grab_rounding)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), settings.grab_min_size)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), settings.border_size)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), settings.button_border_size)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), settings.background)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), settings.frame_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), settings.frame_bg_hovered)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), settings.frame_bg_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), settings.slider_grab)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), settings.slider_grab_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), settings.check_mark)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.button_normal)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.button_hovered)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.button_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), settings.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.text_normal)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), settings.background)
end

function SaveCommandIDs()
    local ids = {}
    for i, widget in ipairs(widgets) do
        if widget.command_id ~= "" then
            ids[widget.script] = widget.command_id
        end
    end
    
    local success, json_str = pcall(function()
        return json.encode(ids)
    end)
    
    if success then
        local file_path = script_path .. "widget_command_ids.json"
        local file = io.open(file_path, "w")
        if file then
            file:write(json_str)
            file:close()
            return true
        end
    end
    return false
end

function LoadCommandIDs()
    local file_path = script_path .. "widget_command_ids.json"
    local file = io.open(file_path, "r")
    
    if file then
        local json_str = file:read("*all")
        file:close()
        
        if json_str and json_str ~= "" then
            local success, ids = pcall(function()
                return json.decode(json_str)
            end)
            
            if success and ids and type(ids) == "table" then
                for i, widget in ipairs(widgets) do
                    if ids[widget.script] then
                        widget.command_id = ids[widget.script]
                    end
                end
                return true
            end
        end
    end
    
    return false
end

LoadCommandIDs()
function ResetCommandID(index)
    if index > 0 and index <= #widgets then
        widgets[index].command_id = ""
        SaveCommandIDs()
    end
end

function ResetAllCommandIDs()
    for i, widget in ipairs(widgets) do
        widget.command_id = ""
    end
    SaveCommandIDs()
end

function UpdateWidgetStatus()
    for i, widget in ipairs(widgets) do
        if r.APIExists("JS_Window_Find") then
            local hwnd = r.JS_Window_Find(widget.name, true)
            widget.is_open = (hwnd ~= nil)
        end
    end
end

function StartWidget(index)
    local widget = widgets[index]
    if widget.is_open or widget.command_id == "" then return end
    
    local cmd_id = r.NamedCommandLookup(widget.command_id)
    if cmd_id ~= 0 then
        r.Main_OnCommand(cmd_id, 0)
        widget.is_open = true
    else
        r.ShowMessageBox("Invalid Command ID: " .. widget.command_id, "Error", 0)
    end
end

function StopWidget(index)
    local widget = widgets[index]
    if not widget.is_open or widget.command_id == "" then return end
    
    local cmd_id = r.NamedCommandLookup(widget.command_id)
    if cmd_id ~= 0 then
        r.Main_OnCommand(cmd_id, 0)
        widget.is_open = false
    end
end

function CommandIDInput(label, widget_index)
    local widget = widgets[widget_index]
    local command_id = widget.command_id
    local changed = false
    
    local rv, new_command_id = r.ImGui_InputText(ctx, label, command_id)
    
    if rv and new_command_id ~= command_id then
        if new_command_id:find("_RS%w+") then
            local clean_id = new_command_id:match("(_RS%w+)")
            if clean_id then
                widget.command_id = clean_id
                changed = true
            else
                widget.command_id = new_command_id
                changed = true
            end
        else
            widget.command_id = new_command_id
            changed = true
        end
    end
    
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Paste##" .. widget_index) then
        if r.APIExists("CF_GetClipboard") then
            local clipboard = r.CF_GetClipboard()
            if clipboard and clipboard ~= "" then
                local clean_id = clipboard:match("(_RS%w+)")
                if clean_id then
                    widget.command_id = clean_id
                else
                    widget.command_id = clipboard
                end
                changed = true
            end
        else
            r.ShowMessageBox("SWS extension is required for clipboard functionality", "Clipboard Error", 0)
        end
    end
    
    return changed
end

function DrawStatusCircle(x, y, radius, color)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddCircleFilled(draw_list, x, y, radius, color)
end

function ShowSetupDialog()
    local window_width = r.ImGui_GetWindowWidth(ctx)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
    r.ImGui_Text(ctx, "TK")
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "WIDGET MANAGER - SETUP")
    
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, window_width - 25)
    r.ImGui_SetCursorPosY(ctx, 6)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
    
    if r.ImGui_Button(ctx, "##close", 14, 14) then
        showing_setup = false
    end
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    r.ImGui_Text(ctx, "Enter the Command ID for each widget:")
    r.ImGui_Spacing(ctx)
    
    local any_changes = false
    
    for i, widget in ipairs(widgets) do
        r.ImGui_PushID(ctx, i)
        
        r.ImGui_Text(ctx, widget.name)
        r.ImGui_SameLine(ctx, r.ImGui_GetWindowWidth(ctx) - 50)
        if r.ImGui_Button(ctx, "Reset##" .. i) then
            ResetCommandID(i)
            any_changes = true
        end
        
        if CommandIDInput("##cmdid" .. i, i) then
            any_changes = true
        end
        
        r.ImGui_Spacing(ctx)
        r.ImGui_PopID(ctx)
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    if r.ImGui_Button(ctx, "Reset All Command IDs") then
        local confirm = r.ShowMessageBox("Are you sure you want to reset all Command IDs?", "Confirm Reset", 4)
        if confirm == 6 then
            ResetAllCommandIDs()
            any_changes = true
        end
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, "Done") then
        showing_setup = false
    end
    
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Save IDs") then
        SaveCommandIDs()
        any_changes = false
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    r.ImGui_TextWrapped(ctx, "How to find Command IDs:")
    r.ImGui_TextWrapped(ctx, "1. Right-click on REAPER's Actions button")
    r.ImGui_TextWrapped(ctx, "2. Select 'Show action IDs' from the context menu")
    r.ImGui_TextWrapped(ctx, "3. Open Actions List and search for your widget script name")
    r.ImGui_TextWrapped(ctx, "4. Copy the Command ID (it starts with _RS or _)")
    r.ImGui_TextWrapped(ctx, "5. Use the 'Paste' button next to each field to paste the command ID properly")
    r.ImGui_TextWrapped(ctx, "6. Click 'Save IDs' to ensure your settings are saved")
    
    if any_changes then
        SaveCommandIDs()
    end
end

local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar()

function Main()
    local window_open = true
    
    if r.ImGui_GetFrameCount(ctx) == 0 then
        LoadCommandIDs()
    end
    
    SetStyle()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)
    
    r.ImGui_SetNextWindowSize(ctx, 500, -1)
    
    local visible, open = r.ImGui_Begin(ctx, 'TK Widget Manager', true, window_flags)
    
    if visible then
        r.ImGui_PushFont(ctx, font, 12)
        
        if showing_setup then
            ShowSetupDialog()
        else
            if r.ImGui_GetFrameCount(ctx) % 30 == 0 then
                UpdateWidgetStatus()
            end
            
            local window_width = r.ImGui_GetWindowWidth(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
            r.ImGui_Text(ctx, "TK")
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "WIDGET MANAGER")
            
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, window_width - 25)
            r.ImGui_SetCursorPosY(ctx, 6)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
            
            if r.ImGui_Button(ctx, "##close", 14, 14) then
                open = false
            end
            r.ImGui_PopStyleColor(ctx, 3)
            
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)
            
            if r.ImGui_Button(ctx, "Start All") then
                for i = 1, #widgets do
                    StartWidget(i)
                end
            end
            
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, "Stop All") then
                for i = 1, #widgets do
                    StopWidget(i)
                end
            end
            
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, "Configure") then
                showing_setup = true
            end
            
            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)
            
            for i, widget in ipairs(widgets) do
                local text_start_x = r.ImGui_GetCursorPosX(ctx)
                local cursor_screen_pos_x, cursor_screen_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                
                r.ImGui_SetCursorPosX(ctx, text_start_x + 12)
                r.ImGui_Text(ctx, widget.name)
                
                local status_color = widget.is_open and 0x00FF00FF or 0xFF0000FF
                DrawStatusCircle(cursor_screen_pos_x + 6, cursor_screen_pos_y + 7, 5, status_color)
                
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xBBBBBBFF)
                r.ImGui_Text(ctx, "    " .. widget.description)
                r.ImGui_PopStyleColor(ctx)
                
                r.ImGui_SameLine(ctx, r.ImGui_GetWindowWidth(ctx) - 120)
                if widget.command_id ~= "" then
                    if widget.is_open then
                        if r.ImGui_Button(ctx, "Stop##" .. i) then
                            StopWidget(i)
                        end
                    else
                        if r.ImGui_Button(ctx, "Start##" .. i) then
                            StartWidget(i)
                        end
                    end
                else
                    r.ImGui_BeginDisabled(ctx)
                    r.ImGui_Button(ctx, "Not Configured##" .. i)
                    r.ImGui_EndDisabled(ctx)
                end
                
                r.ImGui_Spacing(ctx)
                r.ImGui_Separator(ctx)
            end
            
            r.ImGui_Spacing(ctx)
            r.ImGui_TextWrapped(ctx, "Click 'Configure' to set up Command IDs for each widget. Command IDs are specific to your REAPER installation and must be entered once before using the manager.")
        end
        
        r.ImGui_PopFont(ctx)
    end
    
    r.ImGui_End(ctx)
    
    r.ImGui_PopStyleVar(ctx, 8)
    r.ImGui_PopStyleColor(ctx, 13)
    
    window_open = window_open and open
    
    if window_open then
        r.defer(Main)
    end
end

Main()