local r = reaper
local SECTIONS = 0
local resource_path = r.GetResourcePath()


local ButtonRenderer = {}
ButtonRenderer.image_cache = {}

function ButtonRenderer.RenderButtons(ctx, custom_buttons)
    -- Haal de globale offsets op (of gebruik 0 als default)
    local x_offset = custom_buttons.x_offset or 0
    local y_offset = custom_buttons.y_offset or 0
    
    for i, button in ipairs(custom_buttons.buttons) do
        if button.visible then
            r.ImGui_SameLine(ctx)
            -- Pas de positie aan met de globale offsets
            local x_pos = (button.position + x_offset) * r.ImGui_GetWindowWidth(ctx)
            local y_pos = ((button.position_y or 0.15) + y_offset) * r.ImGui_GetWindowHeight(ctx)
            
            r.ImGui_SetCursorPosX(ctx, x_pos)
            r.ImGui_SetCursorPosY(ctx, y_pos)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button.color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), button.hover_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), button.active_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button.text_color)
            
            if button.use_icon and button.icon_name then
                if not r.ImGui_ValidatePtr(ButtonRenderer.image_cache[button.icon_name], 'ImGui_Image*') then
                    local icon_path = resource_path .. "/Data/toolbar_icons/" .. button.icon_name
                    if r.file_exists(icon_path) then
                        ButtonRenderer.image_cache[button.icon_name] = r.ImGui_CreateImage(icon_path)
                    else
                        -- Bestand bestaat niet, schakel icon uit voor deze knop
                        button.use_icon = false
                        button.icon_name = nil
                    end
                end
                button.icon = ButtonRenderer.image_cache[button.icon_name]
            
                if r.ImGui_ValidatePtr(button.icon, 'ImGui_Image*') then
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
                    -- Fallback naar tekstknop wanneer afbeelding ongeldig is
                    button.use_icon = false
                    
                    if r.ImGui_Button(ctx, button.name ~= "" and button.name or "##EmptyButton"..i, button.width) then
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
            else
                if r.ImGui_Button(ctx, button.name ~= "" and button.name or "##EmptyButton"..i, button.width) then
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