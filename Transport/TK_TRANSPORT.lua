-- @description TK_TRANSPORT
-- @author TouristKiller
-- @version 1.1.9
-- @changelog 
--[[

  ]]--
---------------------------------------------------------------------------------------------
local r = reaper
local ctx = r.ImGui_CreateContext('Transport Control')

local script_version = "unknown"
do
    local info = debug.getinfo(1, 'S')
    if info and info.source then
        local file = io.open(info.source:match("^@?(.*)"), "r")
        if file then
            for i = 1, 10 do
                local line = file:read("*l")
                if line and line:match("^%-%- @version") then
                    script_version = line:match("@version%s+([%d%.]+)")
                    break
                end
            end
            file:close()
        end
    end
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
package.path = script_path .. "?.lua;"

local json = require("json")
local preset_path = script_path .. "tk_transport_presets" .. os_separator
local preset_name = ""
local transport_preset_has_unsaved_changes = false


local CustomButtons = require('custom_buttons')
local ButtonEditor = require('button_editor')
local ButtonRenderer = require('button_renderer')
local WidgetManager = require('widget_manager')


local PLAY_COMMAND = 1007
local STOP_COMMAND = 1016
local PAUSE_COMMAND = 1008
local RECORD_COMMAND = 1013
local REPEAT_COMMAND = 1068
local GOTO_START = 40042
local GOTO_END = 40043

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

-- Shuttle Wheel variables
local shuttle_wheel = {
 is_dragging = false,
 last_mouse_angle = 0,
 current_speed = 0,
 center_x = 0,
 center_y = 0,
 last_update_time = 0,
 speed_decay = 0.95,
 rotation_angle = 0,
 accumulated_rotation = 0
}

-- Waveform Scrubber variables
local waveform_scrubber = {
 is_dragging = false,
 waveform_data = {},
 last_project_length = 0,
 last_cache_time = 0,
 cache_valid = false,
 cache_update_interval = 0.5, -- seconds
 samples_per_pixel = 1000,

 -- Advanced peak cache system
 peak_cache = {},
 cache_stats = {hits = 0, misses = 0, size = 0},
 last_update_time = 0,
 cache_keys_lru = {}, 
 item_modification_times = {} 
}

local battery_status = {
 level = -1,
 is_charging = false,
 manual_refresh = false
}

local visual_metronome = {
 enabled = false,
 jsfx_track = nil,
 jsfx_index = -1,
 beat_flash = 0,
 beat_position = 0,
 downbeat_flash = 0,
 size = 40,
 color_offbeat = 0xFF0000FF,
 color_beat = 0x00FF00FF,
 color_ring = 0x0080FFFF,
 color_off = 0x333333FF,
 fade_speed = 8.0,
 show_beat_flash = true,
 show_position_ring = true,
 ring_thickness = 3,
 show_beat_numbers = true,
 current_beat_in_measure = 0
}

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

local AUTOMATION_MODES = {
 {name = "No override", command = 40876},
 {name = "Bypass", command = 40908}, 
 {name = "Latch", command = 40881},
 {name = "Latch Preview", command = 42022},
 {name = "Read", command = 40879},
 {name = "Touch", command = 40880},
 {name = "Trim/Read", command = 40878},
 {name = "Write", command = 40882}
}

local show_settings = false
local show_instance_manager = false
local instance_name_input = "" 
local instance_start_empty = true
local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
local settings_flags = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse() 

local text_sizes = {10, 12, 14, 16, 18}
local fonts = {
 "Arial", "Helvetica", "Verdana", "Tahoma", "Times New Roman",
 "Georgia", "Courier New", "Trebuchet MS", "Impact", "Roboto",
 "Open Sans", "Ubuntu", "Segoe UI", "Noto Sans", "Liberation Sans",
 "DejaVu Sans"
}

local default_settings = {

 -- Style settings
 window_rounding = 12.0,
 frame_rounding = 6.0,
 popup_rounding = 6.0,
 grab_rounding = 12.0,
 grab_min_size = 8.0,
 button_border_size = 1.0,
 border_size = 1.0,
 current_font = "Arial",
 font_size = 12,
 lock_window_size = false,

 -- Transport buttons font (independent of base font)
 transport_font_name = "Arial",
 transport_font_size = 12,
 tempo_font_name = "Arial",
 timesig_font_name = "Arial",
 local_time_font_name = "Arial",
 taptempo_font_name = "Arial",
 tempo_font_size = 12,
 timesig_font_size = 12, 
 show_timesig_button = false, 
 local_time_font_size = 12, 
 taptempo_font_size = 12,
 center_transport = true,
 current_preset_name = "",

 -- x offset
 transport_x = 0.41, 
 timesel_x = 0.0, 
 tempo_x = 0.69, 
 timesig_x = 0.75,
 playrate_x = 0.93, 
 env_x = 0.19, 
 -- settings_x removed
 cursorpos_x = 0.25,
 cursorpos_mode = "both", 
 local_time_x = 0.50,
 custom_buttons_x_offset = 0.0,
 -- y offset
 transport_y = 0.15, 
 timesel_y = 0.15, 
 tempo_y = 0.15, 
 timesig_y = 0.02,
 playrate_y = 0.15, 
 env_y = 0.15, 
 -- settings_y removed
 cursorpos_y = 0.15,
 local_time_y = 0.02,
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
 background = 0x000000FF,
 -- Gradient background settings
 use_gradient_background = false,
 gradient_color_top = 0x1A1A1AFF,
 gradient_color_middle = 0x0D0D0DFF,
 gradient_color_bottom = 0x000000FF,
 
 -- Transparent buttons settings
 use_transparent_buttons = false,
 transparent_button_opacity = 0, -- 0 = fully transparent, 255 = fully opaque
 
 button_normal = 0x333333FF,
 play_active = 0x00FF00FF, 
 record_active = 0xFF0000FF, 
 pause_active = 0xFFFF00FF, 
 loop_active = 0x0088FFFF, 
 text_normal = 0xFFFFFFFF,
 settings_text_color = 0xFFFFFFFF,
 frame_bg = 0x333333FF,
 frame_bg_hovered = 0x444444FF,
 frame_bg_active = 0x555555FF,
 slider_grab = 0x999999FF,
 slider_grab_active = 0xAAAAAAFF,
 check_mark = 0x999999FF,
 button_hovered = 0x444444FF,
 button_active = 0x555555FF,
 border = 0x444444FF,
 transport_normal = 0x333333FF,
 timesel_color = 0x333333FF,
 timesel_border = true,
 show_local_time = true,
 local_time_color = 0xFFFFFFFF,
 timesel_invisible = false,

 show_battery_status = false,
 battery_x = 0.90,
 battery_y = 0.02,
 battery_font_name = "Arial",
 battery_font_size = 14,
 battery_show_icon = true,
 battery_show_percentage = true,
 battery_color_high = 0x00FF00FF,
 battery_color_medium = 0xFFFF00FF,
 battery_color_low = 0xFF0000FF,
 battery_color_charging = 0x00FFFFFF,
 battery_warning_threshold = 20,
 battery_critical_threshold = 10,

 -- Time Signature button colors
 timesig_button_color = 0x333333FF,
 timesig_button_color_hover = 0x444444FF,
 timesig_button_color_active = 0x555555FF,

 -- Envelope (ENV) button colors
 env_button_color = 0x333333FF,
 env_button_color_hover = 0x444444FF,
 env_button_color_active = 0x555555FF,
 env_override_active_color = 0x66CC66FF,

 -- Visibility settings
 use_graphic_buttons = false,
 show_timesel = true,
 show_transport = true,
 show_cursorpos = true,
 show_tempo = true,
 show_playrate = true,
 show_time_selection = true,
 show_beats_selection = true,
 show_env_button = true,
 show_master_volume = false,

 -- Custom Transport Button settings
 use_custom_play_image = false,
 custom_play_image_path = "",
 custom_play_image_size = 1.0,
 use_custom_stop_image = false,
 custom_stop_image_path = "",
 custom_stop_image_size = 1.0,
 use_custom_pause_image = false, 
 custom_pause_image_path = "",
 custom_pause_image_size = 1.0,
 use_custom_record_image = false,
 custom_record_image_path = "",
 custom_record_image_size = 1.0,
 use_custom_loop_image = false,
 custom_loop_image_path = "",
 custom_loop_image_size = 1.0,
 use_custom_rewind_image = false,
 custom_rewind_image_path = "",
 custom_rewind_image_size = 1.0,
 use_custom_forward_image = false,
 custom_forward_image_path = "",
 custom_image_size = 1.0,
 graphic_spacing_factor = 0.2,
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
 measure_display_width = 160,
 
 -- Visual Metronome settings
 show_visual_metronome = false,
 visual_metronome_x = 0.85,
 visual_metronome_y = 0.15,
 visual_metronome_size = 40,
 visual_metronome_fade_speed = 8.0,
 visual_metronome_color_offbeat = 0xFF0000FF,
 visual_metronome_color_beat = 0x00FF00FF,
 visual_metronome_color_ring = 0x0080FFFF,
 visual_metronome_color_off = 0x333333FF,
 visual_metronome_show_beat_flash = true,
 visual_metronome_show_position_ring = true,
 visual_metronome_ring_thickness = 3,
 visual_metronome_show_beat_numbers = true,

 -- Playrate slider settings
 playrate_slider_color = 0x4444AAFF,
 playrate_handle_color = 0x6666DDFF,
 playrate_text_color = 0xFFFFFFFF,
 playrate_handle_size = 12,
 playrate_handle_rounding = 6.0,
 playrate_frame_rounding = 4.0,
 playrate_slider_width = 120,

 -- Shuttle Wheel settings
 show_shuttle_wheel = false,
 shuttle_wheel_x = 0.10,
 shuttle_wheel_y = 0.15,
 shuttle_wheel_radius = 30,
 shuttle_wheel_color = 0x444444FF,
 shuttle_wheel_active_color = 0x0088FFFF,
 shuttle_wheel_border_color = 0x666666FF,
 shuttle_wheel_sensitivity = 2.0,
 shuttle_wheel_max_speed = 10.0,

 -- Waveform Scrubber settings
 show_waveform_scrubber = false,
 waveform_scrubber_x = 0.60,
 waveform_scrubber_y = 0.02,
 waveform_scrubber_width = 200,
 waveform_scrubber_height = 40,
 waveform_scrubber_window_size = 10.0, -- seconds
 waveform_scrubber_bg_color = 0x222222FF,
 waveform_scrubber_wave_color = 0x00AA00FF,
 waveform_scrubber_playhead_color = 0xFF0000FF,
 waveform_scrubber_border_color = 0x666666FF,
 waveform_scrubber_grid_color = 0x444444FF,
 waveform_scrubber_show_grid = true,
 waveform_scrubber_show_time_labels = true,
 waveform_scrubber_show_full_project = false,
 waveform_scrubber_handle_size = 8,

 -- Real Waveform settings
 waveform_scrubber_use_real_peaks = false,
 waveform_scrubber_cache_size = 1000, 
 waveform_scrubber_update_interval = 0.05, 
 waveform_scrubber_lod_auto = true, 
 waveform_scrubber_peak_resolution = 512, 

 -- Alarm/Timer settings
 time_alarm_enabled = false,
 time_alarm_type = "time", 
 time_alarm_hour = 12,
 time_alarm_minute = 0,
 time_alarm_duration_minutes = 10,
 time_alarm_flash_color = 0xFF0000FF,
 time_alarm_set_color = 0xFFFF00FF,
 time_alarm_triggered = false,
 time_alarm_start_time = 0,
 time_alarm_popup_enabled = true,
 time_alarm_popup_size = 300,
 time_alarm_popup_text = "? ALARM! ?",
 time_alarm_popup_text_size = 20,
 time_alarm_auto_dismiss = true,
 time_alarm_auto_dismiss_seconds = 10,

 -- Matrix Ticker settings
 show_matrix_ticker = false,
 matrix_ticker_x = 0.70,
 matrix_ticker_y = 0.15,
 matrix_ticker_width = 200,
 matrix_ticker_height = 40,
 matrix_ticker_text1 = "REAPER",
 matrix_ticker_text2 = "RECORDING",
 matrix_ticker_text3 = "STUDIO",
 matrix_ticker_bg_color = 0x003300FF,       
 matrix_ticker_border_color = 0x000000FF,    
 matrix_ticker_text_color = 0x000000FF,      
 matrix_ticker_grid_color = 0x00FF0088,      
 matrix_ticker_switch_interval = 10.0,       
 matrix_ticker_current_index = 1,
 matrix_ticker_last_switch_time = 0,
 matrix_ticker_font_size = 14,
 matrix_ticker_grid_size = 2,              
 matrix_ticker_show_bezel = true,           

}

local settings = {}
local is_new_empty_instance = false

if r.HasExtState("TK_TRANSPORT", "is_new_instance") then
 is_new_empty_instance = true
 for k, v in pairs(default_settings) do
 settings[k] = v
 end
 
 settings.show_transport = false
 settings.show_timesel = false
 settings.show_cursorpos = false
 settings.show_tempo = false
 settings.show_playrate = false
 settings.show_timesig_button = false
 settings.show_env_button = false
 settings.show_taptempo = false
 settings.show_shuttle_wheel = false
 settings.show_visual_metronome = false
 settings.show_local_time = false
 settings.show_waveform_scrubber = false
 settings.show_matrix_ticker = false
 
 r.DeleteExtState("TK_TRANSPORT", "is_new_instance", true)
else
 for k, v in pairs(default_settings) do
 settings[k] = v
 end
end

local element_rects = {}
local Layout = {
 elems = {
 { name = "transport", showFlag = "show_transport", keyx = "transport_x", keyy = "transport_y", beforeDrag = function() 
 local mode_suffix = ""
 if settings.transport_mode == 0 then mode_suffix = "_text"
 elseif settings.transport_mode == 1 then mode_suffix = "_graphic"
 elseif settings.transport_mode == 2 then mode_suffix = "_custom"
 end
 settings["center_transport" .. mode_suffix] = false
 settings.center_transport = false
 end },
 { name = "master_volume", showFlag = "show_master_volume", keyx = "master_volume_x", keyy = "master_volume_y" },
 { name = "cursorpos", showFlag = "show_cursorpos", keyx = "cursorpos_x", keyy = "cursorpos_y" },
 { name = "localtime", showFlag = "show_local_time", keyx = "local_time_x", keyy = "local_time_y" },
 { name = "battery_status", showFlag = "show_battery_status", keyx = "battery_x", keyy = "battery_y" },
 { name = "tempo", showFlag = "show_tempo", keyx = "tempo_x", keyy = "tempo_y" },
 { name = "playrate", showFlag = "show_playrate", keyx = "playrate_x", keyy = "playrate_y" },
 { name = "timesig", showFlag = "show_timesig_button", keyx = "timesig_x", keyy = "timesig_y" },
 { name = "env", showFlag = "show_env_button", keyx = "env_x", keyy = "env_y" },
 { name = "timesel", showFlag = "show_timesel", keyx = "timesel_x", keyy = "timesel_y" },
 { name = "taptempo", showFlag = "show_taptempo", keyx = "taptempo_x", keyy = "taptempo_y" },
 { name = "visual_metronome", showFlag = "show_visual_metronome", keyx = "visual_metronome_x", keyy = "visual_metronome_y" },
 { name = "shuttle_wheel", showFlag = "show_shuttle_wheel", keyx = "shuttle_wheel_x", keyy = "shuttle_wheel_y" },
 { name = "waveform_scrubber", showFlag = "show_waveform_scrubber", keyx = "waveform_scrubber_x", keyy = "waveform_scrubber_y" },
 { name = "matrix_ticker", showFlag = "show_matrix_ticker", keyx = "matrix_ticker_x", keyy = "matrix_ticker_y" },
 }
}
function Layout.move_frac(dx, dy, keyx, keyy)
 settings[keyx] = math.max(0, math.min(1, (settings[keyx] or 0) + dx))
 settings[keyy] = math.max(0, math.min(1, (settings[keyy] or 0) + dy))
end

function Layout.move_pixel(dx_px, dy_px, dx_frac, dy_frac, keyx, keyy, max_width, max_height)
 local pixel_keyx = keyx .. "_px"
 local pixel_keyy = keyy .. "_px"
 
 if settings[keyx] == nil then
 settings[keyx] = 0.5
 end
 if settings[keyy] == nil then
 settings[keyy] = 0.5
 end
 
 if settings[pixel_keyx] == nil then
 settings[pixel_keyx] = math.floor(settings[keyx] * max_width)
 end
 if settings[pixel_keyy] == nil then
 settings[pixel_keyy] = math.floor(settings[keyy] * max_height)
 end
 
 settings[pixel_keyx] = math.max(0, math.min(max_width, (settings[pixel_keyx] or 0) + dx_px))
 settings[pixel_keyy] = math.max(0, math.min(max_height, (settings[pixel_keyy] or 0) + dy_px))
 
 settings[keyx] = settings[pixel_keyx] / math.max(1, max_width)
 settings[keyy] = settings[pixel_keyy] / math.max(1, max_height)
end

local function DrawPixelXYControls(keyx, keyy, main_window_width, main_window_height, opts)
 opts = opts or {}
 local pixel_keyx = keyx .. "_px"
 local pixel_keyy = keyy .. "_px"
 
 if settings[keyx] == nil then
 settings[keyx] = 0.5
 end
 if settings[keyy] == nil then
 settings[keyy] = 0.5
 end
 
 if settings[pixel_keyx] == nil then
 settings[pixel_keyx] = math.floor(settings[keyx] * main_window_width)
 end
 if settings[pixel_keyy] == nil then
 settings[pixel_keyy] = math.floor(settings[keyy] * main_window_height)
 end
 
 settings[pixel_keyx] = settings[pixel_keyx] or 0
 settings[pixel_keyy] = settings[pixel_keyy] or 0
 
 local rv
 
 local avail_w, _ = r.ImGui_GetContentRegionAvail(ctx)
 local input_w = 90 
 local slider_w = 135  
 local group_gap = 5

 r.ImGui_Text(ctx, "X")
 r.ImGui_SameLine(ctx)
 r.ImGui_SetNextItemWidth(ctx, slider_w)
 rv, settings[pixel_keyx] = r.ImGui_SliderInt(ctx, "##"..keyx.."_slider", settings[pixel_keyx], 0, main_window_width, "%d px")
 if rv then MarkTransportPresetChanged() end
 local x_slider_active = r.ImGui_IsItemActive(ctx) or r.ImGui_IsItemHovered(ctx)
 r.ImGui_SameLine(ctx)
 r.ImGui_SetNextItemWidth(ctx, input_w)
 rv, settings[pixel_keyx] = r.ImGui_InputInt(ctx, "##"..keyx.."Input", settings[pixel_keyx])
 if rv then
 settings[pixel_keyx] = math.max(0, math.min(main_window_width, settings[pixel_keyx]))
 MarkTransportPresetChanged()
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
 if rv then MarkTransportPresetChanged() end
 local y_slider_active = r.ImGui_IsItemActive(ctx) or r.ImGui_IsItemHovered(ctx)
 r.ImGui_SameLine(ctx)
 r.ImGui_SetNextItemWidth(ctx, input_w)
 rv, settings[pixel_keyy] = r.ImGui_InputInt(ctx, "##"..keyy.."Input", settings[pixel_keyy])
 if rv then
 settings[pixel_keyy] = math.max(0, math.min(main_window_height, settings[pixel_keyy]))
 MarkTransportPresetChanged()
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

local settings_active_tab = 0 -- 0 = Global, 1 = Transport, 2 = Buttons, 3 = Images & Graphics, 4 = Widgets

local layout_selected_component = "transport_buttons" 
local selected_transport_component = "base_style"

local selected_button_component = "button_1" 
local editing_group_name = nil 
local group_name_input = "" 
local show_button_import_inline = false 

local transport_components = {
 { id = "transport_buttons", name = "Transport" },
 { id = "master_volume", name = "Master Volume" },
 { id = "envelope", name = "Envelope" },
 { id = "tempo_bpm", name = "Tempo (BPM)" },
 { id = "time_signature", name = "Time Signature" },
 { id = "time_selection", name = "Time Selection" },
 { id = "time_display", name = "Time Display" },
 { id = "battery_status", name = "Battery Status" },
 { id = "cursor_position", name = "Cursor Position" },
 { id = "wave_scrubber", name = "Wave Scrubber" },
 { id = "shuttle_wheel", name = "Shuttle Wheel" },
 { id = "visual_metronome", name = "Visual Metronome" },
 { id = "taptempo", name = "TapTempo" },
 { id = "playrate", name = "Playrate" },
 { id = "matrix_ticker", name = "Matrix Ticker" }
}

function ShowComponentList(ctx)
 for _, component in ipairs(transport_components) do
 local is_selected = (selected_transport_component == component.id)
 if r.ImGui_Selectable(ctx, component.name, is_selected) then
 selected_transport_component = component.id
 end
 
 if is_selected then
 r.ImGui_SetItemDefaultFocus(ctx)
 end
 end
end

function ShowComponentSettings(ctx, main_window_width, main_window_height)
 local component_id = selected_transport_component
 
 local component = nil
 for _, comp in ipairs(transport_components) do
 if comp.id == component_id then
 component = comp
 break
 end
 end
 
 if not component then
 r.ImGui_TextDisabled(ctx, "No component selected")
 return
 end
 
 r.ImGui_Text(ctx, "Settings for: " .. component.name)
 r.ImGui_Separator(ctx)
 
 local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
 if r.ImGui_BeginChild(ctx, "ComponentSettingsScroll", avail_w, avail_h, r.ImGui_ChildFlags_None()) then
 if component_id == "transport_buttons" then
 ShowTransportButtonSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "master_volume" then
 ShowMasterVolumeSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "envelope" then
 ShowEnvelopeSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "tempo_bpm" then
 ShowTempoBPMSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "time_signature" then
 ShowTimeSignatureSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "time_selection" then
 ShowTimeSelectionSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "time_display" then
 ShowTimeDisplaySettings(ctx, main_window_width, main_window_height)
 elseif component_id == "battery_status" then
 ShowBatteryStatusSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "cursor_position" then
 ShowCursorPositionSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "wave_scrubber" then
 ShowWaveScrubberSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "shuttle_wheel" then
 ShowShuttleWheelSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "visual_metronome" then
 ShowVisualMetronomeSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "taptempo" then
 ShowTapTempoSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "playrate" then
 ShowPlayrateSettings(ctx, main_window_width, main_window_height)
 elseif component_id == "matrix_ticker" then
 ShowMatrixTickerSettings(ctx, main_window_width, main_window_height)
 else
 r.ImGui_TextDisabled(ctx, "Settings for this component are not yet implemented")
 end
 r.ImGui_EndChild(ctx)
 end
end

