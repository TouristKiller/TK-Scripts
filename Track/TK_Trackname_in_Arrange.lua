-- @description TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 0.8.6
-- @changelog 
--[[
+ Added hide tekst /label for selected track(s)
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
local grid_divide_state  = 0

local color_cache        = {}
local cached_bg_color    = nil

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
                           r.ImGui_WindowFlags_NoMouseInputs() |
                           r.ImGui_WindowFlags_NoFocusOnAppearing()

local settings_flags     = r.ImGui_WindowFlags_NoTitleBar() | 
                           r.ImGui_WindowFlags_TopMost() |
                           r.ImGui_WindowFlags_NoResize() 



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

local default_settings              = {
    text_opacity                    = 1.0,
    show_parent_tracks              = true,
    show_child_tracks               = false,
    show_first_fx                   = false,
    show_parent_label               = false,
    show_record_color               = true,
    horizontal_offset               = 100,
    vertical_offset                 = 0,
    selected_font                   = 1,
    color_mode                      = 1,
    overlay_alpha                   = 0.1,
    show_track_colors               = true,
    grid_color                      = 0.0,
    bg_brightness                   = 0.2,
    envelope_color_intensity        = 1.0,
    custom_colors_enabled           = false,
    show_label                      = true,
    label_alpha                     = 0.3,
    label_color_mode                = 1,
    text_centered                   = false,
    show_settings_button            = false,
    text_size                       = 14,
    inherit_parent_color            = false,
    deep_inherit_color              = false,
    right_align                     = false,
    show_parent_colors              = true,
    show_child_colors               = true,
    show_normal_colors              = true,
    show_envelope_colors            = true,
    blend_mode                      = 1,
    show_track_numbers              = false,
    track_number_style              = 1,
    autosave_enabled                = false,
    gradient_enabled                = false,
    gradient_direction              = 1,
    gradient_start_alpha            = 1.0,
    gradient_end_alpha              = 0.0,
    track_name_length               = 1,
    all_text_enabled                = true,
    folder_border                   = false,
    folder_border_left              = true,
    folder_border_right             = true,
    folder_border_top               = true,
    folder_border_bottom            = true,
    track_border                    = false,
    track_border_left               = true,
    track_border_right              = true,
    track_border_top                = true,
    track_border_bottom             = true,
    border_thickness                = 2.0,
    border_opacity                  = 1.0,
    button_x                        = 100,
    button_y                        = 100,
    gradient_start_alpha_cached     = 0,
    gradient_end_alpha_cached       = 0,
    darker_parent_tracks            = false,
    parent_darkness                 = 0.7,
    darker_parent_opacity           = 1.0,
    nested_parents_darker           = false,
    show_info_line                  = false,
    color_gradient_enabled          = false,
    bg_brightness_tr1               = 0.2,
    bg_brightness_tr2               = 0.2,
    sel_brightness_tr1              = 0.3,  
    sel_brightness_tr2              = 0.3,
    show_envelope_names             = false,
    envelope_text_opacity           = 0.8,
    grid_color_enabled              = true,
    bg_brightness_enabled           = true,
    master_track_color              = 0x6699FFFF,
    use_custom_master_color         = true,
    master_overlay_alpha            = 1.0,  
    master_gradient_enabled         = true,  
    master_gradient_start_alpha     = 1.0,
    master_gradient_end_alpha       = 0.0,
    text_hover_hide                 = false,
    text_hover_enabled              = false,
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
    settings_font = r.ImGui_CreateFont('Arial', 14)
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

function UpdateBgColorCache()
    cached_bg_color = reaper.GetThemeColor("col_arrangebg", 0)
end

function GetCachedColor(native_color, alpha)
    if not native_color then 
        native_color = settings.master_track_color 
    end
    
    local cache_key = tostring(native_color) .. "_" .. tostring(alpha)
    
    if not color_cache[cache_key] then
        local r, g, b = reaper.ColorFromNative(native_color)
        color_cache[cache_key] = reaper.ImGui_ColorConvertDouble4ToU32(r/255, g/255, b/255, alpha)
    end
    
    return color_cache[cache_key]
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
        
        if settings.custom_colors_enabled then
            UpdateGridColors()    -- Direct updaten van grid kleuren
            UpdateArrangeBG()
    	    UpdateTrackColors() -- Direct updaten van achtergrond kleuren
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
    if not settings.grid_color_enabled then
        reaper.SetThemeColor("col_gridlines", -1, 0)
        reaper.SetThemeColor("col_gridlines2", -1, 0)
        reaper.SetThemeColor("col_gridlines3", -1, 0)
        reaper.SetThemeColor("col_tr1_divline", -1, 0)
        reaper.SetThemeColor("col_tr2_divline", -1, 0)
        return
    end
    local grid_value = (settings.grid_color * 255)//1
    reaper.SetThemeColor("col_gridlines", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines2", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_gridlines3", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr1_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.SetThemeColor("col_tr2_divline", reaper.ColorToNative(grid_value, grid_value, grid_value), 0)
    reaper.UpdateArrange()
end

function UpdateArrangeBG()
    if not settings.bg_brightness_enabled then
        reaper.SetThemeColor("col_arrangebg", -1, 0)
    else
        local MIN_BG_VALUE = 13
        local bg_value = math.max((settings.bg_brightness * 255)//1, MIN_BG_VALUE)
        reaper.SetThemeColor("col_arrangebg", reaper.ColorToNative(bg_value, bg_value, bg_value), 0)
    end
    reaper.UpdateArrange()
end

function UpdateTrackColors()
    local MIN_BG_VALUE = 13
    local bg_value_tr1 = math.max((settings.bg_brightness_tr1 * 255)//1, MIN_BG_VALUE)
    local bg_value_tr2 = math.max((settings.bg_brightness_tr2 * 255)//1, MIN_BG_VALUE)
    local sel_value_tr1 = math.max((settings.sel_brightness_tr1 * 255)//1, MIN_BG_VALUE)
    local sel_value_tr2 = math.max((settings.sel_brightness_tr2 * 255)//1, MIN_BG_VALUE)
    
    reaper.SetThemeColor("col_tr1_bg", reaper.ColorToNative(bg_value_tr1, bg_value_tr1, bg_value_tr1), 0)
    reaper.SetThemeColor("col_tr2_bg", reaper.ColorToNative(bg_value_tr2, bg_value_tr2, bg_value_tr2), 0)
    reaper.SetThemeColor("selcol_tr1_bg", reaper.ColorToNative(sel_value_tr1, sel_value_tr1, sel_value_tr1), 0)
    reaper.SetThemeColor("selcol_tr2_bg", reaper.ColorToNative(sel_value_tr2, sel_value_tr2, sel_value_tr2), 0)
    reaper.UpdateArrange()
end



function RefreshProjectState()
    UpdateBgColorCache()
    if settings.custom_colors_enabled then
        UpdateGridColors()
        UpdateArrangeBG()
        UpdateTrackColors()
        
    end
    reaper.UpdateArrange()
    last_update_time = 0
end

function ToggleColors()
    settings.custom_colors_enabled = not settings.custom_colors_enabled
    if settings.custom_colors_enabled then
        grid_divide_state = r.GetToggleCommandState(42331)
        if grid_divide_state == 1 then             
            r.Main_OnCommand(42331, 0)
        end
        UpdateGridColors()
        UpdateArrangeBG()
        UpdateTrackColors()
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

function BlendColor(track, blend, mode)
    -- Bepaal eerst of het een even of oneven track is
    local track_number = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
    local is_selected = r.IsTrackSelected(track)
    
    -- Kies de juiste achtergrondkleur
    local base
    if is_selected then
        base = track_number % 2 == 0 
            and r.ColorToNative((settings.sel_brightness_tr2 * 255)//1, (settings.sel_brightness_tr2 * 255)//1, (settings.sel_brightness_tr2 * 255)//1)
            or r.ColorToNative((settings.sel_brightness_tr1 * 255)//1, (settings.sel_brightness_tr1 * 255)//1, (settings.sel_brightness_tr1 * 255)//1)
    else
        base = track_number % 2 == 0 
            and r.ColorToNative((settings.bg_brightness_tr2 * 255)//1, (settings.bg_brightness_tr2 * 255)//1, (settings.bg_brightness_tr2 * 255)//1)
            or r.ColorToNative((settings.bg_brightness_tr1 * 255)//1, (settings.bg_brightness_tr1 * 255)//1, (settings.bg_brightness_tr1 * 255)//1)
    end

    local cache_key = "blend_" .. base .. "_" .. blend .. "_" .. mode
    if color_cache[cache_key] then return color_cache[cache_key] end

    local base_r, base_g, base_b = reaper.ColorFromNative(base)
    local blend_r, blend_g, blend_b = reaper.ColorFromNative(blend)
    local result_r, result_g, result_b
    
    -- Hulpfuncties voor nauwkeurigere berekeningen
    local function normalize(value) return value / 255.0 end
    local function denormalize(value) return math.floor(value * 255 + 0.5) end
    local function clamp(value) return math.max(0, math.min(255, value)) end

    -- Genormaliseerde waarden
    local nb_r, nb_g, nb_b = normalize(base_r), normalize(base_g), normalize(base_b)
    local nbl_r, nbl_g, nbl_b = normalize(blend_r), normalize(blend_g), normalize(blend_b)

    if mode == 1 then -- Normal
        return blend
    elseif mode == 2 then -- Multiply
        result_r = denormalize(nb_r * nbl_r)
        result_g = denormalize(nb_g * nbl_g)
        result_b = denormalize(nb_b * nbl_b)
    elseif mode == 3 then -- Screen
        result_r = denormalize(1 - (1 - nb_r) * (1 - nbl_r))
        result_g = denormalize(1 - (1 - nb_g) * (1 - nbl_g))
        result_b = denormalize(1 - (1 - nb_b) * (1 - nbl_b))
    elseif mode == 4 then -- Overlay
        result_r = denormalize(nb_r < 0.5 and (2 * nb_r * nbl_r) or (1 - 2 * (1 - nb_r) * (1 - nbl_r)))
        result_g = denormalize(nb_g < 0.5 and (2 * nb_g * nbl_g) or (1 - 2 * (1 - nb_g) * (1 - nbl_g)))
        result_b = denormalize(nb_b < 0.5 and (2 * nb_b * nbl_b) or (1 - 2 * (1 - nb_b) * (1 - nbl_b)))
    elseif mode == 5 then -- Darken
        result_r = denormalize(math.min(nb_r, nbl_r))
        result_g = denormalize(math.min(nb_g, nbl_g))
        result_b = denormalize(math.min(nb_b, nbl_b))
    elseif mode == 6 then -- Lighten
        result_r = denormalize(math.max(nb_r, nbl_r))
        result_g = denormalize(math.max(nb_g, nbl_g))
        result_b = denormalize(math.max(nb_b, nbl_b))
    elseif mode == 7 then -- Color Dodge
        result_r = denormalize(nb_r == 0 and 0 or nbl_r == 1 and 1 or math.min(1, nb_r / (1 - nbl_r)))
        result_g = denormalize(nb_g == 0 and 0 or nbl_g == 1 and 1 or math.min(1, nb_g / (1 - nbl_g)))
        result_b = denormalize(nb_b == 0 and 0 or nbl_b == 1 and 1 or math.min(1, nb_b / (1 - nbl_b)))
    elseif mode == 8 then -- Color Burn
        result_r = denormalize(nb_r == 1 and 1 or nbl_r == 0 and 0 or 1 - math.min(1, (1 - nb_r) / nbl_r))
        result_g = denormalize(nb_g == 1 and 1 or nbl_g == 0 and 0 or 1 - math.min(1, (1 - nb_g) / nbl_g))
        result_b = denormalize(nb_b == 1 and 1 or nbl_b == 0 and 0 or 1 - math.min(1, (1 - nb_b) / nbl_b))
    elseif mode == 9 then -- Hard Light
        result_r = denormalize(nbl_r < 0.5 and (2 * nb_r * nbl_r) or (1 - 2 * (1 - nb_r) * (1 - nbl_r)))
        result_g = denormalize(nbl_g < 0.5 and (2 * nb_g * nbl_g) or (1 - 2 * (1 - nb_g) * (1 - nbl_g)))
        result_b = denormalize(nbl_b < 0.5 and (2 * nb_b * nbl_b) or (1 - 2 * (1 - nb_b) * (1 - nbl_b)))
    elseif mode == 10 then -- Soft Light
        local function softlight(a, b)
            if b < 0.5 then
                return 2 * a * b + a * a * (1 - 2 * b)
            else
                return 2 * a * (1 - b) + math.sqrt(a) * (2 * b - 1)
            end
        end
        result_r = denormalize(softlight(nb_r, nbl_r))
        result_g = denormalize(softlight(nb_g, nbl_g))
        result_b = denormalize(softlight(nb_b, nbl_b))
    end

    local result = reaper.ColorToNative(clamp(result_r), clamp(result_g), clamp(result_b))
    color_cache[cache_key] = result
    return result
end

function GetReaperMousePosition()
    local x, y = reaper.GetMousePosition()
    x, y = reaper.JS_Window_ScreenToClient(arrange, x, y)
    return x, y
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

function GetMasterTrackColor()
    local master = r.GetMasterTrack(0)
    local color = r.GetTrackColor(master)
    
    if color == 0 and settings.use_custom_master_color then
        return settings.master_native_color
    end
    
    return color
end

function ShowSettingsWindow()
    if not settings_visible then return end
    
    -- Use Sexan's positioning
    local _, DPI_RPR = r.get_config_var_string("uiscale")
    local window_x = LEFT + (RIGHT - LEFT - 520) / 2  -- Center horizontally
    local window_y = TOP + (BOT - TOP - 520) / 2      -- Center vertically
    
    r.ImGui_SetNextWindowPos(ctx, window_x, window_y, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSize(ctx, 520, -1)
    
    -- Style setup
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 8.0)

    -- Colors setup
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x111111D9)  -- D9 = 85% opaque
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x333333FF)        
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x444444FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x555555FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x999999FF)     
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xAAAAAAFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0x999999FF)      
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x333333FF)         
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x444444FF)  
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x555555FF)   
    r.ImGui_PushFont(ctx, settings_font)
    local visible, open = r.ImGui_Begin(ctx, 'Track Names Settings', true, settings_flags)
    
    if visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)  -- Helder rood
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "ARRANGE READECORATOR")
        
        local window_width = r.ImGui_GetWindowWidth(ctx)
        local column_width = window_width / 5

        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 25)
        r.ImGui_SetCursorPosY(ctx, 6)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
        
        if r.ImGui_Button(ctx, "##close", 14, 14) then
            if settings.autosave_enabled then
                SaveSettings()
            end
            r.SetExtState("TK_TRACKNAMES", "settings_visible", "0", false)
        end
        r.ImGui_PopStyleColor(ctx, 3)
        --r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0xFF0000FF) -- Donkerrood
        r.ImGui_Separator(ctx)
        --r.ImGui_PopStyleColor(ctx)

        -- PRESETS
        if r.ImGui_Button(ctx, "Save Preset" , 90) then
            r.ImGui_OpenPopup(ctx, "Save Preset##popup")
        end
        r.ImGui_SameLine(ctx, column_width)
        local presets = GetPresetList()
        r.ImGui_SetNextItemWidth(ctx, 90)
        if r.ImGui_BeginCombo(ctx, "##Load Preset", "Select Preset") then
            for _, preset_name in ipairs(presets) do
                local is_clicked = r.ImGui_Selectable(ctx, preset_name)
                if r.ImGui_BeginPopupContextItem(ctx) then
                    if r.ImGui_MenuItem(ctx, "Delete") then
                        os.remove(preset_path .. preset_name .. '.json')
                    end
                    r.ImGui_EndPopup(ctx)
                end
                if is_clicked then
                    LoadPreset(preset_name)
                end
            end
            r.ImGui_EndCombo(ctx)
        end
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
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_Button(ctx, settings.custom_colors_enabled and "Reset Colors" or "Custom Colors", 90) then
            reaper.Undo_BeginBlock()
            ToggleColors()
            reaper.Undo_EndBlock("Toggle Custom Grid and Background Colors", -1)
        end
        r.ImGui_SameLine(ctx, column_width * 3)
        if r.ImGui_Button(ctx, "Reset Settings", 90) then
            ResetSettings()
        end
        r.ImGui_SameLine(ctx, column_width * 4)
        if r.ImGui_Button(ctx, "Save Settings", 90) then 
            SaveSettings()
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
      
        local changed
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 1, 1)
        if r.ImGui_RadioButton(ctx, "Parent Track", settings.show_parent_tracks) then
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
        if r.ImGui_RadioButton(ctx, "Show button", settings.show_settings_button) then
            settings.show_settings_button = not settings.show_settings_button
        end
        r.ImGui_SameLine(ctx, column_width * 4)
        if r.ImGui_RadioButton(ctx, "Autosave", settings.autosave_enabled) then
            settings.autosave_enabled = not settings.autosave_enabled
        end
        if r.ImGui_RadioButton(ctx, "Track Label", settings.show_label) then
            settings.show_label = not settings.show_label
        end
        r.ImGui_SameLine(ctx, column_width)
        if r.ImGui_RadioButton(ctx, "Parent label", settings.show_parent_label) then
            settings.show_parent_label = not settings.show_parent_label
            needs_font_update = CheckNeedsUpdate()
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_RadioButton(ctx, "Center", settings.text_centered) then
            settings.text_centered = not settings.text_centered
        end
        r.ImGui_SameLine(ctx, column_width * 3)
        if r.ImGui_RadioButton(ctx, "Right align", settings.right_align) then
            settings.right_align = not settings.right_align
        end
        r.ImGui_SameLine(ctx, column_width * 4)
        if r.ImGui_RadioButton(ctx, "Info Line", settings.show_info_line) then
            settings.show_info_line = not settings.show_info_line
        end
        if r.ImGui_RadioButton(ctx, "Track #", settings.show_track_numbers) then
            settings.show_track_numbers = not settings.show_track_numbers
        end
        r.ImGui_BeginDisabled(ctx, not settings.show_track_numbers)
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_SetNextItemWidth(ctx, 90)
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
        r.ImGui_EndDisabled(ctx)


        r.ImGui_SameLine(ctx, column_width * 2)
        r.ImGui_Text(ctx, "Name length:")
        r.ImGui_SameLine(ctx, column_width * 3)
        r.ImGui_SetNextItemWidth(ctx, 90)
        if r.ImGui_BeginCombo(ctx, "##Track name length", 
            settings.track_name_length == 1 and " Full length" or
            settings.track_name_length == 2 and " Max 16 chars" or " Max 32 chars") then
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
        r.ImGui_SameLine(ctx, column_width * 4)
        if r.ImGui_RadioButton(ctx, "Env Names", settings.show_envelope_names) then
            settings.show_envelope_names = not settings.show_envelope_names
        end
        if r.ImGui_RadioButton(ctx, "Hide text for selected tracks", settings.text_hover_hide) then
            settings.text_hover_hide = not settings.text_hover_hide
        end
        r.ImGui_SameLine(ctx, column_width * 2)
        if r.ImGui_RadioButton(ctx, "Hide text on hover", settings.text_hover_enabled) then
            settings.text_hover_enabled = not settings.text_hover_enabled
        end

        r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        if r.ImGui_RadioButton(ctx, "Track colors:", settings.show_track_colors) then
            settings.show_track_colors = not settings.show_track_colors
            needs_font_update = true
        end
        if settings.show_track_colors then
            r.ImGui_SameLine(ctx, column_width)
            r.ImGui_SetNextItemWidth(ctx, 90)
            if r.ImGui_BeginCombo(ctx, "##Blend Mode", blend_modes[settings.blend_mode]) then
                for i, mode in ipairs(blend_modes) do
                    if r.ImGui_Selectable(ctx, mode, settings.blend_mode == i) then
                        settings.blend_mode = i
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            r.ImGui_SameLine(ctx, column_width * 2)
            if r.ImGui_RadioButton(ctx, "Gradient:", settings.gradient_enabled) then
                settings.gradient_enabled = not settings.gradient_enabled
            end
            r.ImGui_BeginDisabled(ctx, not settings.gradient_enabled)
                r.ImGui_SameLine(ctx, column_width * 3)
                r.ImGui_SetNextItemWidth(ctx, 90)
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
            r.ImGui_EndDisabled(ctx)

            if r.ImGui_RadioButton(ctx, "Parent Color", settings.show_parent_colors) then
                settings.show_parent_colors = not settings.show_parent_colors
                needs_font_update = CheckTrackColorUpdate()
            end
            r.ImGui_SameLine(ctx, column_width)
            if r.ImGui_RadioButton(ctx, "Child Color", settings.show_child_colors) then
                settings.show_child_colors = not settings.show_child_colors
                needs_font_update = CheckTrackColorUpdate()
            end
            r.ImGui_SameLine(ctx, column_width * 2)
            if r.ImGui_RadioButton(ctx, "Normal Color", settings.show_normal_colors) then
                settings.show_normal_colors = not settings.show_normal_colors
                needs_font_update = CheckTrackColorUpdate()
            end
            r.ImGui_SameLine(ctx, column_width * 3)
            if r.ImGui_RadioButton(ctx, "Dark Parent", settings.darker_parent_tracks) then
                settings.darker_parent_tracks = not settings.darker_parent_tracks
            end
            r.ImGui_SameLine(ctx, column_width * 4)
            if r.ImGui_RadioButton(ctx, "Dark Nested", settings.nested_parents_darker) then
                settings.nested_parents_darker = not settings.nested_parents_darker
            end
            if r.ImGui_RadioButton(ctx, "Env Color", settings.show_envelope_colors) then
                settings.show_envelope_colors = not settings.show_envelope_colors
            end
            r.ImGui_SameLine(ctx, column_width)
            if r.ImGui_RadioButton(ctx, "Rec color", settings.show_record_color) then
                settings.show_record_color = not settings.show_record_color
            end
            r.ImGui_SameLine(ctx, column_width * 2)
            if r.ImGui_RadioButton(ctx, "Inherit", settings.inherit_parent_color) then
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
            r.ImGui_SameLine(ctx, column_width * 4)
            if settings.show_track_colors then
                if r.ImGui_RadioButton(ctx, "Gradual", settings.color_gradient_enabled) then
                    settings.color_gradient_enabled = not settings.color_gradient_enabled
                end
            end
            if r.ImGui_RadioButton(ctx, "F Borders:", settings.folder_border) then
                settings.folder_border = not settings.folder_border
            end
            r.ImGui_BeginDisabled(ctx, not settings.folder_border)
                r.ImGui_SameLine(ctx, column_width)
                r.ImGui_SetNextItemWidth(ctx, 90)
                if r.ImGui_BeginCombo(ctx, "##Folder Border Options", " Sel Borders") then
                    local clicked, new_state = r.ImGui_Checkbox(ctx, "All Borders", 
                        settings.folder_border_left and
                        settings.folder_border_right and
                        settings.folder_border_top and
                        settings.folder_border_bottom)
                    if clicked then
                        settings.folder_border_left = new_state
                        settings.folder_border_right = new_state
                        settings.folder_border_top = new_state
                        settings.folder_border_bottom = new_state
                    end
                        clicked, settings.folder_border_left = r.ImGui_Checkbox(ctx, "Left Border", settings.folder_border_left)
                        clicked, settings.folder_border_right = r.ImGui_Checkbox(ctx, "Right Border", settings.folder_border_right)
                        clicked, settings.folder_border_top = r.ImGui_Checkbox(ctx, "Top Border", settings.folder_border_top)
                        clicked, settings.folder_border_bottom = r.ImGui_Checkbox(ctx, "Bottom Border", settings.folder_border_bottom)
                        r.ImGui_EndCombo(ctx)
                 end
            r.ImGui_EndDisabled(ctx)


                r.ImGui_SameLine(ctx, column_width * 2)
                if r.ImGui_RadioButton(ctx, "T Borders:", settings.track_border) then
                    settings.track_border = not settings.track_border
                end
                r.ImGui_BeginDisabled(ctx, not settings.track_border)
                    r.ImGui_SameLine(ctx, column_width * 3)
                    r.ImGui_SetNextItemWidth(ctx, 90)
                    if r.ImGui_BeginCombo(ctx, "##Track Border Options", " Sel Borders") then
                        local clicked, new_state = r.ImGui_Checkbox(ctx, "All Borders",
                            settings.track_border_left and
                            settings.track_border_right and
                            settings.track_border_top and
                            settings.track_border_bottom)
                        if clicked then
                            settings.track_border_left = new_state
                            settings.track_border_right = new_state
                            settings.track_border_top = new_state
                            settings.track_border_bottom = new_state
                        end
                        
                        clicked, settings.track_border_left = r.ImGui_Checkbox(ctx, "Left Border", settings.track_border_left)
                        clicked, settings.track_border_right = r.ImGui_Checkbox(ctx, "Right Border", settings.track_border_right)
                        clicked, settings.track_border_top = r.ImGui_Checkbox(ctx, "Top Border", settings.track_border_top)
                        clicked, settings.track_border_bottom = r.ImGui_Checkbox(ctx, "Bottom Border", settings.track_border_bottom)
                        
                    r.ImGui_EndCombo(ctx)
                    end
                r.ImGui_EndDisabled(ctx)   
            end  
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        local Slider_Collumn_2 = 270 
        r.ImGui_PushItemWidth(ctx, 140)
        if settings.show_track_colors then
            if not settings.gradient_enabled then    
                changed, settings.overlay_alpha = r.ImGui_SliderDouble(ctx, "Color Intensity", settings.overlay_alpha, 0.0, 1.0)
            end
            if settings.gradient_enabled then
                changed, settings.gradient_start_alpha = r.ImGui_SliderDouble(ctx, "Start Gradient", settings.gradient_start_alpha, 0.0, 1.0)
                if changed then UpdateGradientAlphaCache() end
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                changed, settings.gradient_end_alpha = r.ImGui_SliderDouble(ctx, "End Gradient", settings.gradient_end_alpha, 0.0, 1.0)
                if changed then UpdateGradientAlphaCache() end
            end
            if settings.show_envelope_colors then
                if settings.gradient_enabled then
                changed, settings.envelope_color_intensity = r.ImGui_SliderDouble(ctx, "Env Intensity", settings.envelope_color_intensity, 0.0, 1.0)
                else
                r.ImGui_SameLine(ctx) 
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                changed, settings.envelope_color_intensity = r.ImGui_SliderDouble(ctx, "Env Intensity", settings.envelope_color_intensity, 0.0, 1.0)
                end
            end
            
            r.ImGui_SetNextItemWidth(ctx, 140)
            if settings.gradient_enabled then
            r.ImGui_SameLine(ctx)    
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            changed, settings.envelope_text_opacity = r.ImGui_SliderDouble(ctx, "Env Text Opacity", settings.envelope_text_opacity, 0.0, 1.0)
            else
            changed, settings.envelope_text_opacity = r.ImGui_SliderDouble(ctx, "Env Text Opacity", settings.envelope_text_opacity, 0.0, 1.0)   
            end
            if settings.darker_parent_tracks then
                changed, settings.parent_darkness = r.ImGui_SliderDouble(ctx, "Parent Darkness", settings.parent_darkness, 0.1, 1.0)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                changed, settings.darker_parent_opacity = r.ImGui_SliderDouble(ctx, "Parent Opacity", settings.darker_parent_opacity, 0.0, 1.0)
            end
            
            if (settings.folder_border and settings.show_parent_colors) or 
            (settings.track_border and settings.show_normal_colors) then    
                changed, settings.border_thickness = r.ImGui_SliderDouble(ctx, "Border Thickness", settings.border_thickness, 1, 20.0)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                changed, settings.border_opacity = r.ImGui_SliderDouble(ctx, "Border Opacity", settings.border_opacity, 0.0, 1.0)     
            end               
        end
        if settings.show_label then                            
            changed, settings.label_alpha = r.ImGui_SliderDouble(ctx, "Label Opacity", settings.label_alpha, 0.0, 1.0)
            local label_combo_pos_x = LEFT + settings.horizontal_offset
            local label_combo_pos_y = WY + settings.vertical_offset 
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            if r.ImGui_BeginCombo(ctx, "Label Color", color_modes[settings.label_color_mode]) then
                for i, color_name in ipairs(color_modes) do
                    if r.ImGui_Selectable(ctx, color_name, settings.label_color_mode == i) then
                        settings.label_color_mode = i
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
        end
        changed, settings.horizontal_offset = r.ImGui_SliderInt(ctx, "Horizontal Offset", settings.horizontal_offset, 0, RIGHT - LEFT)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
        changed, settings.vertical_offset = r.ImGui_SliderInt(ctx, "Vertical Offset", settings.vertical_offset, -50, 50)
        if r.ImGui_BeginCombo(ctx, "Font Selection", fonts[settings.selected_font]) then
            for i, font_name in ipairs(fonts) do
                if r.ImGui_Selectable(ctx, font_name, settings.selected_font == i) then
                    settings.selected_font = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
        if r.ImGui_BeginCombo(ctx, "Text Color", color_modes[settings.color_mode]) then
            for i, color_name in ipairs(color_modes) do
                if r.ImGui_Selectable(ctx, color_name, settings.color_mode == i) then
                    settings.color_mode = i
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_BeginCombo(ctx, "Text Size", tostring(settings.text_size)) then
            for _, size in ipairs(text_sizes) do
                if r.ImGui_Selectable(ctx, tostring(size), settings.text_size == size) then
                    settings.text_size = size
                    needs_font_update = true
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
        changed, settings.text_opacity = r.ImGui_SliderDouble(ctx, "Text Opacity", settings.text_opacity, 0.0, 1.0)
        
        if settings.custom_colors_enabled then
            r.ImGui_Dummy(ctx, 0, 2)
            r.ImGui_Separator(ctx)
            r.ImGui_Dummy(ctx, 0, 2)
        
            r.ImGui_BeginDisabled(ctx, not settings.grid_color_enabled)
            r.ImGui_SetNextItemWidth(ctx, 110)
            changed_grid, settings.grid_color = r.ImGui_SliderDouble(ctx, "Grid Color", settings.grid_color, 0.0, 1.0)
            r.ImGui_EndDisabled(ctx)
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "Grid##toggle", settings.grid_color_enabled) then
                settings.grid_color_enabled = not settings.grid_color_enabled
                if not settings.grid_color_enabled then
                    r.SetThemeColor("col_gridlines", -1, 0)
                    r.SetThemeColor("col_gridlines2", -1, 0)
                    r.SetThemeColor("col_gridlines3", -1, 0)
                    r.SetThemeColor("col_tr1_divline", -1, 0)
                    r.SetThemeColor("col_tr2_divline", -1, 0)
                    r.UpdateArrange()
                else
                    UpdateGridColors()
                end
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            r.ImGui_BeginDisabled(ctx, not settings.bg_brightness_enabled)
            r.ImGui_SetNextItemWidth(ctx, 110)
            changed_bg, settings.bg_brightness = r.ImGui_SliderDouble(ctx, "Bg Brightness", settings.bg_brightness, 0.0, 1.0)
            r.ImGui_EndDisabled(ctx)
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "BG##toggle", settings.bg_brightness_enabled) then
                settings.bg_brightness_enabled = not settings.bg_brightness_enabled
                if not settings.bg_brightness_enabled then
                    r.SetThemeColor("col_arrangebg", -1, 0)
                    r.UpdateArrange()
                else
                    UpdateArrangeBG()
                end
            end
            
            changed_bg_tr1, settings.bg_brightness_tr1 = r.ImGui_SliderDouble(ctx, "Track (odd) ", settings.bg_brightness_tr1, 0.0, 1.0)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            changed_sel_tr1, settings.sel_brightness_tr1 = r.ImGui_SliderDouble(ctx, "Sel Track (odd)", settings.sel_brightness_tr1, 0.0, 1.0)
            changed_bg_tr2, settings.bg_brightness_tr2 = r.ImGui_SliderDouble(ctx, "Track (even) ", settings.bg_brightness_tr2, 0.0, 1.0)
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            changed_sel_tr2, settings.sel_brightness_tr2 = r.ImGui_SliderDouble(ctx, "Sel Track (even)", settings.sel_brightness_tr2, 0.0, 1.0)
            if changed_grid and settings.grid_color_enabled then
                UpdateGridColors()
            end
            if changed_bg and settings.bg_brightness_enabled then
                UpdateArrangeBG()
            end
            if changed_bg_tr1 or changed_bg_tr2 or changed_sel_tr1 or changed_sel_tr2 then
                UpdateTrackColors()
            end
        end

        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Master Track Settings")
        
        changed, settings.use_custom_master_color = r.ImGui_Checkbox(ctx, "Use Custom Master Color", settings.use_custom_master_color)
        
        if settings.use_custom_master_color then
            r.ImGui_SameLine(ctx)
            if r.ImGui_ColorButton(ctx, "Master Track Color##master", settings.master_track_color) then
                r.ImGui_OpenPopup(ctx, "MasterColorPopup")
            end
            
            if r.ImGui_BeginPopup(ctx, "MasterColorPopup") then
                local changed, new_color = r.ImGui_ColorEdit4(ctx, "Master Color", settings.master_track_color)
                if changed then settings.master_track_color = new_color end
                r.ImGui_EndPopup(ctx)
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
            r.ImGui_BeginDisabled(ctx, settings.master_gradient_enabled)
            changed, settings.master_overlay_alpha = r.ImGui_SliderDouble(ctx, "Intensity", settings.master_overlay_alpha, 0.0, 1.0)
            r.ImGui_EndDisabled(ctx)

            changed, settings.master_gradient_enabled = r.ImGui_Checkbox(ctx, "Gradient", settings.master_gradient_enabled)
            if settings.master_gradient_enabled then
                r.ImGui_SameLine(ctx)
                r.ImGui_SetCursorPosX(ctx, Slider_Collumn_2)
                r.ImGui_SetNextItemWidth(ctx, 70)
                changed, settings.master_gradient_start_alpha = r.ImGui_SliderDouble(ctx, "Start", settings.master_gradient_start_alpha, 0.0, 1.0)
                r.ImGui_SameLine(ctx)
                r.ImGui_SetNextItemWidth(ctx, 70)
                changed, settings.master_gradient_end_alpha = r.ImGui_SliderDouble(ctx, "End", settings.master_gradient_end_alpha, 0.0, 1.0)
            end
        end
        

        r.ImGui_PopItemWidth(ctx)
        r.ImGui_End(ctx)
        
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 5)
    r.ImGui_PopStyleColor(ctx, 10)
