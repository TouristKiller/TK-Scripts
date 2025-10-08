-- @description TK Notes
-- @author TouristKiller
-- @version 2.0.4

--------------------------------------------------------------------------------
local r = reaper

local SCRIPT_NAME = "TK Notes"
local RESOURCE_PATH = r.GetResourcePath()
local PATH_SEP = (package and package.config and package.config:sub(1, 1)) or "/"

local function NormalizeSlashes(path)
    if not path or path == "" then return "" end
    return path:gsub("[/\\]", PATH_SEP)
end

local function JoinPaths(base, ...)
    local path = NormalizeSlashes(base)
    for _, part in ipairs({...}) do
        if part and part ~= "" then
            local segment = NormalizeSlashes(part)
            local first_char = segment:sub(1, 1)
            if path == "" then
                path = segment
            elseif path:sub(-1) == PATH_SEP then
                if first_char == PATH_SEP then
                    path = path .. segment:sub(2)
                else
                    path = path .. segment
                end
            elseif first_char == PATH_SEP then
                path = path .. segment
            else
                path = path .. PATH_SEP .. segment
            end
        end
    end
    return path
end

local function EnsureTrailingSeparator(path)
    local normalized = NormalizeSlashes(path)
    if normalized == "" then return PATH_SEP end
    if normalized:sub(-1) ~= PATH_SEP then
        normalized = normalized .. PATH_SEP
    end
    return normalized
end

local SCRIPT_DIR = EnsureTrailingSeparator(JoinPaths(RESOURCE_PATH, "Scripts", "TK Scripts", "TK_NOTES"))
local EXT_NAMESPACE = "TK_NOTES"

local ctx
local font

local state = {
    text = "",
    dirty = false,
    last_edit_time = 0,
    last_save_time = 0,
    auto_save_enabled = true,
    auto_save_interval = 10,
    font_size = 14,
    font_family = "sans-serif",
    show_status = true,
    editor = nil,
    text_color_mode = "white",
    bold_input_active = false,
    text_align = "left",
    current_proj = nil,
    current_track_guid = nil,
    current_track = nil,
    track_name = nil,
    track_number = nil,
    track_bg_color = nil,
    track_bg_color_hover = nil,
    track_bg_color_border = nil,
    can_edit = false,
    images = {},  
    next_image_id = 1,
    selected_image_id = nil,
    window_width = 600,
    window_height = 400,
    window_size_needs_update = false,
    mode = "project", -- "project", "track", "item"
    current_item = nil,
    current_item_guid = nil,
    tabs_enabled = false,
    active_tab_index = 1,
    tabs = {},
    renaming_tab_index = nil,
    renaming_tab_name = "",
    -- Drawing tool state
    drawing_enabled = false,
    is_drawing = false,
    current_stroke = {},
    strokes = {},
    drawing_color = {r = 1.0, g = 0.0, b = 0.0, a = 1.0}, -- red
    drawing_thickness = 2.0,
    eraser_mode = false,
    -- List mode state
    list_mode = "none", -- "none", "bullet", "numbered"
    -- Background colors per mode
    project_bg_color = nil,
    global_bg_color = nil,
    project_bg_brightness = 1.0,
    global_bg_brightness = 1.0,
}

local VARIATION_TEXT = "\239\184\142" 

local BG_COLOR_PRESETS = {
    {name = "None", r = 0, g = 0, b = 0, a = 0, preview_r = 0.13, preview_g = 0.13, preview_b = 0.13},
    {name = "White", r = 1.0, g = 1.0, b = 1.0, a = 0.15, preview_r = 0.28, preview_g = 0.28, preview_b = 0.28},
    {name = "White (bright)", r = 1.0, g = 1.0, b = 1.0, a = 0.6, preview_r = 0.73, preview_g = 0.73, preview_b = 0.73},
    {name = "Red", r = 0.8, g = 0.2, b = 0.2, a = 0.2, preview_r = 0.27, preview_g = 0.13, preview_b = 0.13},
    {name = "Orange", r = 0.9, g = 0.5, b = 0.2, a = 0.2, preview_r = 0.31, preview_g = 0.23, preview_b = 0.13},
    {name = "Yellow", r = 0.9, g = 0.8, b = 0.2, a = 0.2, preview_r = 0.31, preview_g = 0.29, preview_b = 0.13},
    {name = "Green", r = 0.2, g = 0.7, b = 0.3, a = 0.2, preview_r = 0.13, preview_g = 0.27, preview_b = 0.16},
    {name = "Cyan", r = 0.2, g = 0.7, b = 0.8, a = 0.2, preview_r = 0.13, preview_g = 0.27, preview_b = 0.29},
    {name = "Blue", r = 0.3, g = 0.4, b = 0.9, a = 0.2, preview_r = 0.16, preview_g = 0.21, preview_b = 0.31},
    {name = "Purple", r = 0.6, g = 0.3, b = 0.8, a = 0.2, preview_r = 0.24, preview_g = 0.16, preview_b = 0.29},
    {name = "Pink", r = 0.9, g = 0.4, b = 0.7, a = 0.2, preview_r = 0.31, preview_g = 0.21, preview_b = 0.27},
}

local function MonoIcon(str)
    if not str then return VARIATION_TEXT end
    return tostring(str) .. VARIATION_TEXT
end

local has_key_chord = type(r.ImGui_IsKeyChordPressed) == "function"
local has_key_pressed = type(r.ImGui_IsKeyPressed) == "function"
local has_clear_active = type(r.ImGui_ClearActiveID) == "function"
local has_get_color_u32 = type(r.ImGui_GetColorU32) == "function"
local has_style_color = type(r.ImGui_GetStyleColor) == "function"
local has_style_color_vec4 = type(r.ImGui_GetStyleColorVec4) == "function"
local has_color_convert = type(r.ImGui_ColorConvertDouble4ToU32) == "function"
local has_getset_proj_ext_state = type(r.GetSetProjExtState) == "function"
local has_set_proj_ext_state = type(r.SetProjExtState) == "function"
local has_get_proj_ext_state = type(r.GetProjExtState) == "function"
local NormalizeLineEndings
local EnsureEditorState
local BuildFont

local UpdateActiveTrackContext
local UpdateActiveContext

local function WriteProjExtState(proj, extname, key, value)
    if has_getset_proj_ext_state then
        r.GetSetProjExtState(proj, extname, key, value or "")
        return true
    end
    if has_set_proj_ext_state then
        local ok = r.SetProjExtState(proj, extname, key, value or "")
        return ok == true or ok == 1
    end
    return false
end

local function ReadProjExtState(proj, extname, key)
    if has_getset_proj_ext_state then
        local _, stored = r.GetSetProjExtState(proj, extname, key, "")
        return stored or ""
    end
    if has_get_proj_ext_state then
        local ok, stored = r.GetProjExtState(proj, extname, key)
        if (ok == true or ok == 1) and stored then
            return stored
        end
    end
    return ""
end

local function WriteExtState(extname, key, value)
    r.SetExtState(extname, key, value or "", true)
    return true
end

local function ReadExtState(extname, key)
    if r.HasExtState(extname, key) then
        return r.GetExtState(extname, key)
    end
    return ""
end

local function MakeTrackAlignKey(track_guid)
    if not track_guid or track_guid == "" then
        return "__align"
    end
    return tostring(track_guid) .. "::align"
end

local function MakeItemKey(item_guid, suffix)
    if not item_guid or item_guid == "" then
        return "__item_" .. (suffix or "text")
    end
    return "ITEM::" .. tostring(item_guid) .. "::" .. (suffix or "text")
end

local function LoadNotebook()
    if r.HasExtState(EXT_NAMESPACE, "auto_save_interval") then
        local stored_interval = r.GetExtState(EXT_NAMESPACE, "auto_save_interval")
        local interval = tonumber(stored_interval)
        if interval and interval >= 2 and interval <= 120 then
            state.auto_save_interval = interval
        end
    end
    
    UpdateActiveContext(true)
end

local function SaveNotebook()
    local is_item_mode = state.mode == "item" and state.current_item_guid
    local is_track_mode = state.mode == "track" and state.current_track_guid
    local is_project_mode = state.mode == "project" and state.current_proj
    local is_global_mode = state.mode == "global"
    
    if not is_item_mode and not is_track_mode and not is_project_mode and not is_global_mode then return end
    
    local text = state.text or ""
    local text_key, align_key, color_key, images_key, strokes_key, font_size_key, font_family_key, auto_save_key, window_width_key, window_height_key, show_status_key, tabs_enabled_key, tabs_data_key, bg_color_key, bg_brightness_key
    
    if is_item_mode then
        text_key = MakeItemKey(state.current_item_guid, "text")
        align_key = MakeItemKey(state.current_item_guid, "align")
        color_key = MakeItemKey(state.current_item_guid, "text_color")
        images_key = MakeItemKey(state.current_item_guid, "images")
        strokes_key = MakeItemKey(state.current_item_guid, "strokes")
        font_size_key = MakeItemKey(state.current_item_guid, "font_size")
        font_family_key = MakeItemKey(state.current_item_guid, "font_family")
        auto_save_key = MakeItemKey(state.current_item_guid, "auto_save_enabled")
        window_width_key = MakeItemKey(state.current_item_guid, "window_width")
        window_height_key = MakeItemKey(state.current_item_guid, "window_height")
        show_status_key = MakeItemKey(state.current_item_guid, "show_status")
        tabs_enabled_key = MakeItemKey(state.current_item_guid, "tabs_enabled")
        tabs_data_key = MakeItemKey(state.current_item_guid, "tabs_data")
    elseif is_project_mode then
        text_key = "PROJECT::text"
        align_key = "PROJECT::align"
        color_key = "PROJECT::text_color"
        images_key = "PROJECT::images"
        strokes_key = "PROJECT::strokes"
        font_size_key = "PROJECT::font_size"
        font_family_key = "PROJECT::font_family"
        auto_save_key = "PROJECT::auto_save_enabled"
        window_width_key = "PROJECT::window_width"
        window_height_key = "PROJECT::window_height"
        show_status_key = "PROJECT::show_status"
        tabs_enabled_key = "PROJECT::tabs_enabled"
        tabs_data_key = "PROJECT::tabs_data"
        bg_color_key = "PROJECT::bg_color"
        bg_brightness_key = "PROJECT::bg_brightness"
    elseif is_global_mode then
        text_key = "GLOBAL::text"
        align_key = "GLOBAL::align"
        color_key = "GLOBAL::text_color"
        images_key = "GLOBAL::images"
        strokes_key = "GLOBAL::strokes"
        font_size_key = "GLOBAL::font_size"
        font_family_key = "GLOBAL::font_family"
        auto_save_key = "GLOBAL::auto_save_enabled"
        window_width_key = "GLOBAL::window_width"
        window_height_key = "GLOBAL::window_height"
        show_status_key = "GLOBAL::show_status"
        tabs_enabled_key = "GLOBAL::tabs_enabled"
        tabs_data_key = "GLOBAL::tabs_data"
        bg_color_key = "GLOBAL::bg_color"
        bg_brightness_key = "GLOBAL::bg_brightness"
    else
        text_key = state.current_track_guid
        align_key = MakeTrackAlignKey(state.current_track_guid)
        color_key = tostring(state.current_track_guid) .. "::text_color"
        images_key = tostring(state.current_track_guid) .. "::images"
        strokes_key = tostring(state.current_track_guid) .. "::strokes"
        font_size_key = tostring(state.current_track_guid) .. "::font_size"
        font_family_key = tostring(state.current_track_guid) .. "::font_family"
        auto_save_key = tostring(state.current_track_guid) .. "::auto_save_enabled"
        window_width_key = tostring(state.current_track_guid) .. "::window_width"
        window_height_key = tostring(state.current_track_guid) .. "::window_height"
        show_status_key = tostring(state.current_track_guid) .. "::show_status"
        tabs_enabled_key = tostring(state.current_track_guid) .. "::tabs_enabled"
        tabs_data_key = tostring(state.current_track_guid) .. "::tabs_data"
    end
    
    local align_value = state.text_align or "left"
    local color_value = state.text_color_mode or "white"
    

    local images_str = ""
    for i, img in ipairs(state.images) do
        if i > 1 then images_str = images_str .. "|" end

        local escaped_path = img.path:gsub(":", "::")
        images_str = images_str .. string.format("%d;%s;%.1f;%.1f;%d", img.id, escaped_path, img.pos_x, img.pos_y, img.scale)
    end
    
    -- Serialize strokes (drawings) when tabs are disabled
    local strokes_str = ""
    if not state.tabs_enabled and state.strokes then
        for stroke_idx, stroke in ipairs(state.strokes) do
            if stroke_idx > 1 then strokes_str = strokes_str .. "|" end
            local stroke_str = string.format("%.2f,%.2f,%.2f,%.2f;%.1f", 
                stroke.color.r or 1, stroke.color.g or 0, stroke.color.b or 0, stroke.color.a or 1,
                stroke.thickness or 2)
            if stroke.points then
                for _, pt in ipairs(stroke.points) do
                    stroke_str = stroke_str .. ";" .. string.format("%.1f,%.1f", pt.x, pt.y)
                end
            end
            strokes_str = strokes_str .. stroke_str
        end
    end
    -- Always save strokes_str (even if empty) to clear old data when tabs are enabled
    
    local font_size_value = tostring(state.font_size or 14)
    local font_family_value = state.font_family or "sans-serif"
    local auto_save_value = tostring(state.auto_save_enabled and "true" or "false")
    local window_width_value = tostring(state.window_width or 600)
    local window_height_value = tostring(state.window_height or 400)
    local show_status_value = tostring(state.show_status and "true" or "false")
    local tabs_enabled_value = tostring(state.tabs_enabled and "true" or "false")
    
    -- Serialize tabs data (always save, even if tabs are disabled, to preserve them)
    local tabs_data_value = ""
    if #state.tabs > 0 then
        -- Save current tab text and images before serializing (only if tabs are enabled)
        if state.tabs_enabled and state.tabs[state.active_tab_index] then
            state.tabs[state.active_tab_index].text = state.text
            state.tabs[state.active_tab_index].images = state.images
            state.tabs[state.active_tab_index].strokes = state.strokes
        end
        
        -- Format: tab_count|active_index|tab1_name:tab1_text|tab2_name:tab2_text|...
        tabs_data_value = #state.tabs .. "|" .. state.active_tab_index
        for _, tab in ipairs(state.tabs) do
            local escaped_name = (tab.name or "Tab"):gsub("|", "||"):gsub(":", "::")
            local escaped_text = (tab.text or ""):gsub("|", "||"):gsub(":", "::")
            tabs_data_value = tabs_data_value .. "|" .. escaped_name .. ":" .. escaped_text
        end
    end
    
    -- Use ExtState for global mode, ProjExtState for others
    local saved_text, saved_align, saved_color, saved_images, saved_strokes, saved_font_size, saved_font_family
    local saved_auto_save, saved_window_width, saved_window_height, saved_show_status, saved_tabs_enabled, saved_tabs_data, saved_bg_color, saved_bg_brightness
    
    -- Serialize background color and brightness (only for project/global mode)
    local bg_color_value = ""
    local bg_brightness_value = ""
    if is_project_mode and state.project_bg_color then
        bg_color_value = string.format("%.3f,%.3f,%.3f,%.3f", 
            state.project_bg_color.r, state.project_bg_color.g, 
            state.project_bg_color.b, state.project_bg_color.a)
        bg_brightness_value = tostring(state.project_bg_brightness or 1.0)
    elseif is_global_mode and state.global_bg_color then
        bg_color_value = string.format("%.3f,%.3f,%.3f,%.3f", 
            state.global_bg_color.r, state.global_bg_color.g, 
            state.global_bg_color.b, state.global_bg_color.a)
        bg_brightness_value = tostring(state.global_bg_brightness or 1.0)
    end
    
    if is_global_mode then
        saved_text = WriteExtState(EXT_NAMESPACE, text_key, text)
        saved_align = WriteExtState(EXT_NAMESPACE, align_key, align_value)
        saved_color = WriteExtState(EXT_NAMESPACE, color_key, color_value)
        saved_images = WriteExtState(EXT_NAMESPACE, images_key, images_str)
        saved_strokes = WriteExtState(EXT_NAMESPACE, strokes_key, strokes_str)
        saved_font_size = WriteExtState(EXT_NAMESPACE, font_size_key, font_size_value)
        saved_font_family = WriteExtState(EXT_NAMESPACE, font_family_key, font_family_value)
        saved_auto_save = WriteExtState(EXT_NAMESPACE, auto_save_key, auto_save_value)
        saved_window_width = WriteExtState(EXT_NAMESPACE, window_width_key, window_width_value)
        saved_window_height = WriteExtState(EXT_NAMESPACE, window_height_key, window_height_value)
        saved_show_status = WriteExtState(EXT_NAMESPACE, show_status_key, show_status_value)
        saved_tabs_enabled = WriteExtState(EXT_NAMESPACE, tabs_enabled_key, tabs_enabled_value)
        saved_tabs_data = WriteExtState(EXT_NAMESPACE, tabs_data_key, tabs_data_value)
        saved_bg_color = WriteExtState(EXT_NAMESPACE, bg_color_key, bg_color_value)
        saved_bg_brightness = WriteExtState(EXT_NAMESPACE, bg_brightness_key, bg_brightness_value)
    else
        saved_text = WriteProjExtState(state.current_proj, EXT_NAMESPACE, text_key, text)
        saved_align = WriteProjExtState(state.current_proj, EXT_NAMESPACE, align_key, align_value)
        saved_color = WriteProjExtState(state.current_proj, EXT_NAMESPACE, color_key, color_value)
        saved_images = WriteProjExtState(state.current_proj, EXT_NAMESPACE, images_key, images_str)
        saved_strokes = WriteProjExtState(state.current_proj, EXT_NAMESPACE, strokes_key, strokes_str)
        saved_font_size = WriteProjExtState(state.current_proj, EXT_NAMESPACE, font_size_key, font_size_value)
        saved_font_family = WriteProjExtState(state.current_proj, EXT_NAMESPACE, font_family_key, font_family_value)
        saved_auto_save = WriteProjExtState(state.current_proj, EXT_NAMESPACE, auto_save_key, auto_save_value)
        saved_window_width = WriteProjExtState(state.current_proj, EXT_NAMESPACE, window_width_key, window_width_value)
        saved_window_height = WriteProjExtState(state.current_proj, EXT_NAMESPACE, window_height_key, window_height_value)
        saved_show_status = WriteProjExtState(state.current_proj, EXT_NAMESPACE, show_status_key, show_status_value)
        saved_tabs_enabled = WriteProjExtState(state.current_proj, EXT_NAMESPACE, tabs_enabled_key, tabs_enabled_value)
        saved_tabs_data = WriteProjExtState(state.current_proj, EXT_NAMESPACE, tabs_data_key, tabs_data_value)
        if is_project_mode and bg_color_key then
            saved_bg_color = WriteProjExtState(state.current_proj, EXT_NAMESPACE, bg_color_key, bg_color_value)
            saved_bg_brightness = WriteProjExtState(state.current_proj, EXT_NAMESPACE, bg_brightness_key, bg_brightness_value)
        end
    end
    
    -- Save images and strokes per tab (always save, even if tabs are disabled, to preserve them)
    if #state.tabs > 0 then
        for idx, tab in ipairs(state.tabs) do
            local tab_images_key, tab_strokes_key
            if is_item_mode then
                tab_images_key = MakeItemKey(state.current_item_guid, "tab" .. idx .. "_images")
                tab_strokes_key = MakeItemKey(state.current_item_guid, "tab" .. idx .. "_strokes")
            elseif is_project_mode then
                tab_images_key = "PROJECT::tab" .. idx .. "_images"
                tab_strokes_key = "PROJECT::tab" .. idx .. "_strokes"
            elseif is_global_mode then
                tab_images_key = "GLOBAL::tab" .. idx .. "_images"
                tab_strokes_key = "GLOBAL::tab" .. idx .. "_strokes"
            else
                tab_images_key = tostring(state.current_track_guid) .. "::tab" .. idx .. "_images"
                tab_strokes_key = tostring(state.current_track_guid) .. "::tab" .. idx .. "_strokes"
            end
            
            local tab_images_str = ""
            if tab.images then
                for i, img in ipairs(tab.images) do
                    if i > 1 then tab_images_str = tab_images_str .. "|" end
                    local escaped_path = img.path:gsub(":", "::")
                    tab_images_str = tab_images_str .. string.format("%d;%s;%.1f;%.1f;%d", img.id, escaped_path, img.pos_x, img.pos_y, img.scale)
                end
            end
            
            local tab_strokes_str = ""
            if tab.strokes then
                for stroke_idx, stroke in ipairs(tab.strokes) do
                    if stroke_idx > 1 then tab_strokes_str = tab_strokes_str .. "|" end
                    local stroke_str = string.format("%.2f,%.2f,%.2f,%.2f;%.1f", 
                        stroke.color.r or 1, stroke.color.g or 0, stroke.color.b or 0, stroke.color.a or 1,
                        stroke.thickness or 2)
                    if stroke.points then
                        for _, pt in ipairs(stroke.points) do
                            stroke_str = stroke_str .. ";" .. string.format("%.1f,%.1f", pt.x, pt.y)
                        end
                    end
                    tab_strokes_str = tab_strokes_str .. stroke_str
                end
            end
            
            if is_global_mode then
                WriteExtState(EXT_NAMESPACE, tab_images_key, tab_images_str)
                WriteExtState(EXT_NAMESPACE, tab_strokes_key, tab_strokes_str)
            else
                WriteProjExtState(state.current_proj, EXT_NAMESPACE, tab_images_key, tab_images_str)
                WriteProjExtState(state.current_proj, EXT_NAMESPACE, tab_strokes_key, tab_strokes_str)
            end
        end
    end
    
    r.SetExtState(EXT_NAMESPACE, "auto_save_interval", tostring(state.auto_save_interval or 10), true)
    
    if saved_text and saved_align and saved_color and saved_images and saved_strokes and saved_font_size and saved_font_family and saved_auto_save and saved_window_width and saved_window_height and saved_show_status and saved_tabs_enabled and saved_tabs_data then
        state.dirty = false
        state.last_save_time = r.time_precise()
    end
