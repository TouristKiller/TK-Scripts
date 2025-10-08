local r = reaper
local resource_path = r.GetResourcePath()
local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/-]-$]])
local button_presets_path = script_path .. "tk_transport_buttons/presets/"
local IconBrowser = require('icon_browser')
local ButtonEditor = {}
local new_preset_name = ""
local new_group_name = ""
local has_unsaved_changes = false
local active_icon_button = nil  -- Track which button is selecting an icon

local cb_section_states = {
    basic_open = true,
    group_open = false,
    colors_open = false,
    left_open = false,
    right_open = false,
    actions_open = false,  
}

local import_window = {
    open = false,
    ctx = nil,
    title = "Import Buttons from Other Presets"
}

local icon_check_window = {
    open = false,
    ctx = nil,
    title = "Icon Health Check"
}

local function to_int(value, default)
    value = tonumber(value)
    if not value then return default end
    return math.floor(value + 0.5)
end

local function clamp(value, min_val, max_val)
    if min_val and value < min_val then value = min_val end
    if max_val and value > max_val then value = max_val end
    return value
end

local function sanitize_button_xy(button, canvas_width, canvas_height)
    canvas_width = clamp(to_int(canvas_width, 1), 1)
    canvas_height = clamp(to_int(canvas_height, 1), 1)

    local changed = false

    local orig_px = button.position_px
    local orig_frac_x = button.position
    local px = tonumber(orig_px)
    if px == nil then
        px = (tonumber(button.position) or 0) * canvas_width
    end
    local new_px = clamp(to_int(px, 0), 0, canvas_width)
    if new_px ~= orig_px then changed = true end
    button.position_px = new_px

    local new_frac_x = (tonumber(new_px) or 0) / math.max(1, canvas_width)
    if orig_frac_x == nil or math.abs(new_frac_x - orig_frac_x) > 1e-9 then
        changed = true
        button.position = new_frac_x
    end

    local fallback_y = (tonumber(button.position_y) or 0.15) * canvas_height
    local orig_py = button.position_y_px
    local orig_frac_y = button.position_y
    local py = tonumber(orig_py)
    if py == nil then
        py = fallback_y
    end
    local new_py = clamp(to_int(py, fallback_y), 0, canvas_height)
    if new_py ~= orig_py then changed = true end
    button.position_y_px = new_py

    local new_frac_y = (tonumber(new_py) or 0) / math.max(1, canvas_height)
    if orig_frac_y == nil or math.abs(new_frac_y - orig_frac_y) > 1e-9 then
        changed = true
        button.position_y = new_frac_y
    end

    return canvas_width, canvas_height, changed
end

local function ShowCBSectionHeader(ctx, title, state_key)
    r.ImGui_Text(ctx, title)
    r.ImGui_SameLine(ctx)
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

local function MoveItemToPosition(t, from, to)
    if from == to or from < 1 or from > #t or to < 1 or to > #t then 
        return false 
    end
    
    local item = table.remove(t, from)
    local insert_pos = to
    if from < to then
        insert_pos = to - 1
    end
    table.insert(t, insert_pos, item)
    return true
end

local function EnsureUniqueIDs(items)
    local max_id = 0
    for _, item in ipairs(items) do
        if item.unique_id and item.unique_id > max_id then
            max_id = item.unique_id
        end
    end
    for _, item in ipairs(items) do
        if not item.unique_id then
            max_id = max_id + 1
            item.unique_id = max_id
        end
    end
    return max_id
end

local function GetIndexByID(items, unique_id)
    if not unique_id then return nil end
    for idx, item in ipairs(items) do
        if item.unique_id == unique_id then
            return idx
        end
    end
    return nil
end

local function GetItemDepth(items, item)
    if not item.parent_id then return 0 end
    
    local depth = 0
    local current_parent_id = item.parent_id
    
    while current_parent_id and depth < 10 do 
        depth = depth + 1
        local parent_item = nil
        for _, it in ipairs(items) do
            if it.unique_id == current_parent_id then
                parent_item = it
                break
            end
        end
        if not parent_item then break end
        current_parent_id = parent_item.parent_id
    end
    
    return depth
end

local function GetFolderColor(depth)
    local colors = {
        [0] = 0x4A5A7A88,  -- Level 0: Blue-purple
        [1] = 0x5A6A4A88,  -- Level 1: Green-grey
        [2] = 0x7A5A4A88,  -- Level 2: Brown-orange
        [3] = 0x6A4A7A88,  -- Level 3: Purple
    }
    return colors[depth] or colors[3] 
end

local function GetDisplayOrder(items)
    local display_order = {}
    
    local function AddItemAndChildren(idx, item, depth)
        table.insert(display_order, {idx = idx, depth = depth or 0})
        
        if item.is_submenu then
            for child_idx, child_item in ipairs(items) do
                if child_item.parent_id == item.unique_id then
                    AddItemAndChildren(child_idx, child_item, (depth or 0) + 1)
                end
            end
        end
    end
    
    for idx, item in ipairs(items) do
        if not item.parent_id then
            AddItemAndChildren(idx, item, 0)
        end
    end
    
    return display_order
end



function ButtonEditor.ShowPresetsInline(ctx, custom_buttons, opts)
    opts = opts or {}
    local presets = custom_buttons.GetButtonPresets()
    local current_preset = custom_buttons.current_preset or "Select Preset"
    local avail_w1, _ = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetNextItemWidth(ctx, math.max(120, math.floor(avail_w1 * 0.3))) -- Reduced from 0.35 to 0.3
    if r.ImGui_BeginCombo(ctx, "##ButtonPresetCombo", current_preset) then
        for _, preset in ipairs(presets) do
            if preset and type(preset) == "string" then
                if r.ImGui_Selectable(ctx, preset, preset == current_preset) then
                    custom_buttons.LoadButtonPreset(preset)
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                    has_unsaved_changes = false
                end
                if preset == current_preset then r.ImGui_SetItemDefaultFocus(ctx) end
            end
        end
        r.ImGui_EndCombo(ctx)
    end

    r.ImGui_SameLine(ctx)
    local had_unsaved = has_unsaved_changes
    if had_unsaved then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xAA2222FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xDD3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF4444FF)
    end
    if r.ImGui_Button(ctx, "Resave") and custom_buttons.current_preset then
        custom_buttons.SaveButtonPreset(custom_buttons.current_preset)
        has_unsaved_changes = false
    end
    if had_unsaved then
        r.ImGui_PopStyleColor(ctx, 3)
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Delete") and custom_buttons.current_preset then
        custom_buttons.DeleteButtonPreset(custom_buttons.current_preset)
    end

    if not new_preset_name then new_preset_name = "" end
    r.ImGui_SameLine(ctx)
    local avail_w2, _ = r.ImGui_GetContentRegionAvail(ctx)
    local save_tw, _ = r.ImGui_CalcTextSize(ctx, "Save As New")
    local save_btn_w = save_tw + 18
    local input_w = math.max(100, math.floor(avail_w2 - save_btn_w - 80)) -- Reduced width for Action button
    r.ImGui_SetNextItemWidth(ctx, input_w)
    local rv
    rv, new_preset_name = r.ImGui_InputText(ctx, "##ButtonNewPreset", new_preset_name)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Save As New") and new_preset_name ~= "" then
        custom_buttons.SaveButtonPreset(new_preset_name)
        if r.file_exists(button_presets_path .. new_preset_name .. '.json') then
            new_preset_name = ""
        end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Action") and custom_buttons.current_preset then
        r.ShowConsoleMsg("Attempting to create action for: " .. custom_buttons.current_preset .. "\n")
        local cmd_id = custom_buttons.RegisterCommandToLoadPreset(custom_buttons.current_preset)
        r.ShowConsoleMsg("Command ID: " .. tostring(cmd_id) .. "\n")
        if cmd_id ~= 0 then
            r.ImGui_OpenPopup(ctx, "ActionCreatedPopup")
        end
    end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Creates an Action that loads this preset (for keybinds/toolbars)")
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

