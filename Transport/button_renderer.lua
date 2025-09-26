local r = reaper
local SECTIONS = 0
local resource_path = r.GetResourcePath()


local ButtonRenderer = {}
ButtonRenderer.image_cache = {}
ButtonRenderer.drag_active_index = nil
ButtonRenderer.last_mx = nil
ButtonRenderer.last_my = nil
ButtonRenderer.drag_moved = false

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
    local x = x0
    while x <= right do
        r.ImGui_DrawList_AddLine(dl, x, y0, x, bottom, color)
        x = x + grid_px
    end
    local y = y0
    while y <= bottom do
        r.ImGui_DrawList_AddLine(dl, x0, y, right, y, color)
        y = y + grid_px
    end
end

local ExecuteMenuItem, BuildMenuTree, SortedKeys, RenderMenuTree

function ButtonRenderer.RenderButtons(ctx, custom_buttons, settings)
    r.ImGui_SetScrollY(ctx, 0)
    
    local edit_mode = settings and settings.edit_mode
    local snap = settings and settings.edit_snap_to_grid
    local grid_px = settings and (settings.edit_grid_size_px or 16) or 16
    local grid_color = settings and (settings.edit_grid_color or 0xFFFFFF22) or 0xFFFFFF22
    if edit_mode and settings and settings.edit_grid_show then
        draw_grid(ctx, grid_color, grid_px)
    end
    local x_offset = custom_buttons.x_offset or 0  
    local y_offset = custom_buttons.y_offset or 0  
    local x_offset_px = custom_buttons.x_offset_px or 0  
    local y_offset_px = custom_buttons.y_offset_px or 0  
    
    local window_width = r.ImGui_GetWindowWidth(ctx)
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local ref_w = (settings and settings.custom_buttons_ref_width) or 0
    local ref_h = (settings and settings.custom_buttons_ref_height) or 0
    local scale_with_w = settings and settings.custom_buttons_scale_with_width
    local scale_with_h = settings and settings.custom_buttons_scale_with_height
    local scale_sizes  = settings and settings.custom_buttons_scale_sizes
    local scale_w = (scale_with_w and ref_w and ref_w > 0) and (window_width / ref_w) or 1
    local scale_h = (scale_with_h and ref_h and ref_h > 0) and (window_height / ref_h) or 1

    for i, button in ipairs(custom_buttons.buttons) do
        if button.visible then
            r.ImGui_SameLine(ctx)


            local x_pos, y_pos
            if button.position_px ~= nil then
                x_pos = (button.position_px + x_offset_px) * scale_w
            else
                x_pos = (button.position + x_offset) * window_width
            end
            
            if button.position_y_px ~= nil then
                y_pos = (button.position_y_px + y_offset_px) * (scale_h ~= 0 and scale_h or 1)
            else
                y_pos = ((button.position_y or 0.15) + y_offset) * window_height
            end
            
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
            local draw_w = button.width
            if scale_sizes and draw_w and draw_w > 0 then
                draw_w = math.max(1, math.floor(draw_w * scale_w))
            end

            if button.use_icon and button.icon_name then
                if not r.ImGui_ValidatePtr(ButtonRenderer.image_cache[button.icon_name], 'ImGui_Image*') then
                    local icon_path = resource_path .. "/Data/toolbar_icons/" .. button.icon_name
                    if r.file_exists(icon_path) then
                        ButtonRenderer.image_cache[button.icon_name] = r.ImGui_CreateImage(icon_path)
                    else
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
                    local clicked = r.ImGui_Button(ctx, "##btn" .. i, draw_w, draw_w)
                    
                    r.ImGui_SetCursorPos(ctx, cursorX, cursorY)
                    
                    local uv_x = 0
                    if r.ImGui_IsItemHovered(ctx) then
                        uv_x = 0.33
                    end
                    if r.ImGui_IsItemActive(ctx) then
                        uv_x = 0.66
                    end
                    
                    r.ImGui_Image(ctx, button.icon, draw_w, draw_w, uv_x, 0, uv_x + 0.33, 1)
                    
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
                    if button.show_border ~= false then
                        local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
                        local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
                        local dl = r.ImGui_GetWindowDrawList(ctx)
                        local col = button.border_color or 0xFFFFFFFF
                        r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, col)
                    end
                else
                    button.use_icon = false
                    
                    local label = (button.name ~= "" and button.name or "EmptyButton") .. "##btn"..i
                    if r.ImGui_Button(ctx, label, draw_w) and not edit_mode then
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
                    if button.show_border ~= false then
                        local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
                        local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
                        local dl = r.ImGui_GetWindowDrawList(ctx)
                        local col = button.border_color or 0xFFFFFFFF
                        r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, col)
                    end
                end
            else
                local label = (button.name ~= "" and button.name or "EmptyButton") .. "##btn"..i
                if r.ImGui_Button(ctx, label, draw_w) and not edit_mode then
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
                if button.show_border ~= false then
                    local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
                    local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
                    local dl = r.ImGui_GetWindowDrawList(ctx)
                    local col = button.border_color or 0xFFFFFFFF
                    r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, col)
                end
            end
            if edit_mode then
                local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
                local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
                local dl = r.ImGui_GetWindowDrawList(ctx)
                r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, 0xFF8800AA)
                r.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, 0xFF880022)
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
                        local dx_ref = dx / (scale_w ~= 0 and scale_w or 1)
                        local dy_ref = dy / (scale_h ~= 0 and scale_h or 1)
                        local clamp_w = (ref_w and ref_w > 0) and ref_w or (ww / (scale_w ~= 0 and scale_w or 1))
                        local clamp_h = (ref_h and ref_h > 0) and ref_h or (wh / (scale_h ~= 0 and scale_h or 1))
                        
                        if button.group and button.group ~= "" then
                            for _,b in ipairs(custom_buttons.buttons) do
                                if b.group == button.group then
                                    if b.position_px == nil and b.position ~= nil then
                                        b.position_px = math.floor(b.position * clamp_w)
                                    end
                                    if b.position_y_px == nil and b.position_y ~= nil then
                                        b.position_y_px = math.floor((b.position_y or 0.15) * clamp_h)
                                    end
                                    
                                    b.position_px = math.max(0, math.min(clamp_w, (b.position_px or 0) + dx_ref))
                                    b.position_y_px = math.max(0, math.min(clamp_h, (b.position_y_px or math.floor(0.15 * clamp_h)) + dy_ref))
                                    
                                    b.position = b.position_px / clamp_w
                                    b.position_y = b.position_y_px / clamp_h
                                end
                            end
                        else
                            if button.position_px == nil and button.position ~= nil then
                                button.position_px = math.floor(button.position * clamp_w)
                            end
                            if button.position_y_px == nil and button.position_y ~= nil then
                                button.position_y_px = math.floor((button.position_y or 0.15) * clamp_h)
                            end
                            
                            button.position_px = math.max(0, math.min(clamp_w, (button.position_px or 0) + dx_ref))
                            button.position_y_px = math.max(0, math.min(clamp_h, (button.position_y_px or math.floor(0.15 * clamp_h)) + dy_ref))
                            
                            button.position = button.position_px / clamp_w
                            button.position_y = button.position_y_px / clamp_h
                        end
                        ButtonRenderer.last_mx, ButtonRenderer.last_my = mx, my
                        ButtonRenderer.drag_moved = true
                    end
                end
                if ButtonRenderer.drag_active_index == i and r.ImGui_IsMouseReleased(ctx, 0) then
                    ButtonRenderer.drag_active_index = nil
                    ButtonRenderer.last_mx, ButtonRenderer.last_my = nil, nil
                    if ButtonRenderer.drag_moved then
                        if custom_buttons and custom_buttons.SaveCurrentButtons then
                            custom_buttons.SaveCurrentButtons()
                            if custom_buttons.current_preset and custom_buttons.SaveButtonPreset then
                                custom_buttons.SaveButtonPreset(custom_buttons.current_preset)
                            else
                                local ok, CustomButtons = pcall(require, 'custom_buttons')
                                if ok and CustomButtons then
                                    if CustomButtons.SaveCurrentButtons then pcall(CustomButtons.SaveCurrentButtons) end
                                    if custom_buttons and custom_buttons.current_preset and CustomButtons.SaveButtonPreset then
                                        pcall(CustomButtons.SaveButtonPreset, custom_buttons.current_preset)
                                    end
                                end
                            end
                        else
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
                local has_sub = false
                for _, it in ipairs(button.right_menu.items) do
                    if it.name and it.name:find('/') then has_sub = true break end
                end
                if has_sub then
                    local tree = BuildMenuTree(button.right_menu.items)
                    RenderMenuTree(ctx, tree)
                else
                    for _, it in ipairs(button.right_menu.items) do
                        if r.ImGui_MenuItem(ctx, it.name) then
                            ExecuteMenuItem(it)
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