end

function IsTrackVisible(track)
    local MIN_TRACK_HEIGHT = 10
    local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
    return track_height > MIN_TRACK_HEIGHT
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
  
function RenderGradientOverlay(draw_list, track, track_y, track_height, color, window_y, is_parent)    
    local background_draw_list = r.ImGui_GetBackgroundDrawList(ctx)
    
    if is_parent and settings.darker_parent_tracks and 
       (not r.GetParentTrack(track) or settings.nested_parents_darker) then
        r.ImGui_DrawList_AddRectFilled(
            background_draw_list,
            LEFT,
            window_y + track_y,
            RIGHT - scroll_size,
            window_y + track_y + track_height,
            color
        )
    else
        RenderGradientRect(
            background_draw_list,
            LEFT,
            window_y + track_y,
            RIGHT - scroll_size,
            window_y + track_y + track_height,
            color
        )
    end
    
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
    r.ImGui_DrawList_AddLine(draw_list,x1,y1,x2,y2,color,thickness)
end

function DrawTrackBorderLine(draw_list,x1,y1,x2,y2,color,thickness)
    r.ImGui_DrawList_AddLine(draw_list,x1, y1, x2, y2,color,thickness)
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

function DrawFolderBorders(draw_list, track, track_y, track_height, border_color, WY)
    local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
    if depth == 1 then
        local start_idx, end_idx = GetFolderBoundaries(track)
        if start_idx and end_idx then
            -- Check voor zichtbare child tracks
            local has_visible_children = false
            for i = start_idx + 1, end_idx do
                local child = r.GetTrack(0, i)
                local child_height = r.GetMediaTrackInfo_Value(child, "I_TCPH") / screen_scale
                if child_height > 0 then
                    has_visible_children = true
                    break
                end
            end
            
            if has_visible_children then
                local end_track = r.GetTrack(0, end_idx)
                local end_y = r.GetMediaTrackInfo_Value(end_track, "I_TCPY") /screen_scale
                local end_height = r.GetMediaTrackInfo_Value(end_track, "I_TCPH") /screen_scale
                local total_height = (end_y + end_height) - track_y
                
                -- Teken de borders
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
end