function ButtonEditor.ShowEditorInline(ctx, custom_buttons, settings, opts)
    opts = opts or {}
    if not opts.skip_presets then
        ButtonEditor.ShowPresetsInline(ctx, custom_buttons)
    end

    if custom_buttons.current_edit then
        local button = custom_buttons.buttons[custom_buttons.current_edit]
        local changed = false

    if not cb_section_states.actions_open then
        do
            local has_sel = custom_buttons.current_edit ~= nil
            
            local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
            local rv
            
            if has_sel then
                local button = custom_buttons.buttons[custom_buttons.current_edit]
                rv, button.visible = r.ImGui_Checkbox(ctx, "Visible", button.visible)
                if rv then
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                end
            else
                r.ImGui_BeginDisabled(ctx)
                r.ImGui_Checkbox(ctx, "Visible", false)
                r.ImGui_EndDisabled(ctx)
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_Dummy(ctx, 8, 0)
            r.ImGui_SameLine(ctx)
            
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            local name_w = 120
            r.ImGui_SetNextItemWidth(ctx, name_w)
            
            local current_name = ""
            if has_sel then current_name = custom_buttons.buttons[custom_buttons.current_edit].name or "" end
            local rvn, newname = r.ImGui_InputText(ctx, "##cb_name_inline", current_name)
            if rvn and has_sel then
                custom_buttons.buttons[custom_buttons.current_edit].name = newname
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_Dummy(ctx, 8, 0)
            r.ImGui_SameLine(ctx)
            
            r.ImGui_Text(ctx, "Group")
            r.ImGui_SameLine(ctx)
            
            local delete_w = 65
            local cursor_x = select(1, r.ImGui_GetCursorPos(ctx))
            local group_w = math.max(80, avail_w - cursor_x - delete_w - 16)
            r.ImGui_SetNextItemWidth(ctx, group_w)
            
            if has_sel then
                local button = custom_buttons.buttons[custom_buttons.current_edit]
                local group_set, existing_groups = {}, {}
                for _, b in ipairs(custom_buttons.buttons) do
                    local g = b.group
                    if g and g ~= "" and not group_set[g] then
                        group_set[g] = true
                        table.insert(existing_groups, g)
                    end
                end
                table.sort(existing_groups, function(a,b) return a:lower() < b:lower() end)
                
                local current_group_label = (button.group and button.group ~= "") and button.group or "(none)"
                if r.ImGui_BeginCombo(ctx, "##ExistingGroupInline", current_group_label) then
                    if r.ImGui_Selectable(ctx, "(none)", current_group_label == "(none)") then
                        button.group = ""
                        custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                    end
                    for _, g in ipairs(existing_groups) do
                        if r.ImGui_Selectable(ctx, g, button.group == g) then
                            button.group = g
                            custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                        end
                        if button.group == g then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end
            else
                r.ImGui_BeginDisabled(ctx)
                r.ImGui_BeginCombo(ctx, "##ExistingGroupInline_disabled", "(none)")
                r.ImGui_EndCombo(ctx)
                r.ImGui_EndDisabled(ctx)
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Dummy(ctx, 8, 0)
            r.ImGui_SameLine(ctx)
            local can_delete = has_sel
            if r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, not can_delete) end
            if r.ImGui_Button(ctx, "Delete", delete_w, 0) and can_delete then
                table.remove(custom_buttons.buttons, custom_buttons.current_edit)
                custom_buttons.current_edit = nil
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        end
        
        local canvas_width, canvas_height

        do
            local editor_width  = math.floor((r.ImGui_GetWindowWidth(ctx) or 0) + 0.5)
            local editor_height = math.floor((r.ImGui_GetWindowHeight(ctx) or 0) + 0.5)
            canvas_width  = math.max(editor_width, math.floor(((opts and opts.canvas_width) or 0) + 0.5))
            canvas_height = math.max(editor_height, math.floor(((opts and opts.canvas_height) or 0) + 0.5))
            if canvas_width <= 0 then canvas_width = math.max(1, editor_width) end
            if canvas_height <= 0 then canvas_height = math.max(1, editor_height) end
            if canvas_width <= 0 then canvas_width = 1 end
            if canvas_height <= 0 then canvas_height = 1 end

            local sanitized_width = clamp(to_int(button.width, 60), 12, 400)
            if sanitized_width ~= button.width then
                button.width = sanitized_width
                changed = true
            end

            local _, _, xy_changed = sanitize_button_xy(button, canvas_width, canvas_height)
            if xy_changed then changed = true end

            r.ImGui_Separator(ctx)
            
            local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
            
            r.ImGui_Text(ctx, "X")
            r.ImGui_SameLine(ctx)
            
            local x_label_w = select(1, r.ImGui_CalcTextSize(ctx, "X "))
            local y_label_w = select(1, r.ImGui_CalcTextSize(ctx, "Y "))
            local spacing = 12
            local half_width = (avail_w - spacing) / 2
            local x_slider_w = half_width - x_label_w - 110  
            local y_slider_w = half_width - y_label_w - 110
            
            r.ImGui_SetNextItemWidth(ctx, math.max(50, x_slider_w))
            local rvx; rvx, button.position_px = r.ImGui_SliderInt(ctx, "##btnPosX_slider", button.position_px, 0, canvas_width, "%d px")
            if rvx then
                button.position_px = clamp(to_int(button.position_px, 0), 0, canvas_width)
                changed = true
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 90)
            local rvxi; rvxi, button.position_px = r.ImGui_InputInt(ctx, "##btnPosXInputInline", button.position_px)
            if rvxi then
                button.position_px = clamp(to_int(button.position_px, 0), 0, canvas_width)
                changed = true
            end

            r.ImGui_SameLine(ctx); r.ImGui_Dummy(ctx, spacing, 0); r.ImGui_SameLine(ctx)

            r.ImGui_Text(ctx, "Y")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, math.max(50, y_slider_w))
            local rvy; rvy, button.position_y_px = r.ImGui_SliderInt(ctx, "##btnPosY_slider", button.position_y_px, 0, canvas_height, "%d px")
            if rvy then
                button.position_y_px = clamp(to_int(button.position_y_px, 0), 0, canvas_height)
                changed = true
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 90)
            local rvyi; rvyi, button.position_y_px = r.ImGui_InputInt(ctx, "##btnPosYInputInline", button.position_y_px)
            if rvyi then
                button.position_y_px = clamp(to_int(button.position_y_px, 0), 0, canvas_height)
                changed = true
            end
            
            local width_label = "Width"
            local show_total_width = false
            if button.use_icon then
                if button.show_text_with_icon then
                    width_label = "Icon Size"  
                    show_total_width = true  
                else
                    width_label = "Icon Size" 
                end
            end
            
            r.ImGui_Text(ctx, width_label)
            r.ImGui_SameLine(ctx)
            
            r.ImGui_SetNextItemWidth(ctx, 150)
            local rvw; rvw, button.width = r.ImGui_SliderInt(ctx, "##btnWidth_inline", button.width, 12, 400)
            if rvw then
                button.width = clamp(to_int(button.width, 60), 12, 400)
                changed = true
            end
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, "-##btnWidthMinus", 20, 0) then
                button.width = clamp(to_int(button.width, 60) - 1, 12, 400)
                changed = true
            end
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, "+##btnWidthPlus", 20, 0) then
                button.width = clamp(to_int(button.width, 60) + 1, 12, 400)
                changed = true
            end
            
            if show_total_width and button.name and button.name ~= "" then
                r.ImGui_SameLine(ctx)
                local text_size = r.ImGui_CalcTextSize(ctx, " | " .. button.name)
                local padding = 8
                local total_width = button.width + text_size + padding
                r.ImGui_TextDisabled(ctx, string.format("(Total: %d)", math.floor(total_width)))
            end

            if changed then
                button.position   = button.position_px   / math.max(1, canvas_width)
                button.position_y = button.position_y_px / math.max(1, canvas_height)
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
        end

        do
            local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
            local label_gap = 6
            local group_gap = 16
            local name_label = "Name   "
            local name_label_w = select(1, r.ImGui_CalcTextSize(ctx, name_label))
            local name_input_w = 220
            local used_w = name_label_w + label_gap + name_input_w + group_gap
            local width_label = "Width"
            local width_label_w = select(1, r.ImGui_CalcTextSize(ctx, width_label))
            local remaining = math.max(60, avail_w - used_w - width_label_w - label_gap)
            local width_slider_w = math.min(remaining, 260)
            local props_w = math.min(avail_w, used_w + width_label_w + label_gap + width_slider_w)

            button.border_color = button.border_color or 0xFFFFFFFF
            local colorFlags = r.ImGui_ColorEditFlags_NoInputs()
            if r.ImGui_BeginTable(ctx, "CB_PropsWrapper", 2, r.ImGui_TableFlags_SizingStretchProp()) then
                r.ImGui_TableSetupColumn(ctx, "Left", r.ImGui_TableColumnFlags_WidthFixed(), props_w)
                r.ImGui_TableSetupColumn(ctx, "Right", r.ImGui_TableColumnFlags_WidthStretch())
                r.ImGui_TableNextRow(ctx)
                r.ImGui_TableSetColumnIndex(ctx, 0)
                
                if r.ImGui_BeginTable(ctx, "CB_Props", 5, r.ImGui_TableFlags_SizingStretchProp()) then
                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableSetColumnIndex(ctx, 0)
                    local rv
                    rv, button.show_border = r.ImGui_Checkbox(ctx, "Border", button.show_border ~= false)
                    if rv then
                        button.show_border = (button.show_border ~= false)
                        changed = true
                    end

                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    local rv_tt
                    rv_tt, settings.show_custom_button_tooltip = r.ImGui_Checkbox(ctx, "Tooltip", settings.show_custom_button_tooltip)
                    changed = changed or rv_tt

                    r.ImGui_TableSetColumnIndex(ctx, 2)
                    rv, button.use_icon = r.ImGui_Checkbox(ctx, "Use Icon", button.use_icon)
                    changed = changed or rv

                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    if button.use_icon then
                        rv, button.show_text_with_icon = r.ImGui_Checkbox(ctx, "Show Text", button.show_text_with_icon)
                        changed = changed or rv
                    end

                    r.ImGui_TableSetColumnIndex(ctx, 4)
                    if button.use_icon then
                        local is_browser_active = IconBrowser.show_window and active_icon_button == button
                        if is_browser_active then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4080FFFF)
                        end
                        
                        if r.ImGui_Button(ctx, is_browser_active and "Close Browser" or "Browse Icons") then
                            if is_browser_active then
                                IconBrowser.show_window = false
                                active_icon_button = nil
                            else
                                IconBrowser.show_window = true
                                active_icon_button = button
                            end
                        end
                        
                        if is_browser_active then
                            r.ImGui_PopStyleColor(ctx)
                        end
                    end

                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableSetColumnIndex(ctx, 0)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    local rv_col
                    rv_col, button.color = r.ImGui_ColorEdit4(ctx, "Base", button.color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.hover_color = r.ImGui_ColorEdit4(ctx, "Hover", button.hover_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 2)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.active_color = r.ImGui_ColorEdit4(ctx, "Active", button.active_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.text_color = r.ImGui_ColorEdit4(ctx, "Text", button.text_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 4)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.border_color = r.ImGui_ColorEdit4(ctx, "Border", button.border_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_EndTable(ctx)
                end
                
                r.ImGui_Spacing(ctx)
                if r.ImGui_BeginTable(ctx, "CB_Font", 2, r.ImGui_TableFlags_SizingStretchSame()) then
                        r.ImGui_TableNextRow(ctx)
                        r.ImGui_TableSetColumnIndex(ctx, 0)
                        
                        local fonts = {
                            "Arial", "Helvetica", "Verdana", "Tahoma", "Times New Roman",
                            "Georgia", "Courier New", "Trebuchet MS", "Impact", "Roboto",
                            "Open Sans", "Ubuntu", "Segoe UI", "Noto Sans", "Liberation Sans",
                            "DejaVu Sans"
                        }
                        
                        if not button.font_name then
                            button.font_name = settings.transport_font_name or "Arial"
                        end
                        if not button.font_size then
                            button.font_size = settings.transport_font_size or 12
                        end
                        
                        local current_font_index = 0
                        for i, font_name in ipairs(fonts) do
                            if font_name == button.font_name then
                                current_font_index = i - 1
                                break
                            end
                        end
                        
                        r.ImGui_Text(ctx, "Font:")
                        r.ImGui_SameLine(ctx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        rv, current_font_index = r.ImGui_Combo(ctx, "##ButtonFont", current_font_index, table.concat(fonts, '\0') .. '\0')
                        if rv then
                            button.font_name = fonts[current_font_index + 1]
                            button.font = nil 
                            changed = true
                        end
                        
                        r.ImGui_TableSetColumnIndex(ctx, 1)
                        r.ImGui_Text(ctx, "Font Size:")
                        r.ImGui_SameLine(ctx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        rv, button.font_size = r.ImGui_SliderInt(ctx, "##ButtonFontSize", button.font_size, 8, 48)
                        if rv then
                            button.font = nil 
                            changed = true
                        end

                        r.ImGui_EndTable(ctx)
                    end
                end
                
                if not is_graphic_mode then
                    r.ImGui_Spacing(ctx)
                    if r.ImGui_BeginTable(ctx, "CB_RoundingBorder", 2, r.ImGui_TableFlags_SizingStretchSame()) then
                        r.ImGui_TableNextRow(ctx)
                        r.ImGui_TableSetColumnIndex(ctx, 0)
                        
                        if not button.rounding then
                            button.rounding = 0
                        end
                        
                        r.ImGui_Text(ctx, "Button Rounding:")
                        r.ImGui_SameLine(ctx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        rv, button.rounding = r.ImGui_SliderDouble(ctx, "##ButtonRounding", button.rounding, 0.0, 20.0, "%.1f")
                        changed = changed or rv
                        
                        r.ImGui_TableSetColumnIndex(ctx, 1)
                        
                        if not button.border_thickness then
                            button.border_thickness = 1.0
                        end
                        
                        r.ImGui_Text(ctx, "Border Thickness:")
                        r.ImGui_SameLine(ctx)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        rv, button.border_thickness = r.ImGui_SliderDouble(ctx, "##BorderThickness", button.border_thickness, 0.5, 5.0, "%.1f")
                        changed = changed or rv

                        r.ImGui_EndTable(ctx)
                    end
                r.ImGui_EndTable(ctx)
            end
        end
        local gname = (custom_buttons.current_edit and custom_buttons.buttons[custom_buttons.current_edit]) and 
                      custom_buttons.buttons[custom_buttons.current_edit].group or ""
        if gname == "" then
            r.ImGui_TextDisabled(ctx, "(This Button is not in a group)")
        else
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Edit all buttons in Current Group:")
            local gcount = 0
            for _, b in ipairs(custom_buttons.buttons) do
                if b.group and b.group ~= "" and button.group == b.group then
                    gcount = gcount + 1
                end
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_TextColored(ctx, 0x00FF88FF, " " .. button.group .. " (" .. gcount .. ")")
            
            local all_visible = true
            for _, b in ipairs(custom_buttons.buttons) do
                if b.group == gname and not b.visible then all_visible = false break end
            end
            r.ImGui_SameLine(ctx)
            local vis_label = all_visible and "Hide Group" or "Show Group"
            if r.ImGui_Button(ctx, vis_label .. "##grpToggleVis") then
                local new_state = not all_visible
                for _, b in ipairs(custom_buttons.buttons) do if b.group == gname then b.visible = new_state end end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                if all_visible then
                    r.ImGui_SetTooltip(ctx, "Hide all buttons in this group")
                else
                    r.ImGui_SetTooltip(ctx, "Show all buttons in this group")
                end
            end
            
            local raw_w = (opts and opts.canvas_width) or r.ImGui_GetWindowWidth(ctx)
            local raw_h = (opts and opts.canvas_height) or r.ImGui_GetWindowHeight(ctx)
            local canvas_w = clamp(to_int(raw_w, 1), 1)
            local canvas_h = clamp(to_int(raw_h, 1), 1)

            local function adjust_group(dx, dy)
                local any_changed = false
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        local _, _, sanitized = sanitize_button_xy(b, canvas_w, canvas_h)
                        if sanitized then any_changed = true end

                        if dx ~= 0 then
                            local new_px = clamp(to_int((tonumber(b.position_px) or 0) + dx, 0), 0, canvas_w)
                            if new_px ~= b.position_px then
                                b.position_px = new_px
                                b.position = new_px / math.max(1, canvas_w)
                                any_changed = true
                            end
                        end
                        if dy ~= 0 then
                            local new_py = clamp(to_int((tonumber(b.position_y_px) or 0) + dy, 0), 0, canvas_h)
                            if new_py ~= b.position_y_px then
                                b.position_y_px = new_py
                                b.position_y = new_py / math.max(1, canvas_h)
                                any_changed = true
                            end
                        end
                    end
                end
                if any_changed then
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                end
            end

            if r.ImGui_Button(ctx, "← X##grpMoveLeft") then
                adjust_group(-1, 0)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel left") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "X →##grpMoveRight") then
                adjust_group(1, 0)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel right") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "↑ Y##grpMoveUp") then
                adjust_group(0, -1)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel up") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Y ↓##grpMoveDown") then
                adjust_group(0, 1)
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move entire group 1 pixel down") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Align Y") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.position_y = button.position_y
                        b.position_y_px = button.position_y_px
                        sanitize_button_xy(b, canvas_w, canvas_h)
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Set all buttons in this group to the same Y position") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Size") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.width = button.width
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy size/width to the group") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Color") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.color = button.color
                        b.hover_color = button.hover_color
                        b.active_color = button.active_color
                        b.text_color = button.text_color
                        b.border_color = button.border_color
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy all colors to the group") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Use Icon") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.use_icon = button.use_icon
                        b.icon_name = button.icon_name
                        b.icon = nil 
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy 'Use Icon' setting and icon to the group") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Show Text") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.show_text_with_icon = button.show_text_with_icon
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy 'Show Text' setting to the group") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Rounding") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.rounding = button.rounding
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy button rounding to the group") end
            
            if r.ImGui_Button(ctx, "Border Thick") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.border_thickness = button.border_thickness
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy border thickness to the group") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Border Color") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.border_color = button.border_color
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy border color to the group") end
            r.ImGui_SameLine(ctx)
            local all_borders = true
            for _, b in ipairs(custom_buttons.buttons) do
                if b.group == gname and b.show_border == false then all_borders = false break end
            end
            local border_label = all_borders and "No Borders" or "Borders"
            if r.ImGui_Button(ctx, border_label .. "##grpToggleBorder") then
                local new_border = not all_borders
                for _, b in ipairs(custom_buttons.buttons) do if b.group == gname then b.show_border = new_border end end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                if all_borders then
                    r.ImGui_SetTooltip(ctx, "Disable borders for entire group")
                else
                    r.ImGui_SetTooltip(ctx, "Enable borders for entire group")
                end
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Text Color") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.text_color = button.text_color
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy text color to the group") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Text Size") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.font_size = button.font_size
                        b.font = nil 
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy text size to the group") end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Font") then
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.font_name = button.font_name
                        b.font = nil 
                    end
                end
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
        end
    end  

        if opts and opts.render_global_offset then
            opts.render_global_offset(ctx)
        end
        
        if cb_section_states.actions_open then
            r.ImGui_Text(ctx, "Left Click:")

       
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 180)
            do
                local rv_name, new_name = r.ImGui_InputText(ctx, "##lcaName", button.left_click.name)
                if rv_name then button.left_click.name = new_name; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "ID")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 120)
            do
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "##lcaCmd", button.left_click.command or "")
                if rv_cmd then button.left_click.command = new_command; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Type")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            do
                local rv_type, new_type = r.ImGui_Combo(ctx, "##lcaType", button.left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then button.left_click.type = new_type; changed = true end
            end

            if changed then custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end

            r.ImGui_Separator(ctx)
            
            r.ImGui_Text(ctx, "Alt+Left Click:")

       
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 180)
            do
                button.alt_left_click = button.alt_left_click or { name = "", command = "", type = 0 }
                local rv_name, new_name = r.ImGui_InputText(ctx, "##alcaName", button.alt_left_click.name)
                if rv_name then button.alt_left_click.name = new_name; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "ID")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 120)
            do
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "##alcaCmd", button.alt_left_click.command or "")
                if rv_cmd then button.alt_left_click.command = new_command; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Type")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            do
                local rv_type, new_type = r.ImGui_Combo(ctx, "##alcaType", button.alt_left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then button.alt_left_click.type = new_type; changed = true end
            end

            if changed then custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end

            r.ImGui_Separator(ctx)

            r.ImGui_Text(ctx, "Right Click Menu:")
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, "Drag items into folders to create submenus")
            button.right_menu = button.right_menu or {}
            button.right_menu.items = button.right_menu.items or {}
            
            EnsureUniqueIDs(button.right_menu.items)


                local remove_index
                local payload_type = "TK_BTN_RCMENU_ITEM"

                
                if r.ImGui_BeginTable(ctx, "RCM_TABLE", 5,
                        r.ImGui_TableFlags_SizingStretchProp()
                        | r.ImGui_TableFlags_BordersInnerV()
                    ) then
                    r.ImGui_TableSetupColumn(ctx, "Drag", r.ImGui_TableColumnFlags_WidthFixed(), 30)
                    r.ImGui_TableSetupColumn(ctx, "Name", 0)
                    r.ImGui_TableSetupColumn(ctx, "Cmd", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                    r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), 70)
                    r.ImGui_TableSetupColumn(ctx, "X", r.ImGui_TableColumnFlags_WidthFixed(), 20)
                    r.ImGui_TableHeadersRow(ctx)

                    local display_order = GetDisplayOrder(button.right_menu.items)
                    
                    local previous_top_level_folder = nil
                    
                    for i, entry in ipairs(display_order) do
                        local idx = entry.idx
                        local depth = entry.depth
                        local item = button.right_menu.items[idx]
                        r.ImGui_PushID(ctx, idx)
                        
                        local is_submenu = item.is_submenu or false
                        
                        if depth == 0 and is_submenu then
                            if previous_top_level_folder then
                                r.ImGui_TableNextRow(ctx, 0, 8)  
                                r.ImGui_TableSetColumnIndex(ctx, 0)
                                for col = 0, 4 do
                                    r.ImGui_TableSetColumnIndex(ctx, col)
                                    r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_CellBg(), 0x40404040)
                                end
                            end
                            previous_top_level_folder = idx
                        end
                        
                        r.ImGui_TableNextRow(ctx)
                        
                        if depth > 0 or is_submenu then
                            local color_depth = is_submenu and depth or (depth - 1)
                            if color_depth >= 0 then
                                r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg0(), GetFolderColor(color_depth))
                            end
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 0)

                        local handle_w   = 30
                        local handle_h   = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                        local handle_txt = "≡≡"
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x00000000)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x66666633)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x88888855)
                        r.ImGui_Button(ctx, handle_txt .. "##drag", handle_w, handle_h)
                        r.ImGui_PopStyleColor(ctx, 3)

                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeAll())
                            r.ImGui_SetTooltip(ctx, "Drag to move")
                        end

                        if r.ImGui_BeginDragDropSource(ctx) then
                            r.ImGui_SetDragDropPayload(ctx, payload_type, tostring(idx))
                            r.ImGui_Text(ctx, "Drag: " .. (item.name ~= "" and item.name or ("Item " .. idx)))
                            r.ImGui_EndDragDropSource(ctx)
                        end

                        if r.ImGui_BeginDragDropTarget(ctx) then
                            local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, payload_type)
                            if ok then
                                local from = tonumber(payload)
                                if from and from ~= idx then
                                    local dragged_item = button.right_menu.items[from]
                                    local target_item = button.right_menu.items[idx]
                                    
                                    if (dragged_item.parent_id or 0) == (target_item.parent_id or 0) then
                                        if MoveItemToPosition(button.right_menu.items, from, idx) then
                                            custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                                        end
                                    end
                                end
                            end
                            r.ImGui_EndDragDropTarget(ctx)
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 1)
                        
                        if item.parent_id then
                            if r.ImGui_SmallButton(ctx, "⬅##unfolder" .. idx) then
                                item.parent_id = nil
                                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                            end
                            if r.ImGui_IsItemHovered(ctx) then
                                r.ImGui_SetTooltip(ctx, "Remove from folder")
                            end
                            r.ImGui_SameLine(ctx)
                        end
                        
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local display_name = item.name or ""
                        
                        local icon = "📁"
                        if display_name:sub(1, #icon) == icon then
                            display_name = display_name:sub(#icon + 1)
                            if display_name:sub(1, 1) == " " then
                                display_name = display_name:sub(2)
                            end
                            item.name = display_name
                            custom_buttons.SaveCurrentButtons()
                        end
                        
                        local indent = string.rep("  ", depth)
                        
                        if is_submenu then
                            display_name = indent .. "📁 " .. display_name
                        else
                            display_name = indent .. display_name
                        end
                        
                        local rv_name, new_name = r.ImGui_InputText(ctx, "##name", display_name)
                        if rv_name then 
                            local icon = "📁"
                            if new_name:sub(1, #icon) == icon then
                                new_name = new_name:sub(#icon + 1)
                            end
                            while new_name:sub(1, 1) == " " do
                                new_name = new_name:sub(2)
                            end
                            
                            item.name = new_name
                            custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                        end
                        
                        if is_submenu and r.ImGui_BeginDragDropTarget(ctx) then
                            local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, payload_type)
                            if ok then
                                local from = tonumber(payload)
                                if from and from ~= idx then
                                    local dragged_item = button.right_menu.items[from]
                                    
                                    local target_depth = GetItemDepth(button.right_menu.items, item)
                                    if target_depth < 3 then  
                                        dragged_item.parent_id = item.unique_id
                                        custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                                    else
                                        r.ShowConsoleMsg("Maximum folder depth (4 levels) reached!\n")
                                    end
                                end
                            end
                            r.ImGui_EndDragDropTarget(ctx)
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 2)
                        if not is_submenu then
                            r.ImGui_SetNextItemWidth(ctx, -1)
                            local rv_cmd, new_cmd = r.ImGui_InputText(ctx, "##cmd", item.command or "")
                            if rv_cmd then item.command = new_cmd; custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 3)
                        if not is_submenu then
                            r.ImGui_SetNextItemWidth(ctx, -1)
                            local rv_type, new_type = r.ImGui_Combo(ctx, "##type", item.type or 0, "Main\0MIDI Editor\0")
                            if rv_type then item.type = new_type; custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 4)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        if r.ImGui_Button(ctx, "X##del") then
                            remove_index = idx
                        end

                        r.ImGui_PopID(ctx)
                    end

                    r.ImGui_EndTable(ctx)
                end

                r.ImGui_Spacing(ctx)
                local avail_width = r.ImGui_GetContentRegionAvail(ctx)
                local button_size = 30
                local spacing_between = 10
                local total_width = (button_size * 2) + spacing_between
                local center_pos = (avail_width - total_width) * 0.5
                if center_pos > 0 then
                    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + center_pos)
                end
                
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), button_size * 0.5)
                if r.ImGui_Button(ctx, "➕##addMenuItem", button_size, button_size) then
                    local max_id = EnsureUniqueIDs(button.right_menu.items)
                    table.insert(button.right_menu.items, { name = "New Item", command = "", type = 0, is_submenu = false, unique_id = max_id + 1 })
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Add a menu item")
                end
                
                r.ImGui_SameLine(ctx, 0, spacing_between)
                if r.ImGui_Button(ctx, "📁##addSubmenu", button_size, button_size) then
                    local max_id = EnsureUniqueIDs(button.right_menu.items)
                    table.insert(button.right_menu.items, 1, { name = "New Folder", command = "", type = 0, is_submenu = true, unique_id = max_id + 1 })
                    
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                end
                r.ImGui_PopStyleVar(ctx)
                
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Add a submenu folder")
                end

                if remove_index then
                    local removed_item = button.right_menu.items[remove_index]
                    
                    if removed_item and removed_item.is_submenu then
                        for _, it in ipairs(button.right_menu.items) do
                            if it.parent_id == removed_item.unique_id then
                                it.parent_id = nil 
                            end
                        end
                    end
                    
                    table.remove(button.right_menu.items, remove_index)
                    
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                end

        end 
        
    end  
    