end

local function ClearAllImages()
    for _, img in ipairs(state.images) do
        if img.texture and r.ImGui_DestroyImage then
            r.ImGui_DestroyImage(img.texture)
        end
    end
    state.images = {}
    state.selected_image_id = nil
end

local function ResetNotebook()
    if not state.can_edit then return end
    state.text = ""
    state.dirty = true
    state.last_edit_time = r.time_precise()
    local editor = EnsureEditorState()
    editor.caret = 0
    editor.preferred_x = nil
    editor.scroll_to_caret = true
    editor.selection_start = 0
    editor.selection_end = 0
    editor.selection_anchor = 0
    editor.mouse_selecting = false
    state.bold_input_active = false
    ClearAllImages()
    state.strokes = {}  -- Clear all drawings
    state.show_status = true
    state.window_width = 600
    state.window_height = 400
    state.window_size_needs_update = true
end

local function WordCount(str)
    local count = 0
    for _ in string.gmatch(str or "", "%S+") do
        count = count + 1
    end
    return count
end

local function CharacterCount(str)
    if not str or str == "" then return 0 end
    local ok, utf_len = pcall(utf8.len, str)
    if ok and utf_len then return utf_len end
    return #str
end

NormalizeLineEndings = function(str)
    if not str or str == "" then return "" end
    return str:gsub("\r\n", "\n")
end

local function LoadImage(file_path)
    if not file_path or file_path == "" then return nil, nil, nil end
    if not r.file_exists(file_path) then 
        return nil, nil, nil 
    end
    
    if r.ImGui_CreateImage then
        local ok, texture = pcall(function() return r.ImGui_CreateImage(file_path) end)
        if ok and texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
            local width, height = r.ImGui_Image_GetSize(texture)
            return texture, width, height
        end
    end
    
    return nil, nil, nil
end


