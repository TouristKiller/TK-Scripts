-- @description TK Script Template for ReaScript with TK GUI
-- @author TouristKiller
-- @version 2.3.0
-- @changelog
--[[
+ Fixed region time editing: only first region was editable due to shared global state and ImGui ID collisions
+ Fixed nil crash in mbt_to_seconds when edited_times_buf had no value yet
+ Improved timeline minimap: added arrange viewport indicator, play cursor (green), time selection overlay
+ Improved timeline minimap: regions now semi-transparent (45% alpha) with border for better overlap visibility
+ Improved timeline minimap: markers now have shadow outline and triangle head for better contrast
+ Improved timeline minimap: hover tooltip shows type, number, name and time position
+ Improved timeline minimap: fixed BeginChild return value check
+ Added "RULER" button (Ruler Lane Manager, action 43542) to bottom button bar
+ Added "Vis" header toggle for regions table (was only on markers)
+ Renamed DEL ALL MARKERS/REGIONS to compact "DEL MKR"/"DEL RGN" with red styling and tooltips
+ Added drag & drop for markers/regions in timeline minimap with grid snap and auto-renumbering
+ Added right-click to set edit cursor position in timeline minimap
+ Added Undo/Redo buttons alongside tabs with custom drawn curved arrow icons
+ Added ruler lane support: markers/regions now show their lane number in tables (Ln column)
+ Added ruler lane visualization in timeline minimap with stacked sub-lanes and lane separators
+ Added lane filter dropdown (Ln) next to type filter when multiple ruler lanes are present
+ Added lane info to minimap hover/drag tooltips
+ Dynamic minimap height scales with number of visible lanes
+ Added region name labels inside regions on the timeline minimap with text clipping
+ Added per-table lane filter dropdowns behind bulk action buttons for markers and regions separately
+ Improved table sorting: items now sorted by lane first, then by position within each lane
+ Added lane separator header rows in marker and region tables for visual grouping
+ Replaced SWS-based renumbering with custom lane-aware renumber function that preserves lane assignments
+ Removed automatic renumber on drag completion (was too destructive)
+ Added double-click on minimap items to select/deselect them in REAPER's ruler (B_UISEL)
+ Added 4px drag threshold to prevent accidental drags interfering with double-click
+ Fixed PushClipRect usage: replaced ImGui.PushClipRect with DrawList_PushClipRect for region name text clipping
+ Fixed scroll wheel causing window content to bounce by adding NoScrollWithMouse flag
+ Increased bottom section height from 82 to 90 to prevent table overlapping bottom section
+ Added lane-aware progress bar: get_region_under_play_cursor now filters by lane
+ Added lane selector combo next to progress bar when multiple region lanes are present
+ Info status line (Rgn:) now respects the progress lane filter
+ Changed progress bar text color to black for better readability
]]--
----------------------------------------------------------------------------
local r = reaper
local ok, err = pcall(function()

local ImGui
if r.APIExists('ImGui_GetBuiltinPath') then
    if not r.ImGui_GetBuiltinPath then
        return r.MB('This script requires ReaImGui extension','',0)
    end
    package.path = r.ImGui_GetBuiltinPath() .. '/?.lua'
    ImGui = require 'imgui' '0.9'
else
    return r.MB('This script requires ReaImGui extension 0.9+','',0)
end

local ctx = ImGui.CreateContext('TK SMART')
local SCRIPT_NAME = "TK_SMART"

window_open = true
local current_dims = nil

local push_style_color = ImGui.PushStyleColor
local pop_style_color = ImGui.PopStyleColor
local push_style_var = ImGui.PushStyleVar
local pop_style_var = ImGui.PopStyleVar
local push_font = ImGui.PushFont
local pop_font = ImGui.PopFont
local same_line = ImGui.SameLine
local get_window_width = ImGui.GetWindowWidth
local get_window_height = ImGui.GetWindowHeight
local get_window_pos = ImGui.GetWindowPos
local get_window_draw_list = ImGui.GetWindowDrawList
local push_item_width = ImGui.PushItemWidth
local pop_item_width = ImGui.PopItemWidth
local sepa_rator = ImGui.Separator

local BASE_WINDOW_FLAGS = ImGui.WindowFlags_NoTitleBar |
                         ImGui.WindowFlags_NoScrollbar |
                         ImGui.WindowFlags_NoScrollWithMouse

local BASE_SETTINGS_FLAGS = ImGui.WindowFlags_NoTitleBar |
                           ImGui.WindowFlags_NoResize |
                           ImGui.WindowFlags_NoScrollbar |
                           ImGui.WindowFlags_AlwaysAutoResize

local cached_colors = {
bg_color = nil,
text_color = nil,
accent_color = nil,
hover_color = nil,
active_color = nil,
slider_color = nil,
slider_active_color = nil
}                 

local BASE_DIMENSIONS = {
    WINDOW_WIDTH = 640,
    WINDOW_HEIGHT = 300,
    BUTTON_HEIGHT = 30,
    TITLE_BUTTON_SIZE = 14,
    TITLE_PADDING = 8,
    SETTINGS_WIDTH = 250,
    FONT_SIZE = 12,
    TITLE_FONT = 14
}

local function getScaledDimensions(scale)
    local current_dims = {}
    for key, value in pairs(BASE_DIMENSIONS) do
        current_dims[key] = math.floor(value * scale)
    end
    return current_dims
end
local SCALE_STEPS = {0.75, 0.85, 1.0, 1.25, 1.5, 1.75, 2.0}
local scale_labels = {}
for _, v in ipairs(SCALE_STEPS) do
    scale_labels[#scale_labels + 1] = string.format("%.2fx", v)
end
local combo_items = table.concat(scale_labels, '|') .. '|'

local fonts = {}
for _, scale in ipairs(SCALE_STEPS) do
    local size = math.floor(BASE_DIMENSIONS.FONT_SIZE * scale)
    fonts[scale] = ImGui.CreateFont('Arial', size)
    ImGui.Attach(ctx, fonts[scale])
end
local title_fonts = {}
for _, scale in ipairs(SCALE_STEPS) do
    local size = math.floor(BASE_DIMENSIONS.TITLE_FONT * scale)
    title_fonts[scale] = ImGui.CreateFont('Arial', size, ImGui.FontFlags_Bold)
    ImGui.Attach(ctx, title_fonts[scale])
end

local function SetDefaultSettings()
    return {
        is_pinned = false,
        is_nomove = false,
        settings_is_pinned = false,
        settings_is_nomove = false,
        show_settings = false,
        save_on_close = true,
        scale_factor = 1.0,
        window_opacity = 1,
        show_tooltips = true,
        window_bg_color = 0.1,
        text_color = 1.0,
        accent_color = 0.6,
        slider_color = 0.7
    }
end
local settings = {}
-----------------------------------------------------------------------------
-- SMART variables
local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
package.path = package.path .. ";" .. script_path .. "?.lua"
local json = require("json")

local project_path = reaper.GetProjectPath("")
local global_path = reaper.GetResourcePath() .. "/Scripts/TK Scripts/TK SMART/presets/"
local retval, value = reaper.GetProjExtState(0, "TK_SMART", "save_preset_globally")
if retval == 1 then
    save_preset_globally = (value == "true")
else
    save_preset_globally = false
end

-- Editing variables
local editing_id = nil
local editing_name = nil

local editing_time_state = nil
local edited_times_buf = {}

local current_project = nil
local project_items = {}
local invisible_items = {}

-- Selection variables
local selected_items = {}
local item_names = {}

local show_weblink_browser = false
local show_minimap = true
local timeline_filter = "all"
local timeline_lane_filter = "all"
local table_lane_filter_marker = "all"
local table_lane_filter_region = "all"
local progress_lane_filter = "all"

-- Search & Filter
local search_marker = ""
local search_region = ""

-- Multi-select
local multi_selected_markers = {}
local multi_selected_regions = {}

-- Auto Color Variables
local auto_color_rules = {} 
local auto_apply_rules = false

local function save_color_rules()
    local str = json.encode(auto_color_rules)
    r.SetExtState(SCRIPT_NAME, "auto_color_rules", str, true)
    r.SetExtState(SCRIPT_NAME, "auto_apply_rules", tostring(auto_apply_rules), true)
end

local function load_color_rules()
    local str = r.GetExtState(SCRIPT_NAME, "auto_color_rules")
    if str and str ~= "" then
        local success, result = pcall(json.decode, str)
        if success then auto_color_rules = result end
    end
    local apply_state = r.GetExtState(SCRIPT_NAME, "auto_apply_rules")
    auto_apply_rules = (apply_state == "true")
end

load_color_rules()

-- Play variables
local currently_playing_region = nil
local next_region_to_play = nil
local currently_playing_marker = nil
local next_marker_to_play = nil

-- State variables bovenaan het script
local show_region_manager = false
local show_region_playlist = false 
local show_region_matrix = false
local show_as_gridlines = false

-- Cache command IDs
local COMMANDS = {
    PLAYLIST = r.NamedCommandLookup("_S&M_SHOW_RGN_PLAYLIST"),
    MATRIX = 41888,
    MANAGER = 40326,
    GRIDLINES = 42328,
    RULER_LANES = 43542
}

local CACHE_CONFIG = {
    FILES = {
        interval = 1.0, 
        last_update = 0
    },
    MARKERS = {
        interval = 0.1, 
        last_update = 0
    }
}

-- Cache containers
local cached_files = {
    project = {},
    global = {},
    project_hash = 0,
    global_hash = 0
}

local cached_markers = {
    items = {},
    project_key = nil
}
-----------------------------------------------------------------------------

--UI Funcions
local function SaveSaveOnCloseSetting()
    r.SetExtState(SCRIPT_NAME, "save_on_close", tostring(settings.save_on_close), true)
end

local function LoadSaveOnCloseSetting()
    local value = r.GetExtState(SCRIPT_NAME, "save_on_close")
    if value ~= "" then
        settings.save_on_close = value == "true"
    end
end

local function SaveSettings()
    local serialized_settings = ""
    for key, value in pairs(settings) do
        serialized_settings = serialized_settings .. key .. "=" .. tostring(value) .. ";"
    end
    r.SetExtState(SCRIPT_NAME, "settings", serialized_settings, true)
end

local function LoadSettings()
    local serialized_settings = r.GetExtState(SCRIPT_NAME, "settings")
    settings = SetDefaultSettings()

    if serialized_settings and serialized_settings ~= "" then
        for key_value in string.gmatch(serialized_settings, "([^;]+)") do
            local key, value = string.match(key_value, "([^=]+)=(.+)")
            if key and value then
                if value == "true" then
                    settings[key] = true
                elseif value == "false" then
                    settings[key] = false
                else
                    settings[key] = tonumber(value) or value
                end
            end
        end
    end
    for key, value in pairs(settings) do
        print(key, value)
    end
end

local function UpdateCachedColors()
    cached_colors.bg_color = ImGui.ColorConvertDouble4ToU32(settings.window_bg_color,settings.window_bg_color,settings.window_bg_color,settings.window_opacity)
    cached_colors.text_color = ImGui.ColorConvertDouble4ToU32(settings.text_color,settings.text_color,settings.text_color,1.0)
    cached_colors.accent_color = ImGui.ColorConvertDouble4ToU32(settings.accent_color,settings.accent_color,settings.accent_color,1.0)
    cached_colors.hover_color = ImGui.ColorConvertDouble4ToU32(math.min(settings.accent_color + 0.1, 1.0),math.min(settings.accent_color + 0.1, 1.0),math.min(settings.accent_color + 0.1, 1.0),1.0) 
    cached_colors.active_color = ImGui.ColorConvertDouble4ToU32(math.min(settings.accent_color + 0.2, 1.0),math.min(settings.accent_color + 0.2, 1.0),math.min(settings.accent_color + 0.2, 1.0),1.0) 
    cached_colors.slider_color = ImGui.ColorConvertDouble4ToU32(settings.slider_color,settings.slider_color,settings.slider_color,1.0)
    cached_colors.slider_active_color = ImGui.ColorConvertDouble4ToU32(math.min(settings.slider_color + 0.2, 1.0),math.min(settings.slider_color + 0.2, 1.0),math.min(settings.slider_color + 0.2, 1.0),1.0)
end

LoadSettings()
LoadSaveOnCloseSetting()
UpdateCachedColors()

-----------------------------------------------------------------------------
-- Profiler setup
--[[local profiler = dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Scripts/Development/cfillion_Lua profiler.lua')
reaper.defer = profiler.defer
profiler.attachToWorld()
profiler.run()
profiler.start()]]--
-----------------------------------------------------------------------------

local function ShowTooltip(text)
  if settings.show_tooltips and ImGui.IsItemHovered(ctx) then
      ImGui.BeginTooltip(ctx)
      ImGui.Text(ctx, text)
      ImGui.EndTooltip(ctx)
  end
end

-- Styles en Colors
local function SetTKStyle()
    if settings_changed then
        UpdateCachedColors()
    end

    -- Style vars
    push_style_var(ctx, ImGui.StyleVar_WindowRounding, 8.0)
    push_style_var(ctx, ImGui.StyleVar_FrameRounding, 6.0)
    push_style_var(ctx, ImGui.StyleVar_PopupRounding, 6.0)
    push_style_var(ctx, ImGui.StyleVar_GrabRounding, 12.0)
    push_style_var(ctx, ImGui.StyleVar_GrabMinSize, 8.0)

    -- Colors
    push_style_color(ctx, ImGui.Col_WindowBg, cached_colors.bg_color)
    push_style_color(ctx, ImGui.Col_Text, cached_colors.text_color)
    push_style_color(ctx, ImGui.Col_FrameBg, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_FrameBgHovered, cached_colors.hover_color)
    push_style_color(ctx, ImGui.Col_FrameBgActive, cached_colors.active_color)
    push_style_color(ctx, ImGui.Col_SliderGrab, cached_colors.slider_color)
    push_style_color(ctx, ImGui.Col_SliderGrabActive, cached_colors.slider_active_color)
    push_style_color(ctx, ImGui.Col_Button, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_ButtonHovered, cached_colors.hover_color)
    push_style_color(ctx, ImGui.Col_ButtonActive, cached_colors.active_color)
    push_style_color(ctx, ImGui.Col_CheckMark, cached_colors.slider_color)
    push_style_color(ctx, ImGui.Col_PopupBg, cached_colors.bg_color)
    push_style_color(ctx, ImGui.Col_Header, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_HeaderHovered, cached_colors.hover_color)
    push_style_color(ctx, ImGui.Col_HeaderActive, cached_colors.active_color)
    push_style_color(ctx, ImGui.Col_TableBorderStrong, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_TableBorderLight, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_TableHeaderBg, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_Tab, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_TabHovered, cached_colors.hover_color)
    push_style_color(ctx, ImGui.Col_TabActive, cached_colors.hover_color)
    push_style_color(ctx, ImGui.Col_TabUnfocused, cached_colors.accent_color)
    push_style_color(ctx, ImGui.Col_TabUnfocusedActive, cached_colors.active_color)
    push_style_color(ctx, ImGui.Col_Separator, 0x4D4D4DFF)
end

local function TKScaleSettings()
    local settings_flags = BASE_SETTINGS_FLAGS
    if settings_is_pinned then  -- Gebruik de lokale variabele
        settings_flags = settings_flags | ImGui.WindowFlags_TopMost
    end
    if settings_is_nomove then  -- Gebruik de lokale variabele
        settings_flags = settings_flags | ImGui.WindowFlags_NoMove
    end

    ImGui.SetNextWindowSize(ctx, current_dims.SETTINGS_WIDTH, 0)
    SetTKStyle()

    local settings_visible, settings_open = ImGui.Begin(ctx, 'Settings', true, settings_flags)
    
    if settings_visible then
        -- Title section with buttons
        local window_width = get_window_width(ctx)
        local window_pos_x, window_pos_y = get_window_pos(ctx)
        local draw_list = get_window_draw_list(ctx)

        -- Title with TK
        push_font(ctx, title_fonts[settings.scale_factor])
        push_style_color(ctx, ImGui.Col_Text, 0xFF0000FF)
        ImGui.SetCursorPosY(ctx, current_dims.TITLE_PADDING - 2)
        ImGui.Text(ctx, "TK")
        pop_style_color (ctx)
        same_line(ctx)
        ImGui.Text(ctx, "UI SETTINGS")

        -- Button configuration
        local button_size = current_dims.TITLE_BUTTON_SIZE
        local spacing = button_size * 0.5
        local margin = button_size * 0.5
        local current_x = window_width - margin - button_size
        local thickness = math.max(1.5, button_size/10)
        local radius = (button_size/2) * 0.7

        -- Common button Y position
        local button_y = current_dims.TITLE_PADDING
        local center_y = window_pos_y + current_dims.TITLE_PADDING + (button_size/3.75)

        -- NoMove button (Yellow)
        local yellow_color = 0xFFFF00FF
        ImGui.SetCursorPosX(ctx, current_x)
        ImGui.SetCursorPosY(ctx, button_y)
        local center_x = window_pos_x + current_x + (button_size/2)
        local clicked_nomove = ImGui.InvisibleButton(ctx, "##nomove_settings", button_size, button_size)
        local is_hovered = ImGui.IsItemHovered(ctx)
        ShowTooltip("Lock Window Position")
        if settings_is_nomove then
            ImGui.DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, yellow_color)
        else
            ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius, yellow_color, 0, thickness - 2)
        end
        if is_hovered then
            ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius * 1.1, yellow_color, 0, thickness)
        end
        if clicked_nomove then settings_is_nomove = not settings_is_nomove end
        current_x = current_x - spacing - button_size

        -- Pin button (Green)
        local green_color = 0x00FF00FF
        ImGui.SetCursorPosX(ctx, current_x)
        ImGui.SetCursorPosY(ctx, button_y)
        center_x = window_pos_x + current_x + (button_size/2)
        local clicked_pin = ImGui.InvisibleButton(ctx, "##pin_settings", button_size, button_size)
        is_hovered = ImGui.IsItemHovered(ctx)
        ShowTooltip("Keep Window On Top")
        if settings_is_pinned then
            ImGui.DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, green_color)
        else
            ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius, green_color, 0, thickness - 2)
        end
        if is_hovered then
            ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius * 1.1, green_color, 0, thickness)
        end
        if clicked_pin then settings_is_pinned = not settings_is_pinned end
        current_x = current_x - spacing - button_size

        -- Settings button (Blue)
        local blue_color = 0x0000FFFF
        ImGui.SetCursorPosX(ctx, current_x)
        ImGui.SetCursorPosY(ctx, button_y)
        center_x = window_pos_x + current_x + (button_size/2)
        local clicked_settings = ImGui.InvisibleButton(ctx, "##settings_close", button_size, button_size)
        is_hovered = ImGui.IsItemHovered(ctx)
        ShowTooltip("Close Settings")
        if show_settings then
            ImGui.DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, blue_color)
        else
            ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius, blue_color, 0, thickness - 2)
        end
        if is_hovered then
            ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius * 1.1, blue_color, 0, thickness)
        end
        if clicked_settings then show_settings = false end

        pop_font(ctx)

        -- Bottom separator line
        local line_color = 0x4D4D4DFF
        ImGui.DrawList_AddLine(draw_list,
            window_pos_x,
            window_pos_y + (25 * settings.scale_factor),
            window_pos_x + window_width,
            window_pos_y + (25 * settings.scale_factor),
            line_color,
            line_thickness
        )

        ImGui.Dummy(ctx, 0, 5 * settings.scale_factor)

        -- Calculate control width
        local content_width = ImGui.GetContentRegionAvail(ctx)
        local margin = 1 * settings.scale_factor
        local control_width = content_width - margin

        -- Interface Scaling Combo
        ImGui.Text(ctx, 'Interface Scaling:')
        local current_label = string.format("%.2fx", settings.scale_factor)
        ImGui.PushItemWidth(ctx, control_width)
        if ImGui.BeginCombo(ctx, "##scale", current_label) then
            for i, scale in ipairs(SCALE_STEPS) do
                local is_selected = (scale == settings.scale_factor)
                local label = string.format("%.2fx", scale)
                
                if ImGui.Selectable(ctx, label, is_selected) then
                    settings.scale_factor = scale  -- Update de scale_factor in de settings tabel
                    scale_factor = scale
                    settings_changed = true
                end
                if is_selected then
                    ImGui.SetItemDefaultFocus(ctx)
                end
            end
            ImGui.EndCombo(ctx)
        end

        -- Opacity Slider
        ImGui.Spacing(ctx)
        ImGui.Text(ctx, 'Transparency')
        local opacity_changed, new_opacity = ImGui.SliderDouble(ctx, "##opacity", settings.window_opacity, 0.0, 1.0, "%.2f")
        if opacity_changed and settings.window_opacity ~= new_opacity then
            settings.window_opacity = new_opacity
            settings_changed = true
        end

        -- BG Color Slider
        ImGui.Spacing(ctx)
        ImGui.Text(ctx, 'Background Color')
        local bg_changed, new_bg_color = ImGui.SliderDouble(ctx, "##bgcolor", settings.window_bg_color, 0.0, 1.0, "%.2f")
        if bg_changed and settings.window_bg_color ~= new_bg_color then
            settings.window_bg_color = new_bg_color
            settings_changed = true
        end

        -- Text Color Slider
        ImGui.Spacing(ctx)
        ImGui.Text(ctx, 'Text Color')
        local text_changed, new_text_color = ImGui.SliderDouble(ctx, "##textcolor", settings.text_color, 0.0, 1.0, "%.2f")
        if text_changed and settings.text_color ~= new_text_color then
            settings.text_color = new_text_color
            settings_changed = true
        end

        -- Accent Color Slider
        ImGui.Spacing(ctx)
        ImGui.Text(ctx, 'Accent Color')
        local accent_changed, new_accent_color = ImGui.SliderDouble(ctx, "##accentcolor", settings.accent_color, 0.0, 1.0, "%.2f")
        if accent_changed and settings.accent_color ~= new_accent_color then
            settings.accent_color = new_accent_color
            settings_changed = true
        end

        -- Slider Color Slider
        ImGui.Spacing(ctx)
        ImGui.Text(ctx, 'Slider Color')
        local slider_changed, new_slider_color = ImGui.SliderDouble(ctx, "##slidercolor", settings.slider_color, 0.0, 1.0, "%.2f")
        if slider_changed and settings.slider_color ~= new_slider_color then
            settings.slider_color = new_slider_color
            settings_changed = true
        end

        ImGui.PopItemWidth(ctx)

        -- Tooltip Checkbox
        ImGui.Spacing(ctx)
        local tooltip_changed, new_tooltip_state = ImGui.Checkbox(ctx, "Show Tooltips", settings.show_tooltips)
        if tooltip_changed then
            settings.show_tooltips = new_tooltip_state
            settings_changed = true
        end

        same_line(ctx)
        local save_changed, new_save_state = ImGui.Checkbox(ctx, "Save on Close", settings.save_on_close)
        if save_changed then
            settings.save_on_close = new_save_state
            settings_changed = true
            SaveSaveOnCloseSetting()
        end
        ShowTooltip("Automatically save settings when closing the script.")
        


        pop_style_color (ctx, 24)
        pop_style_var(ctx, 5)
        ImGui.End(ctx)
    end

    if not settings_open then
        show_settings = false
    end