end

function ButtonEditor.DeepCopyButton(button)
    local new_button = {}
    for k, v in pairs(button) do
        if type(v) == "table" then
            new_button[k] = {}
            for k2, v2 in pairs(v) do
                if type(v2) == "table" then
                    new_button[k][k2] = {}
                    for k3, v3 in pairs(v2) do
                        new_button[k][k2][k3] = v3
                    end
                else
                    new_button[k][k2] = v2
                end
            end
        else
            new_button[k] = v
        end
    end
    return new_button
end

function ButtonEditor.LoadButtonsFromPreset(preset_name, custom_buttons)
    if not preset_name or preset_name == "" then return {} end
    
    local original_preset = custom_buttons.current_preset
    local original_buttons = {}
    for i, btn in ipairs(custom_buttons.buttons) do
        original_buttons[i] = btn
    end
    
    custom_buttons.LoadButtonPreset(preset_name)
    local other_buttons = {}
    for i, btn in ipairs(custom_buttons.buttons) do
        other_buttons[i] = ButtonEditor.DeepCopyButton(btn)
    end
    
    custom_buttons.buttons = original_buttons
    custom_buttons.current_preset = original_preset
    
    return other_buttons
end

function ButtonEditor.CopyButtonToCurrentPreset(button_data, custom_buttons)
    if not button_data then return false end
    
    local new_button = ButtonEditor.DeepCopyButton(button_data)
    
    if new_button.use_icon and new_button.icon_name then
        local icon, status = ButtonEditor.LoadIconForPreview(new_button)
        if status == "file_not_found" or status == "load_failed" then
            new_button.use_icon = false
            new_button.icon_name = nil
            new_button.name = (new_button.name or "Button") .. " (icon removed)"
        end
    end
    
    local max_id = 0
    for _, btn in ipairs(custom_buttons.buttons) do
        if btn.id and btn.id > max_id then
            max_id = btn.id
        end
    end
    new_button.id = max_id + 1
    
    table.insert(custom_buttons.buttons, new_button)
    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
    
    custom_buttons.current_edit = #custom_buttons.buttons
    
    return true