function ShowTransportButtonSettings(ctx, main_window_width, main_window_height)
 local rv
 
 local function GetModeKey(base_key)
 local mode_suffix = ""
 if settings.transport_mode == 0 then
 mode_suffix = "_text"
 elseif settings.transport_mode == 1 then
 mode_suffix = "_graphic"
 elseif settings.transport_mode == 2 then
 mode_suffix = "_custom"
 end
 return base_key .. mode_suffix
 end
 
 local function GetModeSetting(base_key, default_value)
 local mode_key = GetModeKey(base_key)
 local value = settings[mode_key]
 if value == nil then
 return default_value
 end
 return value
 end
 
 local function SetModeSetting(base_key, value)
 local mode_key = GetModeKey(base_key)
 settings[mode_key] = value
 MarkTransportPresetChanged() 
 end
 
 rv, settings.show_transport = r.ImGui_Checkbox(ctx, "Show Transport", settings.show_transport ~= false)
 
 r.ImGui_SameLine(ctx)
 r.ImGui_Dummy(ctx, 20, 0)  
 r.ImGui_SameLine(ctx)
 
 if not settings.transport_mode then
 settings.transport_mode = settings.use_graphic_buttons and 1 or 0
 end
 
 local text_mode_active = settings.transport_mode == 0
 if text_mode_active then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4488FFFF)
 end
 if r.ImGui_Button(ctx, "Text Mode") then
 settings.transport_mode = 0
 settings.use_graphic_buttons = false
 UpdateCustomImages()
 end
 if text_mode_active then
 r.ImGui_PopStyleColor(ctx)
 end
 
 r.ImGui_SameLine(ctx)
 
 local graphic_mode_active = settings.transport_mode == 1
 if graphic_mode_active then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4488FFFF)
 end
 if r.ImGui_Button(ctx, "Graphic Mode") then
 settings.transport_mode = 1
 settings.use_graphic_buttons = true
 UpdateCustomImages()
 end
 if graphic_mode_active then
 r.ImGui_PopStyleColor(ctx)
 end
 
 r.ImGui_SameLine(ctx)
 
 local custom_mode_active = settings.transport_mode == 2
 if custom_mode_active then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4488FFFF)
 end
 if r.ImGui_Button(ctx, "Custom Mode") then
 settings.transport_mode = 2
 settings.use_graphic_buttons = true  
 UpdateCustomImages()  
 end
 if custom_mode_active then
 r.ImGui_PopStyleColor(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 if settings.show_transport then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 r.ImGui_SameLine(ctx)
 local current_center = GetModeSetting("center_transport", true)
 rv, current_center = r.ImGui_Checkbox(ctx, "Auto Center", current_center)
 if rv then SetModeSetting("center_transport", current_center) end
 
 if not current_center then
 local mode_suffix = ""
 if settings.transport_mode == 0 then mode_suffix = "_text"
 elseif settings.transport_mode == 1 then mode_suffix = "_graphic"
 elseif settings.transport_mode == 2 then mode_suffix = "_custom"
 end
 
 local key_x = "transport_x" .. mode_suffix
 local key_y = "transport_y" .. mode_suffix
 
 DrawPixelXYControls(key_x, key_y, main_window_width, main_window_height)
 end
 
 if settings.transport_mode ~= 1 and settings.transport_mode ~= 2 then
 r.ImGui_Separator(ctx)
 end
 
 if settings.transport_mode ~= 1 and settings.transport_mode ~= 2 then
 if r.ImGui_BeginTable(ctx, "FontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.transport_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##Font", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.transport_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.transport_font_size = r.ImGui_SliderInt(ctx, "##Size", settings.transport_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end
 
 r.ImGui_EndTable(ctx)
 end
 end  
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "SizeTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Button Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 local current_size = GetModeSetting("transport_button_size", 1.0)
 rv, current_size = r.ImGui_SliderDouble(ctx, "##ButtonSize", current_size, 0.5, 3.0, "%.1f")
 if rv then SetModeSetting("transport_button_size", current_size) end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Spacing:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 local current_spacing = GetModeSetting("transport_spacing", 1.0)
 rv, current_spacing = r.ImGui_SliderDouble(ctx, "##Spacing", current_spacing, 0.5, 3.0, "%.1f")
 if rv then SetModeSetting("transport_spacing", current_spacing) end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if settings.transport_mode ~= 2 then
 r.ImGui_Text(ctx, "Button Colors:")
 
 if r.ImGui_BeginTable(ctx, "TransportButtonColors", 3, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 local current_normal = GetModeSetting("transport_button_normal", 0x333333FF)
 rv, current_normal = r.ImGui_ColorEdit4(ctx, "Normal", current_normal, color_flags)
 if rv then SetModeSetting("transport_button_normal", current_normal) end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 local current_hover = GetModeSetting("transport_button_hover", 0x555555FF)
 rv, current_hover = r.ImGui_ColorEdit4(ctx, "Hover", current_hover, color_flags)
 if rv then SetModeSetting("transport_button_hover", current_hover) end
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 local current_active = GetModeSetting("transport_button_active", 0x777777FF)
 rv, current_active = r.ImGui_ColorEdit4(ctx, "Active", current_active, color_flags)
 if rv then SetModeSetting("transport_button_active", current_active) end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 end  
 
 if settings.transport_mode ~= 2 then
 r.ImGui_Text(ctx, "Active State Colors:")
 
 if r.ImGui_BeginTable(ctx, "TransportActiveColors", 4, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 local current_play_active = GetModeSetting("play_active", 0x00FF00FF)
 rv, current_play_active = r.ImGui_ColorEdit4(ctx, "Play", current_play_active, color_flags)
 if rv then SetModeSetting("play_active", current_play_active) end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 local current_record_active = GetModeSetting("record_active", 0xFF0000FF)
 rv, current_record_active = r.ImGui_ColorEdit4(ctx, "Record", current_record_active, color_flags)
 if rv then SetModeSetting("record_active", current_record_active) end
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 local current_pause_active = GetModeSetting("pause_active", 0xFFFF00FF)
 rv, current_pause_active = r.ImGui_ColorEdit4(ctx, "Pause", current_pause_active, color_flags)
 if rv then SetModeSetting("pause_active", current_pause_active) end
 
 r.ImGui_TableSetColumnIndex(ctx, 3)
 local current_loop_active = GetModeSetting("loop_active", 0x00FFFFFF)
 rv, current_loop_active = r.ImGui_ColorEdit4(ctx, "Loop", current_loop_active, color_flags)
 if rv then SetModeSetting("loop_active", current_loop_active) end
 
 r.ImGui_EndTable(ctx)
 end
 end  
 
 if settings.transport_mode ~= 1 then
 r.ImGui_Text(ctx, "Button Rounding:")
 r.ImGui_SetNextItemWidth(ctx, 150)
 local current_rounding = GetModeSetting("transport_button_rounding", 0)
 rv, current_rounding = r.ImGui_SliderDouble(ctx, "##TransportRounding", current_rounding, 0, 20, "%.0f px")
 if rv then SetModeSetting("transport_button_rounding", current_rounding) end
 
 r.ImGui_SameLine(ctx)
 r.ImGui_Dummy(ctx, 20, 0)
 r.ImGui_SameLine(ctx)
 
 local current_show_border = GetModeSetting("transport_show_border", false)
 rv, current_show_border = r.ImGui_Checkbox(ctx, "Show Border", current_show_border)
 if rv then SetModeSetting("transport_show_border", current_show_border) end
 
 if current_show_border then
 r.ImGui_SameLine(ctx)
 r.ImGui_Text(ctx, "Color:")
 r.ImGui_SameLine(ctx)
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 local current_border_color = GetModeSetting("transport_border_color", 0xFFFFFFFF)
 rv, current_border_color = r.ImGui_ColorEdit4(ctx, "##BorderColorTransport", current_border_color, color_flags)
 if rv then SetModeSetting("transport_border_color", current_border_color) end
 
 r.ImGui_SameLine(ctx)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SameLine(ctx)
 r.ImGui_SetNextItemWidth(ctx, 100)
 local current_border_size = GetModeSetting("transport_border_size", 1.0)
 rv, current_border_size = r.ImGui_SliderDouble(ctx, "##BorderSizeTransport", current_border_size, 0.5, 5.0)
 if rv then SetModeSetting("transport_border_size", current_border_size) end
 end
 end
 
 if settings.transport_mode == 2 then
 r.ImGui_Separator(ctx)
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Custom Button Images:")
 r.ImGui_Separator(ctx)
 
 rv, settings.use_locked_button_folder = r.ImGui_Checkbox(ctx, "Use Locked Folder", settings.use_locked_button_folder)
 if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
 r.ImGui_TextWrapped(ctx, "Folder: " .. settings.locked_button_folder_path)
 end
 
 r.ImGui_Separator(ctx)
 
 local function ImageRow(label, use_key, path_key, size_key, suffix, browseTitle)
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableNextColumn(ctx)
 r.ImGui_Text(ctx, label)
 r.ImGui_TableNextColumn(ctx)
 local rv_en, new_enable = r.ImGui_Checkbox(ctx, "##enable_"..suffix, settings[use_key])
 if rv_en then 
 settings[use_key] = new_enable
 UpdateCustomImages()  
 end
 r.ImGui_TableNextColumn(ctx)
 if settings[use_key] then
 if r.ImGui_Button(ctx, "Browse##"..suffix, -1, 0) then
 local start_dir = ""
 if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
 start_dir = settings.locked_button_folder_path
 end
 local retval, file = r.GetUserFileNameForRead(start_dir, browseTitle, ".png")
 if retval then
 settings[path_key] = file
 if settings.use_locked_button_folder then
 settings.locked_button_folder_path = file:match("(.*[\\/])") or ""
 end
 UpdateCustomImages()
 end
 end
 else
 r.ImGui_TextDisabled(ctx, "Disabled")
 end
 r.ImGui_TableNextColumn(ctx)
 do
 local img_handle = transport_custom_images[string.lower(suffix)]
 local size = 16
 if settings[use_key] and img_handle and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(img_handle, 'ImGui_Image*')) then
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetCursorScreenPos(ctx)
 local max_x, max_y = min_x + size, min_y + size
 r.ImGui_DrawList_AddImage(draw_list, img_handle, min_x, min_y, max_x, max_y, 0.0, 0.0, 1/3, 1.0)
 r.ImGui_Dummy(ctx, size, size)
 else
 r.ImGui_TextDisabled(ctx, "N/A")
 end
 end
 r.ImGui_TableNextColumn(ctx)
 r.ImGui_SetNextItemWidth(ctx, -1)
 local rv_sz, new_sz = r.ImGui_SliderDouble(ctx, "##size_"..suffix, settings[size_key], 0.5, 2.0, "%.2f")
 if rv_sz then settings[size_key] = new_sz end
 end
 
 if r.ImGui_BeginTable(ctx, "TB_ImageTable", 5, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Button")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Enable")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Image File")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Preview")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Size")
 
 ImageRow("Rewind", 'use_custom_rewind_image', 'custom_rewind_image_path', 'custom_rewind_image_size', 'Rewind', "Select Rewind Button Image")
 ImageRow("Play", 'use_custom_play_image', 'custom_play_image_path', 'custom_play_image_size', 'Play', "Select Play Button Image")
 ImageRow("Stop", 'use_custom_stop_image', 'custom_stop_image_path', 'custom_stop_image_size', 'Stop', "Select Stop Button Image")
 ImageRow("Pause", 'use_custom_pause_image', 'custom_pause_image_path', 'custom_pause_image_size', 'Pause', "Select Pause Button Image")
 ImageRow("Record", 'use_custom_record_image', 'custom_record_image_path', 'custom_record_image_size', 'Record', "Select Record Button Image")
 ImageRow("Loop", 'use_custom_loop_image', 'custom_loop_image_path', 'custom_loop_image_size', 'Loop', "Select Loop Button Image")
 ImageRow("Forward", 'use_custom_forward_image', 'custom_forward_image_path', 'custom_forward_image_size', 'Forward', "Select Forward Button Image")
 r.ImGui_EndTable(ctx)
 end
 end
 end
end

local function ShowAlarmPopup()
 if not settings.time_alarm_popup_enabled then return end
 if not settings.time_alarm_triggered then return end
 
 local current_time = r.time_precise()
 local popup_size = settings.time_alarm_popup_size or 300
 local text = settings.time_alarm_popup_text or "? ALARM! ?"
 
 local dismiss_time = settings.time_alarm_auto_dismiss_seconds or 10
 if settings.time_alarm_auto_dismiss and settings.time_alarm_start_time > 0 then
     if (current_time - settings.time_alarm_start_time) > dismiss_time then
         settings.time_alarm_triggered = false
         return
     end
 end
 
 local main_viewport = r.ImGui_GetMainViewport(ctx)
 local work_pos_x, work_pos_y = r.ImGui_Viewport_GetWorkPos(main_viewport)
 local work_size_x, work_size_y = r.ImGui_Viewport_GetWorkSize(main_viewport)
 
 local popup_x = work_pos_x + (work_size_x - popup_size) * 0.5
 local popup_y = work_pos_y + (work_size_y - popup_size * 0.5) * 0.3
 
 r.ImGui_SetNextWindowPos(ctx, popup_x, popup_y)
 r.ImGui_SetNextWindowSize(ctx, popup_size, popup_size * 0.5)
 
 local large_font_size = settings.time_alarm_popup_text_size or 20
 local alarm_font = r.ImGui_CreateFont("Arial", large_font_size)
 r.ImGui_Attach(ctx, alarm_font)
 
 r.ImGui_PushFont(ctx, alarm_font, large_font_size)
 
 local text_w, text_h = r.ImGui_CalcTextSize(ctx, text)
 
 r.ImGui_PopFont(ctx)
 
 local flash_speed = 2.0
 local alpha = 0.8 + 0.2 * math.sin(current_time * flash_speed)
 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_Alpha(), alpha)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), settings.time_alarm_flash_color or 0xFF0000FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), settings.time_alarm_flash_color or 0xFF0000FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), settings.time_alarm_flash_color or 0xFF0000FF)
 
 local window_flags = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoMove() | r.ImGui_WindowFlags_TopMost()
 
 if r.ImGui_Begin(ctx, "ALARM!", true, window_flags) then
     local window_width = r.ImGui_GetWindowWidth(ctx)
     local window_height = r.ImGui_GetWindowHeight(ctx)
     
     r.ImGui_SetCursorPosX(ctx, (window_width - text_w) * 0.5)
     r.ImGui_SetCursorPosY(ctx, (window_height - text_h) * 0.3)
     
     r.ImGui_PushFont(ctx, alarm_font, large_font_size)
     r.ImGui_Text(ctx, text)
     r.ImGui_PopFont(ctx)
     
     local time_str = os.date("%H:%M:%S")
     local time_w = r.ImGui_CalcTextSize(ctx, time_str)
     r.ImGui_SetCursorPosX(ctx, (window_width - time_w) * 0.5)
     r.ImGui_Text(ctx, time_str)
     
     r.ImGui_Spacing(ctx)
     
     local button_width = 100
     r.ImGui_SetCursorPosX(ctx, (window_width - button_width) * 0.5)
     if r.ImGui_Button(ctx, "Dismiss", button_width, 30) then
         settings.time_alarm_triggered = false
     end
     
     r.ImGui_End(ctx)
 end
 
 r.ImGui_PopStyleColor(ctx, 3)
 r.ImGui_PopStyleVar(ctx, 1)
end

function ShowTimeDisplaySettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_local_time = r.ImGui_Checkbox(ctx, "Show Time Display", settings.show_local_time ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_local_time then
 r.ImGui_Spacing(ctx)
 
 rv, settings.time_display_hide_seconds = r.ImGui_Checkbox(ctx, "Hide Seconds", settings.time_display_hide_seconds or false)
 
 r.ImGui_Separator(ctx)
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('local_time_x', 'local_time_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "LocalTimeFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.local_time_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##LocalTimeFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.local_time_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.local_time_font_size = r.ImGui_SliderInt(ctx, "##LocalTimeSize", settings.local_time_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end

 r.ImGui_EndTable(ctx)
 end

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 rv, settings.local_time_color = r.ImGui_ColorEdit4(ctx, "Text Color", settings.local_time_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Alarm/Timer:")
 r.ImGui_SameLine(ctx)
 rv, settings.time_alarm_enabled = r.ImGui_Checkbox(ctx, "Enable##alarm", settings.time_alarm_enabled or false)
 
 if settings.time_alarm_enabled then
     r.ImGui_Spacing(ctx)
     
     if r.ImGui_BeginTable(ctx, "AlarmMainSettings", 3, r.ImGui_TableFlags_SizingStretchSame()) then
         r.ImGui_TableNextRow(ctx)
         
         r.ImGui_TableSetColumnIndex(ctx, 0)
         local alarm_types = {"time", "duration"}
         local current_type_index = 0
         for i, alarm_type in ipairs(alarm_types) do
             if alarm_type == settings.time_alarm_type then
                 current_type_index = i - 1
                 break
             end
         end
         r.ImGui_SetNextItemWidth(ctx, -1)
         rv, current_type_index = r.ImGui_Combo(ctx, "##alarm_type", current_type_index, "Time\0Duration\0")
         if rv then
             settings.time_alarm_type = alarm_types[current_type_index + 1]
         end
         
         r.ImGui_TableSetColumnIndex(ctx, 1)
         if settings.time_alarm_type == "time" then
             r.ImGui_PushItemWidth(ctx, 75)
             rv, settings.time_alarm_hour = r.ImGui_InputInt(ctx, "##hour_input", settings.time_alarm_hour or 12)
             if rv then
                 settings.time_alarm_hour = math.max(0, math.min(23, settings.time_alarm_hour))
                 settings.time_alarm_triggered = false
             end
             r.ImGui_PopItemWidth(ctx)
             
             r.ImGui_SameLine(ctx)
             r.ImGui_Text(ctx, ":")
             r.ImGui_SameLine(ctx)
             
             r.ImGui_PushItemWidth(ctx, 75)
             rv, settings.time_alarm_minute = r.ImGui_InputInt(ctx, "##minute_input", settings.time_alarm_minute or 0)
             if rv then
                 settings.time_alarm_minute = math.max(0, math.min(59, settings.time_alarm_minute))
                 settings.time_alarm_triggered = false
             end
             r.ImGui_PopItemWidth(ctx)
             
         elseif settings.time_alarm_type == "duration" then
             r.ImGui_PushItemWidth(ctx, 80)
             rv, settings.time_alarm_duration_minutes = r.ImGui_InputInt(ctx, "##duration", settings.time_alarm_duration_minutes or 10)
             if rv then
                 settings.time_alarm_duration_minutes = math.max(1, settings.time_alarm_duration_minutes)
             end
             r.ImGui_PopItemWidth(ctx)
             r.ImGui_SameLine(ctx)
             r.ImGui_Text(ctx, "min")
         end
         
         r.ImGui_TableSetColumnIndex(ctx, 2)
         rv, settings.time_alarm_popup_enabled = r.ImGui_Checkbox(ctx, "Show Popup", settings.time_alarm_popup_enabled ~= false)
         
         r.ImGui_EndTable(ctx)
     end
     
     r.ImGui_Spacing(ctx)
     
     if settings.time_alarm_type == "duration" then
         if r.ImGui_Button(ctx, "Start Timer") then
             settings.time_alarm_start_time = os.time()
             settings.time_alarm_triggered = false
         end
         r.ImGui_SameLine(ctx)
         if r.ImGui_Button(ctx, "Stop Timer") then
             settings.time_alarm_start_time = 0
             settings.time_alarm_triggered = false
         end
         r.ImGui_SameLine(ctx)
         
         if settings.time_alarm_start_time > 0 then
             local elapsed = math.floor((os.time() - settings.time_alarm_start_time) / 60)
             local remaining = math.max(0, settings.time_alarm_duration_minutes - elapsed)
             r.ImGui_Text(ctx, string.format("Elapsed: %d/%d minutes", elapsed, settings.time_alarm_duration_minutes))
             if remaining == 0 then
                 r.ImGui_SameLine(ctx)
                 r.ImGui_TextColored(ctx, 0xFF4444FF, "DONE!")
             end
         end
         r.ImGui_SameLine(ctx)
     end
     
     if r.ImGui_Button(ctx, "Test Alarm") then
         settings.time_alarm_triggered = true
         settings.time_alarm_start_time = os.time()
         ShowAlarmPopup()
     end
     
     r.ImGui_Spacing(ctx)
     
     rv, settings.time_alarm_auto_dismiss = r.ImGui_Checkbox(ctx, "Auto Dismiss", settings.time_alarm_auto_dismiss ~= false)
     if settings.time_alarm_auto_dismiss then
         r.ImGui_SameLine(ctx)
         r.ImGui_PushItemWidth(ctx, 75)
         rv, settings.time_alarm_auto_dismiss_seconds = r.ImGui_InputInt(ctx, "##auto_dismiss_time", settings.time_alarm_auto_dismiss_seconds or 10)
         if rv then
             settings.time_alarm_auto_dismiss_seconds = math.max(3, math.min(60, settings.time_alarm_auto_dismiss_seconds))
         end
         r.ImGui_PopItemWidth(ctx)
         r.ImGui_SameLine(ctx)
         r.ImGui_Text(ctx, "seconds")
     end
     
     r.ImGui_Spacing(ctx)
     
     if r.ImGui_BeginTable(ctx, "PopupSettings", 3, r.ImGui_TableFlags_SizingStretchSame()) then
         r.ImGui_TableNextRow(ctx)
         
         r.ImGui_TableSetColumnIndex(ctx, 0)
         r.ImGui_SetNextItemWidth(ctx, -1)
         rv, settings.time_alarm_popup_text = r.ImGui_InputText(ctx, "##popup_text", settings.time_alarm_popup_text or "? ALARM! ?")
         
         r.ImGui_TableSetColumnIndex(ctx, 1)
         r.ImGui_SetNextItemWidth(ctx, -1)
         rv, settings.time_alarm_popup_text_size = r.ImGui_InputInt(ctx, "##popup_size", math.floor(settings.time_alarm_popup_text_size or 20))
         if rv then 
             settings.time_alarm_popup_text_size = math.max(8, math.min(72, settings.time_alarm_popup_text_size))
         end
         
         r.ImGui_TableSetColumnIndex(ctx, 2)
         r.ImGui_SetNextItemWidth(ctx, -1)
         rv, settings.time_alarm_popup_size = r.ImGui_InputInt(ctx, "##popup_window_size", settings.time_alarm_popup_size or 300)
         if rv then
             settings.time_alarm_popup_size = math.max(200, math.min(600, settings.time_alarm_popup_size))
         end
         
         r.ImGui_EndTable(ctx)
     end
     
     r.ImGui_Spacing(ctx)
     
     if r.ImGui_BeginTable(ctx, "AlarmColors", 2, r.ImGui_TableFlags_SizingStretchSame()) then
         r.ImGui_TableNextRow(ctx)
         
         r.ImGui_TableSetColumnIndex(ctx, 0)
         local color_flags = r.ImGui_ColorEditFlags_NoInputs()
         rv, settings.time_alarm_set_color = r.ImGui_ColorEdit4(ctx, "##alarm_set", settings.time_alarm_set_color or 0xFFFF00FF, color_flags)
         r.ImGui_SameLine(ctx)
         r.ImGui_Text(ctx, "Alarm Set Color")
         
         r.ImGui_TableSetColumnIndex(ctx, 1)
         rv, settings.time_alarm_flash_color = r.ImGui_ColorEdit4(ctx, "##alarm_flash", settings.time_alarm_flash_color or 0xFF0000FF, color_flags)
         r.ImGui_SameLine(ctx)
         r.ImGui_Text(ctx, "Alarm Active Color")
         
         r.ImGui_EndTable(ctx)
     end
 end
 end
end

function ShowBatteryStatusSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_battery_status = r.ImGui_Checkbox(ctx, "Show Battery Status", settings.show_battery_status or false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_battery_status then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_TextWrapped(ctx, "Manual Update Only: Click on battery display to refresh (prevents freezing)")
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('battery_x', 'battery_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Display Options:")
 rv, settings.battery_show_icon = r.ImGui_Checkbox(ctx, "Show Icon", settings.battery_show_icon ~= false)
 rv, settings.battery_show_percentage = r.ImGui_Checkbox(ctx, "Show Percentage", settings.battery_show_percentage ~= false)
 rv, settings.battery_use_custom_icon = r.ImGui_Checkbox(ctx, "Use Custom Icon (Advanced)", settings.battery_use_custom_icon or false)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "BatteryFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 
 local current_font = settings.battery_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##BatteryFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.battery_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.battery_font_size = r.ImGui_SliderInt(ctx, "##BatterySize", settings.battery_font_size or 14, 8, 48)
 if rv then
 RebuildSectionFonts()
 end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 rv, settings.battery_color_high = r.ImGui_ColorEdit4(ctx, "High (>60%)", settings.battery_color_high or 0x00FF00FF, color_flags)
 rv, settings.battery_color_medium = r.ImGui_ColorEdit4(ctx, "Medium (20-60%)", settings.battery_color_medium or 0xFFFF00FF, color_flags)
 rv, settings.battery_color_low = r.ImGui_ColorEdit4(ctx, "Low (<20%)", settings.battery_color_low or 0xFF0000FF, color_flags)
 rv, settings.battery_color_charging = r.ImGui_ColorEdit4(ctx, "Charging", settings.battery_color_charging or 0x00FFFFFF, color_flags)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Warning Thresholds:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.battery_warning_threshold = r.ImGui_SliderInt(ctx, "Warning Level (%)", settings.battery_warning_threshold or 20, 5, 50)
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.battery_critical_threshold = r.ImGui_SliderInt(ctx, "Critical Level (%) - Blinking", settings.battery_critical_threshold or 10, 5, 30)
 end
end

function ShowMasterVolumeSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_master_volume = r.ImGui_Checkbox(ctx, "Show Master Volume Slider", settings.show_master_volume ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_master_volume then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('master_volume_x', 'master_volume_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Slider Width:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 local slider_width = settings.master_volume_width or 150
 rv, slider_width = r.ImGui_SliderInt(ctx, "##MasterVolumeWidth", slider_width, 50, 400)
 if rv then
 settings.master_volume_width = slider_width
 end
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Separator(ctx)
 
 rv, settings.show_master_volume_label = r.ImGui_Checkbox(ctx, "Show Label", settings.show_master_volume_label ~= false)
 
 r.ImGui_Spacing(ctx)
 
 if r.ImGui_BeginTable(ctx, "MasterVolumeFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.master_volume_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##MasterVolumeFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.master_volume_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 local font_size = settings.master_volume_font_size or settings.font_size
 rv, font_size = r.ImGui_SliderInt(ctx, "##MasterVolumeFontSize", font_size, 8, 72)
 if rv then
 settings.master_volume_font_size = font_size
 RebuildSectionFonts()
 end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "MasterVolumeColors", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.master_volume_slider_bg = r.ImGui_ColorEdit4(ctx, "Slider BG", settings.master_volume_slider_bg or 0x333333FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.master_volume_slider_active = r.ImGui_ColorEdit4(ctx, "Slider Active", settings.master_volume_slider_active or 0x555555FF, color_flags)
 
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.master_volume_grab = r.ImGui_ColorEdit4(ctx, "Handle", settings.master_volume_grab or 0xFFFFFFFF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.master_volume_grab_active = r.ImGui_ColorEdit4(ctx, "Handle Hover", settings.master_volume_grab_active or 0xAAAAAAFF, color_flags)
 
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.master_volume_text_color = r.ImGui_ColorEdit4(ctx, "Text Color", settings.master_volume_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Border & Rounding:")
 
 rv, settings.master_volume_show_border = r.ImGui_Checkbox(ctx, "Show Border", settings.master_volume_show_border or false)
 
 if settings.master_volume_show_border then
 r.ImGui_Spacing(ctx)
 
 if r.ImGui_BeginTable(ctx, "MasterVolumeBorderTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Border Color:")
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.master_volume_border_color = r.ImGui_ColorEdit4(ctx, "##MasterVolumeBorderColor", settings.master_volume_border_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Border Size:")
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.master_volume_border_size = r.ImGui_SliderDouble(ctx, "##MasterVolumeBorderSize", settings.master_volume_border_size or 1.0, 0.5, 5.0, "%.1f")
 
 r.ImGui_EndTable(ctx)
 end
 end
 
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Rounding:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.master_volume_rounding = r.ImGui_SliderDouble(ctx, "##MasterVolumeRounding", settings.master_volume_rounding or 0.0, 0.0, 12.0, "%.1f")
 
 r.ImGui_Spacing(ctx)
 end
end

function ShowEnvelopeSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_env_button = r.ImGui_Checkbox(ctx, "Show Envelope Button", settings.show_env_button ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_env_button then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('env_x', 'env_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "EnvFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.env_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##EnvFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.env_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.env_font_size = r.ImGui_SliderInt(ctx, "##EnvSize", settings.env_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "EnvelopeColors", 4, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.env_button_color = r.ImGui_ColorEdit4(ctx, "Normal", settings.env_button_color or 0x333333FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.env_button_color_hover = r.ImGui_ColorEdit4(ctx, "Hover", settings.env_button_color_hover or 0x444444FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.env_button_color_active = r.ImGui_ColorEdit4(ctx, "Active", settings.env_button_color_active or 0x555555FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 3)
 rv, settings.env_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.env_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.env_override_active_color = r.ImGui_ColorEdit4(ctx, "Override", settings.env_override_active_color or 0x66CC66FF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Button Rounding:")
 r.ImGui_SetNextItemWidth(ctx, 150)
 rv, settings.env_button_rounding = r.ImGui_SliderDouble(ctx, "##EnvRounding", settings.env_button_rounding or 0, 0, 20, "%.0f px")
 
 ShowBorderControls("env")
 end
end

function ShowTempoBPMSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_tempo = r.ImGui_Checkbox(ctx, "Show Tempo (BPM)", settings.show_tempo ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_tempo then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('tempo_x', 'tempo_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "TempoFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.tempo_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##TempoFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.tempo_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.tempo_font_size = r.ImGui_SliderInt(ctx, "##TempoSize", settings.tempo_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end

 r.ImGui_EndTable(ctx)
 end

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 local rv
 
 if r.ImGui_BeginTable(ctx, "TempoColors", 3, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.tempo_button_color = r.ImGui_ColorEdit4(ctx, "Normal", settings.tempo_button_color or 0x333333FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.tempo_button_color_hover = r.ImGui_ColorEdit4(ctx, "Hover", settings.tempo_button_color_hover or 0x444444FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.tempo_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.tempo_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Button Rounding:")
 r.ImGui_SetNextItemWidth(ctx, 150)
 rv, settings.tempo_button_rounding = r.ImGui_SliderDouble(ctx, "##TempoRounding", settings.tempo_button_rounding or 0, 0, 20, "%.0f px")
 
 ShowBorderControls("tempo")
 end
end

function ShowTimeSignatureSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_timesig = r.ImGui_Checkbox(ctx, "Show Time Signature", settings.show_timesig ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_timesig then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('timesig_x', 'timesig_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "TimeSigFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.timesig_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##TimeSigFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.timesig_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.timesig_font_size = r.ImGui_SliderInt(ctx, "##TimeSigSize", settings.timesig_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end

 r.ImGui_EndTable(ctx)
 end

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "TimeSigColors", 4, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.timesig_button_color = r.ImGui_ColorEdit4(ctx, "Normal", settings.timesig_button_color or 0x333333FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.timesig_button_color_hover = r.ImGui_ColorEdit4(ctx, "Hover", settings.timesig_button_color_hover or 0x444444FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.timesig_button_color_active = r.ImGui_ColorEdit4(ctx, "Active", settings.timesig_button_color_active or 0x555555FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 3)
 rv, settings.timesig_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.timesig_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Button Rounding:")
 r.ImGui_SetNextItemWidth(ctx, 150)
 rv, settings.timesig_button_rounding = r.ImGui_SliderDouble(ctx, "##TimeSigRounding", settings.timesig_button_rounding or 0, 0, 20, "%.0f px")
 
 ShowBorderControls("timesig")
 end
end

function ShowTimeSelectionSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_timesel = r.ImGui_Checkbox(ctx, "Show Time Selection", settings.show_timesel ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_timesel then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('timesel_x', 'timesel_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "TimeSelFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.timesel_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##TimeSelFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.timesel_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.timesel_font_size = r.ImGui_SliderInt(ctx, "##TimeSelSize", settings.timesel_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end

 r.ImGui_EndTable(ctx)
 end

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "TimeSelColors", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.timesel_color = r.ImGui_ColorEdit4(ctx, "Normal", settings.timesel_color or 0x333333FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.timesel_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.timesel_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 rv, settings.timesel_toggle_invisible = r.ImGui_Checkbox(ctx, "Toggle Invisible Button", settings.timesel_toggle_invisible or false)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Display Options:")
 rv, settings.show_time = r.ImGui_Checkbox(ctx, "Show Time", settings.show_time ~= false)
 r.ImGui_SameLine(ctx)
 rv, settings.show_beats = r.ImGui_Checkbox(ctx, "Show Beats", settings.show_beats ~= false)
 
 r.ImGui_Text(ctx, "Button Rounding:")
 r.ImGui_SetNextItemWidth(ctx, 150)
 rv, settings.timesel_button_rounding = r.ImGui_SliderDouble(ctx, "##TimeSelRounding", settings.timesel_button_rounding or 0, 0, 20, "%.0f px")
 
 ShowBorderControls("timesel")
 end
end

function ShowCursorPositionSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_cursorpos = r.ImGui_Checkbox(ctx, "Show Cursor Position", settings.show_cursorpos ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_cursorpos then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('cursorpos_x', 'cursorpos_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "CursorPosFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.cursorpos_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##CursorPosFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.cursorpos_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.cursorpos_font_size = r.ImGui_SliderInt(ctx, "##CursorPosSize", settings.cursorpos_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end

 r.ImGui_EndTable(ctx)
 end

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "CursorPosColors", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.cursorpos_button_color = r.ImGui_ColorEdit4(ctx, "Normal", settings.cursorpos_button_color or 0x333333FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.cursorpos_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.cursorpos_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 rv, settings.cursorpos_toggle_invisible = r.ImGui_Checkbox(ctx, "Toggle Invisible Button", settings.cursorpos_toggle_invisible or false)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Display Mode:")
 local mode = settings.cursorpos_mode or "both"
 if r.ImGui_RadioButton(ctx, "Beats (MBT)", mode == "beats") then settings.cursorpos_mode = "beats" end
 r.ImGui_SameLine(ctx)
 if r.ImGui_RadioButton(ctx, "Time", mode == "time") then settings.cursorpos_mode = "time" end
 r.ImGui_SameLine(ctx)
 if r.ImGui_RadioButton(ctx, "Both", mode == "both") then settings.cursorpos_mode = "both" end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Button Rounding:")
 rv, settings.cursorpos_button_rounding = r.ImGui_SliderDouble(ctx, "##CursorPosRounding", settings.cursorpos_button_rounding or 0.0, 0.0, 20.0, "%.1f px")
 
 ShowBorderControls("cursorpos")
 end
end

function ShowWaveScrubberSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_waveform_scrubber = r.ImGui_Checkbox(ctx, "Show Wave Scrubber", settings.show_waveform_scrubber ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_waveform_scrubber then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('waveform_scrubber_x', 'waveform_scrubber_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "WaveScrubSizeTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Width:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.waveform_scrubber_width = r.ImGui_SliderInt(ctx, "##WaveWidth", settings.waveform_scrubber_width or 200, 100, 500, "%d px")
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Height:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.waveform_scrubber_height = r.ImGui_SliderInt(ctx, "##WaveHeight", settings.waveform_scrubber_height or 40, 20, 100, "%d px")

 r.ImGui_EndTable(ctx)
 end

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "WaveScrubColors", 5, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.waveform_scrubber_bg_color = r.ImGui_ColorEdit4(ctx, "Background", settings.waveform_scrubber_bg_color or 0x222222FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.waveform_scrubber_wave_color = r.ImGui_ColorEdit4(ctx, "Waveform", settings.waveform_scrubber_wave_color or 0x00AA00FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.waveform_scrubber_playhead_color = r.ImGui_ColorEdit4(ctx, "Playhead", settings.waveform_scrubber_playhead_color or 0xFF0000FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 3)
 rv, settings.waveform_scrubber_border_color = r.ImGui_ColorEdit4(ctx, "Border", settings.waveform_scrubber_border_color or 0x666666FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 4)
 rv, settings.waveform_scrubber_grid_color = r.ImGui_ColorEdit4(ctx, "Grid", settings.waveform_scrubber_grid_color or 0x444444FF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Display Options:")
 rv, settings.waveform_scrubber_show_grid = r.ImGui_Checkbox(ctx, "Show Grid", settings.waveform_scrubber_show_grid ~= false)
 r.ImGui_SameLine(ctx)
 rv, settings.waveform_scrubber_show_time_labels = r.ImGui_Checkbox(ctx, "Show Time Labels", settings.waveform_scrubber_show_time_labels ~= false)
 r.ImGui_SameLine(ctx)
 rv, settings.waveform_scrubber_show_full_project = r.ImGui_Checkbox(ctx, "Show Full Project", settings.waveform_scrubber_show_full_project or false)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Behavior:")
 rv, settings.waveform_scrubber_window_size = r.ImGui_SliderDouble(ctx, "Window Size", settings.waveform_scrubber_window_size or 10.0, 1.0, 60.0, "%.1f sec")
 rv, settings.waveform_scrubber_handle_size = r.ImGui_SliderInt(ctx, "Handle Size", settings.waveform_scrubber_handle_size or 8, 4, 20, "%d px")
 end
end

function ShowShuttleWheelSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_shuttle_wheel = r.ImGui_Checkbox(ctx, "Show Shuttle Wheel", settings.show_shuttle_wheel ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_shuttle_wheel then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('shuttle_wheel_x', 'shuttle_wheel_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Size:")
 rv, settings.shuttle_wheel_radius = r.ImGui_SliderInt(ctx, "Radius", settings.shuttle_wheel_radius or 30, 10, 60, "%d px")

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "ShuttleColors", 3, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.shuttle_wheel_color = r.ImGui_ColorEdit4(ctx, "Normal", settings.shuttle_wheel_color or 0x444444FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.shuttle_wheel_active_color = r.ImGui_ColorEdit4(ctx, "Active", settings.shuttle_wheel_active_color or 0x0088FFFF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.shuttle_wheel_border_color = r.ImGui_ColorEdit4(ctx, "Border", settings.shuttle_wheel_border_color or 0x666666FF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Behavior:")
 rv, settings.shuttle_wheel_sensitivity = r.ImGui_SliderDouble(ctx, "Sensitivity", settings.shuttle_wheel_sensitivity or 2.0, 0.5, 5.0, "%.1f")
 rv, settings.shuttle_wheel_max_speed = r.ImGui_SliderDouble(ctx, "Max Speed", settings.shuttle_wheel_max_speed or 10.0, 1.0, 20.0, "%.1f")
 end
end

function ShowVisualMetronomeSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_visual_metronome = r.ImGui_Checkbox(ctx, "Show Visual Metronome", settings.show_visual_metronome ~= false)
 if rv and settings.show_visual_metronome then
 InitializeVisualMetronome()
 end
 
 r.ImGui_Separator(ctx)
 
 if settings.show_visual_metronome then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('visual_metronome_x', 'visual_metronome_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Size:")
 rv, settings.visual_metronome_size = r.ImGui_SliderInt(ctx, "Size", settings.visual_metronome_size or 40, 10, 100, "%d px")

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "MetronomeColors", 4, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.visual_metronome_color_beat = r.ImGui_ColorEdit4(ctx, "Beat", settings.visual_metronome_color_beat or 0x00FF00FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.visual_metronome_color_offbeat = r.ImGui_ColorEdit4(ctx, "Off-Beat", settings.visual_metronome_color_offbeat or 0xFF0000FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.visual_metronome_color_ring = r.ImGui_ColorEdit4(ctx, "Ring", settings.visual_metronome_color_ring or 0x0080FFFF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 3)
 rv, settings.visual_metronome_color_off = r.ImGui_ColorEdit4(ctx, "Off", settings.visual_metronome_color_off or 0x333333FF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Display Options:")
 rv, settings.visual_metronome_show_beat_flash = r.ImGui_Checkbox(ctx, "Beat Flash", settings.visual_metronome_show_beat_flash ~= false)
 r.ImGui_SameLine(ctx)
 rv, settings.visual_metronome_show_position_ring = r.ImGui_Checkbox(ctx, "Position Ring", settings.visual_metronome_show_position_ring ~= false)
 r.ImGui_SameLine(ctx)
 rv, settings.visual_metronome_show_beat_numbers = r.ImGui_Checkbox(ctx, "Beat Numbers", settings.visual_metronome_show_beat_numbers ~= false)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Behavior:")
 rv, settings.visual_metronome_fade_speed = r.ImGui_SliderDouble(ctx, "Fade Speed", settings.visual_metronome_fade_speed or 8.0, 1.0, 20.0, "%.1f")
 rv, settings.visual_metronome_ring_thickness = r.ImGui_SliderInt(ctx, "Ring Thickness", settings.visual_metronome_ring_thickness or 3, 1, 10, "%d px")
 end
end

function ShowMatrixTickerSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_matrix_ticker = r.ImGui_Checkbox(ctx, "Show Matrix Ticker", settings.show_matrix_ticker ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_matrix_ticker then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('matrix_ticker_x', 'matrix_ticker_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Size:")
 rv, settings.matrix_ticker_width = r.ImGui_SliderInt(ctx, "Width", settings.matrix_ticker_width or 200, 100, 400, "%d px")
 rv, settings.matrix_ticker_height = r.ImGui_SliderInt(ctx, "Height", settings.matrix_ticker_height or 40, 20, 100, "%d px")
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Text Messages:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.matrix_ticker_text1 = r.ImGui_InputText(ctx, "##Text1", settings.matrix_ticker_text1 or "REAPER")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.matrix_ticker_text2 = r.ImGui_InputText(ctx, "##Text2", settings.matrix_ticker_text2 or "RECORDING")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.matrix_ticker_text3 = r.ImGui_InputText(ctx, "##Text3", settings.matrix_ticker_text3 or "STUDIO")
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Font:")
 rv, settings.matrix_ticker_font_size = r.ImGui_SliderInt(ctx, "Font Size", settings.matrix_ticker_font_size or 14, 8, 32, "%d px")
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "MatrixTickerColors", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.matrix_ticker_bg_color = r.ImGui_ColorEdit4(ctx, "Background", settings.matrix_ticker_bg_color or 0x003300FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.matrix_ticker_border_color = r.ImGui_ColorEdit4(ctx, "Border", settings.matrix_ticker_border_color or 0x000000FF, color_flags)
 
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.matrix_ticker_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.matrix_ticker_text_color or 0x000000FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.matrix_ticker_grid_color = r.ImGui_ColorEdit4(ctx, "Grid", settings.matrix_ticker_grid_color or 0x00FF0088, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Behavior:")
 rv, settings.matrix_ticker_switch_interval = r.ImGui_SliderDouble(ctx, "Switch Interval (seconds)", settings.matrix_ticker_switch_interval or 10.0, 1.0, 60.0, "%.1f")
 rv, settings.matrix_ticker_grid_size = r.ImGui_SliderInt(ctx, "Grid Size", settings.matrix_ticker_grid_size or 2, 1, 5, "%d px")
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Display Options:")
 rv, settings.matrix_ticker_show_bezel = r.ImGui_Checkbox(ctx, "Show Bezel with Screws", settings.matrix_ticker_show_bezel ~= false)
 end
end

function ShowTapTempoSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_taptempo = r.ImGui_Checkbox(ctx, "Show TapTempo", settings.show_taptempo ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_taptempo then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('taptempo_x', 'taptempo_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "TapTempoFontTable", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Font:")
 local current_font = settings.taptempo_font_name or settings.current_font
 local current_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_font then
 current_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, current_font_index = r.ImGui_Combo(ctx, "##TapTempoFont", current_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.taptempo_font_name = fonts[current_font_index + 1]
 RebuildSectionFonts()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.taptempo_font_size = r.ImGui_SliderInt(ctx, "##TapTempoSize", settings.taptempo_font_size or settings.font_size, 8, 48)
 if rv then
 RebuildSectionFonts()
 end

 r.ImGui_EndTable(ctx)
 end

 r.ImGui_Separator(ctx)

 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 if r.ImGui_BeginTable(ctx, "TapTempoColors", 4, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.taptempo_button_color = r.ImGui_ColorEdit4(ctx, "Normal", settings.taptempo_button_color or 0x333333FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.taptempo_button_color_hover = r.ImGui_ColorEdit4(ctx, "Hover", settings.taptempo_button_color_hover or 0x444444FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.taptempo_button_color_active = r.ImGui_ColorEdit4(ctx, "Active", settings.taptempo_button_color_active or 0x555555FF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 3)
 rv, settings.taptempo_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.taptempo_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Settings:")
 rv, settings.set_tempo_on_tap = r.ImGui_Checkbox(ctx, "Set Tempo on Tap", settings.set_tempo_on_tap ~= false)
 
 r.ImGui_Text(ctx, "Button Rounding:")
 r.ImGui_SetNextItemWidth(ctx, 150)
 rv, settings.taptempo_button_rounding = r.ImGui_SliderDouble(ctx, "##TapTempoRounding", settings.taptempo_button_rounding or 0, 0, 20, "%.0f px")
 
 ShowBorderControls("taptempo")
 end
end

function ShowPlayrateSettings(ctx, main_window_width, main_window_height)
 local rv
 rv, settings.show_playrate = r.ImGui_Checkbox(ctx, "Show Playrate", settings.show_playrate ~= false)
 
 r.ImGui_Separator(ctx)
 
 if settings.show_playrate then
 r.ImGui_Spacing(ctx)
 
 r.ImGui_Text(ctx, "Position:")
 DrawPixelXYControls('playrate_x', 'playrate_y', main_window_width, main_window_height)
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Colors:")
 
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 
 if r.ImGui_BeginTable(ctx, "PlayrateColors", 3, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rv, settings.playrate_slider_color = r.ImGui_ColorEdit4(ctx, "Slider", settings.playrate_slider_color or 0x4444AAFF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rv, settings.playrate_handle_color = r.ImGui_ColorEdit4(ctx, "Handle", settings.playrate_handle_color or 0x6666DDFF, color_flags)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 rv, settings.playrate_text_color = r.ImGui_ColorEdit4(ctx, "Text", settings.playrate_text_color or 0xFFFFFFFF, color_flags)
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Handle:")
 rv, settings.playrate_handle_size = r.ImGui_SliderInt(ctx, "Size", settings.playrate_handle_size or 12, 6, 24, "%d px")
 rv, settings.playrate_handle_rounding = r.ImGui_SliderDouble(ctx, "Rounding", settings.playrate_handle_rounding or 6.0, 0.0, 12.0, "%.1f px")
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Frame:")
 rv, settings.playrate_frame_rounding = r.ImGui_SliderDouble(ctx, "Frame Rounding", settings.playrate_frame_rounding or 4.0, 0.0, 12.0, "%.1f px")
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Slider:")
 rv, settings.playrate_slider_width = r.ImGui_SliderInt(ctx, "Width", settings.playrate_slider_width or 120, 60, 300, "%d px")
 r.ImGui_TextDisabled(ctx, "Range: 0.25x - 4.0x")
 
 rv, settings.playrate_show_label = r.ImGui_Checkbox(ctx, "Show 'Rate:' Label", settings.playrate_show_label ~= false)
 
 ShowBorderControls("playrate")
 end
end

function ShowTransportButtonsImagesSettings(ctx, main_window_width, main_window_height)
 local rv
 local changed = false
 
 if not settings.use_graphic_buttons then
 r.ImGui_TextDisabled(ctx, "Enable 'Use Graphic Buttons' in Transport section to configure custom images")
 return
 end
 
 r.ImGui_Text(ctx, "Configure custom button images:")
 r.ImGui_Separator(ctx)
 
 rv, settings.use_locked_button_folder = r.ImGui_Checkbox(ctx, "Use Locked Folder", settings.use_locked_button_folder)
 if settings.use_locked_button_folder and settings.locked_button_folder_path ~= "" then
 r.ImGui_TextWrapped(ctx, "Folder: " .. settings.locked_button_folder_path)
 end
 
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Button Images:")
 
 local function ImageRow(label, use_key, path_key, size_key, suffix, browseTitle)
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableNextColumn(ctx)
 r.ImGui_Text(ctx, label)
 r.ImGui_TableNextColumn(ctx)
 local rv_en, new_enable = r.ImGui_Checkbox(ctx, "##enable_"..suffix, settings[use_key])
 if rv_en then settings[use_key] = new_enable; changed = changed or rv_en end
 r.ImGui_TableNextColumn(ctx)
 if settings[use_key] then
 if r.ImGui_Button(ctx, "Browse##"..suffix, -1, 0) then
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
 r.ImGui_TextDisabled(ctx, "Disabled")
 end
 r.ImGui_TableNextColumn(ctx)
 do
 local img_handle = transport_custom_images[string.lower(suffix)]
 local size = 16
 if settings[use_key] and img_handle and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(img_handle, 'ImGui_Image*')) then
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetCursorScreenPos(ctx)
 local max_x, max_y = min_x + size, min_y + size
 r.ImGui_DrawList_AddImage(draw_list, img_handle, min_x, min_y, max_x, max_y, 0.0, 0.0, 1/3, 1.0)
 r.ImGui_Dummy(ctx, size, size)
 else
 r.ImGui_TextDisabled(ctx, "N/A")
 end
 end
 r.ImGui_TableNextColumn(ctx)
 r.ImGui_SetNextItemWidth(ctx, -1)
 local rv_sz, new_sz = r.ImGui_SliderDouble(ctx, "##size_"..suffix, settings[size_key], 0.5, 2.0, "%.2f")
 if rv_sz then settings[size_key] = new_sz end
 end
 
 if r.ImGui_BeginTable(ctx, "TB_Table", 5, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Button")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Enable")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Image File")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Preview")
 r.ImGui_TableNextColumn(ctx); r.ImGui_Text(ctx, "Size")
 
 ImageRow("Rewind", 'use_custom_rewind_image', 'custom_rewind_image_path', 'custom_rewind_image_size', 'Rewind', "Select Rewind Button Image")
 ImageRow("Play", 'use_custom_play_image', 'custom_play_image_path', 'custom_play_image_size', 'Play', "Select Play Button Image")
 ImageRow("Stop", 'use_custom_stop_image', 'custom_stop_image_path', 'custom_stop_image_size', 'Stop', "Select Stop Button Image")
 ImageRow("Pause", 'use_custom_pause_image', 'custom_pause_image_path', 'custom_pause_image_size', 'Pause', "Select Pause Button Image")
 ImageRow("Record", 'use_custom_record_image', 'custom_record_image_path', 'custom_record_image_size', 'Record', "Select Record Button Image")
 ImageRow("Loop", 'use_custom_loop_image', 'custom_loop_image_path', 'custom_loop_image_size', 'Loop', "Select Loop Button Image")
 ImageRow("Forward", 'use_custom_forward_image', 'custom_forward_image_path', 'custom_forward_image_size', 'Forward', "Select Forward Button Image")
 r.ImGui_EndTable(ctx)
 end
 
 if changed then
 UpdateCustomImages()
 end
end

local font = r.ImGui_CreateFont(settings.current_font, settings.font_size)
local font_transport = r.ImGui_CreateFont(settings.transport_font_name or settings.current_font, settings.transport_font_size or settings.font_size)
local font_env = r.ImGui_CreateFont(settings.env_font_name or settings.current_font, settings.env_font_size or settings.font_size)
local font_master_volume = r.ImGui_CreateFont(settings.master_volume_font_name or settings.current_font, settings.master_volume_font_size or settings.font_size)
local font_tempo = r.ImGui_CreateFont(settings.tempo_font_name or settings.current_font, settings.tempo_font_size or settings.font_size)
local font_timesig = r.ImGui_CreateFont(settings.timesig_font_name or settings.current_font, settings.timesig_font_size or settings.font_size)
local font_timesel = r.ImGui_CreateFont(settings.timesel_font_name or settings.current_font, settings.timesel_font_size or settings.font_size)
local font_cursorpos = r.ImGui_CreateFont(settings.cursorpos_font_name or settings.current_font, settings.cursorpos_font_size or settings.font_size)
local font_localtime = r.ImGui_CreateFont(settings.local_time_font_name or settings.current_font, settings.local_time_font_size or settings.font_size)
local font_battery = r.ImGui_CreateFont(settings.battery_font_name or settings.current_font, settings.battery_font_size or 14)
local SETTINGS_UI_FONT_NAME = 'Segoe UI'
local SETTINGS_UI_FONT_SIZE = 13
local settings_ui_font = r.ImGui_CreateFont(SETTINGS_UI_FONT_NAME, SETTINGS_UI_FONT_SIZE)
local SETTINGS_UI_FONT_SMALL_SIZE = 10
local settings_ui_font_small = r.ImGui_CreateFont(SETTINGS_UI_FONT_NAME, SETTINGS_UI_FONT_SMALL_SIZE)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_transport)
r.ImGui_Attach(ctx, font_env)
r.ImGui_Attach(ctx, font_master_volume)
r.ImGui_Attach(ctx, font_tempo)
r.ImGui_Attach(ctx, font_timesig)
r.ImGui_Attach(ctx, font_timesel)
r.ImGui_Attach(ctx, font_cursorpos)
r.ImGui_Attach(ctx, font_localtime)
r.ImGui_Attach(ctx, font_battery)
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

 local col_Tab = enum({'ImGui_Col_Tab','Col_Tab'})
 local col_TabHovered = enum({'ImGui_Col_TabHovered','Col_TabHovered'})
 local col_TabActive = enum({'ImGui_Col_TabActive','Col_TabActive'})
 local col_TabUnf = enum({'ImGui_Col_TabUnfocused','Col_TabUnfocused','Col_TabDimmed'})
 local col_TabUnfAct = enum({'ImGui_Col_TabUnfocusedActive','Col_TabUnfocusedActive'})
 local col_TabDimmed = enum({'ImGui_Col_TabDimmed','Col_TabDimmed'})
 local col_TabDimmedSel = enum({'ImGui_Col_TabDimmedSelected','Col_TabDimmedSelected'})
 local col_TabDimmedOver = enum({'ImGui_Col_TabDimmedSelectedOverline','Col_TabDimmedSelectedOverline'})

 local hovered = Color_AdjustBrightness(baseColor, 1.15)
 local active = Color_AdjustBrightness(baseColor, 1.30)
 local unf = Color_AdjustBrightness(baseColor, 0.85)
 local unfAct = Color_AdjustBrightness(baseColor, 1.00)

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

 local col_Header = enum({'ImGui_Col_Header','Col_Header'})
 local col_HeaderHover = enum({'ImGui_Col_HeaderHovered','Col_HeaderHovered'})
 local col_HeaderActive = enum({'ImGui_Col_HeaderActive','Col_HeaderActive'})
 local col_Text = enum({'ImGui_Col_Text','Col_Text'})
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

function RebuildSectionFonts()
 local new_font_transport = r.ImGui_CreateFont(settings.transport_font_name or settings.current_font, settings.transport_font_size or settings.font_size)
 local new_font_env = r.ImGui_CreateFont(settings.env_font_name or settings.current_font, settings.env_font_size or settings.font_size)
 local new_font_master_volume = r.ImGui_CreateFont(settings.master_volume_font_name or settings.current_font, settings.master_volume_font_size or settings.font_size)
 local new_font_tempo = r.ImGui_CreateFont(settings.tempo_font_name or settings.current_font, settings.tempo_font_size or settings.font_size)
 local new_font_timesig = r.ImGui_CreateFont(settings.timesig_font_name or settings.current_font, settings.timesig_font_size or settings.font_size)
 local new_font_timesel = r.ImGui_CreateFont(settings.timesel_font_name or settings.current_font, settings.timesel_font_size or settings.font_size)
 local new_font_cursorpos = r.ImGui_CreateFont(settings.cursorpos_font_name or settings.current_font, settings.cursorpos_font_size or settings.font_size)
 local new_font_localtime = r.ImGui_CreateFont(settings.local_time_font_name or settings.current_font, settings.local_time_font_size or settings.font_size)
 local new_font_battery = r.ImGui_CreateFont(settings.battery_font_name or settings.current_font, settings.battery_font_size or 14)
 local new_font_popup = r.ImGui_CreateFont(settings.transport_popup_font_name or settings.current_font, settings.transport_popup_font_size or settings.font_size)
 local new_font_taptempo = r.ImGui_CreateFont(settings.taptempo_font_name or settings.current_font, settings.taptempo_font_size or settings.font_size)
 
 r.ImGui_Attach(ctx, new_font_transport)
 r.ImGui_Attach(ctx, new_font_env)
 r.ImGui_Attach(ctx, new_font_master_volume)
 r.ImGui_Attach(ctx, new_font_tempo)
 r.ImGui_Attach(ctx, new_font_timesig)
 r.ImGui_Attach(ctx, new_font_timesel)
 r.ImGui_Attach(ctx, new_font_cursorpos)
 r.ImGui_Attach(ctx, new_font_localtime)
 r.ImGui_Attach(ctx, new_font_battery)
 r.ImGui_Attach(ctx, new_font_popup)
 r.ImGui_Attach(ctx, new_font_taptempo)
 
 font_transport = new_font_transport
 font_env = new_font_env
 font_master_volume = new_font_master_volume
 font_tempo = new_font_tempo
 font_timesig = new_font_timesig
 font_timesel = new_font_timesel
 font_cursorpos = new_font_cursorpos
 font_localtime = new_font_localtime
 font_battery = new_font_battery
 font_popup = new_font_popup
 font_taptempo = new_font_taptempo
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
 transport_preset_has_unsaved_changes = false
end

function MarkTransportPresetChanged()
 transport_preset_has_unsaved_changes = true
end

function LoadSettings()
 if not settings.tempo_presets or type(settings.tempo_presets) ~= 'table' or #settings.tempo_presets == 0 then
 settings.tempo_presets = {60,80,100,120,140,160,180}
 end
end
LoadSettings()
UpdateCustomImages()
if not is_new_empty_instance then
 CustomButtons.LoadLastUsedPreset()
 if #CustomButtons.buttons == 0 then
 CustomButtons.LoadCurrentButtons()
 end
 CustomButtons.ResetToggleStatesIfNeeded(settings)
else
 CustomButtons.LoadLastUsedPreset()  
end

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
 
 preset_data.visual_metronome = {}
 for k, v in pairs(visual_metronome) do
 preset_data.visual_metronome[k] = v
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
 local success, preset_data = pcall(json.decode, content)
 
 if not success then
 r.ShowMessageBox("Error loading preset '" .. name .. "': " .. tostring(preset_data) .. "\n\nPreset may be corrupted.", "Preset Load Error", 0)
 return
 end
 
 for key, value in pairs(preset_data) do
 if key == "visual_metronome" and type(value) == "table" then
 for vm_key, vm_value in pairs(value) do
 visual_metronome[vm_key] = vm_value
 end
 else
 settings[key] = value
 end
 end
 
 if old_font_size ~= settings.font_size or old_font_name ~= settings.current_font then
 font_needs_update = true
 end
 UpdateCustomImages()
 transport_preset_has_unsaved_changes = false 
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

function Color_ToRGBA(color)
 local a = (color >> 24) & 0xFF
 local r = (color >> 16) & 0xFF
 local g = (color >> 8) & 0xFF
 local b = color & 0xFF
 return r/255, g/255, b/255, a/255
end

function Color_FromRGBA(r, g, b, a)
 return (math.floor(a*255) << 24) | (math.floor(r*255) << 16) | (math.floor(g*255) << 8) | math.floor(b*255)
end

function InitializeVisualMetronome()
 if not settings.show_visual_metronome then return end
 visual_metronome.last_beat_number = -1
 visual_metronome.beat_flash = 0
 visual_metronome.downbeat_flash = 0
 visual_metronome.beat_position = 0
end

function CleanupVisualMetronome()
 local master_track = r.GetMasterTrack(0)
 if master_track then
 local fx_count = r.TrackFX_GetCount(master_track)
 for i = fx_count - 1, 0, -1 do
 local retval, fx_name = r.TrackFX_GetFXName(master_track, i, "")
 if retval and fx_name and (fx_name == "TK_Visual_Metronome" or fx_name:find("JS: TK_Visual_Metronome")) then
 r.TrackFX_Delete(master_track, i)
 end
 end
 end
 visual_metronome.last_beat_number = -1
 visual_metronome.beat_flash = 0
 visual_metronome.downbeat_flash = 0
end

function UpdateVisualMetronome()
 if not settings.show_visual_metronome then return end
 
 local play_state = r.GetPlayState()
 local is_playing = (play_state & 1) == 1
 
 if not is_playing then
 visual_metronome.beat_flash = math.max(0, visual_metronome.beat_flash - ((settings.visual_metronome_fade_speed or 8.0) * (1/60)))
 visual_metronome.downbeat_flash = math.max(0, visual_metronome.downbeat_flash - ((settings.visual_metronome_fade_speed or 8.0) * (1/60)))
 visual_metronome.beat_position = 0
 visual_metronome.last_beat_number = -1
 return
 end
 
 local play_pos = r.GetPlayPosition()
 local retval, measures, cml, fullbeats, cdenom = r.TimeMap2_timeToBeats(0, play_pos)
 
 if retval then
 local timesig_num, timesig_denom = 4, 4
 local marker_count = r.CountTempoTimeSigMarkers(0)
 local marker_timepos = 0
 
 if marker_count > 0 then
 for i = marker_count - 1, 0, -1 do
 local ts_retval, timepos, measurepos, beatpos, bpm, ts_num, ts_denom, lineartempo = r.GetTempoTimeSigMarker(0, i)
 if ts_retval and timepos <= play_pos then
 timesig_num = ts_num
 timesig_denom = ts_denom
 marker_timepos = timepos
 break
 end
 end
 else
 local ts_retval, ts_bpm, ts_bpi = r.GetProjectTimeSignature2(0)
 if ts_retval and ts_bpi then
 timesig_num = ts_bpi
 timesig_denom = 4
 end
 end
 
 if not timesig_num or timesig_num <= 0 then
 timesig_num = 4
 end
 
 local beats_per_measure = math.floor(timesig_num)
 
 local marker_retval, marker_measures, marker_cml, marker_fullbeats, marker_cdenom = r.TimeMap2_timeToBeats(0, marker_timepos)
 
 local current_beat = math.floor(fullbeats)
 local beat_fraction = fullbeats - current_beat
 
 local beats_since_marker = fullbeats - marker_fullbeats
 local beat_in_measure_zero_based = math.floor(beats_since_marker) % beats_per_measure
 local beat_in_measure = beat_in_measure_zero_based + 1
 
 visual_metronome.beat_position = beat_fraction
 visual_metronome.current_beat_in_measure = beat_in_measure
 
 if not visual_metronome.last_beat_number then
 visual_metronome.last_beat_number = -1
 end
 
 if current_beat ~= visual_metronome.last_beat_number then
 visual_metronome.beat_flash = 1.0
 
 if beat_in_measure == 1 then
 visual_metronome.downbeat_flash = 1.0
 end
 
 visual_metronome.last_beat_number = current_beat
 end
 end
 
 visual_metronome.beat_flash = math.max(0, visual_metronome.beat_flash - ((settings.visual_metronome_fade_speed or 8.0) * (1/60)))
 visual_metronome.downbeat_flash = math.max(0, visual_metronome.downbeat_flash - ((settings.visual_metronome_fade_speed or 8.0) * (1/60)))
end

function RenderVisualMetronome(main_window_width, main_window_height)
 if not settings.show_visual_metronome then return end
 
 UpdateVisualMetronome()
 
 local x = settings.visual_metronome_x_px and ScalePosX(settings.visual_metronome_x_px, main_window_width, settings) or ((settings.visual_metronome_x or 0.85) * main_window_width)
 local y = settings.visual_metronome_y_px and ScalePosY(settings.visual_metronome_y_px, main_window_height, settings) or ((settings.visual_metronome_y or 0.15) * main_window_height)
 
 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, y)
 
 local size = settings.visual_metronome_size or 40
 r.ImGui_InvisibleButton(ctx, "##VisualMetronome", size, size)
 StoreElementRect("visual_metronome")
 
 if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Left()) then
  r.Main_OnCommand(40364, 0) -- Metronome: Toggle metronome enabled
 end
 
 if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
  r.Main_OnCommand(40363, 0) -- Metronome: Metronome settings
 end
 
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 local center_x, center_y = r.ImGui_GetItemRectMin(ctx)
 center_x = center_x + size * 0.5
 center_y = center_y + size * 0.5
 local radius = size * 0.4
 
 local bg_color = settings.visual_metronome_color_off or 0x808080FF
 r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, bg_color)
 
 local metronome_enabled = r.GetToggleCommandState(40364) == 1
 if metronome_enabled then
  local indicator_radius = size * 0.08
  local indicator_x = center_x + radius * 0.7
  local indicator_y = center_y - radius * 0.7
  local indicator_color = 0x00FF00FF 
  r.ImGui_DrawList_AddCircleFilled(draw_list, indicator_x, indicator_y, indicator_radius, indicator_color)
 end
 
 if settings.visual_metronome_show_beat_flash then
 local flash_intensity = math.max(visual_metronome.beat_flash, visual_metronome.downbeat_flash)
 if flash_intensity > 0.1 then
 local is_offbeat = visual_metronome.current_beat_in_measure == 1
 local flash_color = is_offbeat and (settings.visual_metronome_color_offbeat or 0xFF0000FF) or (settings.visual_metronome_color_beat or 0x00FF00FF)
 
 r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, flash_color)
 end
 end
 
 if settings.visual_metronome_show_beat_numbers and visual_metronome.current_beat_in_measure > 0 then
 local beat_text = tostring(visual_metronome.current_beat_in_measure)
 local text_size = r.ImGui_CalcTextSize(ctx, beat_text)
 local text_x = center_x - text_size * 0.5
 local text_y = center_y - r.ImGui_GetFontSize(ctx) * 0.5
 
 local text_color = 0xFFFFFFFF
 if visual_metronome.downbeat_flash > 0.1 then
 text_color = 0x000000FF
 elseif visual_metronome.beat_flash > 0.1 then
 text_color = 0x000000FF
 end
 
 r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, beat_text)
 end
 
 if settings.visual_metronome_show_position_ring and visual_metronome.beat_position > 0 then
 local ring_radius = radius + 6
 local arc_start = -math.pi * 0.5
 local arc_end = arc_start + (visual_metronome.beat_position * 2 * math.pi)
 
 r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, ring_radius, arc_start, arc_end, 32)
 r.ImGui_DrawList_PathStroke(draw_list, settings.visual_metronome_color_ring or 0xFFFFFFFF, 0, settings.visual_metronome_ring_thickness or 3)
 end


end

LoadLastUsedPreset()

function SetColorAlpha(color, alpha)
 local r = (color >> 24) & 0xFF
 local g = (color >> 16) & 0xFF
 local b = (color >> 8) & 0xFF
 return (r << 24) | (g << 16) | (b << 8) | (alpha & 0xFF)
end

function GetButtonColorWithTransparency(color)
 if settings.use_transparent_buttons and color then
  local alpha = settings.transparent_button_opacity or 0
  return SetColorAlpha(color, alpha)
 end
 return color
end

function DrawGradientBackground()
 if not settings.use_gradient_background then return end
 
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 local win_x, win_y = r.ImGui_GetWindowPos(ctx)
 local win_w, win_h = r.ImGui_GetWindowSize(ctx)
 
 local color_top = settings.gradient_color_top or 0x1A1A1AFF
 local color_middle = settings.gradient_color_middle or 0x0D0D0DFF
 local color_bottom = settings.gradient_color_bottom or 0x000000FF
 
 local mid_y = win_y + (win_h * 0.5)
 
 r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, 
  win_x, win_y, 
  win_x + win_w, mid_y, 
  color_top, color_top, 
  color_middle, color_middle)
 
 r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, 
  win_x, mid_y, 
  win_x + win_w, win_y + win_h, 
  color_middle, color_middle, 
  color_bottom, color_bottom)
end


function SetStyle()
 -- Style setup
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.window_rounding)
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

function SetTransportStyle()
 -- Transport-specific style setup
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), settings.transport_window_rounding or settings.window_rounding)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.frame_rounding) 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), settings.transport_popup_rounding or settings.popup_rounding)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), settings.grab_rounding)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), settings.grab_min_size) 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0) 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), settings.button_border_size)
 
 -- Transport-specific colors (minimal set)
 local bg_color = settings.use_gradient_background and 0x00000000 or (settings.transport_background or settings.background)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), bg_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), settings.border) 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), settings.transport_popup_bg or settings.background)
 
 -- Use default colors for everything else (so settings window can override them)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), settings.frame_bg)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), settings.frame_bg_hovered)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), settings.frame_bg_active)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), settings.slider_grab)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), settings.slider_grab_active)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), settings.check_mark)
 
 local button_normal_color = settings.button_normal
 local button_hovered_color = settings.button_hovered
 local button_active_color = settings.button_active
 
 if settings.use_transparent_buttons then
  local alpha = settings.transparent_button_opacity or 0
  button_normal_color = SetColorAlpha(settings.button_normal, alpha)
  button_hovered_color = SetColorAlpha(settings.button_hovered, alpha)
  button_active_color = SetColorAlpha(settings.button_active, alpha)
 end
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_normal_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), button_hovered_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), button_active_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.text_normal)
end

function PushTransportPopupStyling(ctx, settings)
 if not ctx then ctx = _G.ctx end
 if not settings then settings = _G.settings end
 if not ctx then return 0, false, nil end 
 if not settings then return 0, false, nil end 
 if not font_cache then font_cache = {} end
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), settings.transport_popup_bg or settings.background)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.transport_popup_text or settings.text_normal)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), settings.transport_border or settings.border)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), settings.transport_popup_bg or settings.background)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), settings.transport_border or settings.border)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), settings.transport_border or settings.border)
 local popup_font = nil
 if settings.transport_popup_font_name and settings.transport_popup_font_size then
 local cache_key = settings.transport_popup_font_name .. "_" .. settings.transport_popup_font_size
 popup_font = font_cache[cache_key]
 if not popup_font then
 popup_font = r.ImGui_CreateFont(settings.transport_popup_font_name, settings.transport_popup_font_size)
 if popup_font then
 r.ImGui_Attach(ctx, popup_font)
 font_cache[cache_key] = popup_font
 end
 end
 if popup_font then
 r.ImGui_PushFont(ctx, popup_font, settings.transport_popup_font_size)
 return 6, true, popup_font 
 end
 end
 r.ImGui_PushFont(ctx, nil, settings.font_size or 14)
 return 6, true, nil
end

function PopTransportPopupStyling(...)
 local arg1, arg2, arg3, arg4 = ...
 if type(arg1) == "number" then
  local color_count = arg1
  if font_popup then r.ImGui_PopFont(ctx) end
  r.ImGui_PopStyleColor(ctx, color_count or 6)
 else
  local ctx, color_count, font_pushed, popup_font = arg1, arg2, arg3, arg4
  if font_pushed then r.ImGui_PopFont(ctx) end
  r.ImGui_PopStyleColor(ctx, color_count or 6)
 end
end

function SetTransportPopupStyle()
 return PushTransportPopupStyling(ctx, settings)
end

function PopTransportPopupStyle()
 PopTransportPopupStyling(6)
end

function ShowBorderControls(prefix)
 r.ImGui_Separator(ctx)
 
 local rv
 local show_border_key = prefix .. "_show_border"
 local border_color_key = prefix .. "_border_color"
 local border_size_key = prefix .. "_border_size"
 
 if settings[show_border_key] == nil then settings[show_border_key] = false end
 rv, settings[show_border_key] = r.ImGui_Checkbox(ctx, "Show Border##" .. prefix, settings[show_border_key])
 
 if settings[show_border_key] then
 r.ImGui_SameLine(ctx)
 r.ImGui_Text(ctx, "Color:")
 r.ImGui_SameLine(ctx)
 local color_flags = r.ImGui_ColorEditFlags_NoInputs()
 local current_color = settings[border_color_key] or 0xFFFFFFFF
 rv, settings[border_color_key] = r.ImGui_ColorEdit4(ctx, "##BorderColor" .. prefix, current_color, color_flags)
 
 r.ImGui_SameLine(ctx)
 r.ImGui_Text(ctx, "Size:")
 r.ImGui_SameLine(ctx)
 r.ImGui_SetNextItemWidth(ctx, 100)
 local current_size = settings[border_size_key] or 1.0
 rv, settings[border_size_key] = r.ImGui_SliderDouble(ctx, "##BorderSize" .. prefix, current_size, 0.5, 5.0)
 end
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
 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 4)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 4)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 10)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1E1E1EFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x2D2D2DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x3D3D3DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x4D4D4DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x0078D7FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x1E90FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0x0078D7FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2D2D2DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3D3D3DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x4D4D4DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x3C3C3CFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x1E1E1EFF)
 
 local settings_window_height = 650 
 r.ImGui_SetNextWindowSize(ctx, settings.settings_window_width or 780, settings_window_height)
 local settings_visible, settings_open = r.ImGui_Begin(ctx, 'Transport Settings', true, settings_flags)
 if settings_visible then
 r.ImGui_PushFont(ctx, settings_ui_font, SETTINGS_UI_FONT_SIZE)
 
 local window_width = r.ImGui_GetWindowWidth(ctx)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
 r.ImGui_Text(ctx, "TK")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_SameLine(ctx)
 r.ImGui_Text(ctx, "TRANSPORT")
 
 r.ImGui_SameLine(ctx)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF)
 r.ImGui_Text(ctx, "v" .. script_version)
 r.ImGui_PopStyleColor(ctx)
 
 local instance_name = _G.TK_TRANSPORT_INSTANCE_NAME
 if instance_name and instance_name ~= "" then
 r.ImGui_SameLine(ctx)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF)
 r.ImGui_Text(ctx, "(" .. instance_name .. ")")
 r.ImGui_PopStyleColor(ctx)
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

 do
 local labels = {
 "Global",
 "Transport",
 "Scaling",
 "Buttons",
 "Widgets",
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

 local transport_tab_active = false
 local buttons_tab_active = false
 local widgets_tab_active = false
 
 local SETTINGS_TAB_HEIGHT = -30 

 if r.ImGui_BeginTabBar(ctx, "SettingsTabs") then
 pushed_tab = PushTabColors(0x32CD32FF)
 local layout_open = r.ImGui_BeginTabItem(ctx, "Transport")
 if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(0x32CD32FF, layout_open) end
 if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
 if layout_open then
 transport_tab_active = true
 local window_width = r.ImGui_GetWindowWidth(ctx)
 local split_pos = math.floor(window_width * 0.2) 
 
 if r.ImGui_BeginTable(ctx, "LayoutSplit", 2, r.ImGui_TableFlags_BordersInnerV()) then
 r.ImGui_TableSetupColumn(ctx, "Components", r.ImGui_TableColumnFlags_WidthFixed(), split_pos)
 r.ImGui_TableSetupColumn(ctx, "Settings", r.ImGui_TableColumnFlags_WidthStretch())
 
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Components:")
 r.ImGui_Separator(ctx)
 
 if r.ImGui_Selectable(ctx, "Base Style", selected_transport_component == "base_style") then
 selected_transport_component = "base_style"
 end
 
 if r.ImGui_Selectable(ctx, "Scaling", selected_transport_component == "scaling") then
 selected_transport_component = "scaling"
 end
 
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginChild(ctx, "ComponentList", 0, SETTINGS_TAB_HEIGHT) then
 ShowComponentList(ctx)
 r.ImGui_EndChild(ctx)
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 
 if r.ImGui_BeginChild(ctx, "ComponentSettings", 0, SETTINGS_TAB_HEIGHT) then
 if selected_transport_component == "base_style" then
 local rv
 
 r.ImGui_Text(ctx, "Settings for: Base Style")
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginTable(ctx, "TransportBaseStyle", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Window Rounding")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.transport_window_rounding = r.ImGui_SliderDouble(ctx, "##WindowRounding", settings.transport_window_rounding or settings.window_rounding or 0.0, 0.0, 20.0)
 if rv then MarkTransportPresetChanged() end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Popup Rounding")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.transport_popup_rounding = r.ImGui_SliderDouble(ctx, "##PopupRounding", settings.transport_popup_rounding or settings.popup_rounding or 0.0, 0.0, 20.0)
 if rv then MarkTransportPresetChanged() end
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Window Border Size")
 r.ImGui_SetNextItemWidth(ctx, -1)
 rv, settings.transport_border_size = r.ImGui_SliderDouble(ctx, "##BorderSize", settings.transport_border_size or settings.border_size or 0.0, 0.0, 5.0)
 if rv then MarkTransportPresetChanged() end
 r.ImGui_TableSetColumnIndex(ctx, 1)
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Popup Font")
 local current_popup_font = settings.transport_popup_font_name or settings.current_font
 local current_popup_font_index = 0
 for i, font_name in ipairs(fonts) do
 if font_name == current_popup_font then
 current_popup_font_index = i - 1
 break
 end
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1) 
 rv, current_popup_font_index = r.ImGui_Combo(ctx, "##PopupFont", current_popup_font_index, table.concat(fonts, '\0') .. '\0')
 if rv then
 settings.transport_popup_font_name = fonts[current_popup_font_index + 1]
 RebuildSectionFonts()
 MarkTransportPresetChanged()
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_Text(ctx, "Popup Font Size")
 local current_popup_size_index = 0
 for i, size in ipairs(text_sizes) do
 if size == (settings.transport_popup_font_size or settings.font_size) then
 current_popup_size_index = i - 1
 break
 end
 end
 
 local size_strings = {}
 for _, size in ipairs(text_sizes) do
 table.insert(size_strings, tostring(size))
 end
 
 r.ImGui_SetNextItemWidth(ctx, -1) 
 rv, current_popup_size_index = r.ImGui_Combo(ctx, "##PopupFontSize", current_popup_size_index, table.concat(size_strings, '\0') .. '\0')
 if rv then
 settings.transport_popup_font_size = text_sizes[current_popup_size_index + 1]
 RebuildSectionFonts()
 MarkTransportPresetChanged()
 end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Spacing(ctx)
 
 local flags = r.ImGui_ColorEditFlags_NoInputs()
 local columns = 2

 local transport_window_colors = {
 { 'transport_background', 'Window Background', 'background' },
 { 'transport_border', 'Window Border Color', 'border' },
 { 'transport_popup_bg', 'Popup Background', 'background' },
 { 'transport_popup_text', 'Popup Text', 'text_normal' },
 }

 if r.ImGui_BeginTable(ctx, '##transport_window_colors', columns, r.ImGui_TableFlags_SizingStretchSame()) then
 local col = 0
 for idx, item in ipairs(transport_window_colors) do
 if col == 0 then r.ImGui_TableNextRow(ctx) end
 r.ImGui_TableSetColumnIndex(ctx, col)
 local key = item[1]
 local label = item[2]
 local fallback_key = item[3]
 local current = settings[key] or settings[fallback_key]
 local rv_col, new_col = r.ImGui_ColorEdit4(ctx, label, current, flags)
 if rv_col then 
 settings[key] = new_col
 MarkTransportPresetChanged()
 end
 col = (col + 1) % columns
 end
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Spacing(ctx)
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x4A90E2FF)
 r.ImGui_Text(ctx, "GRADIENT BACKGROUND")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_Separator(ctx)
 
 local rv_gradient = r.ImGui_Checkbox(ctx, "Use Gradient Background", settings.use_gradient_background or false)
 if rv_gradient then
  settings.use_gradient_background = not settings.use_gradient_background
  MarkTransportPresetChanged()
 end
 
 if settings.use_gradient_background then
  r.ImGui_Spacing(ctx)
  
  if r.ImGui_BeginTable(ctx, '##gradient_colors', 2, r.ImGui_TableFlags_SizingStretchSame()) then
   r.ImGui_TableNextRow(ctx)
   r.ImGui_TableSetColumnIndex(ctx, 0)
   local rv_top, new_top = r.ImGui_ColorEdit4(ctx, "Gradient Top Color", settings.gradient_color_top or 0x1A1A1AFF, flags)
   if rv_top then 
    settings.gradient_color_top = new_top
    MarkTransportPresetChanged()
   end
   
   r.ImGui_TableSetColumnIndex(ctx, 1)
   local rv_middle, new_middle = r.ImGui_ColorEdit4(ctx, "Gradient Middle Color", settings.gradient_color_middle or 0x0D0D0DFF, flags)
   if rv_middle then 
    settings.gradient_color_middle = new_middle
    MarkTransportPresetChanged()
   end
   
   r.ImGui_TableNextRow(ctx)
   r.ImGui_TableSetColumnIndex(ctx, 0)
   local rv_bottom, new_bottom = r.ImGui_ColorEdit4(ctx, "Gradient Bottom Color", settings.gradient_color_bottom or 0x000000FF, flags)
   if rv_bottom then 
    settings.gradient_color_bottom = new_bottom
    MarkTransportPresetChanged()
   end
   
   r.ImGui_EndTable(ctx)
  end
 end
 
 r.ImGui_Spacing(ctx)
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x4A90E2FF)
 r.ImGui_Text(ctx, "TRANSPARENT BUTTONS")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_Separator(ctx)
 
 local rv_transparent = r.ImGui_Checkbox(ctx, "Use Transparent Buttons", settings.use_transparent_buttons or false)
 if rv_transparent then
  settings.use_transparent_buttons = not settings.use_transparent_buttons
  MarkTransportPresetChanged()
 end
 
 if settings.use_transparent_buttons then
  r.ImGui_Spacing(ctx)
  r.ImGui_Text(ctx, "Button Opacity (0 = fully transparent):")
  r.ImGui_SetNextItemWidth(ctx, -1)
  local rv_opacity, new_opacity = r.ImGui_SliderInt(ctx, "##ButtonOpacity", settings.transparent_button_opacity or 0, 0, 255, "%d")
  if rv_opacity then
   settings.transparent_button_opacity = new_opacity
   MarkTransportPresetChanged()
  end
  
  r.ImGui_Spacing(ctx)
  r.ImGui_PushFont(ctx, settings_ui_font_small, SETTINGS_UI_FONT_SMALL_SIZE)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xA0A0A0FF)
  r.ImGui_TextWrapped(ctx, "Applies to: Tempo, Time Signature, Tap Tempo, ENV, and Custom Buttons. Main transport buttons (Play, Stop, etc.) keep their normal colors.")
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_PopFont(ctx)
 end
 
 r.ImGui_Spacing(ctx)
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x4A90E2FF) 
 r.ImGui_Text(ctx, "CUSTOM BUTTON GLOBAL OFFSET")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_Separator(ctx)
 
 r.ImGui_PushFont(ctx, settings_ui_font_small, SETTINGS_UI_FONT_SMALL_SIZE)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xA0A0A0FF)
 r.ImGui_TextWrapped(ctx, "Global Offset is saved in the Transport preset. Re-save your Transport preset to keep these changes.")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_PopFont(ctx)
 
 local old_x = settings.custom_buttons_x_offset_px
 local old_y = settings.custom_buttons_y_offset_px
 DrawPixelXYControls('custom_buttons_x_offset','custom_buttons_y_offset', main_window_width, main_window_height)
 if settings.custom_buttons_x_offset_px ~= old_x or settings.custom_buttons_y_offset_px ~= old_y then
 MarkTransportPresetChanged()
 end
 r.ImGui_SameLine(ctx)
 if r.ImGui_Button(ctx, "Reset Offset") then
 settings.custom_buttons_x_offset = 0.0
 settings.custom_buttons_y_offset = 0.0
 settings.custom_buttons_x_offset_px = 0
 settings.custom_buttons_y_offset_px = 0
 MarkTransportPresetChanged()
 end
 
 elseif selected_transport_component == "scaling" then
 local rv
 
 r.ImGui_Text(ctx, "Settings for: Scaling")
 r.ImGui_Separator(ctx)
 
 local changed_scaling = false
 local rvb
 
 if r.ImGui_BeginTable(ctx, "ScalingOptions", 2, r.ImGui_TableFlags_SizingStretchSame()) then
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rvb, settings.lock_window_size = r.ImGui_Checkbox(ctx, "Lock Window Size", settings.lock_window_size or false)
 if rvb then
 MarkTransportPresetChanged()
 end
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rvb, settings.custom_buttons_scale_with_width = r.ImGui_Checkbox(ctx, "Scale positions with window width", settings.custom_buttons_scale_with_width or false)
 changed_scaling = changed_scaling or rvb
 r.ImGui_TableSetColumnIndex(ctx, 1)
 rvb, settings.custom_buttons_scale_with_height = r.ImGui_Checkbox(ctx, "Scale positions with window height", settings.custom_buttons_scale_with_height or false)
 changed_scaling = changed_scaling or rvb
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 rvb, settings.custom_buttons_scale_sizes = r.ImGui_Checkbox(ctx, "Scale custom button size with width", settings.custom_buttons_scale_sizes or false)
 changed_scaling = changed_scaling or rvb
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "Reference Size Settings:")
 
 local ref_w = settings.custom_buttons_ref_width or 0
 local ref_h = settings.custom_buttons_ref_height or 0
 
 if r.ImGui_BeginTable(ctx, "ReferenceSize", 3, r.ImGui_TableFlags_SizingStretchSame()) then
 
 r.ImGui_TableNextRow(ctx)
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_PushItemWidth(ctx, -1)
 local rvi
 rvi, ref_w = r.ImGui_InputInt(ctx, "##ref_width", ref_w)
 if rvi then settings.custom_buttons_ref_width = math.max(1, ref_w); changed_scaling = true end
 r.ImGui_PopItemWidth(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 r.ImGui_PushItemWidth(ctx, -1)
 rvi, ref_h = r.ImGui_InputInt(ctx, "##ref_height", ref_h)
 if rvi then settings.custom_buttons_ref_height = math.max(1, ref_h); changed_scaling = true end
 r.ImGui_PopItemWidth(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 2)
 if r.ImGui_Button(ctx, "Auto Set (Current)") then
 local current_width, current_height = r.ImGui_GetWindowSize(ctx)
 local main_window_width, main_window_height = r.ImGui_GetWindowSize(ctx)
 settings.custom_buttons_ref_width = main_window_width
 settings.custom_buttons_ref_height = main_window_height
 ref_w = main_window_width
 ref_h = main_window_height
 changed_scaling = true
 end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, string.format("Reference Size: %d x %d", ref_w, ref_h))
 
 r.ImGui_Spacing(ctx)
 r.ImGui_PushFont(ctx, settings_ui_font_small, SETTINGS_UI_FONT_SMALL_SIZE)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xA0A0A0FF)
 r.ImGui_TextWrapped(ctx, "Tip: First set the layout at your desired 'design' window size. With the toggles enabled, that size will be saved automatically as the reference (one-time).")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_PopFont(ctx)
 
 if changed_scaling then 
 SaveSettings()
 else
 if rvb then MarkTransportPresetChanged() end
 end
 else
 ShowComponentSettings(ctx, main_window_width, main_window_height)
 end
 r.ImGui_EndChild(ctx)
 end
 
 r.ImGui_EndTable(ctx)
 end
 
 r.ImGui_EndTabItem(ctx)
 end

 pushed_tab = PushTabColors(0xFF7F50FF) 
 local custom_open = r.ImGui_BeginTabItem(ctx, "Buttons")
 if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(0xFF7F50FF, custom_open) end
 if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
 if custom_open then
 buttons_tab_active = true
 local window_width = r.ImGui_GetWindowWidth(ctx)
 local split_pos = math.floor(window_width * 0.2) 
 
 if r.ImGui_BeginTable(ctx, "ButtonsSplit", 2, r.ImGui_TableFlags_BordersInnerV()) then
 r.ImGui_TableSetupColumn(ctx, "Categories", r.ImGui_TableColumnFlags_WidthFixed(), split_pos)
 r.ImGui_TableSetupColumn(ctx, "Settings", r.ImGui_TableColumnFlags_WidthStretch())
 
 r.ImGui_TableNextRow(ctx)
 
 r.ImGui_TableSetColumnIndex(ctx, 0)
 r.ImGui_Text(ctx, "Buttons")
 r.ImGui_SameLine(ctx)
 if r.ImGui_SmallButton(ctx, "🔘") then
 if CustomButtons and CustomButtons.CreateNewButton then
 local new_button = CustomButtons.CreateNewButton()
 table.insert(CustomButtons.buttons, new_button)
 selected_button_component = "button_" .. #CustomButtons.buttons
 CustomButtons.SaveCurrentButtons()
 end
 end
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Create new button")
 end
 
 r.ImGui_SameLine(ctx)
 if r.ImGui_SmallButton(ctx, "📁") then
 if CustomButtons and CustomButtons.CreateNewButton then
 local new_button = CustomButtons.CreateNewButton()
 new_button.name = "New Group Button"
 new_button.group = "New Group"
 table.insert(CustomButtons.buttons, new_button)
 selected_button_component = "button_" .. #CustomButtons.buttons
 CustomButtons.SaveCurrentButtons()
 editing_group_name = "New Group"
 group_name_input = "New Group"
 end
 end
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Create new group with button")
 end
 
 r.ImGui_Separator(ctx)
 
 local import_button_height = r.ImGui_GetFrameHeightWithSpacing(ctx) + 8
 local scroll_height = SETTINGS_TAB_HEIGHT - import_button_height
 
 if r.ImGui_BeginChild(ctx, "ButtonGroups", 0, scroll_height) then
 if CustomButtons and CustomButtons.buttons then
 local grouped_buttons = {}
 local ungrouped_buttons = {}
 
 for i, button in ipairs(CustomButtons.buttons) do
 if button.group and button.group ~= "" then
 if not grouped_buttons[button.group] then
 grouped_buttons[button.group] = {}
 end
 table.insert(grouped_buttons[button.group], {button = button, index = i})
 else
 table.insert(ungrouped_buttons, {button = button, index = i})
 end
 end
 
 for group_name, buttons in pairs(grouped_buttons) do
 table.sort(buttons, function(a, b)
 local pos_a = a.button.position_px or (a.button.position or 0) * 1000
 local pos_b = b.button.position_px or (b.button.position or 0) * 1000
 return pos_a < pos_b
 end)
 end
 
 table.sort(ungrouped_buttons, function(a, b)
 local pos_a = a.button.position_px or (a.button.position or 0) * 1000
 local pos_b = b.button.position_px or (b.button.position or 0) * 1000
 return pos_a < pos_b
 end)
 
 local sorted_group_names = {}
 for group_name, buttons in pairs(grouped_buttons) do
 local first_button_pos = buttons[1].button.position_px or (buttons[1].button.position or 0) * 1000
 table.insert(sorted_group_names, {name = group_name, pos = first_button_pos})
 end
 table.sort(sorted_group_names, function(a, b)
 return a.pos < b.pos
 end)
 
 for _, group_info in ipairs(sorted_group_names) do
 local group_name = group_info.name
 local buttons = grouped_buttons[group_name]
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x4A90E2FF) 
 
 if editing_group_name == group_name then
 r.ImGui_SetNextItemWidth(ctx, -1)
 local rv, new_name = r.ImGui_InputText(ctx, "##edit_group_" .. group_name, group_name_input, r.ImGui_InputTextFlags_EnterReturnsTrue())
 
 group_name_input = new_name
 
 if rv then
 if new_name ~= "" and new_name ~= group_name then
 for _, button_info in ipairs(buttons) do
 CustomButtons.buttons[button_info.index].group = new_name
 end
 CustomButtons.SaveCurrentButtons()
 end
 editing_group_name = nil
 group_name_input = ""
 end
 
 if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
 editing_group_name = nil
 group_name_input = ""
 end
 else
 if r.ImGui_Selectable(ctx, group_name .. " ✏️##group_" .. group_name, false, r.ImGui_SelectableFlags_AllowDoubleClick()) then
 if r.ImGui_IsMouseDoubleClicked(ctx, r.ImGui_MouseButton_Left()) then
 editing_group_name = group_name
 group_name_input = group_name
 end
 end
 
 if r.ImGui_BeginDragDropTarget(ctx) then
 local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_BUTTON_REORDER")
 if ok then
 local from_idx = tonumber(payload)
 if from_idx and CustomButtons.buttons[from_idx] then
 CustomButtons.buttons[from_idx].group = group_name
 CustomButtons.SaveCurrentButtons()
 ButtonEditor.MarkUnsavedChanges() 
 selected_button_component = "button_" .. from_idx
 end
 end
 r.ImGui_EndDragDropTarget(ctx)
 end
 
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Double-click to rename group\nDrag buttons here to move them to this group")
 end
 end
 
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_Separator(ctx)
 
 for _, button_info in ipairs(buttons) do
 local button = button_info.button
 local i = button_info.index
 local button_name = "  " .. (button.name or ("Button " .. i)) 
 local is_selected = (selected_button_component == "button_" .. i)
 
 if r.ImGui_Selectable(ctx, button_name .. "##btn_" .. i, is_selected) then
 selected_button_component = "button_" .. i
 end
 
 if r.ImGui_BeginDragDropSource(ctx) then
 r.ImGui_SetDragDropPayload(ctx, "TK_BUTTON_REORDER", tostring(i))
 r.ImGui_Text(ctx, "Move: " .. (button.name or ("Button " .. i)))
 r.ImGui_EndDragDropSource(ctx)
 end
 
 if r.ImGui_BeginDragDropTarget(ctx) then
 local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_BUTTON_REORDER")
 if ok then
 local from_idx = tonumber(payload)
 if from_idx and from_idx ~= i and CustomButtons.buttons[from_idx] then
 local moving_button = CustomButtons.buttons[from_idx]
 local target_button = CustomButtons.buttons[i]
 
 local temp_pos_px = moving_button.position_px
 local temp_pos = moving_button.position
 local temp_pos_y_px = moving_button.position_y_px
 local temp_pos_y = moving_button.position_y
 
 if target_button.position_px ~= nil and moving_button.position_px ~= nil then
 moving_button.position_px = target_button.position_px
 target_button.position_px = temp_pos_px
 moving_button.position = moving_button.position_px / math.max(1, main_window_width)
 target_button.position = target_button.position_px / math.max(1, main_window_width)
 elseif target_button.position ~= nil and moving_button.position ~= nil then
 moving_button.position = target_button.position
 target_button.position = temp_pos
 moving_button.position_px = math.floor(moving_button.position * main_window_width)
 target_button.position_px = math.floor(target_button.position * main_window_width)
 end
 
 if target_button.position_y_px ~= nil and moving_button.position_y_px ~= nil then
 moving_button.position_y_px = target_button.position_y_px
 target_button.position_y_px = temp_pos_y_px
 moving_button.position_y = moving_button.position_y_px / math.max(1, main_window_height)
 target_button.position_y = target_button.position_y_px / math.max(1, main_window_height)
 elseif target_button.position_y ~= nil and moving_button.position_y ~= nil then
 moving_button.position_y = target_button.position_y
 target_button.position_y = temp_pos_y
 moving_button.position_y_px = math.floor(moving_button.position_y * main_window_height)
 target_button.position_y_px = math.floor(target_button.position_y * main_window_height)
 end
 
 if moving_button.group ~= button.group then
 moving_button.group = button.group
 end
 
 CustomButtons.SaveCurrentButtons()
 ButtonEditor.MarkUnsavedChanges() 
 selected_button_component = "button_" .. from_idx
 end
 end
 r.ImGui_EndDragDropTarget(ctx)
 end
 end
 
 r.ImGui_Spacing(ctx)
 end
 
 if #ungrouped_buttons > 0 then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x888888FF) 
 if r.ImGui_Selectable(ctx, "Ungrouped##ungrouped_header", false, r.ImGui_SelectableFlags_Disabled()) then
 end
 
 if r.ImGui_BeginDragDropTarget(ctx) then
 local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_BUTTON_REORDER")
 if ok then
 local from_idx = tonumber(payload)
 if from_idx and CustomButtons.buttons[from_idx] then
 CustomButtons.buttons[from_idx].group = ""
 CustomButtons.SaveCurrentButtons()
 ButtonEditor.MarkUnsavedChanges() 
 selected_button_component = "button_" .. from_idx
 end
 end
 r.ImGui_EndDragDropTarget(ctx)
 end
 
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Drag buttons here to remove them from their group")
 end
 
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_Separator(ctx)
 
 for _, button_info in ipairs(ungrouped_buttons) do
 local button = button_info.button
 local i = button_info.index
 local button_name = "  " .. (button.name or ("Button " .. i)) 
 local is_selected = (selected_button_component == "button_" .. i)
 
 if r.ImGui_Selectable(ctx, button_name .. "##btn_" .. i, is_selected) then
 selected_button_component = "button_" .. i
 end
 
 if r.ImGui_BeginDragDropSource(ctx) then
 r.ImGui_SetDragDropPayload(ctx, "TK_BUTTON_REORDER", tostring(i))
 r.ImGui_Text(ctx, "Move: " .. (button.name or ("Button " .. i)))
 r.ImGui_EndDragDropSource(ctx)
 end
 
 if r.ImGui_BeginDragDropTarget(ctx) then
 local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_BUTTON_REORDER")
 if ok then
 local from_idx = tonumber(payload)
 if from_idx and from_idx ~= i and CustomButtons.buttons[from_idx] then
 local moving_button = CustomButtons.buttons[from_idx]
 local target_button = CustomButtons.buttons[i]
 
 local temp_pos_px = moving_button.position_px
 local temp_pos = moving_button.position
 local temp_pos_y_px = moving_button.position_y_px
 local temp_pos_y = moving_button.position_y
 
 if target_button.position_px ~= nil and moving_button.position_px ~= nil then
 moving_button.position_px = target_button.position_px
 target_button.position_px = temp_pos_px
 moving_button.position = moving_button.position_px / math.max(1, main_window_width)
 target_button.position = target_button.position_px / math.max(1, main_window_width)
 elseif target_button.position ~= nil and moving_button.position ~= nil then
 moving_button.position = target_button.position
 target_button.position = temp_pos
 moving_button.position_px = math.floor(moving_button.position * main_window_width)
 target_button.position_px = math.floor(target_button.position * main_window_width)
 end
 
 if target_button.position_y_px ~= nil and moving_button.position_y_px ~= nil then
 moving_button.position_y_px = target_button.position_y_px
 target_button.position_y_px = temp_pos_y_px
 moving_button.position_y = moving_button.position_y_px / math.max(1, main_window_height)
 target_button.position_y = target_button.position_y_px / math.max(1, main_window_height)
 elseif target_button.position_y ~= nil and moving_button.position_y ~= nil then
 moving_button.position_y = target_button.position_y
 target_button.position_y = temp_pos_y
 moving_button.position_y_px = math.floor(moving_button.position_y * main_window_height)
 target_button.position_y_px = math.floor(target_button.position_y * main_window_height)
 end
 
 moving_button.group = ""
 
 CustomButtons.SaveCurrentButtons()
 ButtonEditor.MarkUnsavedChanges() 
 selected_button_component = "button_" .. from_idx
 end
 end
 r.ImGui_EndDragDropTarget(ctx)
 end
 end
 
 r.ImGui_Spacing(ctx)
 end
 end
 
 r.ImGui_Separator(ctx)
 if r.ImGui_Button(ctx, "🔘 New Button", -1, 0) then
 if CustomButtons and CustomButtons.CreateNewButton then
 local new_button = CustomButtons.CreateNewButton()
 table.insert(CustomButtons.buttons, new_button)
 selected_button_component = "button_" .. #CustomButtons.buttons
 CustomButtons.SaveCurrentButtons()
 end
 end
 
 if r.ImGui_Button(ctx, "📁 New Group", -1, 0) then
 if CustomButtons and CustomButtons.CreateNewButton then
 local new_button = CustomButtons.CreateNewButton()
 new_button.name = "New Group Button"
 new_button.group = "New Group"
 table.insert(CustomButtons.buttons, new_button)
 selected_button_component = "button_" .. #CustomButtons.buttons
 CustomButtons.SaveCurrentButtons()
 editing_group_name = "New Group"
 group_name_input = "New Group"
 end
 end
 
 r.ImGui_EndChild(ctx)
 end
 
 r.ImGui_Separator(ctx)
 if r.ImGui_Button(ctx, "Import", -1, 0) then
 show_button_import_inline = not show_button_import_inline
 end
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Import buttons from other presets")
 end
 
 r.ImGui_TableSetColumnIndex(ctx, 1)
 
 if show_button_import_inline then
 r.ImGui_Text(ctx, "Import Buttons from Other Presets")
 elseif selected_button_component:match("^button_") then
 local button_index = tonumber(selected_button_component:sub(8))
 if CustomButtons and CustomButtons.buttons and CustomButtons.buttons[button_index] then
 local button = CustomButtons.buttons[button_index]
 r.ImGui_Text(ctx, "Settings for: " .. (button.name or ("Button " .. button_index)))
 
 r.ImGui_SameLine(ctx)
 local props_pushed = false
 if not ButtonEditor.cb_section_states.actions_open and not ButtonEditor.cb_section_states.toggle_open then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4080FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x5090FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x3070FFFF)
 props_pushed = true
 end
 if r.ImGui_Button(ctx, "⚙ Properties") then
 ButtonEditor.cb_section_states.actions_open = false
 ButtonEditor.cb_section_states.toggle_open = false
 end
 if props_pushed then
 r.ImGui_PopStyleColor(ctx, 3)
 end
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Show Properties view")
 end
 
 r.ImGui_SameLine(ctx)
 local actions_pushed = false
 if ButtonEditor.cb_section_states.actions_open then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4080FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x5090FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x3070FFFF)
 actions_pushed = true
 end
 if r.ImGui_Button(ctx, "⚡ Actions") then
 ButtonEditor.cb_section_states.actions_open = true
 ButtonEditor.cb_section_states.toggle_open = false
 end
 if actions_pushed then
 r.ImGui_PopStyleColor(ctx, 3)
 end
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Show Actions view")
 end
 
 r.ImGui_SameLine(ctx)
 local toggle_pushed = false
 if ButtonEditor.cb_section_states.toggle_open then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4080FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x5090FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x3070FFFF)
 toggle_pushed = true
 end
 if r.ImGui_Button(ctx, "🔄 Toggle") then
 ButtonEditor.cb_section_states.actions_open = false
 ButtonEditor.cb_section_states.toggle_open = true
 end
 if toggle_pushed then
 r.ImGui_PopStyleColor(ctx, 3)
 end
 if r.ImGui_IsItemHovered(ctx) then
 r.ImGui_SetTooltip(ctx, "Show Toggle settings")
 end
 else
 r.ImGui_Text(ctx, "Settings for: Unknown Button")
 end
 else
 r.ImGui_Text(ctx, "Settings")
 end
 r.ImGui_Separator(ctx)
 
 if r.ImGui_BeginChild(ctx, "ButtonSettings", 0, SETTINGS_TAB_HEIGHT) then
 if show_button_import_inline then
 ButtonEditor.ShowImportInline(ctx, CustomButtons)
 elseif selected_button_component:match("^button_") then
 local button_index = tonumber(selected_button_component:sub(8)) 
 if CustomButtons and CustomButtons.buttons and CustomButtons.buttons[button_index] then
 local button = CustomButtons.buttons[button_index]
 
 CustomButtons.current_edit = button_index
 
 ButtonEditor.ShowEditorInline(ctx, CustomButtons, settings, { 
 skip_presets = true,
 canvas_width = main_window_width, 
 canvas_height = main_window_height
 })
 else
 r.ImGui_Text(ctx, "Button not found")
 end
 
 else
 r.ImGui_Text(ctx, "Select a category or button from the left panel")
 r.ImGui_Separator(ctx)
 r.ImGui_TextWrapped(ctx, "? Global Settings: Configure global button offset")
 r.ImGui_TextWrapped(ctx, "? Presets: Manage button presets") 
 r.ImGui_TextWrapped(ctx, "? Individual Buttons: Configure specific button properties")
 end
 r.ImGui_EndChild(ctx)
 end
 
 r.ImGui_EndTable(ctx)
 end
 
 
 r.ImGui_EndTabItem(ctx)
 end

 pushed_tab = PushTabColors(0x40E0D0FF) 
 local widgets_open = r.ImGui_BeginTabItem(ctx, "Widgets")
 if pushed_tab and pushed_tab < 0 then DrawTabUnderlineAccent(0x40E0D0FF, widgets_open) end
 if pushed_tab and pushed_tab ~= 0 then PopTabColors(pushed_tab) end
 if widgets_open then
 widgets_tab_active = true
 WidgetManager.RenderWidgetManagerUI(ctx, script_path)
 r.ImGui_EndTabItem(ctx)
 end
 
 r.ImGui_EndTabBar(ctx)
 end
 
 r.ImGui_Separator(ctx)
 
 if transport_tab_active then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x32CD32FF) 
 r.ImGui_Text(ctx, "Presets:")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_SameLine(ctx)
 do
 local reset_btn_width = 100 
 local right_margin = reset_btn_width + 10 
 local avail_w1 = select(1, r.ImGui_GetContentRegionAvail(ctx)) - right_margin
 r.ImGui_SetNextItemWidth(ctx, math.max(140, math.floor(avail_w1 * 0.30))) 
 local presets = GetPresetList()
 local display_name = preset_name and preset_name ~= "" and preset_name or "preset_name"
 if not preset_input_name then preset_input_name = "" end
 if r.ImGui_BeginCombo(ctx, "##PresetCombo", display_name) then
 for _, preset in ipairs(presets) do
 if preset and preset ~= "" then
 local is_selected = (preset == preset_name)
 if r.ImGui_Selectable(ctx, preset, is_selected) then
 preset_name = preset
 LoadPreset(preset)
 SaveLastUsedPreset(preset)
 end
 if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
 end
 end
 r.ImGui_EndCombo(ctx)
 end

 r.ImGui_SameLine(ctx)
 local had_unsaved = transport_preset_has_unsaved_changes
 if had_unsaved then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4040FFFF) 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x4040CCFF) 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x4040AAFF) 
 end
 if r.ImGui_Button(ctx, "Resave") and preset_name then
 SavePreset(preset_name)
 transport_preset_has_unsaved_changes = false
 end
 if had_unsaved then
 r.ImGui_PopStyleColor(ctx, 3)
 end

 r.ImGui_SameLine(ctx)
 if r.ImGui_Button(ctx, "Delete") and preset_name then
 local preset_path = CreatePresetsFolder()
 os.remove(preset_path .. "/" .. preset_name .. ".json")
 preset_name = nil
 end

 r.ImGui_SameLine(ctx)
 local avail_w2 = select(1, r.ImGui_GetContentRegionAvail(ctx)) - right_margin
 local save_tw = select(1, r.ImGui_CalcTextSize(ctx, "Save New"))
 local save_btn_w = save_tw + 18
 local input_w = math.max(80, math.floor(avail_w2 - save_btn_w - 10))
 r.ImGui_SetNextItemWidth(ctx, input_w)
 local rv
 rv, preset_input_name = r.ImGui_InputText(ctx, "##NewPreset", preset_input_name)
 r.ImGui_SameLine(ctx)
 if r.ImGui_Button(ctx, "Save New") and preset_input_name ~= "" then
 preset_name = preset_input_name
 SavePreset(preset_input_name)
 local preset_path = CreatePresetsFolder()
 if r.file_exists(preset_path .. "/" .. preset_input_name .. ".json") then
 preset_input_name = ""
 end
 end

 r.ImGui_SameLine(ctx)
 if r.ImGui_Button(ctx, "Reset Defaults", reset_btn_width, 0) then
 ResetSettings()
 end
 end
 elseif buttons_tab_active then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF7F50FF) 
 r.ImGui_Text(ctx, "Button Presets:")
 r.ImGui_PopStyleColor(ctx)
 r.ImGui_SameLine(ctx)
 ButtonEditor.ShowPresetsInline(ctx, CustomButtons, { small_font = settings_ui_font_small, small_font_size = SETTINGS_UI_FONT_SMALL_SIZE })
 end
 
 r.ImGui_Spacing(ctx)


 r.ImGui_PopFont(ctx)
 r.ImGui_PopStyleColor(ctx, 13) 
 r.ImGui_PopStyleVar(ctx, 8) 
 r.ImGui_End(ctx)
 end
 show_settings = settings_open
