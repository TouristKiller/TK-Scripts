local r = reaper
local resource_path = r.GetResourcePath()
local ButtonRenderer = {}
ButtonRenderer.image_cache = {}

function ButtonRenderer.RenderButtons(ctx, custom_buttons)
    for i, button in ipairs(custom_buttons.buttons) do
        if button.visible then
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, button.position * r.ImGui_GetWindowWidth(ctx))
            r.ImGui_SetCursorPosY(ctx, (button.position_y or 0.15) * r.ImGui_GetWindowHeight(ctx))
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button.color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), button.hover_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), button.active_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button.text_color)
            
            if button.use_icon and button.icon_name then
                if not r.ImGui_ValidatePtr(ButtonRenderer.image_cache[button.icon_name], 'ImGui_Image*') then
                    ButtonRenderer.image_cache[button.icon_name] = r.ImGui_CreateImage(resource_path .. "/Data/toolbar_icons/" .. button.icon_name)
                end
                button.icon = ButtonRenderer.image_cache[button.icon_name]
            
                
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
                
                local cursorX, cursorY = r.ImGui_GetCursorPos(ctx)
                local clicked = r.ImGui_Button(ctx, "##" .. i, button.width, button.width)
                
                r.ImGui_SetCursorPos(ctx, cursorX, cursorY)
                
                local uv_x = 0
                if r.ImGui_IsItemHovered(ctx) then
                    uv_x = 0.33
                end
                if r.ImGui_IsItemActive(ctx) then
                    uv_x = 0.66
                end
                
                r.ImGui_Image(ctx, button.icon, button.width, button.width, uv_x, 0, uv_x + 0.33, 1)
                
                r.ImGui_PopStyleVar(ctx)
                r.ImGui_PopStyleColor(ctx, 3)
                
                if clicked then
                    if button.left_click.command then
                        local command_id = tonumber(button.left_click.command) or r.NamedCommandLookup(button.left_click.command)
                        if command_id then
                            if button.left_click.type == 1 then
                                local editor = r.MIDIEditor_GetActive()
                                if editor then
                                    r.MIDIEditor_OnCommand(editor, command_id)
                                end
                            else
                                r.Main_OnCommand(command_id, 0)
                            end
                        end
                    end
                end
                
                if r.ImGui_IsItemClicked(ctx, 1) then
                    r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                end
            else
                if r.ImGui_Button(ctx, button.name, button.width) then
                    if button.left_click.command then
                        local command_id = tonumber(button.left_click.command) or r.NamedCommandLookup(button.left_click.command)
                        if command_id then
                            if button.left_click.type == 1 then
                                local editor = r.MIDIEditor_GetActive()
                                if editor then
                                    r.MIDIEditor_OnCommand(editor, command_id)
                                end
                            else
                                r.Main_OnCommand(command_id, 0)
                            end
                        end
                    end
                end
                
                if r.ImGui_IsItemClicked(ctx, 1) then
                    r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                end
            end
            
            if r.ImGui_BeginPopup(ctx, "CustomButtonMenu" .. i) then
                for _, item in ipairs(button.right_menu.items) do
                    if r.ImGui_MenuItem(ctx, item.name) then
                        if item.command then
                            local command_id = tonumber(item.command) or r.NamedCommandLookup(item.command)
                            if command_id then
                                if item.type == 1 then
                                    local editor = r.MIDIEditor_GetActive()
                                    if editor then
                                        r.MIDIEditor_OnCommand(editor, command_id)
                                    end
                                else
                                    r.Main_OnCommand(command_id, 0)
                                end
                            end
                        end
                    end
                end
                r.ImGui_EndPopup(ctx)
            end
            
            r.ImGui_PopStyleColor(ctx, 4)
        end
    end
end

return ButtonRenderer



