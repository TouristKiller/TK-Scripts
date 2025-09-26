-- @description TK_TRANSPORT
-- @author TouristKiller
-- @version 0.6.0
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
local window_flags      = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
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
    -- settings_x removed
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
    -- settings_y removed
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
    settings_text_color = 0xFFFFFFFF,
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

    -- Time Signature button colors
    timesig_button_color        = 0x333333FF,
    timesig_button_color_hover  = 0x444444FF,
    timesig_button_color_active = 0x555555FF,

    -- Envelope (ENV) button colors
    env_button_color            = 0x333333FF,
    env_button_color_hover      = 0x444444FF,
    env_button_color_active     = 0x555555FF,
    -- Optional: when an override mode is active, use loop_active to indicate state by default
    env_override_active_color   = 0x66CC66FF,

    -- Settings tab colors (base color per tab; hover/active are derived)
    tab_color_style     = 0x4AA3FFFF, -- Blue
    tab_color_layout    = 0x66CC66FF, -- Green
    tab_color_scaling   = 0xFFB84DFF, -- Orange
    tab_color_transport = 0xFF6666FF, -- Red
    tab_color_custom    = 0xAA88EEFF, -- Purple
    tab_color_widgets   = 0x66CCCCFF, -- Teal

    -- Visibility settings
    use_graphic_buttons = false,
    show_timesel        = true,
    show_transport      = true,
    show_cursorpos      = true,
    show_tempo          = true,
    show_playrate       = true,
    show_time_selection = true,
    show_beats_selection = true,
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
    graphic_spacing_factor      = 0.2,
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
    { name = "cursorpos",    showFlag = "show_cursorpos",      keyx = "cursorpos_x",  keyy = "cursorpos_y" },
        { name = "localtime",    showFlag = "show_local_time",     keyx = "local_time_x", keyy = "local_time_y" },
        { name = "tempo",        showFlag = "show_tempo",          keyx = "tempo_x",      keyy = "tempo_y" },
        { name = "playrate",     showFlag = "show_playrate",       keyx = "playrate_x",   keyy = "playrate_y" },
        { name = "timesig",      showFlag = "show_timesig_button", keyx = "timesig_x",    keyy = "timesig_y" },
        { name = "env",          showFlag = "show_env_button",     keyx = "env_x",        keyy = "env_y" },
        { name = "timesel",      showFlag = "show_timesel",        keyx = "timesel_x",    keyy = "timesel_y" },
        { name = "taptempo",     showFlag = "show_taptempo",       keyx = "taptempo_x",   keyy = "taptempo_y" },
    }
}
function Layout.move_frac(dx, dy, keyx, keyy)
    settings[keyx] = math.max(0, math.min(1, (settings[keyx] or 0) + dx))
    settings[keyy] = math.max(0, math.min(1, (settings[keyy] or 0) + dy))
end

function Layout.move_pixel(dx_px, dy_px, dx_frac, dy_frac, keyx, keyy, max_width, max_height)
    local pixel_keyx = keyx .. "_px"
    local pixel_keyy = keyy .. "_px"
    
    if settings[pixel_keyx] == nil and settings[keyx] ~= nil then
        settings[pixel_keyx] = math.floor((settings[keyx] or 0) * max_width)
    end
    if settings[pixel_keyy] == nil and settings[keyy] ~= nil then
        settings[pixel_keyy] = math.floor((settings[keyy] or 0) * max_height)
    end
    
    settings[pixel_keyx] = math.max(0, math.min(max_width, (settings[pixel_keyx] or 0) + dx_px))
    settings[pixel_keyy] = math.max(0, math.min(max_height, (settings[pixel_keyy] or 0) + dy_px))
    
    settings[keyx] = settings[pixel_keyx] / math.max(1, max_width)
    settings[keyy] = settings[pixel_keyy] / math.max(1, max_height)
end

local function DrawXYControls(keyx, keyy, main_window_width, main_window_height, opts)
    opts = opts or {}
    local stepType = opts.step or "pixel" 
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
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 2)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "+##"..keyx, 20, 20) then
        if stepType == "percent" then
            settings[keyx] = math.min(1, (settings[keyx] or 0) + percentStep)
        else
            settings[keyx] = math.min(1, (settings[keyx] or 0) + (1 / math.max(1, main_window_width)))
        end
    end
    r.ImGui_PopStyleVar(ctx)
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
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 2)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "+##"..keyy, 20, 20) then
        if stepType == "percent" then
            settings[keyy] = math.min(1, (settings[keyy] or 0) + percentStep)
        else
            settings[keyy] = math.min(1, (settings[keyy] or 0) + (1 / math.max(1, main_window_height)))
        end
    end
    r.ImGui_PopStyleVar(ctx)
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

local function DrawPixelXYControls(keyx, keyy, main_window_width, main_window_height, opts)
    opts = opts or {}
    local pixel_keyx = keyx .. "_px"
    local pixel_keyy = keyy .. "_px"
    
    if settings[pixel_keyx] == nil and settings[keyx] ~= nil then
        settings[pixel_keyx] = math.floor((settings[keyx] or 0) * main_window_width)
    end
    if settings[pixel_keyy] == nil and settings[keyy] ~= nil then
        settings[pixel_keyy] = math.floor((settings[keyy] or 0) * main_window_height)
    end
    
    settings[pixel_keyx] = settings[pixel_keyx] or 0
    settings[pixel_keyy] = settings[pixel_keyy] or 0
    
    local rv
    
    local avail_w, _ = r.ImGui_GetContentRegionAvail(ctx)
    local input_w = 100
    local group_gap = 16
    local spacing_total = 6 * 4  
    local label_w = (r.ImGui_CalcTextSize(ctx, "X")) + (r.ImGui_CalcTextSize(ctx, "Y"))
    local fixed_w = (input_w * 2) + label_w + spacing_total + group_gap
    local remaining = math.max(0, avail_w - fixed_w)
    local default_slider_w = math.max(60, math.floor(remaining / 2))
    default_slider_w = math.min(default_slider_w, 120)
    local slider_w = math.min(default_slider_w, opts.slider_width or default_slider_w)

    r.ImGui_Text(ctx, "X")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, slider_w)
    rv, settings[pixel_keyx] = r.ImGui_SliderInt(ctx, "##"..keyx.."_slider", settings[pixel_keyx], 0, main_window_width, "%d px")
    local x_slider_active = r.ImGui_IsItemActive(ctx) or r.ImGui_IsItemHovered(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, input_w)
    rv, settings[pixel_keyx] = r.ImGui_InputInt(ctx, "##"..keyx.."Input", settings[pixel_keyx])
    if rv then
        settings[pixel_keyx] = math.max(0, math.min(main_window_width, settings[pixel_keyx]))
    end
    local x_input_active = r.ImGui_IsItemActive(ctx) or r.ImGui_IsItemHovered(ctx)
    local x_active = x_slider_active or x_input_active

    r.ImGui_SameLine(ctx)
    r.ImGui_Dummy(ctx, group_gap, 0)
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "Y")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, slider_w)
    rv, settings[pixel_keyy] = r.ImGui_SliderInt(ctx, "##"..keyy.."_slider", settings[pixel_keyy], 0, main_window_height, "%d px")
    local y_slider_active = r.ImGui_IsItemActive(ctx) or r.ImGui_IsItemHovered(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, input_w)
    rv, settings[pixel_keyy] = r.ImGui_InputInt(ctx, "##"..keyy.."Input", settings[pixel_keyy])
    if rv then
        settings[pixel_keyy] = math.max(0, math.min(main_window_height, settings[pixel_keyy]))
    end
    local y_input_active = r.ImGui_IsItemActive(ctx) or r.ImGui_IsItemHovered(ctx)

    settings[keyx] = settings[pixel_keyx] / math.max(1, main_window_width)
    settings[keyy] = settings[pixel_keyy] / math.max(1, main_window_height)
end

local function DrawPixelXYControlsInline(keyx, keyy, main_window_width, main_window_height, opts)
    r.ImGui_SameLine(ctx)
    DrawPixelXYControls(keyx, keyy, main_window_width, main_window_height, opts)
end

local function ScalePosX(px, main_window_width, settings)
    if not px then return nil end
    local ref_w = settings and settings.custom_buttons_ref_width or 0
    local scale_with_w = settings and settings.custom_buttons_scale_with_width
    if scale_with_w and ref_w and ref_w > 0 then
        return (px or 0) * (main_window_width / ref_w)
    end
    return px
