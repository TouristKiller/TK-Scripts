local r = reaper
local resource_path = r.GetResourcePath()
local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/-]-$]])
local button_presets_path = script_path .. "tk_transport_buttons/presets/"
local IconBrowser = require('icon_browser')
local ButtonEditor = {}
local new_preset_name = ""
local new_group_name = ""

local cb_section_states = {
    basic_open = true,
    group_open = false,
    colors_open = false,
    left_open = false,
    right_open = false,
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



function ButtonEditor.ShowPresetsInline(ctx, custom_buttons, opts)
    opts = opts or {}
    r.ImGui_Text(ctx, "Button Presets:")
    r.ImGui_SameLine(ctx)
    local presets = custom_buttons.GetButtonPresets()
    local current_preset = custom_buttons.current_preset or "Select Preset"
    local avail_w1, _ = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetNextItemWidth(ctx, math.max(140, math.floor(avail_w1 * 0.35)))
    if r.ImGui_BeginCombo(ctx, "##ButtonPresetCombo", current_preset) then
        for _, preset in ipairs(presets) do
            if preset and type(preset) == "string" then
                if r.ImGui_Selectable(ctx, preset, preset == current_preset) then
                    custom_buttons.LoadButtonPreset(preset)
                    custom_buttons.SaveCurrentButtons()
                end
                if preset == current_preset then r.ImGui_SetItemDefaultFocus(ctx) end
            end
        end
        r.ImGui_EndCombo(ctx)
    end

    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Resave") and custom_buttons.current_preset then
        custom_buttons.SaveButtonPreset(custom_buttons.current_preset)
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
    local input_w = math.max(120, math.floor(avail_w2 - save_btn_w - 10))
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
    
    if r.ImGui_Button(ctx, "Create action for this preset") and custom_buttons.current_preset then
        r.ShowConsoleMsg("Attempting to create action for: " .. custom_buttons.current_preset .. "\n")
        local cmd_id = custom_buttons.RegisterCommandToLoadPreset(custom_buttons.current_preset)
        r.ShowConsoleMsg("Command ID: " .. tostring(cmd_id) .. "\n")
        if cmd_id ~= 0 then
            r.ImGui_OpenPopup(ctx, "ActionCreatedPopup")
        end
    end
    r.ImGui_SameLine(ctx)
    if opts.small_font then r.ImGui_PushFont(ctx, opts.small_font, opts.small_font_size or 10) end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xA0A0A0FF)
    r.ImGui_Text(ctx, "Creates an Action that loads this preset (for keybinds/toolbars)")
    r.ImGui_PopStyleColor(ctx)
    if opts.small_font then r.ImGui_PopFont(ctx) end
    
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

        local combo_label = custom_buttons.current_edit and
            custom_buttons.buttons[custom_buttons.current_edit].name or "Select A Button"

        do
            local has_sel = custom_buttons.current_edit ~= nil
            local label_text = "Buttons"
            r.ImGui_Text(ctx, label_text)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 170)
        end

    if r.ImGui_BeginCombo(ctx, "##ButtonsCombo", combo_label) then
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
            local group_names = {}
            for g,_ in pairs(groups) do table.insert(group_names, g) end
            table.sort(group_names, function(a,b) return a:lower()<b:lower() end)
            for _,g in ipairs(group_names) do
                table.sort(groups[g], function(a,b) return (a.btn.name or ""):lower() < (b.btn.name or ""):lower() end)
            end
            table.sort(ungrouped, function(a,b) return (a.btn.name or ""):lower() < (b.btn.name or ""):lower() end)
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
        do
            local has_sel = custom_buttons.current_edit ~= nil
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 160)
            local current_name = ""
            if has_sel then current_name = custom_buttons.buttons[custom_buttons.current_edit].name or "" end
            local rvn, newname = r.ImGui_InputText(ctx, "##cb_name_inline", current_name)
            if rvn and has_sel then
                custom_buttons.buttons[custom_buttons.current_edit].name = newname
                custom_buttons.SaveCurrentButtons()
            end

            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "New Button") then
                table.insert(custom_buttons.buttons, custom_buttons.CreateNewButton())
                custom_buttons.current_edit = #custom_buttons.buttons
                custom_buttons.SaveCurrentButtons()
            end
            r.ImGui_SameLine(ctx)
            local can_delete = has_sel
            if r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, not can_delete) end
            if r.ImGui_Button(ctx, "Delete!") and can_delete then
                table.remove(custom_buttons.buttons, custom_buttons.current_edit)
                custom_buttons.current_edit = nil
                custom_buttons.SaveCurrentButtons()
            end
            if r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        end
    if custom_buttons.current_edit then
        local button = custom_buttons.buttons[custom_buttons.current_edit]
        local changed = false
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

            r.ImGui_Text(ctx, "Width   ")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 170)
            local rvw; rvw, button.width = r.ImGui_SliderInt(ctx, "##btnWidth", button.width, 12, 400)
            if rvw then
                button.width = clamp(to_int(button.width, 60), 12, 400)
                changed = true
            end

            r.ImGui_SameLine(ctx); r.ImGui_Dummy(ctx, 18, 0); r.ImGui_SameLine(ctx)

            r.ImGui_Text(ctx, "X")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 85)
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

            r.ImGui_SameLine(ctx); r.ImGui_Dummy(ctx, 12, 0); r.ImGui_SameLine(ctx)

            r.ImGui_Text(ctx, "Y")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 85)
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

            if changed then
                button.position   = button.position_px   / math.max(1, canvas_width)
                button.position_y = button.position_y_px / math.max(1, canvas_height)
                custom_buttons.SaveCurrentButtons()
            end
            r.ImGui_Separator(ctx)
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
                    rv, button.visible = r.ImGui_Checkbox(ctx, "Visible", button.visible)
                    changed = changed or rv

                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    rv, button.show_border = r.ImGui_Checkbox(ctx, "Border", button.show_border ~= false)
                    if rv then
                        button.show_border = (button.show_border ~= false)
                        changed = true
                    end

                    r.ImGui_TableSetColumnIndex(ctx, 2)
                    rv, button.use_icon = r.ImGui_Checkbox(ctx, "Use Icon", button.use_icon)
                    changed = changed or rv

                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    if button.use_icon then
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

                    r.ImGui_TableSetColumnIndex(ctx, 4)
                    if button.use_icon then
                        local rv_tt
                        rv_tt, settings.show_custom_button_tooltip = r.ImGui_Checkbox(ctx, "Show tooltip", settings.show_custom_button_tooltip)
                        changed = changed or rv_tt
                    end

                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableSetColumnIndex(ctx, 0)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    local rv_col
                    rv_col, button.color = r.ImGui_ColorEdit4(ctx, "Base Color", button.color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 1)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.hover_color = r.ImGui_ColorEdit4(ctx, "Hover Color", button.hover_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 2)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.active_color = r.ImGui_ColorEdit4(ctx, "Active Color", button.active_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.text_color = r.ImGui_ColorEdit4(ctx, "Text Color", button.text_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_TableSetColumnIndex(ctx, 4)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    rv_col, button.border_color = r.ImGui_ColorEdit4(ctx, "Border Color", button.border_color, colorFlags)
                    changed = changed or rv_col

                    r.ImGui_EndTable(ctx)
                end
                r.ImGui_EndTable(ctx)
            end
        end

        local group_set, existing_groups = {}, {}
        for _, b in ipairs(custom_buttons.buttons) do
            local g = b.group
            if g and g ~= "" and not group_set[g] then
                group_set[g] = true
                table.insert(existing_groups, g)
            end
        end
        table.sort(existing_groups, function(a,b) return a:lower() < b:lower() end)

        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Existing Group")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 220)
        local current_group_label = (button.group and button.group ~= "") and button.group or "(none)"
        if r.ImGui_BeginCombo(ctx, "##ExistingGroup", current_group_label) then
            if r.ImGui_Selectable(ctx, "(none)", current_group_label == "(none)") then
                button.group = ""
                changed = true
            end
            for _, g in ipairs(existing_groups) do
                if r.ImGui_Selectable(ctx, g, button.group == g) then
                    button.group = g
                    new_group_name = g 
                    changed = true
                end
                if button.group == g then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end

        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "New Group")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 220)
        local rv_ng
        rv_ng, new_group_name = r.ImGui_InputText(ctx, "##NewGroupName", new_group_name or (button.group or ""))
        if rv_ng then
            button.group = new_group_name or ""
            changed = true
        end

        if changed then custom_buttons.SaveCurrentButtons() end

        r.ImGui_Text(ctx, "Edit all buttons sharing this group name ")
        local gcount = 0
        for _, b in ipairs(custom_buttons.buttons) do
            if b.group and b.group ~= "" and button.group == b.group then
                gcount = gcount + 1
            end
        end
        if button.group and button.group ~= "" then
            r.ImGui_SameLine(ctx)
            r.ImGui_TextColored(ctx, 0x00FF88FF, "Current Group: " .. button.group .. " (" .. gcount .. ")")
        end
        local gname = button.group or ""
        if gname == "" then
            r.ImGui_TextDisabled(ctx, "(Deze knop heeft geen groepsnaam)")
        else
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
                    custom_buttons.SaveCurrentButtons()
                end
            end

            if r.ImGui_Button(ctx, "<-X##grpMoveLeft") then
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Verplaats de hele groep 1 pixel naar links") end
                adjust_group(-1, 0)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "X->##grpMoveRight") then
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Verplaats de hele groep 1 pixel naar rechts (begrensd)") end
                adjust_group(1, 0)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "<-Y##grpMoveUp") then
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Verplaats de hele groep 1 pixel omhoog") end
                adjust_group(0, -1)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Y->##grpMoveDown") then
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Verplaats de hele groep 1 pixel omlaag") end
                adjust_group(0, 1)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Align Y") then
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Zet alle knoppen in deze groep op dezelfde Y-positie") end
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.position_y = button.position_y
                        b.position_y_px = button.position_y_px
                        sanitize_button_xy(b, canvas_w, canvas_h)
                    end
                end
                custom_buttons.SaveCurrentButtons()
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Group Width") then
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Gebruik deze breedte voor de hele groep") end
                local new_width = clamp(to_int(button.width, 60), 12, 400)
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.width = new_width
                    end
                end
                custom_buttons.SaveCurrentButtons()
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Color") then
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Kopieer alle kleuren naar de groep") end
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        b.color = button.color
                        b.hover_color = button.hover_color
                        b.active_color = button.active_color
                        b.text_color = button.text_color
                        b.border_color = button.border_color
                    end
                end
                custom_buttons.SaveCurrentButtons()
            end
            r.ImGui_SameLine(ctx)
            local all_visible = true
            for _, b in ipairs(custom_buttons.buttons) do
                if b.group == gname and not b.visible then all_visible = false break end
            end
            local vis_label = all_visible and "Hide Group" or "Show Group"
            if r.ImGui_Button(ctx, vis_label .. "##grpToggleVis") then
                local new_state = not all_visible
                for _, b in ipairs(custom_buttons.buttons) do if b.group == gname then b.visible = new_state end end
                custom_buttons.SaveCurrentButtons()
            end
            if r.ImGui_IsItemHovered(ctx) then
                if all_visible then
                    r.ImGui_SetTooltip(ctx, "Verberg alle knoppen in deze groep")
                else
                    r.ImGui_SetTooltip(ctx, "Toon alle knoppen in deze groep")
                end
            end
            local all_borders = true
            for _, b in ipairs(custom_buttons.buttons) do
                if b.group == gname and b.show_border == false then all_borders = false break end
            end
            r.ImGui_SameLine(ctx)
            local border_label = all_borders and "No Borders" or "Borders"
            if r.ImGui_Button(ctx, border_label .. "##grpToggleBorder") then
                local new_border = not all_borders
                for _, b in ipairs(custom_buttons.buttons) do if b.group == gname then b.show_border = new_border end end
                custom_buttons.SaveCurrentButtons()
            end
            if r.ImGui_IsItemHovered(ctx) then
                if all_borders then
                    r.ImGui_SetTooltip(ctx, "Zet de rand uit voor de hele groep")
                else
                    r.ImGui_SetTooltip(ctx, "Zet de rand aan voor de hele groep")
                end
            end
        end

        if opts and opts.render_global_offset then
            r.ImGui_Separator(ctx)
            opts.render_global_offset(ctx)
            r.ImGui_Separator(ctx)
        else
            r.ImGui_Separator(ctx)
        end
            r.ImGui_Text(ctx, "Left Click Action:")
            local changed = false

       
            r.ImGui_Text(ctx, "Action Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 220)
            do
                local rv_name, new_name = r.ImGui_InputText(ctx, "##lcaName", button.left_click.name)
                if rv_name then button.left_click.name = new_name; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "ID")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 140)
            do
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "##lcaCmd", button.left_click.command or "")
                if rv_cmd then button.left_click.command = new_command; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Type")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 140)
            do
                local rv_type, new_type = r.ImGui_Combo(ctx, "##lcaType", button.left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then button.left_click.type = new_type; changed = true end
            end

            if changed then custom_buttons.SaveCurrentButtons() end

            r.ImGui_Separator(ctx)

            r.ImGui_Text(ctx, "Right Click Menu:")
            r.ImGui_SameLine(ctx)
            r.ImGui_TextDisabled(ctx, "Use '/' in the name to create submenus (e.g. Tools/Render/Stem)")
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

                local child_h = 300
                local child_open = r.ImGui_BeginChild(ctx, "RCM_TABLE_CHILD", 0, child_h)

                if child_open then
                    
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
                                if from and from ~= idx and MoveItem(button.right_menu.items, from, idx) then
                                    custom_buttons.SaveCurrentButtons()
                                end
                            end
                            r.ImGui_EndDragDropTarget(ctx)
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 1)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local rv_name, new_name = r.ImGui_InputText(ctx, "##name", item.name)
                        if rv_name then item.name = new_name; custom_buttons.SaveCurrentButtons() end

                        r.ImGui_TableSetColumnIndex(ctx, 2)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local rv_cmd, new_cmd = r.ImGui_InputText(ctx, "##cmd", item.command or "")
                        if rv_cmd then item.command = new_cmd; custom_buttons.SaveCurrentButtons() end

                        r.ImGui_TableSetColumnIndex(ctx, 3)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        local rv_type, new_type = r.ImGui_Combo(ctx, "##type", item.type or 0, "Main\0MIDI Editor\0")
                        if rv_type then item.type = new_type; custom_buttons.SaveCurrentButtons() end

                        r.ImGui_TableSetColumnIndex(ctx, 4)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        if idx > 1 and r.ImGui_Button(ctx, "↑##up") then
                            if MoveItem(button.right_menu.items, idx, idx - 1) then custom_buttons.SaveCurrentButtons() end
                        end
                        r.ImGui_SameLine(ctx)
                        if idx < #button.right_menu.items and r.ImGui_Button(ctx, "↓##down") then
                            if MoveItem(button.right_menu.items, idx, idx + 1) then custom_buttons.SaveCurrentButtons() end
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 5)
                        r.ImGui_SetNextItemWidth(ctx, -1)
                        if r.ImGui_Button(ctx, "X##del") then
                            remove_index = idx
                        end

                        r.ImGui_PopID(ctx)
                    end

                        r.ImGui_EndTable(ctx)
                    end

                    r.ImGui_EndChild(ctx)
                end

                if remove_index then
                    table.remove(button.right_menu.items, remove_index)
                    custom_buttons.SaveCurrentButtons()
                end

            r.ImGui_Text(ctx, "Set Left click for single click action, right click for menu. Always save button in preset after editing, or it will be lost")
            
        end
end

return ButtonEditor