end

function ShowInstanceManager()
 if not show_instance_manager then return end
 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 2)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 4)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 4)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 10)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1E1E1EFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x2D2D2DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x3D3D3DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x4D4D4DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x0078D7FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x1E90FFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0x0078D7FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2D2D2DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x3D3D3DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x4D4D4DFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x3C3C3CFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x1E1E1EFF)
 
 r.ImGui_SetNextWindowSize(ctx, 500, 300, r.ImGui_Cond_FirstUseEver())
 local visible, open = r.ImGui_Begin(ctx, 'Instance Manager', true)
 
 if visible then
 r.ImGui_Text(ctx, "Create Named Transport Instances")
 r.ImGui_Separator(ctx)
 
 r.ImGui_Text(ctx, "Instance Name:")
 r.ImGui_SameLine(ctx)
 r.ImGui_SetNextItemWidth(ctx, 150)
 local rv
 rv, instance_name_input = r.ImGui_InputText(ctx, "##instancename", instance_name_input)
 
 r.ImGui_Spacing(ctx)
 rv, instance_start_empty = r.ImGui_Checkbox(ctx, "Start with empty canvas (all components disabled)", instance_start_empty)
 r.ImGui_Spacing(ctx)
 
 if r.ImGui_Button(ctx, "Create") and instance_name_input ~= "" then
 CreateNamedInstance(instance_name_input, instance_start_empty)
 instance_name_input = ""
 end
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Text(ctx, "How it works:")
 r.ImGui_BulletText(ctx, "Creates: TK_TRANSPORT_" .. (instance_name_input ~= "" and instance_name_input or "name") .. ".lua")
 r.ImGui_BulletText(ctx, "Window title: TK_TRANSPORT_" .. (instance_name_input ~= "" and instance_name_input or "name"))
 r.ImGui_BulletText(ctx, "Separate Action List entry")
 r.ImGui_BulletText(ctx, "Shares same presets folder")
 r.ImGui_BulletText(ctx, "Independent last-used preset per instance")
 
 r.ImGui_Spacing(ctx)
 r.ImGui_Separator(ctx)
 r.ImGui_Text(ctx, "Existing Instances:")
 
 local files = ListInstanceFiles()
 for _, file in ipairs(files) do
 r.ImGui_AlignTextToFramePadding(ctx)
 r.ImGui_BulletText(ctx, file)
 r.ImGui_SameLine(ctx)
 
 if r.ImGui_Button(ctx, "Launch##" .. file) then
 LaunchInstance(file)
 end
 r.ImGui_SameLine(ctx)
 
 if r.ImGui_Button(ctx, "Delete##" .. file) then
 DeleteInstance(file)
 end
 end
 
 if #files == 0 then
 r.ImGui_Text(ctx, "(No additional instances created yet)")
 end
 
 r.ImGui_End(ctx)
 end
 
 r.ImGui_PopStyleColor(ctx, 13)
 r.ImGui_PopStyleVar(ctx, 8)
 
 show_instance_manager = open