end

function ButtonEditor.LoadIconForPreview(button)
    if not (button.use_icon and button.icon_name) then
        return nil, "no_icon"
    end
    
    local ButtonRenderer = require('button_renderer')
    
    if not r.ImGui_ValidatePtr(ButtonRenderer.image_cache[button.icon_name], 'ImGui_Image*') then
        local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
        local resource_path = script_path
        local icon_path = resource_path .. "/Data/toolbar_icons/" .. button.icon_name
        
        if r.file_exists(icon_path) then
            local img = r.ImGui_CreateImage(icon_path)
            if r.ImGui_ValidatePtr(img, 'ImGui_Image*') then
                ButtonRenderer.image_cache[button.icon_name] = img
                return img, "loaded"
            else
                return nil, "load_failed"
            end
        else
            return nil, "file_not_found"
        end
    end
    
    return ButtonRenderer.image_cache[button.icon_name], "cached"
end

function ButtonEditor.GetIconStatusText(button, status)
    if not button.use_icon then
        return ""
    end
    
    local icon_name = button.icon_name or "unknown"
    
    if status == "file_not_found" then
        return "🚫 Icon missing: " .. icon_name
    elseif status == "load_failed" then
        return "⚠️ Icon corrupt: " .. icon_name
    elseif status == "no_icon" then
        return ""
    else
        return "✓ " .. icon_name
    end
