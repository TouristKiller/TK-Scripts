-- @description TK_TRANSPORT
-- @author TouristKiller
-- @version 0.0.1
-- @changelog 
--[[
+ TK TRANSPORT First basic version
]]--


local r                 = reaper
local ctx               = r.ImGui_CreateContext('Transport Control')
local script_path       = debug.getinfo(1, 'S').source:match([[^@?(.*[\/])[^\/]-$]])
package.path            = package.path .. ";" .. script_path .. "?.lua"
local json              = require("json")
local preset_path       = script_path .. "tk_transport_presets/"
local preset_name       = ""


local PLAY_COMMAND      = 1007
local STOP_COMMAND      = 1016
local PAUSE_COMMAND     = 1008
local RECORD_COMMAND    = 1013
local REPEAT_COMMAND    = 1068
local GOTO_START        = 40042
local GOTO_END          = 40043

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

local show_settings     = true 
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
    transport_x         = 0.41,      
    timesel_x           = 0.0,        
    tempo_x             = 0.69,         
    playrate_x          = 0.93,      
    env_x               = 0.19,           
    settings_x          = 0.99,      

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
}

local settings          = {}

for k, v in pairs(default_settings) do
    settings[k] = v
end

local font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
r.ImGui_Attach(ctx, font)
local font_needs_update = false
function UpdateFont()
    font_needs_update = true
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

function ResetSettings()
    for k, v in pairs(default_settings) do
        settings[k] = v
    end
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


function SetStyle()
    -- Style setup
    --r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 0)
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

function ShowSettings(main_window_width)
    if not show_settings then return end
    
    SetStyle()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)

    r.ImGui_SetNextWindowSize(ctx, 400, -1)
    local settings_visible, settings_open = r.ImGui_Begin(ctx, 'Transport Settings', true, settings_flags)
    if settings_visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "TRANSPORT")
        
        local window_width = r.ImGui_GetWindowWidth(ctx)
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
            local rv
            rv, preset_name = r.ImGui_InputText(ctx, "Preset Name", preset_name or "")
            
            if r.ImGui_Button(ctx, "Save Preset") and preset_name and preset_name ~= "" then
                SavePreset(preset_name)
            end
            
            r.ImGui_Separator(ctx)
            local presets = GetPresetList()
            for _, preset in ipairs(presets) do
                if r.ImGui_Button(ctx, "Load##" .. preset) then
                    LoadPreset(preset)
                end
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, preset)
                
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Delete##" .. preset) then
                    local preset_path = CreatePresetsFolder()
                    os.remove(preset_path .. "/" .. preset .. ".json")
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
        
            rv, settings.center_transport = r.ImGui_Checkbox(ctx, "Center Transport", settings.center_transport)
            local buttons_width = settings.use_graphic_buttons and 280 or 380
            
            if settings.center_transport then
                settings.transport_x = ((main_window_width - buttons_width) / 2) / main_window_width
            else
                local transport_percent = settings.transport_x * 100  -- Already stored as percentage
                rv, transport_percent = r.ImGui_SliderDouble(ctx, "Transport", transport_percent, 0, 100, "%.0f%%")
                settings.transport_x = transport_percent / 100
                local transport_pos = transport_percent * main_window_width
            end
    
            local timesel_percent = settings.timesel_x * 100  -- Already stored as percentage
            rv, timesel_percent = r.ImGui_SliderDouble(ctx, "Time Selection", timesel_percent, 0, 100, "%.0f%%")
            settings.timesel_x = timesel_percent / 100
            local timesel_pos = timesel_percent * main_window_width

            local tempo_percent = settings.tempo_x * 100  -- Already stored as percentage
            rv, tempo_percent = r.ImGui_SliderDouble(ctx, "Tempo", tempo_percent, 0, 100, "%.0f%%")
            settings.tempo_x = tempo_percent / 100
            local tempo_pos = tempo_percent * main_window_width

            local playrate_percent = settings.playrate_x * 100  -- Already stored as percentage
            rv, playrate_percent = r.ImGui_SliderDouble(ctx, "PlayRate", playrate_percent, 0, 100, "%.0f%%")
            settings.playrate_x = playrate_percent / 100
            local playrate_pos = playrate_percent * main_window_width

            local env_percent = settings.env_x * 100  -- Already stored as percentage
            rv, env_percent = r.ImGui_SliderDouble(ctx, "ENV Button", env_percent, 0, 100, "%.0f%%")
            settings.env_x = env_percent / 100
            local env_pos = env_percent * main_window_width

            local settings_percent = settings.settings_x * 100  -- Already stored as percentage
            rv, settings_percent = r.ImGui_SliderDouble(ctx, "Settings Button", settings_percent, 0, 100, "%.0f%%")
            settings.settings_x = settings_percent / 100
            local settings_pos = settings_percent * main_window_width
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Time Selection Display")
            rv, settings.show_time_selection = r.ImGui_Checkbox(ctx, "Show Time", settings.show_time_selection)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.show_beats_selection = r.ImGui_Checkbox(ctx, "Show Beats", settings.show_beats_selection)
            rv, settings.timesel_invisible = r.ImGui_Checkbox(ctx, "Invisible Button", settings.timesel_invisible)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.timesel_border = r.ImGui_Checkbox(ctx, "Show Button Border", settings.timesel_border)
            rv, settings.timesel_color = r.ImGui_ColorEdit4(ctx, "Button Color", settings.timesel_color, flags)
        
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Show/Hide Elements")
            rv, settings.use_graphic_buttons = r.ImGui_Checkbox(ctx, "Use Graphic Buttons", settings.use_graphic_buttons)
            rv, settings.show_timesel = r.ImGui_Checkbox(ctx, "Time selection", settings.show_timesel)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.show_transport = r.ImGui_Checkbox(ctx, "Transport Controls", settings.show_transport)
            rv, settings.show_tempo = r.ImGui_Checkbox(ctx, "Tempo/Time Signature", settings.show_tempo)
            r.ImGui_SameLine(ctx, column_width)
            rv, settings.show_playrate = r.ImGui_Checkbox(ctx, "Playrate", settings.show_playrate)
            rv, settings.show_vismetronome = r.ImGui_Checkbox(ctx, "Visual Metronome", settings.show_vismetronome)
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
        
        if r.ImGui_Button(ctx, "Reset to Defaults") then
            ResetSettings()
            SaveSettings()
        end
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, "Save Settings") then
            SaveSettings()
        end

        r.ImGui_PopStyleVar(ctx, 8)
        r.ImGui_PopStyleColor(ctx, 13)
        r.ImGui_End(ctx)
    end
    show_settings = settings_open
