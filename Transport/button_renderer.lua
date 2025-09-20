local r = reaper
local SECTIONS = 0
local resource_path = r.GetResourcePath()


local ButtonRenderer = {}
ButtonRenderer.image_cache = {}
-- Manual drag state to support edit-mode dragging even if InvisibleButton doesn't capture
ButtonRenderer.drag_active_index = nil
ButtonRenderer.last_mx = nil
ButtonRenderer.last_my = nil
ButtonRenderer.drag_moved = false -- track if any movement happened during current drag for autosave

local function round_to_grid(px, grid)
    if grid and grid > 1 then
        return math.floor((px + grid/2) / grid) * grid
    end
    return px
end

local function draw_grid(ctx, color, grid_px)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x0, y0 = r.ImGui_GetWindowPos(ctx)
    local w, h = r.ImGui_GetWindowSize(ctx)
    local right = x0 + w
    local bottom = y0 + h
    if grid_px < 2 then return end
    -- vertical lines
    local x = x0
    while x <= right do
        r.ImGui_DrawList_AddLine(dl, x, y0, x, bottom, color)
        x = x + grid_px
    end
    -- horizontal lines
    local y = y0
    while y <= bottom do
        r.ImGui_DrawList_AddLine(dl, x0, y, right, y, color)
        y = y + grid_px
    end
end

