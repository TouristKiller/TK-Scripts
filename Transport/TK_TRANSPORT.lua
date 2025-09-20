-- @description TK_TRANSPORT
-- @author TouristKiller
-- @version 0.5.1
-- @changelog 
--[[

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

local tempo_dragging = false
local tempo_start_value = 0
local tempo_accumulated_delta = 0
local tempo_button_center_x = nil
local tempo_button_center_y = nil
local tempo_last_mouse_y = nil
local tempo_mouse_anchor_x, tempo_mouse_anchor_y = nil, nil

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
    -- Transport buttons font (independent of base font)
    transport_font_name = "Arial",
    transport_font_size = 12,
    tempo_font_name         = "Arial",
    timesig_font_name       = "Arial",
    local_time_font_name    = "Arial",
    tempo_font_size         = 12,
    timesig_font_size       = 12, 
    show_timesig_button     = false, 
    local_time_font_size    = 12, 
    center_transport    = true,
    current_preset_name = "",

    -- x offset
    transport_x         = 0.41,      
    timesel_x           = 0.0,        
    tempo_x             = 0.69,         
    timesig_x           = 0.75,
    playrate_x          = 0.93,      
    env_x               = 0.19,           
    settings_x          = 0.99,
    cursorpos_x         = 0.25,
    cursorpos_mode      = "both", 
    local_time_x        = 0.50,
    custom_buttons_x_offset = 0.0,
    -- y offset
    transport_y         = 0.15,      
    timesel_y           = 0.15,        
    tempo_y             = 0.15,         
    timesig_y           = 0.02,
    playrate_y          = 0.15,      
    env_y               = 0.15,           
    settings_y          = 0.15,    
    cursorpos_y         = 0.15,
    local_time_y        = 0.02,
    custom_buttons_y_offset = 0.0,
    -- Edit mode & grid for custom buttons
    edit_mode = false,
    edit_grid_show = true,
    edit_grid_size_px = 16,
    edit_grid_color = 0xFFFFFF22,
    edit_snap_to_grid = true,
    -- Custom buttons UX
    show_custom_button_tooltip = true,

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
    timesel_color       = 0x333333FF,
    timesel_border      = true,
    show_local_time     = true,
    local_time_color    = 0xFFFFFFFF,
    timesel_invisible   = false,

    -- Visibility settings
    use_graphic_buttons = false,
    show_timesel        = true,
    show_transport      = true,
    show_tempo          = true,
    show_playrate       = true,
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
    low_accuracy_color = 0xFF0000FF,
    tempo_presets = {60,80,100,120,140,160,180},
    tempo_button_color = 0x333333FF,
    tempo_button_color_hover = 0x444444FF,
    measure_display_width = 160  

}

local settings          = {}

for k, v in pairs(default_settings) do
    settings[k] = v
end

local element_rects = {}
local Layout = {
    elems = {
        { name = "transport",   showFlag = "show_transport",      keyx = "transport_x",  keyy = "transport_y",  beforeDrag = function() settings.center_transport = false end },
        { name = "cursorpos",    showFlag = nil,                    keyx = "cursorpos_x",  keyy = "cursorpos_y" },
        { name = "localtime",    showFlag = "show_local_time",     keyx = "local_time_x", keyy = "local_time_y" },
        { name = "tempo",        showFlag = "show_tempo",          keyx = "tempo_x",      keyy = "tempo_y" },
        { name = "playrate",     showFlag = "show_playrate",       keyx = "playrate_x",   keyy = "playrate_y" },
        { name = "timesig",      showFlag = "show_timesig_button", keyx = "timesig_x",    keyy = "timesig_y" },
        { name = "env",          showFlag = "show_env_button",     keyx = "env_x",        keyy = "env_y" },
        { name = "timesel",      showFlag = "show_timesel",        keyx = "timesel_x",    keyy = "timesel_y" },
        { name = "settings",     showFlag = "show_settings_button", keyx = "settings_x",   keyy = "settings_y" },
        { name = "taptempo",     showFlag = "show_taptempo",       keyx = "taptempo_x",   keyy = "taptempo_y" },
    }
}
function Layout.move_frac(dx, dy, keyx, keyy)
    settings[keyx] = math.max(0, math.min(1, (settings[keyx] or 0) + dx))
    settings[keyy] = math.max(0, math.min(1, (settings[keyy] or 0) + dy))
end

local function DrawXYControls(keyx, keyy, main_window_width, main_window_height, opts)
    opts = opts or {}
    local stepType = opts.step or "pixel" -- "pixel" or "percent"
    local percentStep = opts.percentStep or 0.001 -- 0.1%

    local x_pct = (settings[keyx] or 0) * 100
    local rv
    rv, x_pct = r.ImGui_SliderDouble(ctx, "X##"..keyx, x_pct, 0, 100, "%.0f%%")
    if rv then settings[keyx] = math.max(0, math.min(1, x_pct / 100)) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "-##"..keyx, 20, 20) then
        if stepType == "percent" then
            settings[keyx] = math.max(0, (settings[keyx] or 0) - percentStep)
        else
            settings[keyx] = math.max(0, (settings[keyx] or 0) - (1 / math.max(1, main_window_width)))
        end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "+##"..keyx, 20, 20) then
        if stepType == "percent" then
            settings[keyx] = math.min(1, (settings[keyx] or 0) + percentStep)
        else
            settings[keyx] = math.min(1, (settings[keyx] or 0) + (1 / math.max(1, main_window_width)))
        end
    end
    if opts.directInputX then
        r.ImGui_Text(ctx, "Direct X:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 80)
        local x_input = (settings[keyx] or 0) * 100
        rv, x_input = r.ImGui_InputDouble(ctx, "##"..keyx.."Input", x_input, 0.1, 1.0, "%.1f")
        if rv then
            x_input = math.max(0, math.min(100, x_input))
            settings[keyx] = x_input / 100
        end
    end

    local y_pct = (settings[keyy] or 0) * 100
    rv, y_pct = r.ImGui_SliderDouble(ctx, "Y##"..keyy, y_pct, 0, 100, "%.0f%%")
    if rv then settings[keyy] = math.max(0, math.min(1, y_pct / 100)) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "-##"..keyy, 20, 20) then
        if stepType == "percent" then
            settings[keyy] = math.max(0, (settings[keyy] or 0) - percentStep)
        else
            settings[keyy] = math.max(0, (settings[keyy] or 0) - (1 / math.max(1, main_window_height)))
        end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "+##"..keyy, 20, 20) then
        if stepType == "percent" then
            settings[keyy] = math.min(1, (settings[keyy] or 0) + percentStep)
        else
            settings[keyy] = math.min(1, (settings[keyy] or 0) + (1 / math.max(1, main_window_height)))
        end
    end
    if opts.directInputY then
        r.ImGui_Text(ctx, "Direct Y:")
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 80)
        local y_input = (settings[keyy] or 0) * 100
        rv, y_input = r.ImGui_InputDouble(ctx, "##"..keyy.."Input", y_input, 0.1, 1.0, "%.1f")
        if rv then
            y_input = math.max(0, math.min(100, y_input))
            settings[keyy] = y_input / 100
        end
    end
end
local overlay_drag_active = nil
local overlay_drag_last_x, overlay_drag_last_y = nil, nil
local overlay_drag_moved = false -- track whether a drag actually changed position for autosave
local function StoreElementRect(name)
    local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
    element_rects[name] = {min_x=min_x, min_y=min_y, max_x=max_x, max_y=max_y}
end
local function StoreElementRectUnion(name, min_x, min_y, max_x, max_y)
    element_rects[name] = {min_x=min_x, min_y=min_y, max_x=max_x, max_y=max_y}
end

local settings_active_tab = 0  -- 0 = Style & Colors, 1 = Layout & Position, 2 = Custom Buttons, 3 = Images & Graphics, 4 = Widget Manager