end

local function TKTitleBar()
    local window_width = get_window_width(ctx)
    local draw_list = get_window_draw_list(ctx)
    local window_pos_x, window_pos_y = get_window_pos(ctx)

    -- Title section
    push_font(ctx, title_fonts[settings.scale_factor])
    push_style_color(ctx, ImGui.Col_Text, 0xFF0000FF)
    ImGui.SetCursorPosY(ctx, current_dims.TITLE_PADDING - 2 * settings.scale_factor)
    ImGui.Text(ctx, "TK")
    pop_style_color (ctx)
    same_line(ctx)
    ImGui.Text(ctx, "SMART")
    pop_font(ctx)
    
    -- Button configuration
    local button_size = current_dims.TITLE_BUTTON_SIZE
    local spacing = button_size * 0.5
    local margin = button_size * 0.5
    local current_x = window_width - margin - button_size
    local thickness = math.max(1.5, button_size/10) * settings.scale_factor
    local radius = (button_size/2) * 0.7

    -- Button colors
    local red_color = 0xFF0000FF
    local green_color = 0x00FF00FF
    local yellow_color = 0xFFFF00FF
    local blue_color = 0x0000FFFF

    -- Common button Y position
    local button_y = current_dims.TITLE_PADDING
    local center_y = window_pos_y + current_dims.TITLE_PADDING + (button_size/3.75)

    -- Close button (Red)
    ImGui.SetCursorPosX(ctx, current_x)
    ImGui.SetCursorPosY(ctx, button_y)
    local center_x = window_pos_x + current_x + (button_size/2)
    local clicked_close = ImGui.InvisibleButton(ctx, "##close", button_size, button_size)
    local is_hovered = ImGui.IsItemHovered(ctx)
    ShowTooltip("Close Window")
    ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius, red_color, 0, thickness - 2)
    if is_hovered then
        ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius * 1.1, red_color, 0, thickness)
    end
    if clicked_close then window_open = false end
    current_x = current_x - spacing - button_size

    -- Pin button (Green)
    ImGui.SetCursorPosX(ctx, current_x)
    ImGui.SetCursorPosY(ctx, button_y)
    center_x = window_pos_x + current_x + (button_size/2)
    local clicked_pin = ImGui.InvisibleButton(ctx, "##pin", button_size, button_size)
    is_hovered = ImGui.IsItemHovered(ctx)
    ShowTooltip("Keep Window On Top")
    if is_pinned then
        ImGui.DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, green_color)
    else
        ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius, green_color, 0, thickness - 2)
    end
    if is_hovered then
        ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius * 1.1, green_color, 0, thickness)
    end
    if clicked_pin then is_pinned = not is_pinned end
    current_x = current_x - spacing - button_size

    -- NoMove button (Yellow)
    ImGui.SetCursorPosX(ctx, current_x)
    ImGui.SetCursorPosY(ctx, button_y)
    center_x = window_pos_x + current_x + (button_size/2)
    local clicked_nomove = ImGui.InvisibleButton(ctx, "##nomove", button_size, button_size)
    is_hovered = ImGui.IsItemHovered(ctx)
    ShowTooltip("Lock Window Position")
    if is_nomove then
        ImGui.DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, yellow_color)
    else
        ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius, yellow_color, 0, thickness - 2)
    end
    if is_hovered then
        ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius * 1.1, yellow_color, 0, thickness)
    end
    if clicked_nomove then is_nomove = not is_nomove end
    current_x = current_x - spacing - button_size

    -- Settings button (Blue)
    ImGui.SetCursorPosX(ctx, current_x)
    ImGui.SetCursorPosY(ctx, button_y)
    center_x = window_pos_x + current_x + (button_size/2)
    local clicked_settings = ImGui.InvisibleButton(ctx, "##settings", button_size, button_size)
    is_hovered = ImGui.IsItemHovered(ctx)
    ShowTooltip("Open UI Settings")
    if show_settings then
        ImGui.DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, blue_color)
    else
        ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius, blue_color, 0, thickness - 2)
    end
    if is_hovered then
        ImGui.DrawList_AddCircle(draw_list, center_x, center_y, radius * 1.1, blue_color, 0, thickness)
    end
    if clicked_settings then show_settings = not show_settings end
    
    -- Bottom separator line
    local line_color = 0x4D4D4DFF
    ImGui.DrawList_AddLine(draw_list,
        window_pos_x,
        window_pos_y + (25 * settings.scale_factor),
        window_pos_x + window_width,
        window_pos_y + (25 * settings.scale_factor),
        line_color,
        line_thickness
    )

    ImGui.Dummy(ctx, 0, 5 * settings.scale_factor)
end
-----------------------------------------------------------------------------
-- SMART Functions:

local function get_project_key()
    local proj = r.EnumProjects(-1)
    local retval, project_path = r.GetProjectPath("")
    if retval and project_path and project_path ~= "" then
        return tostring(proj) .. "_" .. project_path
    else
        return tostring(proj)
    end
end

local function format_time_and_mbt(seconds)
    local minutes = math.floor(seconds / 60)
    local remaining_seconds = seconds % 60
    local time_str = string.format("%d:%05.2f", minutes, remaining_seconds)
    local mbt_str = r.format_timestr_pos(seconds, "", 2):match("(%d+%.%d+%.%d+)")
    local measure, beat, ticks = mbt_str:match("(%d+)%.(%d+)%.(%d%d%d)")
    if measure and beat and ticks then
        ticks = math.floor(tonumber(ticks) / 10)
        mbt_str = string.format("%s.%s.%02d", measure, beat, ticks)
    end
    
    return time_str .. " (" .. mbt_str .. ")"
end

local function mbt_to_seconds(mbt_string)
    if not mbt_string then return nil end
    local measure, beat, ticks = mbt_string:match("(%d+)%.(%d+)%.(%d+)")
    if measure and beat and ticks then
        measure = tonumber(measure)
        beat = tonumber(beat)
        ticks = tonumber(ticks) * 10
        
        local time_str = string.format("%d.%d.%03d", measure, beat, ticks)
        return r.parse_timestr_pos(time_str, 2)
    end
    return nil
end

local function edit_time(ctx, item, is_end_time)
    local time = is_end_time and item.rgnend or item.pos
    local time_str = format_time_and_mbt(time)
    local uid = tostring(item.index) .. (item.isRegion and "R" or "M")
    local label = is_end_time and ("End##" .. uid) or ("Time##" .. uid)
    local state_key = uid .. (is_end_time and "_end" or "_start")
    
    if editing_time_state == state_key then
        local current_mbt = edited_times_buf[state_key] or r.format_timestr_pos(time, "", 2):match("(%d+%.%d+%.%d+)")
        local measure, beat, ticks = current_mbt:match("(%d+)%.(%d+)%.(%d%d%d)")
        if measure and beat and ticks then
            ticks = math.floor(tonumber(ticks) / 10)
            current_mbt = string.format("%s.%s.%02d", measure, beat, ticks)
        end
        local flags = ImGui.InputTextFlags_AutoSelectAll | ImGui.InputTextFlags_EnterReturnsTrue
        local changed, new_time_str = ImGui.InputText(ctx, label, current_mbt, flags)
        if changed then
            edited_times_buf[state_key] = new_time_str
        end
        if ImGui.IsItemDeactivatedAfterEdit(ctx) or (changed and ImGui.IsKeyPressed(ctx, ImGui.Key_Enter)) then
            local new_time = mbt_to_seconds(edited_times_buf[state_key])
            if new_time then
                if is_end_time then
                    item.rgnend = new_time
                    r.SetProjectMarker3(0, item.index, true, item.pos, new_time, item.name, item.color)
                else
                    item.pos = new_time
                    r.SetProjectMarker3(0, item.index, item.isRegion, new_time, item.rgnend or 0, item.name, item.color)
                end
                r.UpdateTimeline()
                r.UpdateArrange()
                r.Undo_OnStateChange("Update " .. (is_end_time and "region end" or "marker/region start") .. " position")
            end
            editing_time_state = nil
            edited_times_buf[state_key] = nil
        end        
        if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
            editing_time_state = nil
            edited_times_buf[state_key] = nil
        end
    else
        if ImGui.Selectable(ctx, time_str .. "##" .. uid .. (is_end_time and "e" or "s"), false) then
            editing_time_state = state_key
        end
    end
end

local function get_invisible_items_file_path()
    local resource_path = r.GetResourcePath()
    return resource_path .. "/Scripts/MarkerRegionInvisibleItems.json"
end

local function save_invisible_items()
    local file_path = get_invisible_items_file_path()
    local file = io.open(file_path, "w")
    if file then
        file:write(json.encode(invisible_items))
        file:close()
    else
        r.ShowMessageBox("Kan onzichtbare items niet opslaan.", "Fout", 0)
    end
end

