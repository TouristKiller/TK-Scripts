-- @description TK_TRANSPORT
-- @author TouristKiller
-- @version 0.2.8
-- @changelog 
--[[
+ Update to ReaImGui
+ Right-click context menu items can be swapped
]]--


local r                 = reaper
local ctx               = r.ImGui_CreateContext('Transport Control')


local script_path       = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator      = package.config:sub(1, 1)
package.path            = script_path .. "?.lua;"

local json              = require("json")
local font_path         = script_path .. "Icons-Regular.otf"
local preset_path       = script_path .. "tk_transport_presets" .. os_separator
local preset_name       = ""


local CustomButtons     = require('custom_buttons')
local ButtonEditor      = require('button_editor')
local ButtonRenderer    = require('button_renderer')
local WidgetManager     = require('widget_manager')


local PLAY_COMMAND      = 1007
local STOP_COMMAND      = 1016
local PAUSE_COMMAND     = 1008
local RECORD_COMMAND    = 1013
local REPEAT_COMMAND    = 1068
local GOTO_START        = 40042
local GOTO_END          = 40043

-- TapTempo state variables
local tap_times = {}
local tap_average_times = {}
local tap_clock = 0
local tap_average_current = 0
local tap_clicks = 0
local tap_z = 0
local tap_w = 0
local last_tap_time = 0

local section_states = {
    transport_open = false,
    cursor_open = false,
    metronome_open = false,
    timesel_open = false,
    tempo_open = false,
    playrate_open = false,
    env_open = false,
    taptempo_open = false,
    settings_open = false
}

local transport_custom_images = {
    play = nil,
    stop = nil,
    pause = nil,
    record = nil,
    loop = nil,
    rewind = nil,
    forward = nil
}

local AUTOMATION_MODES  = {
    {name               = "No override", command = 40876},
    {name               = "Bypass", command = 40908}, 
    {name               = "Latch", command = 40881},
    {name               = "Latch Preview", command = 42022},
    {name               = "Read", command = 40879},
    {name               = "Touch", command = 40880},
    {name               = "Trim/Read", command = 40878},
    {name               = "Write", command = 40882}
}

local show_settings     = false 
local window_flags      = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoScrollbar()
local settings_flags    = window_flags | r.ImGui_WindowFlags_NoResize() 

local text_sizes        = {10, 12, 14, 16, 18}
local fonts             = {
    "Arial", "Helvetica", "Verdana", "Tahoma", "Times New Roman",
    "Georgia", "Courier New", "Trebuchet MS", "Impact", "Roboto",
    "Open Sans", "Ubuntu", "Segoe UI", "Noto Sans", "Liberation Sans",
    "DejaVu Sans"
}

local default_settings  = {

    -- Style settings
    window_rounding     = 12.0,
    frame_rounding      = 6.0,
    popup_rounding      = 6.0,
    grab_rounding       = 12.0,
    grab_min_size       = 8.0,
    button_border_size  = 1.0,
    border_size         = 1.0,
    current_font        = "Arial",
    font_size           = 12,
    center_transport    = true,
    current_preset_name = "",

    -- x offset
    transport_x         = 0.41,      
    timesel_x           = 0.0,        
    tempo_x             = 0.69,         
    playrate_x          = 0.93,      
    env_x               = 0.19,           
    settings_x          = 0.99,
    cursorpos_x         = 0.25,
    visualmtr_x         = 0.32,
    custom_buttons_x_offset = 0.0,
    -- y offset
    transport_y         = 0.15,      
    timesel_y           = 0.15,        
    tempo_y             = 0.15,         
    playrate_y          = 0.15,      
    env_y               = 0.15,           
    settings_y          = 0.15,    
    cursorpos_y         = 0.15,
    visualmtr_y         = 0.15,
    custom_buttons_y_offset = 0.0,

    -- Color settings
    background          = 0x000000FF,
    button_normal       = 0x333333FF,
    play_active         = 0x00FF00FF,    
    record_active       = 0xFF0000FF,  
    pause_active        = 0xFFFF00FF,  
    loop_active         = 0x0088FFFF,    
    text_normal         = 0xFFFFFFFF,
    frame_bg            = 0x333333FF,
    frame_bg_hovered    = 0x444444FF,
    frame_bg_active     = 0x555555FF,
    slider_grab         = 0x999999FF,
    slider_grab_active  = 0xAAAAAAFF,
    check_mark          = 0x999999FF,
    button_hovered      = 0x444444FF,
    button_active       = 0x555555FF,
    border              = 0x444444FF,
    transport_normal    = 0x333333FF,
    metronome_active    = 0x00FF00FF,
    metronome_enabled   = 0x00FF00FF,
    timesel_color       = 0x333333FF,
    timesel_border      = true,
    timesel_invisible   = false,

    -- Visibility settings
    use_graphic_buttons = false,
    show_timesel        = true,
    show_transport      = true,
    show_tempo          = true,
    show_playrate       = true,
    show_vismetronome   = true,
    show_time_selection = true,
    show_beats_selection = true,
    show_settings_button = true,  
    show_env_button      = true,

    -- Custom Transport Button settings
    use_custom_play_image       = false,
    custom_play_image_path      = "",
    custom_play_image_size      = 1.0,
    use_custom_stop_image       = false,
    custom_stop_image_path      = "",
    custom_stop_image_size      = 1.0,
    use_custom_pause_image      = false, 
    custom_pause_image_path     = "",
    custom_pause_image_size     = 1.0,
    use_custom_record_image     = false,
    custom_record_image_path    = "",
    custom_record_image_size    = 1.0,
    use_custom_loop_image       = false,
    custom_loop_image_path      = "",
    custom_loop_image_size      = 1.0,
    use_custom_rewind_image     = false,
    custom_rewind_image_path    = "",
    custom_rewind_image_size    = 1.0,
    use_custom_forward_image    = false,
    custom_forward_image_path   = "",
    custom_image_size           = 1.0,
    locked_button_folder_path = "",
    use_locked_button_folder = false,

        -- TapTempo settings
    show_taptempo = true,
    taptempo_x = 0.80,
    taptempo_y = 0.15,
    tap_button_text = "TAP",
    tap_button_width = 50,
    tap_button_height = 30,
    tap_input_limit = 16,
    set_tempo_on_tap = true,
    show_accuracy_indicator = true,
    high_accuracy_color = 0x00FF00FF,
    medium_accuracy_color = 0xFFFF00FF,
    low_accuracy_color = 0xFF0000FF

}

local settings          = {}

for k, v in pairs(default_settings) do
    settings[k] = v
end

local font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
local font_icons = r.ImGui_CreateFontFromFile(script_path .. 'Icons-Regular.otf', 0)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_icons)
local font_needs_update = false
function UpdateFont()
    font_needs_update = true
end

function UpdateCustomImages()
    -- Play knop
    if settings.use_custom_play_image and settings.custom_play_image_path ~= "" then
        if r.file_exists(settings.custom_play_image_path) then
            transport_custom_images.play = r.ImGui_CreateImage(settings.custom_play_image_path)
        else
            settings.custom_play_image_path = ""
            transport_custom_images.play = nil
        end
    end
    
    -- Stop knop
    if settings.use_custom_stop_image and settings.custom_stop_image_path ~= "" then
        if r.file_exists(settings.custom_stop_image_path) then
            transport_custom_images.stop = r.ImGui_CreateImage(settings.custom_stop_image_path)
        else
            settings.custom_stop_image_path = ""
            transport_custom_images.stop = nil
        end
    end
    
    -- Pause knop
    if settings.use_custom_pause_image and settings.custom_pause_image_path ~= "" then
        if r.file_exists(settings.custom_pause_image_path) then
            transport_custom_images.pause = r.ImGui_CreateImage(settings.custom_pause_image_path)
        else
            settings.custom_pause_image_path = ""
            transport_custom_images.pause = nil
        end
    end
    
    -- Record knop
    if settings.use_custom_record_image and settings.custom_record_image_path ~= "" then
        if r.file_exists(settings.custom_record_image_path) then
            transport_custom_images.record = r.ImGui_CreateImage(settings.custom_record_image_path)
        else
            settings.custom_record_image_path = ""
            transport_custom_images.record = nil
        end
    end
    
    -- Loop knop (let op: gebruik loop_image, niet repeat_image)
    if settings.use_custom_loop_image and settings.custom_loop_image_path ~= "" then
        if r.file_exists(settings.custom_loop_image_path) then
            transport_custom_images.loop = r.ImGui_CreateImage(settings.custom_loop_image_path)
        else
            settings.custom_loop_image_path = ""
            transport_custom_images.loop = nil
        end
    end
    
    -- Rewind knop
    if settings.use_custom_rewind_image and settings.custom_rewind_image_path ~= "" then
        if r.file_exists(settings.custom_rewind_image_path) then
            transport_custom_images.rewind = r.ImGui_CreateImage(settings.custom_rewind_image_path)
        else
            settings.custom_rewind_image_path = ""
            transport_custom_images.rewind = nil
        end
    end
    
    -- Forward knop
    if settings.use_custom_forward_image and settings.custom_forward_image_path ~= "" then
        if r.file_exists(settings.custom_forward_image_path) then
            transport_custom_images.forward = r.ImGui_CreateImage(settings.custom_forward_image_path)
        else
            settings.custom_forward_image_path = ""
            transport_custom_images.forward = nil
        end
    end