local font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
local font_transport = r.ImGui_CreateFont(settings.transport_font_name or settings.current_font, settings.transport_font_size or settings.font_size)
local font_tempo = r.ImGui_CreateFont(settings.tempo_font_name or settings.current_font, settings.tempo_font_size or settings.font_size)
local font_timesig = r.ImGui_CreateFont(settings.timesig_font_name or settings.current_font, settings.timesig_font_size or settings.font_size)
local font_localtime = r.ImGui_CreateFont(settings.local_time_font_name or settings.current_font, settings.local_time_font_size or settings.font_size)
local font_icons = r.ImGui_CreateFontFromFile(script_path .. 'Icons-Regular.otf', 0)
local SETTINGS_UI_FONT_NAME = 'Segoe UI'
local SETTINGS_UI_FONT_SIZE = 13
local settings_ui_font = r.ImGui_CreateFont(SETTINGS_UI_FONT_NAME, SETTINGS_UI_FONT_SIZE)
local SETTINGS_UI_FONT_SMALL_SIZE = 10
local settings_ui_font_small = r.ImGui_CreateFont(SETTINGS_UI_FONT_NAME, SETTINGS_UI_FONT_SMALL_SIZE)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_transport)
r.ImGui_Attach(ctx, font_tempo)
r.ImGui_Attach(ctx, font_timesig)
r.ImGui_Attach(ctx, font_localtime)
r.ImGui_Attach(ctx, font_icons)
r.ImGui_Attach(ctx, settings_ui_font)
r.ImGui_Attach(ctx, settings_ui_font_small)
local font_needs_update = false
function UpdateFont()
    font_needs_update = true
end

local function RebuildSectionFonts()
    font_transport = r.ImGui_CreateFont(settings.transport_font_name or settings.current_font, settings.transport_font_size or settings.font_size)
    font_tempo = r.ImGui_CreateFont(settings.tempo_font_name or settings.current_font, settings.tempo_font_size or settings.font_size)
    font_timesig = r.ImGui_CreateFont(settings.timesig_font_name or settings.current_font, settings.timesig_font_size or settings.font_size)
    font_localtime = r.ImGui_CreateFont(settings.local_time_font_name or settings.current_font, settings.local_time_font_size or settings.font_size)
    r.ImGui_Attach(ctx, font_transport)
    r.ImGui_Attach(ctx, font_tempo)
    r.ImGui_Attach(ctx, font_timesig)
    r.ImGui_Attach(ctx, font_localtime)
end

function UpdateCustomImages()
    if settings.use_custom_play_image and settings.custom_play_image_path ~= "" then
        if r.file_exists(settings.custom_play_image_path) then
            transport_custom_images.play = r.ImGui_CreateImage(settings.custom_play_image_path)
        else
            settings.custom_play_image_path = ""
            transport_custom_images.play = nil
        end
    end
    
    if settings.use_custom_stop_image and settings.custom_stop_image_path ~= "" then
        if r.file_exists(settings.custom_stop_image_path) then
            transport_custom_images.stop = r.ImGui_CreateImage(settings.custom_stop_image_path)
        else
            settings.custom_stop_image_path = ""
            transport_custom_images.stop = nil
        end
    end
    
    if settings.use_custom_pause_image and settings.custom_pause_image_path ~= "" then
        if r.file_exists(settings.custom_pause_image_path) then
            transport_custom_images.pause = r.ImGui_CreateImage(settings.custom_pause_image_path)
        else
            settings.custom_pause_image_path = ""
            transport_custom_images.pause = nil
        end
    end
    
    if settings.use_custom_record_image and settings.custom_record_image_path ~= "" then
        if r.file_exists(settings.custom_record_image_path) then
            transport_custom_images.record = r.ImGui_CreateImage(settings.custom_record_image_path)
        else
            settings.custom_record_image_path = ""
            transport_custom_images.record = nil
        end
    end
    
    if settings.use_custom_loop_image and settings.custom_loop_image_path ~= "" then
        if r.file_exists(settings.custom_loop_image_path) then
            transport_custom_images.loop = r.ImGui_CreateImage(settings.custom_loop_image_path)
        else
            settings.custom_loop_image_path = ""
            transport_custom_images.loop = nil
        end
    end
    
    if settings.use_custom_rewind_image and settings.custom_rewind_image_path ~= "" then
        if r.file_exists(settings.custom_rewind_image_path) then
            transport_custom_images.rewind = r.ImGui_CreateImage(settings.custom_rewind_image_path)
        else
            settings.custom_rewind_image_path = ""
            transport_custom_images.rewind = nil
        end
    end
    
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
    if not preset_name or preset_name == "" then
        preset_name = "Default"
    end
    SavePreset(preset_name)
    SaveLastUsedPreset(preset_name)
end

function LoadSettings()
    if not settings.tempo_presets or type(settings.tempo_presets) ~= 'table' or #settings.tempo_presets == 0 then
        settings.tempo_presets = {60,80,100,120,140,160,180}
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
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)       -- Volledig transparant
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000) -- Blijft transparant bij hover
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)  -- Blijft transparant bij klik
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    
    if r.ImGui_Button(ctx, section_states[state_key] and "-##" .. title or "+##" .. title) then
        section_states[state_key] = not section_states[state_key]
    end
    
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 3)
    
    return section_states[state_key]
end