local function load_invisible_items()
    local file_path = get_invisible_items_file_path()
    local file = io.open(file_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        invisible_items = json.decode(content) or {}
    else
        invisible_items = {}
    end
end
load_invisible_items()

local function save_visibility_to_project()
    local project_key = get_project_key()
    local items = project_items[project_key] or {}
    local visibility_data = {}
    
    for _, item in ipairs(items) do
        visibility_data[tostring(item.index) .. (item.isRegion and "R" or "M")] = item.visible
    end
    
    local serialized = json.encode(visibility_data)
    r.SetProjExtState(0, SCRIPT_NAME, "VisibilityState", serialized)
end

local function load_visibility_from_project()
    local retval, serialized = r.GetProjExtState(0, SCRIPT_NAME, "VisibilityState")
    if retval == 1 then
        local success, visibility_data = pcall(json.decode, serialized)
        if success and type(visibility_data) == "table" then
            return visibility_data
        end
    end
    return {}
end


local function get_markers_and_regions()
    local current_time = r.time_precise()
    local current_project_key = get_project_key()

    if current_time - CACHE_CONFIG.MARKERS.last_update < CACHE_CONFIG.MARKERS.interval 
       and #cached_markers.items > 0 
       and cached_markers.project_key == current_project_key then
        return cached_markers.items
    end

    local visibility_data = load_visibility_from_project()
    local _, num_markers, num_regions = r.CountProjectMarkers(0)
    local new_items = {}

    local has_lane_api = r.GetRegionOrMarker ~= nil and r.GetRegionOrMarkerInfo_Value ~= nil

    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = r.EnumProjectMarkers3(0, i)
        local lane = 0
        if has_lane_api then
            local marker = r.GetRegionOrMarker(0, i, "")
            if marker then
                lane = r.GetRegionOrMarkerInfo_Value(0, marker, "I_LANENUMBER") or 0
            end
        end
        local visibility_key = tostring(markrgnindexnumber) .. (isrgn and "R" or "M")
        local item = {
            name = name or (isrgn and 'Region ' or 'Marker ') .. markrgnindexnumber,
            pos = pos,
            rgnend = rgnend,
            color = color,
            index = markrgnindexnumber,
            isRegion = isrgn,
            lane = lane,
            visible = visibility_data[visibility_key] ~= false,
            project_key = current_project_key
        }
        table.insert(new_items, item)
    end

    for _, invisible_item in ipairs(invisible_items) do
        if invisible_item.project_key == current_project_key then
            local visibility_key = tostring(invisible_item.index) .. (invisible_item.isRegion and "R" or "M")
            if visibility_data[visibility_key] ~= true then
                table.insert(new_items, invisible_item)
            end
        end
    end

    table.sort(new_items, function(a, b)
        local la = a.lane or 0
        local lb = b.lane or 0
        if la ~= lb then return la < lb end
        if a.pos == b.pos then
            return a.index < b.index
        end
        return a.pos < b.pos
    end)

    project_items[current_project_key] = new_items
    cached_markers.items = new_items
    cached_markers.project_key = current_project_key
    CACHE_CONFIG.MARKERS.last_update = current_time

    return new_items
end

local function set_item_visibility(item, visible)
    item.visible = visible
    if visible then
        if item.isRegion then
            r.AddProjectMarker2(0, true, item.pos, item.rgnend, item.name, item.index, item.color)
        else
            r.AddProjectMarker2(0, false, item.pos, 0, item.name, item.index, item.color)
        end
        for i, inv_item in ipairs(invisible_items) do
            if inv_item.index == item.index and inv_item.isRegion == item.isRegion and inv_item.project_key == get_project_key() then
                table.remove(invisible_items, i)
                break
            end
        end
    else
        r.DeleteProjectMarker(0, item.index, item.isRegion)
        table.insert(invisible_items, item)
    end
    r.UpdateTimeline()
    save_invisible_items()
    save_visibility_to_project()
end

local function snap_to_grid(time)
    local _, division = r.GetSetProjectGrid(0, false)
    return math.floor(time / (division * 2) + 0.5) * (division * 2)
end

local renumber_items

local timeline_hovered_item = nil
local timeline_dragging = nil
local timeline_drag_start_x = nil
local timeline_drag_offset = 0

local function draw_timeline_minimap(ctx, items)
    local width, height = ImGui.GetContentRegionAvail(ctx)
    local project_length = r.GetProjectLength(0)
    if project_length <= 0 then return end
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local pos_x, pos_y = ImGui.GetCursorScreenPos(ctx)
    local time_label_height = 13 * settings.scale_factor
    local bar_h = height - time_label_height
    
    ImGui.DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + width, pos_y + bar_h, cached_colors.bg_color)
    
    local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_end > ts_start then
        local sx = pos_x + (ts_start / project_length) * width
        local ex = pos_x + (ts_end / project_length) * width
        ImGui.DrawList_AddRectFilled(draw_list, sx, pos_y, ex, pos_y + bar_h, 0xFFFFFF18)
    end
    
    local arr_start, arr_end = r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
    local vp_x1 = pos_x + (arr_start / project_length) * width
    local vp_x2 = pos_x + (arr_end / project_length) * width
    ImGui.DrawList_AddRectFilled(draw_list, vp_x1, pos_y, vp_x2, pos_y + bar_h, 0xFFFFFF12)
    ImGui.DrawList_AddRect(draw_list, vp_x1, pos_y, vp_x2, pos_y + bar_h, 0xFFFFFF40, 0, 0, 1)
    
    local num_markers = 8
    for i = 0, num_markers do
        local proportion = i / num_markers
        local time = proportion * project_length
        local beat_time = r.TimeMap2_timeToQN(0, time)
        local nearest_measure = math.floor(beat_time / 4) * 4
        local nearest_measure_time = r.TimeMap2_QNToTime(0, nearest_measure)
        local x = pos_x + (nearest_measure_time / project_length) * width
        local mbt = r.format_timestr_pos(nearest_measure_time, "", 1):match("(%d+%.1)")
        
        ImGui.DrawList_AddLine(draw_list, x, pos_y, x, pos_y + bar_h, cached_colors.accent_color, 1)
        ImGui.DrawList_AddText(draw_list, x, pos_y + bar_h, cached_colors.text_color, mbt)
    end
    
    local active_lanes = {}
    local active_lane_set = {}
    for _, item in ipairs(items) do
        if item.visible
           and (timeline_filter == "all" or (timeline_filter == "markers" and not item.isRegion) or (timeline_filter == "regions" and item.isRegion))
           and (timeline_lane_filter == "all" or tostring(item.lane or 0) == timeline_lane_filter) then
            local l = item.lane or 0
            if not active_lane_set[l] then
                active_lane_set[l] = true
                active_lanes[#active_lanes + 1] = l
            end
        end
    end
    table.sort(active_lanes)
    local num_active_lanes = math.max(1, #active_lanes)
    local lane_h = bar_h / num_active_lanes
    local lane_y_map = {}
    for idx, l in ipairs(active_lanes) do
        lane_y_map[l] = pos_y + (idx - 1) * lane_h
    end

    if #active_lanes > 1 then
        for idx = 2, #active_lanes do
            local sep_y = pos_y + (idx - 1) * lane_h
            ImGui.DrawList_AddLine(draw_list, pos_x, sep_y, pos_x + width, sep_y, 0xFFFFFF30, 1)
        end
        for idx, l in ipairs(active_lanes) do
            local ly = lane_y_map[l]
            ImGui.DrawList_AddText(draw_list, pos_x + 2, ly + 1, 0xFFFFFF80, tostring(l))
        end
    end

    timeline_hovered_item = nil
    local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
    
    for _, item in ipairs(items) do
        if item.visible
           and (timeline_filter == "all" or (timeline_filter == "markers" and not item.isRegion) or (timeline_filter == "regions" and item.isRegion))
           and (timeline_lane_filter == "all" or tostring(item.lane or 0) == timeline_lane_filter) then
            local draw_pos = item.pos
            local draw_end = item.rgnend
            if timeline_dragging and timeline_dragging.index == item.index and timeline_dragging.isRegion == item.isRegion then
                local delta_time = ((mouse_x - timeline_drag_start_x) / width) * project_length
                draw_pos = math.max(0, item.pos + delta_time)
                if item.isRegion then
                    local duration = item.rgnend - item.pos
                    draw_end = draw_pos + duration
                end
            end
            
            local x = pos_x + (draw_pos / project_length) * width
            local cr, cg, cb = r.ColorFromNative(item.color)
            local ly = lane_y_map[item.lane or 0] or pos_y
            local lh = lane_h

            if item.isRegion then
                local end_x = pos_x + (draw_end / project_length) * width
                local region_color = ImGui.ColorConvertDouble4ToU32(cr/255, cg/255, cb/255, 0.45)
                local border_color = ImGui.ColorConvertDouble4ToU32(cr/255, cg/255, cb/255, 0.8)
                ImGui.DrawList_AddRectFilled(draw_list, x, ly, end_x, ly + lh, region_color)
                ImGui.DrawList_AddRect(draw_list, x, ly, end_x, ly + lh, border_color, 0, 0, 1)
                if item.name and item.name ~= "" then
                    local rgn_w = end_x - x
                    local txt_w = ImGui.CalcTextSize(ctx, item.name)
                    if txt_w <= rgn_w - 4 then
                        ImGui.DrawList_AddText(draw_list, x + 2, ly + 1, 0xFFFFFFCC, item.name)
                    elseif rgn_w > 12 then
                        ImGui.DrawList_PushClipRect(draw_list, x + 1, ly, end_x - 1, ly + lh, true)
                        ImGui.DrawList_AddText(draw_list, x + 2, ly + 1, 0xFFFFFFCC, item.name)
                        ImGui.DrawList_PopClipRect(draw_list)
                    end
                end
                if not timeline_dragging and mouse_x >= x and mouse_x <= end_x and mouse_y >= ly and mouse_y <= ly + lh then
                    timeline_hovered_item = item
                end
            else
                local marker_color = ImGui.ColorConvertDouble4ToU32(cr/255, cg/255, cb/255, 1)
                ImGui.DrawList_AddLine(draw_list, x, ly, x, ly + lh, 0x000000AA, 4)
                ImGui.DrawList_AddLine(draw_list, x, ly, x, ly + lh, marker_color, 2)
                local tri_h = math.min(6 * settings.scale_factor, lh * 0.35)
                ImGui.DrawList_AddTriangleFilled(draw_list, x, ly, x - tri_h, ly - tri_h, x + tri_h, ly - tri_h, marker_color)
                ImGui.DrawList_AddTriangle(draw_list, x, ly, x - tri_h, ly - tri_h, x + tri_h, ly - tri_h, 0x000000AA, 1)
                if not timeline_dragging and math.abs(mouse_x - x) < 6 and mouse_y >= ly - tri_h and mouse_y <= ly + lh then
                    timeline_hovered_item = item
                end
            end
        end
    end
    
    local drag_threshold = 4
    local drag_active = timeline_dragging and math.abs(mouse_x - (timeline_drag_start_x or mouse_x)) > drag_threshold

    if drag_active then
        local delta_time = ((mouse_x - timeline_drag_start_x) / width) * project_length
        local preview_pos = snap_to_grid(math.max(0, timeline_dragging.pos + delta_time))
        local preview_x = pos_x + (preview_pos / project_length) * width
        ImGui.DrawList_AddLine(draw_list, preview_x, pos_y, preview_x, pos_y + bar_h, 0xFFFF00AA, 1)
        
        local type_label = timeline_dragging.isRegion and "Region" or "Marker"
        local drag_tip = type_label .. " #" .. timeline_dragging.index
        if timeline_dragging.name and timeline_dragging.name ~= "" then
            drag_tip = drag_tip .. ": " .. timeline_dragging.name
        end
        if num_active_lanes > 1 or (timeline_dragging.lane or 0) > 0 then
            drag_tip = drag_tip .. "  [L" .. (timeline_dragging.lane or 0) .. "]"
        end
        drag_tip = drag_tip .. "\n" .. format_time_and_mbt(preview_pos)
        ImGui.SetTooltip(ctx, drag_tip)
    end
    
    local cursor_pos = r.GetCursorPosition()
    local cursor_x = pos_x + (cursor_pos / project_length) * width
    ImGui.DrawList_AddLine(draw_list, cursor_x, pos_y, cursor_x, pos_y + bar_h, cached_colors.text_color, 2)
    
    local play_state = r.GetPlayState()
    if play_state & 1 == 1 then
        local play_pos = r.GetPlayPosition()
        local play_x = pos_x + (play_pos / project_length) * width
        ImGui.DrawList_AddLine(draw_list, play_x, pos_y, play_x, pos_y + bar_h, 0x00FF00CC, 2)
    end
    
    ImGui.InvisibleButton(ctx, "timeline", width, height)
    local is_hovered = ImGui.IsItemHovered(ctx)
    
    if is_hovered and not timeline_dragging and timeline_hovered_item then
        if ImGui.IsMouseDoubleClicked(ctx, 0) then
            local item = timeline_hovered_item
            r.SetEditCurPos(item.pos, true, false)
            if item.isRegion then
                r.GetSet_LoopTimeRange(true, false, item.pos, item.rgnend, false)
            end
            if r.GetRegionOrMarker and r.SetRegionOrMarkerInfo_Value then
                local _, num_m, num_r = r.CountProjectMarkers(0)
                for mi = 0, num_m + num_r - 1 do
                    local rv, isrgn, pos, rgnend, name, idx = r.EnumProjectMarkers3(0, mi)
                    if rv ~= 0 then
                        local marker = r.GetRegionOrMarker(0, mi, "")
                        if marker then
                            local should_select = (isrgn == item.isRegion and idx == item.index) and 1 or 0
                            r.SetRegionOrMarkerInfo_Value(0, marker, "B_UISEL", should_select)
                        end
                    end
                end
            end
            r.UpdateTimeline()
            timeline_dragging = nil
            timeline_drag_start_x = nil
        elseif ImGui.IsMouseClicked(ctx, 0) then
            timeline_dragging = timeline_hovered_item
            timeline_drag_start_x = mouse_x
        end
        local type_label = timeline_hovered_item.isRegion and "Region" or "Marker"
        local tip = type_label .. " #" .. timeline_hovered_item.index
        if timeline_hovered_item.name and timeline_hovered_item.name ~= "" then
            tip = tip .. ": " .. timeline_hovered_item.name
        end
        if num_active_lanes > 1 or (timeline_hovered_item.lane or 0) > 0 then
            tip = tip .. "  [L" .. (timeline_hovered_item.lane or 0) .. "]"
        end
        local t = format_time_and_mbt(timeline_hovered_item.pos)
        if timeline_hovered_item.isRegion then
            t = t .. " - " .. format_time_and_mbt(timeline_hovered_item.rgnend)
        end
        tip = tip .. "\n" .. t
        ImGui.SetTooltip(ctx, tip)
    end
    
    if timeline_dragging then
        if ImGui.IsMouseReleased(ctx, 0) then
            if drag_active then
                local delta_time = ((mouse_x - timeline_drag_start_x) / width) * project_length
                local new_pos = snap_to_grid(math.max(0, timeline_dragging.pos + delta_time))
                
                if math.abs(new_pos - timeline_dragging.pos) > 0.001 then
                    r.Undo_BeginBlock()
                    r.PreventUIRefresh(1)
                    
                    if timeline_dragging.isRegion then
                        local duration = timeline_dragging.rgnend - timeline_dragging.pos
                        local new_end = new_pos + duration
                        r.SetProjectMarker3(0, timeline_dragging.index, true, new_pos, new_end, timeline_dragging.name, timeline_dragging.color)
                        timeline_dragging.pos = new_pos
                        timeline_dragging.rgnend = new_end
                    else
                        r.SetProjectMarker3(0, timeline_dragging.index, false, new_pos, 0, timeline_dragging.name, timeline_dragging.color)
                        timeline_dragging.pos = new_pos
                    end
                    
                    CACHE_CONFIG.MARKERS.last_update = 0
                    
                    r.PreventUIRefresh(-1)
                    r.UpdateTimeline()
                    r.UpdateArrange()
                    local action_name = timeline_dragging.isRegion and "Move region via minimap" or "Move marker via minimap"
                    r.Undo_EndBlock(action_name, -1)
                end
            end
            
            timeline_dragging = nil
            timeline_drag_start_x = nil
        end
    elseif is_hovered and not timeline_hovered_item then
        if ImGui.IsMouseClicked(ctx, 0) then
            local mx = ImGui.GetMousePos(ctx)
            local new_pos = ((mx - pos_x) / width) * project_length
            local snapped_pos = snap_to_grid(new_pos)
            r.SetEditCurPos(snapped_pos, true, true)
        end
    end
    
    if is_hovered and ImGui.IsMouseClicked(ctx, 1) then
        local mx = ImGui.GetMousePos(ctx)
        local new_pos = ((mx - pos_x) / width) * project_length
        local snapped_pos = snap_to_grid(new_pos)
        r.SetEditCurPos(snapped_pos, true, true)
    end
    
    if timeline_dragging or (is_hovered and timeline_hovered_item) then
        ImGui.SetMouseCursor(ctx, ImGui.MouseCursor_Hand)
    end
end

local function display_colored_id(ctx, item, i, items)
    local red, g, b = r.ColorFromNative(item.color)
    local color = ImGui.ColorConvertDouble4ToU32(red/255, g/255, b/255, 0.7)
    push_style_color(ctx, ImGui.Col_FrameBg, color)
    push_style_color(ctx, ImGui.Col_Text, 0xFFFFFFFF)
    push_item_width(ctx, 30 * settings.scale_factor)
    local display_value = editing_id == i and "" or tostring(item.index)
    local changed, new_id_str = ImGui.InputText(ctx, "##id" .. i, display_value, ImGui.InputTextFlags_AutoSelectAll)
    if ImGui.IsItemClicked(ctx) and ImGui.IsMouseDoubleClicked(ctx, 0) then
        editing_id = i
    end
    if editing_id == i then
        if changed then
            local new_id = tonumber(new_id_str)
            if new_id and new_id > 0 then
                local id_exists = false
                for _, other_item in ipairs(items) do
                    if other_item.index == new_id and other_item ~= item then
                        id_exists = true
                        break
                    end
                end
                if not id_exists then
                    local old_id = item.index
                    item.index = new_id
                    if item.visible then
                        r.DeleteProjectMarker(0, old_id, item.isRegion)
                        if item.isRegion then
                            r.AddProjectMarker2(0, true, item.pos, item.rgnend, item.name, new_id, item.color)
                        else
                            r.AddProjectMarker2(0, false, item.pos, 0, item.name, new_id, item.color)
                        end
                    else
                        update_invisible_item(item, old_id, new_id)
                    end
                    r.UpdateTimeline()
                    save_invisible_items()
                    save_visibility_to_project()
                end
            end
        end
        if ImGui.IsItemDeactivatedAfterEdit(ctx) then
            editing_id = nil
        end
    end    
    pop_item_width(ctx)
    pop_style_color(ctx, 2)
end

local function get_sws_colors()
    local colors = {}
    local reaper_resource_path = r.GetResourcePath()
    local color_dir = reaper_resource_path .. "/Color/"

    local function read_color_file(filename)
        local file_path = color_dir .. filename
        if r.file_exists(file_path) then
            for line in io.lines(file_path) do
                local k, v = string.match(line, "^(custcolor%d+)=(%d+)$")
                if k and v then
                    table.insert(colors, tonumber(v))
                end
            end
        end
    end
    local i = 0
    local file = r.EnumerateFiles(color_dir, i)
    while file do
        if string.match(file, "%.SWSColor$") then
            read_color_file(file)
            break
        end
        i = i + 1
        file = r.EnumerateFiles(color_dir, i)
    end
    return colors, #colors > 0
end

local function edit_color(item, i)
    local sws_colors, has_sws_colors = get_sws_colors()
    
    if ImGui.Button(ctx, "Color##" .. tostring(i)) then
        if has_sws_colors then
            if active_color_picker == i then
                active_color_picker = nil
            else
                active_color_picker = i
            end
        else
            -- removed shadowing of global 'r'; ColorFromNative result not needed here
            local retval, new_color = r.GR_SelectColor(item.color)
            if retval then
                local native_color = new_color|0x1000000
                if item.isRegion then
                    r.SetProjectMarker3(0, item.index, true, item.pos, item.rgnend, item.name, native_color)
                else
                    r.SetProjectMarker3(0, item.index, false, item.pos, 0, item.name, native_color)
                end
                item.color = native_color
                r.UpdateTimeline()
            end
        end
    end
    if active_color_picker == i then
        local pos_x, pos_y = ImGui.GetItemRectMax(ctx)
        ImGui.SetNextWindowPos(ctx, pos_x, pos_y, ImGui.Cond_Always)
        ImGui.SetNextWindowSize(ctx, 200 * settings.scale_factor, 200 * settings.scale_factor, ImGui.Cond_FirstUseEver)
        
        local window_flags = ImGui.WindowFlags_NoTitleBar | 
                           ImGui.WindowFlags_NoMove | 
                           ImGui.WindowFlags_NoResize | 
                           ImGui.WindowFlags_AlwaysAutoResize
        
        local visible, open = ImGui.Begin(ctx, "Color Picker##" .. tostring(i), true, window_flags)
        if visible then
            local columns = 8
            local color_count = #sws_colors
            local rows = math.max(1, math.ceil(color_count / columns))

            for row = 1, rows do
                ImGui.PushID(ctx, row)
                for col = 1, columns do
                    local color_index = (row - 1) * columns + col
                    if color_index <= color_count then
                        local color = sws_colors[color_index]
                        local red, g, b = r.ColorFromNative(color)
                        local color_vec4 = ImGui.ColorConvertDouble4ToU32(red/255, g/255, b/255, 1.0)
                        
                        if ImGui.ColorButton(ctx, "##SWSColor" .. color_index, color_vec4) then
                            local native_color = r.ColorToNative(red, g, b)|0x1000000
                            if item.isRegion then
                                r.SetProjectMarker3(0, item.index, true, item.pos, item.rgnend, item.name, native_color)
                            else
                                r.SetProjectMarker3(0, item.index, false, item.pos, 0, item.name, native_color)
                            end
                            item.color = native_color
                            r.UpdateTimeline()
                            active_color_picker = nil
                        end
                        if col < columns then ImGui.SameLine(ctx) end
                    end
                end
                ImGui.PopID(ctx)
            end
            ImGui.End(ctx)
        end
        if not open then
            active_color_picker = nil
        end
    end
end

local function find_next_marker_position(current_pos)
    local items = get_markers_and_regions()
    local next_pos = nil
    for _, item in ipairs(items) do
        if not item.isRegion and item.visible and item.pos > current_pos then
            if not next_pos or item.pos < next_pos then
                next_pos = item.pos
            end
        end
    end
    if not next_pos then
        local project_end = r.GetProjectLength()
        local num_items = r.CountMediaItems(0)
        for i = 0, num_items - 1 do
            local item = r.GetMediaItem(0, i)
            local item_end = r.GetMediaItemInfo_Value(item, "D_POSITION") + 
                           r.GetMediaItemInfo_Value(item, "D_LENGTH")
            project_end = math.max(project_end, item_end)
        end
        next_pos = project_end
    end    
    return next_pos
end

local function play_marker(marker)
    if marker and marker.visible then
        marker.end_time = find_next_marker_position(marker.pos)        
        if marker.end_time > marker.pos then
            r.SetEditCurPos(marker.pos, true, false)
            r.GetSet_LoopTimeRange(true, false, marker.pos, marker.end_time, false)
            r.OnPlayButton()
            currently_playing_marker = marker
            r.UpdateTimeline()
        end
    end
end

local function handle_marker_playback()
    if currently_playing_marker then
        local play_state = r.GetPlayState()
        local play_position = r.GetPlayPosition()
        
        if play_state == 0 or (play_position >= currently_playing_marker.end_time and 
           play_position > currently_playing_marker.pos + 0.1) then
            currently_playing_marker = nil
            if next_marker_to_play then
                play_marker(next_marker_to_play)
                next_marker_to_play = nil
            end
            r.UpdateTimeline()
        end
    end
end

local function apply_color_rules_to_project()
    local items = get_markers_and_regions()
    local change_count = 0
    
    r.Undo_BeginBlock()
    for _, item in ipairs(items) do
        for _, rule in ipairs(auto_color_rules) do
            local scope = rule.scope or "all"
            local scope_match = scope == "all" or (scope == "markers" and not item.isRegion) or (scope == "regions" and item.isRegion)
            if rule.enabled and rule.text ~= "" and scope_match then
                if string.find(string.lower(item.name), string.lower(rule.text), 1, true) then
                    if item.color ~= rule.color then
                        item.color = rule.color
                        if item.isRegion then
                            r.SetProjectMarker3(0, item.index, true, item.pos, item.rgnend, item.name, rule.color)
                        else
                            r.SetProjectMarker3(0, item.index, false, item.pos, 0, item.name, rule.color)
                        end
                        change_count = change_count + 1
                    end
                    break
                end
            end
        end
    end
    
    if change_count > 0 then
        r.UpdateTimeline()
        r.Undo_EndBlock("Apply Auto-Color Rules", -1)
    else
        r.Undo_EndBlock("Apply Auto-Color Rules", -1)
    end
end

local function update_item_name(item, new_name)
    item.name = new_name

    if item.visible then
        r.SetProjectMarker3(0, item.index, item.isRegion, item.pos, item.rgnend or 0, new_name, item.color)
        r.UpdateTimeline()
    end

    local key = item.index .. (item.isRegion and "R" or "M")
    item_names[key] = new_name
    save_visibility_to_project()

    if auto_apply_rules then
        apply_color_rules_to_project()
    end
end

local function get_next_available_index(is_region)
    local current_project_key = get_project_key()
    local max_index = 0
    local items = project_items[current_project_key] or {}    
    for _, item in ipairs(items) do
        if item.visible and item.isRegion == is_region and item.index > max_index then
            max_index = item.index
        end
    end
    return max_index + 1
end

local function toggle_marker_region(item, items)
    if item.isRegion then
        r.DeleteProjectMarker(0, item.index, true)
        local new_index = get_next_available_index(items, false)
        r.AddProjectMarker2(0, false, item.pos, 0, item.name, new_index, item.color)
        item.isRegion = false
        item.rgnend = nil
        item.index = new_index
    else
        r.DeleteProjectMarker(0, item.index, false)
        local rgnend = find_next_marker_position(item.pos)
        local new_index = get_next_available_index(items, true)
        r.AddProjectMarker2(0, true, item.pos, rgnend, item.name, new_index, item.color)
        item.isRegion = true
        item.rgnend = rgnend
        item.index = new_index
    end
    r.UpdateTimeline()
end

local function clear_item_name(item)
    item.name = ""
    item_names[item.index .. (item.isRegion and "R" or "M")] = ""
    local flags = 1  
    r.SetProjectMarker4(0, item.index, item.isRegion, item.pos, item.rgnend or 0, "", item.color, flags)
    r.UpdateTimeline()
end

local function delete_item(item)
    if item.visible then
        r.DeleteProjectMarker(0, item.index, item.isRegion)
        r.UpdateTimeline()
    end
    local project_key = get_project_key()
    for i, list_item in ipairs(project_items[project_key]) do
        if list_item.index == item.index and list_item.isRegion == item.isRegion then
            table.remove(project_items[project_key], i)
            break
        end
    end
    for i, inv_item in ipairs(invisible_items) do
        if inv_item.index == item.index and 
           inv_item.isRegion == item.isRegion and 
           inv_item.project_key == project_key then
            table.remove(invisible_items, i)
            break
        end
    end
    save_invisible_items()
    save_visibility_to_project()
end

local function update_all_items_visibility(visible, filter_type)
    local current_project_key = get_project_key()
    local items = project_items[current_project_key] or {}
    for _, item in ipairs(items) do
        if (filter_type == "markers" and not item.isRegion) or
           (filter_type == "regions" and item.isRegion) or
           filter_type == "all" then
            if item.visible ~= visible then
                set_item_visibility(item, visible)
            end
        end
    end
end

local function matches_search(item, search_text)
    if search_text == "" then return true end
    local lower_name = string.lower(item.name or "")
    local lower_search = string.lower(search_text)
    return string.find(lower_name, lower_search, 1, true) ~= nil
end

local function get_multiselect_key(item)
    return tostring(item.index) .. (item.isRegion and "R" or "M")
end

local function count_multi_selected(selection_table)
    local count = 0
    for _, v in pairs(selection_table) do
        if v then count = count + 1 end
    end
    return count
end

local function bulk_delete(selection_table, items)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local to_delete = {}
    for _, item in ipairs(items) do
        local key = get_multiselect_key(item)
        if selection_table[key] then
            table.insert(to_delete, item)
        end
    end
    for i = #to_delete, 1, -1 do
        delete_item(to_delete[i])
    end
    for k in pairs(selection_table) do selection_table[k] = nil end
    r.PreventUIRefresh(-1)
    r.UpdateTimeline()
    r.Undo_EndBlock("Bulk Delete Markers/Regions", -1)
end

local function bulk_set_visibility(selection_table, items, visible)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for _, item in ipairs(items) do
        local key = get_multiselect_key(item)
        if selection_table[key] and item.visible ~= visible then
            set_item_visibility(item, visible)
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateTimeline()
    r.Undo_EndBlock("Bulk Set Visibility", -1)
end

local function bulk_set_color(selection_table, items, color)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for _, item in ipairs(items) do
        local key = get_multiselect_key(item)
        if selection_table[key] then
            item.color = color
            if item.visible then
                r.SetProjectMarker3(0, item.index, item.isRegion, item.pos, item.rgnend or 0, item.name, color)
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.UpdateTimeline()
    r.Undo_EndBlock("Bulk Set Color", -1)
end

local bulk_color_marker = nil
local bulk_color_region = nil

local function draw_search_and_bulk_bar(ctx, search_var, selection_table, items, is_region)
    local sel_count = count_multi_selected(selection_table)
    local label = is_region and "##search_region" or "##search_marker"
    local hint = "Filter by name..."

    push_item_width(ctx, 150 * settings.scale_factor)
    local changed, new_val = ImGui.InputTextWithHint(ctx, label, hint, search_var)
    pop_item_width(ctx)
    if changed then
        if is_region then search_region = new_val else search_marker = new_val end
    end

    same_line(ctx)
    if ImGui.Button(ctx, "All##sel" .. label) then
        for _, item in ipairs(items) do
            if item.isRegion == is_region and matches_search(item, is_region and search_region or search_marker) then
                selection_table[get_multiselect_key(item)] = true
            end
        end
    end
    ShowTooltip("Select All (filtered)")
    same_line(ctx)
    if ImGui.Button(ctx, "None##sel" .. label) then
        for k in pairs(selection_table) do selection_table[k] = nil end
    end
    ShowTooltip("Deselect All")

    if sel_count > 0 then
        same_line(ctx)
        ImGui.Text(ctx, "(" .. sel_count .. ")")
        same_line(ctx)

        push_style_color(ctx, ImGui.Col_Button, 0xAA0000FF)
        if ImGui.Button(ctx, "Del##bulk" .. label) then
            bulk_delete(selection_table, items)
        end
        pop_style_color(ctx)
        ShowTooltip("Delete selected")

        same_line(ctx)
        if ImGui.Button(ctx, "Show##bulk" .. label) then
            bulk_set_visibility(selection_table, items, true)
        end
        ShowTooltip("Show selected")
        same_line(ctx)
        if ImGui.Button(ctx, "Hide##bulk" .. label) then
            bulk_set_visibility(selection_table, items, false)
        end
        ShowTooltip("Hide selected")

        same_line(ctx)
        local bulk_color_ref = is_region and bulk_color_region or bulk_color_marker
        local col_val = bulk_color_ref or 0xFFFFFF
        local retval, new_col = ImGui.ColorEdit3(ctx, "##bulkclr" .. label, col_val, ImGui.ColorEditFlags_NoInputs)
        if retval then
            if is_region then bulk_color_region = new_col else bulk_color_marker = new_col end
            local new_r = (new_col >> 16) & 0xFF
            local new_g = (new_col >> 8) & 0xFF
            local new_b = new_col & 0xFF
            local native_color = r.ColorToNative(new_r, new_g, new_b) | 0x1000000
            bulk_set_color(selection_table, items, native_color)
        end
        ShowTooltip("Color selected")
    end

    local lane_filter_ref = is_region and table_lane_filter_region or table_lane_filter_marker
    local lane_set = {}
    local lane_list = {}
    for _, item in ipairs(items) do
        if item.isRegion == is_region then
            local l = item.lane or 0
            if not lane_set[l] then
                lane_set[l] = true
                lane_list[#lane_list + 1] = l
            end
        end
    end
    table.sort(lane_list)

    if #lane_list > 1 then
        same_line(ctx)
        local lane_lbl = lane_filter_ref == "all" and "All Lanes" or ("Lane " .. lane_filter_ref)
        ImGui.SetNextItemWidth(ctx, 75 * settings.scale_factor)
        if ImGui.BeginCombo(ctx, "##lane_tbl" .. label, lane_lbl, ImGui.ComboFlags_NoArrowButton) then
            if ImGui.Selectable(ctx, "All Lanes", lane_filter_ref == "all") then
                if is_region then table_lane_filter_region = "all" else table_lane_filter_marker = "all" end
            end
            for _, l in ipairs(lane_list) do
                local ls = tostring(l)
                if ImGui.Selectable(ctx, "Lane " .. ls, lane_filter_ref == ls) then
                    if is_region then table_lane_filter_region = ls else table_lane_filter_marker = ls end
                end
            end
            ImGui.EndCombo(ctx)
        end
        ShowTooltip("Filter by ruler lane")
    end
end

local function draw_marker_table(ctx, items)
    draw_search_and_bulk_bar(ctx, search_marker, multi_selected_markers, items, false)

    local table_flags = ImGui.TableFlags_Borders | ImGui.TableFlags_SizingFixedFit
    if ImGui.BeginTable(ctx, "MarkersTable", 11, table_flags) then
        local col_flags_fixed = ImGui.TableColumnFlags_WidthFixed
        
        ImGui.TableSetupColumn(ctx, "##Sel", col_flags_fixed, 24 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "##Visible", col_flags_fixed, 24 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "ID", col_flags_fixed, 32 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Play", col_flags_fixed, 40 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Name", ImGui.TableColumnFlags_WidthStretch)
        ImGui.TableSetupColumn(ctx, "Time", col_flags_fixed, 130 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Color", col_flags_fixed, 40 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Convert", col_flags_fixed, 65 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Del", col_flags_fixed, 22 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Nav", col_flags_fixed, 22 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Ln", col_flags_fixed, 22 * settings.scale_factor)
        ImGui.TableHeadersRow(ctx)

        ImGui.TableSetColumnIndex(ctx, 1)
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local draw_list = ImGui.GetWindowDrawList(ctx)
        local text_width = ImGui.CalcTextSize(ctx, "Vis")
        local cell_width = 24 * settings.scale_factor
        local cell_height = ImGui.GetTextLineHeight(ctx)
        
        ImGui.DrawList_AddText(draw_list, x + (cell_width - text_width) / 2, y, cached_colors.text_color, "Vis")
        if ImGui.InvisibleButton(ctx, "##VisibleHeaderMarkers", cell_width, cell_height) then
            local all_markers_visible = true
            for _, item in ipairs(project_items[get_project_key()] or {}) do
                if not item.isRegion then
                    all_markers_visible = all_markers_visible and item.visible
                end
            end
            update_all_items_visibility(not all_markers_visible, "markers")
        end

        local last_drawn_lane_m = nil
        for i, item in ipairs(items) do
            if not item.isRegion and matches_search(item, search_marker)
               and (table_lane_filter_marker == "all" or tostring(item.lane or 0) == table_lane_filter_marker) then
                local item_lane = item.lane or 0
                if last_drawn_lane_m ~= nil and item_lane ~= last_drawn_lane_m then
                    ImGui.TableNextRow(ctx)
                    ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0, 0xFFFFFF15)
                    ImGui.TableSetColumnIndex(ctx, 2)
                    push_style_color(ctx, ImGui.Col_Text, 0xFFFFFF80)
                    ImGui.Text(ctx, "Lane " .. tostring(item_lane))
                    pop_style_color(ctx)
                end
                last_drawn_lane_m = item_lane

                local ms_key = get_multiselect_key(item)
                ImGui.TableNextRow(ctx)

                ImGui.TableSetColumnIndex(ctx, 0)
                local is_sel = multi_selected_markers[ms_key] or false
                local sel_changed, new_sel = ImGui.Checkbox(ctx, "##ms" .. i, is_sel)
                if sel_changed then multi_selected_markers[ms_key] = new_sel or nil end

                ImGui.TableSetColumnIndex(ctx, 1)
                local changed, new_visible = ImGui.Checkbox(ctx, "##visible" .. i, item.visible)
                if changed then
                    set_item_visibility(item, new_visible)
                end
                ImGui.TableSetColumnIndex(ctx, 2)
                display_colored_id(ctx, item, i, items)
                ImGui.TableSetColumnIndex(ctx, 3)
                local button_text = "Play"
                local button_color = cached_colors.accent_color
                if currently_playing_marker and currently_playing_marker.index == item.index then
                    if next_marker_to_play and next_marker_to_play.index == item.index then
                        button_color = ImGui.ColorConvertDouble4ToU32(1, 0.55, 0, 1)
                        button_text = "Next"
                    else
                        button_color = ImGui.ColorConvertDouble4ToU32(1, 0, 0, 1)
                        button_text = "Play"
                    end
                elseif next_marker_to_play and next_marker_to_play.index == item.index then
                    button_color = ImGui.ColorConvertDouble4ToU32(1, 0.55, 0, 1)
                    button_text = "Next"
                end
                push_style_color(ctx, ImGui.Col_Button, button_color)
                if ImGui.Button(ctx, button_text .. "##" .. i) then
                    if currently_playing_marker then
                        next_marker_to_play = item
                    else
                        play_marker(item)
                    end
                end
                if ImGui.IsItemClicked(ctx, 1) then
                    if currently_playing_marker and currently_playing_marker.index == item.index then
                        r.OnStopButton()
                        currently_playing_marker = nil
                        next_marker_to_play = nil
                        r.UpdateTimeline()
                    end
                end
                pop_style_color(ctx)

                ImGui.TableSetColumnIndex(ctx, 4)
                if ImGui.Button(ctx, "X##clear_name" .. i) then
                    clear_item_name(item)
                end
                ImGui.SameLine(ctx)

                local display_name = item.name ~= "" and item.name or ""
                if editing_name == i then
                    local changed, new_name = ImGui.InputText(ctx, "##name" .. i, item.name)
                    if changed then
                        update_item_name(item, new_name)
                    end
                    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
                        editing_name = nil
                    end
                else
                    if ImGui.Selectable(ctx, display_name, false) then
                        editing_name = i
                    end
                end
                ImGui.TableSetColumnIndex(ctx, 5)
                edit_time(ctx, item, false)

                ImGui.TableSetColumnIndex(ctx, 6)
                edit_color(item, i)

                ImGui.TableSetColumnIndex(ctx, 7)
                if ImGui.Button(ctx, "To Region##" .. i) then
                    toggle_marker_region(item, items)
                end

                ImGui.TableSetColumnIndex(ctx, 8)
                if ImGui.Button(ctx, "X##" .. i) then
                    delete_item(item)
                end

                ImGui.TableSetColumnIndex(ctx, 9)
                if ImGui.Button(ctx, ">##nav" .. i) then
                    r.SetEditCurPos(item.pos, true, false)
                    r.UpdateTimeline()
                end

                ImGui.TableSetColumnIndex(ctx, 10)
                ImGui.Text(ctx, tostring(item.lane or 0))
            end
        end
        ImGui.EndTable(ctx)
    end
end

local function play_region(region)
    if region and region.visible then
        r.SetEditCurPos(region.pos, true, false)
        r.GetSet_LoopTimeRange(true, false, region.pos, region.rgnend, false)
        r.OnPlayButton()
        currently_playing_region = region
        r.UpdateTimeline()
    end
end

local function duplicate_region_content(region, ripple)
    if not region or not region.isRegion then return end
    
    local cursor_pos = r.GetCursorPosition()
    local region_length = region.rgnend - region.pos
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local orig_start, orig_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    
    r.GetSet_LoopTimeRange(true, false, region.pos, region.rgnend, false)
    r.SetEditCurPos(cursor_pos, false, false)
    
    r.Main_OnCommand(40397, 0)
    
    if not ripple then
        r.GetSet_LoopTimeRange(true, false, cursor_pos + region_length, cursor_pos + region_length + region_length, false)
        r.Main_OnCommand(40201, 0)
    end
    
    r.GetSet_LoopTimeRange(true, false, orig_start, orig_end, false)
    
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    r.UpdateTimeline()
    r.Undo_EndBlock("Duplicate Region Content", -1)
end

local function handle_region_playback()
    if currently_playing_region then
        local play_state = r.GetPlayState()
        local play_position = r.GetPlayPosition()
        if play_state == 0 or (play_position >= (currently_playing_region.rgnend - 0.01) and 
           play_position > currently_playing_region.pos + 0.1) then
            currently_playing_region = nil
            if next_region_to_play then
                play_region(next_region_to_play)
                next_region_to_play = nil
            end
            r.UpdateTimeline()
        end
    end
end

local function draw_region_table(ctx, items)
    draw_search_and_bulk_bar(ctx, search_region, multi_selected_regions, items, true)

    local table_flags = ImGui.TableFlags_Borders | ImGui.TableFlags_SizingFixedFit
    if ImGui.BeginTable(ctx, "RegionsTable", 14, table_flags) then
        local col_flags_fixed = ImGui.TableColumnFlags_WidthFixed
        local col_flags_stretch = ImGui.TableColumnFlags_WidthStretch
        
        ImGui.TableSetupColumn(ctx, "##Sel", col_flags_fixed, 24 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "##Visible", col_flags_fixed, 24 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "ID", col_flags_fixed, 32 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Play", col_flags_fixed, 40 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Name", col_flags_stretch)
        ImGui.TableSetupColumn(ctx, "Start", col_flags_fixed, 130 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "End", col_flags_fixed, 130 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Color", col_flags_fixed, 40 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Zoom", col_flags_fixed, 48 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "D", col_flags_fixed, 22 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Convert", col_flags_fixed, 65 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Del", col_flags_fixed, 22 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Nav", col_flags_fixed, 22 * settings.scale_factor)
        ImGui.TableSetupColumn(ctx, "Ln", col_flags_fixed, 22 * settings.scale_factor)
        ImGui.TableHeadersRow(ctx)

        ImGui.TableSetColumnIndex(ctx, 1)
        local x, y = ImGui.GetCursorScreenPos(ctx)
        local draw_list = ImGui.GetWindowDrawList(ctx)
        local text_width = ImGui.CalcTextSize(ctx, "Vis")
        local cell_width = 24 * settings.scale_factor
        local cell_height = ImGui.GetTextLineHeight(ctx)
        
        ImGui.DrawList_AddText(draw_list, x + (cell_width - text_width) / 2, y, cached_colors.text_color, "Vis")
        if ImGui.InvisibleButton(ctx, "##VisibleHeaderRegions", cell_width, cell_height) then
            local all_regions_visible = true
            for _, item in ipairs(project_items[get_project_key()] or {}) do
                if item.isRegion then
                    all_regions_visible = all_regions_visible and item.visible
                end
            end
            update_all_items_visibility(not all_regions_visible, "regions")
        end

        local last_drawn_lane_r = nil
        for i, item in ipairs(items) do
            if item.isRegion and matches_search(item, search_region)
               and (table_lane_filter_region == "all" or tostring(item.lane or 0) == table_lane_filter_region) then
                local item_lane = item.lane or 0
                if last_drawn_lane_r ~= nil and item_lane ~= last_drawn_lane_r then
                    ImGui.TableNextRow(ctx)
                    ImGui.TableSetBgColor(ctx, ImGui.TableBgTarget_RowBg0, 0xFFFFFF15)
                    ImGui.TableSetColumnIndex(ctx, 2)
                    push_style_color(ctx, ImGui.Col_Text, 0xFFFFFF80)
                    ImGui.Text(ctx, "Lane " .. tostring(item_lane))
                    pop_style_color(ctx)
                end
                last_drawn_lane_r = item_lane

                local ms_key = get_multiselect_key(item)
                ImGui.TableNextRow(ctx)

                ImGui.TableSetColumnIndex(ctx, 0)
                local is_sel = multi_selected_regions[ms_key] or false
                local sel_changed, new_sel = ImGui.Checkbox(ctx, "##ms" .. i, is_sel)
                if sel_changed then multi_selected_regions[ms_key] = new_sel or nil end

                ImGui.TableSetColumnIndex(ctx, 1)
                local changed, new_visible = ImGui.Checkbox(ctx, "##visible" .. i, item.visible)
                if changed then
                    set_item_visibility(item, new_visible)
                end

                ImGui.TableSetColumnIndex(ctx, 2)
                display_colored_id(ctx, item, i, items)

                ImGui.TableSetColumnIndex(ctx, 3)
                local button_text = "Play"
                local button_color = cached_colors.accent_color

                if currently_playing_region and currently_playing_region.index == item.index then
                    if next_region_to_play and next_region_to_play.index == item.index then
                        button_color = ImGui.ColorConvertDouble4ToU32(1, 0.55, 0, 1)
                        button_text = "Next"
                    else
                        button_color = ImGui.ColorConvertDouble4ToU32(1, 0, 0, 1)
                        button_text = "Play"
                    end
                elseif next_region_to_play and next_region_to_play.index == item.index then
                    button_color = ImGui.ColorConvertDouble4ToU32(1, 0.55, 0, 1)
                    button_text = "Next"
                end
                push_style_color(ctx, ImGui.Col_Button, button_color)
                if ImGui.Button(ctx, button_text .. "##" .. i) then
                    if currently_playing_region then
                        next_region_to_play = item
                    else
                        play_region(item)
                    end
                end
                if ImGui.IsItemClicked(ctx, 1) then
                    if currently_playing_region and currently_playing_region.index == item.index then
                        r.OnStopButton()
                        currently_playing_region = nil
                        next_region_to_play = nil
                        r.UpdateTimeline()
                    end
                end
                pop_style_color(ctx)

                ImGui.TableSetColumnIndex(ctx, 4)
                if ImGui.Button(ctx, "X##clear_name" .. i) then
                    clear_item_name(item)
                end
                ImGui.SameLine(ctx)

                local display_name = item.name ~= "" and item.name or ""
                if editing_name == i then
                    local changed, new_name = ImGui.InputText(ctx, "##name" .. i, item.name)
                    if changed then
                        update_item_name(item, new_name)
                    end
                    if ImGui.IsItemDeactivatedAfterEdit(ctx) then
                        editing_name = nil
                    end
                else
                    if ImGui.Selectable(ctx, display_name, false) then
                        editing_name = i
                    end
                end

                ImGui.TableSetColumnIndex(ctx, 5)
                edit_time(ctx, item, false)

                ImGui.TableSetColumnIndex(ctx, 6)
                edit_time(ctx, item, true)

                ImGui.TableSetColumnIndex(ctx, 7)
                edit_color(item, i)

                ImGui.TableSetColumnIndex(ctx, 8)
                if ImGui.Button(ctx, "+##z_in" .. i) then
                    r.GetSet_LoopTimeRange(true, false, item.pos, item.rgnend, false)
                    r.Main_OnCommand(40031, 0)
                end
                ShowTooltip("Zoom to Region")
                ImGui.SameLine(ctx)
                if ImGui.Button(ctx, "-##z_out" .. i) then
                    r.Main_OnCommand(40295, 0)
                end
                ShowTooltip("Zoom to Project")

                ImGui.TableSetColumnIndex(ctx, 9)
                if ImGui.Button(ctx, "D##dup" .. i) then
                    duplicate_region_content(item, true)
                end
                ShowTooltip("Duplicate (ripple). Right-click for no ripple.")
                if ImGui.IsItemClicked(ctx, 1) then
                    duplicate_region_content(item, false)
                end

                ImGui.TableSetColumnIndex(ctx, 10)
                if ImGui.Button(ctx, "To Marker##" .. i) then
                    toggle_marker_region(item, items)
                end

                ImGui.TableSetColumnIndex(ctx, 11)
                if ImGui.Button(ctx, "X##" .. i) then
                    delete_item(item)
                end

                ImGui.TableSetColumnIndex(ctx, 12)
                if ImGui.Button(ctx, ">##nav" .. i) then
                    r.SetEditCurPos(item.pos, true, false)
                    r.GetSet_LoopTimeRange(true, false, item.pos, item.rgnend, false)
                    r.UpdateTimeline()
                end

                ImGui.TableSetColumnIndex(ctx, 13)
                ImGui.Text(ctx, tostring(item.lane or 0))
            end
        end
        ImGui.EndTable(ctx)
    end
end

local function calculate_available_height(ctx)
    local window_height = ImGui.GetWindowHeight(ctx)
    local cursor_pos_y = ImGui.GetCursorPosY(ctx)
    local bottom_section_height = 90 * settings.scale_factor
    return window_height - cursor_pos_y - bottom_section_height
end

local function create_custom_button(button_id)
    local window_width = ImGui.GetWindowWidth(ctx)
    local num_buttons_per_row = 4
    local padding = 6  -- Vaste padding zonder scaling
    local available_width = window_width - (padding * (num_buttons_per_row + 1))
    local button_width = available_width / num_buttons_per_row

    local stored_name = r.GetExtState(SCRIPT_NAME, "custom_button_" .. button_id .. "_name")
    local button_name = stored_name ~= "" and stored_name or ("Custom##btn" .. button_id)
    local stored_action = r.GetExtState(SCRIPT_NAME, "custom_button_" .. button_id .. "_action")

    if ImGui.Button(ctx, button_name, button_width) then
        if stored_action ~= "" then
            local command_id = r.NamedCommandLookup(stored_action)
            if command_id ~= 0 then
                r.Main_OnCommand(command_id, 0)
            end
        end
    end
    if ImGui.IsItemClicked(ctx, 1) then
        local retval, action_id = r.GetUserInputs("Assign Action", 1, "Command ID:", stored_action)
        if retval then
            r.SetExtState(SCRIPT_NAME, "custom_button_" .. button_id .. "_action", action_id, true)
        end
    end

    if ImGui.IsItemClicked(ctx, 0) and ImGui.IsKeyDown(ctx, ImGui.Mod_Alt) then
        local display_name = stored_name ~= "" and stored_name:gsub("##btn.*", "") or "CUSTOM BUTTON"
        local retval, new_name = r.GetUserInputs("Button Name", 1, "New Name:", display_name)
        if retval then
            r.SetExtState(SCRIPT_NAME, "custom_button_" .. button_id .. "_name", new_name .. "##btn" .. button_id, true)
        end
    end
end

local function add_marker_buttons(ctx)
    local button_width = 115 * settings.scale_factor    
    if ImGui.Button(ctx, "Marker@start sel items", button_width) then
        run_script("TK_marker at start items on the track.lua")
    end
    same_line(ctx)    
    if ImGui.Button(ctx, "Marker@mid sel items", button_width) then
        run_script("TK_marker at middle items on the track.lua")
    end
end

local function sync_autocolor_state()
    local marker_state = r.GetToggleCommandState(r.NamedCommandLookup("_S&MAUTOCOLOR_MKR_ENABLE"))
    local region_state = r.GetToggleCommandState(r.NamedCommandLookup("_S&MAUTOCOLOR_RGN_ENABLE"))
    local desired_state = (marker_state == 1 or region_state == 1) and 1 or 0
    if marker_state ~= desired_state then
        r.Main_OnCommand(r.NamedCommandLookup("_S&MAUTOCOLOR_MKR_ENABLE"), 0)
    end
    if region_state ~= desired_state then
        r.Main_OnCommand(r.NamedCommandLookup("_S&MAUTOCOLOR_RGN_ENABLE"), 0)
    end   
    return desired_state == 1
end

local function move_markers_and_regions_to_cursor()
    local cursor_pos = reaper.GetCursorPosition()
    local current_project_key = get_project_key()
    local all_items = project_items[current_project_key] or {}
    
    if #all_items > 0 then
        local offset = cursor_pos - all_items[1].pos
        
        r.Undo_BeginBlock()
        
        for _, item in ipairs(all_items) do
            local new_pos = item.pos + offset
            if item.isRegion then
                local new_end = item.rgnend + offset
                if item.visible then
                    r.SetProjectMarker(item.index, true, new_pos, new_end, item.name, item.color)
                else
                    item.pos = new_pos
                    item.rgnend = new_end
                end
            else
                if item.visible then
                    r.SetProjectMarker(item.index, false, new_pos, 0, item.name, item.color)
                else
                    item.pos = new_pos
                end
            end
        end
        
        r.Undo_EndBlock("Move all markers and regions to cursor", -1)
        r.UpdateTimeline()
        
        save_invisible_items()
        save_visibility_to_project()
    end
end


local function run_script(script_name)
    local script_path = r.GetResourcePath() .. "/Scripts/TK Scripts/TK SMART/" .. script_name
    if r.file_exists(script_path) then
        dofile(script_path)
    else
        r.ShowMessageBox("Script not found: " .. script_name, "Error", 0)
    end
end

local function draw_color_rules_tab(ctx)
    local available_height = calculate_available_height(ctx)
    if ImGui.BeginChild(ctx, "RulesChild", 0, available_height) then
        
        if ImGui.Button(ctx, "Add New Rule") then
            table.insert(auto_color_rules, {
                text = "New Rule", 
                color = 0xFFFFFFFF,
                enabled = true,
                scope = "all"
            })
            save_color_rules()
        end
        
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "APPLY NOW") then
            apply_color_rules_to_project()
        end
        
        ImGui.SameLine(ctx)
        local changed, new_val = ImGui.Checkbox(ctx, "Auto-Apply on Rename", auto_apply_rules)
        if changed then
            auto_apply_rules = new_val
            save_color_rules()
        end
        ShowTooltip("Automatically color items when you rename them in this script")

        ImGui.Separator(ctx)

        local table_flags = ImGui.TableFlags_Borders | ImGui.TableFlags_RowBg
        local scope_labels = { "All", "Markers", "Regions" }
        local scope_values = { "all", "markers", "regions" }
        if ImGui.BeginTable(ctx, "RulesTable", 5, table_flags) then
            ImGui.TableSetupColumn(ctx, "On", ImGui.TableColumnFlags_WidthFixed, 30 * settings.scale_factor)
            ImGui.TableSetupColumn(ctx, "Scope", ImGui.TableColumnFlags_WidthFixed, 75 * settings.scale_factor)
            ImGui.TableSetupColumn(ctx, "If Name Contains...", ImGui.TableColumnFlags_WidthStretch)
            ImGui.TableSetupColumn(ctx, "Color", ImGui.TableColumnFlags_WidthFixed, 50 * settings.scale_factor)
            ImGui.TableSetupColumn(ctx, "Del", ImGui.TableColumnFlags_WidthFixed, 30 * settings.scale_factor)
            ImGui.TableHeadersRow(ctx)

            local to_remove = nil

            for i, rule in ipairs(auto_color_rules) do
                ImGui.PushID(ctx, i)
                ImGui.TableNextRow(ctx)
                
                ImGui.TableSetColumnIndex(ctx, 0)
                local en_changed, new_en = ImGui.Checkbox(ctx, "##en", rule.enabled)
                if en_changed then 
                    rule.enabled = new_en 
                    save_color_rules()
                end

                ImGui.TableSetColumnIndex(ctx, 1)
                local cur_scope = rule.scope or "all"
                local cur_idx = 0
                for si, sv in ipairs(scope_values) do
                    if sv == cur_scope then cur_idx = si - 1 break end
                end
                ImGui.SetNextItemWidth(ctx, -1)
                if ImGui.BeginCombo(ctx, "##scope", scope_labels[cur_idx + 1]) then
                    for si, sl in ipairs(scope_labels) do
                        local is_sel = (cur_idx == si - 1)
                        if ImGui.Selectable(ctx, sl, is_sel) then
                            rule.scope = scope_values[si]
                            save_color_rules()
                        end
                    end
                    ImGui.EndCombo(ctx)
                end

                ImGui.TableSetColumnIndex(ctx, 2)
                ImGui.SetNextItemWidth(ctx, -1)
                local txt_changed, new_txt = ImGui.InputText(ctx, "##txt", rule.text)
                if txt_changed then 
                    rule.text = new_txt 
                    save_color_rules()
                end

                ImGui.TableSetColumnIndex(ctx, 3)
                local r_val, g_val, b_val = r.ColorFromNative(rule.color)
                local col_rgb = (r_val << 16) | (g_val << 8) | b_val
                local retval, new_col_rgb = ImGui.ColorEdit3(ctx, "##clr" .. i, col_rgb, ImGui.ColorEditFlags_NoInputs)
                if retval then
                    local new_r = (new_col_rgb >> 16) & 0xFF
                    local new_g = (new_col_rgb >> 8) & 0xFF
                    local new_b = new_col_rgb & 0xFF
                    rule.color = r.ColorToNative(new_r, new_g, new_b) | 0x1000000
                    save_color_rules()
                end

                ImGui.TableSetColumnIndex(ctx, 4)
                if ImGui.Button(ctx, "X") then
                    to_remove = i
                end

                ImGui.PopID(ctx)
            end
            ImGui.EndTable(ctx)

            if to_remove then
                table.remove(auto_color_rules, to_remove)
                save_color_rules()
            end
        end
        
        ImGui.EndChild(ctx)
    end
end

local function draw_actions_tab(ctx)
    if ImGui.BeginChild(ctx, "ActionsChild", 0, calculate_available_height(ctx)) then
        ImGui.BeginGroup(ctx)
        
        local window_width = ImGui.GetWindowWidth(ctx)
        local num_buttons_per_row = 4
        local padding = 6
        local available_width = window_width - (padding * (num_buttons_per_row + 1))
        local button_width = available_width / num_buttons_per_row

        push_style_color(ctx, ImGui.Col_Button, cached_colors.accent_color)
        if ImGui.Button(ctx, "Action Browser", button_width) then
            if show_action_browser then
                SHOW_ACTION_BROWSER = false
                show_action_browser = false
            else
                SHOW_ACTION_BROWSER = true
                local action_browser_path = r.GetResourcePath() .. "/Scripts/TK Scripts/TK SMART/TK_Action_Browser.lua"
                dofile(action_browser_path)
                show_action_browser = true
            end
        end
        pop_style_color(ctx)
        same_line(ctx)

        local smart_marker_state = r.GetToggleCommandState(r.NamedCommandLookup("_SWSMA_TOGGLE"))
        local button_text = smart_marker_state == 1 and "Smart Marker: ON" or "Smart Marker: OFF"
        local button_color = smart_marker_state == 1 and 0x00AA00FF or 0xAA0000FF

        push_style_color(ctx, ImGui.Col_Button, button_color)
        if ImGui.Button(ctx, button_text, button_width) then
            r.Main_OnCommand(r.NamedCommandLookup("_SWSMA_TOGGLE"), 0)
        end
        pop_style_color(ctx)
        same_line(ctx)

        if ImGui.Button(ctx, "Autocolor Window", button_width) then
            r.Main_OnCommand(r.NamedCommandLookup("_SWSAUTOCOLOR_OPEN"), 0)
        end
        same_line(ctx)
        
        local autocolor_enabled = sync_autocolor_state()
        local ac_button_text = autocolor_enabled and "Autocolor: ON" or "Autocolor: OFF"
        local ac_button_color = autocolor_enabled and 0x00AA00FF or 0xAA0000FF
        
        push_style_color(ctx, ImGui.Col_Button, ac_button_color)
        if ImGui.Button(ctx, ac_button_text, button_width) then
            r.Main_OnCommand(r.NamedCommandLookup("_S&MAUTOCOLOR_MKR_ENABLE"), 0)
            r.Main_OnCommand(r.NamedCommandLookup("_S&MAUTOCOLOR_RGN_ENABLE"), 0)
        end
        pop_style_color(ctx)

        if ImGui.Button(ctx, "Learn Browser", button_width) then
            if show_weblink_browser then
                SHOW_WEBLINK_BROWSER = false
                show_weblink_browser = false
            else
                SHOW_WEBLINK_BROWSER = true
                local weblink_browser_path = r.GetResourcePath() .. "/Scripts/TK Scripts/TK SMART/TK_Learn_Browser(MR).lua"
                dofile(weblink_browser_path)
                show_weblink_browser = true
            end
        end
        same_line(ctx)
        if ImGui.Button(ctx, "Marker@start sel items", button_width) then
            run_script("TK_marker at start items on the track.lua")
        end
        same_line(ctx)
        
        if ImGui.Button(ctx, "Marker@mid sel items", button_width) then
            run_script("TK_marker at middle items on the track.lua")
        end
        same_line(ctx)
        
        if ImGui.Button(ctx, "Move All to cursor", button_width) then
            move_markers_and_regions_to_cursor()
        end
        local ddp_action_id = r.NamedCommandLookup("__DDP_MARKER_EDITOR")
        if ddp_action_id ~= 0 then
            if ImGui.Button(ctx, "DDP Manager", button_width) then
                r.Main_OnCommand(ddp_action_id, 0)
            end
        else
            ImGui.Text(ctx, "DDP Marker Editor not present.")
            if ImGui.Button(ctx, "Download DDP Ext", button_width) then
                r.CF_ShellExecute("https://stash.reaper.fm/34295/reaper_ddp_edit_R1.zip")
            end
        end
        sepa_rator(ctx)
      
        for i = 1, 4 do
            create_custom_button(i)
            if i < 4 then same_line(ctx) end
        end

        for i = 5, 8 do
            create_custom_button(i)
            if i < 8 then same_line(ctx) end
        end
        ImGui.EndGroup(ctx)
        ImGui.EndChild(ctx)
    end
end

local function execute_stored_action(action_id)
    if action_id ~= "" then
        local command_id = r.NamedCommandLookup(action_id)
        if command_id ~= 0 then
            r.Main_OnCommand(command_id, 0)
        end
    end
end

local function handle_button_context_menu(ctx, button_id, current_name, current_action)
    if ImGui.IsItemClicked(ctx, 1) then
        local retval, action_id = r.GetUserInputs("Actie Toewijzen", 1, "Command ID:", current_action)
        if retval then
            r.SetExtState(SCRIPT_NAME, "custom_button_" .. button_id .. "_action", action_id, true)
        end
    end
    if ImGui.IsItemClicked(ctx, 0) and ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) then
        local display_name = current_name ~= "" and current_name:gsub("##btn.*", "") or "CUSTOM BUTTON"
        local retval, new_name = r.GetUserInputs("Button Name", 1, "New Name:", display_name)
        if retval then
            r.SetExtState(SCRIPT_NAME, "custom_button_" .. button_id .. "_name", new_name .. "##btn" .. button_id, true)
        end
    end
end



local function toggle_learn_browser()
    if show_weblink_browser then
        SHOW_WEBLINK_BROWSER = false
        show_weblink_browser = false
    else
        SHOW_WEBLINK_BROWSER = true
        local weblink_browser_path = r.GetResourcePath() .. "/Scripts/TK Scripts/TK SMART/TK_Learn_Browser(MR).lua"
        dofile(weblink_browser_path)
        show_weblink_browser = true
    end
end


local function DrawRegionManagerCheckbox(ctx)
    local changed, new_state = ImGui.Checkbox(ctx, "R/M Manager", show_region_manager)
    
    if changed then
        r.Main_OnCommand(REGION_MANAGER_COMMAND_ID, 0)
        -- Update state na actie
        show_region_manager = r.JS_Window_Find("Region/Marker Manager", true) ~= nil
    end
end

local function DrawShowRgnPlaylistCheckbox(ctx)
    local changed, new_state = ImGui.Checkbox(ctx, "Region Playlist", show_region_playlist)
    
    if changed then
        r.Main_OnCommand(PLAYLIST_COMMAND_ID, 0)
        -- Update state na actie
        show_region_playlist = r.GetToggleCommandStateEx(0, PLAYLIST_COMMAND_ID) == 1
    end
end

local function DrawRenderMatrixCheckbox(ctx)
    local changed, new_state = ImGui.Checkbox(ctx, "Region Matrix", show_region_matrix)
    
    if changed then
        r.Main_OnCommand(REGION_MATRIX_COMMAND_ID, 0)
        -- Update state na actie
        show_region_matrix = r.JS_Window_Find("Region Render Matrix", true) ~= nil
    end
end


local function get_region_under_play_cursor(lane_filter)
    local play_pos = r.GetPlayPosition()
    local num_markers = r.CountProjectMarkers(0)
    local has_lane_api = r.GetRegionOrMarker ~= nil and r.GetRegionOrMarkerInfo_Value ~= nil
    for i = 0, num_markers - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color = r.EnumProjectMarkers3(0, i)
        if isrgn and pos <= play_pos and rgnend >= play_pos then
            local lane = 0
            if has_lane_api then
                local marker = r.GetRegionOrMarker(0, i, "")
                if marker then
                    lane = r.GetRegionOrMarkerInfo_Value(0, marker, "I_LANENUMBER") or 0
                end
            end
            if lane_filter and lane_filter ~= "all" and tostring(lane) ~= lane_filter then
            else
                return {
                    start = pos,
                    ending = rgnend,
                    name = name,
                    color = color,
                    index = markrgnindexnumber,
                    lane = lane
                }
            end
        end
    end
    return nil
end
local function lighten_color(r, g, b, factor)
    return math.min(r + (255 - r) * factor, 255),
           math.min(g + (255 - g) * factor, 255),
           math.min(b + (255 - b) * factor, 255)
end

local function format_time(seconds)
    local minutes = math.floor(seconds / 60)
    local remaining_seconds = seconds % 60
    return string.format("%d:%05.2f", minutes, remaining_seconds)
end

local function draw_region_progress(ctx, region, window_width)
    if not region then return end

    local play_pos = r.GetPlayPosition()
    local progress = (play_pos - region.start) / (region.ending - region.start)
    progress = math.max(0, math.min(1, progress))

    local bar_width = window_width - 16 
    local bar_height = 14 * settings.scale_factor
    local pos_x, pos_y = ImGui.GetCursorScreenPos(ctx)

    local draw_list = ImGui.GetWindowDrawList(ctx)
    local red, g, b = r.ColorFromNative(region.color)
    local region_color = ImGui.ColorConvertDouble4ToU32(red/255, g/255, b/255, 1)
    
    local lr, lg, lb = lighten_color(red, g, b, 0.5)
    local light_region_color = ImGui.ColorConvertDouble4ToU32(lr/255, lg/255, lb/255, 1)

    ImGui.DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + bar_width, pos_y + bar_height, region_color)
    ImGui.DrawList_AddRectFilled(draw_list, pos_x, pos_y, pos_x + bar_width * progress, pos_y + bar_height, light_region_color)

    local elapsed_time = play_pos - region.start
    local remaining_time = region.ending - play_pos
    local total_time = region.ending - region.start
    local time_text = string.format("%d: %s - %s / %s / %s", 
        region.index or 0, 
        region.name or "", 
        format_time(elapsed_time), 
        format_time(remaining_time), 
        format_time(total_time)
    )
    
    local text_width = ImGui.CalcTextSize(ctx, time_text)
    local text_x = pos_x + (bar_width - text_width) / 2
    
    ImGui.DrawList_AddText(draw_list, text_x, pos_y + 1, 0x000000FF, time_text)
    ImGui.Dummy(ctx, bar_width, bar_height)
end


local function draw_bottom_section(ctx)
    local window_width = get_window_width(ctx)
    local window_height = get_window_height(ctx)
   
    local window_pos_x, window_pos_y = ImGui.GetWindowPos(ctx)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local line_color = 0x4D4D4DFF
    local line_thickness = 1 * settings.scale_factor

    -- Teken de lijn
    ImGui.DrawList_AddLine(
        draw_list,
        window_pos_x,
        window_pos_y + ImGui.GetCursorPosY(ctx),
        window_pos_x + window_width,
        window_pos_y + ImGui.GetCursorPosY(ctx),
        line_color,
        line_thickness
    )

    local button_width = 70 * settings.scale_factor
    ImGui.Dummy(ctx, 0, 3)
    if ImGui.Button(ctx, "GRIDLINES", button_width) then
        r.Main_OnCommand(COMMANDS.GRIDLINES, 0)
    end
    same_line(ctx)
    if ImGui.Button(ctx, "MANAGER", button_width) then
        r.Main_OnCommand(COMMANDS.MANAGER, 0)
    end
    same_line(ctx)
    if ImGui.Button(ctx, "PLAYLIST", button_width) then
        r.Main_OnCommand(COMMANDS.PLAYLIST, 0)
    end
    same_line(ctx)
    if ImGui.Button(ctx, "MATRIX", button_width) then
        r.Main_OnCommand(COMMANDS.MATRIX, 0)
    end
    same_line(ctx)
    if ImGui.Button(ctx, "RULER", button_width) then
        r.Main_OnCommand(COMMANDS.RULER_LANES, 0)
    end
    same_line(ctx)

    local del_w = 70 * settings.scale_factor
    ImGui.SetCursorPosX(ctx, window_width - (del_w * 2 + 12) * settings.scale_factor / settings.scale_factor)
    push_style_color(ctx, ImGui.Col_Button, 0x8B0000CC)
    push_style_color(ctx, ImGui.Col_ButtonHovered, 0xCC0000FF)
    push_style_color(ctx, ImGui.Col_ButtonActive, 0xFF0000FF)
    if ImGui.Button(ctx, "DEL MKR", del_w) then
        r.Main_OnCommand(r.NamedCommandLookup("_SWSMARKERLIST9"), 0)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Delete all markers") end
    same_line(ctx)
    if ImGui.Button(ctx, "DEL RGN", del_w) then
        r.Main_OnCommand(r.NamedCommandLookup("_SWSMARKERLIST10"), 0)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Delete all regions") end
    pop_style_color(ctx, 3)

    ImGui.Dummy(ctx, 0, 2)
    ImGui.DrawList_AddLine(draw_list, window_pos_x, window_pos_y + ImGui.GetCursorPosY(ctx), window_pos_x + window_width, window_pos_y + ImGui.GetCursorPosY(ctx), line_color, line_thickness)
    ImGui.Dummy(ctx, 0, 2)

    local current_project_key = get_project_key()
    local all_items = project_items[current_project_key] or {}
    local m_vis, m_hid, r_vis, r_hid = 0, 0, 0, 0
    for _, itm in ipairs(all_items) do
        if itm.isRegion then
            if itm.visible then r_vis = r_vis + 1 else r_hid = r_hid + 1 end
        else
            if itm.visible then m_vis = m_vis + 1 else m_hid = m_hid + 1 end
        end
    end
    
    local cursor_pos = r.GetCursorPosition()
    local cursor_str = format_time_and_mbt(cursor_pos)
    local proj_len = r.GetProjectLength(0)
    local proj_str = format_time_and_mbt(proj_len)
    
    local cur_region = get_region_under_play_cursor(progress_lane_filter)
    local region_name = cur_region and (cur_region.index .. ": " .. (cur_region.name or "")) or "-"
    
    push_style_color(ctx, ImGui.Col_Text, 0xAAAAAAFF)
    ImGui.Text(ctx, string.format("M: %d/%d  R: %d/%d  |  Cursor: %s  |  Len: %s  |  Rgn: %s", m_vis, m_vis + m_hid, r_vis, r_vis + r_hid, cursor_str, proj_str, region_name))
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Markers visible/total  |  Regions visible/total  |  Edit cursor  |  Project length  |  Current region") end
    pop_style_color(ctx, 1)

    local tb_w = 24 * settings.scale_factor
    local tb_w_wide = 30 * settings.scale_factor
    local tb_h = ImGui.GetTextLineHeightWithSpacing(ctx)
    local tb_total = tb_w_wide * 2 + tb_w * 2 + 12 * settings.scale_factor
    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, window_width - tb_total - 16 * settings.scale_factor)
    
    local play_state = r.GetPlayState()
    local is_playing = (play_state & 1 == 1) or (play_state & 4 == 4)
    local icon_col = 0xCCCCCCFF
    local icon_play = 0x66FF66FF
    local s = settings.scale_factor
    local dl = ImGui.GetWindowDrawList(ctx)
    local pad = 5 * s
    
    local bx, by = ImGui.GetCursorScreenPos(ctx)
    if ImGui.Button(ctx, "##tb_start", tb_w_wide, tb_h) then
        r.Main_OnCommand(40042, 0)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Go to start of project") end
    local cx, cy = bx + tb_w_wide / 2, by + tb_h / 2
    local hs = (tb_h / 2) - pad
    ImGui.DrawList_AddLine(dl, cx - hs * 0.6, cy - hs, cx - hs * 0.6, cy + hs, icon_col, 2 * s)
    ImGui.DrawList_AddTriangleFilled(dl, cx + hs * 0.4, cy - hs, cx + hs * 0.4, cy + hs, cx - hs * 0.4, cy, icon_col)
    ImGui.SameLine(ctx)
    
    bx, by = ImGui.GetCursorScreenPos(ctx)
    if ImGui.Button(ctx, "##tb_stop", tb_w, tb_h) then
        r.Main_OnCommand(1016, 0)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Stop") end
    cx, cy = bx + tb_w / 2, by + tb_h / 2
    ImGui.DrawList_AddRectFilled(dl, cx - hs * 0.75, cy - hs * 0.75, cx + hs * 0.75, cy + hs * 0.75, icon_col)
    ImGui.SameLine(ctx)
    
    bx, by = ImGui.GetCursorScreenPos(ctx)
    if ImGui.Button(ctx, "##tb_play", tb_w, tb_h) then
        r.Main_OnCommand(40073, 0)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, is_playing and "Pause" or "Play") end
    cx, cy = bx + tb_w / 2, by + tb_h / 2
    if is_playing then
        local pw = 2 * s
        local gap = 2 * s
        ImGui.DrawList_AddRectFilled(dl, cx - gap - pw, cy - hs * 0.7, cx - gap, cy + hs * 0.7, icon_play)
        ImGui.DrawList_AddRectFilled(dl, cx + gap, cy - hs * 0.7, cx + gap + pw, cy + hs * 0.7, icon_play)
    else
        ImGui.DrawList_AddTriangleFilled(dl, cx - hs * 0.5, cy - hs, cx - hs * 0.5, cy + hs, cx + hs * 0.7, cy, icon_col)
    end
    ImGui.SameLine(ctx)
    
    bx, by = ImGui.GetCursorScreenPos(ctx)
    if ImGui.Button(ctx, "##tb_end", tb_w_wide, tb_h) then
        r.Main_OnCommand(40043, 0)
    end
    if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Go to end of project") end
    cx, cy = bx + tb_w_wide / 2, by + tb_h / 2
    ImGui.DrawList_AddTriangleFilled(dl, cx - hs * 0.4, cy - hs, cx - hs * 0.4, cy + hs, cx + hs * 0.4, cy, icon_col)
    ImGui.DrawList_AddLine(dl, cx + hs * 0.6, cy - hs, cx + hs * 0.6, cy + hs, icon_col, 2 * s)

    ImGui.Dummy(ctx, 0, 2)

    local current_project_key_p = get_project_key()
    local all_items_p = project_items[current_project_key_p] or {}
    local progress_lanes = {}
    for _, itm in ipairs(all_items_p) do
        if itm.isRegion then
            local ln = tostring(itm.lane or 0)
            if not progress_lanes[ln] then
                progress_lanes[ln] = true
            end
        end
    end
    local progress_lane_list = {}
    for ln, _ in pairs(progress_lanes) do
        table.insert(progress_lane_list, tonumber(ln))
    end
    table.sort(progress_lane_list)

    if #progress_lane_list > 1 then
        local combo_w = 52 * settings.scale_factor
        ImGui.SetNextItemWidth(ctx, combo_w)
        local preview = progress_lane_filter == "all" and "All" or ("Ln " .. progress_lane_filter)
        if ImGui.BeginCombo(ctx, "##progress_lane", preview, ImGui.ComboFlags_NoArrowButton) then
            if ImGui.Selectable(ctx, "All", progress_lane_filter == "all") then
                progress_lane_filter = "all"
            end
            for _, ln in ipairs(progress_lane_list) do
                local ls = tostring(ln)
                if ImGui.Selectable(ctx, "Ln " .. ls, progress_lane_filter == ls) then
                    progress_lane_filter = ls
                end
            end
            ImGui.EndCombo(ctx)
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Progress lane filter") end
        same_line(ctx)
        local current_region = get_region_under_play_cursor(progress_lane_filter)
        local remaining_w = window_width - ImGui.GetCursorPosX(ctx) - 8
        draw_region_progress(ctx, current_region, remaining_w)
    else
        local current_region = get_region_under_play_cursor(progress_lane_filter)
        draw_region_progress(ctx, current_region, window_width)
    end
    ImGui.Dummy(ctx, 0, 2)
