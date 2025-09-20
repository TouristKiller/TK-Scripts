local r = reaper
local resource_path = r.GetResourcePath()
local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
local button_presets_path = script_path .. "tk_transport_buttons/presets/"
local IconBrowser = require('icon_browser')
local ButtonEditor = {}
local new_preset_name = ""

-- Local open/close states for inline editor sections
local cb_section_states = {
    basic_open = true,
    group_open = false,
    colors_open = false,
    left_open = false,
    right_open = false,
}

-- Draw a section header with + / - toggle like Layout & Position tab
local function ShowCBSectionHeader(ctx, title, state_key)
    r.ImGui_Text(ctx, title)
    r.ImGui_SameLine(ctx)
    -- Transparent button background (match style)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    if r.ImGui_Button(ctx, (cb_section_states[state_key] and "-##" or "+##") .. title) then
        cb_section_states[state_key] = not cb_section_states[state_key]
    end
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
    return cb_section_states[state_key]
end

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



-- Inline version that renders the editor inside an existing window/tab
function ButtonEditor.ShowEditorInline(ctx, custom_buttons, settings)
    -- Button Presets (altijd zichtbaar)
    r.ImGui_Text(ctx, "Button Presets:")
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
            
        
        r.ImGui_Separator(ctx)

        local combo_label = custom_buttons.current_edit and
            custom_buttons.buttons[custom_buttons.current_edit].name or "Select A Button"

        if r.ImGui_BeginCombo(ctx, "Buttons", combo_label) then
            -- Collect buttons per group
            local groups = {}
            local ungrouped = {}
            for i, button in ipairs(custom_buttons.buttons) do
                local g = button.group and button.group ~= "" and button.group or nil
                if g then
                    groups[g] = groups[g] or {}
                    table.insert(groups[g], {idx=i, btn=button})
                else
                    table.insert(ungrouped, {idx=i, btn=button})
                end
            end
            -- Sort group names alphabetically
            local group_names = {}
            for g,_ in pairs(groups) do table.insert(group_names, g) end
            table.sort(group_names, function(a,b) return a:lower()<b:lower() end)
            -- Sort within each group alphabetically by button name
            for _,g in ipairs(group_names) do
                table.sort(groups[g], function(a,b) return (a.btn.name or ""):lower() < (b.btn.name or ""):lower() end)
            end
            -- Sorteer ungrouped alfabetisch op naam
            table.sort(ungrouped, function(a,b) return (a.btn.name or ""):lower() < (b.btn.name or ""):lower() end)
            -- Render grouped buttons
            for _,g in ipairs(group_names) do
                r.ImGui_SeparatorText(ctx, g)
                for _,entry in ipairs(groups[g]) do
                    if r.ImGui_Selectable(ctx, entry.btn.name .. "##btn"..entry.idx, custom_buttons.current_edit == entry.idx) then
                        custom_buttons.current_edit = entry.idx
                    end
                end
            end
            if #group_names>0 and #ungrouped>0 then r.ImGui_Separator(ctx) end
            if #ungrouped>0 then
                if #group_names>0 then r.ImGui_SeparatorText(ctx, "(No Group)") end
                for _,entry in ipairs(ungrouped) do
                    if r.ImGui_Selectable(ctx, entry.btn.name .. "##btn"..entry.idx, custom_buttons.current_edit == entry.idx) then
                        custom_buttons.current_edit = entry.idx
                    end
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
                
                local selected_icon = IconBrowser.Show(ctx, settings)
                if selected_icon then
                    button.icon_name = selected_icon
                    button.icon = nil
                    custom_buttons.SaveCurrentButtons()
                end
            end
            r.ImGui_Separator(ctx)
            if ShowCBSectionHeader(ctx, "Basic Settings", "basic_open") then
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
                r.ImGui_SameLine(ctx)
                rv, button.show_border = r.ImGui_Checkbox(ctx, "Border", button.show_border ~= false)
                if rv then
                    button.show_border = (button.show_border ~= false)
                    changed = true
                end
                rv, button.group = r.ImGui_InputText(ctx, "Group", button.group or "")
                changed = changed or rv
                
                if changed then custom_buttons.SaveCurrentButtons() end
            end
            if ShowCBSectionHeader(ctx, "Group Edit", "group_open") then
                r.ImGui_Text(ctx, "Edit all buttons sharing this group name (relative spacing preserved when shifting)")
                local gcount = 0
                for _,b in ipairs(custom_buttons.buttons) do if b.group and b.group ~= "" and button.group == b.group then gcount = gcount + 1 end end
                if button.group and button.group ~= "" then
                    r.ImGui_TextColored(ctx, 0x00FF88FF, "Current Group: " .. button.group .. " (" .. gcount .. ")")
                end
                local gname = button.group or ""
                if gname == "" then
                    r.ImGui_TextDisabled(ctx, "(This button has no group name)")
                else
                    local pixel_change_x = 1 / r.ImGui_GetWindowWidth(ctx)
                    local pixel_change_y = 1 / r.ImGui_GetWindowHeight(ctx)
                    if r.ImGui_Button(ctx, "<-X##grpMoveLeft") then
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel left") end
                        for _,b in ipairs(custom_buttons.buttons) do
                            if b.group==gname then b.position = math.max(0, b.position - pixel_change_x) end
                        end
                        custom_buttons.SaveCurrentButtons()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "X->##grpMoveRight") then
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel right") end
                        for _,b in ipairs(custom_buttons.buttons) do
                            if b.group==gname then b.position = math.min(1, b.position + pixel_change_x) end
                        end
                        custom_buttons.SaveCurrentButtons()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "<-Y##grpMoveUp") then
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel up") end
                        for _,b in ipairs(custom_buttons.buttons) do
                            if b.group==gname then b.position_y = math.max(0, (b.position_y or 0) - pixel_change_y) end
                        end
                        custom_buttons.SaveCurrentButtons()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Y->##grpMoveDown") then
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel down") end
                        for _,b in ipairs(custom_buttons.buttons) do
                            if b.group==gname then b.position_y = math.min(1, (b.position_y or 0) + pixel_change_y) end
                        end
                        custom_buttons.SaveCurrentButtons()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Align Y") then
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Align all group members vertically to this button") end
                        for _,b in ipairs(custom_buttons.buttons) do if b.group==gname then b.position_y = button.position_y end end
                        custom_buttons.SaveCurrentButtons()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Group Width") then
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Apply this button's width to entire group") end
                        for _,b in ipairs(custom_buttons.buttons) do if b.group==gname then b.width = button.width end end
                        custom_buttons.SaveCurrentButtons()
                    end
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_Button(ctx, "Color") then
                        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Apply all four colors from this button to group") end
                        for _,b in ipairs(custom_buttons.buttons) do if b.group==gname then
                            b.color=button.color; b.hover_color=button.hover_color; b.active_color=button.active_color; b.text_color=button.text_color
                        end end
                        custom_buttons.SaveCurrentButtons()
                    end
                    r.ImGui_SameLine(ctx)
                    local all_visible = true
                    for _,b in ipairs(custom_buttons.buttons) do
                        if b.group==gname and not b.visible then all_visible = false break end
                    end
                    local label = all_visible and "Hide Group" or "Show Group"
                    if r.ImGui_Button(ctx, label .. "##grpToggleVis") then
                        local new_state = not all_visible
                        for _,b in ipairs(custom_buttons.buttons) do if b.group==gname then b.visible = new_state end end
                        custom_buttons.SaveCurrentButtons()
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        if all_visible then
                            r.ImGui_SetTooltip(ctx, "Hide all buttons in this group")
                        else
                            r.ImGui_SetTooltip(ctx, "Show all buttons in this group")
                        end
                    end
                    -- Border group toggles
                    local all_borders = true
                    for _,b in ipairs(custom_buttons.buttons) do if b.group==gname and b.show_border == false then all_borders = false break end end
                    r.ImGui_SameLine(ctx)
                    local border_label = all_borders and "No Borders" or "Borders"
                    if r.ImGui_Button(ctx, border_label .. "##grpToggleBorder") then
                        local newb = not all_borders
                        for _,b in ipairs(custom_buttons.buttons) do if b.group==gname then b.show_border = newb end end
                        custom_buttons.SaveCurrentButtons()
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        if all_borders then
                            r.ImGui_SetTooltip(ctx, "Disable borders for entire group")
                        else
                            r.ImGui_SetTooltip(ctx, "Enable borders for entire group")
                        end
                    end
                end
            end
            
            if ShowCBSectionHeader(ctx, "Colors", "colors_open") then
                local changed = false
                local flags = r.ImGui_ColorEditFlags_NoInputs()
                
                rv, button.color = r.ImGui_ColorEdit4(ctx, "Base Color", button.color, flags)
                changed = changed or rv
                r.ImGui_SameLine(ctx)
                rv, button.hover_color = r.ImGui_ColorEdit4(ctx, "Hover Color", button.hover_color, flags)
                changed = changed or rv
                
                rv, button.active_color = r.ImGui_ColorEdit4(ctx, "Active Color", button.active_color, flags)
                changed = changed or rv
                r.ImGui_SameLine(ctx)
                rv, button.text_color = r.ImGui_ColorEdit4(ctx, "Text Color", button.text_color, flags)
                changed = changed or rv
                
                if changed then custom_buttons.SaveCurrentButtons() end
            end

            r.ImGui_Separator(ctx)
            if ShowCBSectionHeader(ctx, "Left Click Action", "left_open") then
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

            if ShowCBSectionHeader(ctx, "Right Click Menu", "right_open") then
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

            r.ImGui_Text(ctx, "Set Left click for single click action, right click for menu")
            r.ImGui_Text(ctx, "Always save button in preset after editing, or it will be lost")
        end
    -- No separate window close handling in inline mode
end

return ButtonEditor