end


function SaveSettings()
    local section = "TK_TRANSPORT"
    local settings_json = json.encode(settings)
    r.SetExtState(section, "settings", settings_json, true)
end

function LoadSettings()
    local settings_json = r.GetExtState("TK_TRANSPORT", "settings")
    if settings_json ~= "" then
        local old_font_size = settings.font_size
        local loaded_settings = json.decode(settings_json)
        for k, v in pairs(loaded_settings) do
            settings[k] = v
        end
        if old_font_size ~= settings.font_size then
            font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
            r.ImGui_Attach(ctx, font)
        end
    end
end
LoadSettings()
UpdateCustomImages()
CustomButtons.LoadLastUsedPreset()
CustomButtons.LoadCurrentButtons()

function ResetSettings()
    for k, v in pairs(default_settings) do
        settings[k] = v
    end
    r.DeleteExtState("TK_TRANSPORT", "last_preset", true)
    preset_name = nil
    SaveSettings()
    font_needs_update = true
end

function CreatePresetsFolder()
    local preset_path = script_path .. "tk_transport_presets"
    if not r.file_exists(preset_path) then
        r.RecursiveCreateDirectory(preset_path, 0)
    end
    return preset_path
end

function SavePreset(name)
    local preset_data = {}
    for k, v in pairs(settings) do
        preset_data[k] = v
    end
    
    r.RecursiveCreateDirectory(preset_path, 0)
    local file = io.open(preset_path .. name .. '.json', 'w')
    if file then
        file:write(json.encode(preset_data))
        file:close()
    end
end

function LoadPreset(name)
    local file = io.open(preset_path .. name .. '.json', 'r')
    if file then
        local content = file:read('*all')
        file:close()
        
        local old_font_size = settings.font_size
        local old_font_name = settings.current_font
        local preset_data = json.decode(content)
        
        for key, value in pairs(preset_data) do
            settings[key] = value
        end
        
        if old_font_size ~= settings.font_size or old_font_name ~= settings.current_font then
            font_needs_update = true
        end
        UpdateCustomImages()
        SaveSettings()
    end
end

LoadPreset(preset_name)

function GetPresetList()
    local presets = {}
    local idx = 0
    local filename = r.EnumerateFiles(preset_path, idx)
    
    while filename do
        if filename:match('%.json$') then
            presets[#presets + 1] = filename:gsub('%.json$', '')
        end
        idx = idx + 1
        filename = r.EnumerateFiles(preset_path, idx)
    end
    return presets
end

function SaveLastUsedPreset(name)
    r.SetExtState("TK_TRANSPORT", "last_preset", name, true)
end

function LoadLastUsedPreset()
    local last_preset = r.GetExtState("TK_TRANSPORT", "last_preset")
    if last_preset ~= "" then
        preset_name = last_preset
        LoadPreset(last_preset)
    end
end

LoadLastUsedPreset()


function SetStyle()
    -- Style setup
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.frame_rounding)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), settings.popup_rounding)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), settings.grab_rounding)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), settings.grab_min_size)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), settings.border_size)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), settings.button_border_size)
    
    -- Colors setup
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), settings.background)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), settings.frame_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), settings.frame_bg_hovered)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), settings.frame_bg_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), settings.slider_grab)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), settings.slider_grab_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), settings.check_mark)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.button_normal)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.button_hovered)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.button_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), settings.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.text_normal)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), settings.background)
end

function ShowSectionHeader(title, state_key)
    r.ImGui_Text(ctx, title)
    r.ImGui_SameLine(ctx)
    
    -- Style voor onzichtbare knop achtergrond
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)       -- Volledig transparant
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000) -- Blijft transparant bij hover
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)  -- Blijft transparant bij klik
    
    -- Verwijder de knop border
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    
    if r.ImGui_Button(ctx, section_states[state_key] and "-##" .. title or "+##" .. title) then
        section_states[state_key] = not section_states[state_key]
    end
    
    -- Pop de styles
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
    
    return section_states[state_key]
end