local function AddImage(file_path)
    local texture, orig_width, orig_height = LoadImage(file_path)
    if not texture or not orig_width or not orig_height then
        return nil
    end
    
    local image = {
        id = state.next_image_id,
        path = file_path,
        texture = texture,
        width = 150,
        height = math.floor((orig_height / orig_width) * 150),
        pos_x = 10 + (#state.images * 20), 
        
        pos_y = 10 + (#state.images * 20),
        scale = 100,
        dragging = false,
        drag_offset_x = 0,
        drag_offset_y = 0
    }
    
    table.insert(state.images, image)
    state.next_image_id = state.next_image_id + 1
    state.selected_image_id = image.id
    
    return image
end

local function RemoveImage(image_id)
    for i, img in ipairs(state.images) do
        if img.id == image_id then
            if img.texture and r.ImGui_DestroyImage then
                r.ImGui_DestroyImage(img.texture)
            end
            table.remove(state.images, i)
            if state.selected_image_id == image_id then
                state.selected_image_id = state.images[1] and state.images[1].id or nil
            end
            return true
        end
    end
    return false
end

local function LoadImagesFromString(images_str)
    ClearAllImages()
    if not images_str or images_str == "" then
        return
    end
    

    local image_entries = {}
    for entry in images_str:gmatch("[^|]+") do
        table.insert(image_entries, entry)
    end
    
    for _, entry in ipairs(image_entries) do
        local parts = {}
        for part in entry:gmatch("[^;]+") do
            table.insert(parts, part)
        end
        
        if #parts >= 5 then
            local id = tonumber(parts[1])
            local escaped_path = parts[2]

            local path = escaped_path:gsub("::", ":")
            local pos_x = tonumber(parts[3]) or 10
            local pos_y = tonumber(parts[4]) or 10
            local scale = tonumber(parts[5]) or 100
            
            if id and path and r.file_exists(path) then
                local texture, orig_width, orig_height = LoadImage(path)
                if texture and orig_width and orig_height then
                    local image = {
                        id = id,
                        path = path,
                        texture = texture,
                        width = 150,
                        height = math.floor((orig_height / orig_width) * 150),
                        pos_x = pos_x,
                        pos_y = pos_y,
                        scale = scale,
                        dragging = false,
                        drag_offset_x = 0,
                        drag_offset_y = 0
                    }
                    table.insert(state.images, image)
                    if id >= state.next_image_id then
                        state.next_image_id = id + 1
                    end
                end
            end
        end
    end
    

    if #state.images > 0 then
        state.selected_image_id = state.images[1].id
    end
end

local function GetImageById(image_id)
    for _, img in ipairs(state.images) do
        if img.id == image_id then
            return img
        end
    end
    return nil
end

local function GetActiveProject()
    if type(r.EnumProjects) ~= "function" then return nil end
    local proj = r.EnumProjects(-1, "")
    if type(proj) == "table" then
        proj = proj[1]
    end
    return proj
end

local function GetFirstSelectedTrack(proj)
    if type(r.GetSelectedTrack2) == "function" then
        return r.GetSelectedTrack2(proj, 0, true)
    end
    return r.GetSelectedTrack(0, 0)
end

local function GetFirstSelectedItem(proj)
    return r.GetSelectedMediaItem(proj or 0, 0)
end

local function GetItemGUID(item)
    if not item then return nil end
    local track = r.GetMediaItem_Track(item)
    local track_guid = track and r.GetTrackGUID(track) or "no_track"
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    return track_guid .. "::" .. string.format("%.6f", pos) .. "::" .. string.format("%.6f", length)
end

local function PackColorToU32(rf, gf, bf, af)
    local function clamp(v)
        if not v then return 1.0 end
        if v < 0 then return 0 end
        if v > 1 then return 1 end
        return v
    end

    rf, gf, bf, af = clamp(rf), clamp(gf), clamp(bf), clamp(af)

    if has_color_convert then
        return r.ImGui_ColorConvertDouble4ToU32(rf, gf, bf, af)
    end

    local r8 = math.floor(rf * 255 + 0.5)
    local g8 = math.floor(gf * 255 + 0.5)
    local b8 = math.floor(bf * 255 + 0.5)
    local a8 = math.floor(af * 255 + 0.5)
    return (r8 << 24) | (g8 << 16) | (b8 << 8) | a8
end

local function DistanceToLineSegment(px, py, x1, y1, x2, y2)
    -- Calculate distance from point (px, py) to line segment (x1,y1)-(x2,y2)
    local dx = x2 - x1
    local dy = y2 - y1
    local len_sq = dx * dx + dy * dy
    
    if len_sq == 0 then
        -- Line segment is a point
        local dpx = px - x1
        local dpy = py - y1
        return math.sqrt(dpx * dpx + dpy * dpy)
    end
    
    -- Project point onto line
    local t = ((px - x1) * dx + (py - y1) * dy) / len_sq
    t = math.max(0, math.min(1, t))  -- Clamp to segment
    
    -- Find closest point on segment
    local closest_x = x1 + t * dx
    local closest_y = y1 + t * dy
    
    -- Return distance to closest point
    local dpx = px - closest_x
    local dpy = py - closest_y
    return math.sqrt(dpx * dpx + dpy * dpy)
end

local function ComputeTrackColors(track)
    if not track then return nil end
    local native = r.GetTrackColor(track)
    if not native or native == 0 then return nil end
    local r8, g8, b8 = r.ColorFromNative(native)
    if not r8 then return nil end
    local rf, gf, bf = r8 / 255, g8 / 255, b8 / 255
    local function mix(comp, add)
        local value = 0.18 + comp * 0.72 + (add or 0)
        if value < 0 then value = 0 end
        if value > 1 then value = 1 end
        return value
    end
    local fill = PackColorToU32(mix(rf), mix(gf), mix(bf), 0.95)
    local hover = PackColorToU32(mix(rf, 0.05), mix(gf, 0.05), mix(bf, 0.05), 0.98)
    local border = PackColorToU32(mix(rf, 0.12), mix(gf, 0.12), mix(bf, 0.12), 1.0)
    return fill, hover, border
end

local function ComputeItemColors(item)
    if not item then
        return nil, nil, nil
    end
    
    local item_color = r.GetDisplayedMediaItemColor(item)
    local rf, gf, bf
    
    if item_color == 0 then
        local track = r.GetMediaItem_Track(item)
        if track then
            return ComputeTrackColors(track)
        else
            rf, gf, bf = 0.3, 0.3, 0.3
        end
    else
        rf = ((item_color >> 0) & 0xFF) / 255.0
        gf = ((item_color >> 8) & 0xFF) / 255.0 
        bf = ((item_color >> 16) & 0xFF) / 255.0
    end
    
    local function mix(c, amount)
        return math.max(0, math.min(1, c + amount))
    end
    local fill = PackColorToU32(mix(rf, 0.02), mix(gf, 0.02), mix(bf, 0.02), 0.95)
    local hover = PackColorToU32(mix(rf, 0.05), mix(gf, 0.05), mix(bf, 0.05), 0.98)
    local border = PackColorToU32(mix(rf, 0.12), mix(gf, 0.12), mix(bf, 0.12), 1.0)
    return fill, hover, border
end

local function ApplyTrackAppearance(track)
    if not track then
        state.track_bg_color = nil
        state.track_bg_color_hover = nil
        state.track_bg_color_border = nil
        return
    end
    local fill, hover, border = ComputeTrackColors(track)
    state.track_bg_color = fill
    state.track_bg_color_hover = hover
    state.track_bg_color_border = border
end

local function ApplyItemAppearance(item)
    if not item then
        state.track_bg_color = nil
        state.track_bg_color_hover = nil
        state.track_bg_color_border = nil
        return
    end
    local fill, hover, border = ComputeItemColors(item)
    state.track_bg_color = fill
    state.track_bg_color_hover = hover
    state.track_bg_color_border = border
end

local function SetNoTrackState(proj)
    state.current_proj = proj
    state.current_track = nil
    state.current_track_guid = nil
    state.track_name = nil
    state.track_number = nil
    state.can_edit = false
    state.text = ""
    state.dirty = false
    state.last_edit_time = 0
    state.bold_input_active = false
    state.text_align = "left"
    state.auto_save_enabled = true
    state.show_status = true
    state.window_width = 600
    state.window_height = 400
    state.window_size_needs_update = true
    state.strokes = {}
    ClearAllImages()
    ApplyTrackAppearance(nil)
    local editor = EnsureEditorState()
    editor.caret = 0
    editor.selection_start = 0
    editor.selection_end = 0
    editor.selection_anchor = 0
    editor.preferred_x = nil
    editor.scroll_to_caret = false
    editor.mouse_selecting = false
    editor.active = false
    editor.request_focus = false
end

local function LoadProjectState(proj)
    state.current_proj = proj
    state.current_track = nil
    state.current_track_guid = nil
    state.current_item = nil
    state.current_item_guid = nil
    state.track_name = "Project Notes"
    state.track_number = nil
    state.can_edit = true
    state.dirty = false
    state.last_edit_time = 0
    state.bold_input_active = false
    
    local stored = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::text")
    state.text = NormalizeLineEndings(stored or "")
    
    local stored_align = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::align")
    if stored_align ~= "left" and stored_align ~= "center" and stored_align ~= "right" then
        stored_align = "left"
    end
    state.text_align = stored_align
    
    local stored_color = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::text_color")
    if stored_color ~= "white" and stored_color ~= "black" then
        stored_color = "white"
    end
    state.text_color_mode = stored_color
    
    local stored_font_size = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::font_size"))
    local stored_font_family = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::font_family")
    local min_font, max_font = 11, 26
    local default_font = 14
    local target_font = default_font
    if stored_font_size and stored_font_size >= min_font and stored_font_size <= max_font then
        target_font = math.floor(stored_font_size + 0.5)
    end
    local font_changed = false
    if target_font ~= state.font_size then
        state.font_size = target_font
        font_changed = true
    end
    if stored_font_family and stored_font_family ~= "" and stored_font_family ~= state.font_family then
        state.font_family = stored_font_family
        font_changed = true
    end
    if font_changed then
        BuildFont()
    end
    
    local stored_images = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::images")
    local stored_auto_save = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::auto_save_enabled")
    local stored_width = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::window_width"))
    local stored_height = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::window_height"))
    local stored_show_status = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::show_status")
    local stored_tabs_enabled = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::tabs_enabled")
    local stored_tabs_data = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::tabs_data")
    local stored_bg_color = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::bg_color")
    local stored_bg_brightness = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::bg_brightness")
    
    -- Load background color and brightness
    if stored_bg_color and stored_bg_color ~= "" then
        local parts = {}
        for num in stored_bg_color:gmatch("[^,]+") do
            table.insert(parts, tonumber(num) or 0)
        end
        if #parts >= 4 then
            state.project_bg_color = {r = parts[1], g = parts[2], b = parts[3], a = parts[4]}
        end
    else
        state.project_bg_color = nil
    end
    state.project_bg_brightness = tonumber(stored_bg_brightness) or 1.0
    
    if stored_auto_save then
        state.auto_save_enabled = (stored_auto_save == "true")
    else
        state.auto_save_enabled = true
    end
    
    -- Load tabs data (always load, even if tabs are disabled, to preserve them)
    state.tabs_enabled = stored_tabs_enabled == "true"
    state.tabs = {}
    state.active_tab_index = 1
    state.strokes = {}
    
    if stored_tabs_data and stored_tabs_data ~= "" then
        local parts = {}
        for part in stored_tabs_data:gmatch("[^|]+") do
            table.insert(parts, part)
        end
        
        if #parts >= 2 then
            local tab_count = tonumber(parts[1]) or 0
            state.active_tab_index = tonumber(parts[2]) or 1
            
            for i = 3, #parts do
                local colon_pos = parts[i]:find(":")
                if colon_pos then
                    local name = parts[i]:sub(1, colon_pos - 1):gsub("::", ":"):gsub("||", "|")
                    local text = parts[i]:sub(colon_pos + 1):gsub("::", ":"):gsub("||", "|")
                    table.insert(state.tabs, {name = name, text = text, images = {}, strokes = {}})
                end
            end
            
            -- Load images and strokes for each tab
            for idx = 1, #state.tabs do
                local tab_images_key = "PROJECT::tab" .. idx .. "_images"
                local stored_tab_images = ReadProjExtState(proj, EXT_NAMESPACE, tab_images_key)
                if stored_tab_images and stored_tab_images ~= "" then
                    state.tabs[idx].images = {}
                    for img_data in stored_tab_images:gmatch("[^|]+") do
                        local img_parts = {}
                        for part in img_data:gmatch("[^;]+") do
                            table.insert(img_parts, part)
                        end
                        if #img_parts >= 5 then
                            local img_id = tonumber(img_parts[1])
                            local img_path = img_parts[2]:gsub("::", ":")
                            local img_x = tonumber(img_parts[3]) or 0
                            local img_y = tonumber(img_parts[4]) or 0
                            local img_scale = tonumber(img_parts[5]) or 100
                            
                            local img_texture = nil
                            if r.ImGui_CreateImage then
                                img_texture = r.ImGui_CreateImage(img_path)
                            end
                            
                            if img_texture then
                                local img_w, img_h = r.ImGui_Image_GetSize(img_texture)
                                table.insert(state.tabs[idx].images, {
                                    id = img_id,
                                    path = img_path,
                                    texture = img_texture,
                                    width = img_w,
                                    height = img_h,
                                    pos_x = img_x,
                                    pos_y = img_y,
                                    scale = img_scale
                                })
                            end
                        end
                    end
                end
                
                local tab_strokes_key = "PROJECT::tab" .. idx .. "_strokes"
                local stored_tab_strokes = ReadProjExtState(proj, EXT_NAMESPACE, tab_strokes_key)
                if stored_tab_strokes and stored_tab_strokes ~= "" then
                    state.tabs[idx].strokes = {}
                    for stroke_data in stored_tab_strokes:gmatch("[^|]+") do
                        local stroke_parts = {}
                        for part in stroke_data:gmatch("[^;]+") do
                            table.insert(stroke_parts, part)
                        end
                        if #stroke_parts >= 2 then
                            local color_parts = {}
                            for num in stroke_parts[1]:gmatch("[^,]+") do
                                table.insert(color_parts, tonumber(num) or 1)
                            end
                            local thickness = tonumber(stroke_parts[2]) or 2
                            
                            local points = {}
                            for i = 3, #stroke_parts do
                                local coords = {}
                                for num in stroke_parts[i]:gmatch("[^,]+") do
                                    table.insert(coords, tonumber(num) or 0)
                                end
                                if #coords >= 2 then
                                    table.insert(points, {x = coords[1], y = coords[2]})
                                end
                            end
                            
                            if #points > 1 then
                                table.insert(state.tabs[idx].strokes, {
                                    color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                                    thickness = thickness,
                                    points = points
                                })
                            end
                        end
                    end
                end
            end
            
            if state.tabs[state.active_tab_index] then
                state.text = state.tabs[state.active_tab_index].text or ""
                state.images = state.tabs[state.active_tab_index].images or {}
                state.strokes = state.tabs[state.active_tab_index].strokes or {}
            end
        end
    end
    
    local prev_width = state.window_width
    local prev_height = state.window_height
    if stored_width and stored_width >= 300 and stored_width <= 3000 then
        state.window_width = stored_width
    else
        state.window_width = 600
    end
    if stored_height and stored_height >= 250 and stored_height <= 3000 then
        state.window_height = stored_height
    else
        state.window_height = 400
    end
    if stored_show_status then
        state.show_status = (stored_show_status == "true")
    else
        state.show_status = true
    end
    
    if prev_width ~= state.window_width or prev_height ~= state.window_height then
        state.window_size_needs_update = true
    end
    
    -- Load images and strokes when tabs are disabled
    if not state.tabs_enabled then
        LoadImagesFromString(stored_images)
        
        local stored_strokes = ReadProjExtState(proj, EXT_NAMESPACE, "PROJECT::strokes")
        if stored_strokes and stored_strokes ~= "" then
            state.strokes = {}
            for stroke_data in stored_strokes:gmatch("[^|]+") do
                local stroke_parts = {}
                for part in stroke_data:gmatch("[^;]+") do
                    table.insert(stroke_parts, part)
                end
                if #stroke_parts >= 2 then
                    local color_parts = {}
                    for num in stroke_parts[1]:gmatch("[^,]+") do
                        table.insert(color_parts, tonumber(num) or 1)
                    end
                    local thickness = tonumber(stroke_parts[2]) or 2
                    
                    local points = {}
                    for i = 3, #stroke_parts do
                        local coords = {}
                        for num in stroke_parts[i]:gmatch("[^,]+") do
                            table.insert(coords, tonumber(num) or 0)
                        end
                        if #coords >= 2 then
                            table.insert(points, {x = coords[1], y = coords[2]})
                        end
                    end
                    
                    if #points > 1 then
                        table.insert(state.strokes, {
                            color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                            thickness = thickness,
                            points = points
                        })
                    end
                end
            end
        end
    end
    
    -- Apply default appearance for project mode
    ApplyTrackAppearance(nil)
    
    local editor = EnsureEditorState()
    editor.caret = #state.text
    editor.selection_start = #state.text
    editor.selection_end = #state.text
    editor.selection_anchor = #state.text
    editor.mouse_selecting = false
    editor.active = false
    editor.request_focus = true
end

local function LoadGlobalState()
    state.current_proj = nil
    state.current_track = nil
    state.current_track_guid = nil
    state.current_item = nil
    state.current_item_guid = nil
    state.track_name = "Global Notes"
    state.track_number = nil
    state.can_edit = true
    state.dirty = false
    state.last_edit_time = 0
    state.bold_input_active = false
    
    local stored = ReadExtState(EXT_NAMESPACE, "GLOBAL::text")
    state.text = NormalizeLineEndings(stored or "")
    
    local stored_align = ReadExtState(EXT_NAMESPACE, "GLOBAL::align")
    if stored_align ~= "left" and stored_align ~= "center" and stored_align ~= "right" then
        stored_align = "left"
    end
    state.text_align = stored_align
    
    local stored_color = ReadExtState(EXT_NAMESPACE, "GLOBAL::text_color")
    if stored_color ~= "white" and stored_color ~= "black" then
        stored_color = "white"
    end
    state.text_color_mode = stored_color
    
    local stored_font_size = tonumber(ReadExtState(EXT_NAMESPACE, "GLOBAL::font_size"))
    local stored_font_family = ReadExtState(EXT_NAMESPACE, "GLOBAL::font_family")
    local min_font, max_font = 11, 26
    local default_font = 14
    local target_font = default_font
    if stored_font_size and stored_font_size >= min_font and stored_font_size <= max_font then
        target_font = math.floor(stored_font_size + 0.5)
    end
    local font_changed = false
    if target_font ~= state.font_size then
        state.font_size = target_font
        font_changed = true
    end
    if stored_font_family and stored_font_family ~= "" and stored_font_family ~= state.font_family then
        state.font_family = stored_font_family
        font_changed = true
    end
    if font_changed then
        BuildFont()
    end
    
    local stored_images = ReadExtState(EXT_NAMESPACE, "GLOBAL::images")
    local stored_auto_save = ReadExtState(EXT_NAMESPACE, "GLOBAL::auto_save_enabled")
    local stored_width = tonumber(ReadExtState(EXT_NAMESPACE, "GLOBAL::window_width"))
    local stored_height = tonumber(ReadExtState(EXT_NAMESPACE, "GLOBAL::window_height"))
    local stored_show_status = ReadExtState(EXT_NAMESPACE, "GLOBAL::show_status")
    local stored_tabs_enabled = ReadExtState(EXT_NAMESPACE, "GLOBAL::tabs_enabled")
    local stored_tabs_data = ReadExtState(EXT_NAMESPACE, "GLOBAL::tabs_data")
    local stored_bg_color = ReadExtState(EXT_NAMESPACE, "GLOBAL::bg_color")
    local stored_bg_brightness = ReadExtState(EXT_NAMESPACE, "GLOBAL::bg_brightness")
    
    -- Load background color and brightness
    if stored_bg_color and stored_bg_color ~= "" then
        local parts = {}
        for num in stored_bg_color:gmatch("[^,]+") do
            table.insert(parts, tonumber(num) or 0)
        end
        if #parts >= 4 then
            state.global_bg_color = {r = parts[1], g = parts[2], b = parts[3], a = parts[4]}
        end
    else
        state.global_bg_color = nil
    end
    state.global_bg_brightness = tonumber(stored_bg_brightness) or 1.0
    
    if stored_auto_save then
        state.auto_save_enabled = (stored_auto_save == "true")
    else
        state.auto_save_enabled = true
    end
    
    -- Load tabs data
    state.tabs_enabled = stored_tabs_enabled == "true"
    state.tabs = {}
    state.active_tab_index = 1
    state.strokes = {}
    
    if stored_tabs_data and stored_tabs_data ~= "" then
        local parts = {}
        for part in stored_tabs_data:gmatch("[^|]+") do
            table.insert(parts, part)
        end
        
        if #parts >= 2 then
            local tab_count = tonumber(parts[1]) or 0
            state.active_tab_index = tonumber(parts[2]) or 1
            
            for i = 3, #parts do
                local colon_pos = parts[i]:find(":")
                if colon_pos then
                    local name = parts[i]:sub(1, colon_pos - 1):gsub("::", ":"):gsub("||", "|")
                    local text = parts[i]:sub(colon_pos + 1):gsub("::", ":"):gsub("||", "|")
                    table.insert(state.tabs, {name = name, text = text, images = {}, strokes = {}})
                end
            end
            
            -- Load images and strokes for each tab
            for idx = 1, #state.tabs do
                local tab_images_key = "GLOBAL::tab" .. idx .. "_images"
                local stored_tab_images = ReadExtState(EXT_NAMESPACE, tab_images_key)
                if stored_tab_images and stored_tab_images ~= "" then
                    state.tabs[idx].images = {}
                    for img_data in stored_tab_images:gmatch("[^|]+") do
                        local img_parts = {}
                        for part in img_data:gmatch("[^;]+") do
                            table.insert(img_parts, part)
                        end
                        if #img_parts >= 5 then
                            local img_id = tonumber(img_parts[1])
                            local img_path = img_parts[2]:gsub("::", ":")
                            local img_x = tonumber(img_parts[3]) or 0
                            local img_y = tonumber(img_parts[4]) or 0
                            local img_scale = tonumber(img_parts[5]) or 100
                            
                            local img_texture = nil
                            if r.ImGui_CreateImage then
                                img_texture = r.ImGui_CreateImage(img_path)
                            end
                            
                            if img_texture then
                                local img_w, img_h = r.ImGui_Image_GetSize(img_texture)
                                table.insert(state.tabs[idx].images, {
                                    id = img_id,
                                    path = img_path,
                                    texture = img_texture,
                                    width = img_w,
                                    height = img_h,
                                    pos_x = img_x,
                                    pos_y = img_y,
                                    scale = img_scale
                                })
                            end
                        end
                    end
                end
                
                local tab_strokes_key = "GLOBAL::tab" .. idx .. "_strokes"
                local stored_tab_strokes = ReadExtState(EXT_NAMESPACE, tab_strokes_key)
                if stored_tab_strokes and stored_tab_strokes ~= "" then
                    state.tabs[idx].strokes = {}
                    for stroke_data in stored_tab_strokes:gmatch("[^|]+") do
                        local stroke_parts = {}
                        for part in stroke_data:gmatch("[^;]+") do
                            table.insert(stroke_parts, part)
                        end
                        if #stroke_parts >= 2 then
                            local color_parts = {}
                            for num in stroke_parts[1]:gmatch("[^,]+") do
                                table.insert(color_parts, tonumber(num) or 1)
                            end
                            local thickness = tonumber(stroke_parts[2]) or 2
                            
                            local points = {}
                            for i = 3, #stroke_parts do
                                local coords = {}
                                for num in stroke_parts[i]:gmatch("[^,]+") do
                                    table.insert(coords, tonumber(num) or 0)
                                end
                                if #coords >= 2 then
                                    table.insert(points, {x = coords[1], y = coords[2]})
                                end
                            end
                            
                            if #points > 1 then
                                table.insert(state.tabs[idx].strokes, {
                                    color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                                    thickness = thickness,
                                    points = points
                                })
                            end
                        end
                    end
                end
            end
            
            if state.tabs[state.active_tab_index] then
                state.text = state.tabs[state.active_tab_index].text or ""
                state.images = state.tabs[state.active_tab_index].images or {}
                state.strokes = state.tabs[state.active_tab_index].strokes or {}
            end
        end
    end
    
    local prev_width = state.window_width
    local prev_height = state.window_height
    if stored_width and stored_width >= 300 and stored_width <= 3000 then
        state.window_width = stored_width
    else
        state.window_width = 600
    end
    if stored_height and stored_height >= 250 and stored_height <= 3000 then
        state.window_height = stored_height
    else
        state.window_height = 400
    end
    if stored_show_status then
        state.show_status = (stored_show_status == "true")
    else
        state.show_status = true
    end
    
    if prev_width ~= state.window_width or prev_height ~= state.window_height then
        state.window_size_needs_update = true
    end
    
    -- Load images and strokes when tabs are disabled
    if not state.tabs_enabled then
        LoadImagesFromString(stored_images)
        
        local stored_strokes = ReadExtState(EXT_NAMESPACE, "GLOBAL::strokes")
        if stored_strokes and stored_strokes ~= "" then
            state.strokes = {}
            for stroke_data in stored_strokes:gmatch("[^|]+") do
                local stroke_parts = {}
                for part in stroke_data:gmatch("[^;]+") do
                    table.insert(stroke_parts, part)
                end
                if #stroke_parts >= 2 then
                    local color_parts = {}
                    for num in stroke_parts[1]:gmatch("[^,]+") do
                        table.insert(color_parts, tonumber(num) or 1)
                    end
                    local thickness = tonumber(stroke_parts[2]) or 2
                    
                    local points = {}
                    for i = 3, #stroke_parts do
                        local coords = {}
                        for num in stroke_parts[i]:gmatch("[^,]+") do
                            table.insert(coords, tonumber(num) or 0)
                        end
                        if #coords >= 2 then
                            table.insert(points, {x = coords[1], y = coords[2]})
                        end
                    end
                    
                    if #points > 1 then
                        table.insert(state.strokes, {
                            color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                            thickness = thickness,
                            points = points
                        })
                    end
                end
            end
        end
    end
    
    -- Apply default appearance for global mode
    ApplyTrackAppearance(nil)
    
    local editor = EnsureEditorState()
    editor.caret = #state.text
    editor.selection_start = #state.text
    editor.selection_end = #state.text
    editor.selection_anchor = #state.text
    editor.mouse_selecting = false
    editor.active = false
    editor.request_focus = true
end

local function LoadTrackState(proj, track, track_guid)
    state.current_proj = proj
    state.current_track = track
    state.current_track_guid = track_guid
    state.can_edit = track ~= nil
    state.dirty = false
    state.last_edit_time = 0
    state.bold_input_active = false

    if not track or not track_guid then
        SetNoTrackState(proj)
        return
    end

    local stored = ReadProjExtState(proj, EXT_NAMESPACE, track_guid)
    state.text = NormalizeLineEndings(stored or "")
    local stored_align = ReadProjExtState(proj, EXT_NAMESPACE, MakeTrackAlignKey(track_guid))
    if stored_align ~= "left" and stored_align ~= "center" and stored_align ~= "right" then
        stored_align = "left"
    end
    state.text_align = stored_align
    
    local color_key = tostring(track_guid) .. "::text_color"
    local stored_color = ReadProjExtState(proj, EXT_NAMESPACE, color_key)
    if stored_color ~= "white" and stored_color ~= "black" then
        stored_color = "white"
    end
    state.text_color_mode = stored_color
    local font_size_key = tostring(track_guid) .. "::font_size"
    local stored_font_size = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, font_size_key))
    local font_family_key = tostring(track_guid) .. "::font_family"
    local stored_font_family = ReadProjExtState(proj, EXT_NAMESPACE, font_family_key)
    local min_font, max_font = 11, 26
    local default_font = 14
    local target_font = default_font
    if stored_font_size and stored_font_size >= min_font and stored_font_size <= max_font then
        target_font = math.floor(stored_font_size + 0.5)
    end
    local font_changed = false
    if target_font ~= state.font_size then
        state.font_size = target_font
        font_changed = true
    end
    if stored_font_family and stored_font_family ~= "" and stored_font_family ~= state.font_family then
        state.font_family = stored_font_family
        font_changed = true
    end
    if font_changed then
        BuildFont()
    end
    
    local images_key = tostring(track_guid) .. "::images"
    local stored_images = ReadProjExtState(proj, EXT_NAMESPACE, images_key)
    local auto_save_key = tostring(track_guid) .. "::auto_save_enabled"
    local stored_auto_save = ReadProjExtState(proj, EXT_NAMESPACE, auto_save_key)
    local window_width_key = tostring(track_guid) .. "::window_width"
    local window_height_key = tostring(track_guid) .. "::window_height"
    local stored_width = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, window_width_key))
    local stored_height = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, window_height_key))
    local show_status_key = tostring(track_guid) .. "::show_status"
    local stored_show_status = ReadProjExtState(proj, EXT_NAMESPACE, show_status_key)
    local tabs_enabled_key = tostring(track_guid) .. "::tabs_enabled"
    local stored_tabs_enabled = ReadProjExtState(proj, EXT_NAMESPACE, tabs_enabled_key)
    local tabs_data_key = tostring(track_guid) .. "::tabs_data"
    local stored_tabs_data = ReadProjExtState(proj, EXT_NAMESPACE, tabs_data_key)
    
    if stored_auto_save then
        state.auto_save_enabled = (stored_auto_save == "true")
    else
        state.auto_save_enabled = true
    end
    
    -- Load tabs data (always load, even if tabs are disabled, to preserve them)
    state.tabs_enabled = stored_tabs_enabled == "true"
    state.tabs = {}
    state.active_tab_index = 1
    state.strokes = {}  -- Reset strokes
    
    if stored_tabs_data and stored_tabs_data ~= "" then
        -- Format: tab_count|active_index|tab1_name:tab1_text|tab2_name:tab2_text|...
        local parts = {}
        for part in stored_tabs_data:gmatch("[^|]+") do
            table.insert(parts, part)
        end
        
        if #parts >= 2 then
            local tab_count = tonumber(parts[1]) or 0
            state.active_tab_index = tonumber(parts[2]) or 1
            
            for i = 3, #parts do
                local colon_pos = parts[i]:find(":")
                if colon_pos then
                    local name = parts[i]:sub(1, colon_pos - 1):gsub("::", ":"):gsub("||", "|")
                    local text = parts[i]:sub(colon_pos + 1):gsub("::", ":"):gsub("||", "|")
                    table.insert(state.tabs, {name = name, text = text, images = {}, strokes = {}})
                end
            end
            
            -- Load images for each tab
            for idx = 1, #state.tabs do
                local tab_images_key = tostring(track_guid) .. "::tab" .. idx .. "_images"
                local stored_tab_images = ReadProjExtState(proj, EXT_NAMESPACE, tab_images_key)
                if stored_tab_images and stored_tab_images ~= "" then
                    state.tabs[idx].images = {}
                    for img_data in stored_tab_images:gmatch("[^|]+") do
                        local parts = {}
                        for part in img_data:gmatch("[^;]+") do
                            table.insert(parts, part)
                        end
                        if #parts >= 5 then
                            local img_id = tonumber(parts[1])
                            local img_path = parts[2]:gsub("::", ":")
                            local img_x = tonumber(parts[3]) or 0
                            local img_y = tonumber(parts[4]) or 0
                            local img_scale = tonumber(parts[5]) or 100
                            
                            local img_texture = nil
                            if r.ImGui_CreateImage then
                                img_texture = r.ImGui_CreateImage(img_path)
                            end
                            
                            if img_texture then
                                local img_w, img_h = r.ImGui_Image_GetSize(img_texture)
                                table.insert(state.tabs[idx].images, {
                                    id = img_id,
                                    path = img_path,
                                    texture = img_texture,
                                    width = img_w,
                                    height = img_h,
                                    pos_x = img_x,
                                    pos_y = img_y,
                                    scale = img_scale
                                })
                            end
                        end
                    end
                end
                
                -- Load strokes for each tab
                local tab_strokes_key = tostring(track_guid) .. "::tab" .. idx .. "_strokes"
                local stored_tab_strokes = ReadProjExtState(proj, EXT_NAMESPACE, tab_strokes_key)
                if stored_tab_strokes and stored_tab_strokes ~= "" then
                    state.tabs[idx].strokes = {}
                    for stroke_data in stored_tab_strokes:gmatch("[^|]+") do
                        local parts = {}
                        for part in stroke_data:gmatch("[^;]+") do
                            table.insert(parts, part)
                        end
                        if #parts >= 2 then
                            -- Parse color (r,g,b,a)
                            local color_parts = {}
                            for num in parts[1]:gmatch("[^,]+") do
                                table.insert(color_parts, tonumber(num) or 1)
                            end
                            local thickness = tonumber(parts[2]) or 2
                            
                            -- Parse points
                            local points = {}
                            for i = 3, #parts do
                                local coords = {}
                                for num in parts[i]:gmatch("[^,]+") do
                                    table.insert(coords, tonumber(num) or 0)
                                end
                                if #coords >= 2 then
                                    table.insert(points, {x = coords[1], y = coords[2]})
                                end
                            end
                            
                            if #points > 1 then
                                table.insert(state.tabs[idx].strokes, {
                                    color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                                    thickness = thickness,
                                    points = points
                                })
                            end
                        end
                    end
                end
            end
            
            -- Load the active tab's text, images and strokes
            if state.tabs[state.active_tab_index] then
                state.text = state.tabs[state.active_tab_index].text or ""
                state.images = state.tabs[state.active_tab_index].images or {}
                state.strokes = state.tabs[state.active_tab_index].strokes or {}
            end
        end
    end
    
    local prev_width = state.window_width
    local prev_height = state.window_height
    if stored_width and stored_width >= 300 and stored_width <= 3000 then
        state.window_width = stored_width
    else
        state.window_width = 600
    end
    if stored_height and stored_height >= 250 and stored_height <= 3000 then
        state.window_height = stored_height
    else
        state.window_height = 400
    end
    if prev_width ~= state.window_width or prev_height ~= state.window_height then
        state.window_size_needs_update = true
    end
    if stored_show_status then
        state.show_status = (stored_show_status == "true")
    else
        state.show_status = true
    end
    
    -- Load images and strokes when tabs are disabled
    if not state.tabs_enabled then
        LoadImagesFromString(stored_images)
        
        local strokes_key = tostring(track_guid) .. "::strokes"
        local stored_strokes = ReadProjExtState(proj, EXT_NAMESPACE, strokes_key)
        if stored_strokes and stored_strokes ~= "" then
            state.strokes = {}
            for stroke_data in stored_strokes:gmatch("[^|]+") do
                local stroke_parts = {}
                for part in stroke_data:gmatch("[^;]+") do
                    table.insert(stroke_parts, part)
                end
                if #stroke_parts >= 2 then
                    local color_parts = {}
                    for num in stroke_parts[1]:gmatch("[^,]+") do
                        table.insert(color_parts, tonumber(num) or 1)
                    end
                    local thickness = tonumber(stroke_parts[2]) or 2
                    
                    local points = {}
                    for i = 3, #stroke_parts do
                        local coords = {}
                        for num in stroke_parts[i]:gmatch("[^,]+") do
                            table.insert(coords, tonumber(num) or 0)
                        end
                        if #coords >= 2 then
                            table.insert(points, {x = coords[1], y = coords[2]})
                        end
                    end
                    
                    if #points > 1 then
                        table.insert(state.strokes, {
                            color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                            thickness = thickness,
                            points = points
                        })
                    end
                end
            end
        end
    end

    local _, name = r.GetTrackName(track, "")
    local number = tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0
    if not name or name == "" then
        if number > 0 then
            name = string.format("Track %d", math.floor(number + 0.5))
        else
            name = "Track"
        end
    end
    state.track_name = name
    state.track_number = number
    ApplyTrackAppearance(track)

    local editor = EnsureEditorState()
    editor.caret = #state.text
    editor.selection_start = editor.caret
    editor.selection_end = editor.caret
    editor.selection_anchor = editor.caret
    editor.preferred_x = nil
    editor.scroll_to_caret = false
    editor.mouse_selecting = false
    editor.active = true
    editor.request_focus = true