end

local function get_directory_hash(path)
    local hash = 0
    local i = 0
    local file = r.EnumerateFiles(path, i)
    
    while file do
        local full_path = path .. "/" .. file
        -- Gebruik alleen file_exists voor de hash
        if r.file_exists(full_path) then
            hash = hash + 1
        end
        i = i + 1
        file = r.EnumerateFiles(path, i)
    end
    
    return hash
end


local function update_file_cache()
    local current_time = r.time_precise()
    
    if current_time - CACHE_CONFIG.FILES.last_update < CACHE_CONFIG.FILES.interval then
        return cached_files
    end

    local project_hash = get_directory_hash(project_path)
    local global_hash = get_directory_hash(global_path)
    
    if project_hash ~= cached_files.project_hash then
        cached_files.project = {}
        local i = 0
        local file = r.EnumerateFiles(project_path, i)
        while file do
            if file:match("%.json$") then
                local display_name = file:gsub("%.json$", "")
                table.insert(cached_files.project, {
                    name = display_name,
                    path = project_path .. "/" .. file
                })
            end
            i = i + 1
            file = r.EnumerateFiles(project_path, i)
        end
        cached_files.project_hash = project_hash
    end

    if global_hash ~= cached_files.global_hash then
        cached_files.global = {}
        local i = 0
        local file = r.EnumerateFiles(global_path, i)
        while file do
            if file:match("%.json$") then
                local display_name = file:gsub("%.json$", "")
                table.insert(cached_files.global, {
                    name = display_name,
                    path = global_path .. "/" .. file
                })
            end
            i = i + 1
            file = r.EnumerateFiles(global_path, i)
        end
        cached_files.global_hash = global_hash
    end

    CACHE_CONFIG.FILES.last_update = current_time
    return cached_files