end

function ButtonEditor.ShowCrossPresetImport(ctx, custom_buttons)
    if r.ImGui_CollapsingHeader(ctx, "Import from Other Presets") then
        local all_presets = custom_buttons.GetButtonPresets()
        local current_preset_name = custom_buttons.current_preset
        
        local other_presets = {}
        for _, preset in ipairs(all_presets) do
            if preset ~= current_preset_name then
                table.insert(other_presets, preset)
            end
        end
        
        if #other_presets == 0 then
            r.ImGui_TextDisabled(ctx, "No other presets available")
            return
        end
        
        r.ImGui_Text(ctx, "Select preset to import buttons from:")
        
        for _, preset_name in ipairs(other_presets) do
            if r.ImGui_TreeNode(ctx, preset_name) then
                local other_buttons = ButtonEditor.LoadButtonsFromPreset(preset_name, custom_buttons)
                
                if #other_buttons == 0 then
                    r.ImGui_TextDisabled(ctx, "No buttons in this preset")
                else
                    if r.ImGui_BeginTable(ctx, "ImportButtons_" .. preset_name, 3, 
                        r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
                        
                        r.ImGui_TableSetupColumn(ctx, "Button", r.ImGui_TableColumnFlags_WidthFixed(), 200)
                        r.ImGui_TableSetupColumn(ctx, "Action", r.ImGui_TableColumnFlags_WidthStretch())
                        r.ImGui_TableSetupColumn(ctx, "Copy", r.ImGui_TableColumnFlags_WidthFixed(), 60)
                        r.ImGui_TableHeadersRow(ctx)
                        
                        for i, button in ipairs(other_buttons) do
                            r.ImGui_PushID(ctx, "import_" .. preset_name .. "_" .. i)
                            r.ImGui_TableNextRow(ctx)
                            
                            r.ImGui_TableSetColumnIndex(ctx, 0)
                            local button_name = button.name or "Button " .. i
                            local preview_color = button.color or 0x333333FF
                            
                            if button.use_icon and button.icon_name then
                                local icon, status = ButtonEditor.LoadIconForPreview(button)
                                
                                if status == "cached" or status == "loaded" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), preview_color)
                                    
                                    if r.ImGui_Button(ctx, "##preview_bg_" .. i, 180, 25) then
                                    end
                                    
                                    local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx)
                                    local icon_x = button_min_x + 3
                                    local icon_y = button_min_y + 2.5
                                    local text_x = icon_x + 22
                                    local text_y = button_min_y + 4
                                    
                                    local draw_list = r.ImGui_GetWindowDrawList(ctx)
                                    
                                    local uv_x1 = 0.0    
                                    local uv_x2 = 0.33333  
                                    local uv_y1 = 0.0
                                    local uv_y2 = 1.0
                                    
                                    r.ImGui_DrawList_AddImage(draw_list, icon, 
                                        icon_x, icon_y, 
                                        icon_x + 20, icon_y + 20,
                                        uv_x1, uv_y1, uv_x2, uv_y2)
                                    
                                    local text_color = button.text_color or 0xFFFFFFFF
                                    r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, button_name)
                                    
                                    r.ImGui_PopStyleColor(ctx)
                                    
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, ButtonEditor.GetIconStatusText(button, status))
                                    end
                                    
                                elseif status == "file_not_found" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x663333FF) -- Dark red
                                    r.ImGui_Button(ctx, "🚫 " .. button_name .. "##preview_" .. i, 180, 25)
                                    r.ImGui_PopStyleColor(ctx)
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, ButtonEditor.GetIconStatusText(button, status))
                                    end
                                    
                                elseif status == "load_failed" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x665533FF) -- Dark orange
                                    r.ImGui_Button(ctx, "⚠️ " .. button_name .. "##preview_" .. i, 180, 25)
                                    r.ImGui_PopStyleColor(ctx)
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, ButtonEditor.GetIconStatusText(button, status))
                                    end
                                    
                                else
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), preview_color)
                                    r.ImGui_Button(ctx, "? " .. button_name .. "##preview_" .. i, 180, 25)
                                    r.ImGui_PopStyleColor(ctx)
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, "Unknown icon error")
                                    end
                                end
                            else
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), preview_color)
                                r.ImGui_Button(ctx, button_name .. "##preview_" .. i, 180, 25)
                                r.ImGui_PopStyleColor(ctx)
                            end
                            
                            r.ImGui_TableSetColumnIndex(ctx, 1)
                            local action_text = "No action"
                            if button.left_click and button.left_click.name then
                                action_text = button.left_click.name
                            elseif button.left_click and button.left_click.command then
                                action_text = tostring(button.left_click.command)
                            end
                            r.ImGui_Text(ctx, action_text)
                            
                            r.ImGui_TableSetColumnIndex(ctx, 2)
                            if r.ImGui_Button(ctx, "Copy##copy_" .. i, 50, 25) then
                                if ButtonEditor.CopyButtonToCurrentPreset(button, custom_buttons) then
                                    r.ImGui_SetTooltip(ctx, "Button copied successfully!")
                                end
                            end
                            if r.ImGui_IsItemHovered(ctx) then
                                r.ImGui_SetTooltip(ctx, "Copy this button to current preset")
                            end
                            
                            r.ImGui_PopID(ctx)
                        end
                        
                        r.ImGui_EndTable(ctx)
                    end
                end
                
                r.ImGui_TreePop(ctx)
            end
        end
    end