end

local function ScalePosY(px, main_window_height, settings)
    if not px then return nil end
    local ref_h = settings and settings.custom_buttons_ref_height or 0
    local scale_with_h = settings and settings.custom_buttons_scale_with_height
    if scale_with_h and ref_h and ref_h > 0 then
        return (px or 0) * (main_window_height / ref_h)
    end
    return px
end

local overlay_drag_active = nil
local overlay_drag_last_x, overlay_drag_last_y = nil, nil
local overlay_drag_moved = false 
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

local function Color_ToRGBA(c)
    local r_ = (c >> 24) & 0xFF
    local g_ = (c >> 16) & 0xFF
    local b_ = (c >> 8) & 0xFF
    local a_ = c & 0xFF
    return r_, g_, b_, a_
end

local function Color_FromRGBA(r_, g_, b_, a_)
    r_ = math.max(0, math.min(255, r_ or 0))
    g_ = math.max(0, math.min(255, g_ or 0))
    b_ = math.max(0, math.min(255, b_ or 0))
    a_ = math.max(0, math.min(255, a_ or 255))
    return ((r_ & 0xFF) << 24) | ((g_ & 0xFF) << 16) | ((b_ & 0xFF) << 8) | (a_ & 0xFF)
end

local function Color_AdjustBrightness(c, factor)
    local r_, g_, b_, a_ = Color_ToRGBA(c)
    r_ = math.floor(r_ * factor + 0.5)
    g_ = math.floor(g_ * factor + 0.5)
    b_ = math.floor(b_ * factor + 0.5)
    return Color_FromRGBA(r_, g_, b_, a_)
end

local function PushTabColors(baseColor)
    local function enum(names)
        for _, sym in ipairs(names) do
            local v = r[sym]
            if v then
                if type(v) == 'function' then
                    local ok, res = pcall(v)
                    if ok then return res end
                else
                    return v
                end
            end
        end
        return nil
    end

    local col_Tab        = enum({'ImGui_Col_Tab','Col_Tab'})
    local col_TabHovered = enum({'ImGui_Col_TabHovered','Col_TabHovered'})
    local col_TabActive  = enum({'ImGui_Col_TabActive','Col_TabActive'})
    local col_TabUnf     = enum({'ImGui_Col_TabUnfocused','Col_TabUnfocused','Col_TabDimmed'})
    local col_TabUnfAct  = enum({'ImGui_Col_TabUnfocusedActive','Col_TabUnfocusedActive'})
    local col_TabDimmed      = enum({'ImGui_Col_TabDimmed','Col_TabDimmed'})
    local col_TabDimmedSel   = enum({'ImGui_Col_TabDimmedSelected','Col_TabDimmedSelected'})
    local col_TabDimmedOver  = enum({'ImGui_Col_TabDimmedSelectedOverline','Col_TabDimmedSelectedOverline'})

    local hovered = Color_AdjustBrightness(baseColor, 1.15)
    local active  = Color_AdjustBrightness(baseColor, 1.30)
    local unf     = Color_AdjustBrightness(baseColor, 0.85)
    local unfAct  = Color_AdjustBrightness(baseColor, 1.00)

    if col_Tab and col_TabHovered and col_TabActive then
        local pushed = 0
        r.ImGui_PushStyleColor(ctx, col_Tab, baseColor); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, col_TabHovered, hovered); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, col_TabActive, active); pushed = pushed + 1
        if col_TabUnf then r.ImGui_PushStyleColor(ctx, col_TabUnf, unf); pushed = pushed + 1 end
        if col_TabUnfAct then r.ImGui_PushStyleColor(ctx, col_TabUnfAct, unfAct); pushed = pushed + 1 end
        return pushed
    end

    if col_Tab or col_TabDimmed or col_TabDimmedSel or col_TabDimmedOver then
        local pushed = 0
        if col_Tab then r.ImGui_PushStyleColor(ctx, col_Tab, baseColor); pushed = pushed + 1 end
        if col_TabDimmed then r.ImGui_PushStyleColor(ctx, col_TabDimmed, unf); pushed = pushed + 1 end
        if col_TabDimmedSel then r.ImGui_PushStyleColor(ctx, col_TabDimmedSel, active); pushed = pushed + 1 end
        if col_TabDimmedOver then r.ImGui_PushStyleColor(ctx, col_TabDimmedOver, hovered); pushed = pushed + 1 end
        if pushed > 0 then return pushed end
    end

    local col_Header       = enum({'ImGui_Col_Header','Col_Header'})
    local col_HeaderHover  = enum({'ImGui_Col_HeaderHovered','Col_HeaderHovered'})
    local col_HeaderActive = enum({'ImGui_Col_HeaderActive','Col_HeaderActive'})
    local col_Text         = enum({'ImGui_Col_Text','Col_Text'})
    local pushed = 0
    if col_Header and col_HeaderHover and col_HeaderActive then
        r.ImGui_PushStyleColor(ctx, col_Header, baseColor); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, col_HeaderHover, hovered); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, col_HeaderActive, active); pushed = pushed + 1
    end
    if col_Text then r.ImGui_PushStyleColor(ctx, col_Text, baseColor); pushed = pushed + 1 end
    if pushed > 0 then return -pushed end
    return 0
end

local function PopTabColors(count)
    if count and count ~= 0 then r.ImGui_PopStyleColor(ctx, math.abs(count)) end
end

local function DrawTabUnderlineAccent(baseColor, is_active)
    local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
    if not min_x or not max_x then return end
    local hovered = r.ImGui_IsItemHovered(ctx)
    local col
    if is_active then
        col = Color_AdjustBrightness(baseColor, 1.30)
    elseif hovered then
        col = Color_AdjustBrightness(baseColor, 1.15)
    else
        col = Color_AdjustBrightness(baseColor, 0.90)
    end
    local thickness = 3
    local pad = 4
    local x1 = min_x + pad
    local x2 = max_x - pad
    local y1 = max_y - thickness
    local y2 = max_y
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col)
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
    
    if r.ImGui_Button(ctx, section_states[state_key] and "-##" .. title or "+##" .. title) then
        section_states[state_key] = not section_states[state_key]
    end
    
    return section_states[state_key]
end