function ShowSettings(main_window_width , main_window_height)
    if not show_settings then return end
    
    SetStyle()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)

    r.ImGui_SetNextWindowSize(ctx, 400, -1)
    local settings_visible, settings_open = r.ImGui_Begin(ctx, 'Transport Settings', true, settings_flags)
    if settings_visible then
        local window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "TRANSPORT")
        
        if preset_name and preset_name ~= "" then
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, window_width - 150)  -- Positie aanpassen naar wens
            r.ImGui_Text(ctx, "Preset: " .. preset_name)
        end
        
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 25)
        r.ImGui_SetCursorPosY(ctx, 6)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
        
        if r.ImGui_Button(ctx, "##close", 14, 14) then
            settings_open = false
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)

        if r.ImGui_CollapsingHeader(ctx, "Presets") then
            local presets = GetPresetList()
            local display_name = preset_name and preset_name ~= "" and preset_name or "preset_name"
            
            -- Static variable for new preset name input
            if not preset_input_name then
                preset_input_name = ""
            end
            
            -- Preset selection combo
            if r.ImGui_BeginCombo(ctx, "##PresetCombo", display_name) then
                for _, preset in ipairs(presets) do
                    local is_selected = (preset == preset_name)
                    if r.ImGui_Selectable(ctx, preset, is_selected) then
                        preset_name = preset
                        LoadPreset(preset)
                        SaveLastUsedPreset(preset)  
                    end
                    if is_selected then
                        r.ImGui_SetItemDefaultFocus(ctx)
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            
            -- Resave current preset
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Resave") and preset_name then
                SavePreset(preset_name)
            end
            
            -- Delete current preset
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Delete") and preset_name then
                local preset_path = CreatePresetsFolder()
                os.remove(preset_path .. "/" .. preset_name .. ".json")
                preset_name = nil
            end
            
            -- New preset input and save
            local rv
            rv, preset_input_name = r.ImGui_InputText(ctx, "##NewPreset", preset_input_name)
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Save As New") and preset_input_name ~= "" then
                preset_name = preset_input_name
                SavePreset(preset_input_name)
                -- Only clear input after successful save
                if r.file_exists(preset_path .. "/" .. preset_input_name .. ".json") then
                    preset_input_name = ""
                end
            end
        end
        

        if r.ImGui_CollapsingHeader(ctx, "Style Settings") then
            local rv
            rv, settings.window_rounding = r.ImGui_SliderDouble(ctx, "Window Rounding", settings.window_rounding, 0.0, 20.0)
            rv, settings.frame_rounding = r.ImGui_SliderDouble(ctx, "Frame Rounding", settings.frame_rounding, 0.0, 20.0)
            rv, settings.popup_rounding = r.ImGui_SliderDouble(ctx, "Popup Rounding", settings.popup_rounding, 0.0, 20.0)
            rv, settings.grab_rounding = r.ImGui_SliderDouble(ctx, "Grab Rounding", settings.grab_rounding, 0.0, 20.0)
            rv, settings.grab_min_size = r.ImGui_SliderDouble(ctx, "Grab Min Size", settings.grab_min_size, 4.0, 20.0)
            rv, settings.border_size = r.ImGui_SliderDouble(ctx, "Border Size", settings.border_size, 0.0, 5.0)
            rv, settings.button_border_size = r.ImGui_SliderDouble(ctx, "Button Border Size", settings.button_border_size, 0.0, 5.0)
        end
        
        if r.ImGui_CollapsingHeader(ctx, "Color Settings") then
            local flags = r.ImGui_ColorEditFlags_NoInputs()
            local rv
            local window_width = r.ImGui_GetWindowWidth(ctx)
            local column_width = window_width / 2
        
            r.ImGui_Text(ctx, "Primary Elements")
            r.ImGui_SameLine(ctx, column_width)
            r.ImGui_Text(ctx, "Frame Elements")
            r.ImGui_Separator(ctx)
        
            rv, settings.background = r.ImGui_ColorEdit4(ctx, "Background", settings.background, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.frame_bg = r.ImGui_ColorEdit4(ctx, "Frame Background", settings.frame_bg, flags)
        
            rv, settings.text_normal = r.ImGui_ColorEdit4(ctx, "Text Normal", settings.text_normal, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.frame_bg_hovered = r.ImGui_ColorEdit4(ctx, "Frame Bg Hovered", settings.frame_bg_hovered, flags)
        
            rv, settings.border = r.ImGui_ColorEdit4(ctx, "Border Color", settings.border, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.frame_bg_active = r.ImGui_ColorEdit4(ctx, "Frame Bg Active", settings.frame_bg_active, flags)
        
            r.ImGui_Spacing(ctx)
        
            r.ImGui_Text(ctx, "Button States")
            r.ImGui_SameLine(ctx, column_width)
            r.ImGui_Text(ctx, "Control Elements")
            r.ImGui_Separator(ctx)
        
            rv, settings.button_normal = r.ImGui_ColorEdit4(ctx, "Button Normal", settings.button_normal, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.slider_grab = r.ImGui_ColorEdit4(ctx, "Slider Grab", settings.slider_grab, flags)
        
            rv, settings.button_hovered = r.ImGui_ColorEdit4(ctx, "Button Hovered", settings.button_hovered, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.slider_grab_active = r.ImGui_ColorEdit4(ctx, "Slider Grab Active", settings.slider_grab_active, flags)
        
            rv, settings.button_active = r.ImGui_ColorEdit4(ctx, "Button Active", settings.button_active, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.check_mark = r.ImGui_ColorEdit4(ctx, "Check Mark", settings.check_mark, flags)
        
            r.ImGui_Spacing(ctx)

            r.ImGui_Text(ctx, "Transport Colors")
            r.ImGui_Separator(ctx)
                
            rv, settings.transport_normal = r.ImGui_ColorEdit4(ctx, "Transport Normal", settings.transport_normal, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.play_active = r.ImGui_ColorEdit4(ctx, "Play Active", settings.play_active, flags)
            
            rv, settings.record_active = r.ImGui_ColorEdit4(ctx, "Record Active", settings.record_active, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.pause_active = r.ImGui_ColorEdit4(ctx, "Pause Active", settings.pause_active, flags)
           
            rv, settings.loop_active = r.ImGui_ColorEdit4(ctx, "Loop Active", settings.loop_active, flags)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.metronome_active = r.ImGui_ColorEdit4(ctx, "Metronome Pulse", settings.metronome_active, flags)
            rv, settings.metronome_enabled = r.ImGui_ColorEdit4(ctx, "Metronome Enabled", settings.metronome_enabled, flags)
        end
      
        if r.ImGui_CollapsingHeader(ctx, "Layout Settings") then
            local flags = r.ImGui_ColorEditFlags_NoInputs()
            local rv
            local column_width = r.ImGui_GetWindowWidth(ctx) / 2

            if ShowSectionHeader("Transport", "transport_open") then
                rv, settings.center_transport = r.ImGui_Checkbox(ctx, "Center", settings.center_transport)
                local buttons_width = settings.use_graphic_buttons and 280 or 380
            
                -- Transport positie controls
                if settings.center_transport then
                    settings.transport_x = ((main_window_width - buttons_width) / 2) / main_window_width
                else
                    local transport_percent_x = settings.transport_x * 100
                    rv, transport_percent_x = r.ImGui_SliderDouble(ctx, "X##transportX", transport_percent_x, 0, 100, "%.0f%%")
                    settings.transport_x = transport_percent_x / 100
                end
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##transpX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.transport_x = math.max(0, settings.transport_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##transpX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.transport_x = math.min(1, settings.transport_x + pixel_change)
                end
                
                local transport_percent_y = settings.transport_y * 100
                rv, transport_percent_y = r.ImGui_SliderDouble(ctx, "Y##transportY", transport_percent_y, 0, 100, "%.0f%%")
                settings.transport_y = transport_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##transpY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.transport_y = math.max(0, settings.transport_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##transpY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.transport_y = math.min(1, settings.transport_y + pixel_change)
                end  
            end
            r.ImGui_Separator(ctx)
            if ShowSectionHeader("Cursor Position", "cursor_open") then
                -- Cursor Position positie controls
                local cursorpos_percent_x = settings.cursorpos_x * 100
                rv, cursorpos_percent_x = r.ImGui_SliderDouble(ctx, "X##cursorX", cursorpos_percent_x, 0, 100, "%.0f%%")
                settings.cursorpos_x = cursorpos_percent_x / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##cursorX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.cursorpos_x = math.max(0, settings.cursorpos_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##cursorX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.cursorpos_x = math.min(1, settings.cursorpos_x + pixel_change)
                end
                
                local cursorpos_percent_y = settings.cursorpos_y * 100
                rv, cursorpos_percent_y = r.ImGui_SliderDouble(ctx, "Y##cursorY", cursorpos_percent_y, 0, 100, "%.0f%%")
                settings.cursorpos_y = cursorpos_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##cursorY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.cursorpos_y = math.max(0, settings.cursorpos_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##cursorY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.cursorpos_y = math.min(1, settings.cursorpos_y + pixel_change)
                end
            end
            r.ImGui_Separator(ctx)
            if ShowSectionHeader("Visual Metronome", "visualmtr_open") then
                -- Visual Metronome positie controls
                local visualmtr_percent_x = settings.visualmtr_x * 100
                rv, visualmtr_percent_x = r.ImGui_SliderDouble(ctx, "X##visualmtrX", visualmtr_percent_x, 0, 100, "%.0f%%")
                settings.visualmtr_x = visualmtr_percent_x / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##visualmtrX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.visualmtr_x = math.max(0, settings.visualmtr_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##visualmtrX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.visualmtr_x = math.min(1, settings.visualmtr_x + pixel_change)
                end
                
                local visualmtr_percent_y = settings.visualmtr_y * 100
                rv, visualmtr_percent_y = r.ImGui_SliderDouble(ctx, "Y##visualmtrY", visualmtr_percent_y, 0, 100, "%.0f%%")
                settings.visualmtr_y = visualmtr_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##visualmtrY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.visualmtr_y = math.max(0, settings.visualmtr_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##visualmtrY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.visualmtr_y = math.min(1, settings.visualmtr_y + pixel_change)
                end
            end
            r.ImGui_Separator(ctx)
            if ShowSectionHeader("Time Selection", "timesel_open") then
                -- Time Selection positie controls
                local timesel_percent_x = settings.timesel_x * 100
                rv, timesel_percent_x = r.ImGui_SliderDouble(ctx, "X##timeselX", timesel_percent_x, 0, 100, "%.0f%%")
                settings.timesel_x = timesel_percent_x / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##timeselX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.timesel_x = math.max(0, settings.timesel_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##timeselX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.timesel_x = math.min(1, settings.timesel_x + pixel_change)
                end
                
                local timesel_percent_y = settings.timesel_y * 100
                rv, timesel_percent_y = r.ImGui_SliderDouble(ctx, "Y##timeselY", timesel_percent_y, 0, 100, "%.0f%%")
                settings.timesel_y = timesel_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##timeselY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.timesel_y = math.max(0, settings.timesel_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##timeselY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.timesel_y = math.min(1, settings.timesel_y + pixel_change)
                end
                rv, settings.show_time_selection = r.ImGui_Checkbox(ctx, "Show Time", settings.show_time_selection)
                r.ImGui_SameLine(ctx, column_width)
                rv, settings.show_beats_selection = r.ImGui_Checkbox(ctx, "Show Beats", settings.show_beats_selection)
                rv, settings.timesel_invisible = r.ImGui_Checkbox(ctx, "Invisible Button", settings.timesel_invisible)
                r.ImGui_SameLine(ctx, column_width)
                rv, settings.timesel_border = r.ImGui_Checkbox(ctx, "Show Button Border", settings.timesel_border)
                rv, settings.timesel_color = r.ImGui_ColorEdit4(ctx, "Button Color", settings.timesel_color, flags)
            end
            r.ImGui_Separator(ctx)
            if ShowSectionHeader("Tempo", "tempo_open") then
                -- Tempo positie controls
                local tempo_percent_x = settings.tempo_x * 100
                rv, tempo_percent_x = r.ImGui_SliderDouble(ctx, "X##tempoX", tempo_percent_x, 0, 100, "%.0f%%")
                settings.tempo_x = tempo_percent_x / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##tempoX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.tempo_x = math.max(0, settings.tempo_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##tempoX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.tempo_x = math.min(1, settings.tempo_x + pixel_change)
                end
                
                local tempo_percent_y = settings.tempo_y * 100
                rv, tempo_percent_y = r.ImGui_SliderDouble(ctx, "Y##tempoY", tempo_percent_y, 0, 100, "%.0f%%")
                settings.tempo_y = tempo_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##tempoY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.tempo_y = math.max(0, settings.tempo_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##tempoY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.tempo_y = math.min(1, settings.tempo_y + pixel_change)
                end
            end
            r.ImGui_Separator(ctx)
            if ShowSectionHeader("Playrate", "playrate_open") then
                -- Playrate positie controls
                local playrate_percent_x = settings.playrate_x * 100
                rv, playrate_percent_x = r.ImGui_SliderDouble(ctx, "X##playrateX", playrate_percent_x, 0, 100, "%.0f%%")
                settings.playrate_x = playrate_percent_x / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##playrateX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.playrate_x = math.max(0, settings.playrate_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##playrateX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.playrate_x = math.min(1, settings.playrate_x + pixel_change)
                end
                
                local playrate_percent_y = settings.playrate_y * 100
                rv, playrate_percent_y = r.ImGui_SliderDouble(ctx, "Y##playrateY", playrate_percent_y, 0, 100, "%.0f%%")
                settings.playrate_y = playrate_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##playrateY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.playrate_y = math.max(0, settings.playrate_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##playrateY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.playrate_y = math.min(1, settings.playrate_y + pixel_change)
                end
            end
            r.ImGui_Separator(ctx)
            if ShowSectionHeader("Envelope", "env_open") then
                -- ENV Button positie controls
                local env_percent_x = settings.env_x * 100
                rv, env_percent_x = r.ImGui_SliderDouble(ctx, "X##envX", env_percent_x, 0, 100, "%.0f%%")
                settings.env_x = env_percent_x / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##envX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.env_x = math.max(0, settings.env_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##envX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.env_x = math.min(1, settings.env_x + pixel_change)
                end
                
                local env_percent_y = settings.env_y * 100
                rv, env_percent_y = r.ImGui_SliderDouble(ctx, "Y##envY", env_percent_y, 0, 100, "%.0f%%")
                settings.env_y = env_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##envY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.env_y = math.max(0, settings.env_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##envY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.env_y = math.min(1, settings.env_y + pixel_change)
                end
            end
            r.ImGui_Separator(ctx)

            if ShowSectionHeader("TapTempo", "taptempo_open") then
                local taptempo_percent_x = settings.taptempo_x * 100
                rv, taptempo_percent_x = r.ImGui_SliderDouble(ctx, "X##taptempoX", taptempo_percent_x, 0, 100, "%.0f%%")
                settings.taptempo_x = taptempo_percent_x / 100
                
                local taptempo_percent_y = settings.taptempo_y * 100
                rv, taptempo_percent_y = r.ImGui_SliderDouble(ctx, "Y##taptempoY", taptempo_percent_y, 0, 100, "%.0f%%")
                settings.taptempo_y = taptempo_percent_y / 100
                
                rv, settings.tap_button_text = r.ImGui_InputText(ctx, "Button Text", settings.tap_button_text)
                r.ImGui_SetNextItemWidth(ctx, 80)
                rv, settings.tap_button_width = r.ImGui_InputInt(ctx, "Button Width", settings.tap_button_width)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 80)
                rv, settings.tap_button_height = r.ImGui_InputInt(ctx, "Button Height", settings.tap_button_height)
                r.ImGui_SetNextItemWidth(ctx, 80)
                rv, settings.tap_input_limit = r.ImGui_InputInt(ctx, "History Size", settings.tap_input_limit)
                rv, settings.set_tempo_on_tap = r.ImGui_Checkbox(ctx, "Set Project Tempo Automatically", settings.set_tempo_on_tap)
                r.ImGui_SameLine(ctx)
                rv, settings.show_accuracy_indicator = r.ImGui_Checkbox(ctx, "Show Accuracy Indicator", settings.show_accuracy_indicator)
                
                if settings.show_accuracy_indicator then
                    rv, settings.high_accuracy_color = r.ImGui_ColorEdit4(ctx, "High Accuracy Color", settings.high_accuracy_color)
                    rv, settings.medium_accuracy_color = r.ImGui_ColorEdit4(ctx, "Medium Accuracy Color", settings.medium_accuracy_color)
                    rv, settings.low_accuracy_color = r.ImGui_ColorEdit4(ctx, "Low Accuracy Color", settings.low_accuracy_color)
                end
            end
            
            r.ImGui_Separator(ctx)
            if ShowSectionHeader("Settings", "settings_open") then
                -- Settings Button positie controls
                local settings_percent_x = settings.settings_x * 100
                rv, settings_percent_x = r.ImGui_SliderDouble(ctx, "X##settingsX", settings_percent_x, 0, 100, "%.0f%%")
                settings.settings_x = settings_percent_x / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##settingsX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.settings_x = math.max(0, settings.settings_x - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##settingsX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.settings_x = math.min(1, settings.settings_x + pixel_change)
                end
                
                local settings_percent_y = settings.settings_y * 100
                rv, settings_percent_y = r.ImGui_SliderDouble(ctx, "Y##settingsY", settings_percent_y, 0, 100, "%.0f%%")
                settings.settings_y = settings_percent_y / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##settingsY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.settings_y = math.max(0, settings.settings_y - pixel_change)
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##settingsY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.settings_y = math.min(1, settings.settings_y + pixel_change)
                end
            end
            -- In de ShowSettings functie, onder "Layout Settings"
            if r.ImGui_CollapsingHeader(ctx, "Custom Buttons Group") then
                local rv
                
                -- X positie offset
                r.ImGui_Text(ctx, "Global Position Offset")
                local custom_buttons_x_percent = settings.custom_buttons_x_offset * 100
                rv, custom_buttons_x_percent = r.ImGui_SliderDouble(ctx, "X##customButtonsX", custom_buttons_x_percent, -100, 100, "%.0f%%")
                settings.custom_buttons_x_offset = custom_buttons_x_percent / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##customButtonsX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.custom_buttons_x_offset = settings.custom_buttons_x_offset - pixel_change
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##customButtonsX", 20, 20) then
                    local pixel_change = 1 / main_window_width
                    settings.custom_buttons_x_offset = settings.custom_buttons_x_offset + pixel_change
                end
                
                -- Y positie offset
                local custom_buttons_y_percent = settings.custom_buttons_y_offset * 100
                rv, custom_buttons_y_percent = r.ImGui_SliderDouble(ctx, "Y##customButtonsY", custom_buttons_y_percent, -100, 100, "%.0f%%")
                settings.custom_buttons_y_offset = custom_buttons_y_percent / 100
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "-##customButtonsY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.custom_buttons_y_offset = settings.custom_buttons_y_offset - pixel_change
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "+##customButtonsY", 20, 20) then
                    local pixel_change = 1 / main_window_height
                    settings.custom_buttons_y_offset = settings.custom_buttons_y_offset + pixel_change
                end
                
                if r.ImGui_Button(ctx, "Reset Offset") then
                    settings.custom_buttons_x_offset = 0.0
                    settings.custom_buttons_y_offset = 0.0
                end
            end
            r.ImGui_Separator(ctx)
            

            r.ImGui_Text(ctx, "Show/Hide Elements")
            rv, settings.show_timesel = r.ImGui_Checkbox(ctx, "Time selection", settings.show_timesel)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.show_transport = r.ImGui_Checkbox(ctx, "Transport Controls", settings.show_transport)
            rv, settings.show_tempo = r.ImGui_Checkbox(ctx, "Tempo/Time Signature", settings.show_tempo)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.show_playrate = r.ImGui_Checkbox(ctx, "Playrate", settings.show_playrate)
            rv, settings.show_vismetronome = r.ImGui_Checkbox(ctx, "Visual Metronome", settings.show_vismetronome)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.show_env_button = r.ImGui_Checkbox(ctx, "ENV Button", settings.show_env_button)
            rv, settings.show_taptempo = r.ImGui_Checkbox(ctx, "Show TapTempo", settings.show_taptempo)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.show_settings_button = r.ImGui_Checkbox(ctx, "Settings Button", settings.show_settings_button)
            end

        if r.ImGui_CollapsingHeader(ctx, "Custom Transport Button Images") then
            local changed = false
            rv, settings.use_graphic_buttons = r.ImGui_Checkbox(ctx, "Use Graphic Buttons", settings.use_graphic_buttons)
            rv, settings.custom_image_size = r.ImGui_SliderDouble(ctx, "Global Image Scale", settings.custom_image_size or 1.0, 0.5, 2.0, "%.2fx")
            rv, settings.use_locked_button_folder = r.ImGui_Checkbox(ctx, "Use last image folder for all buttons", settings.use_locked_button_folder)
            if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                r.ImGui_Text(ctx, "Current folder: " .. settings.locked_button_folder_path)
            end
            
            r.ImGui_Separator(ctx)
            
            rv, settings.use_custom_play_image = r.ImGui_Checkbox(ctx, "Use Custom Play Button", settings.use_custom_play_image)
            changed = changed or rv
            if settings.use_custom_play_image then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse##Play") then
                    local start_dir = ""
                    if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                        start_dir = settings.locked_button_folder_path
                    end
                    
                    local retval, file = r.GetUserFileNameForRead(start_dir, "Select Play Button Image", ".png")
                    if retval then
                        settings.custom_play_image_path = file
                        changed = true

                        if settings.use_locked_button_folder then
                            settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                        end
                    end
                end
                
            end
            rv, settings.custom_play_image_size = r.ImGui_SliderDouble(ctx, "Play Image Scale", settings.custom_play_image_size, 0.5, 2.0, "%.2fx")

            rv, settings.use_custom_stop_image = r.ImGui_Checkbox(ctx, "Use Custom Stop Button", settings.use_custom_stop_image)
            changed = changed or rv
            if settings.use_custom_stop_image then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse##Stop") then
                    local start_dir = ""
                    if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                        start_dir = settings.locked_button_folder_path
                    end
                    
                    local retval, file = r.GetUserFileNameForRead(start_dir, "Select Stop Button Image", ".png")
                    if retval then
                        settings.custom_stop_image_path = file
                        changed = true
                        
                        if settings.use_locked_button_folder then
                            settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                        end
                    end
                end
            end
            rv, settings.custom_stop_image_size = r.ImGui_SliderDouble(ctx, "Stop Image Scale", settings.custom_stop_image_size, 0.5, 2.0, "%.2fx")

            rv, settings.use_custom_pause_image = r.ImGui_Checkbox(ctx, "Use Custom Pause Button", settings.use_custom_pause_image)
            changed = changed or rv
            if settings.use_custom_pause_image then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse##Pause") then
                    local start_dir = ""
                    if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                        start_dir = settings.locked_button_folder_path
                    end
                    
                    local retval, file = r.GetUserFileNameForRead(start_dir, "Select Pause Button Image", ".png")
                    if retval then
                        settings.custom_pause_image_path = file
                        changed = true
                        
                        if settings.use_locked_button_folder then
                            settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                        end
                    end
                end
            end
            rv, settings.custom_pause_image_size = r.ImGui_SliderDouble(ctx, "Pause Image Scale", settings.custom_pause_image_size, 0.5, 2.0, "%.2fx")

            rv, settings.use_custom_record_image = r.ImGui_Checkbox(ctx, "Use Custom Record Button", settings.use_custom_record_image)
            changed = changed or rv
            if settings.use_custom_record_image then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse##Record") then
                    local start_dir = ""
                    if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                        start_dir = settings.locked_button_folder_path
                    end
                    
                    local retval, file = r.GetUserFileNameForRead(start_dir, "Select Record Button Image", ".png")
                    if retval then
                        settings.custom_record_image_path = file
                        changed = true
                        if settings.use_locked_button_folder then
                            settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                        end
                    end
                end
            end
            rv, settings.custom_record_image_size = r.ImGui_SliderDouble(ctx, "Record Image Scale", settings.custom_record_image_size, 0.5, 2.0, "%.2fx")
            
            rv, settings.use_custom_loop_image = r.ImGui_Checkbox(ctx, "Use Custom Loop Button", settings.use_custom_loop_image)
            changed = changed or rv
            if settings.use_custom_loop_image then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse##Loop") then
                    local start_dir = ""
                    if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                        start_dir = settings.locked_button_folder_path
                    end
                    
                    local retval, file = r.GetUserFileNameForRead(start_dir, "Select Loop Button Image", ".png")
                    if retval then
                        settings.custom_loop_image_path = file
                        changed = true
                        
                        if settings.use_locked_button_folder then
                            settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                        end
                    end
                end
            end
            rv, settings.custom_loop_image_size = r.ImGui_SliderDouble(ctx, "Loop Image Scale", settings.custom_loop_image_size, 0.5, 2.0, "%.2fx")

            rv, settings.use_custom_rewind_image = r.ImGui_Checkbox(ctx, "Use Custom Rewind Button", settings.use_custom_rewind_image)
            changed = changed or rv
            if settings.use_custom_rewind_image then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse##Rewind") then
                    local start_dir = ""
                    if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                        start_dir = settings.locked_button_folder_path
                    end
                    
                    local retval, file = r.GetUserFileNameForRead(start_dir, "Select Rewind Button Image", ".png")
                    if retval then
                        settings.custom_rewind_image_path = file
                        changed = true
                        
                        if settings.use_locked_button_folder then
                            settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                        end
                    end
                end
            end
            rv, settings.custom_rewind_image_size = r.ImGui_SliderDouble(ctx, "Rewind Image Scale", settings.custom_rewind_image_size, 0.5, 2.0, "%.2fx")
            
            rv, settings.use_custom_forward_image = r.ImGui_Checkbox(ctx, "Use Custom Forward Button", settings.use_custom_forward_image)
            changed = changed or rv
            if settings.use_custom_forward_image then
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Browse##Forward") then
                    local start_dir = ""
                    if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                        start_dir = settings.locked_button_folder_path
                    end
                    
                    local retval, file = r.GetUserFileNameForRead(start_dir, "Select Forward Button Image", ".png")
                    if retval then
                        settings.custom_forward_image_path = file
                        changed = true
                        
                        if settings.use_locked_button_folder then
                            settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                        end
                    end
                end
            end
            rv, settings.custom_forward_image_size = r.ImGui_SliderDouble(ctx, "Forward Image Scale", settings.custom_forward_image_size, 0.5, 2.0, "%.2fx")
            
            if changed then
                UpdateCustomImages()
            end
        end
        
        if r.ImGui_CollapsingHeader(ctx, "Font Settings") then
            local rv
            if r.ImGui_BeginCombo(ctx, "Font", settings.current_font) then
                for i, font in ipairs(fonts) do
                    local is_selected = (settings.current_font == font)
                    if r.ImGui_Selectable(ctx, font, is_selected) then
                        settings.current_font = font
                        UpdateFont()
                    end
                    if is_selected then
                        r.ImGui_SetItemDefaultFocus(ctx)
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_BeginCombo(ctx, "Font Size", tostring(settings.font_size)) then
                for i, size in ipairs(text_sizes) do
                    local is_selected = (settings.font_size == size)
                    if r.ImGui_Selectable(ctx, tostring(size), is_selected) then
                        settings.font_size = size
                        UpdateFont()
                    end
                    if is_selected then
                        r.ImGui_SetItemDefaultFocus(ctx)
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
        end
        if r.ImGui_CollapsingHeader(ctx, "Widget Manager") then
            WidgetManager.RenderWidgetManagerUI(ctx, script_path)
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, "Reset to Defaults") then
            ResetSettings()
            SaveSettings()
        end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Save Settings") then
            SaveSettings()
        end

        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Custom Button Editor") then
            CustomButtons.show_editor = true
        end

        r.ImGui_PopStyleVar(ctx, 8)
        r.ImGui_PopStyleColor(ctx, 13)
        r.ImGui_End(ctx)
    end
    show_settings = settings_open
end

function EnvelopeOverride(main_window_width, main_window_height)
    if not settings.show_env_button then return end 
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.env_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.env_y * main_window_height)
    local current_mode = "No override"
    for _, mode in ipairs(AUTOMATION_MODES) do
        if r.GetToggleCommandState(mode.command) == 1 then
            current_mode = mode.name
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.loop_active)
            break
        end
    end
    
    if r.ImGui_Button(ctx, "ENV") then
        r.ImGui_OpenPopup(ctx, "AutomationMenu")
    end
    
    if current_mode ~= "No override" then
        r.ImGui_PopStyleColor(ctx)
    end
    
    if r.ImGui_BeginPopup(ctx, "AutomationMenu") then
        for _, mode in ipairs(AUTOMATION_MODES) do
            if r.ImGui_MenuItem(ctx, mode.name, nil, current_mode == mode.name) then
                r.Main_OnCommand(mode.command, 0)
            end
        end
        r.ImGui_EndPopup(ctx)
    end
end

-- RECHTSKLIK MENU's VOOR TRANSPORT:
function ShowPlaySyncMenu()
    if r.ImGui_IsItemClicked(ctx, 1) then 
        r.ImGui_OpenPopup(ctx, "SyncMenu")
    end
    if r.ImGui_BeginPopup(ctx, "SyncMenu") then
        if r.ImGui_MenuItem(ctx, "Timecode Sync Settings") then
            r.Main_OnCommand(40619, 0)
        end
        if r.ImGui_MenuItem(ctx, "Toggle Timecode Sync") then
            r.Main_OnCommand(40620, 0)
        end
        r.ImGui_EndPopup(ctx)
    end
end

function ShowRecordMenu()
    if r.ImGui_IsItemClicked(ctx, 1) then 
        r.ImGui_OpenPopup(ctx, "RecordMenu")
    end
    
    if r.ImGui_BeginPopup(ctx, "RecordMenu") then
        if r.ImGui_MenuItem(ctx, "Normal Record Mode") then
            r.Main_OnCommand(40252, 0)
        end
        if r.ImGui_MenuItem(ctx, "Selected Item Auto-Punch") then
            r.Main_OnCommand(40253, 0)
        end
        if r.ImGui_MenuItem(ctx, "Time Selection Auto-Punch") then
            r.Main_OnCommand(40076, 0)
        end
        r.ImGui_EndPopup(ctx)
    end
end


function Transport_Buttons(main_window_width, main_window_height)
    if not settings.show_transport then return end
    
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.transport_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
     
    local buttonSize = settings.font_size * 1.1
    local drawList = r.ImGui_GetWindowDrawList(ctx)
    
    if settings.use_graphic_buttons then
        local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        
        if r.ImGui_InvisibleButton(ctx, "<<", buttonSize, buttonSize) then
            r.Main_OnCommand(GOTO_START, 0)
        end
        
        if settings.use_custom_rewind_image and transport_custom_images.rewind and r.ImGui_ValidatePtr(transport_custom_images.rewind, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(ctx) then
                uv_x = 0.33
            end
            
            local scaled_size = buttonSize * settings.custom_rewind_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.rewind,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, settings.transport_normal)
            graphics.DrawArrows(pos_x-10, pos_y, buttonSize, false)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local play_state = r.GetPlayState() & 1 == 1
        local play_color = play_state and settings.play_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "PLAY", buttonSize, buttonSize) then
            r.Main_OnCommand(PLAY_COMMAND, 0)
        end
        ShowPlaySyncMenu()
        
        if settings.use_custom_play_image and transport_custom_images.play and r.ImGui_ValidatePtr(transport_custom_images.play, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(ctx) then
                uv_x = 0.33
            end
            if play_state then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * settings.custom_play_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.play,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local play_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, play_color)
            play_graphics.DrawPlay(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "STOP", buttonSize, buttonSize) then
            r.Main_OnCommand(STOP_COMMAND, 0)
        end
        
        if settings.use_custom_stop_image and transport_custom_images.stop and r.ImGui_ValidatePtr(transport_custom_images.stop, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(ctx) then
                uv_x = 0.33
            end
            
            local scaled_size = buttonSize * settings.custom_stop_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.stop,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, settings.transport_normal)
            graphics.DrawStop(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local pause_state = r.GetPlayState() & 2 == 2
        local pause_color = pause_state and settings.pause_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "PAUSE", buttonSize, buttonSize) then
            r.Main_OnCommand(PAUSE_COMMAND, 0)
        end
        
        if settings.use_custom_pause_image and transport_custom_images.pause and r.ImGui_ValidatePtr(transport_custom_images.pause, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(ctx) then
                uv_x = 0.33
            end
            if pause_state then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * settings.custom_pause_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.pause,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local pause_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, pause_color)
            pause_graphics.DrawPause(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        local rec_color = (rec_state == 1) and settings.record_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "REC", buttonSize, buttonSize) then
            r.Main_OnCommand(RECORD_COMMAND, 0)
        end
        ShowRecordMenu()
        
        if settings.use_custom_record_image and transport_custom_images.record and r.ImGui_ValidatePtr(transport_custom_images.record, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(ctx) then
                uv_x = 0.33
            end
            if rec_state == 1 then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * settings.custom_record_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.record,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local rec_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, rec_color)
            rec_graphics.DrawRecord(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        local loop_color = (repeat_state == 1) and settings.loop_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "LOOP", buttonSize, buttonSize) then
            r.Main_OnCommand(REPEAT_COMMAND, 0)
        end
        
        if settings.use_custom_loop_image and transport_custom_images.loop and r.ImGui_ValidatePtr(transport_custom_images.loop, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(ctx) then
                uv_x = 0.33
            end
            if repeat_state == 1 then
                uv_x = 0.66
            end
            
            local scaled_size = buttonSize * settings.custom_loop_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.loop,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local loop_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, loop_color)
            loop_graphics.DrawLoop(pos_x, pos_y, buttonSize)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, ">>", buttonSize, buttonSize) then
            r.Main_OnCommand(GOTO_END, 0)
        end
        
        if settings.use_custom_forward_image and transport_custom_images.forward and r.ImGui_ValidatePtr(transport_custom_images.forward, 'ImGui_Image*') then
            local uv_x = 0
            if r.ImGui_IsItemHovered(ctx) then
                uv_x = 0.33
            end
            
            local scaled_size = buttonSize * settings.custom_forward_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.forward,
                pos_x, pos_y,
                pos_x + scaled_size, pos_y + scaled_size,
                uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, settings.transport_normal)
            graphics.DrawArrows(pos_x+5, pos_y, buttonSize, true)
        end
        
    else
    
        if r.ImGui_Button(ctx, "<<") then
            r.Main_OnCommand(GOTO_START, 0)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local play_state = r.GetPlayState() & 1 == 1
        if play_state then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.play_active)
        end
        if r.ImGui_Button(ctx, "PLAY") then
            r.Main_OnCommand(PLAY_COMMAND, 0)
        end
        if play_state then r.ImGui_PopStyleColor(ctx) end
        ShowPlaySyncMenu()

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        if r.ImGui_Button(ctx, "STOP") then
            r.Main_OnCommand(STOP_COMMAND, 0)
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local pause_state = r.GetPlayState() & 2 == 2
        if pause_state then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.pause_active)
        end
        if r.ImGui_Button(ctx, "PAUSE") then
            r.Main_OnCommand(PAUSE_COMMAND, 0)
        end
        if pause_state then r.ImGui_PopStyleColor(ctx) end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        if rec_state == 1 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.record_active)
        end
        if r.ImGui_Button(ctx, "REC") then
            r.Main_OnCommand(RECORD_COMMAND, 0)
        end
        if rec_state == 1 then r.ImGui_PopStyleColor(ctx) end
        ShowRecordMenu()
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        if repeat_state == 1 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.loop_active)
        end
        if r.ImGui_Button(ctx, "LOOP") then
            r.Main_OnCommand(REPEAT_COMMAND, 0)
        end
        if repeat_state == 1 then r.ImGui_PopStyleColor(ctx) end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosY(ctx, settings.transport_y * main_window_height)
        if r.ImGui_Button(ctx, ">>") then
            r.Main_OnCommand(GOTO_END, 0)
        end
    end