end

function ButtonEditor.ShowIconHealthCheck(ctx, custom_buttons)
    if r.ImGui_CollapsingHeader(ctx, "Icon Health Check") then
        local broken_icons = {}
        local working_icons = {}
        
        for i, button in ipairs(custom_buttons.buttons) do
            if button.use_icon and button.icon_name then
                local icon, status = ButtonEditor.LoadIconForPreview(button)
                if status == "file_not_found" or status == "load_failed" then
                    table.insert(broken_icons, {
                        index = i,
                        button = button,
                        status = status
                    })
                else
                    table.insert(working_icons, {
                        index = i,
                        button = button,
                        status = status
                    })
                end
            end
        end
        
        local total_icon_buttons = #broken_icons + #working_icons
        
        if total_icon_buttons == 0 then
            r.ImGui_TextDisabled(ctx, "No buttons with icons in current preset")
        else
            r.ImGui_Text(ctx, string.format("Icons Status: %d working, %d broken", #working_icons, #broken_icons))
            
            if #broken_icons > 0 then
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0xFF4444FF, "⚠️ Broken Icons:")
                
                for _, entry in ipairs(broken_icons) do
                    r.ImGui_PushID(ctx, "broken_" .. entry.index)
                    
                    local button_name = entry.button.name or ("Button " .. entry.index)
                    local icon_name = entry.button.icon_name or "unknown"
                    local status_text = ButtonEditor.GetIconStatusText(entry.button, entry.status)
                    
                    r.ImGui_BulletText(ctx, button_name .. " - " .. status_text)
                    r.ImGui_SameLine(ctx)
                    
                    if r.ImGui_Button(ctx, "Fix") then
                        entry.button.use_icon = false
                        entry.button.icon_name = nil
                        custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Disable icon for this button")
                    end
                    
                    r.ImGui_PopID(ctx)
                end
                
                r.ImGui_Separator(ctx)
                if r.ImGui_Button(ctx, "Fix All Broken Icons") then
                    for _, entry in ipairs(broken_icons) do
                        entry.button.use_icon = false
                        entry.button.icon_name = nil
                    end
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Disable icons for all buttons with missing/broken icons")
                end
            end
            
            if #working_icons > 0 then
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x44FF44FF, "✓ Working Icons:")
                for _, entry in ipairs(working_icons) do
                    local button_name = entry.button.name or ("Button " .. entry.index)
                    local icon_name = entry.button.icon_name or "unknown"
                    r.ImGui_BulletText(ctx, button_name .. " - ✓ " .. icon_name)
                end
            end
        end
    end
end