end

function EnvelopeOverride(main_window_width)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.env_x * main_window_width)
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


function Transport_Buttons(main_window_width)
    if not settings.show_transport then return end
    
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.transport_x * main_window_width)
     
    local buttonSize = settings.font_size * 1.1
    local drawList = r.ImGui_GetWindowDrawList(ctx)
    
    if settings.use_graphic_buttons then
        local pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        
        if r.ImGui_InvisibleButton(ctx, "<<", buttonSize, buttonSize) then
            r.Main_OnCommand(GOTO_START, 0)
        end
        
        local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, settings.transport_normal)
        graphics.DrawArrows(pos_x-10, pos_y, buttonSize, false)
        
        r.ImGui_SameLine(ctx)
        local play_state = r.GetPlayState() & 1 == 1
        local play_color = play_state and settings.play_active or settings.transport_normal 
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "PLAY", buttonSize, buttonSize) then
            r.Main_OnCommand(PLAY_COMMAND, 0)
        end
        ShowPlaySyncMenu()
        
        local play_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, play_color)
        play_graphics.DrawPlay(pos_x, pos_y, buttonSize)
        
        r.ImGui_SameLine(ctx)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "STOP", buttonSize, buttonSize) then
            r.Main_OnCommand(STOP_COMMAND, 0)
        end
        graphics.DrawStop(pos_x, pos_y, buttonSize)
        
        r.ImGui_SameLine(ctx)
        local pause_state = r.GetPlayState() & 2 == 2
        local pause_color = pause_state and settings.pause_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "PAUSE", buttonSize, buttonSize) then
            r.Main_OnCommand(PAUSE_COMMAND, 0)
        end
        
        local pause_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, pause_color)
        pause_graphics.DrawPause(pos_x, pos_y, buttonSize)
        
        r.ImGui_SameLine(ctx)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        local rec_color = (rec_state == 1) and settings.record_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "REC", buttonSize, buttonSize) then
            r.Main_OnCommand(RECORD_COMMAND, 0)
        end
        ShowRecordMenu()
        local rec_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, rec_color)
        rec_graphics.DrawRecord(pos_x, pos_y, buttonSize)
        
        r.ImGui_SameLine(ctx)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        local loop_color = (repeat_state == 1) and settings.loop_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "LOOP", buttonSize, buttonSize) then
            r.Main_OnCommand(REPEAT_COMMAND, 0)
        end
        
        local loop_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, loop_color)
        loop_graphics.DrawLoop(pos_x, pos_y, buttonSize)
        
        r.ImGui_SameLine(ctx)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, ">>", buttonSize, buttonSize) then
            r.Main_OnCommand(GOTO_END, 0)
        end
        graphics.DrawArrows(pos_x+5, pos_y, buttonSize, true)
        
    else
        if r.ImGui_Button(ctx, "<<") then
            r.Main_OnCommand(GOTO_START, 0)
        end
        
        r.ImGui_SameLine(ctx)
        
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
        
        if r.ImGui_Button(ctx, "STOP") then
            r.Main_OnCommand(STOP_COMMAND, 0)
        end
        
        r.ImGui_SameLine(ctx)
        
        local pause_state = r.GetPlayState() & 2 == 2
        if pause_state then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.pause_active)
        end
        if r.ImGui_Button(ctx, "PAUSE") then
            r.Main_OnCommand(PAUSE_COMMAND, 0)
        end
        if pause_state then r.ImGui_PopStyleColor(ctx) end
        
        r.ImGui_SameLine(ctx)
        
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
        
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        if repeat_state == 1 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.loop_active)
        end
        if r.ImGui_Button(ctx, "LOOP") then
            r.Main_OnCommand(REPEAT_COMMAND, 0)
        end
        if repeat_state == 1 then r.ImGui_PopStyleColor(ctx) end
        
        r.ImGui_SameLine(ctx)
        
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