function ShowSettings(main_window_width , main_window_height)
    if not show_settings then return end
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)
    r.ImGui_SetNextWindowSize(ctx, 600, -1)
    local settings_visible, settings_open = r.ImGui_Begin(ctx, 'Transport Settings', true, settings_flags)
    if settings_visible then
        r.ImGui_PushFont(ctx, settings_ui_font, SETTINGS_UI_FONT_SIZE)
        SetStyle()
        
        local window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "TRANSPORT")
        
        
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

        r.ImGui_Text(ctx, "Presets:")
        local presets = GetPresetList()
        local display_name = preset_name and preset_name ~= "" and preset_name or "preset_name"

        if not preset_input_name then
            preset_input_name = ""
        end

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

        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Resave") and preset_name then
            SavePreset(preset_name)
        end

        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Delete") and preset_name then
            local preset_path = CreatePresetsFolder()
            os.remove(preset_path .. "/" .. preset_name .. ".json")
            preset_name = nil
        end

        local rv
        rv, preset_input_name = r.ImGui_InputText(ctx, "##NewPreset", preset_input_name)
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Save As New") and preset_input_name ~= "" then
            preset_name = preset_input_name
            SavePreset(preset_input_name)
            local preset_path = CreatePresetsFolder()
            if r.file_exists(preset_path .. "/" .. preset_input_name .. ".json") then
                preset_input_name = ""
            end
        end
        r.ImGui_Separator(ctx)
        

        if r.ImGui_BeginTabBar(ctx, "SettingsTabs") then
            if r.ImGui_BeginTabItem(ctx, "Style & Colors") then
                local rv
                rv, settings.window_rounding = r.ImGui_SliderDouble(ctx, "Window Rounding", settings.window_rounding, 0.0, 20.0)
                rv, settings.frame_rounding = r.ImGui_SliderDouble(ctx, "Frame Rounding", settings.frame_rounding, 0.0, 20.0)
                rv, settings.popup_rounding = r.ImGui_SliderDouble(ctx, "Popup Rounding", settings.popup_rounding, 0.0, 20.0)
                rv, settings.grab_rounding = r.ImGui_SliderDouble(ctx, "Grab Rounding", settings.grab_rounding, 0.0, 20.0)
                rv, settings.grab_min_size = r.ImGui_SliderDouble(ctx, "Grab Min Size", settings.grab_min_size, 4.0, 20.0)
                rv, settings.border_size = r.ImGui_SliderDouble(ctx, "Border Size", settings.border_size, 0.0, 5.0)
                rv, settings.button_border_size = r.ImGui_SliderDouble(ctx, "Button Border Size", settings.button_border_size, 0.0, 5.0)
                
                local flags = r.ImGui_ColorEditFlags_NoInputs()
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
            
                r.ImGui_EndTabItem(ctx)
            end
            
            if r.ImGui_BeginTabItem(ctx, "Layout & Position") then
                local flags = r.ImGui_ColorEditFlags_NoInputs()
                local column_width = r.ImGui_GetWindowWidth(ctx) / 2

                r.ImGui_Text(ctx, "Global Font")
                if r.ImGui_BeginCombo(ctx, "Base Font", settings.current_font) then
                    for _, f in ipairs(fonts) do
                        local sel = (settings.current_font == f)
                        if r.ImGui_Selectable(ctx, f, sel) then
                            settings.current_font = f
                            UpdateFont()
                            RebuildSectionFonts()
                        end
                        if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                if r.ImGui_BeginCombo(ctx, "Base Size", tostring(settings.font_size)) then
                    for _, size in ipairs(text_sizes) do
                        local sel = (settings.font_size == size)
                        if r.ImGui_Selectable(ctx, tostring(size), sel) then
                            settings.font_size = size
                            UpdateFont()
                            RebuildSectionFonts()
                        end
                        if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                if r.ImGui_BeginCombo(ctx, "Transport Buttons Font", settings.transport_font_name or settings.current_font) then
                    for _, f in ipairs(fonts) do
                        local sel = ((settings.transport_font_name or settings.current_font) == f)
                        if r.ImGui_Selectable(ctx, f, sel) then
                            settings.transport_font_name = f
                            RebuildSectionFonts()
                        end
                        if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                if r.ImGui_BeginCombo(ctx, "Transport Buttons Size", tostring(settings.transport_font_size or settings.font_size)) then
                    for _, size in ipairs(text_sizes) do
                        local sel = ((settings.transport_font_size or settings.font_size) == size)
                        if r.ImGui_Selectable(ctx, tostring(size), sel) then
                            settings.transport_font_size = size
                            RebuildSectionFonts()
                        end
                        if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                    end
                    r.ImGui_EndCombo(ctx)
                end
                r.ImGui_Separator(ctx)

                r.ImGui_Text(ctx, "Layout Edit Mode")
                local rv
                rv, settings.edit_mode = r.ImGui_Checkbox(ctx, "Enable Edit Mode (drag to move)", settings.edit_mode)
                rv, settings.edit_snap_to_grid = r.ImGui_Checkbox(ctx, "Snap to Grid", settings.edit_snap_to_grid)
                r.ImGui_SameLine(ctx)
                rv, settings.edit_grid_show = r.ImGui_Checkbox(ctx, "Show Grid", settings.edit_grid_show)
                r.ImGui_SetNextItemWidth(ctx, 120)
                rv, settings.edit_grid_size_px = r.ImGui_SliderInt(ctx, "Grid Size (px)", settings.edit_grid_size_px or 16, 4, 64)
                local rv_col, new_col = r.ImGui_ColorEdit4(ctx, "Grid Color", settings.edit_grid_color or 0xFFFFFF22, r.ImGui_ColorEditFlags_NoInputs())
                if rv_col then settings.edit_grid_color = new_col end
                r.ImGui_Separator(ctx)

                if ShowSectionHeader("Transport", "transport_open") then
                    rv, settings.show_transport = r.ImGui_Checkbox(ctx, "Show##transport", settings.show_transport)
                    if settings.show_transport then
                        rv, settings.center_transport = r.ImGui_Checkbox(ctx, "Center", settings.center_transport)
                        if settings.center_transport then
                            local tfsize = settings.transport_font_size or settings.font_size or 16
                            local buttonSize = tfsize * 1.1
                            local spacing = math.floor(buttonSize * 0.2)
                            local count = 7 
                            local perButtonWidth = settings.use_graphic_buttons and buttonSize or (buttonSize * 1.7)
                            local buttons_width = perButtonWidth * count + spacing * (count - 1)
                            settings.transport_x = ((main_window_width - buttons_width) / 2) / main_window_width
                        else
                            DrawXYControls('transport_x','transport_y', main_window_width, main_window_height, { step = 'percent', percentStep = 0.001, directInputX = true, directInputY = true })
                        end
                    end
                end
                
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Cursor Position", "cursor_open") then
                    DrawXYControls('cursorpos_x','cursorpos_y', main_window_width, main_window_height, { step = 'percent', percentStep = 0.001, directInputX = true, directInputY = true })
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Time Selection", "timesel_open") then
                    rv, settings.show_timesel = r.ImGui_Checkbox(ctx, "Show##timesel", settings.show_timesel)
                    if settings.show_timesel then
                        DrawXYControls('timesel_x','timesel_y', main_window_width, main_window_height, { step = 'pixel' })
                        rv, settings.show_time_selection = r.ImGui_Checkbox(ctx, "Show Time", settings.show_time_selection)
                        r.ImGui_SameLine(ctx, column_width)
                        rv, settings.show_beats_selection = r.ImGui_Checkbox(ctx, "Show Beats", settings.show_beats_selection)
                        rv, settings.timesel_invisible = r.ImGui_Checkbox(ctx, "Invisible Button", settings.timesel_invisible)
                        r.ImGui_SameLine(ctx, column_width)
                        rv, settings.timesel_border = r.ImGui_Checkbox(ctx, "Show Button Border", settings.timesel_border)
                        rv, settings.timesel_color = r.ImGui_ColorEdit4(ctx, "Button Color", settings.timesel_color, flags)
                    end
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Tempo", "tempo_open") then
                    rv, settings.show_tempo = r.ImGui_Checkbox(ctx, "Show##tempo", settings.show_tempo)
                    if settings.show_tempo then
                        if r.ImGui_BeginCombo(ctx, "Tempo Font", settings.tempo_font_name) then
                            for _, f in ipairs(fonts) do
                                local sel = (settings.tempo_font_name == f)
                                if r.ImGui_Selectable(ctx, f, sel) then
                                    settings.tempo_font_name = f
                                    RebuildSectionFonts()
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        if r.ImGui_BeginCombo(ctx, "Tempo Size", tostring(settings.tempo_font_size)) then
                            for _, size in ipairs(text_sizes) do
                                local sel = (settings.tempo_font_size == size)
                                if r.ImGui_Selectable(ctx, tostring(size), sel) then
                                    settings.tempo_font_size = size
                                    RebuildSectionFonts()
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        DrawXYControls('tempo_x','tempo_y', main_window_width, main_window_height, { step = 'pixel' })
                        rv, settings.tempo_button_color = r.ImGui_ColorEdit4(ctx, "Tempo Button Color", settings.tempo_button_color, flags)
                        rv, settings.tempo_button_color_hover = r.ImGui_ColorEdit4(ctx, "Tempo Hover Color", settings.tempo_button_color_hover, flags)
                    end
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Playrate", "playrate_open") then
                    rv, settings.show_playrate = r.ImGui_Checkbox(ctx, "Show##playrate", settings.show_playrate)
                    if settings.show_playrate then
                        DrawXYControls('playrate_x','playrate_y', main_window_width, main_window_height, { step = 'pixel' })
                    end
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Time Signature", "timesig_layout_open") then
                    rv, settings.show_timesig_button = r.ImGui_Checkbox(ctx, "Show##timesig", settings.show_timesig_button)
                    if settings.show_timesig_button then
                        if r.ImGui_BeginCombo(ctx, "TimeSig Font", settings.timesig_font_name) then
                            for _, f in ipairs(fonts) do
                                local sel = (settings.timesig_font_name == f)
                                if r.ImGui_Selectable(ctx, f, sel) then
                                    settings.timesig_font_name = f
                                    RebuildSectionFonts()
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        if r.ImGui_BeginCombo(ctx, "TimeSig Size", tostring(settings.timesig_font_size)) then
                            for _, size in ipairs(text_sizes) do
                                local sel = (settings.timesig_font_size == size)
                                if r.ImGui_Selectable(ctx, tostring(size), sel) then
                                    settings.timesig_font_size = size
                                    RebuildSectionFonts()
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        DrawXYControls('timesig_x','timesig_y', main_window_width, main_window_height, { step = 'pixel' })

                        if r.ImGui_Button(ctx, "Reset##timesigPos") then
                            settings.timesig_x = 0.75
                            settings.timesig_y = 0.02
                        end
                        r.ImGui_SameLine(ctx)
                    end
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Envelope", "env_open") then
                    rv, settings.show_env_button = r.ImGui_Checkbox(ctx, "Show##env", settings.show_env_button)
                    if settings.show_env_button then
                        DrawXYControls('env_x','env_y', main_window_width, main_window_height, { step = 'pixel' })
                    end
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("TapTempo", "taptempo_open") then
                    rv, settings.show_taptempo = r.ImGui_Checkbox(ctx, "Show##taptempo", settings.show_taptempo)
                    if settings.show_taptempo then
                        DrawXYControls('taptempo_x','taptempo_y', main_window_width, main_window_height, { step = 'pixel' })

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
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Settings", "settings_open") then
                    rv, settings.show_settings_button = r.ImGui_Checkbox(ctx, "Show##settingsBtn", settings.show_settings_button)
                    if settings.show_settings_button then
                        DrawXYControls('settings_x','settings_y', main_window_width, main_window_height, { step = 'pixel' })
                    end
                end
                r.ImGui_Separator(ctx)
                if ShowSectionHeader("Local Time", "localtime_open") then
                    rv, settings.show_local_time = r.ImGui_Checkbox(ctx, "Show##localtime", settings.show_local_time)
                    if settings.show_local_time then
                        if r.ImGui_BeginCombo(ctx, "Local Time Font", settings.local_time_font_name) then
                            for _, f in ipairs(fonts) do
                                local sel = (settings.local_time_font_name == f)
                                if r.ImGui_Selectable(ctx, f, sel) then
                                    settings.local_time_font_name = f
                                    RebuildSectionFonts()
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        if r.ImGui_BeginCombo(ctx, "Local Time Size", tostring(settings.local_time_font_size)) then
                            for _, size in ipairs(text_sizes) do
                                local sel = (settings.local_time_font_size == size)
                                if r.ImGui_Selectable(ctx, tostring(size), sel) then
                                    settings.local_time_font_size = size
                                    RebuildSectionFonts()
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        local changed = false
                        DrawXYControls('local_time_x','local_time_y', main_window_width, main_window_height, { step = 'pixel' })

                        if r.ImGui_Button(ctx, "Reset##ltime") then
                            settings.local_time_x = 0.50
                            settings.local_time_y = 0.02
                        end

                        local flags = r.ImGui_ColorEditFlags_NoInputs()
                        local rv_col, new_col = r.ImGui_ColorEdit4(ctx, "Color##localtime", settings.local_time_color or 0xFFFFFFFF, flags)
                        if rv_col then settings.local_time_color = new_col end
                    end
                end
                r.ImGui_EndTabItem(ctx)
            end
            
            if r.ImGui_BeginTabItem(ctx, "Custom Buttons") then
                local rv
                
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

                r.ImGui_Spacing(ctx)
                r.ImGui_PushFont(ctx, settings_ui_font_small, SETTINGS_UI_FONT_SMALL_SIZE)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xA0A0A0FF)
                r.ImGui_TextWrapped(ctx, "Global Offset is saved in the Transport preset. Re-save your Transport preset to keep these changes.")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_PopFont(ctx)

                -- UX: hover tooltip toggle for custom buttons
                r.ImGui_Separator(ctx)
                local _rv
                _rv, settings.show_custom_button_tooltip = r.ImGui_Checkbox(ctx, "Show action tooltip on hover", settings.show_custom_button_tooltip)

                ButtonEditor.ShowEditorInline(ctx, CustomButtons, settings)
                r.ImGui_EndTabItem(ctx)
            end
            
            if r.ImGui_BeginTabItem(ctx, "Images & Graphics") then
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
                r.ImGui_EndTabItem(ctx)
            end
            
            if r.ImGui_BeginTabItem(ctx, "Widget Manager") then
                WidgetManager.RenderWidgetManagerUI(ctx, script_path)
                r.ImGui_EndTabItem(ctx)
            end
            
            r.ImGui_EndTabBar(ctx)
        end
        
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, "Reset to Defaults") then
            ResetSettings()
        end


        r.ImGui_PopStyleVar(ctx, 7)  
        r.ImGui_PopStyleColor(ctx, 13)
        r.ImGui_PopFont(ctx)
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx) 
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
    
    if r.ImGui_Button(ctx, "ENV") or r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "AutomationMenu")
    end
        StoreElementRect("env")

    if current_mode ~= "No override" then
        r.ImGui_PopStyleColor(ctx)
    end

    if r.ImGui_BeginPopup(ctx, "AutomationMenu") then
        local envelopes_visible = r.GetToggleCommandState(40926) == 1
        if r.ImGui_MenuItem(ctx, "Toggle all active track envelopes", nil, envelopes_visible) then
            r.Main_OnCommand(40926, 0)
        end
        r.ImGui_Separator(ctx)
        for _, mode in ipairs(AUTOMATION_MODES) do
            if r.ImGui_MenuItem(ctx, mode.name, nil, current_mode == mode.name) then
                r.Main_OnCommand(mode.command, 0)
            end
        end
        r.ImGui_EndPopup(ctx)
    end