function ButtonEditor.ShowImportWindow(ctx, custom_buttons)
    if not import_window.open then return end
    
    if not import_window.ctx then
        import_window.ctx = r.ImGui_CreateContext('Import Buttons')
    end
    
    local ctx_import = import_window.ctx
    local visible, open = r.ImGui_Begin(ctx_import, import_window.title, true)
    
    if not open then
        import_window.open = false
    end
    
    if visible and open then
        r.ImGui_SetWindowSize(ctx_import, 600, 400, r.ImGui_Cond_FirstUseEver())
        
        r.ImGui_Text(ctx_import, "Copy buttons from other presets to the current preset.")
        r.ImGui_Separator(ctx_import)
        
        local all_presets = custom_buttons.GetButtonPresets()
        local current_preset_name = custom_buttons.current_preset
        
        local other_presets = {}
        for _, preset in ipairs(all_presets) do
            if preset ~= current_preset_name then
                table.insert(other_presets, preset)
            end
        end
        
        if #other_presets == 0 then
            r.ImGui_TextDisabled(ctx_import, "No other presets available")
        else
            r.ImGui_Text(ctx_import, "Current preset: " .. (current_preset_name or "None"))
            r.ImGui_Separator(ctx_import)
            
            for idx, preset_name in ipairs(other_presets) do
                r.ImGui_PushID(ctx_import, "preset_" .. idx)
                if r.ImGui_TreeNode(ctx_import, preset_name) then
                    local other_buttons = ButtonEditor.LoadButtonsFromPreset(preset_name, custom_buttons)
                    
                    if #other_buttons == 0 then
                        r.ImGui_TextDisabled(ctx_import, "No buttons in this preset")
                    else
                        if r.ImGui_BeginTable(ctx_import, "ImportButtons_" .. preset_name, 3, 
                            r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
                            
                            r.ImGui_TableSetupColumn(ctx_import, "Button", r.ImGui_TableColumnFlags_WidthFixed(), 200)
                            r.ImGui_TableSetupColumn(ctx_import, "Action", r.ImGui_TableColumnFlags_WidthStretch())
                            r.ImGui_TableSetupColumn(ctx_import, "Copy", r.ImGui_TableColumnFlags_WidthFixed(), 60)
                            r.ImGui_TableHeadersRow(ctx_import)
                            
                            r.ImGui_PushStyleVar(ctx_import, r.ImGui_StyleVar_ButtonTextAlign(), 0.0, 0.5)
                            
                            for i, button in ipairs(other_buttons) do
                                r.ImGui_PushID(ctx_import, "import_" .. preset_name .. "_" .. i)
                                r.ImGui_TableNextRow(ctx_import)
                                
                                r.ImGui_TableSetColumnIndex(ctx_import, 0)
                                local button_name = button.name or "Button " .. i
                                local preview_color = button.color or 0x333333FF
                                
                                if button.use_icon and button.icon_name then
                                    local icon, status = ButtonEditor.LoadIconForPreview(button)
                                    
                                    if status == "cached" or status == "loaded" then
                                        r.ImGui_PushStyleColor(ctx_import, r.ImGui_Col_Button(), preview_color)
                                        
                                        if r.ImGui_Button(ctx_import, "##preview_bg_" .. i, 180, 25) then
                                        end
                                        
                                        local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx_import)
                                        local icon_x = button_min_x + 3
                                        local icon_y = button_min_y + 2.5
                                        local text_x = icon_x + 22
                                        local text_y = button_min_y + 4
                                        
                                        local draw_list = r.ImGui_GetWindowDrawList(ctx_import)
                                        
                                        local uv_x1 = 0.0     
                                        local uv_x2 = 0.33333  
                                        local uv_y1 = 0.0
                                        local uv_y2 = 1.0
                                        
                                        r.ImGui_DrawList_AddImage(draw_list, icon, 
                                            icon_x, icon_y, 
                                            icon_x + 20, icon_y + 20,
                                            uv_x1, uv_y1, uv_x2, uv_y2)
                                        
                                        local text_color = button.text_color or 0xFFFFFFFF
                                        r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, button_name)
                                        
                                        r.ImGui_PopStyleColor(ctx_import)
                                        
                                        if r.ImGui_IsItemHovered(ctx_import) then
                                            r.ImGui_SetTooltip(ctx_import, ButtonEditor.GetIconStatusText(button, status))
                                        end
                                        
                                    elseif status == "file_not_found" then
                                        r.ImGui_PushStyleColor(ctx_import, r.ImGui_Col_Button(), 0x663333FF) -- Dark red
                                        r.ImGui_Button(ctx_import, "🚫 " .. button_name .. "##preview_" .. i, 180, 25)
                                        r.ImGui_PopStyleColor(ctx_import)
                                        if r.ImGui_IsItemHovered(ctx_import) then
                                            r.ImGui_SetTooltip(ctx_import, ButtonEditor.GetIconStatusText(button, status))
                                        end
                                        
                                    elseif status == "load_failed" then
                                        r.ImGui_PushStyleColor(ctx_import, r.ImGui_Col_Button(), 0x665533FF) -- Dark orange
                                        r.ImGui_Button(ctx_import, "⚠️ " .. button_name .. "##preview_" .. i, 180, 25)
                                        r.ImGui_PopStyleColor(ctx_import)
                                        if r.ImGui_IsItemHovered(ctx_import) then
                                            r.ImGui_SetTooltip(ctx_import, ButtonEditor.GetIconStatusText(button, status))
                                        end
                                        
                                    else
                                        r.ImGui_PushStyleColor(ctx_import, r.ImGui_Col_Button(), preview_color)
                                        r.ImGui_Button(ctx_import, "? " .. button_name .. "##preview_" .. i, 180, 25)
                                        r.ImGui_PopStyleColor(ctx_import)
                                        if r.ImGui_IsItemHovered(ctx_import) then
                                            r.ImGui_SetTooltip(ctx_import, "Unknown icon error")
                                        end
                                    end
                                else
                                    r.ImGui_PushStyleColor(ctx_import, r.ImGui_Col_Button(), preview_color)
                                    r.ImGui_Button(ctx_import, button_name .. "##preview_" .. i, 180, 25)
                                    r.ImGui_PopStyleColor(ctx_import)
                                end
                                
                                r.ImGui_TableSetColumnIndex(ctx_import, 1)
                                local action_text = "No action"
                                if button.left_click and button.left_click.name then
                                    action_text = button.left_click.name
                                elseif button.left_click and button.left_click.command then
                                    action_text = tostring(button.left_click.command)
                                end
                                r.ImGui_Text(ctx_import, action_text)
                                
                                r.ImGui_TableSetColumnIndex(ctx_import, 2)
                                if r.ImGui_Button(ctx_import, "Copy", 50, 25) then
                                    if ButtonEditor.CopyButtonToCurrentPreset(button, custom_buttons) then
                                        r.ImGui_SetTooltip(ctx_import, "Button copied successfully!")
                                    end
                                end
                                if r.ImGui_IsItemHovered(ctx_import) then
                                    r.ImGui_SetTooltip(ctx_import, "Copy this button to current preset")
                                end
                                
                                r.ImGui_PopID(ctx_import)
                            end
                            
                            r.ImGui_PopStyleVar(ctx_import) 
                            
                            r.ImGui_EndTable(ctx_import)
                        end
                    end
                    
                    r.ImGui_TreePop(ctx_import)
                end
                r.ImGui_PopID(ctx_import)
            end
        end
        
        r.ImGui_End(ctx_import)
    end
end

