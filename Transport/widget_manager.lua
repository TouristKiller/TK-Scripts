local r = reaper
local WidgetManager = {}
local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
package.path = script_path .. "?.lua;" .. package.path

-- Probeer de JSON module te laden
local json_status, json = pcall(require, "json")
if not json_status then
    r.ShowConsoleMsg("Could not load JSON module. Make sure it's installed.\n")
end

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
    }
}

local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
local json = require("json")

function WidgetManager.SaveCommandIDs()
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

function WidgetManager.LoadCommandIDs()
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

function WidgetManager.ResetCommandID(index)
    if index > 0 and index <= #widgets then
        widgets[index].command_id = ""
        WidgetManager.SaveCommandIDs()
    end
end

function WidgetManager.ResetAllCommandIDs()
    for i, widget in ipairs(widgets) do
        widget.command_id = ""
    end
    WidgetManager.SaveCommandIDs()
end

function WidgetManager.UpdateWidgetStatus()
    for i, widget in ipairs(widgets) do
        if r.APIExists("JS_Window_Find") then
            local hwnd = r.JS_Window_Find(widget.name, true)
            widget.is_open = (hwnd ~= nil)
        end
    end
end

function WidgetManager.StartWidget(index)
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

function WidgetManager.StopWidget(index)
    local widget = widgets[index]
    if not widget.is_open or widget.command_id == "" then return end
    
    local cmd_id = r.NamedCommandLookup(widget.command_id)
    if cmd_id ~= 0 then
        r.Main_OnCommand(cmd_id, 0)
        widget.is_open = false
    end
end

function WidgetManager.CommandIDInput(ctx, label, widget_index)
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

function WidgetManager.DrawStatusCircle(ctx, x, y, radius, color)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddCircleFilled(draw_list, x, y, radius, color)
end


function WidgetManager.RenderWidgetManagerUI(ctx, script_path)
    WidgetManager.LoadCommandIDs()
    if r.ImGui_GetFrameCount(ctx) % 30 == 0 then
        WidgetManager.UpdateWidgetStatus()
    end
    if not WidgetManager.showing_setup then
        if r.ImGui_Button(ctx, "Start All Widgets") then
            for i = 1, #widgets do
                WidgetManager.StartWidget(i)
            end
        end
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, "Stop All Widgets") then
            for i = 1, #widgets do
                WidgetManager.StopWidget(i)
            end
        end
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, "Configure") then
            WidgetManager.showing_setup = true
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
            WidgetManager.DrawStatusCircle(ctx, cursor_screen_pos_x + 6, cursor_screen_pos_y + 7, 5, status_color)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xBBBBBBFF)
            r.ImGui_Text(ctx, "    " .. widget.description)
            r.ImGui_PopStyleColor(ctx)
            
            r.ImGui_SameLine(ctx, r.ImGui_GetWindowWidth(ctx) - 120)
            if widget.command_id ~= "" then
                if widget.is_open then
                    if r.ImGui_Button(ctx, "Stop##" .. i) then
                        WidgetManager.StopWidget(i)
                    end
                else
                    if r.ImGui_Button(ctx, "Start##" .. i) then
                        WidgetManager.StartWidget(i)
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
    else
        -- Setup mode
        r.ImGui_Text(ctx, "Enter the Command ID for each widget:")
        r.ImGui_Spacing(ctx)
        
        local any_changes = false
        
        for i, widget in ipairs(widgets) do
            r.ImGui_PushID(ctx, i)
            
            r.ImGui_Text(ctx, widget.name)
            r.ImGui_SameLine(ctx, r.ImGui_GetWindowWidth(ctx) - 50)
            if r.ImGui_Button(ctx, "Reset##" .. i) then
                WidgetManager.ResetCommandID(i)
                any_changes = true
            end
            
            if WidgetManager.CommandIDInput(ctx, "##cmdid" .. i, i) then
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
                WidgetManager.ResetAllCommandIDs()
                any_changes = true
            end
        end
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, "Done") then
            WidgetManager.showing_setup = false
        end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Save IDs") then
            WidgetManager.SaveCommandIDs()
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
            WidgetManager.SaveCommandIDs()
        end
    end
end

return WidgetManager