end

function ShowPlaySyncMenu()
    if settings.edit_mode then return end
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
    if settings.edit_mode then return end
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
    local allow_input = not settings.edit_mode

    local tfsize = settings.transport_font_size or settings.font_size
    local buttonSize = tfsize * 1.1
    local spacing = math.floor(buttonSize * 0.2)
    local count = 7
    local perButtonWidth_graphic = buttonSize
    local perButtonWidth_text = buttonSize * 1.7 -- keep in sync with Settings centering logic
    local total_width = (settings.use_graphic_buttons and perButtonWidth_graphic or perButtonWidth_text) * count + spacing * (count - 1)
    local base_x_px = settings.center_transport and math.max(0, math.floor((main_window_width - total_width) / 2)) or math.floor(settings.transport_x * main_window_width)
    local base_y_px = math.floor(settings.transport_y * main_window_height)

    local drawList = r.ImGui_GetWindowDrawList(ctx)
    if font_transport then r.ImGui_PushFont(ctx, font_transport, settings.transport_font_size or settings.font_size) end

    group_min_x, group_min_y, group_max_x, group_max_y = nil, nil, nil, nil

    local function update_group_bounds()
        local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
        local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
        if group_min_x then
            group_min_x = math.min(group_min_x, min_x)
            group_min_y = math.min(group_min_y, min_y)
            group_max_x = math.max(group_max_x, max_x)
            group_max_y = math.max(group_max_y, max_y)
        else
            group_min_x, group_min_y, group_max_x, group_max_y = min_x, min_y, max_x, max_y
        end
    end

    if settings.use_graphic_buttons then
        local pos_x, pos_y
        -- 1) <<
        r.ImGui_SetCursorPosX(ctx, base_x_px + 0 * (perButtonWidth_graphic + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "<<", buttonSize, buttonSize)
            if allow_input and clicked then r.Main_OnCommand(GOTO_START, 0) end
        end
        update_group_bounds()
        if settings.use_custom_rewind_image and transport_custom_images.rewind and r.ImGui_ValidatePtr(transport_custom_images.rewind, 'ImGui_Image*') then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            local scaled_size = buttonSize * settings.custom_rewind_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.rewind, pos_x, pos_y, pos_x + scaled_size, pos_y + scaled_size, uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, settings.transport_normal)
            graphics.DrawArrows(pos_x-10, pos_y, buttonSize, false)
        end

        r.ImGui_SetCursorPosX(ctx, base_x_px + 1 * (perButtonWidth_graphic + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local play_state = r.GetPlayState() & 1 == 1
        local play_color = play_state and settings.play_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "PLAY", buttonSize, buttonSize)
            if allow_input and clicked then r.Main_OnCommand(PLAY_COMMAND, 0) end
        end
        update_group_bounds()
        ShowPlaySyncMenu()
        if settings.use_custom_play_image and transport_custom_images.play and r.ImGui_ValidatePtr(transport_custom_images.play, 'ImGui_Image*') then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if play_state then uv_x = 0.66 end
            local scaled_size = buttonSize * settings.custom_play_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.play, pos_x, pos_y, pos_x + scaled_size, pos_y + scaled_size, uv_x, 0, uv_x + 0.33, 1)
        else
            local play_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, play_color)
            play_graphics.DrawPlay(pos_x, pos_y, buttonSize)
        end

        r.ImGui_SetCursorPosX(ctx, base_x_px + 2 * (perButtonWidth_graphic + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "STOP", buttonSize, buttonSize)
            if allow_input and clicked then r.Main_OnCommand(STOP_COMMAND, 0) end
        end
        update_group_bounds()
        if settings.use_custom_stop_image and transport_custom_images.stop and r.ImGui_ValidatePtr(transport_custom_images.stop, 'ImGui_Image*') then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            local scaled_size = buttonSize * settings.custom_stop_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.stop, pos_x, pos_y, pos_x + scaled_size, pos_y + scaled_size, uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, settings.transport_normal)
            graphics.DrawStop(pos_x, pos_y, buttonSize)
        end

        r.ImGui_SetCursorPosX(ctx, base_x_px + 3 * (perButtonWidth_graphic + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local pause_state = r.GetPlayState() & 2 == 2
        local pause_color = pause_state and settings.pause_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "PAUSE", buttonSize, buttonSize)
            if allow_input and clicked then r.Main_OnCommand(PAUSE_COMMAND, 0) end
        end
        update_group_bounds()
        if settings.use_custom_pause_image and transport_custom_images.pause and r.ImGui_ValidatePtr(transport_custom_images.pause, 'ImGui_Image*') then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if pause_state then uv_x = 0.66 end
            local scaled_size = buttonSize * settings.custom_pause_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.pause, pos_x, pos_y, pos_x + scaled_size, pos_y + scaled_size, uv_x, 0, uv_x + 0.33, 1)
        else
            local pause_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, pause_color)
            pause_graphics.DrawPause(pos_x, pos_y, buttonSize)
        end

        r.ImGui_SetCursorPosX(ctx, base_x_px + 4 * (perButtonWidth_graphic + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        local rec_color = (rec_state == 1) and settings.record_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "REC", buttonSize, buttonSize)
            if allow_input and clicked then r.Main_OnCommand(RECORD_COMMAND, 0) end
        end
        update_group_bounds()
        ShowRecordMenu()
        if settings.use_custom_record_image and transport_custom_images.record and r.ImGui_ValidatePtr(transport_custom_images.record, 'ImGui_Image*') then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if rec_state == 1 then uv_x = 0.66 end
            local scaled_size = buttonSize * settings.custom_record_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.record, pos_x, pos_y, pos_x + scaled_size, pos_y + scaled_size, uv_x, 0, uv_x + 0.33, 1)
        else
            local rec_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, rec_color)
            rec_graphics.DrawRecord(pos_x, pos_y, buttonSize)
        end

        r.ImGui_SetCursorPosX(ctx, base_x_px + 5 * (perButtonWidth_graphic + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        local loop_color = (repeat_state == 1) and settings.loop_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "LOOP", buttonSize, buttonSize)
            if allow_input and clicked then r.Main_OnCommand(REPEAT_COMMAND, 0) end
        end
        update_group_bounds()
        if settings.use_custom_loop_image and transport_custom_images.loop and r.ImGui_ValidatePtr(transport_custom_images.loop, 'ImGui_Image*') then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if repeat_state == 1 then uv_x = 0.66 end
            local scaled_size = buttonSize * settings.custom_loop_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.loop, pos_x, pos_y, pos_x + scaled_size, pos_y + scaled_size, uv_x, 0, uv_x + 0.33, 1)
        else
            local loop_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, loop_color)
            loop_graphics.DrawLoop(pos_x, pos_y, buttonSize)
        end

        r.ImGui_SetCursorPosX(ctx, base_x_px + 6 * (perButtonWidth_graphic + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, ">>", buttonSize, buttonSize)
            if allow_input and clicked then r.Main_OnCommand(GOTO_END, 0) end
        end
        update_group_bounds()
        if settings.use_custom_forward_image and transport_custom_images.forward and r.ImGui_ValidatePtr(transport_custom_images.forward, 'ImGui_Image*') then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            local scaled_size = buttonSize * settings.custom_forward_image_size * settings.custom_image_size
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.forward, pos_x, pos_y, pos_x + scaled_size, pos_y + scaled_size, uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, buttonSize, settings.transport_normal)
            graphics.DrawArrows(pos_x+5, pos_y, buttonSize, true)
        end

    else
        local clicked
        local button_w = perButtonWidth_text

        r.ImGui_SetCursorPosX(ctx, base_x_px + 0 * (button_w + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        clicked = r.ImGui_Button(ctx, "<<", button_w, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(GOTO_START, 0) end
        update_group_bounds()

        r.ImGui_SetCursorPosX(ctx, base_x_px + 1 * (button_w + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local play_state = r.GetPlayState() & 1 == 1
        if play_state then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.play_active) end
        clicked = r.ImGui_Button(ctx, "PLAY", button_w, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(PLAY_COMMAND, 0) end
        if play_state then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()
        ShowPlaySyncMenu()

        r.ImGui_SetCursorPosX(ctx, base_x_px + 2 * (button_w + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        clicked = r.ImGui_Button(ctx, "STOP", button_w, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(STOP_COMMAND, 0) end
        update_group_bounds()

        r.ImGui_SetCursorPosX(ctx, base_x_px + 3 * (button_w + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local pause_state = r.GetPlayState() & 2 == 2
        if pause_state then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.pause_active) end
        clicked = r.ImGui_Button(ctx, "PAUSE", button_w, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(PAUSE_COMMAND, 0) end
        if pause_state then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()

        r.ImGui_SetCursorPosX(ctx, base_x_px + 4 * (button_w + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        if rec_state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.record_active) end
        clicked = r.ImGui_Button(ctx, "REC", button_w, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(RECORD_COMMAND, 0) end
        if rec_state == 1 then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()
        ShowRecordMenu()

        r.ImGui_SetCursorPosX(ctx, base_x_px + 5 * (button_w + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        if repeat_state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.loop_active) end
        clicked = r.ImGui_Button(ctx, "LOOP", button_w, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(REPEAT_COMMAND, 0) end
        if repeat_state == 1 then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()

        r.ImGui_SetCursorPosX(ctx, base_x_px + 6 * (button_w + spacing))
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        clicked = r.ImGui_Button(ctx, ">>", button_w, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(GOTO_END, 0) end
        update_group_bounds()
    end

    if font_transport then r.ImGui_PopFont(ctx) end
    if group_min_x then
        StoreElementRectUnion("transport", group_min_x, group_min_y, group_max_x, group_max_y)
    end
end

function DrawTransportGraphics(drawList, x, y, size, color)

    local function DrawPlay(x, y, size)
        local adjustedSize = size
        local points = {
            x + size * 0.1, y + size * 0.1,
            x + size * 0.1, y + adjustedSize,
            x + adjustedSize, y + size / 2
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
            x + size * 0.1, y + size * 0.1,
            x + adjustedSize, y + adjustedSize,
            color)
    end

    local function DrawPause(x, y, size)
        local adjustedSize = size
        local barWidth = adjustedSize / 3
        r.ImGui_DrawList_AddRectFilled(drawList,
            x + size * 0.1, y + size * 0.1,
            x + size * 0.1 + barWidth, y + adjustedSize,
            color)
        r.ImGui_DrawList_AddRectFilled(drawList,
            x + adjustedSize - barWidth, y + size * 0.1,
            x + adjustedSize, y + adjustedSize,
            color)
    end

    local function DrawRecord(x, y, size)
        local adjustedSize = size * 1.1
        r.ImGui_DrawList_AddCircleFilled(drawList,
            x + size / 2, y + size / 2,
            adjustedSize / 2,
            color)
    end

    local function DrawLoop(x, y, size)
        local adjustedSize = size
        r.ImGui_DrawList_AddCircle(drawList,
            x + size / 2, y + size / 2,
            adjustedSize / 2,
            color, 32, 2)

        local arrowSize = adjustedSize / 4
        local ax = x + size / 12
        local ay = y + size / 2
        r.ImGui_DrawList_AddTriangleFilled(drawList,
            ax, ay,
            ax - arrowSize / 2, ay + arrowSize / 2,
            ax + arrowSize / 2, ay + arrowSize / 2,
            color)
    end

    local function DrawArrows(x, y, size, forward)
        local arrowSize = size / 1.8
        local spacing = size / 6
        local yCenter = y + size / 2

        for i = 0, 1 do
            local startX = x + (i * (arrowSize + spacing))
            local points

            if forward then
                points = {
                    startX, yCenter - arrowSize / 2.2,
                    startX, yCenter + arrowSize / 2.2,
                    startX + arrowSize, yCenter
                }
            else
                points = {
                    startX + arrowSize, yCenter - arrowSize / 2,
                    startX + arrowSize, yCenter + arrowSize / 2,
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
    if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 0) then
        r.Main_OnCommand(40521, 0)
    end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, 'click to reset')
        r.ImGui_EndTooltip(ctx)
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosY(ctx, settings.playrate_y * main_window_height)
    r.ImGui_PushItemWidth(ctx, 80)
    local rv, new_rate = r.ImGui_SliderDouble(ctx, '##PlayRateSlider', current_rate, 0.25, 4.0, "%.2fx")
    StoreElementRect("playrate")

    if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "PlayRateMenu")
    end

    if r.ImGui_BeginPopup(ctx, "PlayRateMenu") then
        if r.ImGui_MenuItem(ctx, "Set playrate to 1.0") then
            r.Main_OnCommand(40521, 0)
        end
        local preserve_pitch_on = r.GetToggleCommandState(40671) == 1
        if r.ImGui_MenuItem(ctx, "Toggle preserve pitch in audio items", nil, preserve_pitch_on) then
            r.Main_OnCommand(40671, 0)
        end
        r.ImGui_EndPopup(ctx)
    end

    if rv and (not settings.edit_mode) then
        r.CSurf_OnPlayRateChange(new_rate)
    end

    r.ImGui_PopItemWidth(ctx)
end


function ShowCursorPosition(main_window_width, main_window_height)
    if not settings.show_transport then return end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.cursorpos_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.cursorpos_y * main_window_height)
    local play_state = r.GetPlayState()
    local position = (play_state == 1) and r.GetPlayPosition() or r.GetCursorPosition()
    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = reaper.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end
    local _, measures, cml, fullbeats = reaper.TimeMap2_timeToBeats(0, position)
    measures = measures or 0
    local beatsInMeasure = fullbeats % timesig_num
    local ticks = math.floor((beatsInMeasure - math.floor(beatsInMeasure)) * 960/10)
    local minutes = math.floor(position / 60)
    local seconds = position % 60
    local time_str = string.format("%d:%06.3f", minutes, seconds)
    local mbt_str = string.format("%d.%d.%02d", math.floor(measures+1), math.floor(beatsInMeasure+1), ticks)
    local mode = settings.cursorpos_mode or "both"
    local label
    if mode == "beats" then
        label = mbt_str
    elseif mode == "time" then
        label = time_str
    else
        label = mbt_str .. " | " .. time_str
    end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.button_normal)
    if r.ImGui_Button(ctx, label) and r.ImGui_IsItemClicked(ctx, 1) then
    end
    StoreElementRect("cursorpos")
    if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "CursorPosModeMenu")
    end
    r.ImGui_PopStyleColor(ctx)
    if r.ImGui_BeginPopup(ctx, "CursorPosModeMenu") then
        if r.ImGui_MenuItem(ctx, "Beats (MBT)", nil, mode=="beats") then settings.cursorpos_mode = "beats" end
        if r.ImGui_MenuItem(ctx, "Time", nil, mode=="time") then settings.cursorpos_mode = "time" end
        if r.ImGui_MenuItem(ctx, "Both", nil, mode=="both") then settings.cursorpos_mode = "both" end
        r.ImGui_EndPopup(ctx)
    end
end

local function SetProjectTempoGlobal(new_tempo)
    if not new_tempo or new_tempo <= 0 then return end
    local proj = 0
    local count = reaper.CountTempoTimeSigMarkers(proj)
    if count == 0 then
        reaper.GetSetProjectInfo(proj, 'TEMPO', new_tempo, true)
    else
        local cursor = reaper.GetCursorPosition()
        local target_index = nil
        local target_timepos, target_measurepos, target_beatpos, target_num, target_denom, target_lineartempo
        for i = 0, count - 1 do
            local ok, timepos, measurepos, beatpos, bpm, num, denom, lineartempo = reaper.GetTempoTimeSigMarker(proj, i)
            if ok then
                if timepos <= cursor then
                    target_index = i
                    target_timepos = timepos
                    target_measurepos = measurepos
                    target_beatpos = beatpos
                    target_num = num
                    target_denom = denom
                    target_lineartempo = lineartempo
                else
                    break 
                end
            end
        end
        if not target_index then
            local ok, timepos, measurepos, beatpos, bpm, num, denom, lineartempo = reaper.GetTempoTimeSigMarker(proj, 0)
            if ok then
                target_index = 0
                target_timepos = timepos
                target_measurepos = measurepos
                target_beatpos = beatpos
                target_num = num
                target_denom = denom
                target_lineartempo = lineartempo
            end
        end
        if target_index then
            reaper.SetTempoTimeSigMarker(proj, target_index, target_timepos, target_measurepos, target_beatpos, new_tempo, target_num, target_denom, target_lineartempo)
        end
    end
    if reaper.CSurf_OnTempoChange then reaper.CSurf_OnTempoChange(new_tempo) end
    reaper.UpdateTimeline()
end

function ShowTempo(main_window_width, main_window_height)
    if not settings.show_tempo then return end
    local tempo = reaper.Master_GetTempo()

    reaper.ImGui_SetCursorPosX(ctx, settings.tempo_x * main_window_width)
    reaper.ImGui_SetCursorPosY(ctx, settings.tempo_y * main_window_height)

    reaper.ImGui_PushItemWidth(ctx, settings.font_size * 4)
    local tempo_text = string.format("%.1f", tempo)
    if settings.tempo_button_color then
        local hov = settings.tempo_button_color_hover or settings.tempo_button_color
        local act = hov
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), settings.tempo_button_color)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hov)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), act)
    end
    local play_state = reaper.GetPlayState()
    local position = (play_state == 1) and reaper.GetPlayPosition() or reaper.GetCursorPosition()
    local retval, pos, measurepos, beatpos, bpm_marker, timesig_num, timesig_denom = reaper.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4,4 end
    local _, measures, cml, fullbeats = reaper.TimeMap2_timeToBeats(0, position)
    measures = measures or 0
    local beatsInMeasure = fullbeats % timesig_num
    local ticks = math.floor((beatsInMeasure - math.floor(beatsInMeasure)) * 960/10)
    local mbt_str = string.format("%d.%d.%02d", math.floor(measures+1), math.floor(beatsInMeasure+1), ticks)
    local combined_mbt = mbt_str
    if font_tempo then reaper.ImGui_PushFont(ctx, font_tempo, settings.tempo_font_size or settings.font_size) end
    reaper.ImGui_Button(ctx, tempo_text)
    StoreElementRect("tempo")
    if font_tempo then reaper.ImGui_PopFont(ctx) end
    local tempo_button_left_click = reaper.ImGui_IsItemClicked(ctx, 0)
    local tempo_button_right_click = reaper.ImGui_IsItemClicked(ctx, 1)
    if settings.tempo_button_color then
        reaper.ImGui_PopStyleColor(ctx, 3)
    end

    -- Scroll wheel on the tempo button to adjust BPM (when not in edit mode)
    if (not settings.edit_mode) and reaper.ImGui_IsItemHovered(ctx) then
        local wheel = reaper.ImGui_GetMouseWheel(ctx) or 0
        if wheel ~= 0 then
            local delta = (wheel > 0) and math.ceil(wheel) or math.floor(wheel)
            local new_tempo = math.max(1, math.min(590, math.floor(tempo + delta + 0.5)))
            if reaper.CSurf_OnTempoChange then
                reaper.CSurf_OnTempoChange(new_tempo)
            else
                reaper.GetSetProjectInfo(0, 'TEMPO', new_tempo, true)
            end
        end
    end


    if (not settings.edit_mode) and tempo_button_left_click then
        tempo_dragging = true
        tempo_start_value = tempo
        tempo_accumulated_delta = 0

        if reaper.GetMousePosition then
            tempo_mouse_anchor_x, tempo_mouse_anchor_y = reaper.GetMousePosition()
            tempo_last_mouse_y = tempo_mouse_anchor_y
        end

        if reaper.JS_Mouse_SetCursor then
            reaper.JS_Mouse_SetCursor(reaper.JS_Mouse_LoadCursor(0)) -- IDC_BLANK
        end
    end

    if (not settings.edit_mode) and tempo_dragging and reaper.GetMousePosition then
        local _, current_mouse_y = reaper.GetMousePosition()
if tempo_last_mouse_y then
    local mouse_delta_y = current_mouse_y - tempo_last_mouse_y
    if math.abs(mouse_delta_y) > 0 then
        local sensitivity = 5 -- pixels per BPM
    tempo_accumulated_delta = tempo_accumulated_delta + (-mouse_delta_y / sensitivity)
    local adjusted_tempo = math.floor(tempo_start_value + tempo_accumulated_delta + 0.5)
    adjusted_tempo = math.max(1, math.min(590, adjusted_tempo))
    reaper.CSurf_OnTempoChange(adjusted_tempo)
    end
end
        if reaper.JS_Mouse_SetPosition and tempo_mouse_anchor_x then
            reaper.JS_Mouse_SetPosition(tempo_mouse_anchor_x, tempo_mouse_anchor_y)
            tempo_last_mouse_y = tempo_mouse_anchor_y
        else
            tempo_last_mouse_y = current_mouse_y
        end
    end

    if (not settings.edit_mode) and not reaper.ImGui_IsMouseDown(ctx, 0) then
        if tempo_dragging then
            if reaper.JS_Mouse_SetCursor then
                reaper.JS_Mouse_SetCursor(reaper.JS_Mouse_LoadCursor(32512)) -- IDC_ARROW
            end
            if tempo_mouse_anchor_x and tempo_mouse_anchor_y and reaper.JS_Mouse_SetPosition then
                reaper.JS_Mouse_SetPosition(tempo_mouse_anchor_x, tempo_mouse_anchor_y)
            end
        end
        tempo_dragging = false
        tempo_last_mouse_y = nil
        tempo_mouse_anchor_x, tempo_mouse_anchor_y = nil, nil
    end

    if (not settings.edit_mode) and tempo_button_right_click then
        reaper.ImGui_OpenPopup(ctx, "TempoMenu")
    end

    if (not settings.edit_mode) and reaper.ImGui_BeginPopup(ctx, "TempoMenu") then
        reaper.ImGui_Text(ctx, "Set Tempo:")
        reaper.ImGui_PushItemWidth(ctx, 100)
        local popup_tempo = tempo
        local rv_popup, new_popup_tempo = reaper.ImGui_InputDouble(ctx, "##PopupTempo", popup_tempo, 1, 10, "%.1f")
        if rv_popup then
            new_popup_tempo = math.max(2, math.min(500, new_popup_tempo))
            SetProjectTempoGlobal(new_popup_tempo)
        end
        reaper.ImGui_PopItemWidth(ctx)

        reaper.ImGui_Separator(ctx)

    settings.tempo_presets = settings.tempo_presets or {60,80,100,120,140,160,180}
    table.sort(settings.tempo_presets, function(a,b) return a<b end)
        local i = 1
    while i <= #settings.tempo_presets do
        local bpm_val = tonumber(settings.tempo_presets[i])
            if bpm_val then
                if reaper.ImGui_MenuItem(ctx, string.format("%g BPM", bpm_val)) then
                    SetProjectTempoGlobal(bpm_val)
                end
            end
            i=i+1
        end

        if not editing_tempo_presets then
            editing_tempo_presets = {}
            for ii,vv in ipairs(settings.tempo_presets) do editing_tempo_presets[ii]=vv end
        end
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Text(ctx, "Edit Presets")
            local remove_index = nil
            for idx, v in ipairs(editing_tempo_presets) do
                reaper.ImGui_PushID(ctx, idx)
                reaper.ImGui_PushItemWidth(ctx, 60)
                local changed, new_val = reaper.ImGui_InputDouble(ctx, "##tp", v, 0,0,"%.2f")
                reaper.ImGui_PopItemWidth(ctx)
                reaper.ImGui_SameLine(ctx)
                if reaper.ImGui_Button(ctx, "X") then remove_index = idx end
                if changed then
                    if new_val and new_val>=2 and new_val<=500 then
                        editing_tempo_presets[idx] = new_val
                    elseif new_val and new_val < 2 then
                    end
                end
                reaper.ImGui_PopID(ctx)
            end
            if remove_index then table.remove(editing_tempo_presets, remove_index) end
            reaper.ImGui_Separator(ctx)
            temp_new_preset_val = temp_new_preset_val or 120.0
            reaper.ImGui_PushItemWidth(ctx, 80)
            local add_changed, add_val = reaper.ImGui_InputDouble(ctx, "##addPreset", temp_new_preset_val, 0,0,"%.2f")
            if add_changed then temp_new_preset_val = add_val end
            reaper.ImGui_PopItemWidth(ctx); reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Add") then
                if add_val and add_val>=2 and add_val<=500 then
                    local exists=false; for _,v in ipairs(editing_tempo_presets) do if math.abs(v-add_val)<0.0001 then exists=true break end end
                    if not exists then table.insert(editing_tempo_presets, add_val) end
                end
            end
            reaper.ImGui_Separator(ctx)
            if reaper.ImGui_Button(ctx, "Save Presets") then
                local cleaned = {}
                local seen = {}
                for _,val in ipairs(editing_tempo_presets) do
                    if type(val)=="number" and val>=2 and val<=500 then
                        local key = string.format("%.3f", val)
                        if not seen[key] then table.insert(cleaned, val); seen[key]=true end
                    end
                end
                table.sort(cleaned, function(a,b) return a<b end)
                settings.tempo_presets = cleaned
                SaveSettings()
                editing_tempo_presets = nil
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Reset Defaults") then
                editing_tempo_presets = {60,80,100,120,140,160,180}
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Cancel") then editing_tempo_presets = nil end

        reaper.ImGui_Separator(ctx)

        if reaper.ImGui_MenuItem(ctx, "Reset to 120 BPM") then
            SetProjectTempoGlobal(120.0)
        end

        reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_PopItemWidth(ctx)
end

function ShowTimeSignature(main_window_width, main_window_height)
    if not settings.show_timesig_button then return end 
    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_SetCursorPosX(ctx, (settings.timesig_x or (settings.tempo_x + 0.05)) * main_window_width)
    reaper.ImGui_SetCursorPosY(ctx, (settings.timesig_y or settings.tempo_y) * main_window_height)
    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = reaper.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end

    if font_timesig then reaper.ImGui_PushFont(ctx, font_timesig, settings.timesig_font_size or settings.font_size) end
    local ts_text = string.format("%d|%d", timesig_num, timesig_denom)
    if reaper.ImGui_Button(ctx, ts_text) or reaper.ImGui_IsItemClicked(ctx,1) then
        reaper.ImGui_OpenPopup(ctx, "TimeSigPopup")
    end
    StoreElementRect("timesig")
    if font_timesig then reaper.ImGui_PopFont(ctx) end
    if reaper.ImGui_BeginPopup(ctx, "TimeSigPopup") then
        reaper.ImGui_Text(ctx, "Set Time Signature")
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_PushItemWidth(ctx, 60)
        local rv_num, new_num = reaper.ImGui_InputInt(ctx, "Numerator", timesig_num, 0, 0)
        local rv_denom, new_denom = reaper.ImGui_InputInt(ctx, "Denominator", timesig_denom, 0, 0)
        reaper.ImGui_PopItemWidth(ctx)
        if rv_num or rv_denom then
            reaper.Undo_BeginBlock()
            local num_to_set = rv_num and new_num>0 and new_num or timesig_num
            local denom_to_set = rv_denom and new_denom>0 and new_denom or timesig_denom
            local _, measures = reaper.TimeMap2_timeToBeats(0, 0)
            local ptx_in_effect = reaper.FindTempoTimeSigMarker(0, 0)
            reaper.SetTempoTimeSigMarker(0, -1, -1, measures, 0, -1, num_to_set, denom_to_set, true)
            reaper.GetSetTempoTimeSigMarkerFlag(0, ptx_in_effect + 1, 1|2|16, true)
            reaper.Undo_EndBlock("Change time signature", 1|4|8)
        end
        if reaper.ImGui_Button(ctx, "Close") then reaper.ImGui_CloseCurrentPopup(ctx) end
        reaper.ImGui_EndPopup(ctx)
    end
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
        display_text = string.format("Selection: %s | %s | %s | %s | %s | %s",
            start_midi, sec_format,
            end_midi, end_format,
            len_midi, len_format)
    elseif settings.show_beats_selection then
        display_text = string.format("Selection: %s | %s | %s",
            start_midi, end_midi, len_midi)
    elseif settings.show_time_selection then
        display_text = string.format("Selection: %s | %s | %s",
            sec_format, end_format, len_format)
    end

    if display_text == "" then
        r.ImGui_Button(ctx, "##TimeSelectionEmpty")
    else
        r.ImGui_Button(ctx, display_text)
    end
    StoreElementRect("timesel")
    

    if not settings.timesel_border then
        r.ImGui_PopStyleVar(ctx)
    end
    
    if settings.timesel_invisible then
        r.ImGui_PopStyleColor(ctx, 3)
    else
        r.ImGui_PopStyleColor(ctx)
    end
end

local last_local_time_sec = -1
local cached_local_time = ""
local session_start_time = os.time()
local show_session_time = false

local function format_session_time(seconds)
    local h = math.floor(seconds / 3600)
    local m = math.floor((seconds % 3600) / 60)
    local s = seconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

local function ShowLocalTime(main_window_width, main_window_height)
    if not settings.show_local_time then return end
    local t = os.time()
    local display_text
    if show_session_time then
        local elapsed = t - session_start_time
        display_text = format_session_time(elapsed)
    else
        if t ~= last_local_time_sec then
            cached_local_time = os.date("%H:%M:%S", t)
            last_local_time_sec = t
        end
        display_text = cached_local_time
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, (settings.local_time_x or 0.5) * main_window_width)
    r.ImGui_SetCursorPosY(ctx, (settings.local_time_y or 0.02) * main_window_height)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.local_time_color or 0xFFFFFFFF)
    local tw, th = r.ImGui_CalcTextSize(ctx, display_text)
    local pad = 6
    r.ImGui_InvisibleButton(ctx, "##LocalTimeHit", tw + pad * 2, th + pad * 2)
    StoreElementRect("localtime")
    local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local tx = min_x + (max_x - min_x - tw) * 0.5
    local ty = min_y + (max_y - min_y - th) * 0.5
    if font_localtime then r.ImGui_PushFont(ctx, font_localtime, settings.local_time_font_size or settings.font_size) end
    r.ImGui_DrawList_AddText(dl, tx, ty, settings.local_time_color or 0xFFFFFFFF, display_text)
    if font_localtime then r.ImGui_PopFont(ctx) end
    r.ImGui_PopStyleColor(ctx)
    if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 0) then
        show_session_time = not show_session_time
    end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, show_session_time and "Click to show local clock" or "Click to show session elapsed time")
    end
end


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
    
    r.ImGui_SetCursorPosX(ctx, settings.taptempo_x * main_window_width)
    r.ImGui_SetCursorPosY(ctx, settings.taptempo_y * main_window_height)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.button_normal)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.button_hovered)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.button_active)
    
    local tapped = r.ImGui_Button(ctx, settings.tap_button_text, settings.tap_button_width, settings.tap_button_height)
    StoreElementRect("taptempo")
    if tapped then
        local current_time = r.time_precise()
        if last_tap_time > 0 then
            local tap_interval = current_time - last_tap_time
            tap_z = tap_z + 1
            if tap_z > settings.tap_input_limit then tap_z = 1 end
            tap_times[tap_z] = 60 / tap_interval
            tap_average_current = average(tap_times)
            
            if settings.set_tempo_on_tap and tap_average_current > 0 then
                SetProjectTempoGlobal(tap_average_current)
            end
        end
        last_tap_time = current_time
    end
    
    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "TapTempoMenu")
    end
    
    r.ImGui_PopStyleColor(ctx, 3)
    
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

    if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "TapTempoMenu")
    end
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
                SetProjectTempoGlobal(tap_average_current / 2)
            end
            if r.ImGui_MenuItem(ctx, "Set Double Tempo") then
                SetProjectTempoGlobal(tap_average_current * 2)
            end
        end
        r.ImGui_EndPopup(ctx)
    end
