local r = reaper
local SECTIONS = 0
local resource_path = r.GetResourcePath()

local function round_to_grid(px, grid)
    if grid and grid > 1 then
        return math.floor((px + grid/2) / grid) * grid
    end
    return px
end

local function ExecuteButtonAction(ctx, button)
    if button.is_group_visibility_toggle then
        local CustomButtons = require('custom_buttons')
        local toggle_mode = button.toggle_mode or "radio"
        
        if toggle_mode == "cycle" then
            -- Cycle Mode
            if button.cycle_views and #button.cycle_views > 0 then
                -- Advance to next view
                button.cycle_current_view = (button.cycle_current_view or 1) + 1
                if button.cycle_current_view > #button.cycle_views then
                    button.cycle_current_view = 1
                end
                
                -- Deactivate other toggles and reset their cycle position
                for _, other_btn in ipairs(CustomButtons.buttons) do
                    if other_btn.is_group_visibility_toggle and other_btn ~= button then
                        other_btn.toggle_state = false
                        if other_btn.toggle_mode == "cycle" then
                            other_btn.cycle_current_view = 1
                        end
                    end
                end
                
                button.toggle_state = true
                CustomButtons.SaveCurrentButtons()
            end
            
        elseif toggle_mode == "radio" then
            -- Radio Mode
            if not button.toggle_state then
                for _, other_btn in ipairs(CustomButtons.buttons) do
                    if other_btn.is_group_visibility_toggle and other_btn ~= button then
                        other_btn.toggle_state = false
                        if other_btn.toggle_mode == "cycle" then
                            other_btn.cycle_current_view = 1
                        end
                    end
                end
                button.toggle_state = true
            end
            
        else
            -- Toggle Mode
            button.toggle_state = not button.toggle_state
            
            if not button.toggle_state then
                for _, other_btn in ipairs(CustomButtons.buttons) do
                    if other_btn.is_group_visibility_toggle then
                        other_btn.toggle_state = false
                        if other_btn.toggle_mode == "cycle" then
                            other_btn.cycle_current_view = 1
                        end
                    end
                end
            else
                for _, other_btn in ipairs(CustomButtons.buttons) do
                    if other_btn.is_group_visibility_toggle and other_btn ~= button then
                        other_btn.toggle_state = false
                        if other_btn.toggle_mode == "cycle" then
                            other_btn.cycle_current_view = 1
                        end
                    end
                end
            end
        end
        
        CustomButtons.SaveCurrentButtons()
    end
    
    local alt_pressed = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt())
    local shift_pressed = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
    local ctrl_pressed = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
    
    if alt_pressed and button.alt_left_click and button.alt_left_click.command then
        local command_id = tonumber(button.alt_left_click.command) or r.NamedCommandLookup(button.alt_left_click.command)
        if command_id then
            if button.alt_left_click.type == 1 then
                local editor = r.MIDIEditor_GetActive()
                if editor then
                    r.MIDIEditor_OnCommand(editor, command_id)
                end
            else
                r.Main_OnCommand(command_id, 0)
            end
        end
    elseif shift_pressed and button.shift_left_click and button.shift_left_click.command then
        local command_id = tonumber(button.shift_left_click.command) or r.NamedCommandLookup(button.shift_left_click.command)
        if command_id then
            if button.shift_left_click.type == 1 then
                local editor = r.MIDIEditor_GetActive()
                if editor then
                    r.MIDIEditor_OnCommand(editor, command_id)
                end
            else
                r.Main_OnCommand(command_id, 0)
            end
        end
    elseif ctrl_pressed and button.ctrl_left_click and button.ctrl_left_click.command then
        local command_id = tonumber(button.ctrl_left_click.command) or r.NamedCommandLookup(button.ctrl_left_click.command)
        if command_id then
            if button.ctrl_left_click.type == 1 then
                local editor = r.MIDIEditor_GetActive()
                if editor then
                    r.MIDIEditor_OnCommand(editor, command_id)
                end
            else
                r.Main_OnCommand(command_id, 0)
            end
        end
    elseif button.left_click and button.left_click.command then
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
r.GetResourcePath()


local ButtonRenderer = {}
ButtonRenderer.image_cache = {}
ButtonRenderer.drag_active_index = nil
ButtonRenderer.last_mx = nil
ButtonRenderer.last_my = nil
ButtonRenderer.drag_moved = false
ButtonRenderer.popup_font_cache = {}  

-- Helper function to apply transparency to button colors
local function ApplyButtonTransparency(color, settings)
    if settings and settings.use_transparent_buttons then
        local alpha = settings.transparent_button_opacity or 0
        local r = (color >> 24) & 0xFF
        local g = (color >> 16) & 0xFF
        local b = (color >> 8) & 0xFF
        return (r << 24) | (g << 16) | (b << 8) | (alpha & 0xFF)
    end
    return color
end

local function PushTransportPopupStyling(ctx, settings)
 if not settings then return 0, false end
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), settings.transport_popup_bg or settings.background)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.transport_popup_text or settings.text_normal)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), settings.transport_border or settings.border)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), settings.transport_popup_bg or settings.background)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), settings.transport_border or settings.border)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), settings.transport_border or settings.border)
 local popup_font = nil
 if settings.transport_popup_font_name and settings.transport_popup_font_size then
 local cache_key = settings.transport_popup_font_name .. "_" .. settings.transport_popup_font_size
 popup_font = ButtonRenderer.popup_font_cache[cache_key]
 if not popup_font then
 popup_font = r.ImGui_CreateFont(settings.transport_popup_font_name, settings.transport_popup_font_size)
 if popup_font then
 r.ImGui_Attach(ctx, popup_font)
 ButtonRenderer.popup_font_cache[cache_key] = popup_font
 end
 end
 if popup_font then
 r.ImGui_PushFont(ctx, popup_font, settings.transport_popup_font_size)
 return 6, true, popup_font 
 end
 end
 r.ImGui_PushFont(ctx, nil, settings.font_size or 14)
 return 6, true, nil