end

local function get_preset_files()
    local files = update_file_cache()
    return {
        project = files.project,
        global = files.global
    }
end

local function get_filename_for_set(action)
    local retval, user_input = r.GetUserInputs(action .. " Marker/Region Set", 1, "Filename:", "")
    if retval and user_input ~= "" then
        local filename = user_input
        if not filename:match("%.json$") then
            filename = filename .. ".json"
        end
        if save_preset_globally then
            return global_path .. filename 
        else
            return project_path .. "/" .. filename
        end
    end
    return nil
end

local function load_marker_region_set(filepath)
    local file = io.open(filepath, "r")
    if file then
        local content = file:read("*all")
        file:close()
        local success, decoded = pcall(json.decode, content)
        if success then
            r.Undo_BeginBlock()
            
            local current_project_key = get_project_key()
            local items_to_delete = {}
            for _, item in ipairs(project_items[current_project_key] or {}) do
                table.insert(items_to_delete, item)
            end
            for _, item in ipairs(items_to_delete) do
                delete_item(item)
            end

            project_items[current_project_key] = {}
            invisible_items = {}
            
            if decoded.markers then
                for _, marker in ipairs(decoded.markers) do
                    local new_marker = {
                        name = marker.name,
                        pos = marker.pos,
                        visible = marker.visible,
                        color = marker.color,
                        index = marker.index,
                        isRegion = false,
                        project_key = current_project_key
                    }
                    if marker.visible then
                        r.AddProjectMarker2(0, false, marker.pos, 0, marker.name, marker.index, marker.color)
                    else
                        table.insert(invisible_items, new_marker)
                    end
                    table.insert(project_items[current_project_key], new_marker)
                end
            end
           
            if decoded.regions then
                for _, region in ipairs(decoded.regions) do
                    local endPos = region.endPos or region.pos
                    local new_region = {
                        name = region.name,
                        pos = region.pos,
                        rgnend = endPos,
                        visible = region.visible,
                        color = region.color,
                        index = region.index,
                        isRegion = true,
                        project_key = current_project_key
                    }
                    if region.visible then
                        r.AddProjectMarker2(0, true, region.pos, endPos, region.name, region.index, region.color)
                    else
                        table.insert(invisible_items, new_region)
                    end
                    table.insert(project_items[current_project_key], new_region)
                end
            end   
            r.UpdateTimeline()
            save_invisible_items()
            save_visibility_to_project()
            r.Undo_EndBlock("Load Marker/Region Set", -1)
        end
    end