end

function DrawTransportGraphics(drawList, x, y, size, color)
   
    local function DrawPlay(x, y, size)
        local adjustedSize = size  
        local points = {
            x + size*0.1, y + size*0.1,  
            x + size*0.1, y + adjustedSize,
            x + adjustedSize, y + size/2
        }
        r.ImGui_DrawList_AddTriangleFilled(drawList, 
            points[1], points[2],
            points[3], points[4],
            points[5], points[6],
            color)
    end

    local function DrawStop(x, y, size)
        local adjustedSize = size 
        r.ImGui_DrawList_AddRectFilled(drawList, 
            x + size*0.1, y + size*0.1,
            x + adjustedSize, y + adjustedSize,
            color)
    end

    local function DrawPause(x, y, size)
        local adjustedSize = size 
        local barWidth = adjustedSize/3
        r.ImGui_DrawList_AddRectFilled(drawList, 
            x + size*0.1, y + size*0.1,
            x + size*0.1 + barWidth, y + adjustedSize,
            color)
        r.ImGui_DrawList_AddRectFilled(drawList,
            x + adjustedSize - barWidth, y + size*0.1,
            x + adjustedSize, y + adjustedSize,
            color)
    end

    local function DrawRecord(x, y, size)
        local adjustedSize = size *1.1
        r.ImGui_DrawList_AddCircleFilled(drawList,
            x + size/2, y + size/2,
            adjustedSize/2,
            color)
    end

    local function DrawLoop(x, y, size)
        local adjustedSize = size 
        r.ImGui_DrawList_AddCircle(drawList,
            x + size/2, y + size/2,
            adjustedSize/2,
            color, 32, 2)
        
        local arrowSize = adjustedSize/4
        local ax = x + size/12
        local ay = y + size/2
        r.ImGui_DrawList_AddTriangleFilled(drawList,
            ax, ay,
            ax - arrowSize/2, ay + arrowSize/2,
            ax + arrowSize/2, ay + arrowSize/2,
            color)
    end

    local function DrawArrows(x, y, size, forward)
        local arrowSize = size/1.8
        local spacing = size/6
        local yCenter = y + size/2
        
        for i = 0,1 do
            local startX = x + (i * (arrowSize + spacing))
            local points
            
            if forward then
                points = {
                    startX, yCenter - arrowSize/2.2,
                    startX, yCenter + arrowSize/2.2,
                    startX + arrowSize, yCenter
                }
            else
                points = {
                    startX + arrowSize, yCenter - arrowSize/2,
                    startX + arrowSize, yCenter + arrowSize/2,
                    startX, yCenter
                }
            end
            
            r.ImGui_DrawList_AddTriangleFilled(drawList,
                points[1], points[2],
                points[3], points[4],
                points[5], points[6],
                color)
        end
    end
    
    

    return {
        DrawPlay = DrawPlay,
        DrawStop = DrawStop,
        DrawPause = DrawPause,
        DrawRecord = DrawRecord,
        DrawArrows = DrawArrows,
        DrawLoop = DrawLoop
    }
