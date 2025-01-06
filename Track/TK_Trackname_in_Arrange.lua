-- @description TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 0.6.5
-- @changelog 
--[[
- Bugfix: Text and label are now always above borders
- Some under the hood stuff ;o) 
]]--

local r                  = reaper
local script_path        = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
local preset_path        = script_path .. "TK_Trackname_Presets/"
local json               = dofile(script_path .. "json.lua")
package.path             = r.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local im                 = require 'imgui' '0.9.3'
local ctx                = im.CreateContext('Track Names')

local script_active      = true
local settings_visible   = false
local last_update_time   = 0
local last_project       = nil
local last_track_count   = 0
local overlay_enabled    = false
local needs_font_update  = false
local ImGuiScale_saved   = nil
local screen_scale       = nil
local grid_divide_state = 0

local color_cache        = {}
local cached_bg_color    = nil

-- Alleen om te testen {;o)
--[[local profiler = dofile(reaper.GetResourcePath() .. '/Scripts/ReaTeam Scripts/Development/cfillion_Lua profiler.lua')
reaper.defer = profiler.defer]]--

local flags              = r.ImGui_WindowFlags_NoTitleBar() |
                           r.ImGui_WindowFlags_NoResize() |
                           r.ImGui_WindowFlags_NoNav() |
                           r.ImGui_WindowFlags_NoScrollbar() |
                           r.ImGui_WindowFlags_NoDecoration() |
                           r.ImGui_WindowFlags_NoDocking() | 
                           r.ImGui_WindowFlags_NoBackground()

local window_flags       = flags | 
                           r.ImGui_WindowFlags_NoInputs() |
                           r.ImGui_WindowFlags_NoMove() |
                           r.ImGui_WindowFlags_NoSavedSettings() |
                           -- r.ImGui_WindowFlags_AlwaysAutoResize() |
                           r.ImGui_WindowFlags_NoMouseInputs() |
                           r.ImGui_WindowFlags_NoFocusOnAppearing()

function UpdateBgColorCache()
    cached_bg_color = reaper.GetThemeColor("col_arrangebg", 0)
end

function GetCachedColor(native_color, alpha)
    local cache_key = native_color .. "_" .. alpha
    if not color_cache[cache_key] then
        local r, g, b = reaper.ColorFromNative(native_color)
        color_cache[cache_key] = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, alpha)
    end
    return color_cache[cache_key]
end

-- Sexan's positioning system
local LEFT, TOP, RIGHT, BOT = 0, 0, 0, 0
local WX, WY = 0, 0
local draw_list, scroll_size = nil, 0
local OLD_VAL = 0

-- Window setup using Sexan's method
local main = r.GetMainHwnd()
local arrange = r.JS_Window_FindChildByID(main, 0x3E8)

local function DrawOverArrange()
    local _, DPI_RPR = r.get_config_var_string("uiscale")
    scroll_size = 15 * DPI_RPR
    
    local _, orig_LEFT, orig_TOP, orig_RIGHT, orig_BOT = r.JS_Window_GetRect(arrange)
    local current_val = orig_TOP + orig_BOT + orig_LEFT + orig_RIGHT
    
    if current_val ~= OLD_VAL then
        OLD_VAL = current_val
        LEFT, TOP = im.PointConvertNative(ctx, orig_LEFT, orig_TOP)
        RIGHT, BOT = im.PointConvertNative(ctx, orig_RIGHT, orig_BOT)
    end
    r.ImGui_SetNextWindowPos(ctx, LEFT, TOP)
    r.ImGui_SetNextWindowSize(ctx, (RIGHT - LEFT) - scroll_size, (BOT - TOP) - scroll_size)
end

local default_settings = {
    text_opacity                    = 1.0,
    show_parent_tracks             = true,
    show_child_tracks              = false,
    show_first_fx                  = false,
    show_parent_label              = false,
    show_record_color              = true,
    horizontal_offset              = 100,
    vertical_offset                = 0,
    selected_font                  = 1,
    color_mode                     = 1,
    overlay_alpha                  = 0.1,
    show_track_colors              = true,
    grid_color                     = 0.0,
    bg_brightness                  = 0.2,
    envelope_color_intensity       = 1.0,
    custom_colors_enabled          = false,
    show_label                     = true,
    label_alpha                    = 0.3,
    label_color_mode               = 1,
    text_centered                  = false,
    show_settings_button           = false,
    text_size                      = 14,
    inherit_parent_color           = false,
    deep_inherit_color             = false,
    right_align                    = false,
    show_parent_colors             = true,
    show_child_colors              = true,
    show_normal_colors             = true,
    show_envelope_colors           = true,
    blend_mode                     = 1,
    show_track_numbers             = false,
    track_number_style             = 1,
    autosave_enabled               = false,
    gradient_enabled               = false,
    gradient_direction             = 1,
    gradient_start_alpha           = 1.0,
    gradient_end_alpha             = 0.0,
    track_name_length              = 1,
    all_text_enabled               = true,
    folder_border                  = false,
    folder_border_left             = true,
    folder_border_right            = true,
    folder_border_top              = true,
    folder_border_bottom           = true,
    track_border                   = false,
    track_border_left              = true,
    track_border_right             = true,
    track_border_top               = true,
    track_border_bottom            = true,
    border_thickness               = 2.0,
    border_opacity                 = 1.0,
    button_x                       = 100,
    button_y                       = 100,
    gradient_start_alpha_cached    = 0,
    gradient_end_alpha_cached      = 0
}

local settings = {}
for k, v in pairs(default_settings) do
    settings[k] = v
end

local blend_modes = {
    " Normal", " Multiply", " Screen", " Overlay", " Darken",
    " Lighten", " Color Dodge", " Color Burn", " Hard Light", " Soft Light"
}

local text_sizes = {8, 10, 12, 14, 16, 18, 20, 24, 28, 32}
local fonts = {
    "Arial", "Helvetica", "Verdana", "Tahoma", "Times New Roman",
    "Georgia", "Courier New", "Trebuchet MS", "Impact", "Roboto",
    "Open Sans", "Ubuntu", "Segoe UI", "Noto Sans", "Liberation Sans",
    "DejaVu Sans"
}

local color_modes = {"White", "Black", "Track Color", "Complementary"}
local font_objects = {}
local settings_font

function CreateFonts()
    font_objects = {}
    for _, font_name in ipairs(fonts) do
        local font = r.ImGui_CreateFont(font_name, settings.text_size)
        table.insert(font_objects, font)
        r.ImGui_Attach(ctx, font)
    end
    settings_font = r.ImGui_CreateFont('sans-serif', 14)
    r.ImGui_Attach(ctx, settings_font)
end
if old_text_size ~= settings.text_size then
    CreateFonts()
    end 

function GetTextColor(track, is_child)
    if is_child and settings.inherit_parent_color then
        local parent_track = r.GetParentTrack(track)
        if parent_track then
            track = parent_track
        end
    end

    if settings.color_mode == 1 then
        return 0xFFFFFFFF
    elseif settings.color_mode == 2 then
        return 0x000000FF
    elseif settings.color_mode == 3 then
        return GetCachedColor(r.GetTrackColor(track), 1.0)
    else
        local track_color = r.GetTrackColor(track)
        local cache_key = "complementary_" .. track_color
        if not color_cache[cache_key] then
            local r_val, g_val, b_val = r.ColorFromNative(track_color)
            local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val, g_val, b_val)
            h = (h + 0.5) % 1.0
            local r_val, g_val, b_val = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
            color_cache[cache_key] = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 1.0)
        end
        return color_cache[cache_key]
    end