end

local function LoadItemState(proj, item, item_guid)
    state.current_proj = proj
    state.current_item = item
    state.current_item_guid = item_guid
    state.current_track = nil
    state.current_track_guid = nil
    state.can_edit = item ~= nil
    state.dirty = false
    state.last_edit_time = 0
    state.bold_input_active = false

    if not item or not item_guid then
        SetNoTrackState(proj)
        return
    end

    local stored = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "text"))
    state.text = NormalizeLineEndings(stored or "")
    
    local stored_align = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "align"))
    if stored_align ~= "left" and stored_align ~= "center" and stored_align ~= "right" then
        stored_align = "left"
    end
    state.text_align = stored_align
    
    local stored_color = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "text_color"))
    if stored_color ~= "white" and stored_color ~= "black" then
        stored_color = "white"
    end
    state.text_color_mode = stored_color
    
    local stored_font_size = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "font_size")))
    local stored_font_family = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "font_family"))
    local min_font, max_font = 11, 26
    local default_font = 14
    local target_font = default_font
    if stored_font_size and stored_font_size >= min_font and stored_font_size <= max_font then
        target_font = math.floor(stored_font_size + 0.5)
    end
    local font_changed = false
    if target_font ~= state.font_size then
        state.font_size = target_font
        font_changed = true
    end
    if stored_font_family and stored_font_family ~= "" and stored_font_family ~= state.font_family then
        state.font_family = stored_font_family
        font_changed = true
    end
    if font_changed then
        BuildFont()
    end
    
    local stored_images = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "images"))
    local stored_auto_save = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "auto_save_enabled"))
    local stored_width = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "window_width")))
    local stored_height = tonumber(ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "window_height")))
    local stored_show_status = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "show_status"))
    local stored_tabs_enabled = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "tabs_enabled"))
    local stored_tabs_data = ReadProjExtState(proj, EXT_NAMESPACE, MakeItemKey(item_guid, "tabs_data"))
    
    local prev_width = state.window_width
    local prev_height = state.window_height
    
    state.auto_save_enabled = stored_auto_save and (stored_auto_save == "true") or true
    state.window_width = (stored_width and stored_width >= 300 and stored_width <= 3000) and stored_width or 600
    state.window_height = (stored_height and stored_height >= 250 and stored_height <= 3000) and stored_height or 400
    state.show_status = (stored_show_status == nil or stored_show_status == "") and true or (stored_show_status == "true")
    
    -- Load tabs data
    state.tabs_enabled = stored_tabs_enabled == "true"
    state.tabs = {}
    state.active_tab_index = 1
    state.strokes = {}  -- Reset strokes
    
    if stored_tabs_data and stored_tabs_data ~= "" then
        local parts = {}
        for part in stored_tabs_data:gmatch("[^|]+") do
            table.insert(parts, part)
        end
        
        if #parts >= 2 then
            local tab_count = tonumber(parts[1]) or 0
            state.active_tab_index = tonumber(parts[2]) or 1
            
            for i = 3, #parts do
                local colon_pos = parts[i]:find(":")
                if colon_pos then
                    local name = parts[i]:sub(1, colon_pos - 1):gsub("::", ":"):gsub("||", "|")
                    local text = parts[i]:sub(colon_pos + 1):gsub("::", ":"):gsub("||", "|")
                    table.insert(state.tabs, {name = name, text = text, images = {}, strokes = {}})
                end
            end
            
            -- Load images for each tab
            for idx = 1, #state.tabs do
                local tab_images_key = MakeItemKey(item_guid, "tab" .. idx .. "_images")
                local stored_tab_images = ReadProjExtState(proj, EXT_NAMESPACE, tab_images_key)
                if stored_tab_images and stored_tab_images ~= "" then
                    state.tabs[idx].images = {}
                    for img_data in stored_tab_images:gmatch("[^|]+") do
                        local img_parts = {}
                        for part in img_data:gmatch("[^;]+") do
                            table.insert(img_parts, part)
                        end
                        if #img_parts >= 5 then
                            local img_id = tonumber(img_parts[1])
                            local img_path = img_parts[2]:gsub("::", ":")
                            local img_x = tonumber(img_parts[3]) or 0
                            local img_y = tonumber(img_parts[4]) or 0
                            local img_scale = tonumber(img_parts[5]) or 100
                            
                            local img_texture = nil
                            if r.ImGui_CreateImage then
                                img_texture = r.ImGui_CreateImage(img_path)
                            end
                            
                            if img_texture then
                                local img_w, img_h = r.ImGui_Image_GetSize(img_texture)
                                table.insert(state.tabs[idx].images, {
                                    id = img_id,
                                    path = img_path,
                                    texture = img_texture,
                                    width = img_w,
                                    height = img_h,
                                    pos_x = img_x,
                                    pos_y = img_y,
                                    scale = img_scale
                                })
                            end
                        end
                    end
                end
                
                -- Load strokes for each tab
                local tab_strokes_key = MakeItemKey(item_guid, "tab" .. idx .. "_strokes")
                local stored_tab_strokes = ReadProjExtState(proj, EXT_NAMESPACE, tab_strokes_key)
                if stored_tab_strokes and stored_tab_strokes ~= "" then
                    state.tabs[idx].strokes = {}
                    for stroke_data in stored_tab_strokes:gmatch("[^|]+") do
                        local parts = {}
                        for part in stroke_data:gmatch("[^;]+") do
                            table.insert(parts, part)
                        end
                        if #parts >= 2 then
                            -- Parse color (r,g,b,a)
                            local color_parts = {}
                            for num in parts[1]:gmatch("[^,]+") do
                                table.insert(color_parts, tonumber(num) or 1)
                            end
                            local thickness = tonumber(parts[2]) or 2
                            
                            -- Parse points
                            local points = {}
                            for i = 3, #parts do
                                local coords = {}
                                for num in parts[i]:gmatch("[^,]+") do
                                    table.insert(coords, tonumber(num) or 0)
                                end
                                if #coords >= 2 then
                                    table.insert(points, {x = coords[1], y = coords[2]})
                                end
                            end
                            
                            if #points > 1 then
                                table.insert(state.tabs[idx].strokes, {
                                    color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                                    thickness = thickness,
                                    points = points
                                })
                            end
                        end
                    end
                end
            end
            
            if state.tabs[state.active_tab_index] then
                state.text = state.tabs[state.active_tab_index].text or ""
                state.images = state.tabs[state.active_tab_index].images or {}
                state.strokes = state.tabs[state.active_tab_index].strokes or {}
            end
        end
    end
    
    if prev_width ~= state.window_width or prev_height ~= state.window_height then
        state.window_size_needs_update = true
    end
    
    -- Load images and strokes when tabs are disabled
    if not state.tabs_enabled then
        LoadImagesFromString(stored_images)
        
        local strokes_key = MakeItemKey(item_guid, "strokes")
        local stored_strokes = ReadProjExtState(proj, EXT_NAMESPACE, strokes_key)
        if stored_strokes and stored_strokes ~= "" then
            state.strokes = {}
            for stroke_data in stored_strokes:gmatch("[^|]+") do
                local stroke_parts = {}
                for part in stroke_data:gmatch("[^;]+") do
                    table.insert(stroke_parts, part)
                end
                if #stroke_parts >= 2 then
                    local color_parts = {}
                    for num in stroke_parts[1]:gmatch("[^,]+") do
                        table.insert(color_parts, tonumber(num) or 1)
                    end
                    local thickness = tonumber(stroke_parts[2]) or 2
                    
                    local points = {}
                    for i = 3, #stroke_parts do
                        local coords = {}
                        for num in stroke_parts[i]:gmatch("[^,]+") do
                            table.insert(coords, tonumber(num) or 0)
                        end
                        if #coords >= 2 then
                            table.insert(points, {x = coords[1], y = coords[2]})
                        end
                    end
                    
                    if #points > 1 then
                        table.insert(state.strokes, {
                            color = {r = color_parts[1] or 1, g = color_parts[2] or 0, b = color_parts[3] or 0, a = color_parts[4] or 1},
                            thickness = thickness,
                            points = points
                        })
                    end
                end
            end
        end
    end

    if item then
        local track = r.GetMediaItem_Track(item)
        if track then
            local _, track_name = r.GetTrackName(track, "")
            local track_number = tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0
            local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
            local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")

            local item_name = "Item"
            local take = r.GetActiveTake(item)
            if take then
                local _, take_name = r.GetTakeName(take)
                if take_name and take_name ~= "" then
                    item_name = take_name
                else
                    local source = r.GetMediaItemTake_Source(take)
                    if source then
                        local filename = r.GetMediaSourceFileName(source, "")
                        if filename and filename ~= "" then
                            item_name = filename:match("([^/\\]+)$") or filename
                        end
                    end
                end
            end
            
            state.track_name = string.format("%s (Track %d: %s) - Pos: %.2fs", item_name, track_number, track_name or "Unnamed", pos)
            state.track_number = track_number
            ApplyItemAppearance(item)
        end
    end

    local editor = EnsureEditorState()
    editor.caret = #state.text
    editor.selection_start = #state.text
    editor.selection_end = #state.text
    editor.selection_anchor = #state.text
    editor.mouse_selecting = false
    editor.active = false
    editor.request_focus = true
end

local function UpdateActiveItemContext(force)
    local proj = GetActiveProject()
    local item = GetFirstSelectedItem(proj)
    local item_guid = item and GetItemGUID(item) or nil

    local proj_changed = proj ~= state.current_proj
    local guid_changed = item_guid ~= state.current_item_guid

    if force or proj_changed or guid_changed then
        if not force and state.can_edit and state.current_proj and (state.current_track_guid or state.current_item_guid) then
            SaveNotebook()
        end
        if item then
            LoadItemState(proj, item, item_guid)
        else
            SetNoTrackState(proj)
        end
    end
end

local function UpdateActiveProjectContext(force)
    local proj = GetActiveProject()
    local proj_changed = proj ~= state.current_proj

    if force or proj_changed then
        if not force and state.can_edit and state.current_proj then
            SaveNotebook()
        end
        LoadProjectState(proj)
    end
end

local function UpdateActiveGlobalContext(force)
    -- Global state never changes (always the same across all projects)
    -- We need to check if we're actually already showing global content
    -- by verifying that the GUIDs were cleared by LoadGlobalState
    local was_global_loaded = (state.current_track_guid == nil and 
                                state.current_item_guid == nil and 
                                state.track_name == "Global Notes")
    
    if force or not was_global_loaded then
        if not force and state.can_edit and state.current_proj then
            SaveNotebook()
        end
        LoadGlobalState()
    end
end

UpdateActiveTrackContext = function(force)
    local proj = GetActiveProject()
    local track = GetFirstSelectedTrack(proj)
    local track_guid = track and r.GetTrackGUID(track) or nil

    local proj_changed = proj ~= state.current_proj
    local guid_changed = track_guid ~= state.current_track_guid

    if force or proj_changed or guid_changed then
        if not force and state.can_edit and state.current_proj and (state.current_track_guid or state.current_item_guid) then
            SaveNotebook()
        end
        if track then
            LoadTrackState(proj, track, track_guid)
        else
            SetNoTrackState(proj)
        end
    end
end

UpdateActiveContext = function(force)
    if state.mode == "item" then
        UpdateActiveItemContext(force)
    elseif state.mode == "project" then
        UpdateActiveProjectContext(force)
    elseif state.mode == "global" then
        UpdateActiveGlobalContext(force)
    else
        UpdateActiveTrackContext(force)
    end
end

local EditorConstants = {
    padding_x = 14,
    padding_y = 10,
    caret_width = 1.6,
    blink_interval = 0.55,
    scroll_margin = 4,
}

local StatusBarConstants = {
    height = 26,
}

local function ResolveColorU32(color_idx)
    if has_get_color_u32 then
        return r.ImGui_GetColorU32(ctx, color_idx)
    end

    if has_style_color then
        local cr, cg, cb, ca = r.ImGui_GetStyleColor(ctx, color_idx)
        if cr then
            return PackColorToU32(cr, cg, cb, ca)
        end
    end

    if has_style_color_vec4 then
        local cr, cg, cb, ca = r.ImGui_GetStyleColorVec4(ctx, color_idx)
        if cr then
            return PackColorToU32(cr, cg, cb, ca)
        end
    end

    local get_color = r.ImGui_GetColor
    if type(get_color) == "function" then
        local value = get_color(ctx, color_idx)
        if type(value) == "number" then
            return value
        end
    end

    return PackColorToU32(1, 1, 1, 1)
end

local function GetEditorTextColor()
    if state.text_color_mode == "white" then
        return PackColorToU32(1, 1, 1, 1)
    elseif state.text_color_mode == "black" then
        return PackColorToU32(0, 0, 0, 1)
    end

    return ResolveColorU32(r.ImGui_Col_Text())
end

local function ApplyAlpha(color_u32, alpha)
    if not color_u32 then return nil end
    local clamped = alpha
    if clamped == nil then clamped = 1 end
    if clamped < 0 then clamped = 0 end
    if clamped > 1 then clamped = 1 end
    local r8 = (color_u32 >> 24) & 0xFF
    local g8 = (color_u32 >> 16) & 0xFF
    local b8 = (color_u32 >> 8) & 0xFF
    local a8 = math.floor(clamped * 255 + 0.5)
    return (r8 << 24) | (g8 << 16) | (b8 << 8) | a8
end

local function ClampToText(pos)
    if not pos then return 0 end
    if pos < 0 then return 0 end
    local max_len = #state.text
    if pos > max_len then return max_len end
    return pos
end

local function NormalizeSelection(editor)
    if not editor then return end
    local caret = ClampToText(editor.caret or 0)
    editor.caret = caret
    editor.selection_start = ClampToText(editor.selection_start or caret)
    editor.selection_end = ClampToText(editor.selection_end or caret)
    editor.selection_anchor = ClampToText(editor.selection_anchor or caret)
end

local function HasSelection(editor)
    return editor and editor.selection_start and editor.selection_end and editor.selection_start ~= editor.selection_end
end

local function GetSelectionRange(editor)
    if not HasSelection(editor) then return nil end
    local start_pos = editor.selection_start or 0
    local end_pos = editor.selection_end or start_pos
    if end_pos < start_pos then
        start_pos, end_pos = end_pos, start_pos
    end
    return start_pos, end_pos
end

local function ClearSelection(editor, pos)
    if not editor then return end
    local caret = ClampToText(pos or editor.caret or 0)
    editor.selection_start = caret
    editor.selection_end = caret
    editor.selection_anchor = caret
end

local function DeleteSelection(editor)
    local start_pos, end_pos = GetSelectionRange(editor)
    if not start_pos then return false end
    local prefix = start_pos > 0 and state.text:sub(1, start_pos) or ""
    local suffix = state.text:sub(end_pos + 1)
    state.text = prefix .. suffix
    local caret = ClampToText(start_pos)
    editor.caret = caret
    editor.selection_anchor = caret
    editor.selection_start = caret
    editor.selection_end = caret
    editor.scroll_to_caret = true
    editor.preferred_x = nil
    return true
end

local function IsShiftDown(io)
    if io and io.KeyShift ~= nil then
        return io.KeyShift and true or false
    end
    if type(r.ImGui_IsKeyDown) == "function" and r.ImGui_Key_LeftShift and r.ImGui_Key_RightShift then
        if r.ImGui_Key_LeftShift and r.ImGui_Key_RightShift then
            return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
        end
    end
    return false
end

local function GetSelectedText(editor)
    local start_pos, end_pos = GetSelectionRange(editor)
    if not start_pos then return nil end
    if end_pos <= start_pos then return nil end
    return state.text:sub(start_pos + 1, end_pos)
end

local function WriteClipboardText(text)
    if not text or text == "" then return end
    if type(r.ImGui_SetClipboardText) == "function" then
        local ok = pcall(r.ImGui_SetClipboardText, ctx, text)
        if ok then return end
    end
    if type(r.CF_SetClipboard) == "function" then
        pcall(r.CF_SetClipboard, text)
    end
end

local function ReadClipboardText()
    local text = nil
    if type(r.ImGui_GetClipboardText) == "function" then
        local ok, value = pcall(r.ImGui_GetClipboardText, ctx)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    if type(r.CF_GetClipboard) == "function" then
        local ok, value = pcall(r.CF_GetClipboard)
        if ok and type(value) == "string" and value ~= "" then
            return value
        end
    end
    return text
end

local function DrawTextFragment(draw_list, x, y, color, text, bold)
    if not text or text == "" then return end
    
    if not bold then
        r.ImGui_DrawList_AddText(draw_list, x, y, color, text)
        return
    end

    local thickness = math.max(0.9, state.font_size * 0.065)
    local offsets = {
        {0, 0},
        {thickness, 0},
        {-thickness, 0},
        {0, thickness},
        {0, -thickness},
    }
    for _, offset in ipairs(offsets) do
        r.ImGui_DrawList_AddText(draw_list, x + offset[1], y + offset[2], color, text)
    end
end

local function CalculateLineOffset(line, wrap_width, alignment)
    if not line or not wrap_width or wrap_width <= 0 then return 0 end
    if alignment == "center" or alignment == "right" then
        local slack = (wrap_width - (line.width or 0))
        if slack <= 0 then return 0 end
        if alignment == "center" then
            return slack * 0.5
        elseif alignment == "right" then
            return slack
        end
    end
    return 0
end