end

local function PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 if font_pushed then r.ImGui_PopFont(ctx) end
 r.ImGui_PopStyleColor(ctx, color_count or 6)
end

local function round_to_grid(px, grid)
    if grid and grid > 1 then
        return math.floor((px + grid/2) / grid) * grid
    end
    return px
end

local function draw_grid(ctx, color, grid_px, snap_mode)
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
    local snap_mode = settings and settings.edit_snap_mode
    local grid_px = settings and (settings.edit_grid_size_px or 16) or 16
    local grid_color = settings and (settings.edit_grid_color or 0xFFFFFF22) or 0xFFFFFF22
    if edit_mode and settings and settings.edit_grid_show then
        draw_grid(ctx, grid_color, grid_px, snap and snap_mode or nil)
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

    local active_toggle = nil
    for _, btn in ipairs(custom_buttons.buttons) do
        if btn.is_group_visibility_toggle and btn.toggle_state then
            active_toggle = btn
            break
        end
    end

    for i, button in ipairs(custom_buttons.buttons) do
        local should_show = true
        
        if active_toggle then
            should_show = false
            if button.is_group_visibility_toggle then
                should_show = true
            elseif button.group and button.group ~= "" then
                -- Check if cycle mode
                if active_toggle.toggle_mode == "cycle" and active_toggle.cycle_views then
                    local current_view_idx = active_toggle.cycle_current_view or 1
                    local current_view = active_toggle.cycle_views[current_view_idx]
                    if current_view and current_view.visible_groups then
                        should_show = current_view.visible_groups[button.group] == true
                    end
                elseif active_toggle.visible_groups then
                    should_show = active_toggle.visible_groups[button.group] == true
                end
            end
        end
        
        if button.visible and should_show then
            r.ImGui_SameLine(ctx)
            
            local font_pushed = false
            if button.font_name and button.font_size then
                if not button.font or not r.ImGui_ValidatePtr(button.font, 'ImGui_Font*') then
                    button.font = r.ImGui_CreateFont(button.font_name, button.font_size)
                    if button.font then
                        r.ImGui_Attach(ctx, button.font)
                    end
                end
                
                if button.font and r.ImGui_ValidatePtr(button.font, 'ImGui_Font*') then
                    r.ImGui_PushFont(ctx, button.font, button.font_size)
                    font_pushed = true
                end
            end


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
            
            local toggle_state = nil
            if button.show_toggle_state then
                if button.is_group_visibility_toggle then
                    toggle_state = button.toggle_state and 1 or 0
                elseif button.left_click and button.left_click.command then
                    local command_id = button.left_click.command
                    
                    if type(command_id) == "string" then
                        command_id = r.NamedCommandLookup(command_id)
                    end
                    
                    if command_id and command_id ~= 0 then
                        -- Check if it's a MIDI editor command
                        local cmd_type = button.left_click.type
                        if cmd_type == 1 then
                            -- MIDI Editor command
                            local editor = r.MIDIEditor_GetActive()
                            if editor then
                                toggle_state = r.GetToggleCommandStateEx(32060, command_id)
                            end
                        else
                            -- Main action
                            toggle_state = r.GetToggleCommandState(command_id)
                        end
                    end
                end
            end
            
            -- Apply transparency to custom buttons if enabled
            -- If toggle state is ON and toggle colors are defined, use toggle colors
            local btn_color, btn_hover_color, btn_active_color
            
            if toggle_state == 1 and button.toggle_on_color then
                -- Toggle is ON - use toggle_on_color
                btn_color = ApplyButtonTransparency(button.toggle_on_color, settings)
                btn_hover_color = ApplyButtonTransparency(button.toggle_on_color, settings)
                btn_active_color = ApplyButtonTransparency(button.toggle_on_color, settings)
            elseif toggle_state == 0 and button.toggle_off_color then
                -- Toggle is OFF - use toggle_off_color
                btn_color = ApplyButtonTransparency(button.toggle_off_color, settings)
                btn_hover_color = ApplyButtonTransparency(button.toggle_off_color, settings)
                btn_active_color = ApplyButtonTransparency(button.toggle_off_color, settings)
            else
                -- No toggle state or no toggle colors defined - use normal colors
                btn_color = ApplyButtonTransparency(button.color, settings)
                btn_hover_color = ApplyButtonTransparency(button.hover_color, settings)
                btn_active_color = ApplyButtonTransparency(button.active_color, settings)
            end
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button.text_color)
            
            local style_var_count = 0
            if button.rounding then
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), button.rounding)
                style_var_count = style_var_count + 1
            end
            
            -- Handle border: show_border=false always overrides border_thickness
            local border_for_button = (button.show_border ~= false) and 1 or 0
            if border_for_button == 0 then
                -- show_border is false, force border to 0
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
                style_var_count = style_var_count + 1
            elseif button.border_thickness then
                -- show_border is true and border_thickness is set
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), button.border_thickness)
                style_var_count = style_var_count + 1
            end
            local draw_w = button.width
            if scale_sizes and draw_w and draw_w > 0 then
                draw_w = math.max(1, math.floor(draw_w * scale_w))
            end

            if button.use_image and button.image_path then
                if not r.ImGui_ValidatePtr(ButtonRenderer.image_cache[button.image_path], 'ImGui_Image*') then
                    if r.file_exists(button.image_path) then
                        ButtonRenderer.image_cache[button.image_path] = r.ImGui_CreateImage(button.image_path)
                    else
                        button.use_image = false
                        button.image_path = nil
                    end
                end
                button.image = ButtonRenderer.image_cache[button.image_path]
            
                if r.ImGui_ValidatePtr(button.image, 'ImGui_Image*') then
                    local img_w, img_h = r.ImGui_Image_GetSize(button.image)
                    
                    local max_width = draw_w
                    local display_w, display_h
                    
                    if img_w > 0 and img_h > 0 then
                        local scale = math.min(max_width / img_w, 1.0)
                        display_w = img_w * scale
                        display_h = img_h * scale
                    else
                        display_w = max_width
                        display_h = max_width
                    end
                    
                    if button.show_text_with_icon and button.name and button.name ~= "" then
                        local text_pos = button.text_position or "right"
                        local image_padding = (button.show_border ~= false) and 4 or 0
                        local text_w, text_h = r.ImGui_CalcTextSize(ctx, button.name)
                        
                        local btn_color = ApplyButtonTransparency(button.color, settings)
                        local btn_hover_color = ApplyButtonTransparency(button.hover_color, settings)
                        local btn_active_color = ApplyButtonTransparency(button.active_color, settings)
                        
                        if text_pos == "left" or text_pos == "right" then
                            local separator_width = (button.show_border ~= false) and 12 or 4
                            local padding = 8
                            local total_width = image_padding + display_w + separator_width + text_w + padding
                            
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button.text_color)
                            
                            local cursorX, cursorY = r.ImGui_GetCursorPos(ctx)
                            local clicked = r.ImGui_Button(ctx, "##btn" .. i, total_width, display_h)
                            
                            local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx)
                            local button_max_x, button_max_y = r.ImGui_GetItemRectMax(ctx)
                            
                            if text_pos == "left" then
                                local text_offset = (button.show_border ~= false) and 12 or 4
                                r.ImGui_SetCursorPos(ctx, cursorX + padding, cursorY + (display_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5)
                                r.ImGui_Text(ctx, button.name)
                                
                                local win_x, win_y = r.ImGui_GetWindowPos(ctx)
                                local img_x1 = win_x + cursorX + text_w + text_offset
                                local img_y1 = win_y + cursorY
                                local img_x2 = img_x1 + display_w
                                local img_y2 = img_y1 + display_h
                                
                                local dl = r.ImGui_GetWindowDrawList(ctx)
                                local rounding = button.rounding or 0
                                r.ImGui_DrawList_AddImageRounded(dl, button.image, img_x1, img_y1, img_x2, img_y2, 0, 0, 1, 1, 0xFFFFFFFF, rounding)
                                
                                if button.show_border ~= false then
                                    local separator_x = win_x + cursorX + text_w + 6
                                    local separator_y1 = win_y + cursorY + 2
                                    local separator_y2 = win_y + cursorY + display_h - 2
                                    local sep_color = button.border_color or 0xFFFFFFFF
                                    local thickness = button.border_thickness or 1.0
                                    r.ImGui_DrawList_AddLine(dl, separator_x, separator_y1, separator_x, separator_y2, sep_color, thickness)
                                end
                            else
                                local win_x, win_y = r.ImGui_GetWindowPos(ctx)
                                local img_x1 = win_x + cursorX + image_padding
                                local img_y1 = win_y + cursorY
                                local img_x2 = img_x1 + display_w
                                local img_y2 = img_y1 + display_h
                                
                                local dl = r.ImGui_GetWindowDrawList(ctx)
                                local rounding = button.rounding or 0
                                r.ImGui_DrawList_AddImageRounded(dl, button.image, img_x1, img_y1, img_x2, img_y2, 0, 0, 1, 1, 0xFFFFFFFF, rounding)
                                
                                local text_offset = (button.show_border ~= false) and 12 or 4
                                r.ImGui_SetCursorPos(ctx, cursorX + image_padding + display_w + text_offset, cursorY + (display_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5)
                                r.ImGui_Text(ctx, button.name)
                                
                                if button.show_border ~= false then
                                    local win_x, win_y = r.ImGui_GetWindowPos(ctx)
                                    local separator_x = win_x + cursorX + image_padding + display_w + 6
                                    local separator_y1 = win_y + cursorY + 2
                                    local separator_y2 = win_y + cursorY + display_h - 2
                                    local dl = r.ImGui_GetWindowDrawList(ctx)
                                    local sep_color = button.border_color or 0xFFFFFFFF
                                    local thickness = button.border_thickness or 1.0
                                    r.ImGui_DrawList_AddLine(dl, separator_x, separator_y1, separator_x, separator_y2, sep_color, thickness)
                                end
                            end
                            
                            r.ImGui_PopStyleColor(ctx, 4)
                            
                            if clicked and not edit_mode then
                                ExecuteButtonAction(ctx, button)
                            end
                            
                            if button.show_border ~= false then
                                local dl = r.ImGui_GetWindowDrawList(ctx)
                                local col = button.border_color or 0xFFFFFFFF
                                local thickness = button.border_thickness or 1.0
                                r.ImGui_DrawList_AddRect(dl, button_min_x, button_min_y, button_max_x, button_max_y, col, button.rounding or 0, nil, thickness)
                            end
                            
                        elseif text_pos == "bottom" or text_pos == "top" then
                            local total_width = math.max(display_w, text_w) + image_padding * 2
                            local total_height = display_h + text_h + 4
                            
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), button.text_color)
                            
                            local cursorX, cursorY = r.ImGui_GetCursorPos(ctx)
                            local clicked = r.ImGui_Button(ctx, "##btn" .. i, total_width, total_height)
                            
                            local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx)
                            local button_max_x, button_max_y = r.ImGui_GetItemRectMax(ctx)
                            
                            local win_x, win_y = r.ImGui_GetWindowPos(ctx)
                            local dl = r.ImGui_GetWindowDrawList(ctx)
                            local rounding = button.rounding or 0
                            
                            if text_pos == "top" then
                                r.ImGui_SetCursorPos(ctx, cursorX + (total_width - text_w) * 0.5, cursorY + 2)
                                r.ImGui_Text(ctx, button.name)
                                
                                local img_x1 = win_x + cursorX + (total_width - display_w) * 0.5
                                local img_y1 = win_y + cursorY + text_h + 2
                                local img_x2 = img_x1 + display_w
                                local img_y2 = img_y1 + display_h
                                r.ImGui_DrawList_AddImageRounded(dl, button.image, img_x1, img_y1, img_x2, img_y2, 0, 0, 1, 1, 0xFFFFFFFF, rounding)
                            else
                                local img_x1 = win_x + cursorX + (total_width - display_w) * 0.5
                                local img_y1 = win_y + cursorY
                                local img_x2 = img_x1 + display_w
                                local img_y2 = img_y1 + display_h
                                r.ImGui_DrawList_AddImageRounded(dl, button.image, img_x1, img_y1, img_x2, img_y2, 0, 0, 1, 1, 0xFFFFFFFF, rounding)
                                r.ImGui_SetCursorPos(ctx, cursorX + (total_width - text_w) * 0.5, cursorY + display_h + 2)
                                r.ImGui_Text(ctx, button.name)
                            end
                            
                            r.ImGui_PopStyleColor(ctx, 4)
                            
                            if clicked and not edit_mode then
                                ExecuteButtonAction(ctx, button)
                            end
                            
                            if button.show_border ~= false then
                                local dl = r.ImGui_GetWindowDrawList(ctx)
                                local col = button.border_color or 0xFFFFFFFF
                                local thickness = button.border_thickness or 1.0
                                r.ImGui_DrawList_AddRect(dl, button_min_x, button_min_y, button_max_x, button_max_y, col, button.rounding or 0, nil, thickness)
                            end
                            
                        elseif text_pos:match("^overlay") then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover_color)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active_color)
                            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
                            
                            local cursorX, cursorY = r.ImGui_GetCursorPos(ctx)
                            local clicked = r.ImGui_Button(ctx, "##btn" .. i, display_w, display_h)
                            
                            local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx)
                            local button_max_x, button_max_y = r.ImGui_GetItemRectMax(ctx)
                            
                            local dl = r.ImGui_GetWindowDrawList(ctx)
                            local rounding = button.rounding or 0
                            r.ImGui_DrawList_AddImageRounded(dl, button.image, button_min_x, button_min_y, button_max_x, button_max_y, 0, 0, 1, 1, 0xFFFFFFFF, rounding)
                            
                            local text_x, text_y
                            
                            if text_pos == "overlay" then
                                text_x = button_min_x + (display_w - text_w) * 0.5
                                text_y = button_min_y + (display_h - text_h) * 0.5
                            elseif text_pos == "overlay_bottom" then
                                text_x = button_min_x + (display_w - text_w) * 0.5
                                text_y = button_min_y + display_h - text_h - 5
                            elseif text_pos == "overlay_top" then
                                text_x = button_min_x + (display_w - text_w) * 0.5
                                text_y = button_min_y + 5
                            end
                            
                            r.ImGui_DrawList_AddText(dl, text_x, text_y, button.text_color or 0xFFFFFFFF, button.name)
                            
                            r.ImGui_PopStyleVar(ctx)
                            r.ImGui_PopStyleColor(ctx, 3)
                            
                            if clicked and not edit_mode then
                                ExecuteButtonAction(ctx, button)
                            end
                            
                            if button.show_border ~= false then
                                local dl = r.ImGui_GetWindowDrawList(ctx)
                                local col = button.border_color or 0xFFFFFFFF
                                local thickness = button.border_thickness or 1.0
                                r.ImGui_DrawList_AddRect(dl, button_min_x, button_min_y, button_max_x, button_max_y, col, button.rounding or 0, nil, thickness)
                            end
                        end
                        
                        if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                            local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                            local alt_tip = button.alt_left_click and (button.alt_left_click.name or button.alt_left_click.command) or nil
                            local shift_tip = button.shift_left_click and (button.shift_left_click.name or button.shift_left_click.command) or nil
                            local ctrl_tip = button.ctrl_left_click and (button.ctrl_left_click.name or button.ctrl_left_click.command) or nil
                            if (tip and tip ~= "") or (alt_tip and alt_tip ~= "") or (shift_tip and shift_tip ~= "") or (ctrl_tip and ctrl_tip ~= "") then
                                local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
                                r.ImGui_BeginTooltip(ctx)
                                if tip and tip ~= "" then
                                    r.ImGui_Text(ctx, tostring(tip))
                                end
                                if alt_tip and alt_tip ~= "" then
                                    r.ImGui_Text(ctx, "Alt: " .. tostring(alt_tip))
                                end
                                if shift_tip and shift_tip ~= "" then
                                    r.ImGui_Text(ctx, "Shift: " .. tostring(shift_tip))
                                end
                                if ctrl_tip and ctrl_tip ~= "" then
                                    r.ImGui_Text(ctx, "Ctrl: " .. tostring(ctrl_tip))
                                end
                                if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                                    r.ImGui_Separator(ctx)
                                    r.ImGui_Text(ctx, "Right-click for menu")
                                end
                                r.ImGui_EndTooltip(ctx)
                                PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
                            end
                        end
                        
                        if r.ImGui_IsItemClicked(ctx, 1) and not edit_mode then
                            r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                        end
                    else
                        local btn_color = ApplyButtonTransparency(button.color, settings)
                        local btn_hover_color = ApplyButtonTransparency(button.hover_color, settings)
                        local btn_active_color = ApplyButtonTransparency(button.active_color, settings)
                        
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_color)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover_color)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active_color)
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
                        
                        local cursorX, cursorY = r.ImGui_GetCursorPos(ctx)
                        local clicked = r.ImGui_Button(ctx, "##btn" .. i, display_w, display_h)
                        
                        local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx)
                        local button_max_x, button_max_y = r.ImGui_GetItemRectMax(ctx)
                        
                        local dl = r.ImGui_GetWindowDrawList(ctx)
                        local rounding = button.rounding or 0
                        r.ImGui_DrawList_AddImageRounded(dl, button.image, button_min_x, button_min_y, button_max_x, button_max_y, 0, 0, 1, 1, 0xFFFFFFFF, rounding)
                        
                        r.ImGui_PopStyleVar(ctx)
                        r.ImGui_PopStyleColor(ctx, 3)
                        
                        if clicked and not edit_mode then
                            ExecuteButtonAction(ctx, button)
                        end
                        
                        if button.show_border ~= false then
                            local dl = r.ImGui_GetWindowDrawList(ctx)
                            local col = button.border_color or 0xFFFFFFFF
                            local thickness = button.border_thickness or 1.0
                            r.ImGui_DrawList_AddRect(dl, button_min_x, button_min_y, button_max_x, button_max_y, col, button.rounding or 0, nil, thickness)
                        end

                        if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                            local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                            local alt_tip = button.alt_left_click and (button.alt_left_click.name or button.alt_left_click.command) or nil
                            local shift_tip = button.shift_left_click and (button.shift_left_click.name or button.shift_left_click.command) or nil
                            local ctrl_tip = button.ctrl_left_click and (button.ctrl_left_click.name or button.ctrl_left_click.command) or nil
                            if (tip and tip ~= "") or (alt_tip and alt_tip ~= "") or (shift_tip and shift_tip ~= "") or (ctrl_tip and ctrl_tip ~= "") then
                                local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
                                r.ImGui_BeginTooltip(ctx)
                                if tip and tip ~= "" then
                                    r.ImGui_Text(ctx, tostring(tip))
                                end
                                if alt_tip and alt_tip ~= "" then
                                    r.ImGui_Text(ctx, "Alt: " .. tostring(alt_tip))
                                end
                                if shift_tip and shift_tip ~= "" then
                                    r.ImGui_Text(ctx, "Shift: " .. tostring(shift_tip))
                                end
                                if ctrl_tip and ctrl_tip ~= "" then
                                    r.ImGui_Text(ctx, "Ctrl: " .. tostring(ctrl_tip))
                                end
                                if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                                    r.ImGui_Separator(ctx)
                                    r.ImGui_Text(ctx, "Right-click for menu")
                                end
                                r.ImGui_EndTooltip(ctx)
                                PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
                            end
                        end
                        
                        if r.ImGui_IsItemClicked(ctx, 1) and not edit_mode then
                            r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                        end
                    end
                end
            elseif button.use_icon and button.icon_name then
                if not r.ImGui_ValidatePtr(ButtonRenderer.image_cache[button.icon_name], 'ImGui_Image*') then
                    local icon_path
                    if button.icon_name:match("^/") or button.icon_name:match("^[A-Za-z]:") then
                        icon_path = button.icon_name
                    else
                        icon_path = resource_path .. "/Data/toolbar_icons/" .. button.icon_name
                    end
                    if r.file_exists(icon_path) then
                        ButtonRenderer.image_cache[button.icon_name] = r.ImGui_CreateImage(icon_path)
                    else
                        button.use_icon = false
                        button.icon_name = nil
                    end
                end
                button.icon = ButtonRenderer.image_cache[button.icon_name]
            
                if r.ImGui_ValidatePtr(button.icon, 'ImGui_Image*') then
                    if button.show_text_with_icon and button.name and button.name ~= "" then
                        local icon_size = draw_w 
                        local text_label = button.name .. "##btn" .. i
                        
                        local cursorX, cursorY = r.ImGui_GetCursorPos(ctx)
                        
                        local icon_padding = (button.show_border ~= false) and 4 or 0  
                        local text_size = r.ImGui_CalcTextSize(ctx, button.name)
                        local separator_width = (button.show_border ~= false) and 12 or 4  
                        local padding = 8  
                        local total_width = icon_padding + icon_size + separator_width + text_size + padding
                        
                        
                        local clicked = r.ImGui_Button(ctx, "##btn" .. i, total_width, icon_size)
                        
                        local is_hovered = r.ImGui_IsItemHovered(ctx)
                        local is_active = r.ImGui_IsItemActive(ctx)
                        local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx)
                        local button_max_x, button_max_y = r.ImGui_GetItemRectMax(ctx)
                        
                        local icon_padding = (button.show_border ~= false) and 4 or 0
                        r.ImGui_SetCursorPos(ctx, cursorX + icon_padding, cursorY)
                        
                        local uv_x = 0
                        
                        if toggle_state ~= nil and button.show_toggle_state then
                            if toggle_state == 1 then
                                uv_x = 0.66
                            else
                                uv_x = 0
                            end
                        else
                            -- Normal behavior: hover and active states
                            if is_hovered then
                                uv_x = 0.33
                            end
                            if is_active then
                                uv_x = 0.66
                            end
                        end
                        
                        r.ImGui_Image(ctx, button.icon, icon_size, icon_size, uv_x, 0, uv_x + 0.33, 1)
                        
                        local text_offset = (button.show_border ~= false) and 12 or 4 
                        r.ImGui_SameLine(ctx, cursorX + icon_padding + icon_size + text_offset, 0)
                        r.ImGui_SetCursorPosY(ctx, cursorY + (icon_size - r.ImGui_GetTextLineHeight(ctx)) * 0.5)
                        r.ImGui_Text(ctx, button.name)
                        
                        if button.show_border ~= false then
                            local win_x, win_y = r.ImGui_GetWindowPos(ctx)
                            local separator_x = win_x + cursorX + icon_padding + icon_size + 6 
                            local separator_y1 = win_y + cursorY + 2  
                            local separator_y2 = win_y + cursorY + icon_size - 2  
                            local dl = r.ImGui_GetWindowDrawList(ctx)
                            local sep_color = button.border_color or 0xFFFFFFFF
                            local thickness = button.border_thickness or 1.0
                            r.ImGui_DrawList_AddLine(dl, separator_x, separator_y1, separator_x, separator_y2, sep_color, thickness)
                        end
                        
                        if clicked and not edit_mode then
                            ExecuteButtonAction(ctx, button)
                        end

                        
                        if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                            local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                            local alt_tip = button.alt_left_click and (button.alt_left_click.name or button.alt_left_click.command) or nil
                            local shift_tip = button.shift_left_click and (button.shift_left_click.name or button.shift_left_click.command) or nil
                            local ctrl_tip = button.ctrl_left_click and (button.ctrl_left_click.name or button.ctrl_left_click.command) or nil
                            if (tip and tip ~= "") or (alt_tip and alt_tip ~= "") or (shift_tip and shift_tip ~= "") or (ctrl_tip and ctrl_tip ~= "") then
                                local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
                                r.ImGui_BeginTooltip(ctx)
                                if tip and tip ~= "" then
                                    r.ImGui_Text(ctx, tostring(tip))
                                end
                                if alt_tip and alt_tip ~= "" then
                                    r.ImGui_Text(ctx, "Alt: " .. tostring(alt_tip))
                                end
                                if shift_tip and shift_tip ~= "" then
                                    r.ImGui_Text(ctx, "Shift: " .. tostring(shift_tip))
                                end
                                if ctrl_tip and ctrl_tip ~= "" then
                                    r.ImGui_Text(ctx, "Ctrl: " .. tostring(ctrl_tip))
                                end
                                if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                                    r.ImGui_Separator(ctx)
                                    r.ImGui_Text(ctx, "Right-click for menu")
                                end
                                r.ImGui_EndTooltip(ctx)
                                PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
                            end
                        end
                        
                        if r.ImGui_IsItemClicked(ctx, 1) and not edit_mode then
                            r.ImGui_OpenPopup(ctx, "CustomButtonMenu" .. i)
                        end
                        
                        if button.show_border ~= false then
                            local dl = r.ImGui_GetWindowDrawList(ctx)
                            local col = button.border_color or 0xFFFFFFFF
                            local thickness = button.border_thickness or 1.0
                            r.ImGui_DrawList_AddRect(dl, button_min_x, button_min_y, button_max_x, button_max_y, col, button.rounding or 0, nil, thickness)
                        end
                    else
                        -- Icon only (no text) - Use toggle state for UV coordinates if enabled
                        local btn_color = ApplyButtonTransparency(button.color, settings)
                        local btn_hover_color = ApplyButtonTransparency(button.hover_color, settings)
                        local btn_active_color = ApplyButtonTransparency(button.active_color, settings)
                        
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), btn_color)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), btn_hover_color)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), btn_active_color)
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
                        
                        local cursorX, cursorY = r.ImGui_GetCursorPos(ctx)
                        local clicked = r.ImGui_Button(ctx, "##btn" .. i, draw_w, draw_w)
                        
                        r.ImGui_SetCursorPos(ctx, cursorX, cursorY)
                        
                        -- Determine UV coordinates based on toggle state or hover/active state
                        local uv_x = 0
                        
                        if toggle_state ~= nil and button.show_toggle_state then
                            -- Use toggle state for icon selection
                            if toggle_state == 1 then
                                -- Toggle ON: use 3rd state (active/on state)
                                uv_x = 0.66
                            else
                                -- Toggle OFF: use 1st state (normal/off state)
                                uv_x = 0
                            end
                        else
                            -- Normal behavior: hover and active states
                            if r.ImGui_IsItemHovered(ctx) then
                                uv_x = 0.33
                            end
                            if r.ImGui_IsItemActive(ctx) then
                                uv_x = 0.66
                            end
                        end
                        
                        r.ImGui_Image(ctx, button.icon, draw_w, draw_w, uv_x, 0, uv_x + 0.33, 1)
                        
                        r.ImGui_PopStyleVar(ctx)
                        r.ImGui_PopStyleColor(ctx, 3)
                        
                        if clicked and not edit_mode then
                            ExecuteButtonAction(ctx, button)
                        end
                        if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                            local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                            local alt_tip = button.alt_left_click and (button.alt_left_click.name or button.alt_left_click.command) or nil
                            local shift_tip = button.shift_left_click and (button.shift_left_click.name or button.shift_left_click.command) or nil
                            local ctrl_tip = button.ctrl_left_click and (button.ctrl_left_click.name or button.ctrl_left_click.command) or nil
                            if (tip and tip ~= "") or (alt_tip and alt_tip ~= "") or (shift_tip and shift_tip ~= "") or (ctrl_tip and ctrl_tip ~= "") then
                                local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
                                r.ImGui_BeginTooltip(ctx)
                                if tip and tip ~= "" then
                                    r.ImGui_Text(ctx, tostring(tip))
                                end
                                if alt_tip and alt_tip ~= "" then
                                    r.ImGui_Text(ctx, "Alt: " .. tostring(alt_tip))
                                end
                                if shift_tip and shift_tip ~= "" then
                                    r.ImGui_Text(ctx, "Shift: " .. tostring(shift_tip))
                                end
                                if ctrl_tip and ctrl_tip ~= "" then
                                    r.ImGui_Text(ctx, "Ctrl: " .. tostring(ctrl_tip))
                                end
                                if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                                    r.ImGui_Separator(ctx)
                                    r.ImGui_Text(ctx, "Right-click for menu")
                                end
                                r.ImGui_EndTooltip(ctx)
                                PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
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
                            local thickness = button.border_thickness or 1.0
                            r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, col, button.rounding or 0, nil, thickness)
                        end
                    end
                else
                    button.use_icon = false
                    
                    local label = (button.name ~= "" and button.name or "EmptyButton") .. "##btn"..i
                    if r.ImGui_Button(ctx, label, draw_w) and not edit_mode then
                        ExecuteButtonAction(ctx, button)
                    end
                    if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                        local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                        local alt_tip = button.alt_left_click and (button.alt_left_click.name or button.alt_left_click.command) or nil
                        local shift_tip = button.shift_left_click and (button.shift_left_click.name or button.shift_left_click.command) or nil
                        local ctrl_tip = button.ctrl_left_click and (button.ctrl_left_click.name or button.ctrl_left_click.command) or nil
                        if tip and tip ~= "" then
                            local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
                            r.ImGui_BeginTooltip(ctx)
                            r.ImGui_Text(ctx, tostring(tip))
                            if alt_tip and alt_tip ~= "" then
                                r.ImGui_Text(ctx, "Alt: " .. tostring(alt_tip))
                            end
                            if shift_tip and shift_tip ~= "" then
                                r.ImGui_Text(ctx, "Shift: " .. tostring(shift_tip))
                            end
                            if ctrl_tip and ctrl_tip ~= "" then
                                r.ImGui_Text(ctx, "Ctrl: " .. tostring(ctrl_tip))
                            end
                            if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                                r.ImGui_Separator(ctx)
                                r.ImGui_Text(ctx, "Right-click for menu")
                            end
                            r.ImGui_EndTooltip(ctx)
                            PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
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
                        local thickness = button.border_thickness or 1.0
                        r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, col, button.rounding or 0, nil, thickness)
                    end
                end
            else
                local label = (button.name ~= "" and button.name or "EmptyButton") .. "##btn"..i
                if r.ImGui_Button(ctx, label, draw_w) and not edit_mode then
                    ExecuteButtonAction(ctx, button)
                end
                if (settings and settings.show_custom_button_tooltip) and (not edit_mode) and r.ImGui_IsItemHovered(ctx) then
                    local tip = button.left_click and (button.left_click.name or button.left_click.command) or nil
                    local alt_tip = button.alt_left_click and (button.alt_left_click.name or button.alt_left_click.command) or nil
                    local shift_tip = button.shift_left_click and (button.shift_left_click.name or button.shift_left_click.command) or nil
                    local ctrl_tip = button.ctrl_left_click and (button.ctrl_left_click.name or button.ctrl_left_click.command) or nil
                    if tip and tip ~= "" then
                        local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
                        r.ImGui_BeginTooltip(ctx)
                        r.ImGui_Text(ctx, tostring(tip))
                        if alt_tip and alt_tip ~= "" then
                            r.ImGui_Text(ctx, "Alt: " .. tostring(alt_tip))
                        end
                        if shift_tip and shift_tip ~= "" then
                            r.ImGui_Text(ctx, "Shift: " .. tostring(shift_tip))
                        end
                        if ctrl_tip and ctrl_tip ~= "" then
                            r.ImGui_Text(ctx, "Ctrl: " .. tostring(ctrl_tip))
                        end
                        if button.right_menu and button.right_menu.items and #button.right_menu.items > 0 then
                            r.ImGui_Separator(ctx)
                            r.ImGui_Text(ctx, "Right-click for menu")
                        end
                        r.ImGui_EndTooltip(ctx)
                        PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
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
                    local thickness = button.border_thickness or 1.0
                    r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, col, button.rounding or 0, nil, thickness)
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
                        local snap_mode = settings and settings.edit_snap_mode or "step"
                        if snap_mode == "step" then
                            -- Original behavior: move by grid step size
                            dx = round_to_grid(dx, grid_px) - round_to_grid(0, grid_px)
                            dy = round_to_grid(dy, grid_px) - round_to_grid(0, grid_px)
                        elseif snap_mode == "magnetic" then
                            -- New behavior: snap element position to nearest grid line
                            local wx, wy = r.ImGui_GetWindowPos(ctx)
                            local elem_x = min_x - wx
                            local elem_y = min_y - wy
                            local new_elem_x = elem_x + dx
                            local new_elem_y = elem_y + dy
                            local snapped_x = math.floor((new_elem_x + grid_px/2) / grid_px) * grid_px
                            local snapped_y = math.floor((new_elem_y + grid_px/2) / grid_px) * grid_px
                            dx = snapped_x - elem_x
                            dy = snapped_y - elem_y
                        end
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
                                    b.position_y_px = math.max(-20, math.min(clamp_h, (b.position_y_px or math.floor(0.15 * clamp_h)) + dy_ref))
                                    
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
                            button.position_y_px = math.max(-20, math.min(clamp_h, (button.position_y_px or math.floor(0.15 * clamp_h)) + dy_ref))
                            
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
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 local has_folders = false
 for _, it in ipairs(button.right_menu.items) do
 if it.is_submenu then has_folders = true break end
 end
 
 if has_folders then
 RenderMenuWithFolders(ctx, button.right_menu.items)
 else
 for _, it in ipairs(button.right_menu.items) do
 if r.ImGui_MenuItem(ctx, it.name) then
 ExecuteMenuItem(it)
 end
 end
 end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end            r.ImGui_PopStyleColor(ctx, 4)
            if style_var_count > 0 then
                r.ImGui_PopStyleVar(ctx, style_var_count)
            end
            
            if font_pushed then
                r.ImGui_PopFont(ctx)
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