function ShowSettings(main_window_width , main_window_height)
    if not show_settings then return end
    
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)
    r.ImGui_SetNextWindowSize(ctx, settings.settings_window_width or 780, -1)
    local settings_visible, settings_open = r.ImGui_Begin(ctx, 'Transport Settings', true, settings_flags)
    if settings_visible then
        r.ImGui_PushFont(ctx, settings_ui_font, SETTINGS_UI_FONT_SIZE)
        SetStyle()
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.settings_text_color or 0xFFFFFFFF)
        
        local window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "TRANSPORT")

        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "Presets:")
        r.ImGui_SameLine(ctx)
        do
            local right_margin = 60
            local avail_w1 = select(1, r.ImGui_GetContentRegionAvail(ctx)) - right_margin
            r.ImGui_SetNextItemWidth(ctx, math.max(140, math.floor(avail_w1 * 0.35)))
            local presets = GetPresetList()
            local display_name = preset_name and preset_name ~= "" and preset_name or "preset_name"
            if not preset_input_name then preset_input_name = "" end
            if r.ImGui_BeginCombo(ctx, "##PresetCombo", display_name) then
                for _, preset in ipairs(presets) do
                    local is_selected = (preset == preset_name)
                    if r.ImGui_Selectable(ctx, preset, is_selected) then
                        preset_name = preset
                        LoadPreset(preset)
                        SaveLastUsedPreset(preset)
                    end
                    if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
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

            r.ImGui_SameLine(ctx)
            local avail_w2 = select(1, r.ImGui_GetContentRegionAvail(ctx)) - right_margin
            local save_tw = select(1, r.ImGui_CalcTextSize(ctx, "Save As New"))
            local save_btn_w = save_tw + 18
            local input_w = math.max(120, math.floor(avail_w2 - save_btn_w - 10))
            r.ImGui_SetNextItemWidth(ctx, input_w)
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

        do
            local labels = {
                "Style & Colors",
                "Layout & Position",
                "Scaling",
                "Transport Buttons",
                "Custom Buttons",
                "Widget Manager",
            }
            local total = 0
            local per_tab_padding = 28   
            for i = 1, #labels do
                local tw = select(1, r.ImGui_CalcTextSize(ctx, labels[i]))
                total = total + tw + per_tab_padding
            end
            local side_margins = 24  
            local target_w = math.floor(total + side_margins)
            local min_w, max_w = 680, 1100
            target_w = math.max(min_w, math.min(max_w, target_w))
            if settings.settings_window_width ~= target_w then
                settings.settings_window_width = target_w
                r.ImGui_SetNextWindowSize(ctx, target_w, -1)
            end
        end

        if r.ImGui_BeginTabBar(ctx, "SettingsTabs") then
            local pushed_tab = PushTabColors(settings.tab_color_style or 0x4AA3FFFF)
            local style_open = r.ImGui_BeginTabItem(ctx, "Style & Colors")
            if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(settings.tab_color_style or 0x4AA3FFFF, style_open) end
            if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
            if style_open then
                local rv
                if r.ImGui_BeginTable(ctx, "SC_TopSliders", 2) then
                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableNextColumn(ctx)
                    rv, settings.window_rounding = r.ImGui_SliderDouble(ctx, "Window Rounding", settings.window_rounding, 0.0, 20.0)
                    rv, settings.grab_rounding = r.ImGui_SliderDouble(ctx, "Grab Rounding", settings.grab_rounding, 0.0, 20.0)
                    rv, settings.grab_min_size = r.ImGui_SliderDouble(ctx, "Grab Min Size", settings.grab_min_size, 4.0, 20.0)
                    r.ImGui_TableNextColumn(ctx)
                    rv, settings.frame_rounding = r.ImGui_SliderDouble(ctx, "Frame Rounding", settings.frame_rounding, 0.0, 20.0)
                    rv, settings.popup_rounding = r.ImGui_SliderDouble(ctx, "Popup Rounding", settings.popup_rounding, 0.0, 20.0)
                    rv, settings.border_size = r.ImGui_SliderDouble(ctx, "Border Size", settings.border_size, 0.0, 5.0)
                    rv, settings.button_border_size = r.ImGui_SliderDouble(ctx, "Button Border Size", settings.button_border_size, 0.0, 5.0)
                    r.ImGui_EndTable(ctx)
                    r.ImGui_Separator(ctx)
                end
                
                local flags = r.ImGui_ColorEditFlags_NoInputs()
                local window_width = r.ImGui_GetWindowWidth(ctx)
                local columns = 3 

                local unified = {
                    { 'HEADER', 'Background & Frame' },
                    { 'background', 'Background' },
                    { 'frame_bg', 'Frame Background' },
                    { 'frame_bg_hovered', 'Frame Bg Hovered' },
                    { 'frame_bg_active', 'Frame Bg Active' },

                    { 'HEADER', 'Text & Borders' },
                    { 'text_normal', 'Text Normal' },
                    { 'settings_text_color', 'Settings Text', 0xFFFFFFFF },
                    { 'border', 'Border Color' },

                    { 'HEADER', 'Button States' },
                    { 'button_normal', 'Button Normal' },
                    { 'button_hovered', 'Button Hovered' },
                    { 'button_active', 'Button Active' },

                    { 'HEADER', 'Sliders & Check' },
                    { 'slider_grab', 'Slider Grab' },
                    { 'slider_grab_active', 'Slider Grab Active' },
                    { 'check_mark', 'Check Mark' },

                    { 'HEADER', 'Transport Colors' },
                    { 'transport_normal', 'Transport Normal' },
                    { 'play_active', 'Play Active' },
                    { 'record_active', 'Record Active' },
                    { 'pause_active', 'Pause Active' },
                    { 'loop_active', 'Loop Active' },

                    { 'HEADER', 'Transport Widgets' },
                    { 'timesig_button_color', 'TimeSig Button', 0x333333FF },
                    { 'timesig_button_color_hover', 'TimeSig Hover', 0x444444FF },
                    { 'timesig_button_color_active', 'TimeSig Active', 0x555555FF },
                    { 'env_button_color', 'ENV Button', 0x333333FF },
                    { 'env_button_color_hover', 'ENV Hover', 0x444444FF },
                    { 'env_button_color_active', 'ENV Active', 0x555555FF },
                    { 'env_override_active_color', 'ENV Override Active' },
                    { 'tempo_button_color', 'Tempo Button', 0x333333FF },
                    { 'tempo_button_color_hover', 'Tempo Hover', 0x444444FF },
                    { 'timesel_color', 'Time Selection', 0x333333FF },
                    { 'local_time_color', 'Local Time Text', 0xFFFFFFFF },

                    { 'HEADER', 'Tab Colors' },
                    { 'tab_color_style', 'Style & Colors Tab', 0x4AA3FFFF },
                    { 'tab_color_layout', 'Layout & Position Tab', 0x66CC66FF },
                    { 'tab_color_scaling', 'Scaling Tab', 0xFFB84DFF },
                    { 'tab_color_transport', 'Transport Buttons Tab', 0xFF6666FF },
                    { 'tab_color_custom', 'Custom Buttons Tab', 0xAA88EEFF },
                    { 'tab_color_widgets', 'Widget Manager Tab', 0x66CCCCFF },
                }

                if r.ImGui_BeginTable(ctx, '##unified_colors', columns, r.ImGui_TableFlags_SizingStretchProp()) then
                    local col = 0
                    local first_header_passed = false
                    local function DrawFullWidthSeparator()
                        if col ~= 0 then
                            while col ~= 0 do
                                r.ImGui_TableNextColumn(ctx)
                                col = (col + 1) % columns
                            end
                        end
                        r.ImGui_TableNextRow(ctx)
                        for c = 1, columns do
                            r.ImGui_TableNextColumn(ctx)
                            local seg_x, seg_y = r.ImGui_GetCursorScreenPos(ctx)
                            local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                            local seg_w = avail_w > 4 and (avail_w - 2) or avail_w
                            local dl = r.ImGui_GetWindowDrawList(ctx)
                            local color = 0xFFFFFF22
                            if dl then
                                r.ImGui_DrawList_AddLine(dl, seg_x, seg_y + 2, seg_x + seg_w, seg_y + 2, color, 1.0)
                            end
                        end
                        r.ImGui_TableNextRow(ctx)
                        col = 0
                    end
                    for idx, item in ipairs(unified) do
                        if item[1] == 'HEADER' then
                            if first_header_passed then
                                DrawFullWidthSeparator()
                            end
                            first_header_passed = true
                            r.ImGui_TableNextRow(ctx)
                            r.ImGui_TableNextColumn(ctx)
                            r.ImGui_Text(ctx, item[2])
                            r.ImGui_TableNextRow(ctx)
                            col = 0
                        else
                            if col == 0 then r.ImGui_TableNextRow(ctx) end
                            r.ImGui_TableNextColumn(ctx)
                            local key   = item[1]
                            local label = item[2]
                            local default = item[3]
                            if key == 'env_override_active_color' then
                                default = default or settings.loop_active or 0x66CC66FF
                            end
                            local current = settings[key] or default
                            local rv_col, new_col = r.ImGui_ColorEdit4(ctx, label, current, flags)
                            if rv_col then settings[key] = new_col end
                            col = (col + 1) % columns
                        end
                    end
             
                    r.ImGui_EndTable(ctx)
                end
                r.ImGui_Spacing(ctx)
            
                r.ImGui_EndTabItem(ctx)
            end
            pushed_tab = PushTabColors(settings.tab_color_layout or 0x66CC66FF)
            local layout_open = r.ImGui_BeginTabItem(ctx, "Layout & Position")
            if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(settings.tab_color_layout or 0x66CC66FF, layout_open) end
            if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
            if layout_open then
                local flags = r.ImGui_ColorEditFlags_NoInputs()
                local column_width = r.ImGui_GetWindowWidth(ctx) / 2

                r.ImGui_Text(ctx, "Edit mode")
                r.ImGui_SameLine(ctx)
                local rv
                rv, settings.edit_mode = r.ImGui_Checkbox(ctx, "##editenable", settings.edit_mode)
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Snap")
                r.ImGui_SameLine(ctx)
                rv, settings.edit_snap_to_grid = r.ImGui_Checkbox(ctx, "##snaptogrid", settings.edit_snap_to_grid)
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Show")
                r.ImGui_SameLine(ctx)
                rv, settings.edit_grid_show = r.ImGui_Checkbox(ctx, "##showgrid", settings.edit_grid_show)
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Size")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 120)
                rv, settings.edit_grid_size_px = r.ImGui_SliderInt(ctx, "##gridsize", settings.edit_grid_size_px or 16, 4, 64)
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Color")
                r.ImGui_SameLine(ctx)
                local rv_col, new_col = r.ImGui_ColorEdit4(ctx, "##gridcolor", settings.edit_grid_color or 0xFFFFFF22, r.ImGui_ColorEditFlags_NoInputs())
                if rv_col then settings.edit_grid_color = new_col end

                r.ImGui_Separator(ctx)

                r.ImGui_TextColored(ctx, 0x3399FFFF, "Fonts") 
                if r.ImGui_BeginTable(ctx, "LP_Fonts2ColGrid", 6) then
                    local function RenderFontCells(label, font_key, size_key, opts)
                        opts = opts or {}
                        local display_font = opts.display or settings[font_key]
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_Text(ctx, label)
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_SetNextItemWidth(ctx, 200)
                        if r.ImGui_BeginCombo(ctx, "##"..label.."Font", display_font) then
                            for _, f in ipairs(fonts) do
                                local sel = (display_font == f)
                                if r.ImGui_Selectable(ctx, f, sel) then
                                    if font_key == "current_font" then
                                        settings.current_font = f
                                        UpdateFont(); RebuildSectionFonts()
                                        display_font = settings.current_font
                                    else
                                        settings[font_key] = f
                                        if font_key == "transport_font_name" then
                                            display_font = settings.transport_font_name or settings.current_font
                                        else
                                            display_font = settings[font_key]
                                        end
                                        RebuildSectionFonts()
                                    end
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                        r.ImGui_TableNextColumn(ctx)
                        r.ImGui_SetNextItemWidth(ctx, 80)
                        local current_size = tostring(settings[size_key])
                        if r.ImGui_BeginCombo(ctx, "##"..label.."Size", current_size) then
                            for _, size in ipairs(text_sizes) do
                                local sel = (settings[size_key] == size)
                                if r.ImGui_Selectable(ctx, tostring(size), sel) then
                                    settings[size_key] = size
                                    if font_key == "current_font" or size_key == "font_size" then
                                        UpdateFont()
                                    end
                                    RebuildSectionFonts()
                                end
                                if sel then r.ImGui_SetItemDefaultFocus(ctx) end
                            end
                            r.ImGui_EndCombo(ctx)
                        end
                    end

                    r.ImGui_TableNextRow(ctx)
                    RenderFontCells("Base", "current_font", "font_size")
                    RenderFontCells("Transport", "transport_font_name", "transport_font_size", { display = settings.transport_font_name or settings.current_font })

                    r.ImGui_TableNextRow(ctx)
                    RenderFontCells("Tempo", "tempo_font_name", "tempo_font_size")
                    RenderFontCells("Time Signature", "timesig_font_name", "timesig_font_size")

                    r.ImGui_TableNextRow(ctx)
                    RenderFontCells("Local Time", "local_time_font_name", "local_time_font_size")
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "")
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "")
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "")

                    r.ImGui_EndTable(ctx)
                end
                local base_x = r.ImGui_GetCursorPosX(ctx)
                local titles = {
                    "Transport",
                    "Cursor Position",
                    "Time Selection",
                    "Tempo",
                    "Playrate",
                    "Time Signature",
                    "Envelope",
                    "TapTempo",
                    "Local Time",
                }
                local max_label_w = 0
                for i = 1, #titles do
                    local tw, _ = r.ImGui_CalcTextSize(ctx, titles[i])
                    if tw > max_label_w then max_label_w = tw end
                end
                local show_col_x = base_x + max_label_w + 12

                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Transport")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_transport = r.ImGui_Checkbox(ctx, "Show##transport", settings.show_transport)
                if settings.show_transport then
                    r.ImGui_SameLine(ctx)
                    rv, settings.center_transport = r.ImGui_Checkbox(ctx, "Center", settings.center_transport)
                    if settings.center_transport then
                            local tfsize = settings.transport_font_size or settings.font_size or 16
                            local buttonSize = tfsize * 1.1
                            local spacing = math.floor(buttonSize * 0.2)
                            local count = 7 
                            local buttons_width
                            if settings.use_graphic_buttons then
                                local gis = settings.custom_image_size or 1.0
                                local function sz(per, used)
                                    local base = buttonSize * gis
                                    if used then return base * (per or 1.0) else return base end
                                end
                                buttons_width = (
                                    sz(settings.custom_rewind_image_size,  settings.use_custom_rewind_image) +
                                    sz(settings.custom_play_image_size,    settings.use_custom_play_image)   +
                                    sz(settings.custom_stop_image_size,    settings.use_custom_stop_image)   +
                                    sz(settings.custom_pause_image_size,   settings.use_custom_pause_image)  +
                                    sz(settings.custom_record_image_size,  settings.use_custom_record_image) +
                                    sz(settings.custom_loop_image_size,    settings.use_custom_loop_image)   +
                                    sz(settings.custom_forward_image_size, settings.use_custom_forward_image)
                                ) + spacing * (count - 1)
                            else
                                local perButtonWidth_text = buttonSize * 1.7
                                buttons_width = perButtonWidth_text * count + spacing * (count - 1)
                            end
                            settings.transport_x = ((main_window_width - buttons_width) / 2) / main_window_width
                        else
                            DrawPixelXYControlsInline('transport_x','transport_y', main_window_width, main_window_height, { slider_width = 82 })
                        end
                end
                
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Cursor Position")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_cursorpos = r.ImGui_Checkbox(ctx, "Show##cursorpos", settings.show_cursorpos)
                if settings.show_cursorpos then
                    DrawPixelXYControlsInline('cursorpos_x','cursorpos_y', main_window_width, main_window_height)
                end
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Time Selection")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_timesel = r.ImGui_Checkbox(ctx, "Show##timesel", settings.show_timesel)
                if settings.show_timesel then
                    DrawPixelXYControlsInline('timesel_x','timesel_y', main_window_width, main_window_height)
                    local after_first_line_y = r.ImGui_GetCursorPosY(ctx)
                    local line_height = r.ImGui_GetTextLineHeightWithSpacing(ctx)
                    r.ImGui_SetCursorPosX(ctx, show_col_x)
                    r.ImGui_SetCursorPosY(ctx, after_first_line_y + line_height * 0.2) 
                    rv, settings.show_time_selection = r.ImGui_Checkbox(ctx, "Show Time", settings.show_time_selection)
                    r.ImGui_SameLine(ctx)
                    rv, settings.show_beats_selection = r.ImGui_Checkbox(ctx, "Show Beats", settings.show_beats_selection)
                    r.ImGui_SameLine(ctx)
                    rv, settings.timesel_invisible = r.ImGui_Checkbox(ctx, "Invisible Button", settings.timesel_invisible)
                    r.ImGui_SameLine(ctx)
                    rv, settings.timesel_border = r.ImGui_Checkbox(ctx, "Show Button Border", settings.timesel_border)
                end
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Tempo")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_tempo = r.ImGui_Checkbox(ctx, "Show##tempo", settings.show_tempo)
                if settings.show_tempo then
                    DrawPixelXYControlsInline('tempo_x','tempo_y', main_window_width, main_window_height)
                end
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Playrate")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_playrate = r.ImGui_Checkbox(ctx, "Show##playrate", settings.show_playrate)
                if settings.show_playrate then
                    DrawPixelXYControlsInline('playrate_x','playrate_y', main_window_width, main_window_height)
                end
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Time Signature")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_timesig_button = r.ImGui_Checkbox(ctx, "Show##timesig", settings.show_timesig_button)
                if settings.show_timesig_button then
                    DrawPixelXYControlsInline('timesig_x','timesig_y', main_window_width, main_window_height)

                end
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Envelope")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_env_button = r.ImGui_Checkbox(ctx, "Show##env", settings.show_env_button)
                if settings.show_env_button then
                    DrawPixelXYControlsInline('env_x','env_y', main_window_width, main_window_height)
                end
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "TapTempo")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_taptempo = r.ImGui_Checkbox(ctx, "Show##taptempo", settings.show_taptempo)
                if settings.show_taptempo then
                    DrawPixelXYControlsInline('taptempo_x','taptempo_y', main_window_width, main_window_height)

                    local tap_line1_y = r.ImGui_GetCursorPosY(ctx)
                    r.ImGui_SetCursorPosX(ctx, show_col_x)
                    r.ImGui_SetNextItemWidth(ctx, 70)
                    rv, settings.tap_button_text = r.ImGui_InputText(ctx, "Button Text", settings.tap_button_text)
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 70)
                    rv, settings.tap_button_width = r.ImGui_InputInt(ctx, "Width", settings.tap_button_width)
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 70)
                    rv, settings.tap_button_height = r.ImGui_InputInt(ctx, "Height", settings.tap_button_height)
                    local tap_line2_y = r.ImGui_GetCursorPosY(ctx) + r.ImGui_GetTextLineHeightWithSpacing(ctx)*0.2
                    r.ImGui_SetCursorPosX(ctx, show_col_x)
                    r.ImGui_SetCursorPosY(ctx, tap_line2_y)
                    rv, settings.set_tempo_on_tap = r.ImGui_Checkbox(ctx, "Set Project Tempo Automatically", settings.set_tempo_on_tap)
                    r.ImGui_SameLine(ctx)
                    rv, settings.show_accuracy_indicator = r.ImGui_Checkbox(ctx, "Show Accuracy Indicator", settings.show_accuracy_indicator)
                    r.ImGui_SameLine(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 90)
                    rv, settings.tap_input_limit = r.ImGui_InputInt(ctx, "History Size", settings.tap_input_limit)

                    if settings.show_accuracy_indicator then
                        local cflags = r.ImGui_ColorEditFlags_NoInputs()
                        local tap_line3_y = r.ImGui_GetCursorPosY(ctx) + r.ImGui_GetTextLineHeightWithSpacing(ctx)*0.2
                        r.ImGui_SetCursorPosX(ctx, show_col_x)
                        r.ImGui_SetCursorPosY(ctx, tap_line3_y)
                        rv, settings.high_accuracy_color = r.ImGui_ColorEdit4(ctx, "High Accuracy", settings.high_accuracy_color, cflags)
                        r.ImGui_SameLine(ctx)
                        rv, settings.medium_accuracy_color = r.ImGui_ColorEdit4(ctx, "Medium Accuracy", settings.medium_accuracy_color, cflags)
                        r.ImGui_SameLine(ctx)
                        rv, settings.low_accuracy_color = r.ImGui_ColorEdit4(ctx, "Low Accuracy", settings.low_accuracy_color, cflags)
                    end
                end
                r.ImGui_Separator(ctx)
                r.ImGui_TextColored(ctx, 0x3399FFFF, "Local Time")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, show_col_x)
                rv, settings.show_local_time = r.ImGui_Checkbox(ctx, "Show##localtime", settings.show_local_time)
                if settings.show_local_time then
                    local changed = false
                    DrawPixelXYControlsInline('local_time_x','local_time_y', main_window_width, main_window_height)


                    local flags = r.ImGui_ColorEditFlags_NoInputs()
                end
                r.ImGui_EndTabItem(ctx)
            end

            pushed_tab = PushTabColors(settings.tab_color_scaling or 0xFFB84DFF)
            local scaling_open = r.ImGui_BeginTabItem(ctx, "Scaling")
            if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(settings.tab_color_scaling or 0xFFB84DFF, scaling_open) end
            if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
            if scaling_open then
                r.ImGui_Text(ctx, "Responsive Scaling")
                r.ImGui_Separator(ctx)

                local changed_scaling = false
                local rvb
                rvb, settings.custom_buttons_scale_with_width = r.ImGui_Checkbox(ctx, "Scale positions with window width", settings.custom_buttons_scale_with_width or false)
                changed_scaling = changed_scaling or rvb
                rvb, settings.custom_buttons_scale_with_height = r.ImGui_Checkbox(ctx, "Scale positions with window height", settings.custom_buttons_scale_with_height or false)
                changed_scaling = changed_scaling or rvb

                r.ImGui_Spacing(ctx)
                rvb, settings.custom_buttons_scale_sizes = r.ImGui_Checkbox(ctx, "Scale custom button size with width", settings.custom_buttons_scale_sizes or false)
                changed_scaling = changed_scaling or rvb

                r.ImGui_Separator(ctx)
                r.ImGui_Text(ctx, "Reference Size")
                local ref_w = settings.custom_buttons_ref_width or 0
                local ref_h = settings.custom_buttons_ref_height or 0
                r.ImGui_PushItemWidth(ctx, 120)
                local rvi
                rvi, ref_w = r.ImGui_InputInt(ctx, "Ref width", ref_w)
                if rvi then settings.custom_buttons_ref_width = math.max(1, ref_w) end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Use Current Window##ref_w_btn") then
                    settings.custom_buttons_ref_width = math.floor(main_window_width)
                    changed_scaling = true
                end
                rvi, ref_h = r.ImGui_InputInt(ctx, "Ref height", ref_h)
                if rvi then settings.custom_buttons_ref_height = math.max(1, ref_h) end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Use Current Window##ref_h_btn") then
                    settings.custom_buttons_ref_height = math.floor(main_window_height)
                    changed_scaling = true
                end
                r.ImGui_PopItemWidth(ctx)

                if r.ImGui_Button(ctx, "Reset reference (auto)") then
                    settings.custom_buttons_ref_width = 0
                    settings.custom_buttons_ref_height = 0
                    settings.custom_buttons_ref_width = math.floor(main_window_width)
                    settings.custom_buttons_ref_height = math.floor(main_window_height)
                    SaveSettings()
                end

                r.ImGui_Spacing(ctx)
                r.ImGui_PushFont(ctx, settings_ui_font_small, SETTINGS_UI_FONT_SMALL_SIZE)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xA0A0A0FF)
                r.ImGui_TextWrapped(ctx, "Tip: First set the layout at your desired 'design' window size. With the toggles enabled, that size will be saved automatically as the reference (one-time).")
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_PopFont(ctx)

                if changed_scaling then SaveSettings() end
                r.ImGui_EndTabItem(ctx)
            end
            
            pushed_tab = PushTabColors(settings.tab_color_transport or 0xFF6666FF)
            local transport_open = r.ImGui_BeginTabItem(ctx, "Transport Buttons")
            if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(settings.tab_color_transport or 0xFF6666FF, transport_open) end
            if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
            if transport_open then
                local changed = false

                local rv
                rv, settings.use_graphic_buttons = r.ImGui_Checkbox(ctx, "Graphic", settings.use_graphic_buttons)
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Scale")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 120)
                rv, settings.custom_image_size = r.ImGui_SliderDouble(ctx, "##GlobalImgScale", settings.custom_image_size or 1.0, 0.5, 2.0, "%.2fx")
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, "Spacing")
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 110)
                rv, settings.graphic_spacing_factor = r.ImGui_SliderDouble(ctx, "##GlobalSpacing", settings.graphic_spacing_factor or 0.2, 0.0, 1.0, "%.2fx")
                r.ImGui_SameLine(ctx)
                rv, settings.use_locked_button_folder = r.ImGui_Checkbox(ctx, "Locked folder", settings.use_locked_button_folder)
                if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                    r.ImGui_Text(ctx, "Current folder: " .. settings.locked_button_folder_path)
                end

                r.ImGui_Separator(ctx)

                local function ImageRow(label, use_key, path_key, size_key, suffix, browseTitle)
                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableNextColumn(ctx)
                    r.ImGui_Text(ctx, label)
                    r.ImGui_TableNextColumn(ctx)
                    local rv_en, new_enable = r.ImGui_Checkbox(ctx, "##enable_"..suffix, settings[use_key])
                    if rv_en then settings[use_key] = new_enable; changed = changed or rv_en end
                    r.ImGui_TableNextColumn(ctx)
                    if settings[use_key] then
                        if r.ImGui_Button(ctx, "Browse##"..suffix) then
                            local start_dir = ""
                            if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
                                start_dir = settings.locked_button_folder_path
                            end
                            local retval, file = r.GetUserFileNameForRead(start_dir, browseTitle, ".png")
                            if retval then
                                settings[path_key] = file
                                changed = true
                                if settings.use_locked_button_folder then
                                    settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
                                end
                            end
                        end
                    else
                        r.ImGui_TextDisabled(ctx, "-")
                    end
                    r.ImGui_TableNextColumn(ctx)
                    do
                        local img_handle = transport_custom_images[string.lower(suffix)]
                        local size = 20
                        if settings[use_key] and img_handle and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(img_handle, 'ImGui_Image*')) then
                            local draw_list = r.ImGui_GetWindowDrawList(ctx)
                            local min_x, min_y = r.ImGui_GetCursorScreenPos(ctx)
                            local max_x, max_y = min_x + size, min_y + size
                            r.ImGui_DrawList_AddImage(draw_list, img_handle, min_x, min_y, max_x, max_y, 0.0, 0.0, 1/3, 1.0)
                            r.ImGui_Dummy(ctx, size, size)
                        else
                            r.ImGui_TextDisabled(ctx, "NB")
                        end
                    end
                    r.ImGui_TableNextColumn(ctx)
                    r.ImGui_SetNextItemWidth(ctx, 120)
                    local rv_sz, new_sz = r.ImGui_SliderDouble(ctx, "##size_"..suffix, settings[size_key], 0.5, 2.0, "%.2fx")
                    if rv_sz then settings[size_key] = new_sz end
                end

                if r.ImGui_BeginTable(ctx, "TB_Table", 5) then
                    r.ImGui_TableNextRow(ctx)
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Button")
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Enable")
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Image")
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Current")
                    r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Size")

                    ImageRow("Rewind",  'use_custom_rewind_image',  'custom_rewind_image_path',  'custom_rewind_image_size',  'Rewind',  "Select Rewind Button Image")
                    ImageRow("Play",    'use_custom_play_image',    'custom_play_image_path',    'custom_play_image_size',    'Play',    "Select Play Button Image")
                    ImageRow("Stop",    'use_custom_stop_image',    'custom_stop_image_path',    'custom_stop_image_size',    'Stop',    "Select Stop Button Image")
                    ImageRow("Pause",   'use_custom_pause_image',   'custom_pause_image_path',   'custom_pause_image_size',   'Pause',   "Select Pause Button Image")
                    ImageRow("Record",  'use_custom_record_image',  'custom_record_image_path',  'custom_record_image_size',  'Record',  "Select Record Button Image")
                    ImageRow("Loop",    'use_custom_loop_image',    'custom_loop_image_path',    'custom_loop_image_size',    'Loop',    "Select Loop Button Image")
                    ImageRow("Forward", 'use_custom_forward_image', 'custom_forward_image_path', 'custom_forward_image_size', 'Forward', "Select Forward Button Image")
                    r.ImGui_EndTable(ctx)
                end

                if changed then
                    UpdateCustomImages()
                end
                r.ImGui_EndTabItem(ctx)
            end
            
            pushed_tab = PushTabColors(settings.tab_color_custom or 0xAA88EEFF)
            local custom_open = r.ImGui_BeginTabItem(ctx, "Custom Buttons")
            if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(settings.tab_color_custom or 0xAA88EEFF, custom_open) end
            if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
            if custom_open then
                local rv
                ButtonEditor.ShowPresetsInline(ctx, CustomButtons, { small_font = settings_ui_font_small, small_font_size = SETTINGS_UI_FONT_SMALL_SIZE })
                r.ImGui_Separator(ctx)

                local function RenderGlobalOffsetInline(ctx_)
                    r.ImGui_Text(ctx_, "Global Position Offset")
                    r.ImGui_SameLine(ctx_)
                    r.ImGui_PushFont(ctx_, settings_ui_font_small, SETTINGS_UI_FONT_SMALL_SIZE)
                    r.ImGui_PushStyleColor(ctx_, r.ImGui_Col_Text(), 0xA0A0A0FF)
                    r.ImGui_Text(ctx_, "Global Offset is saved in the Transport preset. Re-save your Transport preset to keep these changes.")
                    r.ImGui_PopStyleColor(ctx_)
                    r.ImGui_PopFont(ctx_)
                    DrawPixelXYControls('custom_buttons_x_offset','custom_buttons_y_offset', main_window_width, main_window_height)
                    r.ImGui_SameLine(ctx_)
                    if r.ImGui_Button(ctx_, "Reset Offset") then
                        settings.custom_buttons_x_offset = 0.0
                        settings.custom_buttons_y_offset = 0.0
                        settings.custom_buttons_x_offset_px = 0
                        settings.custom_buttons_y_offset_px = 0
                    end
                end

                local _rv

                ButtonEditor.ShowEditorInline(ctx, CustomButtons, settings, { skip_presets = true, render_global_offset = RenderGlobalOffsetInline, canvas_width = main_window_width, canvas_height = main_window_height })
                r.ImGui_EndTabItem(ctx)
            end

            
            pushed_tab = PushTabColors(settings.tab_color_widgets or 0x66CCCCFF)
            local widgets_open = r.ImGui_BeginTabItem(ctx, "Widget Manager")
            if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(settings.tab_color_widgets or 0x66CCCCFF, widgets_open) end
            if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
            if widgets_open then
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
        r.ImGui_PopStyleColor(ctx, 14)
        r.ImGui_PopFont(ctx)
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx) 
    show_settings = settings_open