local function DrawSelectionHighlights(draw_list, editor, layout, area_x, area_y, scroll_y, line_height, wrap_width, alignment)
    local sel_start, sel_end = GetSelectionRange(editor)
    if not sel_start then return end

    local highlight_color = ResolveColorU32(r.ImGui_Col_TextSelectedBg())
    if highlight_color then
        highlight_color = ApplyAlpha(highlight_color, 0.32)
    else
        highlight_color = PackColorToU32(0.20, 0.46, 0.90, 0.28)
    end

    local sel_start_byte = sel_start + 1
    local sel_end_byte = sel_end
    local padding_x = EditorConstants.padding_x

    for idx, line in ipairs(layout.lines) do
        local line_offset = CalculateLineOffset(line, wrap_width, alignment)
        local base_x = area_x + padding_x + line_offset
        local line_top = area_y + EditorConstants.padding_y - scroll_y + (idx - 1) * line_height
        local line_bottom = line_top + line_height

        local segment_active = false
        local segment_start_x = 0
        local segment_end_x = 0

        if line.chars and #line.chars > 0 then
            for _, ch in ipairs(line.chars) do
                if not ch.is_format then
                    if ch.byte_end >= sel_start_byte and ch.byte_start <= sel_end_byte then
                        local ch_start = base_x + ch.x0
                        local ch_end = base_x + ch.x1
                        if not segment_active then
                            segment_active = true
                            segment_start_x = ch_start
                            segment_end_x = ch_end
                        else
                            segment_end_x = ch_end
                        end
                    elseif segment_active then
                        r.ImGui_DrawList_AddRectFilled(draw_list, segment_start_x, line_top, segment_end_x, line_bottom, highlight_color)
                        segment_active = false
                    end
                end
            end
            if segment_active then
                r.ImGui_DrawList_AddRectFilled(draw_list, segment_start_x, line_top, segment_end_x, line_bottom, highlight_color)
            end
        end

        local newline_byte = line.newline_byte
        if newline_byte and newline_byte >= sel_start_byte and newline_byte <= sel_end_byte then
            local x0 = base_x + line.width
            local extra = math.max(2.0, state.font_size * 0.35)
            r.ImGui_DrawList_AddRectFilled(draw_list, x0, line_top, x0 + extra, line_bottom, highlight_color)
        elseif (not line.chars or #line.chars == 0) then
            local line_start = (line.start_byte or 1) - 1
            local line_end = line.newline_byte and line.newline_byte or (line.end_byte or line_start)
            if sel_start < line_end and sel_end > line_start then
                local extra = math.max(2.0, state.font_size * 0.35)
                r.ImGui_DrawList_AddRectFilled(draw_list, base_x, line_top, base_x + extra, line_bottom, highlight_color)
            end
        end
    end
end

local function ClampCaret(text, caret)
    if not caret or caret < 0 then return 0 end
    local len = #text
    if caret > len then return len end
    return caret
end

EnsureEditorState = function()
    local editor = state.editor
    if not editor then
        editor = {
            caret = #state.text,
            preferred_x = nil,
            blink_visible = true,
            blink_time = r.time_precise(),
            active = false,
            request_focus = true,
            scroll_to_caret = true,
            selection_start = #state.text,
            selection_end = #state.text,
            selection_anchor = #state.text,
            mouse_selecting = false,
        }
        state.editor = editor
    else
        editor.caret = ClampCaret(state.text, editor.caret or #state.text)
    end
    NormalizeSelection(editor)
    return editor
end

local function InsertTextAtCaret(text, caret, insert_text)
    if not insert_text or insert_text == "" then return text, caret end
    local prefix = caret > 0 and text:sub(1, caret) or ""
    local suffix = text:sub(caret + 1)
    local new_text = prefix .. insert_text .. suffix
    local new_caret = caret + #insert_text
    return new_text, new_caret
end

local function DeletePreviousChar(text, caret)
    if caret <= 0 then return text, caret end
    local start = utf8.offset(text, -1, caret + 1)
    if not start then return text, caret end
    local new_text = text:sub(1, start - 1) .. text:sub(caret + 1)
    local new_caret = start - 1
    if new_caret < 0 then new_caret = 0 end
    return new_text, new_caret
end

local function DeleteNextChar(text, caret)
    local next_start = utf8.offset(text, 1, caret + 1)
    if not next_start then return text, caret end
    local next_after = utf8.offset(text, 2, caret + 1)
    if not next_after then next_after = #text + 1 end
    local new_text = text:sub(1, next_start - 1) .. text:sub(next_after)
    return new_text, caret
end

local function ToggleBoldFormatting(editor)
    if not state.can_edit then return end
    if not editor then return end

    local now = r.time_precise()
    local text_modified = false

    if HasSelection(editor) then
        local selected_text = GetSelectedText(editor)
        if selected_text and selected_text ~= "" then
            if DeleteSelection(editor) then
                text_modified = true
            end
            local insert_text = "**" .. selected_text .. "**"
            local new_text, new_caret = InsertTextAtCaret(state.text, editor.caret, insert_text)
            state.text = new_text
            editor.caret = new_caret
            text_modified = true
        end
        state.bold_input_active = false
        ClearSelection(editor, editor.caret)
    else
        local was_active = state.bold_input_active and true or false
        local new_text, new_caret = InsertTextAtCaret(state.text, editor.caret, "**")
        if new_text ~= state.text or new_caret ~= editor.caret then
            state.text = new_text
            editor.caret = new_caret
            text_modified = true
        end
        state.bold_input_active = not was_active
        ClearSelection(editor, editor.caret)
    end

    if text_modified then
        state.dirty = true
        state.last_edit_time = now
        editor.scroll_to_caret = true
    end

    editor.preferred_x = nil
    editor.blink_visible = true
    editor.blink_time = now
    editor.mouse_selecting = false
    NormalizeSelection(editor)
end

local function MoveCaretLeft(text, caret)
    if caret <= 0 then return 0 end
    local start = utf8.offset(text, -1, caret + 1)
    if not start then return 0 end
    return start - 1
end

local function MoveCaretRight(text, caret)
    local next_after = utf8.offset(text, 2, caret + 1)
    if not next_after then return #text end
    return next_after - 1
end

local function BuildEditorLayout(ctx, text, wrap_width, line_height)
    local lines = {}
    local len = #text
    local i = 1
    local char_index = 0
    local current_chars = {}
    local current_width = 0
    local last_break_idx = nil
    local line_start_byte = 1
    local bold_active = false

    local function recalc_width()
        current_width = 0
        last_break_idx = nil
        for idx, info in ipairs(current_chars) do
            current_width = current_width + info.width
            local ch = info.char
            if ch == " " or ch == "\t" then
                last_break_idx = idx
            end
        end
    end

    local function finalize_line(start_byte, chars, newline_byte)
        local line = {
            start_byte = start_byte,
            newline_byte = newline_byte,
            chars = {},
            width = 0,
        }
        local display_parts = {}
        local fragments = {}
        local current_fragment = nil
        local x = 0
        for idx, info in ipairs(chars) do
            local entry = {
                byte_start = info.byte_start,
                byte_end = info.byte_end,
                char = info.char,
                width = info.width,
                x0 = x,
                x1 = x + info.width,
                index = info.index,
                bold = info.bold,
                is_format = info.is_format,
            }
            line.chars[idx] = entry
            if not info.is_format and info.char ~= "" then
                if not current_fragment or current_fragment.bold ~= info.bold then
                    current_fragment = {
                        bold = info.bold,
                        text_parts = {},
                        x = entry.x0,
                        last_x = entry.x0,
                    }
                    table.insert(fragments, current_fragment)
                end
                current_fragment.last_x = entry.x1
                table.insert(current_fragment.text_parts, info.char)
                display_parts[#display_parts + 1] = info.char
            elseif not info.is_format then
                display_parts[#display_parts + 1] = info.char
            end
            x = x + info.width
        end
        for _, fragment in ipairs(fragments) do
            fragment.text = table.concat(fragment.text_parts)
            fragment.text_parts = nil
            fragment.width = math.max(0, (fragment.last_x or fragment.x) - fragment.x)
        end
        line.fragments = fragments
        line.width = x
        if #chars > 0 then
            line.end_byte = chars[#chars].byte_end
        else
            line.end_byte = start_byte - 1
        end
        line.text = table.concat(display_parts)
        table.insert(lines, line)
    end

    while i <= len do
        local byte = text:byte(i)
        if byte == 13 then
            i = i + 1
        elseif byte == 10 then
            finalize_line(line_start_byte, current_chars, i)
            current_chars = {}
            current_width = 0
            last_break_idx = nil
            line_start_byte = i + 1
            i = i + 1
        else
            if byte == 42 and i < len and text:byte(i + 1) == 42 then
                bold_active = not bold_active
                for offset = 0, 1 do
                    local start_idx = i + offset
                    local next_idx = start_idx + 1
                    if next_idx > len + 1 then next_idx = len + 1 end
                    char_index = char_index + 1
                    local info = {
                        char = "*",
                        width = 0,
                        byte_start = start_idx,
                        byte_end = next_idx - 1,
                        index = char_index,
                        is_format = true,
                        bold = bold_active,
                    }
                    table.insert(current_chars, info)
                end
                current_width = current_width
                i = i + 2
            else
            local next_i = utf8.offset(text, 2, i)
            if not next_i then next_i = len + 1 end
            local char = text:sub(i, next_i - 1)
            char_index = char_index + 1
            local width = select(1, r.ImGui_CalcTextSize(ctx, char))
            if not width or width <= 0 then width = state.font_size * 0.55 end
            local info = {
                char = char,
                width = width,
                byte_start = i,
                byte_end = next_i - 1,
                index = char_index,
                is_format = false,
                bold = bold_active,
            }
            table.insert(current_chars, info)
            current_width = current_width + width
            if char == " " or char == "\t" then
                last_break_idx = #current_chars
            end
            if wrap_width > 0 and current_width > wrap_width and #current_chars > 1 then
                local break_idx = last_break_idx and last_break_idx or (#current_chars - 1)
                if break_idx < 1 then break_idx = #current_chars - 1 end
                if break_idx < 1 then break_idx = #current_chars end
                local line_chars = {}
                for idx = 1, break_idx do
                    line_chars[#line_chars + 1] = current_chars[idx]
                end
                while #line_chars > 0 and line_chars[#line_chars].char:match("%s") do
                    table.remove(line_chars)
                end
                finalize_line(line_start_byte, line_chars, nil)
                local leftover = {}
                for idx = break_idx + 1, #current_chars do
                    leftover[#leftover + 1] = current_chars[idx]
                end
                current_chars = leftover
                if #current_chars > 0 then
                    line_start_byte = current_chars[1].byte_start
                else
                    line_start_byte = next_i
                end
                recalc_width()
            end
            i = next_i
            end
        end
    end

    finalize_line(line_start_byte, current_chars, nil)

    local layout = {
        lines = lines,
        char_count = char_index,
        line_height = line_height,
    }
    layout.total_height = math.max(line_height, #lines * line_height)
    return layout
end

local function CaretAtLinePosition(line, target_x)
    if not line then return 0 end
    local caret = (line.start_byte or 1) - 1
    local chars = line.chars
    if not chars or #chars == 0 then
        if line.newline_byte then
            return line.newline_byte
        end
        return caret
    end
    for _, ch in ipairs(chars) do
        local mid = ch.x0 + (ch.width * 0.5)
        if target_x < mid then
            return ch.byte_start - 1
        end
        caret = ch.byte_end
    end
    if line.newline_byte then
        return line.newline_byte
    end
    return caret
end

local function LocateCaret(layout, caret)
    local lines = layout.lines
    if not lines or #lines == 0 then
        return 1, 0.0, 0.0, nil
    end
    caret = ClampCaret(state.text, caret)
    if caret <= 0 then
        return 1, 0.0, 0.0, lines[1]
    end
    for idx, line in ipairs(lines) do
        if caret < line.start_byte then
            local y = (idx - 1) * layout.line_height
            return idx, 0.0, y, line
        end
        if line.end_byte >= line.start_byte and caret <= line.end_byte then
            local x = 0.0
            for _, ch in ipairs(line.chars) do
                if caret < ch.byte_start then
                    break
                end
                if caret >= ch.byte_end then
                    x = ch.x1
                else
                    x = ch.x0
                    break
                end
                if caret == ch.byte_end then
                    x = ch.x1
                end
            end
            local y = (idx - 1) * layout.line_height
            return idx, x, y, line
        end
        if line.newline_byte and caret == line.newline_byte then
        elseif not line.newline_byte and idx == #lines and caret > line.end_byte then
            local y = (idx - 1) * layout.line_height
            return idx, line.width, y, line
        end
    end
    local last_idx = #lines
    local last_line = lines[last_idx]
    local y = (last_idx - 1) * layout.line_height
    local x = last_line and last_line.width or 0.0
    return last_idx, x, y, last_line
end

local function CaretFromMouse(layout, local_x, local_y, wrap_width, alignment)
    local lines = layout.lines
    if not lines or #lines == 0 then
        return 0, 0
    end
    local line_height = layout.line_height
    local idx = math.floor(local_y / line_height) + 1
    if idx < 1 then idx = 1 end
    if idx > #lines then idx = #lines end
    local line = lines[idx]
    local offset = CalculateLineOffset(line, wrap_width, alignment)
    local relative_x = local_x - offset
    if relative_x < 0 then relative_x = 0 end
    return CaretAtLinePosition(line, relative_x), relative_x
end

local function HandleEditorInput(ctx, editor, layout, wrap_width, line_height, max_text_height, editing_enabled)
    local text_changed = false
    local caret_changed = false
    local now = r.time_precise()
    local io = r.ImGui_GetIO and r.ImGui_GetIO(ctx) or nil
    local ctrl_down = false
    if io and io.KeyCtrl ~= nil then
        ctrl_down = io.KeyCtrl and true or false
    elseif type(r.ImGui_IsKeyDown) == "function" and r.ImGui_Key_LeftCtrl and r.ImGui_Key_RightCtrl then
        ctrl_down = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl())
    end
    local shift_down = IsShiftDown(io)

    if not editing_enabled then
        editor.active = false
        editor.scroll_to_caret = false
        editor.blink_visible = false
        return false
    end

    local function capture_editor_state()
        return {
            caret = editor.caret,
            selection_start = editor.selection_start,
            selection_end = editor.selection_end,
            selection_anchor = editor.selection_anchor,
            scroll_to_caret = editor.scroll_to_caret,
            preferred_x = editor.preferred_x,
        }
    end

    local function restore_editor_state(snapshot)
        if not snapshot then return end
        editor.caret = snapshot.caret
        editor.selection_start = snapshot.selection_start
        editor.selection_end = snapshot.selection_end
        editor.selection_anchor = snapshot.selection_anchor
        editor.scroll_to_caret = snapshot.scroll_to_caret
        editor.preferred_x = snapshot.preferred_x
    end

    local function would_exceed_height(candidate_text)
        if not max_text_height or max_text_height <= 0 then
            return false
        end
        local candidate_layout = BuildEditorLayout(ctx, candidate_text, wrap_width, line_height)
        return candidate_layout.total_height > max_text_height
    end

    local function ctrl_combo(key_const)
        if not key_const then return false end
        if has_key_chord and r.ImGui_Mod_Ctrl then
            return r.ImGui_IsKeyChordPressed(ctx, r.ImGui_Mod_Ctrl() | key_const)
        end
        if not ctrl_down then return false end
        if not has_key_pressed then return false end
        return r.ImGui_IsKeyPressed(ctx, key_const, false)
    end

    local function move_caret_to(new_caret, extend_selection)
        new_caret = ClampCaret(state.text, new_caret)
        if extend_selection then
            editor.selection_anchor = ClampToText(editor.selection_anchor or editor.caret or new_caret)
            editor.selection_end = new_caret
            editor.selection_start = editor.selection_anchor
            editor.caret = new_caret
        else
            editor.caret = new_caret
            ClearSelection(editor, new_caret)
        end
        caret_changed = true
    end

    local function apply_newline()
        local snapshot = capture_editor_state()
        local previous_text = state.text
        if HasSelection(editor) then
            DeleteSelection(editor)
        end
        local new_text, new_caret = InsertTextAtCaret(state.text, editor.caret, "\n")
        if would_exceed_height(new_text) then
            state.text = previous_text
            restore_editor_state(snapshot)
            return
        end
        state.text = new_text
        editor.caret = new_caret
        ClearSelection(editor)
        text_changed = true
        caret_changed = true
    end

    local function process_codepoint(cp)
        if not cp then return false end
        if ctrl_down and cp ~= 10 and cp ~= 13 then return false end
        if cp == 10 or cp == 13 then
            apply_newline()
            return true
        end
        if cp < 32 then return false end
        local ok_char, char = pcall(utf8.char, cp)
        if not ok_char or not char or char == "" then return false end
        local snapshot = capture_editor_state()
        local previous_text = state.text
        if HasSelection(editor) then
            DeleteSelection(editor)
        end
        local new_text, new_caret = InsertTextAtCaret(state.text, editor.caret, char)
        if would_exceed_height(new_text) then
            state.text = previous_text
            restore_editor_state(snapshot)
            return false
        end
        state.text = new_text
        editor.caret = new_caret
        ClearSelection(editor)
        text_changed = true
        caret_changed = true
        return false
    end

    if editor.active then
        local key_a = r.ImGui_Key_A and r.ImGui_Key_A()
        local key_c = r.ImGui_Key_C and r.ImGui_Key_C()
        local key_x = r.ImGui_Key_X and r.ImGui_Key_X()
        local key_v = r.ImGui_Key_V and r.ImGui_Key_V()

        if key_a and ctrl_combo(key_a) then
            editor.selection_anchor = 0
            editor.selection_start = 0
            editor.selection_end = #state.text
            editor.caret = #state.text
            editor.mouse_selecting = false
            editor.scroll_to_caret = true
            editor.preferred_x = nil
            editor.blink_visible = true
            editor.blink_time = now
            caret_changed = true
        end

        if key_c and ctrl_combo(key_c) then
            local selected_text = GetSelectedText(editor)
            if selected_text and selected_text ~= "" then
                WriteClipboardText(selected_text)
            end
        end

        if key_x and ctrl_combo(key_x) then
            local selected_text = GetSelectedText(editor)
            if selected_text and selected_text ~= "" then
                WriteClipboardText(selected_text)
                if DeleteSelection(editor) then
                    text_changed = true
                    caret_changed = true
                end
                state.bold_input_active = false
            end
        end

        if key_v and ctrl_combo(key_v) then
            local clip = ReadClipboardText()
            if clip and clip ~= "" then
                clip = NormalizeLineEndings(clip)
                if clip ~= "" then
                    local snapshot = capture_editor_state()
                    local previous_text = state.text
                    if HasSelection(editor) then
                        DeleteSelection(editor)
                    end
                    local new_text, new_caret = InsertTextAtCaret(state.text, editor.caret, clip)
                    if would_exceed_height(new_text) then
                        state.text = previous_text
                        restore_editor_state(snapshot)
                    elseif new_text ~= state.text or new_caret ~= editor.caret then
                        state.text = new_text
                        editor.caret = new_caret
                        ClearSelection(editor)
                        text_changed = true
                        caret_changed = true
                        state.bold_input_active = false
                    end
                end
            end
        end

        if type(r.ImGui_GetInputQueueCharacter) == "function" then
            for idx = 0, math.huge do
                local primary, secondary = r.ImGui_GetInputQueueCharacter(ctx, idx)
                if not primary or primary == 0 then
                    break
                end
                local codepoint = secondary or primary
                process_codepoint(codepoint)
            end
        end

        if r.ImGui_Key_Enter and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false) then
            local marker = ""
            if state.list_mode ~= "none" then
                if state.list_mode == "bullet" then
                    marker = "• "
                else
                    local before_text = state.text:sub(1, editor.caret)
                    local last_line = before_text:match("[^\n]*$") 
                    local prev_num = last_line:match("^(%d+)%. ")
                    
                    if prev_num then
                        marker = (tonumber(prev_num) + 1) .. ". "
                    else
                        marker = "1. "
                    end
                end
            end
            
            process_codepoint(10)  
            
            if state.list_mode ~= "none" then
                local before = state.text:sub(1, editor.caret)
                local after = state.text:sub(editor.caret + 1)
                state.text = before .. marker .. after
                editor.caret = editor.caret + #marker
                ClearSelection(editor, editor.caret)
                text_changed = true
                caret_changed = true
            end
        end
        if r.ImGui_Key_KeypadEnter and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter(), false) then
            local marker = ""
            if state.list_mode ~= "none" then
                if state.list_mode == "bullet" then
                    marker = "• "
                else
                    local before_text = state.text:sub(1, editor.caret)
                    local last_line = before_text:match("[^\n]*$")  
                    local prev_num = last_line:match("^(%d+)%. ")
                    
                    if prev_num then
                        marker = (tonumber(prev_num) + 1) .. ". "
                    else
                        marker = "1. "
                    end
                end
            end
            
            process_codepoint(10)  
            
            if state.list_mode ~= "none" then
                local before = state.text:sub(1, editor.caret)
                local after = state.text:sub(editor.caret + 1)
                state.text = before .. marker .. after
                editor.caret = editor.caret + #marker
                ClearSelection(editor, editor.caret)
                text_changed = true
                caret_changed = true
            end
        end

        if r.ImGui_Key_Backspace and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Backspace(), true) then
            if HasSelection(editor) then
                if DeleteSelection(editor) then
                    text_changed = true
                    caret_changed = true
                end
            else
                local new_text, new_caret = DeletePreviousChar(state.text, editor.caret)
                if new_text ~= state.text or new_caret ~= editor.caret then
                    state.text = new_text
                    editor.caret = new_caret
                    ClearSelection(editor, editor.caret)
                    text_changed = true
                    caret_changed = true
                end
            end
        end

        if r.ImGui_Key_Delete and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Delete(), true) then
            if HasSelection(editor) then
                if DeleteSelection(editor) then
                    text_changed = true
                    caret_changed = true
                end
            else
                local new_text, new_caret = DeleteNextChar(state.text, editor.caret)
                if new_text ~= state.text then
                    state.text = new_text
                    editor.caret = new_caret
                    ClearSelection(editor, editor.caret)
                    text_changed = true
                    caret_changed = true
                end
            end
        end

        if r.ImGui_Key_LeftArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_LeftArrow(), true) then
            if HasSelection(editor) and not shift_down then
                local start_pos = GetSelectionRange(editor)
                if start_pos then
                    move_caret_to(start_pos, false)
                end
            else
                local new_caret = MoveCaretLeft(state.text, editor.caret)
                if new_caret ~= editor.caret or shift_down then
                    move_caret_to(new_caret, shift_down)
                end
            end
        end

        if r.ImGui_Key_RightArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_RightArrow(), true) then
            if HasSelection(editor) and not shift_down then
                local _, end_pos = GetSelectionRange(editor)
                if end_pos then
                    move_caret_to(end_pos, false)
                end
            else
                local new_caret = MoveCaretRight(state.text, editor.caret)
                if new_caret ~= editor.caret or shift_down then
                    move_caret_to(new_caret, shift_down)
                end
            end
        end

        if r.ImGui_Key_Home and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Home(), true) then
            local line_idx, _, _, line = LocateCaret(layout, editor.caret)
            if line then
                local home_caret = ClampCaret(state.text, (line.start_byte or 1) - 1)
                move_caret_to(home_caret, shift_down)
            end
        end

        if r.ImGui_Key_End and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_End(), true) then
            local line_idx, _, _, line = LocateCaret(layout, editor.caret)
            if line then
                local end_caret
                if line.newline_byte then
                    end_caret = line.newline_byte
                else
                    end_caret = ClampCaret(state.text, line.end_byte or #state.text)
                end
                move_caret_to(end_caret, shift_down)
            end
        end

        if r.ImGui_Key_UpArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow(), true) then
            local line_idx, caret_x = LocateCaret(layout, editor.caret)
            editor.preferred_x = editor.preferred_x or caret_x
            local target_idx = math.max(1, (line_idx or 1) - 1)
            local target_line = layout.lines[target_idx]
            if target_line then
                local new_caret = CaretAtLinePosition(target_line, editor.preferred_x)
                move_caret_to(new_caret, shift_down)
            end
        end

        if r.ImGui_Key_DownArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow(), true) then
            local line_idx, caret_x = LocateCaret(layout, editor.caret)
            editor.preferred_x = editor.preferred_x or caret_x
            local target_idx = math.min(#layout.lines, (line_idx or 1) + 1)
            local target_line = layout.lines[target_idx]
            if target_line then
                local new_caret = CaretAtLinePosition(target_line, editor.preferred_x)
                move_caret_to(new_caret, shift_down)
            end
        end
    end

    if caret_changed then
        editor.caret = ClampCaret(state.text, editor.caret)
        local _, caret_x = LocateCaret(layout, editor.caret)
        editor.preferred_x = caret_x
        editor.blink_visible = true
        editor.blink_time = now
        editor.scroll_to_caret = true
    end

    if text_changed then
        state.dirty = true
        state.last_edit_time = now
    end

    NormalizeSelection(editor)
    return text_changed
end

BuildFont = function()
    if font and type(r.ImGui_Detach) == "function" then
        r.ImGui_Detach(ctx, font)
    end

    local new_font
    if type(r.ImGui_CreateFont) == "function" then
        local ok, created = pcall(r.ImGui_CreateFont, state.font_family or "sans-serif", state.font_size)
        if ok then new_font = created end
    end

    if not new_font then
        return
    end

    font = new_font
    if type(r.ImGui_Attach) == "function" then
        r.ImGui_Attach(ctx, font)
    end
end

local function DrawMenuBar()
    if not r.ImGui_BeginMenuBar(ctx) then return true end
    
    local transparent = PackColorToU32(0, 0, 0, 0)
    
    local colors_pushed = 0
    
    if r.ImGui_Col_HeaderHovered then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), transparent)
        colors_pushed = colors_pushed + 1
    end
    if r.ImGui_Col_HeaderActive then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), transparent)
        colors_pushed = colors_pushed + 1
    end
    if r.ImGui_Col_Header then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), transparent)
        colors_pushed = colors_pushed + 1
    end
    
    local editor = EnsureEditorState()
    local file_menu_offset_y = 2
    local file_cursor_x, file_cursor_y = r.ImGui_GetCursorPos(ctx)
    
    local toolbar_base_y = file_cursor_y + file_menu_offset_y
    local center_button_offset_y = 1
    local close_button_offset_y = toolbar_base_y - 2
    
    r.ImGui_SetCursorPos(ctx, file_cursor_x, close_button_offset_y)
    local close_size = 20.0
    local close_cursor_x, close_cursor_y = r.ImGui_GetCursorScreenPos(ctx)
    
    r.ImGui_InvisibleButton(ctx, "##close", close_size, close_size)
    local close_hovered = r.ImGui_IsItemHovered(ctx)
    local close_clicked = r.ImGui_IsItemClicked(ctx)
    
    if close_clicked then
        should_close = true
    end
    
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local center_x = close_cursor_x + close_size * 0.5
    local center_y = close_cursor_y + close_size * 0.65
    local radius = 5.0
    local close_color = close_hovered and 0xFF6666FF or 0xFF4444FF
    r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, close_color)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Close")
    end
    
    r.ImGui_SameLine(ctx, 0, 5)
    r.ImGui_SetCursorPosY(ctx, toolbar_base_y)
    if r.ImGui_BeginMenu(ctx, "File") then
        if r.ImGui_MenuItem(ctx, "New", "Ctrl+N", false, state.can_edit) then
            ResetNotebook()
        end
        if r.ImGui_MenuItem(ctx, "Save as TXT", nil, false, state.can_edit) then
            local ok, path = r.JS_Dialog_BrowseForSaveFile("Save notebook", SCRIPT_DIR, "notebook.txt", "Text files (*.txt)\0*.txt\0")
            if ok and path and path ~= "" then
                local file = io.open(path, "w")
                if file then
                    file:write(state.text)
                    file:close()
                end
            end
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Exit") then
            should_close = true
        end
        r.ImGui_EndMenu(ctx)
    end
    
    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_SetCursorPosY(ctx, toolbar_base_y)
    
    if r.ImGui_BeginMenu(ctx, "Font") then
        local font_families = {
            "sans-serif",
            "serif", 
            "monospace",
            "cursive",
            "Arial",
            "Courier New",
            "Times New Roman",
            "Verdana",
            "Georgia",
            "Comic Sans MS",
        }
        
        local current_font = state.font_family or "sans-serif"
        
        for _, family in ipairs(font_families) do
            local is_selected = (family == current_font)
            if r.ImGui_MenuItem(ctx, family, nil, is_selected) then
                if state.font_family ~= family then
                    state.font_family = family
                    BuildFont()
                    state.dirty = true
                    state.last_edit_time = r.time_precise()
                end
            end
        end
        
        r.ImGui_EndMenu(ctx)
    end
    
    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_SetCursorPosY(ctx, toolbar_base_y)
    
    local mode_text = "Track"
    if state.mode == "item" then
        mode_text = "Item"
    elseif state.mode == "project" then
        mode_text = "Project"
    elseif state.mode == "global" then
        mode_text = "Global"
    end
    local mode_tinted = state.mode ~= "track"
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent)
    if mode_tinted then
        local accent_color = PackColorToU32(0.48, 0.72, 1.0, 1.0)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), accent_color)
    end
    if r.ImGui_Button(ctx, mode_text .. "##mode_toggle") then
        if state.mode == "track" then
            state.mode = "item"
        elseif state.mode == "item" then
            state.mode = "project"
        elseif state.mode == "project" then
            state.mode = "global"
        else
            state.mode = "track"
        end
        UpdateActiveContext(true)
    end
    
    if (state.mode == "project" or state.mode == "global") and r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "mode_bg_color_popup")
    end
    
    if r.ImGui_BeginPopup(ctx, "mode_bg_color_popup") then
        r.ImGui_Text(ctx, "Background Color:")
        r.ImGui_Separator(ctx)
        
        for i, preset in ipairs(BG_COLOR_PRESETS) do
            -- Use preview color to show actual blended result
            local preview_r = preset.preview_r or preset.r
            local preview_g = preset.preview_g or preset.g
            local preview_b = preset.preview_b or preset.b
            local color_u32 = PackColorToU32(preview_r, preview_g, preview_b, 1.0)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color_u32)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color_u32)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), color_u32)
            
            if r.ImGui_Button(ctx, "    ##bgcol" .. i, 40, 20) then
                if state.mode == "project" then
                    if preset.a == 0 then
                        state.project_bg_color = nil
                    else
                        state.project_bg_color = {r = preset.r, g = preset.g, b = preset.b, a = preset.a}
                    end
                elseif state.mode == "global" then
                    if preset.a == 0 then
                        state.global_bg_color = nil
                    else
                        state.global_bg_color = {r = preset.r, g = preset.g, b = preset.b, a = preset.a}
                    end
                end
                state.dirty = true
                state.last_edit_time = r.time_precise()
                r.ImGui_CloseCurrentPopup(ctx)
            end
            
            r.ImGui_PopStyleColor(ctx, 3)
            
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, preset.name)
            end
            
            if i % 5 ~= 0 and i < #BG_COLOR_PRESETS then
                r.ImGui_SameLine(ctx)
            end
        end
        
        -- Brightness slider
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Brightness:")
        r.ImGui_SetNextItemWidth(ctx, 200)
        
        local current_brightness = (state.mode == "project" and state.project_bg_brightness) or state.global_bg_brightness or 1.0
        local changed, new_brightness = r.ImGui_SliderDouble(ctx, "##brightness", current_brightness, 0.5, 4.0, "%.2f")
        if changed then
            if state.mode == "project" then
                state.project_bg_brightness = new_brightness
            else
                state.global_bg_brightness = new_brightness
            end
            state.dirty = true
            state.last_edit_time = r.time_precise()
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    if mode_tinted then
        r.ImGui_PopStyleColor(ctx, 1)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        local tooltip = "Switch to "
        if state.mode == "track" then
            tooltip = tooltip .. "Item mode"
        elseif state.mode == "item" then
            tooltip = tooltip .. "Project mode"
        elseif state.mode == "project" then
            tooltip = tooltip .. "Global mode (Right-click for background color)"
        else
            tooltip = tooltip .. "Track mode (Right-click for background color)"
        end
        r.ImGui_SetTooltip(ctx, tooltip)
    end
    
    r.ImGui_SameLine(ctx, 0, 8)
    r.ImGui_SetCursorPosY(ctx, toolbar_base_y)
    r.ImGui_Text(ctx, "|")
    
    local button_height = r.ImGui_GetTextLineHeight(ctx) + 6
    local button_width = button_height
    local transparent_button = PackColorToU32(0, 0, 0, 0)
    local bold_accent = PackColorToU32(1.0, 0.78, 0.32, 1.0)
    local align_accent = PackColorToU32(0.48, 0.72, 1.0, 1.0)
    
    local function SameLineToolbar(spacing)
        r.ImGui_SameLine(ctx, 0, spacing or 4)
        r.ImGui_SetCursorPosY(ctx, toolbar_base_y)
    end
    
    SameLineToolbar()
    
    local tabs_icon = "☰"
    local tabs_tinted = state.tabs_enabled
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
    if tabs_tinted then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), align_accent)
    end
    local tabs_label = tabs_icon .. "##toggle_tabs"
    if r.ImGui_Button(ctx, tabs_label, button_width, button_height) then
        state.tabs_enabled = not state.tabs_enabled
        if state.tabs_enabled and #state.tabs == 0 then
            state.tabs = {{name = "Notes", text = state.text, images = state.images, strokes = state.strokes}}
            state.active_tab_index = 1
        elseif not state.tabs_enabled and #state.tabs > 0 then
            if state.tabs[state.active_tab_index] then
                state.text = state.tabs[state.active_tab_index].text
                state.images = state.tabs[state.active_tab_index].images or {}
                state.strokes = state.tabs[state.active_tab_index].strokes or {}
            end
        end
        state.dirty = true
        state.last_edit_time = r.time_precise()
    end
    if tabs_tinted then
        r.ImGui_PopStyleColor(ctx, 1)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, state.tabs_enabled and "Disable tabs" or "Enable tabs")
    end
    
    SameLineToolbar()
    
    local color_icon = state.text_color_mode == "white" and "■" or "▢"
    local color_tinted = state.text_color_mode == "black"
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
    if color_tinted then
        local dark_accent = PackColorToU32(0.3, 0.3, 0.3, 1.0)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), dark_accent)
    end
    local color_label = color_icon .. "##toggle_color"
    if r.ImGui_Button(ctx, color_label, button_width, button_height) then
        state.text_color_mode = state.text_color_mode == "white" and "black" or "white"
        SaveNotebook()
    end
    if color_tinted then
        r.ImGui_PopStyleColor(ctx, 1)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Toggle text color (white/black)")
    end

    SameLineToolbar()
    local editor = EnsureEditorState()
    local tinted = state.bold_input_active and true or false
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
    if tinted then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), bold_accent)
    end
    local bold_label = MonoIcon("𝗕") .. "##toggle_bold"
    if r.ImGui_Button(ctx, bold_label, button_width, button_height) then
        ToggleBoldFormatting(editor)
        editor.request_focus = true
    end
    if tinted then
        r.ImGui_PopStyleColor(ctx, 1)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Toggle bold")
    end

    SameLineToolbar()
    local alignments = {
        {icon = "|≡", value = "left", tooltip = "Align left"},
        {icon = "≡", value = "center", tooltip = "Align center"},
        {icon = "≡|", value = "right", tooltip = "Align right"},
    }
    for idx, info in ipairs(alignments) do
        if idx > 1 then
            SameLineToolbar()
        end
        local active = state.text_align == info.value
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
        local pushed_text = false
        if active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), align_accent)
            pushed_text = true
        end
        local icon_label = MonoIcon(info.icon) .. "##align_" .. info.value
        if r.ImGui_Button(ctx, icon_label, button_width, button_height) then
            if state.text_align ~= info.value then
                state.text_align = info.value
                state.dirty = true
                state.last_edit_time = r.time_precise()
            end
            editor.request_focus = true
        end
        if pushed_text then
            r.ImGui_PopStyleColor(ctx, 1)
        end
        r.ImGui_PopStyleColor(ctx, 3)
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, info.tooltip)
        end
    end

    SameLineToolbar()
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
    local image_label = "▦##load_image"
    if r.ImGui_Button(ctx, image_label, button_width, button_height) then
        local ok, path = r.JS_Dialog_BrowseForOpenFiles("Select Image", "", "*.png;*.jpg;*.jpeg;*.bmp;*.gif", "Images", false)
        if ok and path and path ~= "" then
            local image = AddImage(path)
            if image then
                state.dirty = true
                state.last_edit_time = r.time_precise()
                SaveNotebook()
            else
                r.ShowMessageBox("Failed to load image. Please check if the file format is supported.", "TK Notebook", 0)
            end
        end
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Load image")
    end
    
    SameLineToolbar()
    
    local drawing_active = state.drawing_enabled or state.eraser_mode
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
    if state.eraser_mode then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), PackColorToU32(1.0, 0.3, 0.3, 1.0))
    elseif drawing_active then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), bold_accent)
    end
    local draw_label = (state.eraser_mode and "🗑" or "✎") .. "##drawing_tool"
    if r.ImGui_Button(ctx, draw_label, button_width, button_height) then
        if state.eraser_mode then
            state.eraser_mode = false
        else
            state.drawing_enabled = not state.drawing_enabled
        end
    end
    if drawing_active then
        r.ImGui_PopStyleColor(ctx, 1)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        local tooltip = state.eraser_mode and "Eraser mode (click strokes to delete)\nRight-click for options" 
                        or (state.drawing_enabled and "Drawing enabled (click and drag to draw)\nRight-click for options" 
                        or "Enable drawing tool\nRight-click for options")
        r.ImGui_SetTooltip(ctx, tooltip)
    end
    
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "drawing_options")
    end
    
    if r.ImGui_BeginPopup(ctx, "drawing_options") then
        r.ImGui_Text(ctx, "Drawing Options")
        r.ImGui_Separator(ctx)
        
        r.ImGui_Text(ctx, "Current Pen Color:")
        local col_int = r.ImGui_ColorConvertDouble4ToU32(
            state.drawing_color.r, state.drawing_color.g, state.drawing_color.b, state.drawing_color.a)
        r.ImGui_ColorButton(ctx, "##current_color", col_int, 0, 40, 40)
        
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Color Presets:")
        local presets = {
            {name = "Red", r = 1.0, g = 0.0, b = 0.0, a = 1.0},
            {name = "Blue", r = 0.0, g = 0.5, b = 1.0, a = 1.0},
            {name = "Green", r = 0.0, g = 0.8, b = 0.2, a = 1.0},
            {name = "Yellow", r = 1.0, g = 0.9, b = 0.0, a = 1.0},
            {name = "Orange", r = 1.0, g = 0.6, b = 0.0, a = 1.0},
            {name = "Purple", r = 0.7, g = 0.0, b = 1.0, a = 1.0},
            {name = "Black", r = 0.0, g = 0.0, b = 0.0, a = 1.0},
            {name = "White", r = 1.0, g = 1.0, b = 1.0, a = 1.0},
        }
        for i, preset in ipairs(presets) do
            if i > 1 and (i - 1) % 4 ~= 0 then
                r.ImGui_SameLine(ctx)
            end
            local preset_color = PackColorToU32(preset.r, preset.g, preset.b, preset.a)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), preset_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), preset_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), preset_color)
            if r.ImGui_Button(ctx, "##preset_" .. i, 30, 30) then
                state.drawing_color.r = preset.r
                state.drawing_color.g = preset.g
                state.drawing_color.b = preset.b
                state.drawing_color.a = preset.a
            end
            r.ImGui_PopStyleColor(ctx, 3)
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, preset.name)
            end
        end
        
        r.ImGui_Separator(ctx)
        
        r.ImGui_Text(ctx, "Pen Thickness:")
        local thickness_changed, new_thickness = r.ImGui_SliderDouble(ctx, "##thickness", state.drawing_thickness, 1.0, 10.0, "%.1f")
        if thickness_changed then
            state.drawing_thickness = new_thickness
        end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_MenuItem(ctx, state.eraser_mode and "✓ Eraser Mode" or "Eraser Mode") then
            state.eraser_mode = not state.eraser_mode
            if state.eraser_mode then
                state.drawing_enabled = false 
            end
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Click on strokes to delete them")
        end
        
        r.ImGui_Separator(ctx)
        
        if r.ImGui_MenuItem(ctx, "Clear All Drawings") then
            state.strokes = {}
            state.dirty = true
            state.last_edit_time = r.time_precise()
            SaveNotebook()
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    SameLineToolbar()
    
    local list_active = state.list_mode ~= "none"
    local list_icon = state.list_mode == "bullet" and "•" or (state.list_mode == "numbered" and "#" or "≡")
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
    if list_active then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), align_accent)
    end
    local list_label = list_icon .. "##list_mode"
    if r.ImGui_Button(ctx, list_label, button_width, button_height) then
        if state.list_mode == "none" then
            state.list_mode = "bullet"
        else
            state.list_mode = "none"
        end
        local editor = EnsureEditorState()
        editor.request_focus = true
    end
    if list_active then
        r.ImGui_PopStyleColor(ctx, 1)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        local tooltip = list_active and ("List mode active (" .. (state.list_mode == "bullet" and "bullets" or "numbers") .. ")\nClick to disable\nRight-click for options") 
                        or "Enable list mode\nRight-click for options"
        r.ImGui_SetTooltip(ctx, tooltip)
    end
    
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "list_options")
    end
    
    if r.ImGui_BeginPopup(ctx, "list_options") then
        r.ImGui_Text(ctx, "List Type")
        r.ImGui_Separator(ctx)
        
        if r.ImGui_MenuItem(ctx, state.list_mode == "bullet" and "✓ Bullet (•)" or "Bullet (•)") then
            state.list_mode = "bullet"
        end
        
        if r.ImGui_MenuItem(ctx, state.list_mode == "numbered" and "✓ Numbered (1. 2. 3.)" or "Numbered (1. 2. 3.)") then
            state.list_mode = "numbered"
        end
        
        r.ImGui_EndPopup(ctx)
    end
    
    SameLineToolbar()
    
    local info_icon = state.show_status and "ⓘ" or "ⓘ"
    local info_tinted = state.show_status
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), transparent_button)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), transparent_button)
    if info_tinted then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), align_accent)
    end
    local info_label = info_icon .. "##toggle_info"
    if r.ImGui_Button(ctx, info_label, button_width, button_height) then
        state.show_status = not state.show_status
        state.dirty = true
        state.last_edit_time = r.time_precise()
        SaveNotebook()
    end
    if info_tinted then
        r.ImGui_PopStyleColor(ctx, 1)
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Toggle status bar")
    end

    SameLineToolbar()
    
    local slider_width = 60.0
    local slider_height = 16.0
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
    
    r.ImGui_InvisibleButton(ctx, "##font_size_slider", slider_width, slider_height)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    
    local x0, y0 = cursor_x, cursor_y
    local cx = x0 + 8.0
    local cy = y0 + slider_height * 0.65
    local track_w = slider_width - 16.0
    local min_val, max_val = 11, 26
    local norm = (state.font_size - min_val) / (max_val - min_val)
    if norm < 0.0 then norm = 0.0 elseif norm > 1.0 then norm = 1.0 end
    
    local font_changed = false
    if active then
        local mx, _ = r.ImGui_GetMousePos(ctx)
        local new_norm = (mx - cx) / math.max(1.0, track_w)
        if new_norm < 0.0 then new_norm = 0.0 elseif new_norm > 1.0 then new_norm = 1.0 end
        local new_font = math.floor(min_val + (new_norm * (max_val - min_val)) + 0.5)
        if new_font ~= state.font_size then
            state.font_size = new_font
            BuildFont()
            font_changed = true
        end
        norm = new_norm
    elseif hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        local mx, _ = r.ImGui_GetMousePos(ctx)
        local new_norm = (mx - cx) / math.max(1.0, track_w)
        if new_norm < 0.0 then new_norm = 0.0 elseif new_norm > 1.0 then new_norm = 1.0 end
        local new_font = math.floor(min_val + (new_norm * (max_val - min_val)) + 0.5)
        if new_font ~= state.font_size then
            state.font_size = new_font
            BuildFont()
            font_changed = true
        end
        norm = new_norm
    end
    if font_changed then
        state.dirty = true
        state.last_edit_time = r.time_precise()
    end
    
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local track_col = 0x666666FF  
    local knob_x = cx + norm * track_w
    
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, cx + track_w, cy, track_col, 2.0)
    r.ImGui_DrawList_AddCircleFilled(draw_list, knob_x, cy, 6.0, 0xFFFFFFFF)
    r.ImGui_DrawList_AddCircle(draw_list, knob_x, cy, 6.0, 0x333333FF, 0, 1.0)
    
    if hovered then
        r.ImGui_SetTooltip(ctx, string.format("Font size: %d", state.font_size))
    end


    if colors_pushed > 0 then
        r.ImGui_PopStyleColor(ctx, colors_pushed)
    end
    
    r.ImGui_EndMenuBar(ctx)
    return not should_close
