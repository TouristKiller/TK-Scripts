local r = reaper
local script_path = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
local json = require('json')
local button_presets_path = script_path .. "tk_transport_buttons/presets/"
local current_buttons_path = script_path .. "tk_transport_buttons/current_buttons.json"

local CustomButtons = {
    buttons = {},
    current_edit = nil,
    show_editor = false,
    command_picker_target = nil,
    command_picker_type = nil,
    last_command = nil,
    icon = nil,  
    use_icon = false,
    current_preset = nil
}

function CustomButtons.CreateNewButton()
    return {
        name = "New Button",
        position = 0.5,
        position_y = 0.15,
        width = 60,
        visible = true,
    group = "", 
    show_border = true, 
        color = 0x333333FF,
        hover_color = 0x444444FF,
        active_color = 0x555555FF,
        text_color = 0xFFFFFFFF,
        -- Toggle state visualization
        show_toggle_state = false,
        toggle_on_color = 0x00FF00FF,  -- Green when toggle is ON
        toggle_off_color = nil,  -- nil means use default color
        -- Group visibility control
        is_group_visibility_toggle = false,
        target_group = nil,  -- Name of the group to control
        left_click = {
            command = nil,
            name = "No Action"
        },
        right_menu = {
            items = {}
        }
    }
end

function CustomButtons.PrepareForSave()
    local save_data = {}
    for i, button in ipairs(CustomButtons.buttons) do
        local button_copy = {}
        for k, v in pairs(button) do
            if k ~= "icon" and k ~= "font" then  
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

function CustomButtons.SaveButtonPreset(name)
    r.RecursiveCreateDirectory(button_presets_path, 0)
    
    local save_data = CustomButtons.PrepareForSave()
    local file = io.open(button_presets_path .. name .. '.json', 'w')
    if file then
        file:write(json.encode(save_data))
        file:close()
        CustomButtons.current_preset = name
        r.SetExtState("TK_TRANSPORT", "last_button_preset", name, true)
    end
end

function CustomButtons.LoadButtonPreset(name)
    local file = io.open(button_presets_path .. name .. '.json', 'r')
    if file then
        local content = file:read('*all')
        file:close()
        local success, result = pcall(json.decode, content)
        if success then
            CustomButtons.buttons = result
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
    else
        CustomButtons.LoadCurrentButtons()
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
    
    CustomButtons.SaveCurrentButtons()
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

CustomButtons.LoadLastUsedPreset()

return CustomButtons