function GetDarkerColor(color)
    local r_val, g_val, b_val = r.ColorFromNative(color)
    return r.ColorToNative(
        (r_val * settings.parent_darkness)//1,
        (g_val * settings.parent_darkness)//1,
        (b_val * settings.parent_darkness)//1
    )
end

function GetLighterColor(color, step, total_steps)
    local red, g, b = reaper.ColorFromNative(color)
    local h, s, v = reaper.ImGui_ColorConvertRGBtoHSV(red/255, g/255, b/255)
    local v_step = (1.0 - v) / (total_steps * 0.5)  
    local s_step = (s * 0.8) / total_steps         
    v = v + (v_step * step)
    s = s - (s_step * step)
    v = math.min(v, 1.0)
    s = math.max(s, 0.0)
    local red, g, b = reaper.ImGui_ColorConvertHSVtoRGB(h, s, v)
    return reaper.ColorToNative(
        math.floor(red * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5)
    )
end

function GetFolderInfo(track)
    local totals = {
        fx = r.TrackFX_GetCount(track),
        sends = r.GetTrackNumSends(track, 0),
        receives = r.GetTrackNumSends(track, -1),
        envelopes = r.CountTrackEnvelopes(track),
        items = r.GetTrackNumMediaItems(track),
        armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1 and 1 or 0,
        muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1 and 1 or 0,
        soloed = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0 and 1 or 0,
        tracks = 1,
        folder_tracks = 0
    }
    
    local idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
    local depth = 1
    
    while depth > 0 and idx < r.CountTracks(0) - 1 do
        local child = r.GetTrack(0, idx + 1)
        depth = depth + r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
        totals.tracks = totals.tracks + 1
        totals.folder_tracks = totals.folder_tracks + 1
        totals.fx = totals.fx + r.TrackFX_GetCount(child)
        totals.sends = totals.sends + r.GetTrackNumSends(child, 0)
        totals.receives = totals.receives + r.GetTrackNumSends(child, -1)
        totals.envelopes = totals.envelopes + r.CountTrackEnvelopes(child)
        totals.items = totals.items + r.GetTrackNumMediaItems(child)
        totals.armed = totals.armed + (r.GetMediaTrackInfo_Value(child, "I_RECARM") == 1 and 1 or 0)
        totals.muted = totals.muted + (r.GetMediaTrackInfo_Value(child, "B_MUTE") == 1 and 1 or 0)
        totals.soloed = totals.soloed + (r.GetMediaTrackInfo_Value(child, "I_SOLO") > 0 and 1 or 0)
        idx = idx + 1
    end
    
    return string.format("Total Tracks: %d(%d) | FX: %d | Sends/Rec: %d | Env: %d | Items: %d | %s | Rec: %d | Mute: %d | Solo: %d",
        totals.tracks, totals.folder_tracks, totals.fx, totals.sends + totals.receives, totals.envelopes, totals.items,
        has_automation and "Auto" or "No Auto", totals.armed, totals.muted, totals.soloed)
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