end

local function HandleShortcuts()
    if not state.can_edit then return end
    local function ctrl_combo(key_const)
        if has_key_chord then
            return r.ImGui_IsKeyChordPressed(ctx, r.ImGui_Mod_Ctrl() | key_const)
        end
        if not has_key_pressed or type(r.ImGui_IsKeyDown) ~= "function" then return false end
        local ctrl_down = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl())
        if not ctrl_down then return false end
        return r.ImGui_IsKeyPressed(ctx, key_const, false)
    end

    if ctrl_combo(r.ImGui_Key_N()) then
        ResetNotebook()
    end
end

local function AutoSaveText()
    if not state.can_edit or not state.dirty then return end
    local debounce_time = 0.5
    if r.time_precise() - state.last_edit_time >= debounce_time then
        SaveNotebook()
    end
end

local function DrawStatusBar(status_height)
    if not state.show_status then return end
    
    if state.mode == "item" and state.current_item then
        if not r.ValidatePtr2(0, state.current_item, "MediaItem*") then
            state.current_item = nil
            state.current_item_guid = nil
            UpdateActiveContext(true)
        end
    end
    
    status_height = status_height or StatusBarConstants.height
    r.ImGui_Separator(ctx)
    local child_flags = 0
    if r.ImGui_WindowFlags_NoScrollbar then
        child_flags = child_flags | r.ImGui_WindowFlags_NoScrollbar()
    end
    if r.ImGui_WindowFlags_NoScrollWithMouse then
        child_flags = child_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
    end
    local border = 0
    if r.ImGui_BeginChild(ctx, "##status_bar", 0, status_height, border, child_flags) then
        local word_count = WordCount(state.text)
        local char_count = CharacterCount(state.text)
        local parts = {}
        if state.mode == "global" then
            table.insert(parts, "Global Notes")
        elseif state.mode == "project" then
            table.insert(parts, "Project Notes")
        elseif state.mode == "item" and state.current_item then
            local item_label = "Item"
            if state.track_name then
                item_label = state.track_name 
            elseif state.current_item then
                local track = nil
                if r.ValidatePtr2(0, state.current_item, "MediaItem*") then
                    track = r.GetMediaItem_Track(state.current_item)
                end
                if track then
                    local pos = r.GetMediaItemInfo_Value(state.current_item, "D_POSITION")
                    local track_number = tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0
                    item_label = string.format("Item on Track %d - Pos: %.2fs", track_number, pos)
                else
                    item_label = "Item (deleted)"
                end
            end
            table.insert(parts, item_label)
        elseif state.current_track and state.track_name then
            local track_label
            if state.track_number and state.track_number > 0 then
                track_label = string.format("Track %d: %s", math.floor(state.track_number + 0.5), state.track_name)
            else
                track_label = state.track_name
            end
            table.insert(parts, track_label)
        else
            if state.mode == "global" then
                table.insert(parts, "Global Notes")
            elseif state.mode == "item" then
                table.insert(parts, "No item selected")
            elseif state.mode == "project" then
                table.insert(parts, "Project Notes")
            else
                table.insert(parts, "No track selected")
            end
        end
        table.insert(parts, string.format("%d words", word_count))
        table.insert(parts, string.format("%d characters", char_count))
        local status = table.concat(parts, "  |  ")
        local text_height = r.ImGui_GetTextLineHeight(ctx)
        r.ImGui_SetCursorPosY(ctx, math.max(0, (status_height - text_height) * 0.5))
        r.ImGui_Text(ctx, status)
    end
    r.ImGui_EndChild(ctx)