end

function CreateNamedInstance(name, start_empty)
 local clean_name = name:gsub("[^%w_%-]", "_")
 local new_filename = "TK_TRANSPORT_" .. clean_name .. ".lua"
 local new_filepath = script_path .. new_filename
 local current_script_path = debug.getinfo(1, "S").source:match("@?(.*)")
 
 local escaped_path = current_script_path:gsub("\\", "\\\\"):gsub('"', '\\"')
 
 local wrapper_content = 'local r = reaper\n'
 wrapper_content = wrapper_content .. 'local instance_name = "' .. clean_name .. '"\n'
 wrapper_content = wrapper_content .. '_G.TK_TRANSPORT_INSTANCE_NAME = instance_name\n\n'
 
 if start_empty then
 wrapper_content = wrapper_content .. 'local is_new_instance = not r.HasExtState("TK_TRANSPORT_" .. instance_name, "settings")\n'
 wrapper_content = wrapper_content .. 'if is_new_instance then\n'
 wrapper_content = wrapper_content .. ' r.SetExtState("TK_TRANSPORT_" .. instance_name, "is_new_instance", "1", true)\n'
 wrapper_content = wrapper_content .. 'end\n\n'
 end
 
 wrapper_content = wrapper_content .. 'local original_CreateContext = r.ImGui_CreateContext\n'
 wrapper_content = wrapper_content .. 'r.ImGui_CreateContext = function(title)\n'
 wrapper_content = wrapper_content .. ' return original_CreateContext("Transport Control " .. instance_name)\n'
 wrapper_content = wrapper_content .. 'end\n\n'
 wrapper_content = wrapper_content .. 'local original_GetExtState = r.GetExtState\n'
 wrapper_content = wrapper_content .. 'local original_SetExtState = r.SetExtState\n'
 wrapper_content = wrapper_content .. 'local original_DeleteExtState = r.DeleteExtState\n'
 wrapper_content = wrapper_content .. 'local original_HasExtState = r.HasExtState\n\n'
 wrapper_content = wrapper_content .. 'r.HasExtState = function(section, key, ...)\n'
 wrapper_content = wrapper_content .. ' if section == "TK_TRANSPORT" then\n'
 wrapper_content = wrapper_content .. ' return original_HasExtState("TK_TRANSPORT_" .. instance_name, key, ...)\n'
 wrapper_content = wrapper_content .. ' end\n'
 wrapper_content = wrapper_content .. ' return original_HasExtState(section, key, ...)\n'
 wrapper_content = wrapper_content .. 'end\n\n'
 wrapper_content = wrapper_content .. 'r.GetExtState = function(section, key, ...)\n'
 wrapper_content = wrapper_content .. ' if section == "TK_TRANSPORT" then\n'
 wrapper_content = wrapper_content .. ' return original_GetExtState("TK_TRANSPORT_" .. instance_name, key, ...)\n'
 wrapper_content = wrapper_content .. ' end\n'
 wrapper_content = wrapper_content .. ' return original_GetExtState(section, key, ...)\n'
 wrapper_content = wrapper_content .. 'end\n\n'
 wrapper_content = wrapper_content .. 'r.SetExtState = function(section, key, value, ...)\n'
 wrapper_content = wrapper_content .. ' if section == "TK_TRANSPORT" then\n'
 wrapper_content = wrapper_content .. ' return original_SetExtState("TK_TRANSPORT_" .. instance_name, key, value, ...)\n'
 wrapper_content = wrapper_content .. ' end\n'
 wrapper_content = wrapper_content .. ' return original_SetExtState(section, key, value, ...)\n'
 wrapper_content = wrapper_content .. 'end\n\n'
 wrapper_content = wrapper_content .. 'r.DeleteExtState = function(section, key, ...)\n'
 wrapper_content = wrapper_content .. ' if section == "TK_TRANSPORT" then\n'
 wrapper_content = wrapper_content .. ' return original_DeleteExtState("TK_TRANSPORT_" .. instance_name, key, ...)\n'
 wrapper_content = wrapper_content .. ' end\n'
 wrapper_content = wrapper_content .. ' return original_DeleteExtState(section, key, ...)\n'
 wrapper_content = wrapper_content .. 'end\n\n'
 wrapper_content = wrapper_content .. 'dofile("' .. escaped_path .. '")\n'
 
 local file = io.open(new_filepath, "w")
 if file then
 file:write(wrapper_content)
 file:close()
 r.AddRemoveReaScript(true, 0, new_filepath, true)
 r.ShowMessageBox("Instance created successfully!\n\nFile: " .. new_filename .. "\n\nThis wrapper will always use the latest version of the main script.", "Instance Manager", 0)
 else
 r.ShowMessageBox("Error: Could not create instance file", "Instance Manager", 0)
 end
end

function ListInstanceFiles()
 local files = {}
 local i = 0
 
 repeat
 local file = r.EnumerateFiles(script_path, i)
 if file and file:match("^TK_TRANSPORT_.*%.lua$") and file ~= "TK_TRANSPORT.lua" then
 files[#files + 1] = file:gsub("%.lua$", "")
 end
 i = i + 1
 until not file
 
 return files
end

function LaunchInstance(instance_name)
 local script_file = script_path .. instance_name .. ".lua"
 
 if not r.file_exists(script_file) then
 r.ShowMessageBox("Error: Script file not found:\n" .. script_file, "Instance Manager", 0)
 return
 end
 
 local command_id = r.AddRemoveReaScript(true, 0, script_file, false)
 if command_id and command_id ~= 0 then
 r.Main_OnCommand(command_id, 0)
 else
 r.Main_OnCommand(40015, 0) 
 r.ShowMessageBox("Script registered! Please search for '" .. instance_name .. "' in the Actions window and run it.", "Instance Manager", 0)
 end
end

function DeleteInstance(instance_name)
 local script_file = script_path .. instance_name .. ".lua"
 
 local result = r.ShowMessageBox("Are you sure you want to delete this instance?\n\n" .. instance_name .. "\n\nThis action cannot be undone.", "Delete Instance", 4)
 
 if result == 6 then 
  LaunchInstance(instance_name)
  
  r.AddRemoveReaScript(false, 0, script_file, true)
  os.remove(script_file)
 
  local clean_instance_name = instance_name:gsub("TK_TRANSPORT_", "")
  local current_buttons_file = script_path .. "tk_transport_buttons/current_buttons_" .. clean_instance_name .. ".json"
  os.remove(current_buttons_file)
 
  local section = "TK_TRANSPORT_" .. clean_instance_name
  r.DeleteExtState(section, "settings", true)
  r.DeleteExtState(section, "last_preset", true)
  r.DeleteExtState(section, "last_button_preset", true)
  r.DeleteExtState(section, "is_new_instance", true)
 
  r.ShowMessageBox("Instance deleted successfully!", "Instance Manager", 0)
 end
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
 local override_col = settings.env_override_active_color or mode_loop_active
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), GetButtonColorWithTransparency(override_col))
 break
 end
 end

 if current_mode == "No override" then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), GetButtonColorWithTransparency(settings.env_button_color or settings.button_normal))
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), GetButtonColorWithTransparency(settings.env_button_color_hover or settings.button_hovered))
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), GetButtonColorWithTransparency(settings.env_button_color_active or settings.button_active))
 else
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), GetButtonColorWithTransparency(settings.env_button_color_hover or settings.button_hovered))
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), GetButtonColorWithTransparency(settings.env_button_color_active or settings.button_active))
 end

 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.env_button_rounding or 0)

 if font_env then r.ImGui_PushFont(ctx, font_env, settings.env_font_size or settings.font_size) end
 if settings.env_text_color then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.env_text_color) end
 if r.ImGui_Button(ctx, "ENV") or r.ImGui_IsItemClicked(ctx, 1) then
 r.ImGui_OpenPopup(ctx, "AutomationMenu")
 end
 if settings.env_text_color then r.ImGui_PopStyleColor(ctx) end
 if font_env then r.ImGui_PopFont(ctx) end
 
 if settings.env_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 local border_col = settings.env_border_color or 0xFFFFFFFF
 local border_thickness = settings.env_border_size or 1.0
 local rounding = settings.env_button_rounding or 0
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_col, rounding, nil, border_thickness)
 end
 
 r.ImGui_PopStyleVar(ctx, 2) 
 
 StoreElementRect("env")

 if current_mode == "No override" then
 r.ImGui_PopStyleColor(ctx, 3)
 else
 r.ImGui_PopStyleColor(ctx, 3)
 end

 if r.ImGui_BeginPopup(ctx, "AutomationMenu") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
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
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end
end

function ShowPlaySyncMenu()
 if settings.edit_mode then return end
 if r.ImGui_IsItemClicked(ctx, 1) then 
 r.ImGui_OpenPopup(ctx, "SyncMenu")
 end
 if r.ImGui_BeginPopup(ctx, "SyncMenu") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 if r.ImGui_MenuItem(ctx, "Timecode Sync Settings") then
 r.Main_OnCommand(40619, 0)
 end
 if r.ImGui_MenuItem(ctx, "Toggle Timecode Sync") then
 r.Main_OnCommand(40620, 0)
 end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end
end