function ExecuteMenuItem(item)
    if not item or not item.command or item.command == '' then return end
    local command_id = tonumber(item.command) or r.NamedCommandLookup(item.command)
    if not command_id or command_id == 0 then return end
    if item.type == 1 then
        local editor = r.MIDIEditor_GetActive()
        if editor then r.MIDIEditor_OnCommand(editor, command_id) end
    else
        r.Main_OnCommand(command_id, 0)
    end
end

function BuildMenuTree(items)
    local root = { children = {}, items = {} }
    for _, it in ipairs(items) do
        local name = it.name or ''
        if name:find('/') then
            local current = root
            local segment_index = 0
            for segment in name:gmatch('[^/]+') do
                segment_index = segment_index + 1
                if segment_index == 0 then break end
                if segment_index == select(2, name:gsub('/', '')) + 1 then
                    current.items = current.items or {}
                    table.insert(current.items, { label = segment, item = it })
                else
                    current.children[segment] = current.children[segment] or { children = {}, items = {} }
                    current = current.children[segment]
                end
            end
        else
            table.insert(root.items, { label = name, item = it })
        end
    end
    return root
end

function SortedKeys(t)
    local keys = {}
    for k,_ in pairs(t) do table.insert(keys, k) end
    table.sort(keys, function(a,b) return a:lower()<b:lower() end)
    return keys
end

function RenderMenuTree(ctx, node)
    if node.items then
        for _, leaf in ipairs(node.items) do
            if r.ImGui_MenuItem(ctx, leaf.label) then
                ExecuteMenuItem(leaf.item)
            end
        end
    end
    if node.children then
        for _, k in ipairs(SortedKeys(node.children)) do
            local child = node.children[k]
            if r.ImGui_BeginMenu(ctx, k) then
                RenderMenuTree(ctx, child)
                r.ImGui_EndMenu(ctx)
            end
        end
    end
end

if not ButtonRenderer._submenu_patched then
    local original_draw = ButtonRenderer.DrawButtons
    ButtonRenderer.DrawButtons = function(...)
        original_draw(...)

    end
    ButtonRenderer._submenu_patched = true
end

return ButtonRenderer