end

function EnvelopeOverride(main_window_width, main_window_height)
    if not settings.show_env_button then return end 
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.env_x_px and ScalePosX(settings.env_x_px, main_window_width, settings) or (settings.env_x * main_window_width))
    r.ImGui_SetCursorPosY(ctx, settings.env_y_px and ScalePosY(settings.env_y_px, main_window_height, settings) or (settings.env_y * main_window_height))
    local current_mode = "No override"
    for _, mode in ipairs(AUTOMATION_MODES) do
        if r.GetToggleCommandState(mode.command) == 1 then
            current_mode = mode.name
            local override_col = settings.env_override_active_color or settings.loop_active
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), override_col)
            break
        end
    end

    if current_mode == "No override" then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.env_button_color or settings.button_normal)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.env_button_color_hover or settings.button_hovered)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.env_button_color_active or settings.button_active)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.env_button_color_hover or settings.button_hovered)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.env_button_color_active or settings.button_active)
    end

    if r.ImGui_Button(ctx, "ENV") or r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "AutomationMenu")
    end
        StoreElementRect("env")

    if current_mode == "No override" then
        r.ImGui_PopStyleColor(ctx, 3)
    else
        r.ImGui_PopStyleColor(ctx, 3)
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
    local spacing_graphic = math.floor(buttonSize * (settings.graphic_spacing_factor or 0.2))
    local spacing_text = math.floor(buttonSize * 0.2)
    local spacing = settings.use_graphic_buttons and spacing_graphic or spacing_text
    local count = 7
    local perButtonWidth_text = buttonSize * 1.7 

    local drawList = r.ImGui_GetWindowDrawList(ctx)
    if font_transport then r.ImGui_PushFont(ctx, font_transport, settings.transport_font_size or settings.font_size) end

    local sizes = nil
    local widths_text = nil
    local total_width
    if settings.use_graphic_buttons then
        local gis = settings.custom_image_size or 1.0
        local function sz(use_flag, img_handle, per)
            local base = buttonSize * gis
            if use_flag and img_handle then
                local ok = true
                if r.ImGui_ValidatePtr then ok = r.ImGui_ValidatePtr(img_handle, 'ImGui_Image*') end
                if ok then return base * (per or 1.0) end
            end
            return base
        end
        sizes = {
            rewind  = sz(settings.use_custom_rewind_image,  transport_custom_images.rewind,  settings.custom_rewind_image_size),
            play    = sz(settings.use_custom_play_image,    transport_custom_images.play,    settings.custom_play_image_size),
            stop    = sz(settings.use_custom_stop_image,    transport_custom_images.stop,    settings.custom_stop_image_size),
            pause   = sz(settings.use_custom_pause_image,   transport_custom_images.pause,   settings.custom_pause_image_size),
            rec     = sz(settings.use_custom_record_image,  transport_custom_images.record,  settings.custom_record_image_size),
            loop    = sz(settings.use_custom_loop_image,    transport_custom_images.loop,    settings.custom_loop_image_size),
            forward = sz(settings.use_custom_forward_image, transport_custom_images.forward, settings.custom_forward_image_size),
        }
        total_width = (sizes.rewind + sizes.play + sizes.stop + sizes.pause + sizes.rec + sizes.loop + sizes.forward)
            + spacing * (count - 1)
    else
        widths_text = {}
        local labels = {"<<","PLAY","STOP","PAUSE","REC","LOOP",">>"}
        local pad = math.floor(buttonSize * 0.6) 
        for i=1,#labels do
            local tw, _ = r.ImGui_CalcTextSize(ctx, labels[i])
            widths_text[i] = math.max(tw + pad, perButtonWidth_text)
        end
        total_width = 0
        for i=1,#widths_text do total_width = total_width + widths_text[i] end
        total_width = total_width + spacing * (count - 1)
    end

    local base_x_px = settings.center_transport and math.max(0, math.floor((main_window_width - total_width) / 2)) or (settings.transport_x_px or math.floor(settings.transport_x * main_window_width))
    local base_y_px = settings.transport_y_px or math.floor(settings.transport_y * main_window_height)
    if settings.transport_x_px then base_x_px = ScalePosX(base_x_px, main_window_width, settings) end
    if settings.transport_y_px then base_y_px = ScalePosY(base_y_px, main_window_height, settings) end

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
        local x = base_x_px
        local pos_x, pos_y

      
    r.ImGui_SetCursorPosX(ctx, x)
    r.ImGui_SetCursorPosY(ctx, base_y_px)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "<<", sizes.rewind, sizes.rewind)
            if allow_input and clicked then r.Main_OnCommand(GOTO_START, 0) end
        end
        update_group_bounds()
        if settings.use_custom_rewind_image and transport_custom_images.rewind and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.rewind, 'ImGui_Image*')) then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.rewind, pos_x, pos_y, pos_x + sizes.rewind, pos_y + sizes.rewind, uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.rewind, settings.transport_normal)
            graphics.DrawArrows(pos_x, pos_y, sizes.rewind, false)
        end
        local play_uses_vector = not (settings.use_custom_play_image and transport_custom_images.play and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.play, 'ImGui_Image*')))
        local play_bias = play_uses_vector and math.floor(spacing * 0.5) or 0
        x = x + sizes.rewind + spacing + play_bias

    r.ImGui_SetCursorPosX(ctx, x)
    r.ImGui_SetCursorPosY(ctx, base_y_px)
        local play_state = r.GetPlayState() & 1 == 1
        local play_color = play_state and settings.play_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "PLAY", sizes.play, sizes.play)
            if allow_input and clicked then r.Main_OnCommand(PLAY_COMMAND, 0) end
        end
        update_group_bounds()
        ShowPlaySyncMenu()
        if settings.use_custom_play_image and transport_custom_images.play and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.play, 'ImGui_Image*')) then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if play_state then uv_x = 0.66 end
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.play, pos_x, pos_y, pos_x + sizes.play, pos_y + sizes.play, uv_x, 0, uv_x + 0.33, 1)
        else
            local play_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.play, play_color)
            play_graphics.DrawPlay(pos_x, pos_y, sizes.play)
        end
    local post_play_spacing = spacing - play_bias
    if post_play_spacing < 0 then post_play_spacing = 0 end
    x = x + sizes.play + post_play_spacing

    r.ImGui_SetCursorPosX(ctx, x)
    r.ImGui_SetCursorPosY(ctx, base_y_px)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "STOP", sizes.stop, sizes.stop)
            if allow_input and clicked then r.Main_OnCommand(STOP_COMMAND, 0) end
        end
        update_group_bounds()
        if settings.use_custom_stop_image and transport_custom_images.stop and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.stop, 'ImGui_Image*')) then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.stop, pos_x, pos_y, pos_x + sizes.stop, pos_y + sizes.stop, uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.stop, settings.transport_normal)
            graphics.DrawStop(pos_x, pos_y, sizes.stop)
        end
        x = x + sizes.stop + spacing

    r.ImGui_SetCursorPosX(ctx, x)
    r.ImGui_SetCursorPosY(ctx, base_y_px)
        local pause_state = r.GetPlayState() & 2 == 2
        local pause_color = pause_state and settings.pause_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "PAUSE", sizes.pause, sizes.pause)
            if allow_input and clicked then r.Main_OnCommand(PAUSE_COMMAND, 0) end
        end
        update_group_bounds()
        if settings.use_custom_pause_image and transport_custom_images.pause and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.pause, 'ImGui_Image*')) then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if pause_state then uv_x = 0.66 end
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.pause, pos_x, pos_y, pos_x + sizes.pause, pos_y + sizes.pause, uv_x, 0, uv_x + 0.33, 1)
        else
            local pause_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.pause, pause_color)
            pause_graphics.DrawPause(pos_x, pos_y, sizes.pause)
        end
        x = x + sizes.pause + spacing

    r.ImGui_SetCursorPosX(ctx, x)
    r.ImGui_SetCursorPosY(ctx, base_y_px)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        local rec_color = (rec_state == 1) and settings.record_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "REC", sizes.rec, sizes.rec)
            if allow_input and clicked then r.Main_OnCommand(RECORD_COMMAND, 0) end
        end
        update_group_bounds()
        ShowRecordMenu()
        if settings.use_custom_record_image and transport_custom_images.record and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.record, 'ImGui_Image*')) then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if rec_state == 1 then uv_x = 0.66 end
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.record, pos_x, pos_y, pos_x + sizes.rec, pos_y + sizes.rec, uv_x, 0, uv_x + 0.33, 1)
        else
            local rec_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.rec, rec_color)
            rec_graphics.DrawRecord(pos_x, pos_y, sizes.rec)
        end
        x = x + sizes.rec + spacing

    r.ImGui_SetCursorPosX(ctx, x)
    r.ImGui_SetCursorPosY(ctx, base_y_px)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        local loop_color = (repeat_state == 1) and settings.loop_active or settings.transport_normal
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, "LOOP", sizes.loop, sizes.loop)
            if allow_input and clicked then r.Main_OnCommand(REPEAT_COMMAND, 0) end
        end
        update_group_bounds()
        if settings.use_custom_loop_image and transport_custom_images.loop and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.loop, 'ImGui_Image*')) then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            if repeat_state == 1 then uv_x = 0.66 end
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.loop, pos_x, pos_y, pos_x + sizes.loop, pos_y + sizes.loop, uv_x, 0, uv_x + 0.33, 1)
        else
            local loop_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.loop, loop_color)
            loop_graphics.DrawLoop(pos_x, pos_y, sizes.loop)
        end
        x = x + sizes.loop + spacing

    r.ImGui_SetCursorPosX(ctx, x)
    r.ImGui_SetCursorPosY(ctx, base_y_px)
        pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
        do
            local clicked = r.ImGui_InvisibleButton(ctx, ">>", sizes.forward, sizes.forward)
            if allow_input and clicked then r.Main_OnCommand(GOTO_END, 0) end
        end
        update_group_bounds()
        if settings.use_custom_forward_image and transport_custom_images.forward and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.forward, 'ImGui_Image*')) then
            local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
            r.ImGui_DrawList_AddImage(drawList, transport_custom_images.forward, pos_x, pos_y, pos_x + sizes.forward, pos_y + sizes.forward, uv_x, 0, uv_x + 0.33, 1)
        else
            local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.forward, settings.transport_normal)
            graphics.DrawArrows(pos_x, pos_y, sizes.forward, true)
        end

    else
        local clicked
        local x = base_x_px
        local w = widths_text or {}

        r.ImGui_SetCursorPosX(ctx, x)
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        clicked = r.ImGui_Button(ctx, "<<", w[1] or perButtonWidth_text, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(GOTO_START, 0) end
        update_group_bounds()
        x = x + (w[1] or perButtonWidth_text) + spacing

        r.ImGui_SetCursorPosX(ctx, x)
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local play_state = r.GetPlayState() & 1 == 1
        if play_state then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.play_active) end
        clicked = r.ImGui_Button(ctx, "PLAY", w[2] or perButtonWidth_text, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(PLAY_COMMAND, 0) end
        if play_state then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()
        ShowPlaySyncMenu()
        x = x + (w[2] or perButtonWidth_text) + spacing

        r.ImGui_SetCursorPosX(ctx, x)
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        clicked = r.ImGui_Button(ctx, "STOP", w[3] or perButtonWidth_text, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(STOP_COMMAND, 0) end
        update_group_bounds()
        x = x + (w[3] or perButtonWidth_text) + spacing

        r.ImGui_SetCursorPosX(ctx, x)
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local pause_state = r.GetPlayState() & 2 == 2
        if pause_state then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.pause_active) end
        clicked = r.ImGui_Button(ctx, "PAUSE", w[4] or perButtonWidth_text, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(PAUSE_COMMAND, 0) end
        if pause_state then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()
        x = x + (w[4] or perButtonWidth_text) + spacing

        r.ImGui_SetCursorPosX(ctx, x)
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
        if rec_state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.record_active) end
        clicked = r.ImGui_Button(ctx, "REC", w[5] or perButtonWidth_text, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(RECORD_COMMAND, 0) end
        if rec_state == 1 then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()
        ShowRecordMenu()
        x = x + (w[5] or perButtonWidth_text) + spacing

        r.ImGui_SetCursorPosX(ctx, x)
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
        if repeat_state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.loop_active) end
        clicked = r.ImGui_Button(ctx, "LOOP", w[6] or perButtonWidth_text, buttonSize)
        if allow_input and clicked then r.Main_OnCommand(REPEAT_COMMAND, 0) end
        if repeat_state == 1 then r.ImGui_PopStyleColor(ctx) end
        update_group_bounds()
        x = x + (w[6] or perButtonWidth_text) + spacing

        r.ImGui_SetCursorPosX(ctx, x)
        r.ImGui_SetCursorPosY(ctx, base_y_px)
        clicked = r.ImGui_Button(ctx, ">>", w[7] or perButtonWidth_text, buttonSize)
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
    r.ImGui_SetCursorPosX(ctx, settings.playrate_x_px and ScalePosX(settings.playrate_x_px, main_window_width, settings) or (settings.playrate_x * main_window_width))
    r.ImGui_SetCursorPosY(ctx, settings.playrate_y_px and ScalePosY(settings.playrate_y_px, main_window_height, settings) or (settings.playrate_y * main_window_height))
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
    r.ImGui_SetCursorPosY(ctx, settings.playrate_y_px or (settings.playrate_y * main_window_height))
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
    if not settings.show_cursorpos then return end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, settings.cursorpos_x_px and ScalePosX(settings.cursorpos_x_px, main_window_width, settings) or (settings.cursorpos_x * main_window_width))
    r.ImGui_SetCursorPosY(ctx, settings.cursorpos_y_px and ScalePosY(settings.cursorpos_y_px, main_window_height, settings) or (settings.cursorpos_y * main_window_height))
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

    reaper.ImGui_SetCursorPosX(ctx, settings.tempo_x_px and ScalePosX(settings.tempo_x_px, main_window_width, settings) or (settings.tempo_x * main_window_width))
    reaper.ImGui_SetCursorPosY(ctx, settings.tempo_y_px and ScalePosY(settings.tempo_y_px, main_window_height, settings) or (settings.tempo_y * main_window_height))

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
            reaper.JS_Mouse_SetCursor(reaper.JS_Mouse_LoadCursor(0)) 
        end
    end

    if (not settings.edit_mode) and tempo_dragging and reaper.GetMousePosition then
        local _, current_mouse_y = reaper.GetMousePosition()