function RenderMenuWithFolders(ctx, items)
    for idx, it in ipairs(items) do
        if not it.parent_id then
            if it.is_submenu then
                if r.ImGui_BeginMenu(ctx, it.name) then
                    for child_idx, child_it in ipairs(items) do
                        if child_it.parent_id == it.unique_id then
                            if child_it.is_submenu then
                                RenderMenuFolder(ctx, items, child_it)
                            else
                                if r.ImGui_MenuItem(ctx, child_it.name) then
                                    ExecuteMenuItem(child_it)
                                end
                            end
                        end
                    end
                    r.ImGui_EndMenu(ctx)
                end
            else
                if r.ImGui_MenuItem(ctx, it.name) then
                    ExecuteMenuItem(it)
                end
            end
        end
    end
end

function RenderMenuFolder(ctx, items, folder)
    if r.ImGui_BeginMenu(ctx, folder.name) then
        for child_idx, child_it in ipairs(items) do
            if child_it.parent_id == folder.unique_id then
                if child_it.is_submenu then
                    RenderMenuFolder(ctx, items, child_it)
                else
                    if r.ImGui_MenuItem(ctx, child_it.name) then
                        ExecuteMenuItem(child_it)
                    end
                end
            end
        end
        r.ImGui_EndMenu(ctx)
    end
