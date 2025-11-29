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
    toggle_open = false,
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

-- Style clipboard for copy/paste functionality
local style_clipboard = {
    has_data = false,
    data = {},
    -- Which properties to copy (saved preferences)
    copy_settings = {
        width = true,
        border = true,
        tooltip = true,
        use_icon = true,
        show_text = true,
        color_base = true,
        color_hover = true,
        color_active = true,
        color_text = true,
        color_border = true,
        font = true,
        font_size = true,
        rounding = true,
        border_thickness = true,
    }
}

local style_settings_window = {
    open = false,
    ctx = nil,
    title = "Copy Style Settings"
}

-- Auto align spacing setting
local auto_align_spacing = 3  -- default 3px

-- New button placement spacing (shared with custom_buttons.lua)
local new_button_spacing = 5  -- default 5px

-- Load auto align spacing from ExtState
local function LoadAutoAlignSpacing()
    local value = r.GetExtState("TK_TRANSPORT_BUTTON_EDITOR", "auto_align_spacing")
    if value and value ~= "" then
        local num = tonumber(value)
        if num and num >= 0 and num <= 50 then
            auto_align_spacing = num
        end
    end
end

-- Save auto align spacing to ExtState
local function SaveAutoAlignSpacing()
    r.SetExtState("TK_TRANSPORT_BUTTON_EDITOR", "auto_align_spacing", tostring(auto_align_spacing), true)
end

-- Load new button spacing from ExtState
local function LoadNewButtonSpacing()
    local value = r.GetExtState("TK_TRANSPORT_BUTTON_EDITOR", "new_button_spacing")
    if value and value ~= "" then
        local num = tonumber(value)
        if num and num >= 0 and num <= 50 then
            new_button_spacing = num
        end
    end
end

-- Save new button spacing to ExtState
local function SaveNewButtonSpacing()
    r.SetExtState("TK_TRANSPORT_BUTTON_EDITOR", "new_button_spacing", tostring(new_button_spacing), true)
end

-- Getter for new button spacing (used by custom_buttons.lua)
function ButtonEditor.GetNewButtonSpacing()
    return new_button_spacing
end

-- Load style copy settings from ExtState
local function LoadStyleCopySettings()
    for key, _ in pairs(style_clipboard.copy_settings) do
        local value = r.GetExtState("TK_TRANSPORT_BUTTON_STYLE", key)
        if value == "true" then
            style_clipboard.copy_settings[key] = true
        elseif value == "false" then
            style_clipboard.copy_settings[key] = false
        end
        -- If value is empty, keep the default
    end
end

-- Save style copy settings to ExtState
local function SaveStyleCopySettings()
    for key, value in pairs(style_clipboard.copy_settings) do
        r.SetExtState("TK_TRANSPORT_BUTTON_STYLE", key, tostring(value), true)
    end
end

-- Load settings on module initialization
LoadStyleCopySettings()
LoadAutoAlignSpacing()
LoadNewButtonSpacing()

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

-- Function to show style copy settings window
local function ShowStyleSettingsWindow(ctx)
    if not style_settings_window.open then return end
    
    local flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_AlwaysAutoResize()
    local visible, open = r.ImGui_Begin(ctx, style_settings_window.title, true, flags)
    
    if visible then
        r.ImGui_Text(ctx, "Select which properties to copy:")
        r.ImGui_Separator(ctx)
        
        r.ImGui_Text(ctx, "Size & Layout:")
        local rv
        rv, style_clipboard.copy_settings.width = r.ImGui_Checkbox(ctx, "Icon Size / Width", style_clipboard.copy_settings.width)
        if rv then SaveStyleCopySettings() end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Display Options:")
        rv, style_clipboard.copy_settings.border = r.ImGui_Checkbox(ctx, "Show Border", style_clipboard.copy_settings.border)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.use_icon = r.ImGui_Checkbox(ctx, "Use Icon", style_clipboard.copy_settings.use_icon)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.show_text = r.ImGui_Checkbox(ctx, "Show Text with Icon", style_clipboard.copy_settings.show_text)
        if rv then SaveStyleCopySettings() end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Colors:")
        rv, style_clipboard.copy_settings.color_base = r.ImGui_Checkbox(ctx, "Base Color", style_clipboard.copy_settings.color_base)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.color_hover = r.ImGui_Checkbox(ctx, "Hover Color", style_clipboard.copy_settings.color_hover)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.color_active = r.ImGui_Checkbox(ctx, "Active Color", style_clipboard.copy_settings.color_active)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.color_text = r.ImGui_Checkbox(ctx, "Text Color", style_clipboard.copy_settings.color_text)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.color_border = r.ImGui_Checkbox(ctx, "Border Color", style_clipboard.copy_settings.color_border)
        if rv then SaveStyleCopySettings() end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Text & Font:")
        rv, style_clipboard.copy_settings.font = r.ImGui_Checkbox(ctx, "Font", style_clipboard.copy_settings.font)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.font_size = r.ImGui_Checkbox(ctx, "Font Size", style_clipboard.copy_settings.font_size)
        if rv then SaveStyleCopySettings() end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Border Style:")
        rv, style_clipboard.copy_settings.rounding = r.ImGui_Checkbox(ctx, "Button Rounding", style_clipboard.copy_settings.rounding)
        if rv then SaveStyleCopySettings() end
        rv, style_clipboard.copy_settings.border_thickness = r.ImGui_Checkbox(ctx, "Border Thickness", style_clipboard.copy_settings.border_thickness)
        if rv then SaveStyleCopySettings() end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        local button_width = 80
        local avail = r.ImGui_GetContentRegionAvail(ctx)
        local center_x = (avail - (button_width * 3 + 20)) * 0.5
        if center_x > 0 then
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + center_x)
        end
        
        if r.ImGui_Button(ctx, "Select All", button_width) then
            for k, _ in pairs(style_clipboard.copy_settings) do
                style_clipboard.copy_settings[k] = true
            end
            SaveStyleCopySettings()
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Deselect All", button_width) then
            for k, _ in pairs(style_clipboard.copy_settings) do
                style_clipboard.copy_settings[k] = false
            end
            SaveStyleCopySettings()
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "OK", button_width) then
            style_settings_window.open = false
        end
        
        r.ImGui_End(ctx)
    end
    
    if not open then
        style_settings_window.open = false
    end