function ShouldHideTrackElements(track)
    return settings.text_hover_hide and r.IsTrackSelected(track)
end


function IsMouseOverTrack(track_y, track_height, WY)
    local x, y = r.GetMousePosition()
    local window = r.JS_Window_FromPoint(x, y)
    
    if window and r.JS_Window_GetTitle(window) == "trackview" then
        x, y = r.JS_Window_ScreenToClient(arrange, x, y)
        y = y / screen_scale
        return y >= track_y and y <= track_y + track_height
    end
    return false
end


--[[profiler.attachToWorld()
profiler.run()
profiler.start()]]--
function loop()
    if r.GetExtState("TK_TRACKNAMES", "reload_settings") == "1" then
        LoadSettings()
        r.SetExtState("TK_TRACKNAMES", "reload_settings", "0", false)
    end
    

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

        for i = -1, track_count - 1 do  -- -1 voor master track
            local track
            if i == -1 then
                track = r.GetMasterTrack(0)
            else
                track = r.GetTrack(0, i)
            end
            
            local is_master = (i == -1)

            if is_master then
                local master_visible = r.GetMasterTrackVisibility()
                local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") /screen_scale
                local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") /screen_scale
                if master_visible == 1 then
                    if settings.show_track_colors and settings.use_custom_master_color then
                        if settings.master_gradient_enabled then
                            -- Converteer de alpha waardes naar de juiste schaal (0-255)
                            local start_alpha = (settings.master_gradient_start_alpha * 255)//1
                            local end_alpha = (settings.master_gradient_end_alpha * 255)//1
                            
                            -- Pas beide alpha waardes toe op de master kleur
                            local start_color = (settings.master_track_color & 0xFFFFFF00) | start_alpha
                            local end_color = (settings.master_track_color & 0xFFFFFF00) | end_alpha
                            
                            -- Render de gradient met beide kleuren
                            r.ImGui_DrawList_AddRectFilledMultiColor(
                                draw_list, 
                                LEFT, 
                                WY + track_y,
                                RIGHT - scroll_size,
                                WY + track_y + track_height,
                                start_color,
                                settings.gradient_direction == 1 and end_color or start_color,
                                settings.gradient_direction == 1 and end_color or start_color,
                                start_color
                            )
                        else
                            local red, green, blue, _ = r.ImGui_ColorConvertU32ToDouble4(settings.master_track_color)
                            local color_with_alpha = r.ImGui_ColorConvertDouble4ToU32(red, green, blue, settings.master_overlay_alpha)
                            RenderSolidOverlay(draw_list, track, track_y, track_height, color_with_alpha, WY)
                        end
                    end
                    local text = "MASTER"
                    local text_width = r.ImGui_CalcTextSize(ctx, text)
                    local text_y = WY + track_y + (track_height * 0.5) - (settings.text_size * 0.5)
                    local text_x = WX + settings.horizontal_offset
                    
                    if settings.text_centered then
                        local offset = (max_width - text_width) / 2
                        text_x = WX + settings.horizontal_offset + offset
                    elseif settings.right_align then
                        text_x = RIGHT - scroll_size - text_width - 20 - settings.horizontal_offset
                    end
                    
                    local text_color = GetTextColor(track)
                    text_color = (text_color & 0xFFFFFF00) | ((settings.text_opacity * 255)//1)
                
                    r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, text)
                end
            else
            
             
                local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") /screen_scale
                local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") /screen_scale
                local is_parent = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") == 1
                local is_child = r.GetParentTrack(track) ~= nil
                local track_color = r.GetTrackColor(track)
                
                -- Folder borders altijd tekenen als de optie aan staat
                if settings.show_track_colors and settings.folder_border and (is_parent or is_child) then
                    local border_base_color = r.GetTrackColor(track)
                    if is_child then
                        local parent = r.GetParentTrack(track)
                        if parent then
                            border_base_color = r.GetTrackColor(parent)
                        end
                    end
                    local darker_color = GetDarkerColor(border_base_color)
                    local border_color = GetCachedColor(darker_color, settings.border_opacity)
                    DrawFolderBorders(draw_list, track, track_y, track_height, border_color, WY)
                end
                
                -- Normale track rendering alleen voor zichtbare tracks
                local track_visible = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1
                if track_visible and IsTrackVisible(track) then
                    local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
                    local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
                    local is_soloed = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
                    local track_number = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
            
                    local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                    max_width = math.max(max_width, text_width)
            
                    -- Track colors
                    if settings.show_track_colors then
                        if ((is_parent and settings.show_parent_colors) or
                            (is_child and settings.show_child_colors) or
                            (not is_parent and not is_child and settings.show_normal_colors)) then
                            
                            local base_color = track_color
                            local main_parent = nil
                            
                            -- Deep inherit logica
                            if settings.deep_inherit_color then
                                -- Deep inherit + gradient logica blijft als hoogste prioriteit
                                local current = track
                                while r.GetParentTrack(current) do
                                    current = r.GetParentTrack(current)
                                    if not r.GetParentTrack(current) then
                                        main_parent = current
                                    end
                                end
                                if main_parent then
                                    base_color = r.GetTrackColor(main_parent)
                                    
                                    if settings.color_gradient_enabled then
                                        local main_parent_idx = r.GetMediaTrackInfo_Value(main_parent, "IP_TRACKNUMBER") - 1
                                        local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
                                        local position = track_idx - main_parent_idx
                                        track_color = GetLighterColor(base_color, position, 5)
                                    else
                                        track_color = base_color
                                    end
                                end
                            elseif settings.color_gradient_enabled and not is_parent then
                                -- Gradient krijgt nu voorrang op normal inherit
                                local parent = r.GetParentTrack(track)
                                if parent then
                                    base_color = r.GetTrackColor(parent)
                                    if base_color == 0 then base_color = track_color end
                                    
                                    local track_position = 0
                                    local parent_idx = r.GetMediaTrackInfo_Value(parent, "IP_TRACKNUMBER") - 1
                                    local current_idx = parent_idx
                                    local current_depth = 0
                                    
                                    while current_depth >= 0 and current_idx < r.CountTracks(0) do
                                        local current_track = r.GetTrack(0, current_idx)
                                        local depth = r.GetMediaTrackInfo_Value(current_track, "I_FOLDERDEPTH")
                                        
                                        if current_track == track then
                                            track_color = GetLighterColor(base_color, track_position, 5)
                                            break
                                        end
                                        
                                        current_depth = current_depth + depth
                                        track_position = track_position + 1
                                        current_idx = current_idx + 1
                                    end
                                end
                            elseif settings.inherit_parent_color and not is_parent then
                                -- Normal inherit heeft nu laagste prioriteit
                                local parent = r.GetParentTrack(track)
                                if parent then
                                    track_color = r.GetTrackColor(parent)
                                end
                            end
                            
                            if settings.show_record_color and IsRecording(track) and r.GetPlayState() == 5 then
                                track_color = r.ColorToNative(255, 0, 0)
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
                                    local blended_color = BlendColor(track, track_color, settings.blend_mode)
                                    local color
                                    
                                    if is_parent and settings.darker_parent_tracks and 
                                    (not r.GetParentTrack(track) or settings.nested_parents_darker) then
                                    local darker_color = GetDarkerColor(blended_color)
                                    color = GetCachedColor(darker_color, settings.darker_parent_opacity)
                                    else
                                    color = GetCachedColor(blended_color, settings.overlay_alpha)
                                    end
                                    
                                    if settings.gradient_enabled then
                                        RenderGradientOverlay(draw_list, track, track_y, track_height, color, WY, is_parent)
                                    else
                                        RenderSolidOverlay(draw_list, track, track_y, track_height, color, WY)
                                    end
                                end
                            end
                        end
                        
                        if settings.track_border and not is_parent and not is_child and track_color ~= 0 then
                            local blended_color = BlendColor(track, track_color, settings.blend_mode)

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

                    if (settings.text_hover_enabled and IsMouseOverTrack(track_y, track_height, WY)) or
                    (settings.text_hover_hide and r.IsTrackSelected(track)) then
                     should_show_track = false
                     should_show_name = false
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
                        if is_child and settings.show_parent_label and not IsMouseOverTrack(track_y, track_height, 0) then
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

                                if settings.show_label and not IsMouseOverTrack(track_y, track_height, WY) then
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
                        
                            if settings.show_label and not IsMouseOverTrack(track_y, track_height, WY) then
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

                            
                            -- Info line na de track naam
                            if settings.show_info_line and not r.GetParentTrack(track) then
                                local info_text = GetFolderInfo(track)
                                local track_text_width = r.ImGui_CalcTextSize(ctx, modified_display_name)
                                local info_text_x
                                
                                if settings.right_align then
                                    info_text_x = text_x - r.ImGui_CalcTextSize(ctx, info_text) - 20
                                else
                                    info_text_x = text_x + track_text_width + 20
                                end
                                
                                r.ImGui_DrawList_AddText(draw_list, info_text_x, text_y, text_color, info_text)
                            end

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
                    if settings.show_envelope_names then
                        local env_count = r.CountTrackEnvelopes(track)
                        for i = 0, env_count - 1 do
                            local env = r.GetTrackEnvelope(track, i)
                            local env_height = r.GetEnvelopeInfo_Value(env, "I_TCPH") / screen_scale
                            local env_y = r.GetEnvelopeInfo_Value(env, "I_TCPY") / screen_scale
                            local in_lane = r.GetEnvelopeInfo_Value(env, "I_TCPH_USED") > 0
                            
                            if in_lane then
                                local retval, env_name = r.GetEnvelopeName(env)
                                local text_width = r.ImGui_CalcTextSize(ctx, env_name)
                                local env_text_x = WX + settings.horizontal_offset
                                if settings.text_centered then
                                    local offset = (max_width - text_width) / 2
                                    env_text_x = WX + settings.horizontal_offset + offset
                                elseif settings.right_align then
                                    env_text_x = RIGHT - scroll_size - text_width - 20 - settings.horizontal_offset
                                end
                                
                                local absolute_env_y = track_y + env_y
                                local text_y = WY + absolute_env_y + (env_height/2) - (settings.text_size/2)
                                
                                local env_color = GetTextColor(track, is_child)
                                env_color = (env_color & 0xFFFFFF00) | ((settings.envelope_text_opacity * 255)//1)
                                r.ImGui_DrawList_AddText(draw_list, env_text_x, text_y, env_color, env_name)
                            end
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
-- In de initialisatie code
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

        -- Alleen als Grid radio button aan staat
        if settings.grid_color_enabled then
            UpdateGridColors()
        else
            -- Gebruik standaard theme grid kleur
            r.SetThemeColor("col_gridlines", -1, 0)
            r.SetThemeColor("col_gridlines2", -1, 0)
            r.SetThemeColor("col_gridlines3", -1, 0)
            r.SetThemeColor("col_tr1_divline", -1, 0)
            r.SetThemeColor("col_tr2_divline", -1, 0)
        end

        -- Alleen als BG radio button aan staat
        if settings.bg_brightness_enabled then
            UpdateArrangeBG()
        UpdateTrackColors()
        else
            -- Gebruik standaard theme achtergrond kleur
            r.SetThemeColor("col_arrangebg", -1, 0)
        end
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