end

local function DrawTabBar()
    if not state.tabs_enabled or #state.tabs == 0 then
        return 0
    end
    
    local tab_height = 28
    local tab_min_width = 80
    local tab_max_width = 150
    local add_button_width = 30
    local close_button_size = 16
    
    if not r.ImGui_BeginChild(ctx, "##tab_bar", 0, tab_height, 0) then
        return 0
    end
    
    local avail_width = r.ImGui_GetContentRegionAvail(ctx)
    local tab_bg = PackColorToU32(0.15, 0.15, 0.15, 1.0)
    local tab_active_bg = PackColorToU32(0.25, 0.25, 0.25, 1.0)
    local tab_hover_bg = PackColorToU32(0.2, 0.2, 0.2, 1.0)
    local tab_text = PackColorToU32(0.8, 0.8, 0.8, 1.0)
    local tab_active_text = PackColorToU32(1.0, 1.0, 1.0, 1.0)
    
    for i, tab in ipairs(state.tabs) do
        if i > 1 then
            r.ImGui_SameLine(ctx, 0, 2)
        end
        
        local is_active = (i == state.active_tab_index)
        local tab_name = tab.name or ("Tab " .. i)
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_active and tab_active_bg or tab_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), tab_hover_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), tab_active_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), is_active and tab_active_text or tab_text)
        
        local tab_label = tab_name .. "##tab_" .. i
        if r.ImGui_Button(ctx, tab_label, tab_min_width, tab_height - 4) then
            if state.active_tab_index ~= i then
                if state.tabs[state.active_tab_index] then
                    state.tabs[state.active_tab_index].text = state.text
                    state.tabs[state.active_tab_index].images = state.images
                    state.tabs[state.active_tab_index].strokes = state.strokes
                end
                state.active_tab_index = i
                state.text = state.tabs[i].text or ""
                state.images = state.tabs[i].images or {}
                state.strokes = state.tabs[i].strokes or {}
                
                for _, img in ipairs(state.images) do
                    if img.path then
                        img.texture = r.ImGui_CreateImage(img.path)
                        if img.texture then
                            local w, h = r.ImGui_Image_GetSize(img.texture)
                            img.width = w
                            img.height = h
                        end
                    end
                end
                
                state.dirty = true
                state.last_edit_time = r.time_precise()
                SaveNotebook()
                state.editor = nil
                local new_editor = EnsureEditorState()
                new_editor.request_focus = true
            end
        end
        
        r.ImGui_PopStyleColor(ctx, 4)
        
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
            r.ImGui_OpenPopup(ctx, "tab_menu_" .. i)
        end
        
        if r.ImGui_BeginPopup(ctx, "tab_menu_" .. i) then
            r.ImGui_Text(ctx, "Tab: " .. tab_name)
            r.ImGui_Separator(ctx)
            
            if r.ImGui_MenuItem(ctx, "Rename") then
                state.renaming_tab_index = i
                state.renaming_tab_name = tab_name
            end
            
            if #state.tabs > 1 then
                if r.ImGui_MenuItem(ctx, "Delete") then
                    if state.tabs[state.active_tab_index] and state.active_tab_index ~= i then
                        state.tabs[state.active_tab_index].text = state.text
                        state.tabs[state.active_tab_index].images = state.images
                        state.tabs[state.active_tab_index].strokes = state.strokes
                    end
                    
                    table.remove(state.tabs, i)
                    
                    if state.active_tab_index == i then
                        state.active_tab_index = math.max(1, i - 1)
                        state.text = state.tabs[state.active_tab_index].text or ""
                        state.images = state.tabs[state.active_tab_index].images or {}
                        state.strokes = state.tabs[state.active_tab_index].strokes or {}
                        
                        for _, img in ipairs(state.images) do
                            if img.path then
                                img.texture = r.ImGui_CreateImage(img.path)
                                if img.texture then
                                    local w, h = r.ImGui_Image_GetSize(img.texture)
                                    img.width = w
                                    img.height = h
                                end
                            end
                        end
                    elseif state.active_tab_index > i then
                        state.active_tab_index = state.active_tab_index - 1
                    end
                    
                    state.dirty = true
                    state.last_edit_time = r.time_precise()
                    SaveNotebook()
                    
                    state.editor = nil
                    local new_editor = EnsureEditorState()
                    new_editor.request_focus = true
                end
            end
            
            r.ImGui_EndPopup(ctx)
        end
    end
    
    if state.renaming_tab_index and state.tabs[state.renaming_tab_index] then
        r.ImGui_OpenPopup(ctx, "Rename Tab")
        if r.ImGui_BeginPopupModal(ctx, "Rename Tab", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
            r.ImGui_Text(ctx, "Enter new name:")
            local changed, new_name = r.ImGui_InputText(ctx, "##rename_input", state.renaming_tab_name)
            if changed then
                state.renaming_tab_name = new_name
            end
            
            r.ImGui_Separator(ctx)
            
            if r.ImGui_Button(ctx, "OK", 120, 0) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
                if state.renaming_tab_name ~= "" then
                    state.tabs[state.renaming_tab_index].name = state.renaming_tab_name
                    state.dirty = true
                    state.last_edit_time = r.time_precise()
                    SaveNotebook()
                end
                state.renaming_tab_index = nil
                state.renaming_tab_name = ""
                r.ImGui_CloseCurrentPopup(ctx)
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Cancel", 120, 0) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
                state.renaming_tab_index = nil
                state.renaming_tab_name = ""
                r.ImGui_CloseCurrentPopup(ctx)
            end
            
            r.ImGui_EndPopup(ctx)
        end
    end
    
    r.ImGui_SameLine(ctx, 0, 2)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), tab_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), tab_hover_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), tab_active_bg)
    if r.ImGui_Button(ctx, "+##add_tab", add_button_width, tab_height - 4) then
        if state.tabs[state.active_tab_index] then
            state.tabs[state.active_tab_index].text = state.text
            state.tabs[state.active_tab_index].images = state.images
            state.tabs[state.active_tab_index].strokes = state.strokes
        end
        table.insert(state.tabs, {name = "Tab " .. (#state.tabs + 1), text = "", images = {}, strokes = {}})
        state.active_tab_index = #state.tabs
        state.text = ""
        state.images = state.tabs[state.active_tab_index].images  
        state.strokes = state.tabs[state.active_tab_index].strokes  
        state.dirty = true
        state.last_edit_time = r.time_precise()
        SaveNotebook()
        state.editor = nil
        local new_editor = EnsureEditorState()
        new_editor.request_focus = true
    end
    r.ImGui_PopStyleColor(ctx, 3)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Add new tab")
    end
    
    r.ImGui_EndChild(ctx)
    
    return tab_height - 15
end

local function DrawEditor()
    local tab_bar_height = DrawTabBar()
    
    local editor = EnsureEditorState()
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local editor_w = math.max(220, avail_w)
    local status_height = state.show_status and StatusBarConstants.height or 0
    local margin = (tab_bar_height > 0) and 0 or (EditorConstants.scroll_margin or 0)
    local extra_margin = (tab_bar_height > 0) and 0 or 8
    local editor_h = math.max(200, avail_h - status_height - margin - extra_margin - tab_bar_height)

    local using_custom_font = font ~= nil
    if using_custom_font then
        r.ImGui_PushFont(ctx, font, state.font_size)
    end

    local line_height = r.ImGui_GetTextLineHeight(ctx)
    local wrap_width = editor_w - (EditorConstants.padding_x * 2)
    if wrap_width < 32 then wrap_width = 32 end
    local max_text_height = math.max(0, editor_h - EditorConstants.padding_y)

    local layout = BuildEditorLayout(ctx, state.text, wrap_width, line_height)
    local text_changed = HandleEditorInput(ctx, editor, layout, wrap_width, line_height, max_text_height, state.can_edit)
    if text_changed then
        layout = BuildEditorLayout(ctx, state.text, wrap_width, line_height)
    end

    local child_flags = 0
    if r.ImGui_WindowFlags_NoScrollbar then
        child_flags = child_flags | r.ImGui_WindowFlags_NoScrollbar()
    end
    if r.ImGui_WindowFlags_NoScrollWithMouse then
        child_flags = child_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
    end
    local border = 0
    
    if r.ImGui_BeginChild(ctx, "##notebook_editor", editor_w, editor_h, border, child_flags) then
        local area_x, area_y = r.ImGui_GetCursorScreenPos(ctx)
    local can_edit = state.can_edit and true or false
    local content_height = math.max(0, editor_h - margin)
    
    for i, img in ipairs(state.images) do
        if img.texture and img.width > 0 and img.height > 0 then
            local max_width = 150
            local base_img_w = img.width
            local base_img_h = img.height
            if base_img_w > max_width then
                local scale = max_width / base_img_w
                base_img_w = max_width
                base_img_h = base_img_h * scale
            end
            local user_scale = (img.scale or 100) / 100.0
            local img_w = base_img_w * user_scale
            local img_h = base_img_h * user_scale

            local cursor_x, cursor_y = r.ImGui_GetCursorPos(ctx)

            r.ImGui_SetCursorPos(ctx, img.pos_x, img.pos_y)

            local button_id = "##image_drag_" .. img.id
            r.ImGui_InvisibleButton(ctx, button_id, img_w, img_h)

            if r.ImGui_IsItemHovered(ctx) and r.ImGui_MouseCursor_Hand then
                r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
            end

            if r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, 0) then
                if not img.dragging then
                    img.dragging = true
                    state.selected_image_id = img.id
                end

                local delta_x, delta_y = r.ImGui_GetMouseDragDelta(ctx, 0)
                if delta_x ~= 0 or delta_y ~= 0 then
                    local prev_x = img.pos_x
                    local prev_y = img.pos_y
                    local new_x = prev_x + delta_x
                    local new_y = prev_y + delta_y

                    local max_x = math.max(0, editor_w - img_w)
                    local max_y = math.max(0, editor_h - img_h)
                    local clamped_x = math.max(0, math.min(max_x, new_x))
                    local clamped_y = math.max(0, math.min(max_y, new_y))
                    if clamped_x ~= prev_x or clamped_y ~= prev_y then
                        img.pos_x = clamped_x
                        img.pos_y = clamped_y
                        state.dirty = true
                        state.last_edit_time = r.time_precise()
                    else
                        img.pos_x = clamped_x
                        img.pos_y = clamped_y
                    end

                    r.ImGui_ResetMouseDragDelta(ctx, 0)
                end
            elseif img.dragging and not r.ImGui_IsMouseDown(ctx, 0) then
                img.dragging = false
                if state.dirty then
                    SaveNotebook()
                end
            end

            if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 0) and not img.dragging then
                state.selected_image_id = img.id
            end

            if r.ImGui_IsItemHovered(ctx) and not img.dragging then
                local tooltip = string.format("Image %d\nDrag to move\nRight-click for options", img.id)
                if state.selected_image_id == img.id then
                    tooltip = tooltip .. "\n(Selected)"
                end
                r.ImGui_SetTooltip(ctx, tooltip)
            end

            if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
                state.selected_image_id = img.id
                r.ImGui_OpenPopup(ctx, "image_context_" .. img.id)
            end

            local popup_id = "image_context_" .. img.id
            if r.ImGui_BeginPopup(ctx, popup_id) then
                r.ImGui_Text(ctx, string.format("Image %d", img.id))
                r.ImGui_Separator(ctx)
                r.ImGui_Text(ctx, "Image Size:")
                r.ImGui_PushItemWidth(ctx, 200)
                local scale_changed, new_scale = r.ImGui_SliderInt(ctx, "##image_scale_" .. img.id, img.scale or 100, 10, 200, "%d%%")
                r.ImGui_PopItemWidth(ctx)
                if scale_changed and new_scale ~= img.scale then
                    img.scale = new_scale
                    state.dirty = true
                    state.last_edit_time = r.time_precise()
                    SaveNotebook()
                end
                
                r.ImGui_Separator(ctx)
                
                if r.ImGui_MenuItem(ctx, "Remove This Image") then
                    RemoveImage(img.id)
                    state.dirty = true
                    state.last_edit_time = r.time_precise()
                    SaveNotebook()
                end
                
                if #state.images > 1 then
                    r.ImGui_Separator(ctx)
                    if r.ImGui_MenuItem(ctx, "Remove All Images") then
                        ClearAllImages()
                        state.dirty = true
                        state.last_edit_time = r.time_precise()
                        SaveNotebook()
                    end
                end
                
                r.ImGui_EndPopup(ctx)
            end

            r.ImGui_SetCursorPos(ctx, img.pos_x, img.pos_y)
            r.ImGui_InvisibleButton(ctx, "##image_" .. img.id, img_w, img_h)
            
            local texture_valid = false
            if img.texture then
                texture_valid = r.ValidatePtr(img.texture, "ImGui_Image*")
            end
            
            if not texture_valid and img.path then
                img.texture = r.ImGui_CreateImage(img.path)
                if img.texture then
                    local w, h = r.ImGui_Image_GetSize(img.texture)
                    img.width = w
                    img.height = h
                    texture_valid = true
                end
            end
            
            if not texture_valid then
                goto continue_image_loop
            end
            
            local overlay_list = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx)
            local target_list = overlay_list or (r.ImGui_GetWindowDrawList and r.ImGui_GetWindowDrawList(ctx))
            if target_list and r.ImGui_DrawList_AddImage then
                local scroll_x = r.ImGui_GetScrollX(ctx)
                local scroll_y = r.ImGui_GetScrollY(ctx)
                local min_x = area_x + img.pos_x - scroll_x
                local min_y = area_y + img.pos_y - scroll_y
                local max_x = min_x + img_w
                local max_y = min_y + img_h
                
                r.ImGui_DrawList_AddImage(target_list, img.texture, min_x, min_y, max_x, max_y, 0, 0, 1, 1, PackColorToU32(1.0, 1.0, 1.0, 1.0))
                
                if state.selected_image_id == img.id then
                    local border_color = PackColorToU32(0.2, 0.6, 1.0, 1.0) 
                    r.ImGui_DrawList_AddRect(target_list, min_x - 2, min_y - 2, max_x + 2, max_y + 2, border_color, 0, 0, 2.0)
                end
            else
                r.ImGui_SetCursorPos(ctx, img.pos_x, img.pos_y)
                r.ImGui_Image(ctx, img.texture, img_w, img_h)
            end
            
            r.ImGui_SetCursorPos(ctx, cursor_x, cursor_y)
            
            ::continue_image_loop::
        end
    end

        if editor.request_focus then
            if has_clear_active then
                r.ImGui_ClearActiveID(ctx)
            end
            r.ImGui_SetKeyboardFocusHere(ctx)
            editor.active = true
        end

        r.ImGui_InvisibleButton(ctx, "##editor_capture", editor_w, content_height)
        local hovered = r.ImGui_IsItemHovered(ctx)
        local active = r.ImGui_IsItemActive(ctx)
        local io = r.ImGui_GetIO and r.ImGui_GetIO(ctx) or nil
        local shift_down = IsShiftDown(io)

        if can_edit and r.ImGui_IsItemClicked(ctx) then
            state.selected_image_id = nil
            
            editor.active = true
            editor.request_focus = true
            editor.blink_visible = true
            editor.blink_time = r.time_precise()
            local previous_caret = editor.caret or 0
            local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
            local scroll_y = r.ImGui_GetScrollY(ctx)
            local local_x = mouse_x - (area_x + EditorConstants.padding_x)
            local local_y = mouse_y - (area_y + EditorConstants.padding_y) + scroll_y
            local caret_pos, relative_x = CaretFromMouse(layout, local_x, local_y, wrap_width, state.text_align)
            local new_caret = ClampCaret(state.text, caret_pos)
            if shift_down then
                editor.selection_anchor = ClampToText(editor.selection_anchor or previous_caret)
                editor.selection_start = editor.selection_anchor
                editor.selection_end = new_caret
                editor.caret = new_caret
                editor.mouse_selecting = false
            else
                editor.caret = new_caret
                editor.selection_anchor = new_caret
                editor.selection_start = new_caret
                editor.selection_end = new_caret
                editor.mouse_selecting = true
            end
            editor.preferred_x = relative_x
            editor.scroll_to_caret = true
        end

        if editor.request_focus then
            editor.request_focus = false
        end

        if can_edit and editor.mouse_selecting then
            if r.ImGui_IsMouseDown(ctx, 0) then
                local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                local scroll_y = r.ImGui_GetScrollY(ctx)
                local local_x = mouse_x - (area_x + EditorConstants.padding_x)
                local local_y = mouse_y - (area_y + EditorConstants.padding_y) + scroll_y
                local caret_pos, relative_x = CaretFromMouse(layout, local_x, local_y, wrap_width, state.text_align)
                local new_caret = ClampCaret(state.text, caret_pos)
                editor.caret = new_caret
                editor.selection_start = editor.selection_anchor or new_caret
                editor.selection_end = new_caret
                editor.preferred_x = relative_x
                editor.scroll_to_caret = true
                editor.blink_visible = true
                editor.blink_time = r.time_precise()
            else
                editor.mouse_selecting = false
            end
        else
            editor.mouse_selecting = false
        end

        NormalizeSelection(editor)

        if not can_edit then
            editor.active = false
        elseif not r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_ChildWindows()) then
            editor.active = active and true or false
        else
            editor.active = true
        end

        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local scroll_y = r.ImGui_GetScrollY(ctx)
        
        local base_bg = state.track_bg_color or 0x202020FF
        local hover_bg = state.track_bg_color_hover or 0x303030FF
        local border_color = state.track_bg_color_border or 0x3A3A3AFF
        
        -- Use custom color for Project/Global mode with brightness adjustment
        if state.mode == "project" and state.project_bg_color then
            local brightness = state.project_bg_brightness or 1.0
            local r = math.min(1.0, state.project_bg_color.r * brightness)
            local g = math.min(1.0, state.project_bg_color.g * brightness)
            local b = math.min(1.0, state.project_bg_color.b * brightness)
            base_bg = PackColorToU32(r, g, b, state.project_bg_color.a)
        elseif state.mode == "global" and state.global_bg_color then
            local brightness = state.global_bg_brightness or 1.0
            local r = math.min(1.0, state.global_bg_color.r * brightness)
            local g = math.min(1.0, state.global_bg_color.g * brightness)
            local b = math.min(1.0, state.global_bg_color.b * brightness)
            base_bg = PackColorToU32(r, g, b, state.global_bg_color.a)
        end
        
        local bg_color = base_bg
        if not can_edit then
            bg_color = ApplyAlpha(bg_color, 0.6) or bg_color
            border_color = ApplyAlpha(border_color, 0.5) or border_color
        end
        local inset = 0.5
        local rounding = 12.0
        local left = area_x + inset
        local top = area_y + inset
        local right = area_x + editor_w - inset
        local bottom = area_y + editor_h - inset
        if right - left < 2 then right = left + 2 end
        if bottom - top < 2 then bottom = top + 2 end
        local max_rounding = math.min((right - left) * 0.5, (bottom - top) * 0.5)
        if rounding > max_rounding then rounding = max_rounding end
        r.ImGui_DrawList_AddRectFilled(draw_list, left, top, right, bottom, bg_color, rounding)
        r.ImGui_DrawList_AddRect(draw_list, left, top, right, bottom, border_color, rounding, 0, 1.0)

        r.ImGui_DrawList_PushClipRect(draw_list, area_x, area_y, area_x + editor_w, area_y + editor_h, true)

    DrawSelectionHighlights(draw_list, editor, layout, area_x, area_y, scroll_y, line_height, wrap_width, state.text_align)

        local text_color = GetEditorTextColor()
        
        for idx, line in ipairs(layout.lines) do
            local line_offset = CalculateLineOffset(line, wrap_width, state.text_align)
            local base_x = area_x + EditorConstants.padding_x + line_offset
            local line_y = area_y + EditorConstants.padding_y - scroll_y + (idx - 1) * line_height
            
            local fragments = line.fragments
            if fragments and #fragments > 0 then
                for _, fragment in ipairs(fragments) do
                    local fragment_text = fragment.text
                    if fragment_text and fragment_text ~= "" then
                        local fragment_x = base_x + (fragment.x or 0)
                        DrawTextFragment(draw_list, fragment_x, line_y, text_color, fragment_text, fragment.bold)
                    end
                end
            elseif line.text and line.text ~= "" then
                r.ImGui_DrawList_AddText(draw_list, base_x, line_y, text_color, line.text)
            end
        end

        local caret_line_idx, caret_x, caret_y = LocateCaret(layout, editor.caret)
        if caret_line_idx then
            local now = r.time_precise()
            if editor.active then
                if now - (editor.blink_time or now) >= EditorConstants.blink_interval then
                    editor.blink_visible = not editor.blink_visible
                    editor.blink_time = now
                end
            else
                editor.blink_visible = false
            end

            if editor.scroll_to_caret then
                local caret_top = caret_y + EditorConstants.padding_y
                local caret_bottom = caret_top + line_height
                local visible_top = scroll_y
                local visible_bottom = scroll_y + editor_h
                if caret_top < visible_top then
                    r.ImGui_SetScrollY(ctx, caret_top)
                    scroll_y = r.ImGui_GetScrollY(ctx)
                elseif caret_bottom > visible_bottom then
                    local target_scroll = caret_bottom - editor_h
                    if target_scroll < 0 then target_scroll = 0 end
                    r.ImGui_SetScrollY(ctx, target_scroll)
                    scroll_y = r.ImGui_GetScrollY(ctx)
                end
                editor.scroll_to_caret = false
            end

            if editor.active and editor.blink_visible then
                local caret_line = layout.lines[caret_line_idx]
                local caret_offset = CalculateLineOffset(caret_line, wrap_width, state.text_align)
                local caret_screen_x = area_x + EditorConstants.padding_x + caret_offset + caret_x
                local caret_screen_y = area_y + EditorConstants.padding_y - scroll_y + caret_y
                local caret_color = text_color
                r.ImGui_DrawList_AddLine(draw_list, caret_screen_x, caret_screen_y, caret_screen_x, caret_screen_y + line_height, caret_color, EditorConstants.caret_width)
            end
        end

        if not can_edit then
            local overlay = "Select a track to edit"
            local overlay_w, overlay_h = r.ImGui_CalcTextSize(ctx, overlay)
            local overlay_x = area_x + math.max(0, (editor_w - overlay_w) * 0.5)
            local overlay_y = area_y + math.max(0, (editor_h - overlay_h) * 0.5)
            local overlay_color = ApplyAlpha(text_color, 0.45) or text_color
            r.ImGui_DrawList_AddText(draw_list, overlay_x, overlay_y, overlay_color, overlay)
        end

        r.ImGui_DrawList_PopClipRect(draw_list)
        
        for _, stroke in ipairs(state.strokes) do
            if stroke.points and #stroke.points > 1 then
                local color = PackColorToU32(stroke.color.r or 1, stroke.color.g or 0, stroke.color.b or 0, stroke.color.a or 1)
                for i = 1, #stroke.points - 1 do
                    local p1 = stroke.points[i]
                    local p2 = stroke.points[i + 1]
                    local x1 = area_x + p1.x
                    local y1 = area_y + p1.y - scroll_y
                    local x2 = area_x + p2.x
                    local y2 = area_y + p2.y - scroll_y
                    r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, color, stroke.thickness or 2.0)
                end
            end
        end
        
        if state.drawing_enabled and can_edit then
            local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
            local is_mouse_down = r.ImGui_IsMouseDown(ctx, 0)
            
            if hovered and is_mouse_down and not state.is_drawing then
                state.is_drawing = true
                state.current_stroke = {}
                table.insert(state.current_stroke, {x = mouse_x - area_x, y = mouse_y - area_y + scroll_y})
            end
            
            if state.is_drawing and is_mouse_down then
                local last_point = state.current_stroke[#state.current_stroke]
                local new_x = mouse_x - area_x
                local new_y = mouse_y - area_y + scroll_y
                if not last_point or math.abs(new_x - last_point.x) > 1 or math.abs(new_y - last_point.y) > 1 then
                    table.insert(state.current_stroke, {x = new_x, y = new_y})
                end
            end
            
            if state.is_drawing and not is_mouse_down then
                if #state.current_stroke > 1 then
                    table.insert(state.strokes, {
                        points = state.current_stroke,
                        color = {r = state.drawing_color.r, g = state.drawing_color.g, b = state.drawing_color.b, a = state.drawing_color.a},
                        thickness = state.drawing_thickness
                    })
                    state.dirty = true
                    state.last_edit_time = r.time_precise()
                end
                state.is_drawing = false
                state.current_stroke = {}
            end
            
            if state.is_drawing and #state.current_stroke > 1 then
                local color = PackColorToU32(state.drawing_color.r, state.drawing_color.g, state.drawing_color.b, state.drawing_color.a)
                for i = 1, #state.current_stroke - 1 do
                    local p1 = state.current_stroke[i]
                    local p2 = state.current_stroke[i + 1]
                    local x1 = area_x + p1.x
                    local y1 = area_y + p1.y - scroll_y
                    local x2 = area_x + p2.x
                    local y2 = area_y + p2.y - scroll_y
                    r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, color, state.drawing_thickness)
                end
            end
        end
        
        if state.eraser_mode and can_edit then
            local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
            local is_mouse_down = r.ImGui_IsMouseDown(ctx, 0)
            
            local eraser_radius = 10
            r.ImGui_DrawList_AddCircle(draw_list, mouse_x, mouse_y, eraser_radius, PackColorToU32(1, 0.3, 0.3, 0.8), 0, 2.0)
            r.ImGui_DrawList_AddCircleFilled(draw_list, mouse_x, mouse_y, eraser_radius * 0.5, PackColorToU32(1, 0.3, 0.3, 0.3), 0)
            
            if hovered and is_mouse_down then
                local strokes_modified = false
                local new_strokes = {}
                
                for stroke_idx, stroke in ipairs(state.strokes) do
                    if stroke.points and #stroke.points > 1 then
                        local new_points = {}
                        local current_segment = {}
                        
                        for i, pt in ipairs(stroke.points) do
                            local px = area_x + pt.x
                            local py = area_y + pt.y - scroll_y
                            local dx = mouse_x - px
                            local dy = mouse_y - py
                            local dist = math.sqrt(dx * dx + dy * dy)
                            
                            if dist > eraser_radius then
                                table.insert(current_segment, pt)
                            else
                                if #current_segment > 1 then
                                    table.insert(new_strokes, {
                                        points = current_segment,
                                        color = stroke.color,
                                        thickness = stroke.thickness
                                    })
                                end
                                current_segment = {}
                                strokes_modified = true
                            end
                        end
                        
                        if #current_segment > 1 then
                            table.insert(new_strokes, {
                                points = current_segment,
                                color = stroke.color,
                                thickness = stroke.thickness
                            })
                        end
                    else
                        table.insert(new_strokes, stroke)
                    end
                end
                
                if strokes_modified then
                    state.strokes = new_strokes
                    state.dirty = true
                    state.last_edit_time = r.time_precise()
                end
            end
        end

    r.ImGui_SetCursorScreenPos(ctx, area_x, area_y + content_height)
    r.ImGui_Dummy(ctx, 0, 0)
    end
    r.ImGui_EndChild(ctx)

    if using_custom_font then
        r.ImGui_PopFont(ctx)
    end

    AutoSaveText()

    DrawStatusBar(status_height)