end

-- Function to copy style from button
local function CopyButtonStyle(button)
    if not button then return end
    
    style_clipboard.data = {}
    local settings = style_clipboard.copy_settings
    
    if settings.width then
        style_clipboard.data.width = button.width
    end
    if settings.border then
        style_clipboard.data.show_border = button.show_border
    end
    if settings.use_icon then
        style_clipboard.data.use_icon = button.use_icon
        style_clipboard.data.icon_name = button.icon_name
    end
    if settings.show_text then
        style_clipboard.data.show_text_with_icon = button.show_text_with_icon
    end
    if settings.color_base then
        style_clipboard.data.color = button.color
    end
    if settings.color_hover then
        style_clipboard.data.hover_color = button.hover_color
    end
    if settings.color_active then
        style_clipboard.data.active_color = button.active_color
    end
    if settings.color_text then
        style_clipboard.data.text_color = button.text_color
    end
    if settings.color_border then
        style_clipboard.data.border_color = button.border_color
    end
    if settings.font then
        style_clipboard.data.font_name = button.font_name
    end
    if settings.font_size then
        style_clipboard.data.font_size = button.font_size
    end
    if settings.rounding then
        style_clipboard.data.rounding = button.rounding
    end
    if settings.border_thickness then
        style_clipboard.data.border_thickness = button.border_thickness
    end
    
    style_clipboard.has_data = true
end

-- Function to paste style to button
local function PasteButtonStyle(button)
    if not button or not style_clipboard.has_data then return false end
    
    local changed = false
    
    for key, value in pairs(style_clipboard.data) do
        if key == "icon_name" then
            -- Special handling for icons - also clear the cached icon
            if button.icon_name ~= value then
                local ButtonRenderer = require('button_renderer')
                if button.icon_name and ButtonRenderer.image_cache[button.icon_name] then
                    ButtonRenderer.image_cache[button.icon_name] = nil
                end
                button.icon_name = value
                button.icon = nil
                changed = true
            end
        elseif key == "font_name" or key == "font_size" then
            -- Clear font cache when font properties change
            if button[key] ~= value then
                button[key] = value
                button.font = nil
                changed = true
            end
        else
            -- Regular property copy
            if button[key] ~= value then
                button[key] = value
                changed = true
            end
        end
    end
    
    return changed
end

-- Function to paste style to all buttons in a group
local function PasteStyleToGroup(button, custom_buttons)
    if not button or not button.group or button.group == "" then return false end
    if not style_clipboard.has_data then return false end
    
    local changed = false
    local gname = button.group
    
    for _, b in ipairs(custom_buttons.buttons) do
        if b.group == gname then
            -- Use PasteButtonStyle for each button in the group
            if PasteButtonStyle(b) then
                changed = true
            end
        end
    end
    
    return changed
end

