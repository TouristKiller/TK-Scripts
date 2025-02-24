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

function ButtonEditor.ShowEditor(ctx, custom_buttons, settings)
    if not custom_buttons.show_editor then return end

    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)
    local window_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_TopMost()
    
    r.ImGui_SetNextWindowSize(ctx, 400, -1)
    local visible, open = r.ImGui_Begin(ctx, "Custom Button Editor##TK", true, window_flags)
    
    if visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "BUTTON SETTINGS")
        
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

        r.ImGui_Separator(ctx)

        if custom_buttons.current_edit then
            local button = custom_buttons.buttons[custom_buttons.current_edit]
            
            r.ImGui_BeginChild(ctx, "ButtonEditor", 0, 200)
            
            if r.ImGui_CollapsingHeader(ctx, "Basic Settings", r.ImGui_TreeNodeFlags_DefaultOpen()) then
                local changed = false
                
                rv, button.name = r.ImGui_InputText(ctx, "Name", button.name)
                changed = changed or rv
                
                rv, button.position = r.ImGui_SliderDouble(ctx, "Position X", button.position, 0, 1, "%.3f")
                changed = changed or rv
                
                rv, button.position_y = r.ImGui_SliderDouble(ctx, "Position Y", button.position_y or 0.15, 0, 1, "%.3f")
                changed = changed or rv
                
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

            if r.ImGui_Checkbox(ctx, "Use Icon", button.use_icon) then
                button.use_icon = not button.use_icon
                custom_buttons.SaveCurrentButtons()
            end
            r.ImGui_SameLine(ctx)
            if button.use_icon then
                if r.ImGui_Button(ctx, "Browse Icons") then
                    IconBrowser.show_window = true
                end
                
                r.ImGui_Text(ctx, "Or select from list")
                r.ImGui_SameLine(ctx)
                local icon_list = GetIconFiles()
                if r.ImGui_BeginCombo(ctx, "##", button.icon_name or "Choose an icon") then
                    for _, icon_name in ipairs(icon_list) do
                        if r.ImGui_Selectable(ctx, icon_name, button.icon_name == icon_name) then
                            button.icon_name = icon_name
                            button.icon = r.ImGui_CreateImage(r.GetResourcePath() .. "/Data/toolbar_icons/" .. icon_name)
                            custom_buttons.SaveCurrentButtons()
                        end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                
                local selected_icon = IconBrowser.Show(ctx)
                if selected_icon then
                    button.icon_name = selected_icon
                    button.icon = nil
                    custom_buttons.SaveCurrentButtons()
                end
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
                if r.ImGui_Button(ctx, "Add A Menu Item") then
                    table.insert(button.right_menu.items, {
                        name = "New Item",
                        command = nil
                    })
                    custom_buttons.SaveCurrentButtons()
                end
                
                local menu_changed = false
                for idx, item in ipairs(button.right_menu.items) do
                    r.ImGui_PushID(ctx, idx)
                    if r.ImGui_Button(ctx, "X") then
                        table.remove(button.right_menu.items, idx)
                        menu_changed = true
                    end
                    r.ImGui_SameLine(ctx)
                    
                    local rv_name, new_name = r.ImGui_InputText(ctx, "Naam##" .. idx, item.name)
                    if rv_name then
                        item.name = new_name
                        menu_changed = true
                    end
                    
                    local rv_cmd, new_command = r.ImGui_InputText(ctx, "Command ID##" .. idx, item.command or "")
                    if rv_cmd then
                        item.command = new_command
                        menu_changed = true
                    end
                    
                    local rv_type, new_type = r.ImGui_Combo(ctx, "Command Type##" .. idx, item.type or 0, "Main\0MIDI Editor\0")
                    if rv_type then
                        item.type = new_type
                        menu_changed = true
                    end
                    
                    r.ImGui_PopID(ctx)
                end
                
                if menu_changed then custom_buttons.SaveCurrentButtons() end
            end
            r.ImGui_EndChild(ctx)
            r.ImGui_Text(ctx, "Set Left click for single click action, right click for menu")
        end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx)
    custom_buttons.show_editor = open
end

return ButtonEditor