end

function PlayRate_Slider(main_window_width, main_window_height)
    if not settings.show_playrate then return end
    local current_rate = r.Master_GetPlayRate(0)
    
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.playrate_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.playrate_y * main_window_height)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, 'Rate:')
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosY(ctx, settings.playrate_y * main_window_height)
    r.ImGui_PushItemWidth(ctx, 80)
    local rv, new_rate = r.ImGui_SliderDouble(ctx, '##PlayRateSlider', current_rate, 0.25, 4.0, "%.2fx")  
    
    if r.ImGui_IsItemClicked(ctx, 1) then
        new_rate = 1.0
        r.CSurf_OnPlayRateChange(new_rate)
    elseif rv then
        r.CSurf_OnPlayRateChange(new_rate)
    end
    
    r.ImGui_PopItemWidth(ctx)
end

function ShowCursorPosition(main_window_width, main_window_height)
    if not settings.show_transport then return end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.cursorpos_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.cursorpos_y * main_window_height)
    r.ImGui_InvisibleButton(ctx, "##", 10, 10)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.cursorpos_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.cursorpos_y * main_window_height)
    local play_state = r.GetPlayState()
    local position = (play_state == 1) and r.GetPlayPosition() or r.GetCursorPosition()

    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = reaper.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end
    
    local retval, measures, cml, fullbeats = r.TimeMap2_timeToBeats(0, position)
    measures = measures or 0
    
    local beatsInMeasure = fullbeats % timesig_num
    local ticks = math.floor((beatsInMeasure - math.floor(beatsInMeasure)) * 960/10)
    local minutes = math.floor(position / 60)
    local seconds = position % 60
    local time_str = string.format("%d:%06.3f", minutes, seconds)
    
    local mbt_str = string.format("%d.%d.%02d", 
    math.floor(measures+1), 
    math.floor(beatsInMeasure+1),
    ticks)
    
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), settings.button_normal)
    r.ImGui_Button(ctx, mbt_str .. " / " .. time_str)
    r.ImGui_PopStyleColor(ctx)
