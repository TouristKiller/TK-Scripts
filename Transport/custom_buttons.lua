local r = reaper
local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
local json = require('json')
local instance_suffix = _G.TK_TRANSPORT_INSTANCE_NAME or ""
local button_presets_path = script_path .. "tk_transport_buttons/presets/"

local current_buttons_path = script_path .. "tk_transport_buttons/current_buttons" .. (instance_suffix ~= "" and "_" .. instance_suffix or "") .. ".json"

local CustomButtons = {
    buttons = {},
    current_edit = nil,
    show_editor = false,
    command_picker_target = nil,
    command_picker_type = nil,
    last_command = nil,
    icon = nil,  
    use_icon = false,
    current_preset = nil,
    remember_toggle_states = false  -- Per-preset setting for toggle state memory
}

function CustomButtons.CreateNewButton(options)
    options = options or {}
    
    local new_button = {
        name = "New Button",
        position = 0.5,
        position_y = 0.15,
        position_px = nil,
        position_y_px = nil,
        width = 60,
        visible = true,
        group = "", 
        show_border = true, 
        color = 0x333333FF,
        hover_color = 0x444444FF,
        active_color = 0x555555FF,
        text_color = 0xFFFFFFFF,
        show_toggle_state = false,
        toggle_on_color = 0x00FF00FF,
        toggle_off_color = nil,
        is_group_visibility_toggle = false,
        target_group = nil,
        left_click = {
            command = nil,
            name = "No Action"
        },
        right_menu = {
            items = {}
        }
    }
    
    if #CustomButtons.buttons > 0 then
        local last_button = CustomButtons.buttons[#CustomButtons.buttons]
        
        if options.copy_style then
            new_button.width = last_button.width or 60
            new_button.show_border = last_button.show_border
            new_button.color = last_button.color or 0x333333FF
            new_button.hover_color = last_button.hover_color or 0x444444FF
            new_button.active_color = last_button.active_color or 0x555555FF
            new_button.text_color = last_button.text_color or 0xFFFFFFFF
            new_button.rounding = last_button.rounding
            new_button.border_thickness = last_button.border_thickness
            new_button.border_color = last_button.border_color
            new_button.font_size = last_button.font_size
            new_button.font_name = last_button.font_name
            new_button.font_style = last_button.font_style
            new_button.use_icon = last_button.use_icon
            new_button.icon_name = last_button.icon_name
            new_button.show_text_with_icon = last_button.show_text_with_icon
        end
        
        if options.place_next_to then
            local spacing = 5
            local spacing_str = r.GetExtState("TK_TRANSPORT_BUTTON_EDITOR", "new_button_spacing")
            if spacing_str and spacing_str ~= "" then
                local num = tonumber(spacing_str)
                if num and num >= 0 and num <= 50 then
                    spacing = num
                end
            end
            
            local last_x = last_button.position_px or 0
            local last_width = last_button.width or 60
            new_button.position_px = last_x + last_width + spacing
            new_button.position_y_px = last_button.position_y_px
            new_button.position_y = last_button.position_y or 0.15
        end
    end
    
    return new_button
end

function CustomButtons.PrepareForSave()
    local save_data = {}
    for i, button in ipairs(CustomButtons.buttons) do
        local button_copy = {}
        for k, v in pairs(button) do
            if k ~= "icon" and k ~= "font" and k ~= "image" then  
                button_copy[k] = v
            end
        end
        save_data[i] = button_copy
    end
    return save_data
end

function CustomButtons.SaveCurrentButtons()
    r.RecursiveCreateDirectory(script_path .. "tk_transport_buttons", 0)
    local save_data = CustomButtons.PrepareForSave()
    local file = io.open(current_buttons_path, 'w')
    if file then
        file:write(json.encode(save_data))
        file:close()
    end
end

function CustomButtons.LoadCurrentButtons()
    local file = io.open(current_buttons_path, 'r')
    if file then
        local content = file:read('*all')
        file:close()
        local success, result = pcall(json.decode, content)
        if success then
            CustomButtons.buttons = result
        else
            reaper.ShowMessageBox("Error loading custom buttons: " .. tostring(result) .. "\n\nResetting to default buttons.", "Custom Buttons Error", 0)
            CustomButtons.buttons = {}
        end
    end
end

function CustomButtons.ResetToggleStatesIfNeeded(settings)
    -- Check if we should remember states (use per-preset setting)
    local should_remember = CustomButtons.remember_toggle_states
    
    if not should_remember then
        -- Reset all toggle buttons to OFF state
        for _, button in ipairs(CustomButtons.buttons) do
            if button.is_group_visibility_toggle then
                button.toggle_state = false
                if button.cycle_current_view then
                    button.cycle_current_view = 1
                end
            end
        end
    end
    
    -- Always ensure at least one radio mode toggle is active (regardless of remember setting)
    -- First check if any radio toggle is already active
    local has_active_radio = false
    for _, button in ipairs(CustomButtons.buttons) do
        if button.is_group_visibility_toggle and button.toggle_mode == "radio" and button.toggle_state then
            has_active_radio = true
            break
        end
    end
    
    -- If no radio toggle is active, activate the first one
    if not has_active_radio then
        for _, button in ipairs(CustomButtons.buttons) do
            if button.is_group_visibility_toggle and button.toggle_mode == "radio" then
                button.toggle_state = true
                break
            end
        end
    end
    
    CustomButtons.SaveCurrentButtons()
end

function CustomButtons.SaveButtonPreset(name)
    r.RecursiveCreateDirectory(button_presets_path, 0)
    
    local save_data = {
        buttons = CustomButtons.PrepareForSave(),
        settings = {
            remember_toggle_states = CustomButtons.remember_toggle_states
        }
    }
    
    local file = io.open(button_presets_path .. name .. '.json', 'w')
    if file then
        file:write(json.encode(save_data))
        file:close()
        CustomButtons.current_preset = name
        r.SetExtState("TK_TRANSPORT", "last_button_preset", name, true)
    end
end

function CustomButtons.LoadButtonPreset(name)
    local preset_file_path = button_presets_path .. name .. '.json'
    local file = io.open(preset_file_path, 'r')
    if file then
        local content = file:read('*all')
        file:close()
        local success, result = pcall(json.decode, content)
        if success then
            -- First, load current buttons to get the latest toggle states
            local current_toggle_states = {}
            local current_file = io.open(current_buttons_path, 'r')
            if current_file then
                local current_content = current_file:read('*all')
                current_file:close()
                local current_success, current_buttons = pcall(json.decode, current_content)
                if current_success and current_buttons then
                    -- Extract toggle states from current buttons
                    for _, button in ipairs(current_buttons) do
                        if button.is_group_visibility_toggle and button.name then
                            current_toggle_states[button.name] = {
                                toggle_state = button.toggle_state,
                                cycle_current_view = button.cycle_current_view
                            }
                        end
                    end
                end
            end
            
            -- Handle old format (array) and new format (table with buttons + settings)
            if result.buttons then
                -- New format
                CustomButtons.buttons = result.buttons
                if result.settings and result.settings.remember_toggle_states ~= nil then
                    CustomButtons.remember_toggle_states = result.settings.remember_toggle_states
                else
                    CustomButtons.remember_toggle_states = false
                end
            else
                -- Old format (just array of buttons)
                CustomButtons.buttons = result
                CustomButtons.remember_toggle_states = false
            end
            
            -- Restore toggle states if remember is enabled
            if CustomButtons.remember_toggle_states then
                for _, button in ipairs(CustomButtons.buttons) do
                    if button.is_group_visibility_toggle and button.name and current_toggle_states[button.name] then
                        button.toggle_state = current_toggle_states[button.name].toggle_state
                        button.cycle_current_view = current_toggle_states[button.name].cycle_current_view
                    end
                end
            end
            
            CustomButtons.current_preset = name
            CustomButtons.SaveCurrentButtons()
            r.SetExtState("TK_TRANSPORT", "last_button_preset", name, true)
        else
            reaper.ShowMessageBox("Error loading button preset '" .. name .. "': " .. tostring(result) .. "\n\nPreset may be corrupted.", "Preset Load Error", 0)
        end
    end
end

function CustomButtons.GetButtonPresets()
    local presets = {}
    local seen = {} 
    local idx = 0
    r.RecursiveCreateDirectory(button_presets_path, 0)
    local filename = r.EnumerateFiles(button_presets_path, idx)
    
    while filename do
        if filename:match('%.json$') then
            local preset_name = filename:gsub('%.json$', '')
            if not seen[preset_name] then
                presets[#presets + 1] = preset_name
                seen[preset_name] = true
            end
        end
        idx = idx + 1
        filename = r.EnumerateFiles(button_presets_path, idx)
    end
    return presets
end

function CustomButtons.LoadLastUsedPreset()
    local last_preset = r.GetExtState("TK_TRANSPORT", "last_button_preset")
    if last_preset ~= "" then
        CustomButtons.LoadButtonPreset(last_preset)
    end
end

function CustomButtons.DeleteButtonPreset(name)
    if name then
        os.remove(button_presets_path .. name .. ".json")
        if CustomButtons.current_preset == name then
            CustomButtons.current_preset = nil
            r.DeleteExtState("TK_TRANSPORT", "last_button_preset", true)
            CustomButtons.LoadCurrentButtons()
        end
    end
end

function CustomButtons.RegisterCommandToLoadPreset(preset_name)
    local safe_name = preset_name:gsub("[^%w]", "_")
    local command_id = "TK_TRANSPORT_" .. safe_name
    local section_name = "Custom: Scripts"
    local command_name = "TK_TRANSPORT_" .. preset_name
    
    local sep = package.config:sub(1,1) -- Returns "/" on Unix/Mac, "\" on Windows
    
    local preset_loader_dir = script_path .. "preset_loaders"
    local preset_script_path = preset_loader_dir .. sep .. "TK_TRANSPORT_" .. safe_name .. ".lua"
    r.RecursiveCreateDirectory(preset_loader_dir, 0)
    
    local script_content = [[
local r = reaper
local script_path = debug.getinfo(1, 'S').source:match([=[^@?(.*[\/])[^\/]-$]=])
local sep = package.config:sub(1,1)  -- OS path separator
package.path = script_path .. ".." .. sep .. "?.lua;" .. package.path
local CustomButtons = require('custom_buttons')
CustomButtons.LoadLastUsedPreset()
CustomButtons.LoadButtonPreset("]] .. preset_name .. [[")
CustomButtons.SaveCurrentButtons()
r.SetExtState("TK_TRANSPORT", "last_button_preset", "]] .. preset_name .. [[", true)
r.UpdateArrange()
r.SetExtState("TK_TRANSPORT", "refresh_buttons", "1", false)
]]
    
    local file = io.open(preset_script_path, "w")
    if file then
        file:write(script_content)
        file:close()
        
        local result = r.AddRemoveReaScript(true, 0, preset_script_path, true)
        r.RefreshToolbar2(0, 0)
        return result and 1 or 0
    end
    
    return 0
end


function CustomButtons.CheckForCommandPick()
    local retval, lastfx = r.GetLastTouchedFX()
    
    if lastfx ~= CustomButtons.last_command then
        CustomButtons.last_command = lastfx
        
        if CustomButtons.command_picker_target then
            local button = CustomButtons.buttons[CustomButtons.current_edit]
            local command_id = lastfx
            
            if command_id > 0 then
                if CustomButtons.command_picker_type == "left_click" then
                    button.left_click.command = command_id
                    button.left_click.name = r.GetActionName(0, command_id)
                elseif CustomButtons.command_picker_type == "menu_item" then
                    local item = button.right_menu.items[CustomButtons.command_picker_target]
                    item.command = command_id
                    item.name = r.GetActionName(0, command_id)
                end
                
                CustomButtons.command_picker_target = nil
                CustomButtons.command_picker_type = nil
                CustomButtons.SaveCurrentButtons()
            end
        end
    end
end

-- Get the toggle state of a command
function CustomButtons.GetToggleState(button)
    if not button or not button.show_toggle_state then
        return nil
    end
    
    -- Check if this is a group visibility toggle button
    if button.is_group_visibility_toggle and button.target_group then
        return CustomButtons.GetGroupVisibilityState(button.target_group)
    end
    
    local command_id = button.left_click and button.left_click.command
    if not command_id then
        return nil
    end
    
    -- Convert string command IDs to numbers if needed
    if type(command_id) == "string" then
        command_id = r.NamedCommandLookup(command_id)
    end
    
    if not command_id or command_id == 0 then
        return nil
    end
    
    -- Check if it's a MIDI editor command
    local cmd_type = button.left_click.type
    if cmd_type == 1 then
        -- MIDI Editor command
        local editor = r.MIDIEditor_GetActive()
        if editor then
            return r.GetToggleCommandStateEx(32060, command_id)
        end
        return nil
    else
        -- Main action
        return r.GetToggleCommandState(command_id)
    end
end

-- Get the visibility state of a group (1 = visible, 0 = hidden)
function CustomButtons.GetGroupVisibilityState(group_name)
    if not group_name or group_name == "" then
        return 0
    end
    
    local any_visible = false
    for _, btn in ipairs(CustomButtons.buttons) do
        if btn.group == group_name and btn.visible then
            any_visible = true
            break
        end
    end
    
    return any_visible and 1 or 0
end

-- Save group visibility state to ExtState
function CustomButtons.SaveGroupVisibilityState(group_name, is_visible)
    if not group_name or group_name == "" then return end
    local state_key = "group_visibility_" .. group_name
    r.SetExtState("TK_TRANSPORT_GROUPS", state_key, is_visible and "1" or "0", true)
end

-- Load group visibility state from ExtState
function CustomButtons.LoadGroupVisibilityState(group_name)
    if not group_name or group_name == "" then return nil end
    local state_key = "group_visibility_" .. group_name
    local state = r.GetExtState("TK_TRANSPORT_GROUPS", state_key)
    if state == "" then return nil end
    return state == "1"
end

-- Toggle the visibility of a group
function CustomButtons.ToggleGroupVisibility(group_name)
    if not group_name or group_name == "" then
        return
    end
    
    -- Check current state
    local any_visible = false
    for _, btn in ipairs(CustomButtons.buttons) do
        if btn.group == group_name and btn.visible then
            any_visible = true
            break
        end
    end
    
    -- Toggle to opposite state
    local new_state = not any_visible
    
    for _, btn in ipairs(CustomButtons.buttons) do
        if btn.group == group_name then
            btn.visible = new_state
        end
    end
    
    -- Save the visibility state
    CustomButtons.SaveGroupVisibilityState(group_name, new_state)
    CustomButtons.SaveCurrentButtons()
end

-- Restore group visibility states from ExtState
function CustomButtons.RestoreGroupVisibilityStates()
    -- Early exit if no buttons loaded yet
    if not CustomButtons.buttons or #CustomButtons.buttons == 0 then
        return
    end
    
    local groups = CustomButtons.GetAllGroups()
    
    for _, group_name in ipairs(groups) do
        local saved_state = CustomButtons.LoadGroupVisibilityState(group_name)
        
        -- Only apply if there's a saved state
        if saved_state ~= nil then
            for _, btn in ipairs(CustomButtons.buttons) do
                if btn.group == group_name then
                    btn.visible = saved_state
                end
            end
        end
    end
    
    -- Save the restored state to current buttons
    if #CustomButtons.buttons > 0 then
        CustomButtons.SaveCurrentButtons()
    end
end

-- Get all unique group names
function CustomButtons.GetAllGroups()
    local groups = {}
    local seen = {}
    
    for _, btn in ipairs(CustomButtons.buttons) do
        if btn.group and btn.group ~= "" and not seen[btn.group] then
            table.insert(groups, btn.group)
            seen[btn.group] = true
        end
    end
    
    table.sort(groups)
    return groups
end

return CustomButtons