end

local function new_menu_node()
    return { children = {}, entries = {} }
end

local function ensure_submenu(current, segment)
    local child = current.children[segment]
    if not child then
        child = new_menu_node()
        current.children[segment] = child
        table.insert(current.entries, { type = 'submenu', name = segment, node = child })
    end
    return child
end

function BuildMenuTree(items)
    local root = new_menu_node()
    for _, it in ipairs(items or {}) do
        local raw_name = it.name or ''
        local segments = {}
        for segment in raw_name:gmatch('[^/]+') do
            segments[#segments + 1] = segment
        end

        if #segments == 0 then
            table.insert(root.entries, { type = 'item', label = raw_name, item = it })
        else
            local current = root
            for idx, segment in ipairs(segments) do
                if idx == #segments then
                    table.insert(current.entries, { type = 'item', label = segment, item = it })
                else
                    current = ensure_submenu(current, segment)
                end
            end
        end
    end
    return root
end

function RenderMenuTree(ctx, node)
    for _, entry in ipairs(node.entries or {}) do
        if entry.type == 'item' then
            if r.ImGui_MenuItem(ctx, entry.label or '') then
                ExecuteMenuItem(entry.item)
            end
        elseif entry.type == 'submenu' then
            if r.ImGui_BeginMenu(ctx, entry.name or '') then
                RenderMenuTree(ctx, entry.node)
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

function ButtonRenderer.Cleanup(ctx)
    -- Cleanup popup fonts
    for key, font in pairs(ButtonRenderer.popup_font_cache) do
        if r.ImGui_ValidatePtr(font, 'ImGui_Font*') then
            r.ImGui_Detach(ctx, font)
        end
    end
    ButtonRenderer.popup_font_cache = {}
    
    -- Cleanup image cache
    for key, img in pairs(ButtonRenderer.image_cache) do
        ButtonRenderer.image_cache[key] = nil
    end
    
    collectgarbage("collect")
end

return ButtonRenderer