end

function GetLabelColor(track)
    if settings.label_color_mode == 1 then
        return r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, settings.label_alpha)
    elseif settings.label_color_mode == 2 then
        return r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, settings.label_alpha)
    elseif settings.label_color_mode == 3 then
        return GetCachedColor(r.GetTrackColor(track), settings.label_alpha)
    else
        local track_color = r.GetTrackColor(track)
        local cache_key = "label_complementary_" .. track_color .. "_" .. settings.label_alpha
        if not color_cache[cache_key] then
            local r_val, g_val, b_val = r.ColorFromNative(track_color)
            local h, s, v = r.ImGui_ColorConvertRGBtoHSV(r_val/255, g_val/255, b_val/255)
            h = (h + 0.5) % 1.0
            local r_val, g_val, b_val = r.ImGui_ColorConvertHSVtoRGB(h, s, v)
            color_cache[cache_key] = r.ImGui_ColorConvertDouble4ToU32(r_val, g_val, b_val, settings.label_alpha)
        end
        return color_cache[cache_key]
    end
end

function UpdateGradientAlphaCache()
    settings.gradient_start_alpha_cached = (settings.gradient_start_alpha//0.00392156862745098)
    settings.gradient_end_alpha_cached = (settings.gradient_end_alpha//0.00392156862745098)
end

function SaveSettings()
    local section = "TK_TRACKNAMES"
    local settings_json = json.encode(settings)
    r.SetExtState(section, "settings", settings_json, true)
end

function LoadSettings()
    local section = "TK_TRACKNAMES"
    local settings_json = r.GetExtState(section, "settings")
    if settings_json ~= "" then
        local old_text_size = settings.text_size
        local loaded_settings = json.decode(settings_json)
        for k, v in pairs(loaded_settings) do
            settings[k] = v
        end
        if old_text_size ~= settings.text_size then
            needs_font_update = true
        end
        UpdateGradientAlphaCache()
    end
end

function SavePreset(name)
    local preset_data = {}
    for k, v in pairs(settings) do
        if k ~= "manual_scaling" then
            preset_data[k] = v
        end
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
        local old_text_size = settings.text_size
        local preset_data = json.decode(content)
        
        for key, value in pairs(preset_data) do
            settings[key] = value
        end
        
        if old_text_size ~= settings.text_size then
            needs_font_update = true
        end
        SaveSettings()
    end
end

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

function UpdateGridColors()
    local grid_value = (settings.grid_color * 255)//1
    reaper.SetThemeColor("col_gridlines", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines2", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines3", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr1_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr2_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.UpdateArrange()
end

function UpdateBackgroundColors()
    local MIN_BG_VALUE = 13
    local bg_value = math.max((settings.bg_brightness * 128)//1, MIN_BG_VALUE)
    
    reaper.SetThemeColor("col_arrangebg", reaper.ColorToNative(bg_value, bg_value, bg_value), 0)
    reaper.SetThemeColor("col_tr1_bg", reaper.ColorToNative(bg_value + 10, bg_value + 10, bg_value + 10), 0)
    reaper.SetThemeColor("col_tr2_bg", reaper.ColorToNative(bg_value + 5, bg_value + 5, bg_value + 5), 0)
    reaper.SetThemeColor("selcol_tr1_bg", reaper.ColorToNative(bg_value + 20, bg_value + 20, bg_value + 20), 0)
    reaper.SetThemeColor("selcol_tr2_bg", reaper.ColorToNative(bg_value + 15, bg_value + 15, bg_value + 15), 0)
    reaper.UpdateArrange()
end

function RefreshProjectState()
    UpdateBgColorCache()
    if settings.custom_colors_enabled then
        UpdateGridColors()
        UpdateBackgroundColors()
    end
    reaper.UpdateArrange()
    last_update_time = 0
end

function ToggleColors()
    settings.custom_colors_enabled = not settings.custom_colors_enabled
    if settings.custom_colors_enabled then
        -- Store current grid divide state
        grid_divide_state = r.GetToggleCommandState(42331)
        if grid_divide_state == 1 then
            -- Turn off grid divide if it's on
            r.Main_OnCommand(42331, 0)
        end
        UpdateGridColors()
        UpdateBackgroundColors()
    else
        -- Reset colors
        reaper.SetThemeColor("col_gridlines", -1, 0)
        reaper.SetThemeColor("col_gridlines2", -1, 0)
        reaper.SetThemeColor("col_gridlines3", -1, 0)
        reaper.SetThemeColor("col_arrangebg", -1, 0)
        reaper.SetThemeColor("col_tr1_bg", -1, 0)
        reaper.SetThemeColor("col_tr2_bg", -1, 0)
        reaper.SetThemeColor("selcol_tr1_bg", -1, 0)
        reaper.SetThemeColor("selcol_tr2_bg", -1, 0)
        reaper.SetThemeColor("col_tr1_divline", -1, 0)
        reaper.SetThemeColor("col_tr2_divline", -1, 0)
        
        -- Restore grid divide state if it was on
        if grid_divide_state == 1 then
            r.Main_OnCommand(42331, 0)
        end
    end
    reaper.UpdateArrange()
end

function ResetSettings()
    for k, v in pairs(default_settings) do
        settings[k] = v
    end
    if settings.custom_colors_enabled then
        ToggleColors()
    end   
    SaveSettings()
end

function BlendColor(base, blend, mode)
    local cache_key = "blend_" .. base .. "_" .. blend .. "_" .. mode
    if color_cache[cache_key] then return color_cache[cache_key] end

    local base_r, base_g, base_b = reaper.ColorFromNative(base)
    local blend_r, blend_g, blend_b = reaper.ColorFromNative(blend)
    local result_r, result_g, result_b

    if mode == 1 then return blend end -- Normal
    local div = 0.00392156862745098
    
    if mode == 2 then -- Multiply
        result_r = base_r * blend_r * div
        result_g = base_g * blend_g * div
        result_b = base_b * blend_b * div
    elseif mode == 3 then -- Screen
        result_r = 255 - (255 - base_r) * (255 - blend_r) * div
        result_g = 255 - (255 - base_g) * (255 - blend_g) * div
        result_b = 255 - (255 - base_b) * (255 - blend_b) * div
    elseif mode == 4 then -- Overlay
        result_r = base_r < 128 and (2 * base_r * blend_r * div) or (255 - 2 * (255 - base_r) * (255 - blend_r) * div)
        result_g = base_g < 128 and (2 * base_g * blend_g * div) or (255 - 2 * (255 - base_g) * (255 - blend_g) * div)
        result_b = base_b < 128 and (2 * base_b * blend_b * div) or (255 - 2 * (255 - base_b) * (255 - blend_b) * div)
    elseif mode == 5 then -- Darken
        result_r = math.min(base_r, blend_r)
        result_g = math.min(base_g, blend_g)
        result_b = math.min(base_b, blend_b)
    elseif mode == 6 then -- Lighten
        result_r = math.max(base_r, blend_r)
        result_g = math.max(base_g, blend_g)
        result_b = math.max(base_b, blend_b)
    elseif mode == 7 then -- Color Dodge
        result_r = base_r == 0 and 0 or math.min(255, (blend_r * 255) / (255 - base_r))
        result_g = base_g == 0 and 0 or math.min(255, (blend_g * 255) / (255 - base_g))
        result_b = base_b == 0 and 0 or math.min(255, (blend_b * 255) / (255 - base_b))
    elseif mode == 8 then -- Color Burn
        result_r = base_r == 255 and 255 or math.max(0, 255 - (255 - blend_r) * 255 / base_r)
        result_g = base_g == 255 and 255 or math.max(0, 255 - (255 - blend_g) * 255 / base_g)
        result_b = base_b == 255 and 255 or math.max(0, 255 - (255 - blend_b) * 255 / base_b)
    elseif mode == 9 then -- Hard Light
        result_r = blend_r < 128 and (2 * base_r * blend_r * div) or (255 - 2 * (255 - base_r) * (255 - blend_r) * div)
        result_g = blend_g < 128 and (2 * base_g * blend_g * div) or (255 - 2 * (255 - base_g) * (255 - blend_g) * div)
        result_b = blend_b < 128 and (2 * base_b * blend_b * div) or (255 - 2 * (255 - base_b) * (255 - blend_b) * div)
    else -- Soft Light (mode == 10)
        result_r = blend_r < 128 and base_r - (255 - 2 * blend_r) * base_r * (255 - base_r) * div * div or base_r + (2 * blend_r - 255) * (math.sqrt(base_r/255) * 255 - base_r) * div
        result_g = blend_g < 128 and base_g - (255 - 2 * blend_g) * base_g * (255 - base_g) * div * div or base_g + (2 * blend_g - 255) * (math.sqrt(base_g/255) * 255 - base_g) * div
        result_b = blend_b < 128 and base_b - (255 - 2 * blend_b) * base_b * (255 - base_b) * div * div or base_b + (2 * blend_b - 255) * (math.sqrt(base_b/255) * 255 - base_b) * div
    end

    local result = reaper.ColorToNative((result_r//1), (result_g//1), (result_b//1))
    color_cache[cache_key] = result
    return result
end

function GetFolderBoundaries(track)
    if not track then return nil end
    if r.GetParentTrack(track) then return nil end
    
    local folder_depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if folder_depth ~= 1 then return nil end
    
    local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local current_depth = 1
    local end_idx = track_idx
    local total_tracks = r.CountTracks(0)
    
    while current_depth > 0 and end_idx < total_tracks - 1 do
        end_idx = end_idx + 1
        local child_track = r.GetTrack(0, end_idx)
        if not child_track then break end
        
        local child_depth = r.GetMediaTrackInfo_Value(child_track, "I_FOLDERDEPTH")
        current_depth = current_depth + child_depth
    end
    
    return track_idx, end_idx
end

function ShowSettingsWindow()
    if not settings_visible then return end
    
    -- Use Sexan's positioning
    local _, DPI_RPR = r.get_config_var_string("uiscale")
    local window_x = LEFT + (RIGHT - LEFT - 460) / 2  -- Center horizontally
    local window_y = TOP + (BOT - TOP - 520) / 2      -- Center vertically
    
    r.ImGui_SetNextWindowPos(ctx, window_x, window_y, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSize(ctx, 460, -1)
    
    -- Style setup
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 8.0)

    -- Colors setup
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x333333FF)        
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x444444FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x555555FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x999999FF)     
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xAAAAAAFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0x999999FF)      
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x333333FF)         
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x444444FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x555555FF)   

    local window_flags = r.ImGui_WindowFlags_NoTitleBar() | 
    r.ImGui_WindowFlags_TopMost() |
    r.ImGui_WindowFlags_NoResize() 
    r.ImGui_PushFont(ctx, settings_font)
    local visible, open = r.ImGui_Begin(ctx, 'Track Names Settings', true, window_flags)
    
    if visible then
        r.ImGui_Text(ctx, "TK Track ReaDecorator Settings")
        local window_width = r.ImGui_GetWindowWidth(ctx)
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 200)
        r.ImGui_Text(ctx, string.format("Scaling: %.0f%%", screen_scale * 100))

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 50)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
        if r.ImGui_Button(ctx, "Close") then
            if settings.autosave_enabled then
                SaveSettings()
            end
            r.SetExtState("TK_TRACKNAMES", "settings_visible", "0", false)
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)

        -- PRESETS
        if r.ImGui_Button(ctx, "Save Preset" , 100) then
            r.ImGui_OpenPopup(ctx, "Save Preset##popup")
        end
        r.ImGui_SameLine(ctx)
        local presets = GetPresetList()
        r.ImGui_SetNextItemWidth(ctx, 100)
        if r.ImGui_BeginCombo(ctx, "##Load Preset", "Select Preset") then
            for _, preset_name in ipairs(presets) do
                if r.ImGui_Selectable(ctx, preset_name) then
                    LoadPreset(preset_name)
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        -- Save Preset popup
        if r.ImGui_BeginPopup(ctx, "Save Preset##popup") then
            r.ImGui_Text(ctx, "Enter preset name:")
            local changed, new_name = r.ImGui_InputText(ctx, "##preset_name", preset_name)
            if changed then preset_name = new_name end
            
            if r.ImGui_Button(ctx, "Save") then
                if preset_name ~= "" then
                    SavePreset(preset_name)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            end
            r.ImGui_EndPopup(ctx)
        end

        r.ImGui_Separator(ctx)
        local changed
        local column_width = r.ImGui_GetWindowWidth(ctx) / 4
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
        
        -- Eerste rij controls
        if r.ImGui_RadioButton(ctx, "Parent", settings.show_parent_tracks) then
            settings.show_parent_tracks = not settings.show_parent_tracks
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width)
        
        if r.ImGui_RadioButton(ctx, "Normal/Child", settings.show_child_tracks) then
            settings.show_child_tracks = not settings.show_child_tracks
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        
        if r.ImGui_RadioButton(ctx, "First FX", settings.show_first_fx) then
            settings.show_first_fx = not settings.show_first_fx
        end
        r.ImGui_SameLine(ctx, column_width * 3)
        
        if r.ImGui_RadioButton(ctx, "Label", settings.show_label) then
            settings.show_label = not settings.show_label
        end

        -- Tweede rij controls
        if r.ImGui_RadioButton(ctx, "Parent label", settings.show_parent_label) then
            settings.show_parent_label = not settings.show_parent_label
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width)
        
        if r.ImGui_RadioButton(ctx, "Center", settings.text_centered) then
            settings.text_centered = not settings.text_centered
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        
        if r.ImGui_RadioButton(ctx, "Right align", settings.right_align) then
            settings.right_align = not settings.right_align
        end
        r.ImGui_SameLine(ctx, column_width * 3)
        
        if r.ImGui_RadioButton(ctx, "Settings button", settings.show_settings_button) then
            settings.show_settings_button = not settings.show_settings_button
        end
       
        -- Track number controls
        if r.ImGui_RadioButton(ctx, "Track Number", settings.show_track_numbers) then
            settings.show_track_numbers = not settings.show_track_numbers
        end
        r.ImGui_SameLine(ctx, column_width)
        
        r.ImGui_SetNextItemWidth(ctx, 100)
        if r.ImGui_BeginCombo(ctx, "##Number Style", 
            settings.track_number_style == 1 and " Before Name" or
            settings.track_number_style == 2 and " After Name" or
            "Above Name") then
            if r.ImGui_Selectable(ctx, " Before Name", settings.track_number_style == 1) then
                settings.track_number_style = 1
            end
            if r.ImGui_Selectable(ctx, " After Name", settings.track_number_style == 2) then
                settings.track_number_style = 2
            end
            r.ImGui_EndCombo(ctx)
        end

        -- Name length controls
        r.ImGui_SameLine(ctx, column_width * 2)
        r.ImGui_Text(ctx, "Name length:")
        r.ImGui_SameLine(ctx, column_width * 3)
        r.ImGui_SetNextItemWidth(ctx, 100)
        if r.ImGui_BeginCombo(ctx, "##Track name length", 
            settings.track_name_length == 1 and " Full length" or
            settings.track_name_length == 2 and " Max 16 chars" or
            " Max 32 chars") then
            
            if r.ImGui_Selectable(ctx, " Full length", settings.track_name_length == 1) then
                settings.track_name_length = 1
            end
            if r.ImGui_Selectable(ctx, " Max 16 chars", settings.track_name_length == 2) then
                settings.track_name_length = 2
            end
            if r.ImGui_Selectable(ctx, " Max 32 chars", settings.track_name_length == 3) then
                settings.track_name_length = 3
            end
            r.ImGui_EndCombo(ctx)
        end

        r.ImGui_Separator(ctx)
        -- Track colors en overlay controls
        if r.ImGui_RadioButton(ctx, "Track colors", settings.show_track_colors) then
            settings.show_track_colors = not settings.show_track_colors
            needs_font_update = true
        end
        if settings.show_track_colors then
            r.ImGui_SameLine(ctx, column_width)
            r.ImGui_SetNextItemWidth(ctx, 100)
            if r.ImGui_BeginCombo(ctx, "##Blend Mode", blend_modes[settings.blend_mode]) then
                for i, mode in ipairs(blend_modes) do
                    if r.ImGui_Selectable(ctx, mode, settings.blend_mode == i) then
                        settings.blend_mode = i
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            
            r.ImGui_SameLine(ctx, column_width * 2)
            if r.ImGui_RadioButton(ctx, "Inherit color", settings.inherit_parent_color) then
                settings.inherit_parent_color = not settings.inherit_parent_color
                if settings.inherit_parent_color then
                    settings.deep_inherit_color = false
                end
            end 
            r.ImGui_SameLine(ctx, column_width * 3)
            if r.ImGui_RadioButton(ctx, "Deep Inherit", settings.deep_inherit_color) then
                settings.deep_inherit_color = not settings.deep_inherit_color
                if settings.deep_inherit_color then
                    settings.inherit_parent_color = false
                end
            end  
        
            -- Vierde rij
            if r.ImGui_RadioButton(ctx, "Parent colors", settings.show_parent_colors) then
                settings.show_parent_colors = not settings.show_parent_colors
                needs_font_update = CheckTrackColorUpdate()
            end
            r.ImGui_SameLine(ctx, column_width)
            if r.ImGui_RadioButton(ctx, "Child colors", settings.show_child_colors) then
                settings.show_child_colors = not settings.show_child_colors
                needs_font_update = CheckTrackColorUpdate()
            end
            r.ImGui_SameLine(ctx, column_width * 2)
            if r.ImGui_RadioButton(ctx, "Normal colors", settings.show_normal_colors) then
                settings.show_normal_colors = not settings.show_normal_colors
                needs_font_update = CheckTrackColorUpdate()
            end
            r.ImGui_SameLine(ctx, column_width * 3)
            if r.ImGui_RadioButton(ctx, "Record color", settings.show_record_color) then
                settings.show_record_color = not settings.show_record_color
            end

            -- Vijfde rij
            if r.ImGui_RadioButton(ctx, "Env Colors", settings.show_envelope_colors) then
                settings.show_envelope_colors = not settings.show_envelope_colors
            end
            r.ImGui_SameLine(ctx, column_width)
            if settings.overlay_style == 1 then
                if r.ImGui_RadioButton(ctx, "Gradient", settings.gradient_enabled) then
                    settings.gradient_enabled = not settings.gradient_enabled
                end
            end
            if settings.gradient_enabled and settings.overlay_style == 1 then
                r.ImGui_SameLine(ctx, column_width * 2)
                r.ImGui_SetNextItemWidth(ctx, 100)
                if r.ImGui_BeginCombo(ctx, "##Gradient Direction", 
                    settings.gradient_direction == 1 and " Horizontal" or " Vertical") then
                    if r.ImGui_Selectable(ctx, " Horizontal", settings.gradient_direction == 1) then
                        settings.gradient_direction = 1
                    end
                    if r.ImGui_Selectable(ctx, " Vertical", settings.gradient_direction == 2) then
                        settings.gradient_direction = 2
                    end
                    r.ImGui_EndCombo(ctx)
                end
            end
            if settings.overlay_style == 1 then
                if r.ImGui_RadioButton(ctx, "Folder Borders", settings.folder_border) then
                    settings.folder_border = not settings.folder_border
                end
                if settings.folder_border then
                    r.ImGui_SameLine(ctx, column_width)  
                    if r.ImGui_RadioButton(ctx, "All##folder",
                        settings.folder_border_left and
                        settings.folder_border_right and
                        settings.folder_border_top and
                        settings.folder_border_bottom) then
                        local new_state = not (settings.folder_border_left and
                                             settings.folder_border_right and
                                             settings.folder_border_top and
                                             settings.folder_border_bottom)
                        settings.folder_border_left = new_state
                        settings.folder_border_right = new_state
                        settings.folder_border_top = new_state
                        settings.folder_border_bottom = new_state
                    end
            
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Left##folder", settings.folder_border_left) then
                        settings.folder_border_left = not settings.folder_border_left
                    end
            
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Right##folder", settings.folder_border_right) then
                        settings.folder_border_right = not settings.folder_border_right
                    end
            
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Top##folder", settings.folder_border_top) then
                        settings.folder_border_top = not settings.folder_border_top
                    end
            
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Bottom##folder", settings.folder_border_bottom) then
                        settings.folder_border_bottom = not settings.folder_border_bottom
                    end
                end
            end
            if settings.overlay_style == 1 then
                if r.ImGui_RadioButton(ctx, "Track Borders ", settings.track_border) then
                    settings.track_border = not settings.track_border
                end

                if settings.track_border then
                    r.ImGui_SameLine(ctx, column_width)
                    if r.ImGui_RadioButton(ctx, "All##track",
                        settings.track_border_left and
                        settings.track_border_right and
                        settings.track_border_top and
                        settings.track_border_bottom) then
                        local new_state = not (settings.track_border_left and
                                            settings.track_border_right and
                                            settings.track_border_top and
                                            settings.track_border_bottom)
                        settings.track_border_left = new_state
                        settings.track_border_right = new_state
                        settings.track_border_top = new_state
                        settings.track_border_bottom = new_state
                    end

                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Left##track", settings.track_border_left) then
                        settings.track_border_left = not settings.track_border_left
                    end

                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Right##track", settings.track_border_right) then
                        settings.track_border_right = not settings.track_border_right
                    end

                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Top##track", settings.track_border_top) then
                        settings.track_border_top = not settings.track_border_top
                    end

                    r.ImGui_SameLine(ctx)
                    if r.ImGui_RadioButton(ctx, "Bottom##track", settings.track_border_bottom) then
                        settings.track_border_bottom = not settings.track_border_bottom
                    end
                end
            end
        end  
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_Separator(ctx)
           
        r.ImGui_PushItemWidth(ctx, 340)
        if settings.show_track_colors then

            if (settings.folder_border and settings.show_parent_colors and settings.overlay_style == 1) or 
            (settings.track_border and settings.show_normal_colors and settings.overlay_style == 1) then
                changed, settings.border_thickness = r.ImGui_SliderDouble(ctx, "Border Thickness", settings.border_thickness, 1, 20.0)
                changed, settings.border_opacity = r.ImGui_SliderDouble(ctx, "Border Opacity", settings.border_opacity, 0.0, 1.0)
            end
                    
            if settings.overlay_style == 2 or settings.overlay_style == 3 then
                changed, settings.frame_thickness = r.ImGui_SliderDouble(ctx, "Frame Thickness", settings.frame_thickness, 1.0, 20.0)
            end

            if not settings.gradient_enabled or settings.overlay_style == 2 or settings.overlay_style == 3 then
                changed, settings.overlay_alpha = r.ImGui_SliderDouble(ctx, "Color Intensity", settings.overlay_alpha, 0.0, 1.0)
            end
            if settings.show_envelope_colors then
                changed, settings.envelope_color_intensity = r.ImGui_SliderDouble(ctx, "Env Intensity", settings.envelope_color_intensity, 0.0, 1.0)
            end

            if settings.gradient_enabled and settings.overlay_style == 1 then
                changed, settings.gradient_start_alpha = r.ImGui_SliderDouble(ctx, "Start Gradient", settings.gradient_start_alpha, 0.0, 1.0)
                if changed then UpdateGradientAlphaCache() end
                
                changed, settings.gradient_end_alpha = r.ImGui_SliderDouble(ctx, "End Gradient", settings.gradient_end_alpha, 0.0, 1.0)
                if changed then UpdateGradientAlphaCache() end
            end
        end
        
        -- Label controls
        if not settings.show_label then
            r.ImGui_BeginDisabled(ctx)
        end
        changed, settings.label_alpha = r.ImGui_SliderDouble(ctx, "Label opacity", settings.label_alpha, 0.0, 1.0)
        
        -- Label color combo using Sexan's positioning
        local label_combo_pos_x = LEFT + settings.horizontal_offset
        local label_combo_pos_y = WY + settings.vertical_offset
        if r.ImGui_BeginCombo(ctx, "Label color", color_modes[settings.label_color_mode]) then
            for i, color_name in ipairs(color_modes) do
                if r.ImGui_Selectable(ctx, color_name, settings.label_color_mode == i) then
                    settings.label_color_mode = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        if not settings.show_label then
            r.ImGui_EndDisabled(ctx)
        end

        -- Position controls using Sexan's arrange window coordinates
        changed, settings.horizontal_offset = r.ImGui_SliderInt(ctx, "Horizontal offset", settings.horizontal_offset, 0, RIGHT - LEFT)
        changed, settings.vertical_offset = r.ImGui_SliderInt(ctx, "Vertical offset(%)", settings.vertical_offset, -50, 50)
        
        if r.ImGui_BeginCombo(ctx, "Font", fonts[settings.selected_font]) then
            for i, font_name in ipairs(fonts) do
                if r.ImGui_Selectable(ctx, font_name, settings.selected_font == i) then
                    settings.selected_font = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        -- Text color and size controls
        if r.ImGui_BeginCombo(ctx, "Text color", color_modes[settings.color_mode]) then
            for i, color_name in ipairs(color_modes) do
                if r.ImGui_Selectable(ctx, color_name, settings.color_mode == i) then
                    settings.color_mode = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        if r.ImGui_BeginCombo(ctx, "Text size", tostring(settings.text_size)) then
            for _, size in ipairs(text_sizes) do
                if r.ImGui_Selectable(ctx, tostring(size), settings.text_size == size) then
                    settings.text_size = size
                    needs_font_update = true
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        -- Opacity and custom colors
        changed, settings.text_opacity = r.ImGui_SliderDouble(ctx, "Text opacity", settings.text_opacity, 0.0, 1.0)

        if settings.custom_colors_enabled then
            changed_grid, settings.grid_color = r.ImGui_SliderDouble(ctx, "Grid Color", settings.grid_color, 0.0, 1.0)
            changed_bg, settings.bg_brightness = r.ImGui_SliderDouble(ctx, "Bg Brightness", settings.bg_brightness, 0.0, 1.0)
            
            if changed_grid then UpdateGridColors() end
            if changed_bg then UpdateBackgroundColors() end
        end

        r.ImGui_PopItemWidth(ctx)

        -- Bottom buttons
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, settings.custom_colors_enabled and "Reset Colors" or "Custom Colors", 100) then
            reaper.Undo_BeginBlock()
            ToggleColors()
            reaper.Undo_EndBlock("Toggle Custom Grid and Background Colors", -1)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Reset Settings", 100) then
            ResetSettings()
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Save Settings", 100) then
            SaveSettings()
        end
        r.ImGui_SameLine(ctx)

        local changed, new_value = r.ImGui_Checkbox(ctx, "Autosave", settings.autosave_enabled)
        if changed then
            settings.autosave_enabled = new_value
        end

        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 5)
    r.ImGui_PopStyleColor(ctx, 9)