end

function Main()
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
    ShowLocalTime(main_window_width, main_window_height)
        CustomButtons.x_offset = settings.custom_buttons_x_offset
    CustomButtons.y_offset = settings.custom_buttons_y_offset

    ButtonRenderer.RenderButtons(ctx, CustomButtons, settings)
        CustomButtons.CheckForCommandPick()
        ShowTempo(main_window_width, main_window_height)
        ShowTimeSignature(main_window_width, main_window_height)
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
            StoreElementRect("settings")
            r.ImGui_PopFont(ctx)
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_PopStyleColor(ctx, 3)
        end
        if settings.edit_mode then
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local grid_px = settings.edit_grid_size_px or 16
            local snap = settings.edit_snap_to_grid
            local wx, wy = r.ImGui_GetWindowPos(ctx)
            local ww, wh = r.ImGui_GetWindowSize(ctx)
            local function mouse_in_rect(mx, my, x1, y1, x2, y2)
                return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
            end
            local function overlay_rect(name, sx1, sy1, sx2, sy2, ondrag)
                if not sx1 then return end
                local fill = 0x44AAFF22
                local border = 0x44AAFFAA
                r.ImGui_DrawList_AddRectFilled(dl, sx1, sy1, sx2, sy2, fill)
                r.ImGui_DrawList_AddRect(dl, sx1, sy1, sx2, sy2, border)
                local mx, my = r.ImGui_GetMousePos(ctx)
                if r.ImGui_IsMouseClicked(ctx, 0) and mouse_in_rect(mx, my, sx1, sy1, sx2, sy2) then
                    overlay_drag_active = name
                    overlay_drag_last_x, overlay_drag_last_y = mx, my
                    overlay_drag_moved = false
                end
                if overlay_drag_active == name and r.ImGui_IsMouseDown(ctx, 0) then
                    local dx_px = mx - (overlay_drag_last_x or mx)
                    local dy_px = my - (overlay_drag_last_y or my)
                    if snap then
                        dx_px = math.floor((dx_px + grid_px/2) / grid_px) * grid_px
                        dy_px = math.floor((dy_px + grid_px/2) / grid_px) * grid_px
                    end
                    if dx_px ~= 0 or dy_px ~= 0 then
                        ondrag(dx_px / ww, dy_px / wh)
                        overlay_drag_last_x, overlay_drag_last_y = mx, my
                        overlay_drag_moved = true
                    end
                end
                if overlay_drag_active == name and r.ImGui_IsMouseReleased(ctx, 0) then
                    overlay_drag_active = nil
                    overlay_drag_last_x, overlay_drag_last_y = nil, nil
                    if overlay_drag_moved then
                        SaveSettings() 
                        overlay_drag_moved = false
                    end
                end
            end
            for _, e in ipairs(Layout.elems) do
                if not e.showFlag or settings[e.showFlag] then
                    local rct = element_rects[e.name]
                    if rct then
                        overlay_rect(e.name, rct.min_x, rct.min_y, rct.max_x, rct.max_y, function(dx, dy)
                            if e.beforeDrag then e.beforeDrag() end
                            Layout.move_frac(dx, dy, e.keyx, e.keyy)
                        end)
                    end
                end
            end
        end
        ShowSettings(main_window_width, main_window_height)

        -- Only open the transport context menu when right-clicking empty space (not over items)
        if r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem())
            and r.ImGui_IsMouseClicked(ctx, 1)
            and not r.ImGui_IsAnyItemHovered(ctx) then
            r.ImGui_OpenPopup(ctx, "TransportContextMenu")
        end
        if r.ImGui_BeginPopup(ctx, "TransportContextMenu") then
            if r.ImGui_MenuItem(ctx, settings.edit_mode and "Disable Edit Mode" or "Enable Edit Mode") then
                settings.edit_mode = not settings.edit_mode
                SaveSettings()
            end
            local changed
            changed, settings.edit_snap_to_grid = r.ImGui_MenuItem(ctx, "Snap to Grid", nil, settings.edit_snap_to_grid or false)
            if changed then SaveSettings() end
            changed, settings.edit_grid_show = r.ImGui_MenuItem(ctx, "Show Grid", nil, settings.edit_grid_show or false)
            if changed then SaveSettings() end
            r.ImGui_Separator(ctx)
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