function PlayRate_Slider(main_window_width)
    if not settings.show_playrate then return end
    local current_rate = r.Master_GetPlayRate(0)
    
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.playrate_x * main_window_width)
    r.ImGui_Text(ctx, 'Rate:')
    r.ImGui_SameLine(ctx)
    
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

function ShowCursorPosition()
    if not settings.show_transport then return end
    r.ImGui_SameLine(ctx)
    r.ImGui_InvisibleButton(ctx, "##", 10, 10)
    r.ImGui_SameLine(ctx)
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

function ShowTempoAndTimeSignature(main_window_width)
    if not settings.show_tempo then return end
    
    local tempo = r.Master_GetTempo()

    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.tempo_x * main_window_width)
    r.ImGui_Text(ctx, "BPM:")
    r.ImGui_SameLine(ctx)
    
    r.ImGui_PushItemWidth(ctx, settings.font_size * 6.5)
    local rv_tempo, new_tempo = r.ImGui_InputDouble(ctx, "##tempo", tempo, 0.1, 1.0, "%.1f")
    if rv_tempo then r.CSurf_OnTempoChange(new_tempo) end
    if r.ImGui_IsItemClicked(ctx, 1) then r.CSurf_OnTempoChange(120.0) end
    r.ImGui_PopItemWidth(ctx)
   
   r.ImGui_SameLine(ctx)
   r.ImGui_Text(ctx, "Time Sig:")
   r.ImGui_SameLine(ctx)
   
   local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = r.GetTempoTimeSigMarker(0, 0)
   if not retval then timesig_num, timesig_denom = 4, 4 end
   
   r.ImGui_PushItemWidth(ctx, 80)
   local rv_num, new_num = r.ImGui_InputInt(ctx, "##num", timesig_num)
   r.ImGui_SameLine(ctx)
   r.ImGui_Text(ctx, "/")
   r.ImGui_SameLine(ctx)
   local rv_denom, new_denom = r.ImGui_InputInt(ctx, "##denom", timesig_denom)
   
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
   r.ImGui_SameLine(ctx)
end


function ShowTimeSelection(main_window_width)
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

    r.ImGui_Button(ctx, display_text)

    if not settings.timesel_border then
        r.ImGui_PopStyleVar(ctx)
    end
    
    if settings.timesel_invisible then
        r.ImGui_PopStyleColor(ctx, 3)
    else
        r.ImGui_PopStyleColor(ctx)
    end
end

function VisualMetronome()
    if not settings.show_vismetronome then return end
    r.ImGui_SameLine(ctx)
    local playPos = reaper.GetPlayPosition()
    local tempo = reaper.Master_GetTempo()
    local beatLength = 60/tempo
    local currentBeatPhase = playPos % beatLength
    local pulseSize = settings.font_size * 0.62

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


function Main()
    if font_needs_update then
        font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
        r.ImGui_Attach(ctx, font)
        font_needs_update = false
    end
    r.ImGui_PushFont(ctx, font)

    SetStyle()
    
    local visible, open = r.ImGui_Begin(ctx, 'Transport', true, window_flags)
    if visible then
        local main_window_width = r.ImGui_GetWindowWidth(ctx)
         
        ShowTimeSelection(main_window_width)
        EnvelopeOverride(main_window_width)
        Transport_Buttons(main_window_width)
        ShowCursorPosition(main_window_width)
        VisualMetronome(main_window_width)
        ShowTempoAndTimeSignature(main_window_width)
        PlayRate_Slider(main_window_width) 
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, settings.settings_x * main_window_width)
        if r.ImGui_Button(ctx, "S") then
            show_settings = not show_settings
        end
        ShowSettings(main_window_width)

        
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 7)
    r.ImGui_PopStyleColor(ctx, 13)
    
    if open then
        r.defer(Main)
    end
end

r.defer(Main)