end

function ShowTempoAndTimeSignature(main_window_width, main_window_height)
    if not settings.show_tempo then return end
    local tempo = r.Master_GetTempo()

    r.ImGui_SetCursorPosX(ctx, settings.tempo_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.tempo_y * main_window_height)

    r.ImGui_PushItemWidth(ctx, settings.font_size * 4)
local rv_tempo, new_tempo = r.ImGui_InputDouble(ctx, "##tempo", tempo, 0, 0, "%.1f")
    if rv_tempo then r.CSurf_OnTempoChange(new_tempo) end
    if r.ImGui_IsItemClicked(ctx, 1) then r.CSurf_OnTempoChange(120.0) end
    r.ImGui_PopItemWidth(ctx)
   
   r.ImGui_SameLine(ctx)
   r.ImGui_SetCursorPosY(ctx, settings.tempo_y * main_window_height)
   
   r.ImGui_SameLine(ctx)
   r.ImGui_SetCursorPosY(ctx, settings.tempo_y * main_window_height)
   local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = r.GetTempoTimeSigMarker(0, 0)
   if not retval then timesig_num, timesig_denom = 4, 4 end
   r.ImGui_PushItemWidth(ctx, settings.font_size * 2)
   local rv_num, new_num = r.ImGui_InputInt(ctx, "##num", timesig_num, 0, 0)
   r.ImGui_SameLine(ctx)
   r.ImGui_SetCursorPosY(ctx, settings.tempo_y * main_window_height)
   r.ImGui_Text(ctx, "/")

   r.ImGui_SameLine(ctx)
   r.ImGui_SetCursorPosY(ctx, settings.tempo_y * main_window_height)
   local rv_denom, new_denom = r.ImGui_InputInt(ctx, "##denom", timesig_denom, 0, 0)

   if rv_num or rv_denom then
       r.Undo_BeginBlock()
       r.PreventUIRefresh(1)
       
       local _, measures = r.TimeMap2_timeToBeats(0, 0)
       local ptx_in_effect = r.FindTempoTimeSigMarker(0, 0)

       local num_to_set = rv_num and new_num > 0 and new_num or timesig_num
       local denom_to_set = rv_denom and new_denom > 0 and new_denom or timesig_denom

       r.SetTempoTimeSigMarker(0, -1, -1, measures, 0, -1, num_to_set, denom_to_set, true)
       r.GetSetTempoTimeSigMarkerFlag(0, ptx_in_effect + 1, 1|2|16, true)
       
       r.PreventUIRefresh(-1)
       r.Undo_EndBlock("Change time signature", 1|4|8)
   end
   r.ImGui_PopItemWidth(ctx)