if tempo_last_mouse_y then
    local mouse_delta_y = current_mouse_y - tempo_last_mouse_y
    if math.abs(mouse_delta_y) > 0 then
        local sensitivity = 5 
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
                reaper.JS_Mouse_SetCursor(reaper.JS_Mouse_LoadCursor(32512)) 
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

        reaper.ImGui_Separator(ctx)
        if reaper.ImGui_BeginMenu(ctx, "Edit Presets") then
            if not editing_tempo_presets then
                editing_tempo_presets = {}
                for ii,vv in ipairs(settings.tempo_presets) do editing_tempo_presets[ii]=vv end
            end
            
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
            
            reaper.ImGui_EndMenu(ctx)
        end

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
    reaper.ImGui_SetCursorPosX(ctx, settings.timesig_x_px and ScalePosX(settings.timesig_x_px, main_window_width, settings) or ((settings.timesig_x or (settings.tempo_x + 0.05)) * main_window_width))
    reaper.ImGui_SetCursorPosY(ctx, settings.timesig_y_px and ScalePosY(settings.timesig_y_px, main_window_height, settings) or ((settings.timesig_y or settings.tempo_y) * main_window_height))
    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = reaper.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end

    if font_timesig then reaper.ImGui_PushFont(ctx, font_timesig, settings.timesig_font_size or settings.font_size) end
    local ts_text = string.format("%d/%d", timesig_num, timesig_denom)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), settings.timesig_button_color or settings.button_normal)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), settings.timesig_button_color_hover or settings.button_hovered)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), settings.timesig_button_color_active or settings.button_active)
    local clicked_ts = reaper.ImGui_Button(ctx, ts_text)
    reaper.ImGui_PopStyleColor(ctx, 3)
    if clicked_ts or reaper.ImGui_IsItemClicked(ctx,1) then
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

    r.ImGui_SetCursorPosX(ctx, settings.timesel_x_px and ScalePosX(settings.timesel_x_px, main_window_width, settings) or (settings.timesel_x * main_window_width))
    r.ImGui_SetCursorPosY(ctx, settings.timesel_y_px and ScalePosY(settings.timesel_y_px, main_window_height, settings) or (settings.timesel_y * main_window_height))

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
    r.ImGui_SetCursorPosX(ctx, settings.local_time_x_px and ScalePosX(settings.local_time_x_px, main_window_width, settings) or ((settings.local_time_x or 0.5) * main_window_width))
    r.ImGui_SetCursorPosY(ctx, settings.local_time_y_px and ScalePosY(settings.local_time_y_px, main_window_height, settings) or ((settings.local_time_y or 0.02) * main_window_height))
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
    
    r.ImGui_SetCursorPosX(ctx, settings.taptempo_x_px and ScalePosX(settings.taptempo_x_px, main_window_width, settings) or (settings.taptempo_x * main_window_width))
    r.ImGui_SetCursorPosY(ctx, settings.taptempo_y_px and ScalePosY(settings.taptempo_y_px, main_window_height, settings) or (settings.taptempo_y * main_window_height))
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
        r.ImGui_SetScrollY(ctx, 0)
        
        local main_window_width = r.ImGui_GetWindowWidth(ctx)
        local main_window_height = r.ImGui_GetWindowHeight(ctx)

        do
            local changed_ref = false
            if settings.custom_buttons_scale_with_width and ((settings.custom_buttons_ref_width or 0) <= 0) then
                settings.custom_buttons_ref_width = math.floor(main_window_width)
                changed_ref = true
            end
            if settings.custom_buttons_scale_with_height and ((settings.custom_buttons_ref_height or 0) <= 0) then
                settings.custom_buttons_ref_height = math.floor(main_window_height)
                changed_ref = true
            end
            if changed_ref then SaveSettings() end
        end


    ShowTimeSelection(main_window_width, main_window_height)
    EnvelopeOverride(main_window_width, main_window_height)
    Transport_Buttons(main_window_width, main_window_height)
    ShowCursorPosition(main_window_width, main_window_height)
    ShowLocalTime(main_window_width, main_window_height)
        CustomButtons.x_offset_px = settings.custom_buttons_x_offset_px or (settings.custom_buttons_x_offset * main_window_width)
    CustomButtons.y_offset_px = settings.custom_buttons_y_offset_px or (settings.custom_buttons_y_offset * main_window_height)
    CustomButtons.x_offset = CustomButtons.x_offset_px / main_window_width
    CustomButtons.y_offset = CustomButtons.y_offset_px / main_window_height

    ButtonRenderer.RenderButtons(ctx, CustomButtons, settings)
        CustomButtons.CheckForCommandPick()
        ShowTempo(main_window_width, main_window_height)
        ShowTimeSignature(main_window_width, main_window_height)
        PlayRate_Slider(main_window_width, main_window_height) 
        TapTempo(main_window_width, main_window_height) 

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
                        ondrag(dx_px, dy_px, dx_px / ww, dy_px / wh)
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
                        overlay_rect(e.name, rct.min_x, rct.min_y, rct.max_x, rct.max_y, function(dx_px, dy_px, dx_frac, dy_frac)
                            if e.beforeDrag then e.beforeDrag() end
                            Layout.move_pixel(dx_px, dy_px, dx_frac, dy_frac, e.keyx, e.keyy, ww, wh)
                        end)
                    end
                end
            end
        end
        ShowSettings(main_window_width, main_window_height)

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