end

local function save_marker_region_set()
    local filename = get_filename_for_set("Save")
    if filename then
        local prefix = save_preset_globally and "g_" or "p_"
        local full_path = filename:gsub("([^\\/]+)$", prefix .. "%1")

        local data = {markers = {}, regions = {}}
        local current_project_key = get_project_key()
        local items = project_items[current_project_key] or {}
        
        for _, item in ipairs(items) do
            local entry = {
                name = item.name,
                pos = item.pos,
                visible = item.visible,
                color = item.color,
                index = item.index
            }
            
            if item.isRegion then
                entry.endPos = item.rgnend
                table.insert(data.regions, entry)
            else
                table.insert(data.markers, entry)
            end
        end

        if #data.markers > 0 or #data.regions > 0 then
            local file, err = io.open(full_path, "w")
            if file then
                file:write(json.encode(data))
                file:close()
                r.ShowConsoleMsg("Preset saved successfully.\n")
            else
                r.ShowConsoleMsg("Error opening file for writing: " .. tostring(err) .. "\n")
            end
        else
            r.ShowConsoleMsg("No items to Save.\n")
        end
    end
end

local function handle_preset_item(ctx, preset, index, category, selected_preset)
    local is_selected = (selected_preset.category == category and selected_preset.index == index)
    if ImGui.Selectable(ctx, preset.name, is_selected) then
        if ImGui.IsKeyDown(ctx, ImGui.Mod_Alt) then
            table.remove(presets[category], index)
            os.remove(preset.path)
            selected_preset = {category = nil, index = nil}
        else
            selected_preset = {category = category, index = index}
            load_marker_region_set(preset.path)
        end
    end
    if is_selected then
        ImGui.SetItemDefaultFocus(ctx)
    end
