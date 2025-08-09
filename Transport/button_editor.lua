local r = reaper
local resource_path = r.GetResourcePath()
local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
local button_presets_path = script_path .. "tk_transport_buttons/presets/"
local IconBrowser = require('icon_browser')
local ButtonEditor = {}
local new_preset_name = ""

function GetIconFiles()
    local icons = {}
    local resource_path = r.GetResourcePath() .. "/Data/toolbar_icons"
    local idx = 0
    
    while true do
        local file = r.EnumerateFiles(resource_path, idx)
        if not file then break end
        if file:match("%.png$") then
            table.insert(icons, file)
        end
        idx = idx + 1
    end
    return icons
end

local function MoveItem(t, from, to)
    if to < 1 or to > #t or from == to then return false end
    t[from], t[to] = t[to], t[from]
    return true
end



function ButtonEditor.ShowEditor(ctx, custom_buttons, settings, main_window_width, main_window_height)
    if not custom_buttons.show_editor then return end

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)
    local window_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_TopMost()
    
    r.ImGui_SetNextWindowSize(ctx, 500, -1)
    local visible, open = r.ImGui_Begin(ctx, "Custom Button Editor##TK", true, window_flags)
    
    if visible then
        local window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "BUTTON EDITOR")
        
        if custom_buttons.current_preset then
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, window_width - 150)  -- Positie aanpassen naar wens
            r.ImGui_Text(ctx, "Preset: " .. custom_buttons.current_preset)
        end
        
        local window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 25)
        r.ImGui_SetCursorPosY(ctx, 6)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
        
        if r.ImGui_Button(ctx, "##close", 14, 14) then
            open = false
            custom_buttons.SaveCurrentButtons()
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)

        if r.ImGui_CollapsingHeader(ctx, "Button Presets", r.ImGui_TreeNodeFlags_DefaultOpen()) then
            local presets = custom_buttons.GetButtonPresets()
            local current_preset = custom_buttons.current_preset or "Select Preset"
            
            if r.ImGui_BeginCombo(ctx, "##PresetCombo", current_preset) then
                for _, preset in ipairs(presets) do
                    if preset and type(preset) == "string" then
                        if r.ImGui_Selectable(ctx, preset, preset == current_preset) then
                            custom_buttons.LoadButtonPreset(preset)
                            custom_buttons.SaveCurrentButtons()
                        end
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
    
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Save") and custom_buttons.current_preset then
                custom_buttons.SaveButtonPreset(custom_buttons.current_preset)
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Delete") and custom_buttons.current_preset then
                custom_buttons.DeleteButtonPreset(custom_buttons.current_preset)
            end
            

            local rv
            rv, new_preset_name = r.ImGui_InputText(ctx, "##NewPreset", new_preset_name)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Save As New") and new_preset_name ~= "" then
                custom_buttons.SaveButtonPreset(new_preset_name)
                if r.file_exists(button_presets_path .. new_preset_name .. '.json') then
                    new_preset_name = ""
                end
            end
            if r.ImGui_Button(ctx, "Create action for this preset") and custom_buttons.current_preset then
                r.ShowConsoleMsg("Attempting to create action for: " .. custom_buttons.current_preset .. "\n")
                local cmd_id = custom_buttons.RegisterCommandToLoadPreset(custom_buttons.current_preset)
                r.ShowConsoleMsg("Command ID: " .. tostring(cmd_id) .. "\n")
                if cmd_id ~= 0 then
                    r.ImGui_OpenPopup(ctx, "ActionCreatedPopup")
                end
            end
            
            if r.ImGui_BeginPopup(ctx, "ActionCreatedPopup") then
                r.ImGui_Text(ctx, "Action created! You can find it in the action list as:")
                r.ImGui_Text(ctx, "TK_TRANSPORT_LOAD_PRESET_" .. custom_buttons.current_preset)
                if r.ImGui_Button(ctx, "OK") then
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                r.ImGui_EndPopup(ctx)
            end
            
        end
        
        r.ImGui_Separator(ctx)

        local combo_label = custom_buttons.current_edit and
            custom_buttons.buttons[custom_buttons.current_edit].name or "Select A Button"

        if r.ImGui_BeginCombo(ctx, "Buttons", combo_label) then
            for i, button in ipairs(custom_buttons.buttons) do
                if r.ImGui_Selectable(ctx, button.name, custom_buttons.current_edit == i) then
                    custom_buttons.current_edit = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        if r.ImGui_Button(ctx, "New Button") then
            table.insert(custom_buttons.buttons, custom_buttons.CreateNewButton())
            custom_buttons.current_edit = #custom_buttons.buttons
            custom_buttons.SaveCurrentButtons()
        end

        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Del Button") and custom_buttons.current_edit then
            table.remove(custom_buttons.buttons, custom_buttons.current_edit)
            custom_buttons.current_edit = nil
            custom_buttons.SaveCurrentButtons()
        end


        


        if custom_buttons.current_edit then
            local button = custom_buttons.buttons[custom_buttons.current_edit]
            
            r.ImGui_BeginChild(ctx, "ButtonEditor", 0, 200)
            r.ImGui_Separator(ctx)

            if r.ImGui_Checkbox(ctx, "Use Icon", button.use_icon) then
                button.use_icon = not button.use_icon
                custom_buttons.SaveCurrentButtons()
            end
            
            if button.use_icon then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse Icons") then
                    IconBrowser.show_window = true
                end
                
                local selected_icon = IconBrowser.Show(ctx)
                if selected_icon then
                    button.icon_name = selected_icon
                    button.icon = nil
                    custom_buttons.SaveCurrentButtons()
                end
            end
            r.ImGui_Separator(ctx)
            if r.ImGui_CollapsingHeader(ctx, "Basic Settings", r.ImGui_TreeNodeFlags_DefaultOpen()) then
                local changed = false
                
                rv, button.name = r.ImGui_InputText(ctx, "Name", button.name)
                changed = changed or rv
                
                -- X positie met pixel-nauwkeurige knoppen
                rv, button.position = r.ImGui_SliderDouble(ctx, "Position X", button.position, 0, 1, "%.3f")
                changed = changed or rv
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##btnPosX", 20, 20) then
                    local pixel_change = 1 / r.ImGui_GetWindowWidth(ctx)
                    button.position = math.max(0, button.position - pixel_change)
                    changed = true
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##btnPosX", 20, 20) then
                    local pixel_change = 1 / r.ImGui_GetWindowWidth(ctx)
                    button.position = math.min(1, button.position + pixel_change)
                    changed = true
                end
                
                -- Y positie met pixel-nauwkeurige knoppen
                rv, button.position_y = r.ImGui_SliderDouble(ctx, "Position Y", button.position_y or 0.15, 0, 1, "%.3f")
                changed = changed or rv
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##btnPosY", 20, 20) then
                    local pixel_change = 1 / r.ImGui_GetWindowHeight(ctx)
                    button.position_y = math.max(0, button.position_y - pixel_change)
                    changed = true
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##btnPosY", 20, 20) then
                    local pixel_change = 1 / r.ImGui_GetWindowHeight(ctx)
                    button.position_y = math.min(1, button.position_y + pixel_change)
                    changed = true
                end
                
                rv, button.width = r.ImGui_SliderInt(ctx, "Width", button.width, 12, 200)
                changed = changed or rv
                
                rv, button.visible = r.ImGui_Checkbox(ctx, "Visible", button.visible)
                changed = changed or rv
                
                if changed then custom_buttons.SaveCurrentButtons() end
            end
            
            if r.ImGui_CollapsingHeader(ctx, "Colors") then
                local changed = false
                local flags = r.ImGui_ColorEditFlags_NoInputs()
                
                rv, button.color = r.ImGui_ColorEdit4(ctx, "Base Color", button.color, flags)
                changed = changed or rv
                
                rv, button.hover_color = r.ImGui_ColorEdit4(ctx, "Hover Color", button.hover_color, flags)
                changed = changed or rv
                
                rv, button.active_color = r.ImGui_ColorEdit4(ctx, "Active Color", button.active_color, flags)
                changed = changed or rv
                
                rv, button.text_color = r.ImGui_ColorEdit4(ctx, "Text Color", button.text_color, flags)
                changed = changed or rv
                
                if changed then custom_buttons.SaveCurrentButtons() end
            end

            r.ImGui_Separator(ctx)
            if r.ImGui_CollapsingHeader(ctx, "Left Click Action") then
                local changed = false
                
                local rv_name, new_name = r.ImGui_InputText(ctx, "Action Name", button.left_click.name)
                if rv_name then
                    button.left_click.name = new_name
                    changed = true
                end
                
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "Command ID", button.left_click.command or "")
                if rv_cmd then
                    button.left_click.command = new_command
                    changed = true
                end
                
                local rv_type, new_type = r.ImGui_Combo(ctx, "Command Type", button.left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then
                    button.left_click.type = new_type
                    changed = true
                end
                
                if changed then custom_buttons.SaveCurrentButtons() end
            end

            if r.ImGui_CollapsingHeader(ctx, "Right Click Menu") then
                button.right_menu = button.right_menu or {}
                button.right_menu.items = button.right_menu.items or {}

                if r.ImGui_Button(ctx, "Add A Menu Item") then
                    table.insert(button.right_menu.items, { name = "New Item", command = "", type = 0 })
                    custom_buttons.SaveCurrentButtons()
                end
                r.ImGui_SameLine(ctx)
                r.ImGui_TextDisabled(ctx, "Drag or ↑ ↓ rearrange")
                r.ImGui_Separator(ctx)

                local remove_index
                local payload_type = "TK_BTN_RCMENU_ITEM"

                -- Table: Drag | Name | Cmd | Type | Move | Del
                if r.ImGui_BeginTable(ctx, "RCM_TABLE", 6,
                    r.ImGui_TableFlags_SizingStretchProp()
                    | r.ImGui_TableFlags_BordersInnerV()
                    | r.ImGui_TableFlags_RowBg()
                ) then
                    r.ImGui_TableSetupColumn(ctx, "Drag", r.ImGui_TableColumnFlags_WidthFixed(), 30)
                    r.ImGui_TableSetupColumn(ctx, "Name", 0)
                    r.ImGui_TableSetupColumn(ctx, "Cmd", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                    r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), 70)
                    r.ImGui_TableSetupColumn(ctx, "Move", r.ImGui_TableColumnFlags_WidthFixed(), 50)
                    r.ImGui_TableSetupColumn(ctx, "X", r.ImGui_TableColumnFlags_WidthFixed(), 20)
                    r.ImGui_TableHeadersRow(ctx)

                    for idx, item in ipairs(button.right_menu.items) do
                        r.ImGui_PushID(ctx, idx)
                        r.ImGui_TableNextRow(ctx)

                        r.ImGui_TableSetColumnIndex(ctx, 0)

                        local handle_w   = 30
                        local handle_h   = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                        local handle_txt = "≡≡"  -- kan ook "☰" of ":::" naar smaak

                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x00000000)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x66666633)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x88888855)
                        r.ImGui_Button(ctx, handle_txt .. "##drag", handle_w, handle_h)
                        r.ImGui_PopStyleColor(ctx, 3)

                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
                            r.ImGui_SetTooltip(ctx, "Drag to move")
                        end

                        -- Drag source
                        if r.ImGui_BeginDragDropSource(ctx) then
                            r.ImGui_SetDragDropPayload(ctx, payload_type, tostring(idx))
                            r.ImGui_Text(ctx, "Drag: " .. (item.name ~= "" and item.name or ("Item " .. idx)))
                            r.ImGui_EndDragDropSource(ctx)
                        end

                        -- Drop target (geef visuele feedback)
                        if r.ImGui_BeginDragDropTarget(ctx) then
                            local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, payload_type)
                            if ok then
                                local from = tonumber(payload)
                                if from and from ~= idx and MoveItem(button.right_menu.items, from, idx) then
                                    custom_buttons.SaveCurrentButtons()
                                end
                            end
                            r.ImGui_EndDragDropTarget(ctx)
                        end

                        -- Name
                        r.ImGui_TableSetColumnIndex(ctx, 1)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local rv_name, new_name = r.ImGui_InputText(ctx, "##name", item.name)
                        if rv_name then item.name = new_name; custom_buttons.SaveCurrentButtons() end

                        -- Cmd
                        r.ImGui_TableSetColumnIndex(ctx, 2)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local rv_cmd, new_cmd = r.ImGui_InputText(ctx, "##cmd", item.command or "")
                        if rv_cmd then item.command = new_cmd; custom_buttons.SaveCurrentButtons() end

                        -- Type
                        r.ImGui_TableSetColumnIndex(ctx, 3)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local rv_type, new_type = r.ImGui_Combo(ctx, "##type", item.type or 0, "Main\0MIDI Editor\0")
                        if rv_type then item.type = new_type; custom_buttons.SaveCurrentButtons() end

                        -- Move
                        r.ImGui_TableSetColumnIndex(ctx, 4)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        if idx > 1 and r.ImGui_Button(ctx, "↑##up") then
                            if MoveItem(button.right_menu.items, idx, idx - 1) then custom_buttons.SaveCurrentButtons() end
                        end
                        r.ImGui_SameLine(ctx)
                        if idx < #button.right_menu.items and r.ImGui_Button(ctx, "↓##down") then
                            if MoveItem(button.right_menu.items, idx, idx + 1) then custom_buttons.SaveCurrentButtons() end
                        end

                        -- Delete
                        r.ImGui_TableSetColumnIndex(ctx, 5)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        if r.ImGui_Button(ctx, "X##del") then
                            remove_index = idx
                        end

                        r.ImGui_PopID(ctx)
                    end

                    r.ImGui_EndTable(ctx)
                end

                if remove_index then
                    table.remove(button.right_menu.items, remove_index)
                    custom_buttons.SaveCurrentButtons()
                end
            end

            r.ImGui_EndChild(ctx)
            r.ImGui_Text(ctx, "Set Left click for single click action, right click for menu")
            r.ImGui_Text(ctx, "Always save button in preset after editing, or it will be lost")
        end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx)
    custom_buttons.show_editor = open
end

return ButtonEditor