end

function IsTrackVisible(track)
    local MIN_TRACK_HEIGHT = 10
    local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
    
    if track_height <= MIN_TRACK_HEIGHT then
        return false
    end
    
    local parent = r.GetParentTrack(track)
    while parent do
        local parent_height = r.GetMediaTrackInfo_Value(parent, "I_TCPH") / screen_scale
        if parent_height <= MIN_TRACK_HEIGHT then
            return false
        end
        parent = r.GetParentTrack(parent)
    end
    return true
end

-- Thanx Smandrap
local function IsRecording(track)
    if r.GetMediaTrackInfo_Value(track, "I_RECARM") == 0 then return false end
    if r.GetMediaTrackInfo_Value(track, "I_RECINPUT") < 0 then return false end
    if r.GetMediaTrackInfo_Value(track, "I_RECMODE") == 2 then return false end
    return true
end

function GetAllParentTracks(track)
    local parents = {}
    local current = track
    while true do
        local parent = r.GetParentTrack(current)
        if not parent then break end
        table.insert(parents, parent)
        current = parent
    end
    return parents
end

function TruncateTrackName(name, mode)
    if mode == 1 then
        return name 
    elseif mode == 2 and #name > 16 then
        return name:sub(1, 13) .. "..."
    elseif mode == 3 and #name > 32 then
        return name:sub(1, 29) .. "..."
    end
    return name