function ButtonEditor.ShowIconCheckWindow(ctx, custom_buttons)
    if not icon_check_window.open then return end
    
    if not icon_check_window.ctx then
        icon_check_window.ctx = r.ImGui_CreateContext('Icon Health Check')
    end
    
    local ctx_check = icon_check_window.ctx
    local visible, open = r.ImGui_Begin(ctx_check, icon_check_window.title, true)
    
    if not open then
        icon_check_window.open = false
    end
    
    if visible and open then
        r.ImGui_SetWindowSize(ctx_check, 500, 400, r.ImGui_Cond_FirstUseEver())
        
        r.ImGui_Text(ctx_check, "Check and fix broken icons in the current preset.")
        r.ImGui_Separator(ctx_check)
        
        local broken_icons = {}
        local working_icons = {}
        
        for i, button in ipairs(custom_buttons.buttons) do
            if button.use_icon and button.icon_name then
                local icon, status = ButtonEditor.LoadIconForPreview(button)
                if status == "file_not_found" or status == "load_failed" then
                    table.insert(broken_icons, {
                        index = i,
                        button = button,
                        status = status
                    })
                else
                    table.insert(working_icons, {
                        index = i,
                        button = button,
                        status = status
                    })
                end
            end
        end
        
        local total_icon_buttons = #broken_icons + #working_icons
        
        if total_icon_buttons == 0 then
            r.ImGui_TextDisabled(ctx_check, "No buttons with icons in current preset")
        else
            r.ImGui_Text(ctx_check, string.format("Icons Status: %d working, %d broken", #working_icons, #broken_icons))
            
            if #broken_icons > 0 then
                r.ImGui_Separator(ctx_check)
                r.ImGui_TextColored(ctx_check, 0xFF4444FF, "⚠️ Broken Icons:")
                
                for _, entry in ipairs(broken_icons) do
                    r.ImGui_PushID(ctx_check, "broken_" .. entry.index)
                    
                    local button_name = entry.button.name or ("Button " .. entry.index)
                    local icon_name = entry.button.icon_name or "unknown"
                    local status_text = ButtonEditor.GetIconStatusText(entry.button, entry.status)
                    
                    r.ImGui_BulletText(ctx_check, button_name .. " - " .. status_text)
                    r.ImGui_SameLine(ctx_check)
                    
                    if r.ImGui_Button(ctx_check, "Fix") then
                        entry.button.use_icon = false
                        entry.button.icon_name = nil
                        custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                    end
                    if r.ImGui_IsItemHovered(ctx_check) then
                        r.ImGui_SetTooltip(ctx_check, "Disable icon for this button")
                    end
                    
                    r.ImGui_PopID(ctx_check)
                end
                
                r.ImGui_Separator(ctx_check)
                if r.ImGui_Button(ctx_check, "Fix All Broken Icons") then
                    for _, entry in ipairs(broken_icons) do
                        entry.button.use_icon = false
                        entry.button.icon_name = nil
                    end
                    custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
                end
                if r.ImGui_IsItemHovered(ctx_check) then
                    r.ImGui_SetTooltip(ctx_check, "Disable icons for all buttons with missing/broken icons")
                end
            end
            
            if #working_icons > 0 then
                r.ImGui_Separator(ctx_check)
                r.ImGui_TextColored(ctx_check, 0x44FF44FF, "✓ Working Icons:")
                for _, entry in ipairs(working_icons) do
                    local button_name = entry.button.name or ("Button " .. entry.index)
                    local icon_name = entry.button.icon_name or "unknown"
                    r.ImGui_BulletText(ctx_check, button_name .. " - ✓ " .. icon_name)
                end
            end
        end
        
        r.ImGui_End(ctx_check)
    end
end

ButtonEditor.import_window = import_window
ButtonEditor.icon_check_window = icon_check_window

function ButtonEditor.HasUnsavedChanges()
    return has_unsaved_changes
end

function ButtonEditor.ResetUnsavedChanges()
    has_unsaved_changes = false
end

function ButtonEditor.MarkUnsavedChanges()
    has_unsaved_changes = true
end

function ButtonEditor.ShowImportInline(ctx, custom_buttons)
    r.ImGui_Text(ctx, "Copy buttons from other presets to the current preset.")
    r.ImGui_Separator(ctx)
    
    local all_presets = custom_buttons.GetButtonPresets()
    local current_preset_name = custom_buttons.current_preset
    
    local other_presets = {}
    for _, preset in ipairs(all_presets) do
        if preset ~= current_preset_name then
            table.insert(other_presets, preset)
        end
    end
    
    if #other_presets == 0 then
        r.ImGui_TextDisabled(ctx, "No other presets available")
    else
        r.ImGui_Text(ctx, "Current preset: " .. (current_preset_name or "None"))
        r.ImGui_Separator(ctx)
        
        for idx, preset_name in ipairs(other_presets) do
            r.ImGui_PushID(ctx, "preset_" .. idx)
            if r.ImGui_TreeNode(ctx, preset_name) then
                local other_buttons = ButtonEditor.LoadButtonsFromPreset(preset_name, custom_buttons)
                
                if #other_buttons == 0 then
                    r.ImGui_TextDisabled(ctx, "No buttons in this preset")
                else
                    if r.ImGui_BeginTable(ctx, "ImportButtons_" .. preset_name, 3, 
                        r.ImGui_TableFlags_Borders() | r.ImGui_TableFlags_RowBg()) then
                        
                        r.ImGui_TableSetupColumn(ctx, "Button", r.ImGui_TableColumnFlags_WidthFixed(), 200)
                        r.ImGui_TableSetupColumn(ctx, "Action", r.ImGui_TableColumnFlags_WidthStretch())
                        r.ImGui_TableSetupColumn(ctx, "Copy", r.ImGui_TableColumnFlags_WidthFixed(), 60)
                        r.ImGui_TableHeadersRow(ctx)
                        
                        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0.0, 0.5)
                        
                        for i, button in ipairs(other_buttons) do
                            r.ImGui_PushID(ctx, "import_" .. preset_name .. "_" .. i)
                            r.ImGui_TableNextRow(ctx)
                            
                            r.ImGui_TableSetColumnIndex(ctx, 0)
                            local button_name = button.name or "Button " .. i
                            local preview_color = button.color or 0x333333FF
                            
                            if button.use_icon and button.icon_name then
                                local icon, status = ButtonEditor.LoadIconForPreview(button)
                                
                                if status == "cached" or status == "loaded" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), preview_color)
                                    
                                    if r.ImGui_Button(ctx, "##preview_bg_" .. i, 180, 25) then
                                    end
                                    
                                    local button_min_x, button_min_y = r.ImGui_GetItemRectMin(ctx)
                                    local icon_x = button_min_x + 3
                                    local icon_y = button_min_y + 2.5
                                    local text_x = icon_x + 22
                                    local text_y = button_min_y + 4
                                    
                                    local draw_list = r.ImGui_GetWindowDrawList(ctx)
                                    
                                    local uv_x1 = 0.0
                                    local uv_x2 = 0.33333
                                    local uv_y1 = 0.0
                                    local uv_y2 = 1.0
                                    
                                    r.ImGui_DrawList_AddImage(draw_list, icon, 
                                        icon_x, icon_y, 
                                        icon_x + 20, icon_y + 20,
                                        uv_x1, uv_y1, uv_x2, uv_y2)
                                    
                                    local text_color = button.text_color or 0xFFFFFFFF
                                    r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, button_name)
                                    
                                    r.ImGui_PopStyleColor(ctx)
                                    
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, ButtonEditor.GetIconStatusText(button, status))
                                    end
                                    
                                elseif status == "file_not_found" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x663333FF)
                                    r.ImGui_Button(ctx, "🚫 " .. button_name .. "##preview_" .. i, 180, 25)
                                    r.ImGui_PopStyleColor(ctx)
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, ButtonEditor.GetIconStatusText(button, status))
                                    end
                                    
                                elseif status == "load_failed" then
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x665533FF)
                                    r.ImGui_Button(ctx, "⚠️ " .. button_name .. "##preview_" .. i, 180, 25)
                                    r.ImGui_PopStyleColor(ctx)
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, ButtonEditor.GetIconStatusText(button, status))
                                    end
                                    
                                else
                                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), preview_color)
                                    r.ImGui_Button(ctx, "? " .. button_name .. "##preview_" .. i, 180, 25)
                                    r.ImGui_PopStyleColor(ctx)
                                    if r.ImGui_IsItemHovered(ctx) then
                                        r.ImGui_SetTooltip(ctx, "Unknown icon error")
                                    end
                                end
                            else
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), preview_color)
                                r.ImGui_Button(ctx, button_name .. "##preview_" .. i, 180, 25)
                                r.ImGui_PopStyleColor(ctx)
                            end
                            
                            r.ImGui_TableSetColumnIndex(ctx, 1)
                            local action_text = "No action"
                            if button.left_click and button.left_click.name then
                                action_text = button.left_click.name
                            elseif button.left_click and button.left_click.command then
                                action_text = tostring(button.left_click.command)
                            end
                            r.ImGui_Text(ctx, action_text)
                            
                            r.ImGui_TableSetColumnIndex(ctx, 2)
                            if r.ImGui_Button(ctx, "Copy", 50, 25) then
                                if ButtonEditor.CopyButtonToCurrentPreset(button, custom_buttons) then
                                    r.ImGui_SetTooltip(ctx, "Button copied successfully!")
                                end
                            end
                            if r.ImGui_IsItemHovered(ctx) then
                                r.ImGui_SetTooltip(ctx, "Copy this button to current preset")
                            end
                            
                            r.ImGui_PopID(ctx)
                        end
                        
                        r.ImGui_PopStyleVar(ctx) 
                        
                        r.ImGui_EndTable(ctx)
                    end
                end
                
                r.ImGui_TreePop(ctx)
            end
            r.ImGui_PopID(ctx)
        end
    end
end

-- Handle IconBrowser separately to avoid GUI conflicts with settings window
function ButtonEditor.HandleIconBrowser(ctx, custom_buttons, settings)
    local selected_icon = IconBrowser.Show(ctx, settings)
    if selected_icon and active_icon_button then
        local ButtonRenderer = require('button_renderer')
        if active_icon_button.icon_name and ButtonRenderer.image_cache[active_icon_button.icon_name] then
            ButtonRenderer.image_cache[active_icon_button.icon_name] = nil
        end
        
        active_icon_button.icon_name = selected_icon
        active_icon_button.icon = nil
        custom_buttons.SaveCurrentButtons()
        has_unsaved_changes = true
        
        IconBrowser.selected_icon = nil
    end
end

ButtonEditor.cb_section_states = cb_section_states

return ButtonEditor