end

local function draw_preset_section(ctx)
    local window_width = ImGui.GetWindowWidth(ctx)
    local num_buttons_per_row = 8
    local padding = 6
    local available_width = window_width - (padding * (num_buttons_per_row + 1))
    local button_width = available_width / num_buttons_per_row
    
    if ImGui.Button(ctx, "Save Preset", button_width) then
        save_marker_region_set()
    end
    
    same_line(ctx)
    ImGui.SetNextItemWidth(ctx, button_width +20)

    local presets = get_preset_files()
    local selected_preset = {category = nil, index = nil}
    
    if ImGui.BeginCombo(ctx, "##Presets", selected_preset.index and 
        (selected_preset.category .. ": " .. presets[selected_preset.category][selected_preset.index].name) or "Select preset") then
        
        if #presets.project > 0 then
            ImGui.TextDisabled(ctx, "Project Presets:")
            for i, preset in ipairs(presets.project) do
                handle_preset_item(ctx, preset, i, "project", selected_preset)
            end
        end

        if #presets.global > 0 then
            ImGui.TextDisabled(ctx, "Global Presets:")
            for i, preset in ipairs(presets.global) do
                handle_preset_item(ctx, preset, i, "global", selected_preset)
            end
        end    
        ImGui.EndCombo(ctx)
    end
    same_line(ctx)
    local button_text = save_preset_globally and "Global: ON" or "Global: OFF"
    if ImGui.Button(ctx, button_text, button_width) then
        save_preset_globally = not save_preset_globally
        r.SetExtState(SCRIPT_NAME, "save_preset_globally", tostring(save_preset_globally), true)
    end