function ShowRecordMenu()
 if settings.edit_mode then return end
 if r.ImGui_IsItemClicked(ctx, 1) then 
 r.ImGui_OpenPopup(ctx, "RecordMenu")
 end
 
 if r.ImGui_BeginPopup(ctx, "RecordMenu") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 if r.ImGui_MenuItem(ctx, "Normal Record Mode") then
 r.Main_OnCommand(40252, 0)
 end
 if r.ImGui_MenuItem(ctx, "Selected Item Auto-Punch") then
 r.Main_OnCommand(40253, 0)
 end
 if r.ImGui_MenuItem(ctx, "Time Selection Auto-Punch") then
 r.Main_OnCommand(40076, 0)
 end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end
end

local function DrawTransportButtonBorder(ctx, mode_suffix)
 local mode_show_border = settings["transport_show_border" .. mode_suffix]
 if mode_show_border == nil then mode_show_border = false end
 
 local mode_border_color = settings["transport_border_color" .. mode_suffix]
 if mode_border_color == nil then mode_border_color = 0xFFFFFFFF end
 
 local mode_border_size = settings["transport_border_size" .. mode_suffix]
 if mode_border_size == nil then mode_border_size = 1.0 end
 
 local mode_rounding = settings["transport_button_rounding" .. mode_suffix]
 if mode_rounding == nil then mode_rounding = 0 end
 
 if mode_show_border and settings.transport_mode ~= 1 then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 
 if mode_border_size < 2.0 then
 local offset = 0.5
 min_x = min_x + offset
 min_y = min_y + offset
 max_x = max_x - offset
 max_y = max_y - offset
 end
 
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, mode_border_color, mode_rounding, nil, mode_border_size)
 end
end

function Transport_Buttons(main_window_width, main_window_height)
 if not settings.show_transport then return end
 local allow_input = not settings.edit_mode

 local mode_suffix = ""
 if settings.transport_mode == 0 then
 mode_suffix = "_text"
 elseif settings.transport_mode == 1 then
 mode_suffix = "_graphic"
 elseif settings.transport_mode == 2 then
 mode_suffix = "_custom"
 end
 
 local mode_rounding = settings["transport_button_rounding" .. mode_suffix]
 if mode_rounding == nil then mode_rounding = 0 end
 
 local mode_play_active = settings["play_active" .. mode_suffix]
 if mode_play_active == nil then mode_play_active = 0x00FF00FF end
 
 local mode_record_active = settings["record_active" .. mode_suffix]
 if mode_record_active == nil then mode_record_active = 0xFF0000FF end
 
 local mode_pause_active = settings["pause_active" .. mode_suffix]
 if mode_pause_active == nil then mode_pause_active = 0xFFFF00FF end
 
 local mode_loop_active = settings["loop_active" .. mode_suffix]
 if mode_loop_active == nil then mode_loop_active = 0x00FFFFFF end


 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), mode_rounding)

 local tfsize = settings.transport_font_size or settings.font_size
 
 local mode_button_size = settings["transport_button_size" .. mode_suffix]
 if mode_button_size == nil then mode_button_size = 1.0 end
 
 local mode_spacing = settings["transport_spacing" .. mode_suffix]
 if mode_spacing == nil then mode_spacing = 1.0 end
 
 local buttonSize_graphic = 30 * mode_button_size 
 local buttonSize_text = (tfsize * 1.1) * mode_button_size 
 local buttonSize = settings.use_graphic_buttons and buttonSize_graphic or buttonSize_text
 
 local spacing_graphic = math.floor(buttonSize_graphic * 0.2 * mode_spacing)
 local spacing_text = math.floor(buttonSize_text * 0.2 * mode_spacing)
 local spacing = settings.use_graphic_buttons and spacing_graphic or spacing_text
 local count = 7
 local perButtonWidth_text = buttonSize_text * 1.7 

 local drawList = r.ImGui_GetWindowDrawList(ctx)
 if font_transport then r.ImGui_PushFont(ctx, font_transport, settings.transport_font_size or settings.font_size) end

 local sizes = nil
 local widths_text = nil
 local total_width
 if settings.use_graphic_buttons then
 local gis = settings.custom_image_size or 1.0
 local function sz(use_flag, img_handle, per)
 local base = buttonSize_graphic * gis
 if settings.transport_mode ~= 1 and use_flag and img_handle then
 local ok = true
 if r.ImGui_ValidatePtr then ok = r.ImGui_ValidatePtr(img_handle, 'ImGui_Image*') end
 if ok then return base * (per or 1.0) end
 end
 return base
 end
 sizes = {
 rewind = sz(settings.use_custom_rewind_image, transport_custom_images.rewind, settings.custom_rewind_image_size),
 play = sz(settings.use_custom_play_image, transport_custom_images.play, settings.custom_play_image_size),
 stop = sz(settings.use_custom_stop_image, transport_custom_images.stop, settings.custom_stop_image_size),
 pause = sz(settings.use_custom_pause_image, transport_custom_images.pause, settings.custom_pause_image_size),
 rec = sz(settings.use_custom_record_image, transport_custom_images.record, settings.custom_record_image_size),
 loop = sz(settings.use_custom_loop_image, transport_custom_images.loop, settings.custom_loop_image_size),
 forward = sz(settings.use_custom_forward_image, transport_custom_images.forward, settings.custom_forward_image_size),
 }
 total_width = (sizes.rewind + sizes.play + sizes.stop + sizes.pause + sizes.rec + sizes.loop + sizes.forward)
 + spacing * (count - 1)
 else
 widths_text = {}
 local labels = {"<<","PLAY","STOP","PAUSE","REC","LOOP",">>"}
 local pad = math.floor(buttonSize_text * 0.6) 
 for i=1,#labels do
 local tw, _ = r.ImGui_CalcTextSize(ctx, labels[i])
 widths_text[i] = math.max(tw + pad, perButtonWidth_text)
 end
 total_width = 0
 for i=1,#widths_text do total_width = total_width + widths_text[i] end
 total_width = total_width + spacing * (count - 1)
 end

 local mode_center = settings["center_transport" .. mode_suffix]
 if mode_center == nil then mode_center = true end 
 
 local mode_x = settings["transport_x" .. mode_suffix]
 if mode_x == nil then mode_x = 0.5 end 
 
 local mode_y = settings["transport_y" .. mode_suffix]
 if mode_y == nil then mode_y = 0.5 end  
 
 local mode_x_px = settings["transport_x" .. mode_suffix .. "_px"]
 local mode_y_px = settings["transport_y" .. mode_suffix .. "_px"]
 
 local base_x_px = mode_center and math.max(0, math.floor((main_window_width - total_width) / 2)) or (mode_x_px or math.floor(mode_x * main_window_width))
 local base_y_px = mode_y_px or math.floor(mode_y * main_window_height)
 if mode_x_px then base_x_px = ScalePosX(base_x_px, main_window_width, settings) end
 if mode_y_px then base_y_px = ScalePosY(base_y_px, main_window_height, settings) end

 group_min_x, group_min_y, group_max_x, group_max_y = nil, nil, nil, nil

 local function GetButtonColor()
 local mode_suffix = ""
 if settings.transport_mode == 0 then
 mode_suffix = "_text"
 elseif settings.transport_mode == 1 then
 mode_suffix = "_graphic"
 elseif settings.transport_mode == 2 then
 mode_suffix = "_custom"
 end
 
 local default_normal = 0x333333FF
 local default_hover = 0x555555FF
 local default_active = 0x777777FF
 
 local color
 if r.ImGui_IsItemActive(ctx) then
 color = settings["transport_button_active" .. mode_suffix]
 color = color ~= nil and color or default_active
 elseif r.ImGui_IsItemHovered(ctx) then
 color = settings["transport_button_hover" .. mode_suffix]
 color = color ~= nil and color or default_hover
 else
 color = settings["transport_button_normal" .. mode_suffix]
 color = color ~= nil and color or default_normal
 end
 
 
 return color
 end

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
 DrawTransportButtonBorder(ctx, mode_suffix)
 update_group_bounds()
 if settings.transport_mode ~= 1 and settings.use_custom_rewind_image and transport_custom_images.rewind and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.rewind, 'ImGui_Image*')) then
 local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
 r.ImGui_DrawList_AddImageRounded(drawList, transport_custom_images.rewind, pos_x, pos_y, pos_x + sizes.rewind, pos_y + sizes.rewind, uv_x, 0, uv_x + 0.33, 1, 0xFFFFFFFF, mode_rounding)
 else
 local rewind_color = GetButtonColor()
 local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.rewind, rewind_color)
 graphics.DrawArrows(pos_x, pos_y, sizes.rewind, false)
 end
 local play_uses_vector = not (settings.transport_mode ~= 1 and settings.use_custom_play_image and transport_custom_images.play and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.play, 'ImGui_Image*')))
 local play_bias = play_uses_vector and math.floor(spacing * 0.5) or 0
 x = x + sizes.rewind + spacing + play_bias

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local play_state = r.GetPlayState() & 1 == 1
 pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
 do
 local clicked = r.ImGui_InvisibleButton(ctx, "PLAY", sizes.play, sizes.play)
 if allow_input and clicked then r.Main_OnCommand(PLAY_COMMAND, 0) end
 end
 DrawTransportButtonBorder(ctx, mode_suffix)
 update_group_bounds()
 ShowPlaySyncMenu()
 if settings.transport_mode ~= 1 and settings.use_custom_play_image and transport_custom_images.play and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.play, 'ImGui_Image*')) then
 local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
 if play_state then uv_x = 0.66 end
 r.ImGui_DrawList_AddImageRounded(drawList, transport_custom_images.play, pos_x, pos_y, pos_x + sizes.play, pos_y + sizes.play, uv_x, 0, uv_x + 0.33, 1, 0xFFFFFFFF, mode_rounding)
 else
 local play_color = play_state and mode_play_active or GetButtonColor()
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
 DrawTransportButtonBorder(ctx, mode_suffix)
 update_group_bounds()
 if settings.transport_mode ~= 1 and settings.use_custom_stop_image and transport_custom_images.stop and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.stop, 'ImGui_Image*')) then
 local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
 r.ImGui_DrawList_AddImageRounded(drawList, transport_custom_images.stop, pos_x, pos_y, pos_x + sizes.stop, pos_y + sizes.stop, uv_x, 0, uv_x + 0.33, 1, 0xFFFFFFFF, mode_rounding)
 else
 local stop_color = GetButtonColor()
 local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.stop, stop_color)
 graphics.DrawStop(pos_x, pos_y, sizes.stop)
 end
 x = x + sizes.stop + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local pause_state = r.GetPlayState() & 2 == 2
 pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
 do
 local clicked = r.ImGui_InvisibleButton(ctx, "PAUSE", sizes.pause, sizes.pause)
 if allow_input and clicked then r.Main_OnCommand(PAUSE_COMMAND, 0) end
 end
 DrawTransportButtonBorder(ctx, mode_suffix)
 update_group_bounds()
 if settings.transport_mode ~= 1 and settings.use_custom_pause_image and transport_custom_images.pause and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.pause, 'ImGui_Image*')) then
 local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
 if pause_state then uv_x = 0.66 end
 r.ImGui_DrawList_AddImageRounded(drawList, transport_custom_images.pause, pos_x, pos_y, pos_x + sizes.pause, pos_y + sizes.pause, uv_x, 0, uv_x + 0.33, 1, 0xFFFFFFFF, mode_rounding)
 else
 local pause_color = pause_state and mode_pause_active or GetButtonColor()
 local pause_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.pause, pause_color)
 pause_graphics.DrawPause(pos_x, pos_y, sizes.pause)
 end
 x = x + sizes.pause + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
 pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
 do
 local clicked = r.ImGui_InvisibleButton(ctx, "REC", sizes.rec, sizes.rec)
 if allow_input and clicked then r.Main_OnCommand(RECORD_COMMAND, 0) end
 end
 DrawTransportButtonBorder(ctx, mode_suffix)
 update_group_bounds()
 ShowRecordMenu()
 if settings.transport_mode ~= 1 and settings.use_custom_record_image and transport_custom_images.record and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.record, 'ImGui_Image*')) then
 local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
 if rec_state == 1 then uv_x = 0.66 end
 r.ImGui_DrawList_AddImageRounded(drawList, transport_custom_images.record, pos_x, pos_y, pos_x + sizes.rec, pos_y + sizes.rec, uv_x, 0, uv_x + 0.33, 1, 0xFFFFFFFF, mode_rounding)
 else
 local rec_color = (rec_state == 1) and mode_record_active or GetButtonColor()
 local rec_graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.rec, rec_color)
 rec_graphics.DrawRecord(pos_x, pos_y, sizes.rec)
 end
 x = x + sizes.rec + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
 pos_x, pos_y = r.ImGui_GetCursorScreenPos(ctx)
 do
 local clicked = r.ImGui_InvisibleButton(ctx, "LOOP", sizes.loop, sizes.loop)
 if allow_input and clicked then r.Main_OnCommand(REPEAT_COMMAND, 0) end
 end
 DrawTransportButtonBorder(ctx, mode_suffix)
 update_group_bounds()
 if settings.transport_mode ~= 1 and settings.use_custom_loop_image and transport_custom_images.loop and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.loop, 'ImGui_Image*')) then
 local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
 if repeat_state == 1 then uv_x = 0.66 end
 r.ImGui_DrawList_AddImageRounded(drawList, transport_custom_images.loop, pos_x, pos_y, pos_x + sizes.loop, pos_y + sizes.loop, uv_x, 0, uv_x + 0.33, 1, 0xFFFFFFFF, mode_rounding)
 else
 local loop_color = (repeat_state == 1) and mode_loop_active or GetButtonColor()
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
 DrawTransportButtonBorder(ctx, mode_suffix)
 update_group_bounds()
 if settings.transport_mode ~= 1 and settings.use_custom_forward_image and transport_custom_images.forward and (not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(transport_custom_images.forward, 'ImGui_Image*')) then
 local uv_x = r.ImGui_IsItemHovered(ctx) and 0.33 or 0
 r.ImGui_DrawList_AddImageRounded(drawList, transport_custom_images.forward, pos_x, pos_y, pos_x + sizes.forward, pos_y + sizes.forward, uv_x, 0, uv_x + 0.33, 1, 0xFFFFFFFF, mode_rounding)
 else
 local forward_color = GetButtonColor()
 local graphics = DrawTransportGraphics(drawList, pos_x, pos_y, sizes.forward, forward_color)
 graphics.DrawArrows(pos_x, pos_y, sizes.forward, true)
 end

 else
 local padding_y = math.floor(buttonSize_text * 0.15)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, padding_y)
 
 local mode_normal = settings["transport_button_normal" .. mode_suffix]
 if mode_normal == nil then mode_normal = 0x333333FF end
 local mode_hover = settings["transport_button_hover" .. mode_suffix]
 if mode_hover == nil then mode_hover = 0x555555FF end
 local mode_active = settings["transport_button_active" .. mode_suffix]
 if mode_active == nil then mode_active = 0x777777FF end
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mode_normal)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), mode_hover)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), mode_active)
 
 local buttonHeight = buttonSize_text + (padding_y * 2)
 
 local clicked
 local x = base_x_px
 local w = widths_text or {}

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 clicked = r.ImGui_Button(ctx, "<<", w[1] or perButtonWidth_text, buttonHeight)
 DrawTransportButtonBorder(ctx, mode_suffix)
 if allow_input and clicked then r.Main_OnCommand(GOTO_START, 0) end
 update_group_bounds()
 x = x + (w[1] or perButtonWidth_text) + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local play_state = r.GetPlayState() & 1 == 1
 if play_state then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mode_play_active) end
 clicked = r.ImGui_Button(ctx, "PLAY", w[2] or perButtonWidth_text, buttonHeight)
 DrawTransportButtonBorder(ctx, mode_suffix)
 if allow_input and clicked then r.Main_OnCommand(PLAY_COMMAND, 0) end
 if play_state then r.ImGui_PopStyleColor(ctx) end
 update_group_bounds()
 ShowPlaySyncMenu()
 x = x + (w[2] or perButtonWidth_text) + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 clicked = r.ImGui_Button(ctx, "STOP", w[3] or perButtonWidth_text, buttonHeight)
 DrawTransportButtonBorder(ctx, mode_suffix)
 if allow_input and clicked then r.Main_OnCommand(STOP_COMMAND, 0) end
 update_group_bounds()
 x = x + (w[3] or perButtonWidth_text) + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local pause_state = r.GetPlayState() & 2 == 2
 if pause_state then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mode_pause_active) end
 clicked = r.ImGui_Button(ctx, "PAUSE", w[4] or perButtonWidth_text, buttonHeight)
 DrawTransportButtonBorder(ctx, mode_suffix)
 if allow_input and clicked then r.Main_OnCommand(PAUSE_COMMAND, 0) end
 if pause_state then r.ImGui_PopStyleColor(ctx) end
 update_group_bounds()
 x = x + (w[4] or perButtonWidth_text) + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local rec_state = r.GetToggleCommandState(RECORD_COMMAND)
 if rec_state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mode_record_active) end
 clicked = r.ImGui_Button(ctx, "REC", w[5] or perButtonWidth_text, buttonHeight)
 DrawTransportButtonBorder(ctx, mode_suffix)
 if allow_input and clicked then r.Main_OnCommand(RECORD_COMMAND, 0) end
 if rec_state == 1 then r.ImGui_PopStyleColor(ctx) end
 update_group_bounds()
 ShowRecordMenu()
 x = x + (w[5] or perButtonWidth_text) + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 local repeat_state = r.GetToggleCommandState(REPEAT_COMMAND)
 if repeat_state == 1 then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mode_loop_active) end
 clicked = r.ImGui_Button(ctx, "LOOP", w[6] or perButtonWidth_text, buttonHeight)
 DrawTransportButtonBorder(ctx, mode_suffix)
 if allow_input and clicked then r.Main_OnCommand(REPEAT_COMMAND, 0) end
 if repeat_state == 1 then r.ImGui_PopStyleColor(ctx) end
 update_group_bounds()
 x = x + (w[6] or perButtonWidth_text) + spacing

 r.ImGui_SetCursorPosX(ctx, x)
 r.ImGui_SetCursorPosY(ctx, base_y_px)
 clicked = r.ImGui_Button(ctx, ">>", w[7] or perButtonWidth_text, buttonHeight)
 DrawTransportButtonBorder(ctx, mode_suffix)
 if allow_input and clicked then r.Main_OnCommand(GOTO_END, 0) end
 update_group_bounds()
 
 r.ImGui_PopStyleColor(ctx, 3)
 
 r.ImGui_PopStyleVar(ctx, 1)
 end

 r.ImGui_PopStyleVar(ctx, 2) 

 if font_transport then r.ImGui_PopFont(ctx) end
 if group_min_x then
 StoreElementRectUnion("transport", group_min_x, group_min_y, group_max_x, group_max_y)
 end
end

function MasterVolumeSlider(main_window_width, main_window_height)
 if not settings.show_master_volume then return end
 
 local allow_input = not settings.edit_mode
 
 local master_track = r.GetMasterTrack(0)
 if not master_track then return end
 
 local volume_linear = r.GetMediaTrackInfo_Value(master_track, "D_VOL")
 
 local volume_db
 if volume_linear < 0.0000000298023223876953125 then
 volume_db = -150.0
 elseif volume_linear > 3.981071705534969 then
 volume_db = 12.0
 else
 volume_db = 20.0 * math.log(volume_linear, 10)
 end
 
 local pos_x = settings.master_volume_x_px and ScalePosX(settings.master_volume_x_px, main_window_width, settings) 
 or ((settings.master_volume_x or 0.5) * main_window_width)
 local pos_y = settings.master_volume_y_px and ScalePosY(settings.master_volume_y_px, main_window_height, settings) 
 or ((settings.master_volume_y or 0.7) * main_window_height)
 
 r.ImGui_SetCursorPosX(ctx, pos_x)
 r.ImGui_SetCursorPosY(ctx, pos_y)
 
 local slider_width = settings.master_volume_width or 150
 
 local rounding = settings.master_volume_rounding or 0.0
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), rounding)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), rounding)
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), settings.master_volume_grab or 0xFFFFFFFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), settings.master_volume_grab_active or 0xAAAAAAFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), settings.master_volume_slider_bg or 0x333333FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), settings.master_volume_slider_active or 0x555555FF)
 if settings.master_volume_text_color then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.master_volume_text_color)
 end
 
 if font_master_volume then 
 r.ImGui_PushFont(ctx, font_master_volume, settings.master_volume_font_size or settings.font_size) 
 end
 
 r.ImGui_PushItemWidth(ctx, slider_width)
 
 local rv, new_volume_db = r.ImGui_SliderDouble(ctx, "##MasterVolume", volume_db, -60.0, 12.0, "%.1f dB")
 
 if allow_input and rv then
 local new_volume_linear
 if new_volume_db <= -150.0 then
 new_volume_linear = 0.0
 else
 new_volume_linear = 10.0 ^ (new_volume_db / 20.0)
 end
 
 r.SetMediaTrackInfo_Value(master_track, "D_VOL", new_volume_linear)
 end
 
 if allow_input and r.ImGui_IsItemClicked(ctx, 1) then
 r.SetMediaTrackInfo_Value(master_track, "D_VOL", 1.0) 
 end
 
 r.ImGui_PopItemWidth(ctx)
 
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 
 if settings.master_volume_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local border_color = settings.master_volume_border_color or 0xFFFFFFFF
 local border_size = settings.master_volume_border_size or 1.0
 local border_rounding = settings.master_volume_rounding or 0.0
 
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_color, border_rounding, nil, border_size)
 end
 
 local show_label = settings.show_master_volume_label
 if show_label == nil then show_label = true end 
 
 if show_label then
 r.ImGui_SameLine(ctx)
 r.ImGui_Text(ctx, "Master")
 
 local label_max_x, label_max_y = r.ImGui_GetItemRectMax(ctx)
 max_x = label_max_x
 max_y = math.max(max_y, label_max_y)
 end
 
 if font_master_volume then 
 r.ImGui_PopFont(ctx) 
 end
 
 local color_count = settings.master_volume_text_color and 5 or 4
 r.ImGui_PopStyleColor(ctx, color_count)
 
 r.ImGui_PopStyleVar(ctx, 2)
 
 StoreElementRectUnion("master_volume", min_x, min_y, max_x, max_y)
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
 
 if settings.playrate_show_label ~= false then
 r.ImGui_AlignTextToFramePadding(ctx)
 r.ImGui_Text(ctx, 'Rate:')
 if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 0) then
 r.Main_OnCommand(40521, 0)
 end
 if r.ImGui_IsItemHovered(ctx) then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 r.ImGui_BeginTooltip(ctx)
 r.ImGui_Text(ctx, 'click to reset')
 r.ImGui_EndTooltip(ctx)
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 end
 r.ImGui_SameLine(ctx)
 r.ImGui_SetCursorPosY(ctx, settings.playrate_y_px or (settings.playrate_y * main_window_height))
 end
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), settings.playrate_handle_color or 0x6666DDFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), settings.playrate_handle_color or 0x6666DDFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), settings.playrate_slider_color or 0x4444AAFF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.playrate_text_color or 0xFFFFFFFF)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), settings.playrate_handle_rounding or 6.0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), settings.playrate_handle_size or 12)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.playrate_frame_rounding or 4.0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0) 
 
 r.ImGui_PushItemWidth(ctx, settings.playrate_slider_width or 120)
 local rv, new_rate = r.ImGui_SliderDouble(ctx, '##PlayRateSlider', current_rate, 0.25, 4.0, "%.2fx")
 
 if settings.playrate_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 local border_col = settings.playrate_border_color or 0xFFFFFFFF
 local border_thickness = settings.playrate_border_size or 1.0
 local border_rounding = settings.playrate_frame_rounding or 4.0
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_col, border_rounding, nil, border_thickness)
 end
 
 r.ImGui_PopStyleVar(ctx, 4) 
 r.ImGui_PopStyleColor(ctx, 4)
 
 StoreElementRect("playrate")

 if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 1) then
 r.ImGui_OpenPopup(ctx, "PlayRateMenu")
 end

 if r.ImGui_BeginPopup(ctx, "PlayRateMenu") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 if r.ImGui_MenuItem(ctx, "Set playrate to 1.0") then
 r.Main_OnCommand(40521, 0)
 end
 local preserve_pitch_on = r.GetToggleCommandState(40671) == 1
 if r.ImGui_MenuItem(ctx, "Toggle preserve pitch in audio items", nil, preserve_pitch_on) then
 r.Main_OnCommand(40671, 0)
 end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end

 if rv and (not settings.edit_mode) then
 r.CSurf_OnPlayRateChange(new_rate)
 end

 r.ImGui_PopItemWidth(ctx)
end


function ShowShuttleWheel(main_window_width, main_window_height)
 if not settings.show_shuttle_wheel then return end
 
 r.ImGui_SameLine(ctx)
 r.ImGui_SetCursorPosX(ctx, settings.shuttle_wheel_x_px and ScalePosX(settings.shuttle_wheel_x_px, main_window_width, settings) or (settings.shuttle_wheel_x * main_window_width))
 r.ImGui_SetCursorPosY(ctx, settings.shuttle_wheel_y_px and ScalePosY(settings.shuttle_wheel_y_px, main_window_height, settings) or (settings.shuttle_wheel_y * main_window_height))
 
 local radius = settings.shuttle_wheel_radius or 30
 local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx)
 local center_x = screen_x + radius
 local center_y = screen_y + radius
 
 shuttle_wheel.center_x = center_x
 shuttle_wheel.center_y = center_y
 
 r.ImGui_InvisibleButton(ctx, "shuttle_wheel", radius * 2, radius * 2)
 StoreElementRect("shuttle_wheel")
 
 local is_hovered = r.ImGui_IsItemHovered(ctx)
 local is_active = r.ImGui_IsItemActive(ctx)
 
 local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
 
 local dx = mouse_x - center_x
 local dy = mouse_y - center_y
 local distance = math.sqrt(dx * dx + dy * dy)
 
 local mouse_in_wheel = distance <= radius
 
 if (not settings.edit_mode) and mouse_in_wheel then
 if r.ImGui_IsMouseClicked(ctx, 0) then
 shuttle_wheel.is_dragging = true
 shuttle_wheel.last_mouse_angle = math.atan(dy, dx)
 shuttle_wheel.last_update_time = r.time_precise()
 end
 
 if shuttle_wheel.is_dragging and r.ImGui_IsMouseDown(ctx, 0) then
 local current_angle = math.atan(dy, dx)
 local angle_diff = current_angle - shuttle_wheel.last_mouse_angle
 
 if angle_diff > math.pi then
 angle_diff = angle_diff - 2 * math.pi
 elseif angle_diff < -math.pi then
 angle_diff = angle_diff + 2 * math.pi
 end
 
 local sensitivity = settings.shuttle_wheel_sensitivity or 2.0
 local max_speed = settings.shuttle_wheel_max_speed or 10.0
 local speed = angle_diff * sensitivity
 speed = math.max(-max_speed, math.min(max_speed, speed))
 
 shuttle_wheel.current_speed = speed
 shuttle_wheel.last_mouse_angle = current_angle
 
 shuttle_wheel.accumulated_rotation = shuttle_wheel.accumulated_rotation + angle_diff
 shuttle_wheel.rotation_angle = shuttle_wheel.accumulated_rotation
 
 if math.abs(speed) > 0.01 then
 r.CSurf_ScrubAmt(speed)
 end
 end
 
 if r.ImGui_IsMouseReleased(ctx, 0) then
 shuttle_wheel.is_dragging = false
 shuttle_wheel.current_speed = 0
 end
 end
 
 if not shuttle_wheel.is_dragging then
 shuttle_wheel.current_speed = shuttle_wheel.current_speed * (settings.shuttle_wheel_speed_decay or 0.95)
 end
 
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 
 local wheel_color = settings.shuttle_wheel_color or 0x444444FF
 local active_color = settings.shuttle_wheel_active_color or 0x0088FFFF
 local border_color = settings.shuttle_wheel_border_color or 0x666666FF
 
 local current_color = wheel_color
 if is_hovered or shuttle_wheel.is_dragging then
 current_color = active_color
 end
 
 r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, current_color)
 r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, radius, border_color, 0, 2.0)
 
 local num_ticks = 8
 local tick_length = radius * 0.35 
 local tick_color = 0xDDDDDDFF 
 
 for i = 0, num_ticks - 1 do
 local tick_angle = (i / num_ticks) * 2 * math.pi + shuttle_wheel.rotation_angle
 local inner_x = center_x + math.cos(tick_angle) * (radius - tick_length)
 local inner_y = center_y + math.sin(tick_angle) * (radius - tick_length)
 local outer_x = center_x + math.cos(tick_angle) * (radius - 2)
 local outer_y = center_y + math.sin(tick_angle) * (radius - 2)
 
 local thickness = (i % 2 == 0) and 3.0 or 2.0
 local color = (i % 2 == 0) and 0xFFFFFFFF or tick_color
 
 r.ImGui_DrawList_AddLine(draw_list, inner_x, inner_y, outer_x, outer_y, color, thickness)
 end
 
 if math.abs(shuttle_wheel.current_speed) > 0.01 then
 local speed_normalized = shuttle_wheel.current_speed / (settings.shuttle_wheel_max_speed or 10.0)
 local indicator_length = radius * 0.75 * math.abs(speed_normalized) 
 
 local main_angle = shuttle_wheel.rotation_angle + (speed_normalized > 0 and 0 or math.pi)
 local end_x = center_x + math.cos(main_angle) * indicator_length
 local end_y = center_y + math.sin(main_angle) * indicator_length
 
 local indicator_color = speed_normalized > 0 and 0x00FF00FF or 0xFF0000FF
 r.ImGui_DrawList_AddLine(draw_list, center_x, center_y, end_x, end_y, indicator_color, 5.0) 
 
 local arrow_size = 8
 local arrow_angle1 = main_angle + 2.8
 local arrow_angle2 = main_angle - 2.8
 local arrow_x1 = end_x + math.cos(arrow_angle1) * arrow_size
 local arrow_y1 = end_y + math.sin(arrow_angle1) * arrow_size
 local arrow_x2 = end_x + math.cos(arrow_angle2) * arrow_size
 local arrow_y2 = end_y + math.sin(arrow_angle2) * arrow_size
 
 r.ImGui_DrawList_AddTriangleFilled(draw_list, end_x, end_y, arrow_x1, arrow_y1, arrow_x2, arrow_y2, indicator_color)
 end
 
 r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, 5, 0xFFFFFFFF) 
 r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, 5, 0x000000FF, 0, 2.0) 
 
 if is_hovered and not shuttle_wheel.is_dragging then
 local arrow_size = 6
 local arrow_alpha = 0x666666AA
 
 local left_x = center_x - radius * 0.7
 local left_y = center_y
 r.ImGui_DrawList_AddTriangleFilled(draw_list, 
 left_x + arrow_size, left_y - arrow_size,
 left_x + arrow_size, left_y + arrow_size,
 left_x - arrow_size, left_y, arrow_alpha)
 
 local right_x = center_x + radius * 0.7
 local right_y = center_y
 r.ImGui_DrawList_AddTriangleFilled(draw_list,
 right_x - arrow_size, right_y - arrow_size,
 right_x - arrow_size, right_y + arrow_size, 
 right_x + arrow_size, right_y, arrow_alpha)
 end