end

local function Frame()
    local target_width = state.window_width or 600
    local target_height = state.window_height or 400
    
    local size_cond = 0
    if state.window_size_needs_update then
        size_cond = r.ImGui_Cond_Always and r.ImGui_Cond_Always() or 0
        state.window_size_needs_update = false
    else
        size_cond = r.ImGui_Cond_FirstUseEver and r.ImGui_Cond_FirstUseEver() or 0
    end
    r.ImGui_SetNextWindowSize(ctx, target_width, target_height, size_cond)
    local min_width = 380 
    local min_height = 350
    local max_width = 3000
    local max_height = 3000
    r.ImGui_SetNextWindowSizeConstraints(ctx, min_width, min_height, max_width, max_height)

    UpdateActiveContext(false)

    local window_flags = r.ImGui_WindowFlags_MenuBar()
    if r.ImGui_WindowFlags_NoTitleBar then
        window_flags = window_flags | r.ImGui_WindowFlags_NoTitleBar()
    end

    local pushed_rounding = false
    if r.ImGui_StyleVar_WindowRounding then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 12)
        pushed_rounding = true
    end

    local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
    if visible then
        -- Capture keyboard input when window has focus to prevent REAPER shortcuts
        if type(r.ImGui_SetNextFrameWantCaptureKeyboard) == "function" and 
           type(r.ImGui_IsWindowFocused) == "function" then
            if r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_ChildWindows()) then
                r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
            end
        end
        
        if state.window_size_needs_update and r.ImGui_SetWindowSize then
            r.ImGui_SetWindowSize(ctx, state.window_width or 600, state.window_height or 400)
            state.window_size_needs_update = false
        end
        
        local current_width, current_height = r.ImGui_GetWindowSize(ctx)
        if current_width and current_height then
            if not state.window_size_needs_update and 
               (math.abs(current_width - (state.window_width or 600)) > 1 or 
                math.abs(current_height - (state.window_height or 400)) > 1) then
                state.window_width = math.floor(current_width + 0.5)
                state.window_height = math.floor(current_height + 0.5)
                state.dirty = true
                state.last_edit_time = r.time_precise()
            end
        end
        
        if DrawMenuBar() then
            HandleShortcuts()
            DrawEditor()
        end
    end
    r.ImGui_End(ctx)

    if pushed_rounding and r.ImGui_PopStyleVar then
        r.ImGui_PopStyleVar(ctx)
    end

    if should_close then
        open = false
    end

    if open then
        r.defer(Frame)
    else
        SaveNotebook()
       
    end
end

ctx = r.ImGui_CreateContext(SCRIPT_NAME)
BuildFont()
LoadNotebook()
local initial_editor = EnsureEditorState()
initial_editor.caret = #state.text
initial_editor.request_focus = true
initial_editor.active = true
initial_editor.scroll_to_caret = true
r.defer(Frame)