end

local function handle_preset_item(ctx, preset, index, category, selected_preset)
    local is_selected = (selected_preset.category == category and selected_preset.index == index)
    if ImGui.Selectable(ctx, preset.name, is_selected) then
        if ImGui.IsKeyDown(ctx, ImGui.Mod_Alt()) then
            table.remove(presets[category], index)
            os.remove(preset.path)
            selected_preset = {category = nil, index = nil}
        else
            selected_preset = {category = category, index = index}
            load_marker_region_set(preset.path)
        end
    end
    if is_selected then
        ImGui.SetItemDefaultFocus(ctx)
    end
end

renumber_items = function(is_region)
    local current_project_key = get_project_key()
    local items = project_items[current_project_key] or {}
    local has_lane_api = r.GetRegionOrMarker ~= nil and r.SetRegionOrMarkerInfo_Value ~= nil

    local visibility_status = {}
    local lane_status = {}
    local lanes = {}
    for _, item in ipairs(items) do
        if item.isRegion == is_region then
            visibility_status[item.index] = item.visible
            lane_status[item.index] = item.lane or 0
            local l = item.lane or 0
            if not lanes[l] then lanes[l] = {} end
            table.insert(lanes[l], item)
            if not item.visible then
                set_item_visibility(item, true)
            end
        end
    end

    local sorted_lanes = {}
    for l in pairs(lanes) do sorted_lanes[#sorted_lanes + 1] = l end
    table.sort(sorted_lanes)

    for _, l in ipairs(sorted_lanes) do
        table.sort(lanes[l], function(a, b) return a.pos < b.pos end)
    end

    r.PreventUIRefresh(1)

    local next_id = 1
    local rename_map = {}
    for _, l in ipairs(sorted_lanes) do
        for _, item in ipairs(lanes[l]) do
            rename_map[#rename_map + 1] = {
                old_index = item.index,
                new_index = next_id,
                is_region = is_region,
                pos = item.pos,
                rgnend = item.rgnend or 0,
                name = item.name,
                color = item.color,
                lane = l,
                visible = visibility_status[item.index]
            }
            next_id = next_id + 1
        end
    end

    for _, entry in ipairs(rename_map) do
        r.DeleteProjectMarker(0, entry.old_index, is_region)
    end

    for _, entry in ipairs(rename_map) do
        r.AddProjectMarker2(0, is_region, entry.pos, entry.rgnend, entry.name, entry.new_index, entry.color)
    end

    if has_lane_api then
        local _, num_m, num_r = r.CountProjectMarkers(0)
        for mi = 0, num_m + num_r - 1 do
            local rv, isrgn, pos, rgnend, name, idx = r.EnumProjectMarkers3(0, mi)
            if rv ~= 0 and isrgn == is_region then
                for _, entry in ipairs(rename_map) do
                    if entry.new_index == idx then
                        local marker = r.GetRegionOrMarker(0, mi, "")
                        if marker then
                            r.SetRegionOrMarkerInfo_Value(0, marker, "I_LANENUMBER", entry.lane)
                        end
                        break
                    end
                end
            end
        end
    end

    r.PreventUIRefresh(-1)

    CACHE_CONFIG.MARKERS.last_update = 0
    local refreshed = get_markers_and_regions()

    for _, item in ipairs(refreshed) do
        if item.isRegion == is_region then
            for _, entry in ipairs(rename_map) do
                if entry.new_index == item.index then
                    if entry.visible == false then
                        set_item_visibility(item, false)
                    end
                    break
                end
            end
        end
    end

    r.UpdateTimeline()
    save_invisible_items()
    save_visibility_to_project()
end

-----------------------------------------------------------------------------

function frame()
    current_dims = getScaledDimensions(settings.scale_factor)

    local window_flags = BASE_WINDOW_FLAGS
    if is_pinned then window_flags = window_flags | ImGui.WindowFlags_TopMost end
    if is_nomove then window_flags = window_flags | ImGui.WindowFlags_NoMove end
    
    local items = get_markers_and_regions()
    SetTKStyle()
    push_font(ctx, fonts[settings.scale_factor])

    ImGui.SetNextWindowSizeConstraints(ctx, current_dims.WINDOW_WIDTH , current_dims.WINDOW_HEIGHT, 16384, 16384)
    local visible, open = ImGui.Begin(ctx, 'TK SMART', window_open, window_flags)
    
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        if settings.save_on_close then SaveSettings() end
        window_open = false
    end
    
    if visible then
        local content_w = ImGui.GetContentRegionAvail(ctx)
        
        TKTitleBar()
        push_font(ctx, fonts[settings.scale_factor])
        if show_settings then TKScaleSettings() end
        
        draw_preset_section(ctx)
        local window_width = ImGui.GetWindowWidth(ctx)
        local num_buttons_per_row = 8
        local padding = 6
        local available_width = window_width - (padding * (num_buttons_per_row + 1))
        local button_width = available_width / num_buttons_per_row
        ImGui.SameLine(ctx)

        if ImGui.Button(ctx, "+Marker", button_width -20) then
            local cursor_pos = r.GetCursorPosition()
            r.AddProjectMarker(0, false, cursor_pos, 0, "", -1)
            items = get_markers_and_regions()
        end
        ImGui.SameLine(ctx)

        if ImGui.Button(ctx, "+Region", button_width -20) then
            local start_time, end_time = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
            if end_time <= start_time then
                start_time = r.GetCursorPosition()
                end_time = start_time + 1
            end
            r.AddProjectMarker(0, true, start_time, end_time, "", -1)
            items = get_markers_and_regions()
        end
        ImGui.SameLine(ctx)

        if ImGui.Button(ctx, "Re# Marker", button_width) then
            r.Undo_BeginBlock()
            renumber_items(false) 
            r.Undo_EndBlock("Renumber Markers", -1)
            items = get_markers_and_regions()
        end
        ImGui.SameLine(ctx)

        if ImGui.Button(ctx, "Re# Region", button_width) then
            r.Undo_BeginBlock()
            renumber_items(true)
            r.Undo_EndBlock("Renumber Regions", -1)
            items = get_markers_and_regions()
        end
        reaper.ImGui_SameLine(ctx)

        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x0080FFFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x0099FFFF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x0080FFFF)
        if reaper.ImGui_Button(ctx, "Browser", button_width) then
            if show_browser then
            SHOW_BROWSER = false
            show_browser = false
            else
            SHOW_BROWSER = true
            local browser_path = reaper.GetResourcePath() .. "/Scripts/TK Scripts/TK SMART/TK_marker_Region_Action_Browser.lua"
            dofile(browser_path)
            show_browser = true
            end
        end
        reaper.ImGui_PopStyleColor(ctx, 3)

        ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0x00000000)
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x00000000)
        ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x00000000)
        local tl_text_w = ImGui.CalcTextSize(ctx, "Timeline")
        if ImGui.Selectable(ctx, "Timeline", false, 0, tl_text_w + 8 * settings.scale_factor, 0) then
            show_minimap = not show_minimap
        end
        ImGui.PopStyleColor(ctx, 3)

        local all_lanes = {}
        local lane_check = {}
        for _, it in ipairs(items) do
            local l = it.lane or 0
            if not lane_check[l] then
                lane_check[l] = true
                all_lanes[#all_lanes + 1] = l
            end
        end
        table.sort(all_lanes)
        
        if show_minimap then
            ImGui.SameLine(ctx)
            local filter_labels = { ["all"] = "All", ["markers"] = "M", ["regions"] = "R" }
            local btn_s = settings.scale_factor
            local filter_w = 40 * btn_s
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_FramePadding, 4 * btn_s, 0)
            ImGui.SetNextItemWidth(ctx, filter_w)
            if ImGui.BeginCombo(ctx, "##tl_filter", filter_labels[timeline_filter], ImGui.ComboFlags_NoArrowButton) then
                if ImGui.Selectable(ctx, "All", timeline_filter == "all") then timeline_filter = "all" end
                if ImGui.Selectable(ctx, "Markers", timeline_filter == "markers") then timeline_filter = "markers" end
                if ImGui.Selectable(ctx, "Regions", timeline_filter == "regions") then timeline_filter = "regions" end
                ImGui.EndCombo(ctx)
            end
            if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Timeline filter: All / Markers / Regions") end

            if #all_lanes > 1 then
                ImGui.SameLine(ctx)
                local lane_label = timeline_lane_filter == "all" and "Ln" or ("L" .. timeline_lane_filter)
                ImGui.SetNextItemWidth(ctx, filter_w)
                if ImGui.BeginCombo(ctx, "##tl_lane_filter", lane_label, ImGui.ComboFlags_NoArrowButton) then
                    if ImGui.Selectable(ctx, "All Lanes", timeline_lane_filter == "all") then timeline_lane_filter = "all" end
                    for _, l in ipairs(all_lanes) do
                        local ls = tostring(l)
                        if ImGui.Selectable(ctx, "Lane " .. ls, timeline_lane_filter == ls) then timeline_lane_filter = ls end
                    end
                    ImGui.EndCombo(ctx)
                end
                if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Filter by ruler lane") end
            end

            ImGui.PopStyleVar(ctx)
        end

        if show_minimap then
            local base_height = 50 * settings.scale_factor
            local visible_lane_count = (#all_lanes > 1 and timeline_lane_filter == "all") and #all_lanes or 1
            local timeline_height = base_height + math.max(0, visible_lane_count - 1) * 20 * settings.scale_factor
            if ImGui.BeginChild(ctx, "Timeline", 0, timeline_height, ImGui.WindowFlags_None) then
                draw_timeline_minimap(ctx, items)
                ImGui.EndChild(ctx)
            end
        end
        
        local tab_avail_w = ImGui.GetContentRegionAvail(ctx)
        local tab_sx, tab_sy = ImGui.GetCursorScreenPos(ctx)
        
        if ImGui.BeginTabBar(ctx, "MarkerRegionTabs") then
            local available_height = calculate_available_height(ctx)
            
            if ImGui.BeginTabItem(ctx, "Markers") then
                if ImGui.BeginChild(ctx, "MarkersTableChild", 0, available_height) then
                    draw_marker_table(ctx, get_markers_and_regions())
                end
                ImGui.EndChild(ctx)
                ImGui.EndTabItem(ctx)
            end
            
            if ImGui.BeginTabItem(ctx, "Regions") then
                if ImGui.BeginChild(ctx, "RegionsTableChild", 0, available_height) then
                    draw_region_table(ctx, get_markers_and_regions())
                end
                ImGui.EndChild(ctx)
                ImGui.EndTabItem(ctx)
            end
            
            if ImGui.BeginTabItem(ctx, "Rules") then
                draw_color_rules_tab(ctx)
                ImGui.EndTabItem(ctx)
            end

            if ImGui.BeginTabItem(ctx, "Actions") then
                if ImGui.BeginChild(ctx, "ActionsChild", 0, available_height) then
                    draw_actions_tab(ctx)
                end
                ImGui.EndChild(ctx)
                ImGui.EndTabItem(ctx)
            end   
            ImGui.EndTabBar(ctx)
        end
        
        local restore_cy = ImGui.GetCursorPosY(ctx)
        local ur_dl = ImGui.GetWindowDrawList(ctx)
        local ur_s = settings.scale_factor
        local undo_btn_w = 28 * ur_s
        local ur_h = ImGui.GetFrameHeight(ctx)
        local ur_col = 0xCCCCCCFF
        local ur_pad = 3 * ur_s
        local ur_r = (ur_h / 2) - ur_pad
        
        ImGui.SetCursorScreenPos(ctx, tab_sx + tab_avail_w - undo_btn_w * 2 - 4 * ur_s, tab_sy)
        
        local ubx, uby = ImGui.GetCursorScreenPos(ctx)
        if ImGui.InvisibleButton(ctx, "##undo_btn", undo_btn_w, ur_h) then
            r.Main_OnCommand(40029, 0)
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Undo") end
        local ucx, ucy = ubx + undo_btn_w / 2, uby + ur_h / 2
        ImGui.DrawList_AddBezierCubic(ur_dl, ucx + ur_r * 0.6, ucy - ur_r * 0.7, ucx - ur_r * 0.3, ucy - ur_r * 1.1, ucx - ur_r * 0.7, ucy - ur_r * 0.2, ucx - ur_r * 0.2, ucy + ur_r * 0.3, ur_col, 1.5 * ur_s, 12)
        ImGui.DrawList_AddTriangleFilled(ur_dl, ucx - ur_r * 0.8, ucy - ur_r * 0.1, ucx - ur_r * 0.1, ucy - ur_r * 0.6, ucx - ur_r * 0.0, ucy + ur_r * 0.4, ur_col)
        
        ImGui.SameLine(ctx)
        
        local rbx, rby = ImGui.GetCursorScreenPos(ctx)
        if ImGui.InvisibleButton(ctx, "##redo_btn", undo_btn_w, ur_h) then
            r.Main_OnCommand(40030, 0)
        end
        if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, "Redo") end
        local rcx, rcy = rbx + undo_btn_w / 2, rby + ur_h / 2
        ImGui.DrawList_AddBezierCubic(ur_dl, rcx - ur_r * 0.6, rcy - ur_r * 0.7, rcx + ur_r * 0.3, rcy - ur_r * 1.1, rcx + ur_r * 0.7, rcy - ur_r * 0.2, rcx + ur_r * 0.2, rcy + ur_r * 0.3, ur_col, 1.5 * ur_s, 12)
        ImGui.DrawList_AddTriangleFilled(ur_dl, rcx + ur_r * 0.8, rcy - ur_r * 0.1, rcx + ur_r * 0.1, rcy - ur_r * 0.6, rcx + ur_r * 0.0, rcy + ur_r * 0.4, ur_col)
        
        ImGui.SetCursorPosY(ctx, restore_cy)

        draw_bottom_section(ctx)
        handle_region_playback()
        handle_marker_playback()
        
        pop_font(ctx)
        pop_style_color(ctx, 24)
        pop_style_var(ctx, 5)
        pop_font(ctx)
        ImGui.End(ctx)
    else
        pop_style_color(ctx, 24)
        pop_style_var(ctx, 5)
        pop_font(ctx)
    end
    if not window_open then
        if settings.save_on_close then SaveSettings() end
    end
    return window_open
end

function loop()
  if frame() then
      r.defer(loop)
  else
    if settings.save_on_close then  
        SaveSettings()
    end
  end
end

r.defer(loop)

end)  -- PCall end - Error handling
if not ok then
  r.ShowConsoleMsg("TK SCALE SCRIPT Error: " .. tostring(err) .. "\n")
  r.ShowMessageBox("An error occurred in TK SCALE SCRIPT. Check console for details.", "Script Error", 0)
end