-- Function to calculate actual button width including icon and text
local function CalculateButtonWidth(ctx, button)
    if button.use_icon and button.icon_name then
        if button.show_text_with_icon and button.name and button.name ~= "" then
            -- Icon + text mode
            local icon_size = button.width or 100
            local icon_padding = (button.show_border ~= false) and 4 or 0
            local separator_width = (button.show_border ~= false) and 12 or 4
            local padding = 8
            
            -- Calculate text size (need to push font if custom)
            local font_pushed = false
            if button.font_name and button.font_size then
                if not button.font then
                    button.font = r.ImGui_CreateFont(button.font_name, button.font_size)
                end
                if button.font and r.ImGui_ValidatePtr(button.font, 'ImGui_Font*') then
                    r.ImGui_PushFont(ctx, button.font, button.font_size)
                    font_pushed = true
                end
            end
            
            local text_size = r.ImGui_CalcTextSize(ctx, button.name)
            
            if font_pushed then
                r.ImGui_PopFont(ctx)
            end
            
            local total_width = icon_padding + icon_size + separator_width + text_size + padding
            return total_width
        else
            -- Icon only mode
            return button.width or 100
        end
    else
        -- Text only mode
        local font_pushed = false
        if button.font_name and button.font_size then
            if not button.font then
                button.font = r.ImGui_CreateFont(button.font_name, button.font_size)
            end
            if button.font and r.ImGui_ValidatePtr(button.font, 'ImGui_Font*') then
                r.ImGui_PushFont(ctx, button.font, button.font_size)
                font_pushed = true
            end
        end
        
        local text_size = r.ImGui_CalcTextSize(ctx, button.name or "")
        local padding = 16  -- ImGui default button padding
        
        if font_pushed then
            r.ImGui_PopFont(ctx)
        end
        
        -- Use either calculated width or button.width, whichever is larger
        local calculated = text_size + padding
        return math.max(calculated, button.width or 0)
    end
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
                    r.SetExtState("TK_TRANSPORT", "last_button_preset", preset, true)
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

    if not cb_section_states.actions_open and not cb_section_states.toggle_open then
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
            elseif button.use_image then
                if button.show_text_with_icon then
                    width_label = "Image Max Width"
                    show_total_width = true
                else
                    width_label = "Max Width"
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
                
                if r.ImGui_BeginTable(ctx, "CB_Props", 5, r.ImGui_TableFlags_SizingFixedFit()) then
                    r.ImGui_TableSetupColumn(ctx, "Col0", r.ImGui_TableColumnFlags_WidthFixed(), 110)
                    r.ImGui_TableSetupColumn(ctx, "Col1", r.ImGui_TableColumnFlags_WidthFixed(), 80)
                    r.ImGui_TableSetupColumn(ctx, "Col2", r.ImGui_TableColumnFlags_WidthFixed(), 120)
                    r.ImGui_TableSetupColumn(ctx, "Col3", r.ImGui_TableColumnFlags_WidthFixed(), 90)
                    r.ImGui_TableSetupColumn(ctx, "Col4", r.ImGui_TableColumnFlags_WidthStretch())
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
                    local use_icon_or_image = button.use_icon or button.use_image
                    rv, use_icon_or_image = r.ImGui_Checkbox(ctx, "Use Icon/Image", use_icon_or_image)
                    if rv then
                        if use_icon_or_image then
                            if not button.use_icon and not button.use_image then
                                button.use_icon = true
                            end
                        else
                            button.use_icon = false
                            button.use_image = false
                        end
                        changed = true
                    end

                    r.ImGui_TableSetColumnIndex(ctx, 3)
                    if button.use_icon or button.use_image then
                        rv, button.show_text_with_icon = r.ImGui_Checkbox(ctx, "Show Text", button.show_text_with_icon)
                        changed = changed or rv
                    end

                    r.ImGui_TableSetColumnIndex(ctx, 4)
                    r.ImGui_SetNextItemWidth(ctx, -1)
                    if button.use_image and button.show_text_with_icon then
                        if not button.text_position then
                            button.text_position = "right"
                        end
                        
                        local pos_labels = {"Left", "Right", "Bottom", "Top", "Overlay Center", "Overlay Bottom", "Overlay Top"}
                        local pos_values = {"left", "right", "bottom", "top", "overlay", "overlay_bottom", "overlay_top"}
                        
                        local current_idx = 0
                        for i, val in ipairs(pos_values) do
                            if button.text_position == val then
                                current_idx = i - 1
                                break
                            end
                        end
                        
                        local combo_label = pos_labels[current_idx + 1] or "Right"
                        if r.ImGui_BeginCombo(ctx, "##textpos", combo_label) then
                            for i, val in ipairs(pos_values) do
                                local is_selected = (button.text_position == val)
                                if r.ImGui_Selectable(ctx, pos_labels[i], is_selected) then
                                    button.text_position = val
                                    changed = true
                                end
                                if is_selected then
                                    r.ImGui_SetItemDefaultFocus(ctx)
                                end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                    else
                        r.ImGui_BeginDisabled(ctx)
                        if r.ImGui_BeginCombo(ctx, "##textpos_disabled", "") then
                            r.ImGui_EndCombo(ctx)
                        end
                        r.ImGui_EndDisabled(ctx)
                    end

                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableSetColumnIndex(ctx, 0)
                    if button.use_icon or button.use_image then
                        local is_browser_active = IconBrowser.show_window and active_icon_button == button
                        
                        if not is_browser_active then
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF4040FF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF5555FF)
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF2020FF)
                        else
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4080FFFF)
                        end
                        
                        if r.ImGui_Button(ctx, is_browser_active and "Close Browser##browse" or "Open Browser##browse") then
                            if is_browser_active then
                                IconBrowser.show_window = false
                                active_icon_button = nil
                            else
                                if button.use_image and button.image_path then
                                    local last_folder = button.image_path:match("(.+[/\\])") or ""
                                    IconBrowser.SetBrowseMode("images", last_folder)
                                else
                                    IconBrowser.SetBrowseMode("icons")
                                end
                                IconBrowser.show_window = true
                                active_icon_button = button
                            end
                        end
                        
                        if not is_browser_active then
                            r.ImGui_PopStyleColor(ctx, 3)
                        else
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
                            "Georgia", "Courier New", "Consolas", "Trebuchet MS", "Impact", "Roboto",
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
            r.ImGui_Text(ctx, "Group Settings:")
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
            
            -- Auto Align X with spacing input
            r.ImGui_Text(ctx, "Spacing:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 50)
            local rv, new_spacing = r.ImGui_InputDouble(ctx, "px##alignSpacing", auto_align_spacing, 0, 0, "%.0f")
            if rv then
                auto_align_spacing = clamp(to_int(new_spacing, 3), 0, 50)
                SaveAutoAlignSpacing()
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Spacing between buttons for Auto Align X (0-50 pixels)") end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Auto Align X") then
                -- Collect all buttons in this group
                local group_buttons = {}
                for _, b in ipairs(custom_buttons.buttons) do
                    if b.group == gname then
                        table.insert(group_buttons, b)
                    end
                end
                
                -- Sort by current X position
                table.sort(group_buttons, function(a, b)
                    return (a.position_px or 0) < (b.position_px or 0)
                end)
                
                -- Auto-align with user-defined spacing
                local current_x = group_buttons[1] and group_buttons[1].position_px or 0
                
                for _, b in ipairs(group_buttons) do
                    b.position_px = current_x
                    b.position = current_x / math.max(1, canvas_w)
                    sanitize_button_xy(b, canvas_w, canvas_h)
                    
                    -- Calculate actual button width (includes icon, text, padding)
                    local button_width = CalculateButtonWidth(ctx, b)
                    current_x = current_x + button_width + auto_align_spacing
                end
                
                custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Auto-align buttons horizontally with custom spacing\n(calculates actual width including text and icons)") end
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        local has_sel = custom_buttons.current_edit ~= nil
        
        r.ImGui_Text(ctx, "Button Style:")
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, not has_sel) end
        if r.ImGui_Button(ctx, "Copy Style", 100, 0) and has_sel then
            CopyButtonStyle(custom_buttons.buttons[custom_buttons.current_edit])
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Copy style settings from this button")
        end
        if r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "⚙##style_settings", 30, 0) then
            style_settings_window.open = not style_settings_window.open
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Choose which style properties to copy")
        end
        
        r.ImGui_SameLine(ctx)
        local can_paste = has_sel and style_clipboard.has_data
        if r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, not can_paste) end
        if style_clipboard.has_data then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4080FF88)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x5090FFAA)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x60A0FFCC)
        end
        if r.ImGui_Button(ctx, "Paste Style", 100, 0) and can_paste then
            if PasteButtonStyle(custom_buttons.buttons[custom_buttons.current_edit]) then
                custom_buttons.SaveCurrentButtons()
                has_unsaved_changes = true
            end
        end
        if style_clipboard.has_data then
            r.ImGui_PopStyleColor(ctx, 3)
        end
        if r.ImGui_IsItemHovered(ctx) then
            if style_clipboard.has_data then
                r.ImGui_SetTooltip(ctx, "Paste copied style to this button")
            else
                r.ImGui_SetTooltip(ctx, "No style copied yet")
            end
        end
        if r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        
        local button = custom_buttons.buttons[custom_buttons.current_edit]
        if button and button.group and button.group ~= "" then
            r.ImGui_SameLine(ctx)
            local can_paste_group = style_clipboard.has_data
            if r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, not can_paste_group) end
            if style_clipboard.has_data then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00AA44FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x10BB55FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x20CC66FF)
            end
            if r.ImGui_Button(ctx, "Paste Style to Group", 150, 0) and can_paste_group then
                if PasteStyleToGroup(button, custom_buttons) then
                    custom_buttons.SaveCurrentButtons()
                    has_unsaved_changes = true
                end
            end
            if style_clipboard.has_data then
                r.ImGui_PopStyleColor(ctx, 3)
            end
            if r.ImGui_IsItemHovered(ctx) then
                if style_clipboard.has_data then
                    r.ImGui_SetTooltip(ctx, "Paste the copied style to all buttons in group '" .. button.group .. "'\n(excluding position and alignment)")
                else
                    r.ImGui_SetTooltip(ctx, "No style copied yet. Use 'Copy Style' button first.")
                end
            end
            if r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        end
        
        -- "Copy style from button" dropdown for quick style copying
        if has_sel and #custom_buttons.buttons > 1 then
            r.ImGui_Text(ctx, "Copy style from:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 200)
            if r.ImGui_BeginCombo(ctx, "##copy_style_from_button", "Select button...") then
                for i, btn in ipairs(custom_buttons.buttons) do
                    if i ~= custom_buttons.current_edit then
                        local display_name = btn.name or ("Button " .. i)
                        if btn.group and btn.group ~= "" then
                            display_name = display_name .. " [" .. btn.group .. "]"
                        end
                        if r.ImGui_Selectable(ctx, display_name .. "##copy_from_" .. i) then
                            -- Copy style from selected button
                            CopyButtonStyle(btn)
                            -- Immediately paste to current button
                            if PasteButtonStyle(custom_buttons.buttons[custom_buttons.current_edit]) then
                                custom_buttons.SaveCurrentButtons()
                                has_unsaved_changes = true
                            end
                        end
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Quickly copy style from another button to this button")
            end
        end
        
        -- "Copy position from button" dropdown - places button to the right of selected button
        if has_sel and #custom_buttons.buttons > 1 then
            r.ImGui_Text(ctx, "Place next to:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 200)
            if r.ImGui_BeginCombo(ctx, "##copy_position_from_button", "Select button...") then
                for i, btn in ipairs(custom_buttons.buttons) do
                    if i ~= custom_buttons.current_edit then
                        local display_name = btn.name or ("Button " .. i)
                        if btn.group and btn.group ~= "" then
                            display_name = display_name .. " [" .. btn.group .. "]"
                        end
                        -- Show position info
                        local pos_info = string.format(" (x:%d, y:%d)", btn.position_px or 0, btn.position_y_px or 0)
                        if r.ImGui_Selectable(ctx, display_name .. pos_info .. "##pos_from_" .. i) then
                            -- Place current button to the right of selected button
                            local current_button = custom_buttons.buttons[custom_buttons.current_edit]
                            local source_x = btn.position_px or 0
                            local source_width = btn.width or 60
                            current_button.position_px = source_x + source_width + new_button_spacing
                            current_button.position_y_px = btn.position_y_px
                            current_button.position_y = btn.position_y
                            -- Update fractional position
                            if canvas_width and canvas_width > 0 then
                                current_button.position = current_button.position_px / canvas_width
                            end
                            if canvas_height and canvas_height > 0 then
                                current_button.position_y = (current_button.position_y_px or 0) / canvas_height
                            end
                            custom_buttons.SaveCurrentButtons()
                            has_unsaved_changes = true
                            changed = true
                        end
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Place this button to the right of the selected button\nwith " .. new_button_spacing .. "px spacing")
            end
            
            -- Spacing slider on the same line
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Spacing:")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 80)
            local rv_spacing
            rv_spacing, new_button_spacing = r.ImGui_SliderInt(ctx, "##new_button_spacing", new_button_spacing, 0, 50, "%d px")
            if rv_spacing then
                SaveNewButtonSpacing()
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Spacing between buttons when using 'Place next to'\nor when creating new buttons")
            end
        end
        
        r.ImGui_Spacing(ctx)
    end  

        if opts and opts.render_global_offset then
            opts.render_global_offset(ctx)
        end
        
        if cb_section_states.actions_open then
            r.ImGui_Text(ctx, "Left Click:")

       
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 160)
            do
                local rv_name, new_name = r.ImGui_InputText(ctx, "##lcaName", button.left_click.name)
                if rv_name then button.left_click.name = new_name; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "ID")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            do
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "##lcaCmd", button.left_click.command or "")
                if rv_cmd then button.left_click.command = new_command; changed = true end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Paste##lcaPaste", 50, 0) then
                local clipboard = ""
                if r.CF_GetClipboard then
                    clipboard = r.CF_GetClipboard("")
                end
                
                if clipboard and clipboard ~= "" then
                    clipboard = clipboard:gsub("^%s+", ""):gsub("%s+$", "")
                    
                    local cmd_id = clipboard:match("^(_?%w+)$")
                    if cmd_id then
                        button.left_click.command = cmd_id
                        local cmd_id_no_underscore = cmd_id:gsub("^_", "")
                        local numeric_id = tonumber(cmd_id_no_underscore)
                        if numeric_id then
                            local retval, cmd_name = r.kbd_getTextFromCmd(numeric_id, 0)
                            if retval and cmd_name and cmd_name ~= "" then
                                button.left_click.name = cmd_name
                            end
                        end
                        changed = true
                    else
                        r.MB("Could not parse command ID from clipboard.\nClipboard content: " .. clipboard, "Paste ID", 0)
                    end
                else
                    r.MB("Clipboard is empty.\n\nCopy a command ID first.", "Paste ID", 0)
                end
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Paste command ID from clipboard\n(Copy ID in Action List first)")
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Type")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 80)
            do
                local rv_type, new_type = r.ImGui_Combo(ctx, "##lcaType", button.left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then button.left_click.type = new_type; changed = true end
            end

            if changed then custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end

            r.ImGui_Separator(ctx)
            
            r.ImGui_Text(ctx, "Alt+Left Click:")

       
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 160)
            do
                button.alt_left_click = button.alt_left_click or { name = "", command = "", type = 0 }
                local rv_name, new_name = r.ImGui_InputText(ctx, "##alcaName", button.alt_left_click.name)
                if rv_name then button.alt_left_click.name = new_name; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "ID")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            do
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "##alcaCmd", button.alt_left_click.command or "")
                if rv_cmd then button.alt_left_click.command = new_command; changed = true end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Paste##alcaPaste", 50, 0) then
                local clipboard = ""
                if r.CF_GetClipboard then
                    clipboard = r.CF_GetClipboard("")
                end
                
                if clipboard and clipboard ~= "" then
                    clipboard = clipboard:gsub("^%s+", ""):gsub("%s+$", "")
                    
                    local cmd_id = clipboard:match("^(_?%w+)$")
                    if cmd_id then
                        button.alt_left_click.command = cmd_id
                        local cmd_id_no_underscore = cmd_id:gsub("^_", "")
                        local numeric_id = tonumber(cmd_id_no_underscore)
                        if numeric_id then
                            local retval, cmd_name = r.kbd_getTextFromCmd(numeric_id, 0)
                            if retval and cmd_name and cmd_name ~= "" then
                                button.alt_left_click.name = cmd_name
                            end
                        end
                        changed = true
                    else
                        r.MB("Could not parse command ID from clipboard.\nClipboard content: " .. clipboard, "Paste ID", 0)
                    end
                else
                    r.MB("Clipboard is empty.\n\nCopy a command ID first.", "Paste ID", 0)
                end
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Paste command ID from clipboard\n(Copy ID in Action List first)")
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Type")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 80)
            do
                local rv_type, new_type = r.ImGui_Combo(ctx, "##alcaType", button.alt_left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then button.alt_left_click.type = new_type; changed = true end
            end

            if changed then custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end

            r.ImGui_Separator(ctx)
            
            r.ImGui_Text(ctx, "Shift+Left Click:")

       
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 160)
            do
                button.shift_left_click = button.shift_left_click or { name = "", command = "", type = 0 }
                local rv_name, new_name = r.ImGui_InputText(ctx, "##slcaName", button.shift_left_click.name)
                if rv_name then button.shift_left_click.name = new_name; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "ID")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            do
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "##slcaCmd", button.shift_left_click.command or "")
                if rv_cmd then button.shift_left_click.command = new_command; changed = true end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Paste##slcaPaste", 50, 0) then
                local clipboard = ""
                if r.CF_GetClipboard then
                    clipboard = r.CF_GetClipboard("")
                end
                
                if clipboard and clipboard ~= "" then
                    clipboard = clipboard:gsub("^%s+", ""):gsub("%s+$", "")
                    
                    local cmd_id = clipboard:match("^(_?%w+)$")
                    if cmd_id then
                        button.shift_left_click.command = cmd_id
                        local cmd_id_no_underscore = cmd_id:gsub("^_", "")
                        local numeric_id = tonumber(cmd_id_no_underscore)
                        if numeric_id then
                            local retval, cmd_name = r.kbd_getTextFromCmd(numeric_id, 0)
                            if retval and cmd_name and cmd_name ~= "" then
                                button.shift_left_click.name = cmd_name
                            end
                        end
                        changed = true
                    else
                        r.MB("Could not parse command ID from clipboard.\nClipboard content: " .. clipboard, "Paste ID", 0)
                    end
                else
                    r.MB("Clipboard is empty.\n\nCopy a command ID first.", "Paste ID", 0)
                end
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Paste command ID from clipboard\n(Copy ID in Action List first)")
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Type")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 80)
            do
                local rv_type, new_type = r.ImGui_Combo(ctx, "##slcaType", button.shift_left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then button.shift_left_click.type = new_type; changed = true end
            end

            if changed then custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end

            r.ImGui_Separator(ctx)
            
            r.ImGui_Text(ctx, "Ctrl+Left Click:")

       
            r.ImGui_Text(ctx, "Name")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 160)
            do
                button.ctrl_left_click = button.ctrl_left_click or { name = "", command = "", type = 0 }
                local rv_name, new_name = r.ImGui_InputText(ctx, "##clcaName", button.ctrl_left_click.name)
                if rv_name then button.ctrl_left_click.name = new_name; changed = true end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "ID")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 100)
            do
                local rv_cmd, new_command = r.ImGui_InputText(ctx, "##clcaCmd", button.ctrl_left_click.command or "")
                if rv_cmd then button.ctrl_left_click.command = new_command; changed = true end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Paste##clcaPaste", 50, 0) then
                local clipboard = ""
                if r.CF_GetClipboard then
                    clipboard = r.CF_GetClipboard("")
                end
                
                if clipboard and clipboard ~= "" then
                    clipboard = clipboard:gsub("^%s+", ""):gsub("%s+$", "")
                    
                    local cmd_id = clipboard:match("^(_?%w+)$")
                    if cmd_id then
                        button.ctrl_left_click.command = cmd_id
                        local cmd_id_no_underscore = cmd_id:gsub("^_", "")
                        local numeric_id = tonumber(cmd_id_no_underscore)
                        if numeric_id then
                            local retval, cmd_name = r.kbd_getTextFromCmd(numeric_id, 0)
                            if retval and cmd_name and cmd_name ~= "" then
                                button.ctrl_left_click.name = cmd_name
                            end
                        end
                        changed = true
                    else
                        r.MB("Could not parse command ID from clipboard.\nClipboard content: " .. clipboard, "Paste ID", 0)
                    end
                else
                    r.MB("Clipboard is empty.\n\nCopy a command ID first.", "Paste ID", 0)
                end
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Paste command ID from clipboard\n(Copy ID in Action List first)")
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "Type")
            r.ImGui_SameLine(ctx)
            r.ImGui_SetNextItemWidth(ctx, 80)
            do
                local rv_type, new_type = r.ImGui_Combo(ctx, "##clcaType", button.ctrl_left_click.type or 0, "Main\0MIDI Editor\0")
                if rv_type then button.ctrl_left_click.type = new_type; changed = true end
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

                
                if r.ImGui_BeginTable(ctx, "RCM_TABLE", 6,
                        r.ImGui_TableFlags_SizingStretchProp()
                        | r.ImGui_TableFlags_BordersInnerV()
                    ) then
                    r.ImGui_TableSetupColumn(ctx, "Drag", r.ImGui_TableColumnFlags_WidthFixed(), 30)
                    r.ImGui_TableSetupColumn(ctx, "Name", 0)
                    r.ImGui_TableSetupColumn(ctx, "Cmd", r.ImGui_TableColumnFlags_WidthFixed(), 100)
                    r.ImGui_TableSetupColumn(ctx, "Paste", r.ImGui_TableColumnFlags_WidthFixed(), 40)
                    r.ImGui_TableSetupColumn(ctx, "Type", r.ImGui_TableColumnFlags_WidthFixed(), 60)
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
                            if r.ImGui_SmallButton(ctx, "Paste##paste" .. idx) then
                                local clipboard = ""
                                if r.CF_GetClipboard then
                                    clipboard = r.CF_GetClipboard("")
                                end
                                
                                if clipboard and clipboard ~= "" then
                                    clipboard = clipboard:gsub("^%s+", ""):gsub("%s+$", "")
                                    local cmd_id = clipboard:match("^(_?%w+)$")
                                    if cmd_id then
                                        item.command = cmd_id
                                        custom_buttons.SaveCurrentButtons()
                                        has_unsaved_changes = true
                                    end
                                end
                            end
                            if r.ImGui_IsItemHovered(ctx) then
                                r.ImGui_SetTooltip(ctx, "Paste command ID")
                            end
                        end

                        r.ImGui_TableSetColumnIndex(ctx, 4)
                        if not is_submenu then
                            r.ImGui_SetNextItemWidth(ctx, -1)
                            local rv_type, new_type = r.ImGui_Combo(ctx, "##type", item.type or 0, "Main\0MIDI Editor\0")
                            if rv_type then item.type = new_type; custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end
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
    
    if cb_section_states.toggle_open then
        local rv_remember, new_remember = r.ImGui_Checkbox(ctx, "Remember Toggle States##rememberToggle", custom_buttons.remember_toggle_states)
        if rv_remember then
            custom_buttons.remember_toggle_states = new_remember
            if custom_buttons.current_preset then
                custom_buttons.SaveButtonPreset(custom_buttons.current_preset)
            end
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Remember the state of toggle buttons in this preset\n(Per-preset setting - each button preset can have its own behavior)")
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Group Visibility Control:")
        
        if not button.is_group_visibility_toggle then
            button.is_group_visibility_toggle = false
        end
        
        local rv_grp_vis, new_grp_vis = r.ImGui_Checkbox(ctx, "Use as Group Visibility Toggle##grpVisToggle", button.is_group_visibility_toggle)
        if rv_grp_vis then
            button.is_group_visibility_toggle = new_grp_vis
            changed = true
            if new_grp_vis then
                button.show_toggle_state = true
            end
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Use this button to show/hide groups of buttons")
        end
        
        if button.is_group_visibility_toggle then
            r.ImGui_Spacing(ctx)
            r.ImGui_Text(ctx, "Mode:")
            
            if button.toggle_mode == nil then
                -- Migrate old toggle_radio_mode to new system
                if button.toggle_radio_mode ~= nil then
                    button.toggle_mode = button.toggle_radio_mode and "radio" or "toggle"
                    button.toggle_radio_mode = nil
                else
                    button.toggle_mode = "radio"
                end
            end
            
            local mode_changed = false
            
            if r.ImGui_RadioButton(ctx, "Radio Mode##radioMode", button.toggle_mode == "radio") then
                button.toggle_mode = "radio"
                mode_changed = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Only one toggle active at a time (stays active)")
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Toggle Mode##toggleMode", button.toggle_mode == "toggle") then
                button.toggle_mode = "toggle"
                mode_changed = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Click to activate, click again to deactivate and show all")
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Cycle Mode##cycleMode", button.toggle_mode == "cycle") then
                button.toggle_mode = "cycle"
                if not button.cycle_views then
                    button.cycle_views = {{name = "View 1", visible_groups = {}}}
                end
                if not button.cycle_current_view then
                    button.cycle_current_view = 1
                end
                mode_changed = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Click to cycle through different views")
            end
            
            if mode_changed then
                changed = true
            end
            
            r.ImGui_Separator(ctx)
            
            if button.toggle_mode == "cycle" then
                -- Cycle Mode UI
                if not button.cycle_views then
                    button.cycle_views = {{name = "View 1", visible_groups = {}}}
                end
                if not button.cycle_current_view then
                    button.cycle_current_view = 1
                end
                
                r.ImGui_Text(ctx, "Cycle Views:")
                
                -- Get all groups
                local all_groups = {}
                for _, btn in ipairs(custom_buttons.buttons) do
                    if btn.group and btn.group ~= "" then
                        local found = false
                        for _, g in ipairs(all_groups) do
                            if g == btn.group then
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(all_groups, btn.group)
                        end
                    end
                end
                table.sort(all_groups)
                
                local view_to_remove = nil
                
                if not button.editing_view_name then
                    button.editing_view_name = {}
                end
                
                for view_idx, view in ipairs(button.cycle_views) do
                    r.ImGui_PushID(ctx, view_idx)
                    
                    -- Ensure view has a name
                    if not view.name or view.name == "" then
                        view.name = "View " .. view_idx
                    end
                    
                    -- Highlight current view
                    local header_color = (view_idx == button.cycle_current_view) and 0x4080FFFF or 0x404040FF
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), header_color)
                    
                    -- Use saved name for header to prevent collapse during editing
                    if not button.editing_view_name[view_idx] then
                        button.editing_view_name[view_idx] = view.name
                    end
                    
                    local header_label = button.editing_view_name[view_idx] .. "##viewheader"
                    local is_open = r.ImGui_CollapsingHeader(ctx, header_label, r.ImGui_TreeNodeFlags_DefaultOpen())
                    
                    r.ImGui_PopStyleColor(ctx)
                    
                    if is_open then
                        r.ImGui_Indent(ctx)
                        
                        r.ImGui_Text(ctx, "View Name:")
                        r.ImGui_SameLine(ctx)
                        r.ImGui_SetNextItemWidth(ctx, 150)
                        local rv_name, new_name = r.ImGui_InputText(ctx, "##viewName", view.name)
                        if rv_name then 
                            view.name = new_name
                            changed = true 
                        end
                        
                        -- Update header name when input loses focus
                        if not r.ImGui_IsItemActive(ctx) then
                            button.editing_view_name[view_idx] = view.name
                        end
                        
                        -- Move up/down buttons
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, "▲##up") and view_idx > 1 then
                            button.cycle_views[view_idx], button.cycle_views[view_idx - 1] = 
                                button.cycle_views[view_idx - 1], button.cycle_views[view_idx]
                            if button.cycle_current_view == view_idx then
                                button.cycle_current_view = view_idx - 1
                            elseif button.cycle_current_view == view_idx - 1 then
                                button.cycle_current_view = view_idx
                            end
                            changed = true
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Move view up in cycle order")
                        end
                        
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, "▼##down") and view_idx < #button.cycle_views then
                            button.cycle_views[view_idx], button.cycle_views[view_idx + 1] = 
                                button.cycle_views[view_idx + 1], button.cycle_views[view_idx]
                            if button.cycle_current_view == view_idx then
                                button.cycle_current_view = view_idx + 1
                            elseif button.cycle_current_view == view_idx + 1 then
                                button.cycle_current_view = view_idx
                            end
                            changed = true
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Move view down in cycle order")
                        end
                        
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, "✖##delete") and #button.cycle_views > 1 then
                            view_to_remove = view_idx
                        end
                        if r.ImGui_IsItemHovered(ctx) then
                            r.ImGui_SetTooltip(ctx, "Delete this view")
                        end
                        
                        r.ImGui_Spacing(ctx)
                        r.ImGui_Text(ctx, "Visible groups in this view:")
                        
                        if not view.visible_groups then
                            view.visible_groups = {}
                            for _, g in ipairs(all_groups) do
                                view.visible_groups[g] = true
                            end
                        end
                        
                        if #all_groups > 0 then
                            for _, group_name in ipairs(all_groups) do
                                if view.visible_groups[group_name] == nil then
                                    view.visible_groups[group_name] = true
                                end
                                
                                local rv_grp, new_grp = r.ImGui_Checkbox(ctx, group_name .. "##" .. view_idx, view.visible_groups[group_name])
                                if rv_grp then 
                                    view.visible_groups[group_name] = new_grp
                                    changed = true 
                                end
                            end
                        else
                            r.ImGui_TextDisabled(ctx, "No groups available")
                        end
                        
                        r.ImGui_Unindent(ctx)
                    end
                    
                    r.ImGui_PopID(ctx)
                end
                
                if view_to_remove then
                    table.remove(button.cycle_views, view_to_remove)
                    if button.cycle_current_view >= view_to_remove then
                        button.cycle_current_view = math.max(1, button.cycle_current_view - 1)
                    end
                    changed = true
                end
                
                r.ImGui_Spacing(ctx)
                if r.ImGui_Button(ctx, "+ Add View") then
                    table.insert(button.cycle_views, {
                        name = "View " .. (#button.cycle_views + 1),
                        visible_groups = {}
                    })
                    changed = true
                end
                
            else
                -- Radio/Toggle Mode UI
                r.ImGui_Text(ctx, "Visible groups when active:")
                r.ImGui_Separator(ctx)
                
                local all_groups = {}
                for _, btn in ipairs(custom_buttons.buttons) do
                    if btn.group and btn.group ~= "" then
                        local found = false
                        for _, g in ipairs(all_groups) do
                            if g == btn.group then
                                found = true
                                break
                            end
                        end
                        if not found then
                            table.insert(all_groups, btn.group)
                        end
                    end
                end
                table.sort(all_groups)
                
                if not button.visible_groups then
                    button.visible_groups = {}
                    for _, g in ipairs(all_groups) do
                        button.visible_groups[g] = true
                    end
                end
                
                if #all_groups > 0 then
                    for _, group_name in ipairs(all_groups) do
                        if button.visible_groups[group_name] == nil then
                            button.visible_groups[group_name] = true
                        end
                        
                        rv, button.visible_groups[group_name] = r.ImGui_Checkbox(ctx, group_name, button.visible_groups[group_name])
                        if rv then changed = true end
                    end
                else
                    r.ImGui_TextDisabled(ctx, "No groups available")
                end
            end
            
            r.ImGui_Separator(ctx)
            
            r.ImGui_Text(ctx, "Toggle State Visualization:")
            
            if not button.show_toggle_state then
                button.show_toggle_state = false
            end
            if not button.toggle_on_color then
                button.toggle_on_color = 0x00FF00FF
            end
            
            local rv_toggle, new_toggle_state = r.ImGui_Checkbox(ctx, "Show Toggle State##toggleVis", button.show_toggle_state)
            if rv_toggle then 
                button.show_toggle_state = new_toggle_state
                changed = true
            end
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Visualize the ON/OFF state (Shows if group is visible/hidden)")
            end
            
            if button.show_toggle_state then
                local color_flags = r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_AlphaBar()
                
                r.ImGui_Text(ctx, "Toggle ON Color:")
                r.ImGui_SameLine(ctx)
                rv, button.toggle_on_color = r.ImGui_ColorEdit4(ctx, "##toggleOnColor", button.toggle_on_color, color_flags)
                if rv then changed = true end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Color when the toggle is active (group visible)")
                end
                
                r.ImGui_Text(ctx, "Toggle OFF Color:")
                r.ImGui_SameLine(ctx)
                if button.toggle_off_color == nil then
                    button.toggle_off_color = button.color or 0x333333FF
                end
                rv, button.toggle_off_color = r.ImGui_ColorEdit4(ctx, "##toggleOffColor", button.toggle_off_color, color_flags)
                if rv then changed = true end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Color when the toggle is inactive (group hidden)")
                end
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_SmallButton(ctx, "Reset##toggleOffReset") then
                    button.toggle_off_color = nil
                    changed = true
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_SetTooltip(ctx, "Reset to use normal button colors when OFF")
                end
            end
            
            if changed then custom_buttons.SaveCurrentButtons(); has_unsaved_changes = true end
            
            r.ImGui_Separator(ctx)
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
        local icon_path
        if button.icon_name:match("^/") or button.icon_name:match("^[A-Za-z]:") then
            icon_path = button.icon_name
        else
            local resource_path = r.GetResourcePath()
            icon_path = resource_path .. "/Data/toolbar_icons/" .. button.icon_name
        end
        
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

function ButtonEditor.HandleIconBrowser(ctx, custom_buttons, settings)
    if not IconBrowser or not IconBrowser.show_window then
        return
    end
    
    local ok, selected_icon = pcall(IconBrowser.Show, ctx, settings)
    
    if not ok then
        reaper.ShowConsoleMsg("IconBrowser error: " .. tostring(selected_icon) .. "\n")
        IconBrowser.show_window = false
        return
    end
    
    if selected_icon and active_icon_button then
        local ButtonRenderer = require('button_renderer')
        
        if IconBrowser.browse_mode == "images" and IconBrowser.selected_image_path then
            active_icon_button.use_image = true
            active_icon_button.use_icon = false
            active_icon_button.image_path = IconBrowser.selected_image_path
            active_icon_button.image = nil
            if active_icon_button.image_path and ButtonRenderer.image_cache[active_icon_button.image_path] then
                ButtonRenderer.image_cache[active_icon_button.image_path] = nil
            end
        else
            active_icon_button.use_icon = true
            active_icon_button.use_image = false
            if active_icon_button.icon_name and ButtonRenderer.image_cache[active_icon_button.icon_name] then
                ButtonRenderer.image_cache[active_icon_button.icon_name] = nil
            end
            active_icon_button.icon_name = selected_icon
            active_icon_button.icon = nil
        end
        
        custom_buttons.SaveCurrentButtons()
        has_unsaved_changes = true
        
        IconBrowser.selected_icon = nil
        IconBrowser.selected_image_path = nil
    end
end

-- Handle Style Settings Window
function ButtonEditor.HandleStyleSettingsWindow(ctx)
    ShowStyleSettingsWindow(ctx)
end

ButtonEditor.cb_section_states = cb_section_states

return ButtonEditor

