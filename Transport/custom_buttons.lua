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
    group = "", -- optional group name for batch editing
    show_border = true, -- new: individual border toggle
        color = 0x333333FF,
        hover_color = 0x444444FF,
        active_color = 0x555555FF,
        text_color = 0xFFFFFFFF,
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
            if k ~= "icon" then  
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
        CustomButtons.buttons = json.decode(content)
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
        CustomButtons.buttons = json.decode(content)
        CustomButtons.current_preset = name
        CustomButtons.SaveCurrentButtons()
        r.SetExtState("TK_TRANSPORT", "last_button_preset", name, true)
    end
end

function CustomButtons.GetButtonPresets()
    local presets = {}
    local idx = 0
    r.RecursiveCreateDirectory(button_presets_path, 0)
    local filename = r.EnumerateFiles(button_presets_path, idx)
    
    while filename do
        if filename:match('%.json$') then
            presets[#presets + 1] = filename:gsub('%.json$', '')
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
    -- Create cross-platform safe filename
    local safe_name = preset_name:gsub("[^%w]", "_")
    local command_id = "TK_TRANSPORT_" .. safe_name
    local section_name = "Custom: Scripts"
    local command_name = "TK_TRANSPORT_" .. preset_name
    
    -- Get the OS path separator
    local sep = package.config:sub(1,1) -- Returns "/" on Unix/Mac, "\" on Windows
    
    -- Create directory and path safely
    local preset_loader_dir = script_path .. "preset_loaders"
    local preset_script_path = preset_loader_dir .. sep .. "TK_TRANSPORT_" .. safe_name .. ".lua"
    r.RecursiveCreateDirectory(preset_loader_dir, 0)
    
    -- Create script content with platform-independent path handling
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
    
    -- Write the script file
    local file = io.open(preset_script_path, "w")
    if file then
        file:write(script_content)
        file:close()
        
        -- Register as REAPER action
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

CustomButtons.LoadLastUsedPreset()

return CustomButtons