function ButtonRenderer.RenderButtons(ctx, custom_buttons, settings)
    local edit_mode = settings and settings.edit_mode
    local snap = settings and settings.edit_snap_to_grid
    local grid_px = settings and (settings.edit_grid_size_px or 16) or 16
    local grid_color = settings and (settings.edit_grid_color or 0xFFFFFF22) or 0xFFFFFF22
    if edit_mode and settings and settings.edit_grid_show then
        draw_grid(ctx, grid_color, grid_px)
    end
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
            
            local border_for_button = (button.show_border ~= false) and 1 or 0
            if border_for_button == 0 then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
            end
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
                    local clicked = r.ImGui_Button(ctx, "##btn" .. i, button.width, button.width)
                    
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
                    
                    if clicked and not edit_mode then
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
                    -- Tooltip on hover (icons)
                    if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                        local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                        if tip and tip ~= "" then
                            r.ImGui_BeginTooltip(ctx)
                            r.ImGui_Text(ctx, tostring(tip))
                            if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                                r.ImGui_Separator(ctx)
                                r.ImGui_Text(ctx, "Right-click for menu")
                            end
                            r.ImGui_EndTooltip(ctx)
                        end
                    end
                    
                    if r.ImGui_IsItemClicked(ctx, 1) and not edit_mode then
                        r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                    end
                    -- overlay for edit mode (draw frame + drag capture)
                else
                    -- Fallback naar tekstknop wanneer afbeelding ongeldig is
                    button.use_icon = false
                    
                    local label = (button.name ~= "" and button.name or "EmptyButton") .. "##btn"..i
                    if r.ImGui_Button(ctx, label, button.width) and not edit_mode then
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
                    -- Tooltip on hover (fallback text button)
                    if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                        local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                        if tip and tip ~= "" then
                            r.ImGui_BeginTooltip(ctx)
                            r.ImGui_Text(ctx, tostring(tip))
                            if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                                r.ImGui_Separator(ctx)
                                r.ImGui_Text(ctx, "Right-click for menu")
                            end
                            r.ImGui_EndTooltip(ctx)
                        end
                    end
                    
                    if r.ImGui_IsItemClicked(ctx, 1) and not edit_mode then
                        r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                    end
                    -- overlay for edit mode (draw frame + drag capture)
                end
            else
                local label = (button.name ~= "" and button.name or "EmptyButton") .. "##btn"..i
                if r.ImGui_Button(ctx, label, button.width) and not edit_mode then
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
                -- Tooltip on hover (text buttons)
                if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                    local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                    if tip and tip ~= "" then
                        r.ImGui_BeginTooltip(ctx)
                        r.ImGui_Text(ctx, tostring(tip))
                        if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                            r.ImGui_Separator(ctx)
                            r.ImGui_Text(ctx, "Right-click for menu")
                        end
                        r.ImGui_EndTooltip(ctx)
                    end
                end
                
                if r.ImGui_IsItemClicked(ctx, 1) and not edit_mode then
                    r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                end
                -- overlay for edit mode (draw frame + drag capture)
            end
            -- Common overlay for edit mode based on last drawn item rect
            if edit_mode then
                local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
                local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
                local dl = r.ImGui_GetWindowDrawList(ctx)
                r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, 0xFF8800AA)
                r.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, 0xFF880022)
                -- Manual hit-test and drag independent of InvisibleButton
                local mx, my = r.ImGui_GetMousePos(ctx)
                local inside = (mx >= min_x and mx <= max_x and my >= min_y and my <= max_y)
                if r.ImGui_IsMouseClicked(ctx, 0) and inside then
                    ButtonRenderer.drag_active_index = i
                    ButtonRenderer.last_mx, ButtonRenderer.last_my = mx, my
                    ButtonRenderer.drag_moved = false
                end
                if ButtonRenderer.drag_active_index == i and r.ImGui_IsMouseDown(ctx, 0) then
                    local ww, wh = r.ImGui_GetWindowSize(ctx)
                    local dx = mx - (ButtonRenderer.last_mx or mx)
                    local dy = my - (ButtonRenderer.last_my or my)
                    if snap then
                        dx = round_to_grid(dx, grid_px) - round_to_grid(0, grid_px)
                        dy = round_to_grid(dy, grid_px) - round_to_grid(0, grid_px)
                    end
                    if dx ~= 0 or dy ~= 0 then
                        local dpx = dx / ww
                        local dpy = dy / wh
                        if button.group and button.group ~= "" then
                            for _,b in ipairs(custom_buttons.buttons) do
                                if b.group == button.group then
                                    b.position = math.max(0, math.min(1, (b.position or 0) + dpx))
                                    b.position_y = math.max(0, math.min(1, (b.position_y or 0.15) + dpy))
                                end
                            end
                        else
                            button.position = math.max(0, math.min(1, (button.position or 0) + dpx))
                            button.position_y = math.max(0, math.min(1, (button.position_y or 0.15) + dpy))
                        end
                        ButtonRenderer.last_mx, ButtonRenderer.last_my = mx, my
                        ButtonRenderer.drag_moved = true
                    end
                end
                if ButtonRenderer.drag_active_index == i and r.ImGui_IsMouseReleased(ctx, 0) then
                    ButtonRenderer.drag_active_index = nil
                    ButtonRenderer.last_mx, ButtonRenderer.last_my = nil, nil
                    if ButtonRenderer.drag_moved then
                        -- Autosave current custom buttons layout after a drag
                        if custom_buttons and custom_buttons.SaveCurrentButtons then
                            custom_buttons.SaveCurrentButtons()
                            -- If a Buttons preset is active, also persist the changes to that preset
                            if custom_buttons.current_preset and custom_buttons.SaveButtonPreset then
                                custom_buttons.SaveButtonPreset(custom_buttons.current_preset)
                            else
                                -- fallback if module method is not exposed on instance
                                local ok, CustomButtons = pcall(require, 'custom_buttons')
                                if ok and CustomButtons then
                                    if CustomButtons.SaveCurrentButtons then pcall(CustomButtons.SaveCurrentButtons) end
                                    if custom_buttons and custom_buttons.current_preset and CustomButtons.SaveButtonPreset then
                                        pcall(CustomButtons.SaveButtonPreset, custom_buttons.current_preset)
                                    end
                                end
                            end
                        else
                            -- fall back if module method is not exposed on instance
                            local ok, CustomButtons = pcall(require, 'custom_buttons')
                            if ok and CustomButtons and CustomButtons.SaveCurrentButtons then
                                CustomButtons.SaveCurrentButtons()
                                if custom_buttons and custom_buttons.current_preset and CustomButtons.SaveButtonPreset then
                                    CustomButtons.SaveButtonPreset(custom_buttons.current_preset)
                                end
                            end
                        end
                        ButtonRenderer.drag_moved = false
                    end
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
            if border_for_button == 0 then
                r.ImGui_PopStyleVar(ctx)
            end
        end
    end
end


return ButtonRenderer