end

function ShowTimeSelection(main_window_width, main_window_height)
    if not settings.show_timesel then return end
    
    local start_time, end_time = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local length = end_time - start_time
    
    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = r.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end
    
    local minutes_start = math.floor(start_time / 60)
    local seconds_start = start_time % 60
    local sec_format = string.format("%d:%06.3f", minutes_start, seconds_start)
    
    local retval, measures_start, cml, fullbeats_start = r.TimeMap2_timeToBeats(0, start_time)
    local beatsInMeasure_start = fullbeats_start % timesig_num
    local ticks_start = math.floor((beatsInMeasure_start - math.floor(beatsInMeasure_start)) * 960/10)
    local start_midi = string.format("%d.%d.%02d",
        math.floor(measures_start+1),
        math.floor(beatsInMeasure_start+1),
        ticks_start)
    
    local minutes_end = math.floor(end_time / 60)
    local seconds_end = end_time % 60
    local end_format = string.format("%d:%06.3f", minutes_end, seconds_end)
    
    local retval, measures_end, cml, fullbeats_end = r.TimeMap2_timeToBeats(0, end_time)
    local beatsInMeasure_end = fullbeats_end % timesig_num
    local ticks_end = math.floor((beatsInMeasure_end - math.floor(beatsInMeasure_end)) * 960/10)
    local end_midi = string.format("%d.%d.%02d",
        math.floor(measures_end+1),
        math.floor(beatsInMeasure_end+1),
        ticks_end)
    
    local minutes_len = math.floor(length / 60)
    local seconds_len = length % 60
    local len_format = string.format("%d:%06.3f", minutes_len, seconds_len)
    
    local retval, measures_length, cml, fullbeats_length = r.TimeMap2_timeToBeats(0, length)
    local beatsInMeasure_length = fullbeats_length % timesig_num
    local ticks_length = math.floor((beatsInMeasure_length - math.floor(beatsInMeasure_length)) * 960/10)
    local len_midi = string.format("%d.%d.%02d",
        math.floor(measures_length),
        math.floor(beatsInMeasure_length),
        ticks_length)

        r.ImGui_SetCursorPosX(ctx, settings.timesel_x * main_window_width)
        r.ImGui_SetCursorPosY(ctx, settings.timesel_y * main_window_height)

    if settings.timesel_invisible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.timesel_color)
    end

    if not settings.timesel_border then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    end

    local display_text = ""
    if settings.show_beats_selection and settings.show_time_selection then
        display_text = string.format("Selection: %s / %s / %s / %s / %s / %s",
            start_midi, sec_format,
            end_midi, end_format,
            len_midi, len_format)
    elseif settings.show_beats_selection then
        display_text = string.format("Selection: %s / %s / %s",
            start_midi, end_midi, len_midi)
    elseif settings.show_time_selection then
        display_text = string.format("Selection: %s / %s / %s",
            sec_format, end_format, len_format)
    end

    if display_text == "" then
        r.ImGui_Button(ctx, "##TimeSelectionEmpty")
    else
        r.ImGui_Button(ctx, display_text)
    end
    

    if not settings.timesel_border then
        r.ImGui_PopStyleVar(ctx)
    end
    
    if settings.timesel_invisible then
        r.ImGui_PopStyleColor(ctx, 3)
    else
        r.ImGui_PopStyleColor(ctx)
    end
end