end

function DrawTrackIcon(track, x, y)
    local retval, icon_data = r.GetTrackIcon(track)
    if retval > 0 and icon_data then
        local icon_texture = r.ImGui_CreateImage(icon_data)
        if icon_texture then
            r.ImGui_DrawList_AddImage(draw_list, icon_texture, x, y, x + 16, y + 16)
            r.ImGui_Image_Destroy(icon_texture)
        end
    end
end

function SetButtonState(set)
    local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
    reaper.SetToggleCommandState(sec, cmd, set or 0)
    reaper.RefreshToolbar2(sec, cmd)
end

function CheckNeedsUpdate()
    return not (settings.show_child_tracks or 
                settings.show_parent_tracks or 
                settings.show_parent_label)
end

function CheckTrackColorUpdate()
    return not (settings.show_parent_colors or 
                settings.show_child_colors or 
                settings.show_normal_colors)
end

function ResetRenderContext()
    ctx = r.ImGui_CreateContext('Track Names')
    r.ImGui_Attach(ctx, settings_font)
    for _, font in ipairs(font_objects) do
        r.ImGui_Attach(ctx, font)
    end
end

function RenderSolidOverlay(draw_list, track, track_y, track_height, color, window_y)
    local background_draw_list = r.ImGui_GetBackgroundDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(
        background_draw_list,
        LEFT,
        window_y + track_y,
        RIGHT - scroll_size,
        window_y + track_y + track_height,
        color
    )
    
    -- Envelope overlay
    local track_env_cnt = r.CountTrackEnvelopes(track)
    if track_env_cnt > 0 and settings.show_envelope_colors then
        local env_y = track_y + track_height
        local env_height = (r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale) - track_height
        local env_color = (color & 0xFFFFFF00) | ((settings.envelope_color_intensity * settings.overlay_alpha * 255)//1)
        
        r.ImGui_DrawList_AddRectFilled(
            draw_list,
            LEFT,
            window_y + env_y,
            RIGHT - scroll_size,
            window_y + env_y + env_height,
            env_color
        )
    end
end

function RenderGradientRect(draw_list, x1, y1, x2, y2, color, intensity)
    local alpha_start = intensity and (settings.gradient_start_alpha_cached * intensity)//1 or settings.gradient_start_alpha_cached
    local alpha_end = intensity and (settings.gradient_end_alpha_cached * intensity)//1 or settings.gradient_end_alpha_cached

    if settings.gradient_direction == 1 then
        r.ImGui_DrawList_AddRectFilledMultiColor(
            draw_list, x1, y1, x2, y2,
            (color & 0xFFFFFF00) | alpha_start,
            (color & 0xFFFFFF00) | alpha_end,
            (color & 0xFFFFFF00) | alpha_end,
            (color & 0xFFFFFF00) | alpha_start
        )
    else
        r.ImGui_DrawList_AddRectFilledMultiColor(
            draw_list, x1, y1, x2, y2,
            (color & 0xFFFFFF00) | alpha_start,
            (color & 0xFFFFFF00) | alpha_start,
            (color & 0xFFFFFF00) | alpha_end,
            (color & 0xFFFFFF00) | alpha_end
        )
    end
end


    
function RenderGradientOverlay(draw_list, track, track_y, track_height, color, window_y)    
    local background_draw_list = r.ImGui_GetBackgroundDrawList(ctx)
    RenderGradientRect(
        background_draw_list,
        LEFT,
        window_y + track_y,
        RIGHT - scroll_size,
        window_y + track_y + track_height,
        color
    )
    
    -- Envelope gradient
    local track_env_cnt = r.CountTrackEnvelopes(track)
    if track_env_cnt > 0 and settings.show_envelope_colors then
        local env_y = track_y + track_height
        local env_height = (r.GetMediaTrackInfo_Value(track, "I_WNDH") / screen_scale) - track_height
        
        RenderGradientRect(
            draw_list,
            LEFT,
            window_y + env_y,
            RIGHT - scroll_size,
            window_y + env_y + env_height,
            color,
            settings.envelope_color_intensity
        )
    end
end

function DrawFolderBorderLine(draw_list,x1,y1,x2,y2,color,thickness)
    --local foreground_draw_list = r.ImGui_GetForegroundDrawList(ctx)
    r.ImGui_DrawList_AddLine(draw_list,x1,y1,x2,y2,color,thickness)
end

function DrawTrackBorderLine(draw_list,x1,y1,x2,y2,color,thickness)
    r.ImGui_DrawList_AddLine(draw_list,x1, y1, x2, y2,color,thickness)
end

function DrawFolderBorders(draw_list, track, track_y, track_height, border_color, WY)
    if r.GetParentTrack(track) then return end
    
    local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if depth == 1 then
        local start_idx, end_idx = GetFolderBoundaries(track)
        if start_idx and end_idx then
            local end_track = r.GetTrack(0, end_idx)
            local end_y = r.GetMediaTrackInfo_Value(end_track, "I_TCPY") /screen_scale
            local end_height = r.GetMediaTrackInfo_Value(end_track, "I_TCPH") /screen_scale
            local total_height = (end_y + end_height) - track_y
            
            -- Draw the complete frame
            if settings.folder_border_top then
                DrawFolderBorderLine(
                    draw_list,
                    LEFT,
                    WY + track_y + settings.border_thickness/2,
                    RIGHT - scroll_size,
                    WY + track_y + settings.border_thickness/2,
                    border_color,
                    settings.border_thickness
                )
            end

            if settings.folder_border_left then
                DrawFolderBorderLine(
                    draw_list,
                    LEFT + settings.border_thickness/2,
                    WY + track_y,
                    LEFT + settings.border_thickness/2,
                    WY + track_y + total_height,
                    border_color,
                    settings.border_thickness
                )
            end
            
            if settings.folder_border_right then
                DrawFolderBorderLine(
                    draw_list,
                    RIGHT - scroll_size - settings.border_thickness/2,
                    WY + track_y,
                    RIGHT - scroll_size - settings.border_thickness/2,
                    WY + track_y + total_height,
                    border_color,
                    settings.border_thickness
                )
            end
            
            if settings.folder_border_bottom then
                DrawFolderBorderLine(
                    draw_list,
                    LEFT,
                    WY + track_y + total_height - settings.border_thickness/2,
                    RIGHT - scroll_size,
                    WY + track_y + total_height - settings.border_thickness/2,
                    border_color,
                    settings.border_thickness
                )
            end
        end
    end
end


function DrawTrackBorders(draw_list, track_y, track_height, border_color, WY)
    if settings.track_border_left then
        DrawTrackBorderLine(
            draw_list,
            LEFT + settings.border_thickness/2,
            WY + track_y,
            LEFT + settings.border_thickness/2,
            WY + track_y + track_height,
            border_color,
            settings.border_thickness
        )
    end
    
    if settings.track_border_right then
        DrawTrackBorderLine(
            draw_list,
            RIGHT - scroll_size - settings.border_thickness/2,
            WY + track_y,
            RIGHT - scroll_size - settings.border_thickness/2,
            WY + track_y + track_height,
            border_color,
            settings.border_thickness
        )
    end
    
    if settings.track_border_top then
        DrawTrackBorderLine(
            draw_list,
            LEFT,
            WY + track_y + settings.border_thickness/2,
            RIGHT - scroll_size,
            WY + track_y + settings.border_thickness/2,
            border_color,
            settings.border_thickness
        )
    end
    
    if settings.track_border_bottom then
        DrawTrackBorderLine(
            draw_list,
            LEFT,
            WY + track_y + track_height - settings.border_thickness/2,
            RIGHT - scroll_size,
            WY + track_y + track_height - settings.border_thickness/2,
            border_color,
            settings.border_thickness
        )
    end
end


function GetDarkerColor(color)
    local r_val, g_val, b_val = r.ColorFromNative(color)
    return r.ColorToNative(
        (r_val * 0.7)//1,
        (g_val * 0.7)//1,
        (b_val * 0.7)//1
    )
end

-- Scaling by OLSHALOM!
function SetWindowScale(ImGuiScale)
    local OS = reaper.GetOS()
    if OS:find("Win") then
        screen_scale = ImGuiScale  -- Voor Windows
    else
        screen_scale = 1
    end
end
--[[profiler.attachToWorld()
profiler.run()
profiler.start()]]--
function loop()

    settings_visible = r.GetExtState("TK_TRACKNAMES", "settings_visible") == "1"
    if not (ctx and r.ImGui_ValidatePtr(ctx, 'ImGui_Context*')) then
        ctx = r.ImGui_CreateContext('Track Names')
        CreateFonts()
    end

    local current_project = reaper.EnumProjects(-1)
    local track_count = reaper.CountTracks(0)
    if current_project ~= last_project or track_count ~= last_track_count then
        RefreshProjectState()
        last_project = current_project
        last_track_count = track_count
    end
    if settings.custom_colors_enabled then
        local current_grid_divide = r.GetToggleCommandState(42331)
        if current_grid_divide == 1 then
            r.Main_OnCommand(42331, 0)
        end
    end

    DrawOverArrange()
    r.ImGui_PushFont(ctx, font_objects[settings.selected_font])
    -- Later in code (1.48% vs 0.01% minimal impact on total cost)
    local ImGuiScale = reaper.ImGui_GetWindowDpiScale(ctx)
    if ImGuiScale ~= ImGuiScale_saved then
      SetWindowScale(ImGuiScale)
      ImGuiScale_saved = ImGuiScale
    end


    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0.0)

    local visible, open = r.ImGui_Begin(ctx, 'Track Names Display', true, window_flags)
    if visible then
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local WX, WY = r.ImGui_GetWindowPos(ctx)
        local max_width = 0

        if not cached_bg_color then
            UpdateBgColorCache()
        end

        -- Main track processing loop
        for i = 0, track_count - 1 do
            local track = r.GetTrack(0, i)
            local track_visible = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1
            
            if track_visible and IsTrackVisible(track) then
                local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") /screen_scale
                local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") /screen_scale
                local is_parent = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                local is_child = r.GetParentTrack(track) ~= nil
                local track_color = r.GetTrackColor(track)
                local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
                local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
                local is_soloed = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
                local track_number = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")

                local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                max_width = math.max(max_width, text_width)

                -- Track colors and borders
                if settings.show_track_colors then
                    if ((is_parent and settings.show_parent_colors) or
                        (is_child and settings.show_child_colors) or
                        (not is_parent and not is_child and settings.show_normal_colors)) then
                        
                            if settings.deep_inherit_color then
                                local current = track
                                local main_parent = nil
                                while r.GetParentTrack(current) do
                                    current = r.GetParentTrack(current)
                                    if not r.GetParentTrack(current) then
                                        main_parent = current
                                    end
                                end
                                if main_parent then
                                    track_color = r.GetTrackColor(main_parent)
                                end
                            elseif settings.inherit_parent_color then
                                local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
                                local parent = r.GetParentTrack(track)
                                
                                if depth ~= 1 then
                                    if parent then
                                        track_color = r.GetTrackColor(parent)
                                    end
                                end
                            end
                            
                        if settings.show_record_color and IsRecording(track) and r.GetPlayState() == 5 then
                            track_color = r.ColorToNative(255, 0, 0)  -- Rood voor alle systemen
                        end

                        if track_color ~= 0 then
                            local total_height = track_height
                            local env_count = r.CountTrackEnvelopes(track)
                            
                            if env_count > 0 then
                                for i = 0, env_count - 1 do
                                    total_height = total_height + r.GetEnvelopeInfo_Value(r.GetTrackEnvelope(track, i), "I_TCPH") / screen_scale
                                end
                            end
                            
                            if track_y < (BOT - TOP) - scroll_size or (track_y + total_height) > 0 then
                                local blended_color = BlendColor(cached_bg_color, track_color, settings.blend_mode)
                                local color = GetCachedColor(blended_color, settings.overlay_alpha)
                                
                                if settings.gradient_enabled then
                                    RenderGradientOverlay(draw_list, track, track_y, track_height, color, WY)
                                else
                                    RenderSolidOverlay(draw_list, track, track_y, track_height, color, WY)
                                end
                            end
                        end
                        
                    end

                    if settings.folder_border and (is_parent or is_child) then
                        local track_color = r.GetTrackColor(track)
                        if is_child then
                            track_color = r.GetTrackColor(r.GetParentTrack(track))
                        end
                        local darker_color = GetDarkerColor(track_color)
                        local border_color = GetCachedColor(darker_color, settings.border_opacity)
                        DrawFolderBorders(draw_list, track, track_y, track_height, border_color, WY)
                    end
                    
                    if settings.track_border and not is_parent and not is_child and track_color ~= 0 then
                        local blended_color = BlendColor(cached_bg_color, track_color, settings.blend_mode)
                        local border_color = GetCachedColor(blended_color, settings.border_opacity)
                        DrawTrackBorders(draw_list, track_y, track_height, border_color, WY)
                    end
                    
                end

                -- Track name processing
                local should_show_track = false
                local should_show_name = false

                if settings.show_parent_tracks and is_parent then
                    should_show_track = true
                    should_show_name = true
                end
                if settings.show_child_tracks and (is_child or (not is_parent and not is_child)) then
                    should_show_track = true
                    should_show_name = true
                end
                if settings.show_parent_label and is_child then
                    should_show_track = true
                end

                if should_show_track then
                    local _, track_name = r.GetTrackName(track)
                    local display_name = TruncateTrackName(track_name, settings.track_name_length)
                    
                    if settings.show_first_fx then
                        local fx_count = r.TrackFX_GetCount(track)
                        if fx_count > 0 then
                            local _, fx_name = r.TrackFX_GetFXName(track, 0, "")
                            fx_name = fx_name:gsub("^[^:]+:%s*", "")
                            display_name = display_name .. " - " .. fx_name
                        end
                    end

                    local vertical_offset = (track_height * settings.vertical_offset) / 100
                    local text_y = WY + track_y + (track_height * 0.5) - (settings.text_size * 0.5) + vertical_offset

                    -- Parent label processing
                    if is_child and settings.show_parent_label then
                        local parents = GetAllParentTracks(track)
                        if #parents > 0 then
                            local combined_name = ""
                            for i = #parents, 1, -1 do
                                local _, parent_name = r.GetTrackName(parents[i])
                                parent_name = TruncateTrackName(parent_name, settings.track_name_length)
                                combined_name = combined_name .. parent_name .. " / "
                            end

                            local parent_text_width = r.ImGui_CalcTextSize(ctx, combined_name)
                            local track_text_width = r.ImGui_CalcTextSize(ctx, display_name)
                            local parent_text_pos = WX + settings.horizontal_offset
                            local label_x = parent_text_pos
                            
                            local BASE_SPACING = 20
                            local NUMBER_SPACING = 20
                            local TEXT_SIZE_FACTOR = settings.text_size

                            if settings.text_centered then
                                if should_show_name then
                                    local total_spacing = BASE_SPACING + TEXT_SIZE_FACTOR
                                    if settings.show_track_numbers then
                                        total_spacing = total_spacing + NUMBER_SPACING /2
                                    end
                                    
                                    local offset = (max_width - track_text_width) / 2
                                    parent_text_pos = WX + settings.horizontal_offset + offset + track_text_width + total_spacing
                                    label_x = parent_text_pos
                                else
                                    local offset = (max_width - parent_text_width) / 2
                                    parent_text_pos = WX + settings.horizontal_offset + offset
                                    label_x = parent_text_pos
                                end
                            elseif settings.right_align then
                                local right_margin = 20
                                local total_spacing = BASE_SPACING + TEXT_SIZE_FACTOR
                                if settings.show_track_numbers then
                                    total_spacing = total_spacing + NUMBER_SPACING
                                end
                                
                                parent_text_pos = RIGHT - scroll_size - parent_text_width - right_margin - settings.horizontal_offset
                                label_x = parent_text_pos
                                if should_show_name then
                                    parent_text_pos = parent_text_pos - track_text_width - total_spacing
                                    label_x = parent_text_pos
                                end
                            else
                                if should_show_name then
                                    local total_spacing = BASE_SPACING + TEXT_SIZE_FACTOR
                                    if settings.show_track_numbers then
                                        total_spacing = total_spacing + NUMBER_SPACING
                                    end
                                    
                                    parent_text_pos = WX + settings.horizontal_offset + track_text_width + total_spacing
                                    label_x = parent_text_pos
                                end
                            end

                            if settings.show_label then
                                local parent_color = r.GetTrackColor(parents[#parents])
                                local r_val, g_val, b_val = r.ColorFromNative(parent_color)
                                local parent_label_color = r.ImGui_ColorConvertDouble4ToU32(
                                    r_val/255, g_val/255, b_val/255,
                                    settings.label_alpha
                                )
                                
                                r.ImGui_DrawList_AddRectFilled(
                                    draw_list,
                                    label_x - 10,
                                    text_y - 1,
                                    label_x + parent_text_width + 10,
                                    text_y + settings.text_size + 1,
                                    parent_label_color,
                                    4.0
                                )
                            end

                            local parent_text_color = GetTextColor(parents[#parents])
                            r.ImGui_DrawList_AddText(
                                draw_list,
                                parent_text_pos,
                                text_y,
                                parent_text_color,
                                combined_name
                            )
                        end
                    end

                    -- Track name rendering
                    if should_show_name then
                        local modified_display_name = display_name
                        
                        if settings.show_track_numbers then
                            if settings.track_number_style == 1 then
                                modified_display_name = string.format("%02d. %s", track_number, display_name)
                            elseif settings.track_number_style == 2 then
                                modified_display_name = string.format("%s -%02d", display_name, track_number)
                            end
                        end

                        local text_width = r.ImGui_CalcTextSize(ctx, modified_display_name)
                        local text_x = WX + settings.horizontal_offset

                        if settings.text_centered then
                            local offset = (max_width - text_width) / 2
                            text_x = WX + settings.horizontal_offset + offset
                        elseif settings.right_align then
                            text_x = RIGHT - scroll_size - text_width - 20 - settings.horizontal_offset
                        end

                        if settings.show_label then
                            local label_color = GetLabelColor(track)
                            r.ImGui_DrawList_AddRectFilled(
                                draw_list,
                                text_x - 10,
                                text_y - 1,
                                text_x + text_width + 10,
                                text_y + settings.text_size + 1,
                                label_color,
                                4.0
                            )
                        end

                        local text_color = GetTextColor(track, is_child)
                        text_color = (text_color & 0xFFFFFF00) | ((settings.text_opacity * 255)//1)
                        r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, modified_display_name)
                        
                        -- Track state indicators
                        local dot_size = 4
                        local dot_spacing = 1
                        local total_dots_height = (dot_size * 3) + (dot_spacing * 2)
                        local track_center = text_y + (settings.text_size / 2)
                        local dots_start_y = track_center - (total_dots_height / 2)
                        local dot_x = text_x + text_width + 5
                    
                        if is_armed then
                            r.ImGui_DrawList_AddCircleFilled(
                                draw_list,
                                dot_x,
                                dots_start_y + dot_size/2,
                                dot_size/2,
                                0xFF0000FF
                            )
                        end
                        
                        if is_soloed then
                            r.ImGui_DrawList_AddCircleFilled(
                                draw_list,
                                dot_x,
                                dots_start_y + dot_size + dot_spacing + dot_size/2,
                                dot_size/2,
                                0x0000FFFF
                            )
                        end
                        
                        if is_muted then
                            r.ImGui_DrawList_AddCircleFilled(
                                draw_list,
                                dot_x,
                                dots_start_y + (dot_size * 2) + (dot_spacing * 2) + dot_size/2,
                                dot_size/2,
                                0xFF8C00FF
                            )
                        end
                    end
                end
            end
        end
        r.ImGui_End(ctx)
    end

    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 2)
    r.ImGui_PopFont(ctx)

    if settings.show_settings_button then
        r.ImGui_SetNextWindowPos(ctx, settings.button_x, settings.button_y, r.ImGui_Cond_Once())
        local button_flags = r.ImGui_WindowFlags_NoTitleBar() | 
                            r.ImGui_WindowFlags_TopMost() |
                            r.ImGui_WindowFlags_NoResize() |
                            r.ImGui_WindowFlags_AlwaysAutoResize()
        
        local button_visible = r.ImGui_Begin(ctx, '##Settings Button', true, button_flags)
        if button_visible then
            settings.button_x, settings.button_y = r.ImGui_GetWindowPos(ctx)
            
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4.0)
            r.ImGui_PushFont(ctx, settings_font)
            if r.ImGui_Button(ctx, "S") then
                settings_visible = not settings_visible
                r.SetExtState("TK_TRACKNAMES", "settings_visible", settings_visible and "1" or "0", false)
            end
            r.ImGui_PopFont(ctx)
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_End(ctx)
        end
    end

    if settings_visible then
        ShowSettingsWindow()
    end

    if needs_font_update then
        ctx = r.ImGui_CreateContext('Track Names')
        CreateFonts()
        needs_font_update = false
    end

    if open then
        script_active = true
        r.defer(loop)
    else
        if script_active then
            if settings.autosave_enabled then
                SaveSettings()
            end
            script_active = false
        end
    end
end

-- Script initialization and cleanup
local success = pcall(function()
    color_cache = {}
    cached_bg_color = nil
    
    LoadSettings()
    CreateFonts()
    if settings.custom_colors_enabled then
        grid_divide_state = r.GetToggleCommandState(42331)
        if grid_divide_state == 1 then
            r.Main_OnCommand(42331, 0)
        end
        UpdateGridColors()
        UpdateBackgroundColors()
    end
    SetButtonState(1)
    r.defer(loop)
end)


r.atexit(function() 
    SetButtonState(0) 
    if settings.autosave_enabled then
        SaveSettings()
    end
    
    -- Reset ALL theme colors
    r.SetThemeColor("col_gridlines", -1, 0)
    r.SetThemeColor("col_gridlines2", -1, 0)
    r.SetThemeColor("col_gridlines3", -1, 0)
    r.SetThemeColor("col_arrangebg", -1, 0)
    r.SetThemeColor("col_tr1_bg", -1, 0)
    r.SetThemeColor("col_tr2_bg", -1, 0)
    r.SetThemeColor("selcol_tr1_bg", -1, 0)
    r.SetThemeColor("selcol_tr2_bg", -1, 0)
    r.SetThemeColor("col_tr1_divline", -1, 0)
    r.SetThemeColor("col_tr2_divline", -1, 0)
    
    -- Restore grid divide if it was on
    if grid_divide_state == 1 then
        r.Main_OnCommand(42331, 0)
    end
    
    r.UpdateArrange()
    r.TrackList_AdjustWindows(false)
end)



if not success then
    r.ShowConsoleMsg("Script error occurred\n")
end