end

local function CleanupCache()
 local max_size = settings.waveform_scrubber_cache_size or 1000
 if waveform_scrubber.cache_stats.size > max_size then
 local to_remove = math.floor(max_size * 0.2) 
 for i = 1, to_remove do
 local oldest_key = table.remove(waveform_scrubber.cache_keys_lru, 1)
 if oldest_key then
 waveform_scrubber.peak_cache[oldest_key] = nil
 waveform_scrubber.cache_stats.size = waveform_scrubber.cache_stats.size - 1
 end
 end
 end
end

local function GetCacheKey(item_guid, start_time, end_time, resolution)
 return string.format("%s_%.3f_%.3f_%d", item_guid, start_time, end_time, resolution)
end

local function GetRealPeaksFromItem(item, item_start_time, item_end_time, resolution)
 if not item then return {} end
 
 local take = r.GetActiveTake(item)
 if not take then return {} end
 
 local accessor = r.CreateTakeAudioAccessor(take)
 if not accessor then return {} end
 
 local item_guid = r.BR_GetMediaItemGUID(item)
 if not item_guid then item_guid = tostring(item) end
 
 local cache_key = GetCacheKey(item_guid, item_start_time, item_end_time, resolution)
 
 if waveform_scrubber.peak_cache[cache_key] then
 if accessor then r.DestroyAudioAccessor(accessor) end
 waveform_scrubber.cache_stats.hits = waveform_scrubber.cache_stats.hits + 1
 for i, key in ipairs(waveform_scrubber.cache_keys_lru) do
 if key == cache_key then
 table.remove(waveform_scrubber.cache_keys_lru, i)
 break
 end
 end
 table.insert(waveform_scrubber.cache_keys_lru, cache_key)
 return waveform_scrubber.peak_cache[cache_key]
 end
 
 waveform_scrubber.cache_stats.misses = waveform_scrubber.cache_stats.misses + 1
 
 local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
 local item_len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
 local volume = r.GetMediaItemInfo_Value(item, "D_VOL")
 
 local take_source = r.GetMediaItemTake_Source(take)
 if not take_source then
 if accessor then r.DestroyAudioAccessor(accessor) end
 return {}
 end
 
 local source_srate = r.GetMediaSourceSampleRate(take_source) or 44100
 local source_channels = r.GetMediaSourceNumChannels(take_source) or 1
 
 local take_channels = r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE")
 if take_channels == 1 or take_channels == 2 or take_channels == 3 then
 source_channels = 1
 end
 
 local relative_start = math.max(0, item_start_time - item_pos)
 local relative_end = math.min(item_len, item_end_time - item_pos)
 local time_len = relative_end - relative_start
 
 if time_len <= 0 then 
 if accessor then r.DestroyAudioAccessor(accessor) end
 return {} 
 end
 
 local peaks = {}
 local desired_points = math.min(resolution, math.max(32, resolution))
 local numch = math.max(1, source_channels)
 local buf = r.new_array(desired_points * numch)
 
 local out_sr = desired_points / time_len
 local out_sr_int = math.max(1, math.min(384000, math.floor(out_sr + 0.5)))
 
 local start_sample_time = relative_start
 local ok = r.GetAudioAccessorSamples(accessor, out_sr_int, numch, start_sample_time, desired_points, buf)
 
 if ok then
 for i = 0, desired_points - 1 do
 local sum = 0.0
 for ch = 0, numch - 1 do
 local idx = (i * numch) + ch + 1
 local sample_val = buf[idx] or 0.0
 sum = sum + math.abs(sample_val)
 end
 local peak_val = (sum / numch) * volume
 table.insert(peaks, peak_val)
 end
 else
 for i = 1, desired_points do
 table.insert(peaks, 0)
 end
 end
 
 if accessor then r.DestroyAudioAccessor(accessor) end
 
 waveform_scrubber.peak_cache[cache_key] = peaks
 table.insert(waveform_scrubber.cache_keys_lru, cache_key)
 waveform_scrubber.cache_stats.size = waveform_scrubber.cache_stats.size + 1
 
 CleanupCache()
 
 return peaks
end

local function GetWaveformPeaks(start_time, end_time, width)
 if not settings.waveform_scrubber_use_real_peaks then
 local peaks = {}
 local time_per_pixel = (end_time - start_time) / width
 
 for x = 1, width do
 local time_pos = start_time + (x - 1) * time_per_pixel
 local peak = 0
 local has_audio = false
 
 for i = 0, r.CountMediaItems(0) - 1 do
 local item = r.GetMediaItem(0, i)
 if item then
 local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
 local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
 local item_end = item_start + item_length
 
 if time_pos >= item_start and time_pos <= item_end then
 has_audio = true
 local volume = r.GetMediaItemInfo_Value(item, "D_VOL")
 local rel_pos = (time_pos - item_start) / item_length
 local wave_pattern = math.abs(math.sin(rel_pos * 20)) * (0.7 + 0.3 * math.sin(rel_pos * 3))
 peak = math.max(peak, volume * wave_pattern)
 end
 end
 end
 
 peaks[x] = has_audio and peak or 0
 end
 
 return peaks
 end
 
 local time_range = end_time - start_time
 local time_per_pixel = time_range / width
 
 local base_resolution = settings.waveform_scrubber_peak_resolution or 512
 local lod_factor = 1.0
 
 if settings.waveform_scrubber_lod_auto then
 if time_per_pixel > 1.0 then 
 lod_factor = 0.25 
 elseif time_per_pixel > 0.1 then 
 lod_factor = 0.5 
 else
 lod_factor = 1.0
 end
 end
 
 local resolution = math.max(32, math.floor(base_resolution * lod_factor))
 
 local final_peaks = {}
 for x = 1, width do
 final_peaks[x] = 0
 end
 
 for i = 0, r.CountMediaItems(0) - 1 do
 local item = r.GetMediaItem(0, i)
 if item then
 local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
 local item_end = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
 
 if item_end > start_time and item_start < end_time then
 local overlap_start = math.max(start_time, item_start)
 local overlap_end = math.min(end_time, item_end)
 
 local item_peaks = GetRealPeaksFromItem(item, overlap_start, overlap_end, resolution)
 
 for peak_idx, peak_val in ipairs(item_peaks) do
 local time_pos = overlap_start + (peak_idx - 1) * (overlap_end - overlap_start) / #item_peaks
 local pixel_pos = math.floor((time_pos - start_time) / time_per_pixel) + 1
 
 if pixel_pos >= 1 and pixel_pos <= width then
 final_peaks[pixel_pos] = math.max(final_peaks[pixel_pos], peak_val or 0)
 end
 end
 end
 end
 end
 
 return final_peaks
end

function ShowWaveformScrubber(main_window_width, main_window_height)
 if not settings.show_waveform_scrubber then return end
 
 r.ImGui_SameLine(ctx)
 r.ImGui_SetCursorPosX(ctx, settings.waveform_scrubber_x_px and ScalePosX(settings.waveform_scrubber_x_px, main_window_width, settings) or (settings.waveform_scrubber_x * main_window_width))
 r.ImGui_SetCursorPosY(ctx, settings.waveform_scrubber_y_px and ScalePosY(settings.waveform_scrubber_y_px, main_window_height, settings) or (settings.waveform_scrubber_y * main_window_height))
 
 local width = settings.waveform_scrubber_width or 200
 local height = settings.waveform_scrubber_height or 40
 local window_size = settings.waveform_scrubber_window_size or 10.0
 
 local play_state = r.GetPlayState()
 local current_pos = (play_state == 1) and r.GetPlayPosition() or r.GetCursorPosition()
 
 local project_length = r.GetProjectLength(0)
 local project_start = 0
 
 local start_time, end_time
 
 if settings.waveform_scrubber_show_full_project and project_length > 0 then
 start_time = 0
 end_time = project_length
 else
 start_time = current_pos - window_size / 2
 end_time = current_pos + window_size / 2
 
 if start_time < 0 then
 end_time = end_time - start_time
 start_time = 0
 end
 
 if end_time > project_length and project_length > 0 then
 start_time = start_time - (end_time - project_length)
 end_time = project_length
 if start_time < 0 then start_time = 0 end
 end
 end
 
 local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx)
 
 r.ImGui_InvisibleButton(ctx, "waveform_scrubber", width, height)
 StoreElementRect("waveform_scrubber")
 
 local is_hovered = r.ImGui_IsItemHovered(ctx)
 local is_active = r.ImGui_IsItemActive(ctx)
 
 local time_range = end_time - start_time
 local playhead_relative_pos = time_range > 0 and (current_pos - start_time) / time_range or 0
 playhead_relative_pos = math.max(0, math.min(1, playhead_relative_pos))
 local playhead_x = screen_x + playhead_relative_pos * width
 
 local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
 local handle_size = settings.waveform_scrubber_handle_size or 8
 local mouse_near_playhead = false
 
 if playhead_relative_pos >= 0 and playhead_relative_pos <= 1 and is_hovered then
 mouse_near_playhead = math.abs(mouse_x - playhead_x) <= handle_size
 end
 
 if (not settings.edit_mode) then
 if r.ImGui_IsMouseClicked(ctx, 0) and mouse_near_playhead then
 waveform_scrubber.is_dragging = true
 end
 
 if waveform_scrubber.is_dragging and r.ImGui_IsMouseDown(ctx, 0) then
 local relative_x = mouse_x - screen_x
 local normalized_x = relative_x / width
 normalized_x = math.max(0, math.min(1, normalized_x))
 
 local new_time = start_time + normalized_x * time_range
 r.SetEditCurPos(new_time, true, true)
 end
 
 if r.ImGui_IsMouseReleased(ctx, 0) then
 waveform_scrubber.is_dragging = false
 end
 end
 
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 
 local bg_color = settings.waveform_scrubber_bg_color or 0x222222FF
 r.ImGui_DrawList_AddRectFilled(draw_list, screen_x, screen_y, screen_x + width, screen_y + height, bg_color)
 
 local border_color = settings.waveform_scrubber_border_color or 0x666666FF
 r.ImGui_DrawList_AddRect(draw_list, screen_x, screen_y, screen_x + width, screen_y + height, border_color, 0, 0, 1.0)
 
 if settings.waveform_scrubber_show_grid then
 local grid_color = settings.waveform_scrubber_grid_color or 0x444444FF
 local grid_lines = 4
 
 for i = 1, grid_lines - 1 do
 local x = screen_x + (i / grid_lines) * width
 r.ImGui_DrawList_AddLine(draw_list, x, screen_y, x, screen_y + height, grid_color, 1.0)
 end
 
 local center_y = screen_y + height / 2
 r.ImGui_DrawList_AddLine(draw_list, screen_x, center_y, screen_x + width, center_y, grid_color, 1.0)
 end
 
 local current_time = r.time_precise()
 local update_interval = settings.waveform_scrubber_update_interval or 0.05
 local should_update = (current_time - waveform_scrubber.last_update_time) > update_interval
 
 if waveform_scrubber.is_dragging then
 should_update = true
 end
 
 local peaks
 if should_update then
 peaks = GetWaveformPeaks(start_time, end_time, width)
 waveform_scrubber.waveform_data = peaks 
 waveform_scrubber.last_update_time = current_time
 else
 peaks = waveform_scrubber.waveform_data or {}
 end
 
 local wave_color = settings.waveform_scrubber_wave_color or 0x00AA00FF
 
 for x = 1, width - 1 do
 if peaks[x] and peaks[x] > 0 then
 local peak_height = peaks[x] * height * 0.8 
 local wave_top = screen_y + height/2 - peak_height/2
 local wave_bottom = screen_y + height/2 + peak_height/2
 
 r.ImGui_DrawList_AddLine(draw_list, 
 screen_x + x, wave_top, 
 screen_x + x, wave_bottom, 
 wave_color, 1.0)
 end
 end
 
 local playhead_color = settings.waveform_scrubber_playhead_color or 0xFF0000FF
 
 if mouse_near_playhead or waveform_scrubber.is_dragging then
 local handle_bg_color = waveform_scrubber.is_dragging and 0xFFFF0044 or 0xFFFFFF22
 r.ImGui_DrawList_AddRectFilled(draw_list, 
 playhead_x - handle_size, screen_y, 
 playhead_x + handle_size, screen_y + height, 
 handle_bg_color)
 
 r.ImGui_DrawList_AddLine(draw_list, playhead_x, screen_y, playhead_x, screen_y + height, playhead_color, 4.0)
 
 for i = -1, 1 do
 if i ~= 0 then
 local grip_x = playhead_x + i * 3
 local grip_color = 0xFFFFFF88
 r.ImGui_DrawList_AddLine(draw_list, 
 grip_x, screen_y + height * 0.3, 
 grip_x, screen_y + height * 0.7, 
 grip_color, 1.0)
 end
 end
 else
 r.ImGui_DrawList_AddLine(draw_list, playhead_x, screen_y, playhead_x, screen_y + height, playhead_color, 2.0)
 end
 
 if settings.waveform_scrubber_show_time_labels then
 local text_color = 0xCCCCCCFF
 
 local start_str = string.format("%.1fs", start_time)
 r.ImGui_DrawList_AddText(draw_list, screen_x + 2, screen_y + height - 12, text_color, start_str)
 
 local end_str = string.format("%.1fs", end_time)
 local text_size_x = r.ImGui_CalcTextSize(ctx, end_str)
 r.ImGui_DrawList_AddText(draw_list, screen_x + width - text_size_x - 2, screen_y + height - 12, text_color, end_str)
 
 if playhead_relative_pos >= 0 and playhead_relative_pos <= 1 then
 local current_str = string.format("%.2fs", current_pos)
 local current_text_size = r.ImGui_CalcTextSize(ctx, current_str)
 local text_x = math.max(screen_x + 2, math.min(screen_x + width - current_text_size - 2, playhead_x - current_text_size/2))
 r.ImGui_DrawList_AddText(draw_list, text_x, screen_y + 2, text_color, current_str)
 end
 end
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
 local _, projmeasoffs = reaper.get_config_var_string("projmeasoffs")
 local measure_correction = (projmeasoffs and tonumber(projmeasoffs) == 0) and 1 or 0
 local beatsInMeasure = fullbeats % timesig_num
 local ticks = math.floor((beatsInMeasure - math.floor(beatsInMeasure)) * 960/10)
 local minutes = math.floor(position / 60)
 local seconds = position % 60
 local time_str = string.format("%d:%06.3f", minutes, seconds)
 local mbt_str = string.format("%d.%d.%02d", math.floor(measures + measure_correction), math.floor(beatsInMeasure+1), ticks)
 local mode = settings.cursorpos_mode or "both"
 local label
 if mode == "beats" then
 label = mbt_str
 elseif mode == "time" then
 label = time_str
 else
 label = mbt_str .. " | " .. time_str
 end
 if settings.cursorpos_toggle_invisible then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.cursorpos_text_color or 0xFFFFFFFF)
 else
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.cursorpos_button_color or 0x333333FF)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.cursorpos_text_color or 0xFFFFFFFF)
 end
 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.cursorpos_button_rounding or 0.0)
 
 if font_cursorpos then r.ImGui_PushFont(ctx, font_cursorpos, settings.cursorpos_font_size or settings.font_size) end
 if r.ImGui_Button(ctx, label) and r.ImGui_IsItemClicked(ctx, 1) then
 end
 if font_cursorpos then r.ImGui_PopFont(ctx) end
 
 if settings.cursorpos_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 local border_col = settings.cursorpos_border_color or 0xFFFFFFFF
 local border_thickness = settings.cursorpos_border_size or 1.0
 local border_rounding = settings.cursorpos_button_rounding or 0.0
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_col, border_rounding, nil, border_thickness)
 end
 
 r.ImGui_PopStyleVar(ctx, 2)
 
 StoreElementRect("cursorpos")
 if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 1) then
 r.ImGui_OpenPopup(ctx, "CursorPosModeMenu")
 end
 
 if settings.cursorpos_toggle_invisible then
 r.ImGui_PopStyleColor(ctx, 4)
 else
 r.ImGui_PopStyleColor(ctx, 2) 
 end
 if r.ImGui_BeginPopup(ctx, "CursorPosModeMenu") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 if r.ImGui_MenuItem(ctx, "Beats (MBT)", nil, mode=="beats") then settings.cursorpos_mode = "beats" end
 if r.ImGui_MenuItem(ctx, "Time", nil, mode=="time") then settings.cursorpos_mode = "time" end
 if r.ImGui_MenuItem(ctx, "Both", nil, mode=="both") then settings.cursorpos_mode = "both" end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end
end

function ShowMatrixTicker(main_window_width, main_window_height)
 if not settings.show_matrix_ticker then return end
 
 r.ImGui_SameLine(ctx)
 r.ImGui_SetCursorPosX(ctx, settings.matrix_ticker_x_px and ScalePosX(settings.matrix_ticker_x_px, main_window_width, settings) or (settings.matrix_ticker_x * main_window_width))
 r.ImGui_SetCursorPosY(ctx, settings.matrix_ticker_y_px and ScalePosY(settings.matrix_ticker_y_px, main_window_height, settings) or (settings.matrix_ticker_y * main_window_height))
 
 local width = settings.matrix_ticker_width or 200
 local height = settings.matrix_ticker_height or 40
 
 local current_time = r.time_precise()
 if settings.matrix_ticker_last_switch_time == 0 then
 settings.matrix_ticker_last_switch_time = current_time
 end
 
 local time_since_switch = current_time - settings.matrix_ticker_last_switch_time
 local switch_interval = settings.matrix_ticker_switch_interval or 10.0
 
 if time_since_switch >= switch_interval then
 settings.matrix_ticker_current_index = (settings.matrix_ticker_current_index % 3) + 1
 settings.matrix_ticker_last_switch_time = current_time
 end
 
 local texts = {
 settings.matrix_ticker_text1 or "REAPER",
 settings.matrix_ticker_text2 or "RECORDING",
 settings.matrix_ticker_text3 or "STUDIO"
 }
 local current_text = texts[settings.matrix_ticker_current_index or 1]
 
 local bg_color = settings.matrix_ticker_bg_color or 0x003300FF
 local border_color = settings.matrix_ticker_border_color or 0x000000FF
 local text_color = settings.matrix_ticker_text_color or 0x000000FF
 local grid_color = settings.matrix_ticker_grid_color or 0x00FF0088
 local grid_size = settings.matrix_ticker_grid_size or 2
 
 local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx)
 
 r.ImGui_InvisibleButton(ctx, "##MatrixTicker", width, height)
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 
 local show_bezel = settings.matrix_ticker_show_bezel ~= false
 
 local bezel_side, bezel_top_bottom
 if show_bezel then
 bezel_side = 8  
 bezel_top_bottom = 2 
 else
 bezel_side = 2  
 bezel_top_bottom = 2  
 end
 
 local display_x = screen_x + bezel_side
 local display_y = screen_y + bezel_top_bottom
 local display_width = width - (bezel_side * 2)
 local display_height = height - (bezel_top_bottom * 2)
 
 r.ImGui_DrawList_AddRectFilled(draw_list, screen_x, screen_y, screen_x + width, screen_y + height, border_color)
 
 r.ImGui_DrawList_AddRectFilled(draw_list, display_x, display_y, display_x + display_width, display_y + display_height, bg_color)
 
 r.ImGui_DrawList_AddRect(draw_list, display_x, display_y, display_x + display_width, display_y + display_height, border_color, 0, 0, 1.0)
 
 local font_size = settings.matrix_ticker_font_size or 14
 local font_key = "matrix_ticker_" .. font_size
 if not font_cache then font_cache = {} end
 if not font_cache[font_key] or not r.ImGui_ValidatePtr(font_cache[font_key], 'ImGui_Font*') then
 font_cache[font_key] = r.ImGui_CreateFont('Arial', font_size)
 r.ImGui_Attach(ctx, font_cache[font_key])
 end
 
 r.ImGui_PushFont(ctx, font_cache[font_key], font_size)
 local text_width, text_height = r.ImGui_CalcTextSize(ctx, current_text)
 local text_x = display_x + (display_width - text_width) / 2
 local text_y = display_y + (display_height - text_height) / 2
 r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, current_text)
 r.ImGui_PopFont(ctx)
 
 local grid_border = 1
 local grid_start_x = display_x + grid_border
 local grid_start_y = display_y + grid_border
 local grid_end_x = display_x + display_width - grid_border
 local grid_end_y = display_y + display_height - grid_border
 
 for x = grid_start_x, grid_end_x, grid_size do
 r.ImGui_DrawList_AddLine(draw_list, x, grid_start_y, x, grid_end_y, grid_color, 1.0)
 end
 for y = grid_start_y, grid_end_y, grid_size do
 r.ImGui_DrawList_AddLine(draw_list, grid_start_x, y, grid_end_x, y, grid_color, 1.0)
 end
 
 if show_bezel then
 local screw_radius = 3
 local screw_offset_x = bezel_side / 2  
 local screw_color = 0x666666FF  
 local screw_head_color = 0x999999FF  
 local screw_cross_color = 0x333333FF  
 
 local function draw_screw(cx, cy)
 r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, screw_radius, screw_head_color)
 r.ImGui_DrawList_AddCircle(draw_list, cx, cy, screw_radius, screw_color, 0, 1.0)
 local cross_len = screw_radius * 0.6
 r.ImGui_DrawList_AddLine(draw_list, cx - cross_len, cy, cx + cross_len, cy, screw_cross_color, 1.0)
 r.ImGui_DrawList_AddLine(draw_list, cx, cy - cross_len, cx, cy + cross_len, screw_cross_color, 1.0)
 end
 
 local screw_y = screen_y + height / 2
 draw_screw(screen_x + screw_offset_x, screw_y) 
 draw_screw(screen_x + width - screw_offset_x, screw_y) 
 end
 
 StoreElementRect("matrix_ticker")
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
 reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), GetButtonColorWithTransparency(settings.tempo_button_color))
 reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), GetButtonColorWithTransparency(hov))
 reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), GetButtonColorWithTransparency(act))
 end
 
 reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 0)
 reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), settings.tempo_button_rounding or 0)
 
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
 if settings.tempo_text_color then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), settings.tempo_text_color) end
 reaper.ImGui_Button(ctx, tempo_text)
 if settings.tempo_text_color then reaper.ImGui_PopStyleColor(ctx) end
 
 if settings.tempo_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 local border_col = settings.tempo_border_color or 0xFFFFFFFF
 local border_thickness = settings.tempo_border_size or 1.0
 local rounding = settings.tempo_button_rounding or 0
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_col, rounding, nil, border_thickness)
 end
 
 reaper.ImGui_PopStyleVar(ctx, 2) 
 
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
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
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

 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 reaper.ImGui_EndPopup(ctx)
 end

 reaper.ImGui_PopItemWidth(ctx)
end

function ShowTimeSignature(main_window_width, main_window_height)
 if not settings.show_timesig_button then return end 
 reaper.ImGui_SameLine(ctx)
 reaper.ImGui_SetCursorPosX(ctx, settings.timesig_x_px and ScalePosX(settings.timesig_x_px, main_window_width, settings) or ((settings.timesig_x or (settings.tempo_x + 0.05)) * main_window_width))
 reaper.ImGui_SetCursorPosY(ctx, settings.timesig_y_px and ScalePosY(settings.timesig_y_px, main_window_height, settings) or ((settings.timesig_y or settings.tempo_y) * main_window_height))
 
 local timesig_num, timesig_denom = 4, 4
 local play_state = r.GetPlayState()
 local check_pos
 if play_state & 1 == 1 then
  check_pos = r.GetPlayPosition()
 else
  check_pos = r.GetCursorPosition()
 end
 
 local num_markers = r.CountTempoTimeSigMarkers(0)
 local active_marker_idx = -1
 
 for i = num_markers - 1, 0, -1 do
  local retval, timepos, measurepos, beatpos, bpm, sig_num, sig_denom = r.GetTempoTimeSigMarker(0, i)
  if retval and timepos <= check_pos then
   timesig_num = sig_num
   timesig_denom = sig_denom
   active_marker_idx = i
   break
  end
 end
 
 if active_marker_idx == -1 then
  local _, _, sig_num, sig_denom = r.GetProjectTimeSignature2(0)
  if sig_num and sig_denom then
   timesig_num = sig_num
   timesig_denom = sig_denom
  end
 end

 if font_timesig then reaper.ImGui_PushFont(ctx, font_timesig, settings.timesig_font_size or settings.font_size) end
 local ts_text = string.format("%d/%d", timesig_num, timesig_denom)
 reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), GetButtonColorWithTransparency(settings.timesig_button_color or settings.button_normal))
 reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), GetButtonColorWithTransparency(settings.timesig_button_color_hover or settings.button_hovered))
 reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), GetButtonColorWithTransparency(settings.timesig_button_color_active or settings.button_active))
 if settings.timesig_text_color then reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), settings.timesig_text_color) end
 
 reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameBorderSize(), 0)
 reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), settings.timesig_button_rounding or 0)
 
 local clicked_ts = reaper.ImGui_Button(ctx, ts_text)
 if settings.timesig_text_color then reaper.ImGui_PopStyleColor(ctx) end
 reaper.ImGui_PopStyleColor(ctx, 3)
 
 if settings.timesig_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 local border_col = settings.timesig_border_color or 0xFFFFFFFF
 local border_thickness = settings.timesig_border_size or 1.0
 local rounding = settings.timesig_button_rounding or 0
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_col, rounding, nil, border_thickness)
 end
 
 reaper.ImGui_PopStyleVar(ctx, 2) 
 if clicked_ts or reaper.ImGui_IsItemClicked(ctx,1) then
 reaper.ImGui_OpenPopup(ctx, "TimeSigPopup")
 end
 StoreElementRect("timesig")
 if font_timesig then reaper.ImGui_PopFont(ctx) end
 if reaper.ImGui_BeginPopup(ctx, "TimeSigPopup") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 reaper.ImGui_Text(ctx, "Set Time Signature")
 reaper.ImGui_Separator(ctx)
 reaper.ImGui_PushItemWidth(ctx, 60)
 
 if not timesig_popup_num then timesig_popup_num = timesig_num end
 if not timesig_popup_denom then timesig_popup_denom = timesig_denom end
 
 local rv_num, new_num = reaper.ImGui_InputInt(ctx, "Numerator", timesig_popup_num, 0, 0)
 local rv_denom, new_denom = reaper.ImGui_InputInt(ctx, "Denominator", timesig_popup_denom, 0, 0)
 
 if rv_num and new_num > 0 then timesig_popup_num = new_num end
 if rv_denom and new_denom > 0 then timesig_popup_denom = new_denom end
 
 reaper.ImGui_PopItemWidth(ctx)
 
 reaper.ImGui_Separator(ctx)
 settings.timesig_create_marker_at_cursor = settings.timesig_create_marker_at_cursor or false
 local rv_marker, new_marker = reaper.ImGui_Checkbox(ctx, "Create marker at cursor/play position", settings.timesig_create_marker_at_cursor)
 if rv_marker then
 settings.timesig_create_marker_at_cursor = new_marker
 SaveSettings()
 end
 
 reaper.ImGui_Separator(ctx)
 if reaper.ImGui_Button(ctx, "Apply") then
 reaper.Undo_BeginBlock()
 
 local target_pos = 0
 if settings.timesig_create_marker_at_cursor then
 local play_state = reaper.GetPlayState()
 if play_state & 1 == 1 then
 target_pos = reaper.GetPlayPosition()
 else
 target_pos = reaper.GetCursorPosition()
 end
 end
 
 reaper.SetTempoTimeSigMarker(0, -1, target_pos, -1, -1, -1, timesig_popup_num, timesig_popup_denom, false)
 reaper.Undo_EndBlock("Change time signature", 1|4|8)
 
 timesig_popup_num = nil
 timesig_popup_denom = nil
 reaper.ImGui_CloseCurrentPopup(ctx)
 end
 
 reaper.ImGui_SameLine(ctx)
 if reaper.ImGui_Button(ctx, "Close") then 
 timesig_popup_num = nil
 timesig_popup_denom = nil
 reaper.ImGui_CloseCurrentPopup(ctx) 
 end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 reaper.ImGui_EndPopup(ctx)
 else
 timesig_popup_num = nil
 timesig_popup_denom = nil
 end