function VisualMetronome(main_window_width, main_window_height)
    if not settings.show_vismetronome then return end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.visualmtr_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.visualmtr_y * main_window_height)
    local playPos = reaper.GetPlayPosition()
    local tempo = reaper.Master_GetTempo()
    local beatLength = 60/tempo
    local currentBeatPhase = playPos % beatLength
    local pulseSize = settings.font_size * 0.5

    local pulseIntensity = math.exp(-currentBeatPhase * 8/beatLength)
    local finalSize = pulseSize * (1 + pulseIntensity * 0.1)
    
    local screenX, screenY = reaper.ImGui_GetCursorScreenPos(ctx)
    local posX = screenX + pulseSize
    local posY = screenY + pulseSize
    
    local buttonSize = pulseSize * 2
    r.ImGui_InvisibleButton(ctx, "MetronomeButton", buttonSize, buttonSize)
    
    local drawList = reaper.ImGui_GetWindowDrawList(ctx)
    local color = settings.button_normal
    if currentBeatPhase < 0.05 then
        color = settings.metronome_active

    end

    reaper.ImGui_DrawList_AddCircleFilled(drawList, posX, posY, finalSize, color)
    
    local metronome_enabled = r.GetToggleCommandState(40364) == 1
    if metronome_enabled then
        reaper.ImGui_DrawList_AddCircle(drawList, posX, posY, finalSize + 2, settings.metronome_enabled, 32, 2)
    end
    
    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "MetronomeMenu")
    end
    
    if r.ImGui_BeginPopup(ctx, "MetronomeMenu") then
        if r.ImGui_MenuItem(ctx, "Metronome Settings") then
            r.Main_OnCommand(40363, 0)
        end
        if r.ImGui_MenuItem(ctx, "Toggle Metronome") then
            r.Main_OnCommand(40364, 0)
        end
        r.ImGui_EndPopup(ctx)
    end
end

-- TapTempo helper functions
local function average(matrix)
    if #matrix == 0 then return 0 end
    local sum = 0
    for i, cell in ipairs(matrix) do
        sum = sum + cell
    end
    return sum / #matrix
end

local function standardDeviation(t)
    if #t <= 1 then return 0 end
    local m = average(t)
    local sum = 0
    for k, v in pairs(t) do
        if type(v) == 'number' then
            sum = sum + ((v - m) * (v - m))
        end
    end
    return math.sqrt(sum / (#t - 1))
end

function TapTempo(main_window_width, main_window_height)
    if not settings.show_taptempo then return end
    
    -- Position the TapTempo widget
    r.ImGui_SetCursorPosX(ctx, settings.taptempo_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.taptempo_y * main_window_height)
    r.ImGui_AlignTextToFramePadding(ctx)
    -- Style the tap button
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.button_normal)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.button_hovered)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.button_active)
    
    -- TAP button
    if r.ImGui_Button(ctx, settings.tap_button_text, settings.tap_button_width, settings.tap_button_height) then
        local current_time = r.time_precise()
        if last_tap_time > 0 then
            local tap_interval = current_time - last_tap_time
            tap_z = tap_z + 1
            if tap_z > settings.tap_input_limit then tap_z = 1 end
            tap_times[tap_z] = 60 / tap_interval
            tap_average_current = average(tap_times)
            
            if settings.set_tempo_on_tap and tap_average_current > 0 then
                r.CSurf_OnTempoChange(tap_average_current)
            end
        end
        last_tap_time = current_time
    end
    
    -- Context menu
    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "TapTempoMenu")
    end
    
    r.ImGui_PopStyleColor(ctx, 3)
    
    -- Display current BPM and accuracy
    r.ImGui_SameLine(ctx)
    r.ImGui_AlignTextToFramePadding(ctx)
    if #tap_times > 0 then
        local deviation = standardDeviation(tap_times)
        local precision = 0
        if tap_average_current > 0 then
            precision = (tap_average_current - deviation) / tap_average_current
        end
        
        if settings.show_accuracy_indicator then
            local accuracyColor = settings.low_accuracy_color
            if precision > 0.9 then
                accuracyColor = settings.high_accuracy_color
            elseif precision > 0.5 then
                accuracyColor = settings.medium_accuracy_color
            end
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), accuracyColor)
            
            r.ImGui_Text(ctx, string.format("%.1f%%", precision * 100))
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_SameLine(ctx)
            r.ImGui_AlignTextToFramePadding(ctx)
        end
        r.ImGui_Text(ctx, string.format("BPM: %.1f", math.floor(tap_average_current * 10 + 0.5) / 10))
    else
        r.ImGui_Text(ctx, "Tap to start...")
    end
    
    -- Context menu items
    if r.ImGui_BeginPopup(ctx, "TapTempoMenu") then
        if r.ImGui_MenuItem(ctx, "Reset Taps") then
            tap_times = {}
            tap_average_times = {}
            tap_clicks = 0
            tap_z = 0
            tap_w = 0
            last_tap_time = 0
        end
        
        local rv
        rv, settings.set_tempo_on_tap = r.ImGui_MenuItem(ctx, "Set Project Tempo", nil, settings.set_tempo_on_tap)
        
        if #tap_times > 0 then
            r.ImGui_Separator(ctx)
            if r.ImGui_MenuItem(ctx, "Set Half Tempo") then
                r.CSurf_OnTempoChange(tap_average_current / 2)
            end
            if r.ImGui_MenuItem(ctx, "Set Double Tempo") then
                r.CSurf_OnTempoChange(tap_average_current * 2)
            end
        end
        
        r.ImGui_EndPopup(ctx)
    end
end

function Main()
    if not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        ctx = r.ImGui_CreateContext('Transport Control')
        font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
        font_icons = r.ImGui_CreateFontFromFile(script_path .. 'Icons-Regular.otf', 0)
        r.ImGui_Attach(ctx, font)
        r.ImGui_Attach(ctx, font_icons)
        font_needs_update = false
    end

    if font_needs_update then
        font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
        font_icons = r.ImGui_CreateFontFromFile(script_path .. 'Icons-Regular.otf', 0)
        
        r.ImGui_Attach(ctx, font)
        r.ImGui_Attach(ctx, font_icons)
        
        font_needs_update = false
    end
    local needs_refresh = r.GetExtState("TK_TRANSPORT", "refresh_buttons")
    if needs_refresh == "1" then
        CustomButtons.LoadLastUsedPreset()
        r.SetExtState("TK_TRANSPORT", "refresh_buttons", "0", false)
    end
    r.ImGui_PushFont(ctx, font, settings.font_size)

    SetStyle()
    
    local visible, open = r.ImGui_Begin(ctx, 'Transport', true, window_flags)
    if visible then
        local main_window_width = r.ImGui_GetWindowWidth(ctx)
        local main_window_height = r.ImGui_GetWindowHeight(ctx) 
         
        ShowTimeSelection(main_window_width, main_window_height)
        EnvelopeOverride(main_window_width, main_window_height)
        Transport_Buttons(main_window_width, main_window_height)
        ShowCursorPosition(main_window_width, main_window_height)
        VisualMetronome(main_window_width, main_window_height)
        CustomButtons.x_offset = settings.custom_buttons_x_offset
        CustomButtons.y_offset = settings.custom_buttons_y_offset

        ButtonRenderer.RenderButtons(ctx, CustomButtons)
        ButtonEditor.ShowEditor(ctx, CustomButtons, settings, main_window_width, main_window_height)
        CustomButtons.CheckForCommandPick()
        ShowTempoAndTimeSignature(main_window_width, main_window_height)
        PlayRate_Slider(main_window_width, main_window_height) 
        TapTempo(main_window_width, main_window_height) 
        
        if settings.show_settings_button then
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, settings.settings_x * main_window_width)
            r.ImGui_SetCursorPosY(ctx, settings.settings_y * main_window_height)

            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000) 
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)

            r.ImGui_PushFont(ctx, font_icons, 12)
            if r.ImGui_Button(ctx, "\u{0047}") then
                show_settings = not show_settings
            end
            r.ImGui_PopFont(ctx)
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_PopStyleColor(ctx, 3)
        end
        ShowSettings(main_window_width, main_window_height)

        if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) and not r.ImGui_IsAnyItemHovered(ctx) then
            r.ImGui_OpenPopup(ctx, "TransportContextMenu")
        end
        
        if r.ImGui_BeginPopup(ctx, "TransportContextMenu") then
            if r.ImGui_MenuItem(ctx, "Show Settings") then
                show_settings = true
            end
            
            if r.ImGui_MenuItem(ctx, "Close Script") then
                open = false
            end
            
            r.ImGui_EndPopup(ctx)
        end
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 7)
    r.ImGui_PopStyleColor(ctx, 13)
    
    if open then
        r.defer(Main)
    else
        CustomButtons.SaveCurrentButtons()
    end
end

r.defer(Main)