end

function ShowTimeSelection(main_window_width, main_window_height)
 if not settings.show_timesel then return end
 
 local start_time, end_time = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
 local length = end_time - start_time
 
 local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = r.GetTempoTimeSigMarker(0, 0)
 if not retval then timesig_num, timesig_denom = 4, 4 end
 
 local _, projmeasoffs = r.get_config_var_string("projmeasoffs")
 local measure_correction = (projmeasoffs and tonumber(projmeasoffs) == 0) and 1 or 0
 
 local minutes_start = math.floor(start_time / 60)
 local seconds_start = start_time % 60
 local sec_format = string.format("%d:%06.3f", minutes_start, seconds_start)
 
 local retval, measures_start, cml, fullbeats_start = r.TimeMap2_timeToBeats(0, start_time)
 local beatsInMeasure_start = fullbeats_start % timesig_num
 local ticks_start = math.floor((beatsInMeasure_start - math.floor(beatsInMeasure_start)) * 960/10)
 local start_midi = string.format("%d.%d.%02d",
 math.floor(measures_start + measure_correction),
 math.floor(beatsInMeasure_start+1),
 ticks_start)
 
 local minutes_end = math.floor(end_time / 60)
 local seconds_end = end_time % 60
 local end_format = string.format("%d:%06.3f", minutes_end, seconds_end)
 
 local retval, measures_end, cml, fullbeats_end = r.TimeMap2_timeToBeats(0, end_time)
 local beatsInMeasure_end = fullbeats_end % timesig_num
 local ticks_end = math.floor((beatsInMeasure_end - math.floor(beatsInMeasure_end)) * 960/10)
 local end_midi = string.format("%d.%d.%02d",
 math.floor(measures_end + measure_correction),
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

 if settings.timesel_toggle_invisible then
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
 else
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.timesel_color or 0x333333FF)
 end

 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.timesel_button_rounding or 0)

 local display_text = ""
 if settings.show_beats and settings.show_time then
 display_text = string.format("Selection: %s | %s | %s | %s | %s | %s",
 start_midi, sec_format,
 end_midi, end_format,
 len_midi, len_format)
 elseif settings.show_beats then
 display_text = string.format("Selection: %s | %s | %s",
 start_midi, end_midi, len_midi)
 elseif settings.show_time then
 display_text = string.format("Selection: %s | %s | %s",
 sec_format, end_format, len_format)
 end

 if display_text == "" then
 if font_timesel then r.ImGui_PushFont(ctx, font_timesel, settings.timesel_font_size or settings.font_size) end
 if settings.timesel_text_color then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.timesel_text_color) end
 r.ImGui_Button(ctx, "##TimeSelectionEmpty")
 if settings.timesel_text_color then r.ImGui_PopStyleColor(ctx) end
 if font_timesel then r.ImGui_PopFont(ctx) end
 else
 if font_timesel then r.ImGui_PushFont(ctx, font_timesel, settings.timesel_font_size or settings.font_size) end
 if settings.timesel_text_color then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.timesel_text_color) end
 r.ImGui_Button(ctx, display_text)
 if settings.timesel_text_color then r.ImGui_PopStyleColor(ctx) end
 if font_timesel then r.ImGui_PopFont(ctx) end
 end
 
 if settings.timesel_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 local border_col = settings.timesel_border_color or 0xFFFFFFFF
 local border_thickness = settings.timesel_border_size or 1.0
 local rounding = settings.timesel_button_rounding or 0
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_col, rounding, nil, border_thickness)
 end
 
 StoreElementRect("timesel")
 

 r.ImGui_PopStyleVar(ctx, 2) 
 
 if settings.timesel_toggle_invisible then
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
 if settings.time_display_hide_seconds then
  return string.format("%02d:%02d", h, m)
 else
  return string.format("%02d:%02d:%02d", h, m, s)
 end
end

local function GetBatteryStatus()
 battery_status.manual_refresh = false
 
 if r.GetOS():match("Win") then
  local handle = io.popen("wmic path Win32_Battery get EstimatedChargeRemaining,BatteryStatus /format:list 2>nul")
  if handle then
   local output = handle:read("*a")
   handle:close()
   
   if output and output ~= "" then
    local level = output:match("EstimatedChargeRemaining=(%d+)")
    if level then
     battery_status.level = tonumber(level)
    end
    
    local status = output:match("BatteryStatus=(%d+)")
    if status then
     battery_status.is_charging = (tonumber(status) == 2)
    end
   else
    battery_status.level = -1
    battery_status.is_charging = false
   end
  end
 
 elseif r.GetOS():match("OSX") or r.GetOS():match("macOS") then
  local handle = io.popen("pmset -g batt 2>/dev/null")
  if handle then
   local output = handle:read("*a")
   handle:close()
   
   if output then
    local level = output:match("(%d+)%%")
    if level then
     battery_status.level = tonumber(level)
    end
    
    battery_status.is_charging = output:match("charging") ~= nil
   end
  end
 
 elseif r.GetOS():match("Linux") then
  local capacity_file = io.open("/sys/class/power_supply/BAT0/capacity", "r")
  if capacity_file then
   local level = capacity_file:read("*n")
   capacity_file:close()
   if level then
    battery_status.level = level
   end
   
   local status_file = io.open("/sys/class/power_supply/BAT0/status", "r")
   if status_file then
    local status = status_file:read("*l")
    status_file:close()
    battery_status.is_charging = (status and status:match("Charging")) ~= nil
   end
  else
   local handle = io.popen("upower -i $(upower -e | grep BAT) 2>/dev/null | grep -E 'percentage|state'")
   if handle then
    local output = handle:read("*a")
    handle:close()
    
    if output and output ~= "" then
     local level = output:match("percentage:%s*(%d+)%%")
     if level then
      battery_status.level = tonumber(level)
     end
     battery_status.is_charging = output:match("state:%s*charging") ~= nil
    end
   end
  end
 end
 
 return battery_status.level, battery_status.is_charging
end

local function DrawBatteryIcon(draw_list, x, y, width, height, level, is_charging, color)
 local body_x1 = x
 local body_y1 = y + height * 0.1
 local body_x2 = x + width * 0.85
 local body_y2 = y + height * 0.9
 local body_rounding = height * 0.1
 
 local tip_x1 = x + width * 0.85
 local tip_y1 = y + height * 0.35
 local tip_x2 = x + width
 local tip_y2 = y + height * 0.65
 
 r.ImGui_DrawList_AddRect(draw_list, body_x1, body_y1, body_x2, body_y2, color, body_rounding, nil, 1.5)
 
 r.ImGui_DrawList_AddRectFilled(draw_list, tip_x1, tip_y1, tip_x2, tip_y2, color)
 
 if level > 0 then
 local fill_width = (body_x2 - body_x1 - 4) * (level / 100)
 local fill_x1 = body_x1 + 2
 local fill_y1 = body_y1 + 2
 local fill_x2 = fill_x1 + fill_width
 local fill_y2 = body_y2 - 2
 
 r.ImGui_DrawList_AddRectFilled(draw_list, fill_x1, fill_y1, fill_x2, fill_y2, color, body_rounding * 0.5)
 end
 
 if is_charging then
 local bolt_x = x + width * 0.35
 local bolt_y = y + height * 0.25
 local bolt_w = width * 0.3
 local bolt_h = height * 0.5
 
 local charging_color = settings.battery_color_charging or 0x00FFFFFF
 r.ImGui_DrawList_AddLine(draw_list, bolt_x + bolt_w * 0.5, bolt_y, bolt_x, bolt_y + bolt_h * 0.5, charging_color, 2)
 r.ImGui_DrawList_AddLine(draw_list, bolt_x, bolt_y + bolt_h * 0.5, bolt_x + bolt_w * 0.5, bolt_y + bolt_h * 0.5, charging_color, 2)
 r.ImGui_DrawList_AddLine(draw_list, bolt_x + bolt_w * 0.5, bolt_y + bolt_h * 0.5, bolt_x + bolt_w * 0.2, bolt_y + bolt_h, charging_color, 2)
 end
end

local function ShowBatteryStatus(main_window_width, main_window_height)
 if not settings.show_battery_status then return end
 
 local level = battery_status.level
 local is_charging = battery_status.is_charging
 
 local display_text = ""
 if level < 0 then
  display_text = "🔋 Click"
  level = 0
  is_charging = false
 else
  if settings.battery_show_icon then
   display_text = is_charging and "⚡" or "🔋"
   if settings.battery_show_percentage then
    display_text = display_text .. " "
   end
  end
  if settings.battery_show_percentage then
   display_text = display_text .. level .. "%"
  end
 end
 
 r.ImGui_SameLine(ctx)
 r.ImGui_SetCursorPosX(ctx, settings.battery_x_px and ScalePosX(settings.battery_x_px, main_window_width, settings) or ((settings.battery_x or 0.90) * main_window_width))
 r.ImGui_SetCursorPosY(ctx, settings.battery_y_px and ScalePosY(settings.battery_y_px, main_window_height, settings) or ((settings.battery_y or 0.02) * main_window_height))
 
 local battery_color
 if is_charging then
 battery_color = settings.battery_color_charging or 0x00FFFFFF
 elseif level > 60 then
 battery_color = settings.battery_color_high or 0x00FF00FF
 elseif level > (settings.battery_warning_threshold or 20) then
 battery_color = settings.battery_color_medium or 0xFFFF00FF
 else
 battery_color = settings.battery_color_low or 0xFF0000FF
 end
 
 if level <= (settings.battery_critical_threshold or 10) and not is_charging then
 local blink = math.floor(r.time_precise() * 2) % 2
 if blink == 0 then
 battery_color = 0xFF000088
 end
 end
 
 if font_battery then 
 r.ImGui_PushFont(ctx, font_battery, settings.battery_font_size or 14) 
 end
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), battery_color)
 
 local screen_x, screen_y = r.ImGui_GetCursorScreenPos(ctx)
 r.ImGui_Text(ctx, display_text)
 local text_w, text_h = r.ImGui_CalcTextSize(ctx, display_text)
 
 r.ImGui_PopStyleColor(ctx)
 
 if settings.battery_use_custom_icon then
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 local icon_size = text_h * 0.9
 local icon_y = screen_y - (icon_size - text_h) * 0.5 + 2
 DrawBatteryIcon(draw_list, screen_x - icon_size - 5, icon_y, icon_size, icon_size, level, is_charging, battery_color)
 end
 
 if font_battery then 
 r.ImGui_PopFont(ctx) 
 end
 
 if r.ImGui_IsItemHovered(ctx) then
 local status_text = is_charging and "Charging" or "Discharging"
 local time_remaining = ""
 
 if level > 0 and not is_charging then
 local estimated_minutes = math.floor((level / 100) * 240)
 local hours = math.floor(estimated_minutes / 60)
 local minutes = estimated_minutes % 60
 time_remaining = string.format("\nEstimated: %dh %dm remaining", hours, minutes)
 end
 
 local tooltip = string.format(
 "Battery: %d%%\nStatus: %s%s\n\nClick to refresh", 
 level, 
 status_text,
 time_remaining
 )
 r.ImGui_SetTooltip(ctx, tooltip)
 
 if r.ImGui_IsItemClicked(ctx, 0) then
 battery_status.manual_refresh = true
 GetBatteryStatus()
 end
 end
 
 StoreElementRect("battery_status")
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
  local format_str = settings.time_display_hide_seconds and "%H:%M" or "%H:%M:%S"
  cached_local_time = os.date(format_str, t)
  last_local_time_sec = t
 end
 display_text = cached_local_time
 end
 
 if settings.time_alarm_enabled and not settings.time_alarm_triggered then
 if settings.time_alarm_type == "time" then
 local current_hour = tonumber(os.date("%H", t))
 local current_minute = tonumber(os.date("%M", t))
 if current_hour == settings.time_alarm_hour and current_minute == settings.time_alarm_minute then
 settings.time_alarm_triggered = true
 settings.time_alarm_start_time = t
 ShowAlarmPopup()
 end
 elseif settings.time_alarm_type == "duration" then
 if settings.time_alarm_start_time == 0 then
 settings.time_alarm_start_time = t
 end
 local elapsed_minutes = math.floor((t - settings.time_alarm_start_time) / 60)
 if elapsed_minutes >= settings.time_alarm_duration_minutes then
 settings.time_alarm_triggered = true
 ShowAlarmPopup()
 end
 end
 end
 
 local text_color = settings.local_time_color or 0xFFFFFFFF
 
 if settings.time_alarm_enabled and not settings.time_alarm_triggered then
     text_color = settings.time_alarm_set_color or 0xFFFF00FF
 end
 
 if settings.time_alarm_triggered and settings.time_alarm_enabled then
     local flash_interval = 1000 
     local current_ms = math.floor(t * 1000) % (flash_interval * 2)
     if current_ms < flash_interval then
         text_color = settings.time_alarm_flash_color or 0xFF0000FF
     end
 end
 
 r.ImGui_SameLine(ctx)
 r.ImGui_SetCursorPosX(ctx, settings.local_time_x_px and ScalePosX(settings.local_time_x_px, main_window_width, settings) or ((settings.local_time_x or 0.5) * main_window_width))
 r.ImGui_SetCursorPosY(ctx, settings.local_time_y_px and ScalePosY(settings.local_time_y_px, main_window_height, settings) or ((settings.local_time_y or 0.02) * main_window_height))
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), settings.local_time_bg_color or 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), settings.local_time_bg_color or 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), settings.local_time_bg_color or 0x00000000)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.local_time_rounding or 0)
 
 if font_localtime then r.ImGui_PushFont(ctx, font_localtime, settings.local_time_font_size or settings.font_size) end
 
 if r.ImGui_Button(ctx, display_text) then
 if not settings.edit_mode then
 show_session_time = not show_session_time
 end
 end
 
 if font_localtime then r.ImGui_PopFont(ctx) end
 
 StoreElementRect("localtime")
 
 r.ImGui_PopStyleVar(ctx, 2)
 r.ImGui_PopStyleColor(ctx, 4)
 
 if (not settings.edit_mode) and r.ImGui_IsItemClicked(ctx, 1) then
 r.ImGui_OpenPopup(ctx, "TimeAlarmMenu")
 end
 
 if r.ImGui_BeginPopup(ctx, "TimeAlarmMenu") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 local rv
 
 rv, settings.time_alarm_enabled = r.ImGui_MenuItem(ctx, "Enable Alarm", nil, settings.time_alarm_enabled)
 
 if settings.time_alarm_enabled then
 r.ImGui_Separator(ctx)
 
 if r.ImGui_MenuItem(ctx, "Specific Time", nil, settings.time_alarm_type == "time") then
 settings.time_alarm_type = "time"
 settings.time_alarm_triggered = false
 settings.time_alarm_start_time = 0
 end
 
 if r.ImGui_MenuItem(ctx, "Duration Timer", nil, settings.time_alarm_type == "duration") then
 settings.time_alarm_type = "duration" 
 settings.time_alarm_triggered = false
 settings.time_alarm_start_time = t
 end
 
 r.ImGui_Separator(ctx)
 
 if settings.time_alarm_triggered then
 if r.ImGui_MenuItem(ctx, "Stop Alarm") then
 settings.time_alarm_triggered = false
 settings.time_alarm_start_time = 0
 end
 else
 if r.ImGui_MenuItem(ctx, "Test Alarm") then
 settings.time_alarm_triggered = true
 settings.time_alarm_start_time = t
 ShowAlarmPopup()
 end
 end
 end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end
 
 if r.ImGui_IsItemHovered(ctx) then
 local tooltip_text = show_session_time and "Click to show local clock" or "Click to show session elapsed time"
 if settings.time_alarm_enabled then
 if settings.time_alarm_type == "time" then
 tooltip_text = tooltip_text .. string.format("\nAlarm set for %02d:%02d", settings.time_alarm_hour, settings.time_alarm_minute)
 else
 tooltip_text = tooltip_text .. string.format("\nTimer: %d minutes", settings.time_alarm_duration_minutes)
 end
 end
 r.ImGui_SetTooltip(ctx, tooltip_text)
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
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), GetButtonColorWithTransparency(settings.taptempo_button_color or settings.button_normal))
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), GetButtonColorWithTransparency(settings.taptempo_button_color_hover or settings.button_hovered))
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), GetButtonColorWithTransparency(settings.taptempo_button_color_active or settings.button_active))
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.taptempo_text_color or 0xFFFFFFFF)
 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.taptempo_button_rounding or 0)
 
 if font_taptempo then r.ImGui_PushFont(ctx, font_taptempo, settings.taptempo_font_size or settings.font_size) end
 
 local tapped = r.ImGui_Button(ctx, settings.tap_button_text)
 
 if font_taptempo then r.ImGui_PopFont(ctx) end
 
 if settings.taptempo_show_border then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
 local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
 local border_col = settings.taptempo_border_color or 0xFFFFFFFF
 local border_thickness = settings.taptempo_border_size or 1.0
 local rounding = settings.taptempo_button_rounding or 0
 r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border_col, rounding, nil, border_thickness)
 end
 
 r.ImGui_PopStyleVar(ctx, 2) 
 r.ImGui_PopStyleColor(ctx, 4) 
 
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
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
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
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end
end

local function CleanupFonts()
 if not ctx or not r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
  return
 end
 
 if font then r.ImGui_Detach(ctx, font) end
 if font_transport then r.ImGui_Detach(ctx, font_transport) end
 if font_env then r.ImGui_Detach(ctx, font_env) end
 if font_master_volume then r.ImGui_Detach(ctx, font_master_volume) end
 if font_tempo then r.ImGui_Detach(ctx, font_tempo) end
 if font_timesig then r.ImGui_Detach(ctx, font_timesig) end
 if font_timesel then r.ImGui_Detach(ctx, font_timesel) end
 if font_cursorpos then r.ImGui_Detach(ctx, font_cursorpos) end
 if font_localtime then r.ImGui_Detach(ctx, font_localtime) end
 if settings_ui_font then r.ImGui_Detach(ctx, settings_ui_font) end
 if settings_ui_font_small then r.ImGui_Detach(ctx, settings_ui_font_small) end
 if font_popup then r.ImGui_Detach(ctx, font_popup) end
 if font_taptempo then r.ImGui_Detach(ctx, font_taptempo) end
 
 if font_cache then
 for key, font_handle in pairs(font_cache) do
 if r.ImGui_ValidatePtr(font_handle, 'ImGui_Font*') then
 r.ImGui_Detach(ctx, font_handle)
 end
 end
 font_cache = {}
 end
 
 collectgarbage("collect")
 collectgarbage("collect")
end

local function CleanupImages()
 if transport_custom_images then
 for key, img in pairs(transport_custom_images) do
 transport_custom_images[key] = nil
 end
 end
 
 collectgarbage("collect")
end

function Main()
 local styles_pushed = false
 local font_pushed = false
 local visible, open
 
 local needs_refresh = r.GetExtState("TK_TRANSPORT", "refresh_buttons")
 if needs_refresh == "1" then
 CustomButtons.LoadLastUsedPreset()
 r.SetExtState("TK_TRANSPORT", "refresh_buttons", "0", false)
 end
 
 if font_needs_update then
 RebuildSectionFonts()
 font_needs_update = false
 end
 
 if ctx and r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
  r.ImGui_PushFont(ctx, font, settings.font_size)
  font_pushed = true

  SetTransportStyle()
  styles_pushed = true
 
  local current_window_flags = window_flags
  if settings.lock_window_size then
   current_window_flags = current_window_flags | r.ImGui_WindowFlags_NoResize()
  end
 
  visible, open = r.ImGui_Begin(ctx, 'Transport', true, current_window_flags)
  if visible then
   r.ImGui_SetScrollY(ctx, 0)
 
 DrawGradientBackground()
 
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
 MasterVolumeSlider(main_window_width, main_window_height)
 ShowCursorPosition(main_window_width, main_window_height)
 ShowShuttleWheel(main_window_width, main_window_height)
 ShowWaveformScrubber(main_window_width, main_window_height)
 ShowMatrixTicker(main_window_width, main_window_height)
 
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
 RenderVisualMetronome(main_window_width, main_window_height)
 ShowLocalTime(main_window_width, main_window_height) 
 ShowBatteryStatus(main_window_width, main_window_height) 

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
 local show_element = true
 if e.showFlag then
 if e.name == "visual_metronome" then
 show_element = settings.show_visual_metronome
 else
 show_element = settings[e.showFlag]
 end
 end
 
 if show_element then
 local rct = element_rects[e.name]
 if rct then
 overlay_rect(e.name, rct.min_x, rct.min_y, rct.max_x, rct.max_y, function(dx_px, dy_px, dx_frac, dy_frac)
 if e.beforeDrag then e.beforeDrag() end
 
 local keyx_to_use = e.keyx
 local keyy_to_use = e.keyy
 if e.name == "transport" then
 local mode_suffix = ""
 if settings.transport_mode == 0 then mode_suffix = "_text"
 elseif settings.transport_mode == 1 then mode_suffix = "_graphic"
 elseif settings.transport_mode == 2 then mode_suffix = "_custom"
 end
 keyx_to_use = e.keyx .. mode_suffix
 keyy_to_use = e.keyy .. mode_suffix
 end
 
 Layout.move_pixel(dx_px, dy_px, dx_frac, dy_frac, keyx_to_use, keyy_to_use, ww, wh)
 end)
 end
 end
 end
 end
 ShowSettings(main_window_width, main_window_height)
 ShowInstanceManager()
 
 if CustomButtons then
     ButtonEditor.HandleIconBrowser(ctx, CustomButtons, settings)
     ButtonEditor.HandleStyleSettingsWindow(ctx)
 end

 if r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem())
 and r.ImGui_IsMouseClicked(ctx, 1)
 and not r.ImGui_IsAnyItemHovered(ctx) then
 r.ImGui_OpenPopup(ctx, "TransportContextMenu")
 end
 if r.ImGui_BeginPopup(ctx, "TransportContextMenu") then
 local color_count, font_pushed, popup_font = PushTransportPopupStyling(ctx, settings)
 
 if r.ImGui_MenuItem(ctx, settings.edit_mode and "Disable Edit Mode" or "Enable Edit Mode") then
 settings.edit_mode = not settings.edit_mode
 SaveSettings()
 end
 local changed
 changed, settings.edit_snap_to_grid = r.ImGui_MenuItem(ctx, "Snap to Grid", nil, settings.edit_snap_to_grid or false)
 if changed then SaveSettings() end
 changed, settings.edit_grid_show = r.ImGui_MenuItem(ctx, "Show Grid", nil, settings.edit_grid_show or false)
 if changed then SaveSettings() end
 
 r.ImGui_SetNextItemWidth(ctx, 150)
 changed, settings.edit_grid_size_px = r.ImGui_SliderInt(ctx, "Grid Size", settings.edit_grid_size_px or 16, 1, 15, "%d px")
 if changed then SaveSettings() end
 
 r.ImGui_Separator(ctx)
 if r.ImGui_MenuItem(ctx, "Show Settings") then
 show_settings = true
 end
 r.ImGui_Separator(ctx)
 if r.ImGui_MenuItem(ctx, "Instance Manager") then
 show_instance_manager = true
 end
 if r.ImGui_MenuItem(ctx, "Close Script") then
 open = false
 end
 
 PopTransportPopupStyling(ctx, color_count, font_pushed, popup_font)
 r.ImGui_EndPopup(ctx)
 end
 
 if settings.transport_border and (settings.transport_border_size or settings.border_size or 0) > 0 then
 local dl = r.ImGui_GetWindowDrawList(ctx)
 local win_x, win_y = r.ImGui_GetWindowPos(ctx)
 local win_w, win_h = r.ImGui_GetWindowSize(ctx)
 local border_col = settings.transport_border
 local border_thickness = settings.transport_border_size or settings.border_size or 1.0
 local rounding = settings.transport_window_rounding or settings.window_rounding or 0.0
 
 r.ImGui_DrawList_AddRect(dl, win_x, win_y, win_x + win_w, win_y + win_h, border_col, rounding, nil, border_thickness)
 end
 
 r.ImGui_End(ctx)
 end
 
 if settings.time_alarm_triggered and settings.time_alarm_popup_enabled then
  local current_time = os.time()
 
  if settings.time_alarm_auto_dismiss and settings.time_alarm_start_time > 0 then
   local elapsed = current_time - settings.time_alarm_start_time
   if elapsed >= (settings.time_alarm_auto_dismiss_seconds or 10) then
    settings.time_alarm_triggered = false
    settings.time_alarm_start_time = 0
   end
  end
 
  if settings.time_alarm_triggered then
   local viewport_x, viewport_y = r.ImGui_GetMainViewport(ctx)
   local display_w, display_h = r.ImGui_Viewport_GetSize(viewport_x)
   local popup_size = settings.time_alarm_popup_size or 300
 r.ImGui_SetNextWindowPos(ctx, (display_w - popup_size) * 0.5, (display_h - popup_size * 0.5) * 0.5)
 r.ImGui_SetNextWindowSize(ctx, popup_size, popup_size * 0.5)
 
 local flash_interval = 500 
 local current_ms = math.floor(current_time * 1000) % (flash_interval * 2)
 local flash_color = (current_ms < flash_interval) and (settings.time_alarm_flash_color or 0xFF0000FF) or 0xFFFFFFFF
 
   local popup_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoTitleBar()
 
   if r.ImGui_Begin(ctx, "##ALARM_POPUP", true, popup_flags) then
    local text = settings.time_alarm_popup_text or "? ALARM! ?"
 
    local large_font_size = settings.time_alarm_popup_text_size or 20
    local alarm_font = r.ImGui_CreateFont("Arial", large_font_size)
    r.ImGui_Attach(ctx, alarm_font)
 
    r.ImGui_PushFont(ctx, alarm_font, large_font_size)
 
    local text_w, text_h = r.ImGui_CalcTextSize(ctx, text)
    local window_w = r.ImGui_GetWindowWidth(ctx)
    local window_h = r.ImGui_GetWindowHeight(ctx)
 
    r.ImGui_SetCursorPosX(ctx, (window_w - text_w) * 0.5)
    r.ImGui_SetCursorPosY(ctx, (window_h - text_h) * 0.4)
 
    r.ImGui_TextColored(ctx, flash_color, text)
    r.ImGui_PopFont(ctx)
 
    r.ImGui_SetCursorPosX(ctx, (window_w - 100) * 0.5)
    r.ImGui_SetCursorPosY(ctx, window_h - 60)
 
    if r.ImGui_Button(ctx, "STOP ALARM", 100, 30) then
     settings.time_alarm_triggered = false
     settings.time_alarm_start_time = 0
    end
 
    r.ImGui_End(ctx)
   end
  end
 end
 end 
 
 if font_pushed then
  r.ImGui_PopFont(ctx)
 end
 if styles_pushed then
  r.ImGui_PopStyleVar(ctx, 8)
  r.ImGui_PopStyleColor(ctx, 13)
 end
 
 if open then
 r.defer(Main)
 else
 CustomButtons.SaveCurrentButtons()
 CleanupImages()
 CleanupFonts()
 ButtonRenderer.Cleanup(ctx)
 collectgarbage("collect")
 collectgarbage("collect")
 end
end

r.defer(Main)


