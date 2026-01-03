local r = reaper

local ai_samples = {
    database = nil,
    db_path = nil,
    db_loaded = false,
    active_category = "all",
    active_subcategory = nil,
    drums_only = false,
    show_loops_only = false,
    show_oneshots_only = false,
    active_character_tags = {},
    filtered_samples = {},
    category_counts = {},
    total_count = 0,
    drum_count = 0,
    search_term = "",
    selected_index = 0,
    scroll_to_selected = false,
    sort_by = "name",
    sort_ascending = true
}

local CHARACTER_TAGS = {"loud", "soft", "punchy", "snappy", "bright", "dark", "warm", "tonal", "sustained", "compressed", "dynamic"}

local CHARACTER_COLORS = {
    loud = 0xAAAAAAFF,
    soft = 0xAAAAAAFF,
    punchy = 0xAAAAAAFF,
    snappy = 0xAAAAAAFF,
    bright = 0xAAAAAAFF,
    dark = 0xAAAAAAFF,
    warm = 0xAAAAAAFF,
    tonal = 0xAAAAAAFF,
    sustained = 0xAAAAAAFF,
    compressed = 0xAAAAAAFF,
    dynamic = 0xAAAAAAFF
}

local DRUM_CATEGORIES = {
    kick = true,
    snare = true,
    hihat = true,
    tom = true,
    cymbal = true,
    percussion = true,
    drumloop = true
}

local CATEGORY_COLORS = {
    kick =       0xCC2222FF,
    tom =        0xE64A19FF,
    snare =      0xF57C00FF,
    percussion = 0xFFA726FF,
    hihat =      0xFFCA28FF,
    cymbal =     0xFFEE58FF,
    drumloop =   0x8D6E63FF,
    
    bass =       0x4A148CFF,
    synth =      0x7B1FA2FF,
    pad =        0xBA68C8FF,
    
    keys =       0x00695CFF,
    guitar =     0x00897BFF,
    strings =    0x4DB6ACFF,
    
    vocal =      0x1976D2FF,
    
    fx =         0x37474FFF,
    loop =       0x546E7AFF,
    other =      0x78909CFF
}

local CATEGORY_ICONS = {
    kick = "K",
    snare = "S",
    hihat = "H",
    tom = "T",
    cymbal = "C",
    percussion = "P",
    drumloop = "D",
    bass = "B",
    synth = "~",
    pad = "=",
    keys = "#",
    guitar = "G",
    fx = "*",
    vocal = "V",
    strings = "S",
    loop = "L",
    other = "?"
}

local function init_ai_samples(script_path)
    ai_samples.db_path = script_path .. "sample_database.json"
end

local function get_luminance(color)
    local a = (color >> 24) & 0xFF
    local b = (color >> 16) & 0xFF
    local g = (color >> 8) & 0xFF
    local r_val = color & 0xFF
    return (0.299 * r_val + 0.587 * g + 0.114 * b) / 255
end

local function get_contrast_text_color(bg_color)
    local lum = get_luminance(bg_color)
    if lum > 0.5 then
        return 0x000000FF
    else
        return 0xFFFFFFFF
    end
end

local function load_ai_database(json_module)
    if ai_samples.db_loaded and ai_samples.database then
        return true
    end
    
    if not ai_samples.db_path then
        r.ShowConsoleMsg("AI: db_path is nil\n")
        return false
    end
    
    local file = io.open(ai_samples.db_path, "r")
    if not file then
        return false
    end
    
    local content = file:read("*all")
    file:close()
    
    if not content or content == "" then
        return false
    end
    
    if not json_module or not json_module.decode then
        return false
    end
    
    local success, data = pcall(json_module.decode, content)
    if success and data then
        ai_samples.database = data
        ai_samples.total_count = data.sample_count or 0
        ai_samples.drum_count = data.drum_count or 0
        ai_samples.db_loaded = true
        ai_samples.filtered_samples = data.samples or {}
        
        ai_samples.category_counts = {}
        ai_samples.character_tag_counts = {}
        for _, sample in ipairs(data.samples or {}) do
            local cat = sample.category
            if cat then
                ai_samples.category_counts[cat] = (ai_samples.category_counts[cat] or 0) + 1
            end
            if sample.secondary_categories then
                for _, sec_cat in ipairs(sample.secondary_categories) do
                    ai_samples.category_counts[sec_cat] = (ai_samples.category_counts[sec_cat] or 0) + 1
                end
            end
            if sample.tags then
                for _, tag in ipairs(sample.tags) do
                    ai_samples.character_tag_counts[tag] = (ai_samples.character_tag_counts[tag] or 0) + 1
                end
            end
        end
        
        sort_filtered_samples()
        return true
    end
    
    return false
end

local function reload_ai_database(json_module)
    ai_samples.db_loaded = false
    ai_samples.database = nil
    return load_ai_database(json_module)
end

local function matches_search(sample, search_lower)
    if search_lower == "" then
        return true
    end
    
    if sample.name:lower():find(search_lower, 1, true) then
        return true
    end
    
    if sample.folder and sample.folder:lower():find(search_lower, 1, true) then
        return true
    end
    
    if sample.tags then
        for _, tag in ipairs(sample.tags) do
            if tag:lower():find(search_lower, 1, true) then
                return true
            end
        end
    end
    
    if sample.pitch_note and sample.pitch_note:lower():find(search_lower, 1, true) then
        return true
    end
    
    return false
end

function filter_ai_samples(search_term)
    if not ai_samples.database or not ai_samples.database.samples then
        ai_samples.filtered_samples = {}
        return {}
    end
    
    local results = {}
    local search_lower = search_term and search_term:lower() or ""
    ai_samples.search_term = search_term or ""
    
    for _, sample in ipairs(ai_samples.database.samples) do
        local matches = true
        
        if ai_samples.drums_only then
            if not sample.is_drum then
                matches = false
            end
        end
        
        if matches and ai_samples.active_category ~= "all" then
            local cat_matches = false
            if sample.category == ai_samples.active_category then
                cat_matches = true
            elseif sample.secondary_categories then
                for _, sec_cat in ipairs(sample.secondary_categories) do
                    if sec_cat == ai_samples.active_category then
                        cat_matches = true
                        break
                    end
                end
            end
            if not cat_matches then
                matches = false
            end
        end
        
        if matches and ai_samples.active_subcategory then
            if sample.subcategory ~= ai_samples.active_subcategory then
                matches = false
            end
        end
        
        if matches and ai_samples.show_loops_only then
            if not sample.is_loop then
                matches = false
            end
        end
        
        if matches and ai_samples.show_oneshots_only then
            if sample.is_loop then
                matches = false
            end
        end
        
        if matches and next(ai_samples.active_character_tags) then
            for tag, _ in pairs(ai_samples.active_character_tags) do
                local has_tag = false
                if sample.tags then
                    for _, sample_tag in ipairs(sample.tags) do
                        if sample_tag == tag then
                            has_tag = true
                            break
                        end
                    end
                end
                if not has_tag then
                    matches = false
                    break
                end
            end
        end
        
        if matches and search_lower ~= "" then
            if not matches_search(sample, search_lower) then
                matches = false
            end
        end
        
        if matches then
            table.insert(results, sample)
        end
    end
    
    ai_samples.filtered_samples = results
    sort_filtered_samples()
    return results
end

local function get_note_value(note_str)
    if not note_str or note_str == "" then return -1 end
    local note_map = {C=0, D=2, E=4, F=5, G=7, A=9, B=11}
    local note_name = note_str:sub(1,1):upper()
    local base = note_map[note_name] or 0
    local sharp = note_str:find("#") and 1 or 0
    local flat = note_str:find("b") and -1 or 0
    local octave = tonumber(note_str:match("%-?%d+$")) or 4
    return (octave + 1) * 12 + base + sharp + flat
end

function sort_filtered_samples()
    local sort_by = ai_samples.sort_by
    local ascending = ai_samples.sort_ascending
    
    table.sort(ai_samples.filtered_samples, function(a, b)
        local val_a, val_b
        
        if sort_by == "name" then
            val_a = (a.name or ""):lower()
            val_b = (b.name or ""):lower()
        elseif sort_by == "category" then
            val_a = a.category or "zzz"
            val_b = b.category or "zzz"
        elseif sort_by == "key" then
            val_a = get_note_value(a.pitch_note)
            val_b = get_note_value(b.pitch_note)
        elseif sort_by == "bpm" then
            val_a = a.bpm or 0
            val_b = b.bpm or 0
        elseif sort_by == "length" then
            val_a = a.duration or 0
            val_b = b.duration or 0
        else
            val_a = (a.name or ""):lower()
            val_b = (b.name or ""):lower()
        end
        
        if ascending then
            return val_a < val_b
        else
            return val_a > val_b
        end
    end)
end

local function set_sort(sort_by, ascending)
    if ascending == nil then
        if ai_samples.sort_by == sort_by then
            ai_samples.sort_ascending = not ai_samples.sort_ascending
        else
            ai_samples.sort_ascending = true
        end
    else
        ai_samples.sort_ascending = ascending
    end
    ai_samples.sort_by = sort_by
    sort_filtered_samples()
end

local function set_category_filter(category)
    ai_samples.active_category = category
    ai_samples.active_subcategory = nil
    filter_ai_samples(ai_samples.search_term)
end

local function set_drums_only(enabled)
    ai_samples.drums_only = enabled
    filter_ai_samples(ai_samples.search_term)
end

local function toggle_character_tag(tag)
    if ai_samples.active_character_tags[tag] then
        ai_samples.active_character_tags[tag] = nil
    else
        ai_samples.active_character_tags[tag] = true
    end
    filter_ai_samples(ai_samples.search_term)
end

local function clear_character_tags()
    ai_samples.active_character_tags = {}
    filter_ai_samples(ai_samples.search_term)
end

local function draw_character_tag_buttons(ctx, accent_hue, hsv_to_color)
    local accent_color = hsv_to_color(accent_hue, 1.0, 1.0)
    local spacing = 4
    local any_active = next(ai_samples.active_character_tags) ~= nil
    local first_button = true
    
    for _, tag in ipairs(CHARACTER_TAGS) do
        local count = ai_samples.character_tag_counts and ai_samples.character_tag_counts[tag] or 0
        local is_active = ai_samples.active_character_tags[tag]
        
        if count > 0 or is_active then
            if not first_button then
                r.ImGui_SameLine(ctx, 0, spacing)
            end
            first_button = false
            
            local tag_color = CHARACTER_COLORS[tag] or 0x888888FF
            
            if is_active then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), accent_color)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), accent_color)
            else
                local dimmed = ((tag_color >> 8) & 0xFFFFFF00) | 0x80
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), dimmed)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), tag_color)
            end
            
            local label = tag:upper()
            if r.ImGui_Button(ctx, label .. "##char_" .. tag, 0, 20) then
                toggle_character_tag(tag)
            end
            
            r.ImGui_PopStyleColor(ctx, 2)
        end
    end
    
    if any_active then
        r.ImGui_SameLine(ctx, 0, spacing * 2)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x666666FF)
        if r.ImGui_Button(ctx, "X##clear_chars", 20, 20) then
            clear_character_tags()
        end
        r.ImGui_PopStyleColor(ctx, 1)
    end
end

local function set_loops_filter(loops_only, oneshots_only)
    ai_samples.show_loops_only = loops_only
    ai_samples.show_oneshots_only = oneshots_only
    filter_ai_samples(ai_samples.search_term)
end

local function get_sample_by_index(index)
    if index >= 1 and index <= #ai_samples.filtered_samples then
        return ai_samples.filtered_samples[index]
    end
    return nil
end

local function get_category_color(category)
    return CATEGORY_COLORS[category] or CATEGORY_COLORS.other
end

local function get_category_icon(category)
    return CATEGORY_ICONS[category] or "?"
end

local function is_drum_category(category)
    return DRUM_CATEGORIES[category] or false
end

local function draw_ai_category_buttons(ctx, hsv_to_color, accent_hue)
    local accent_color = hsv_to_color(accent_hue, 1.0, 1.0)
    local inactive_color = r.ImGui_ColorConvertDouble4ToU32(0.3, 0.3, 0.3, 1.0)
    
    local categories = {"all", "kick", "snare", "hihat", "tom", "percussion", "cymbal", "drumloop", "bass", "synth", "pad", "keys", "guitar", "fx", "vocal", "strings", "loop", "other"}
    
    local avail_width = r.ImGui_GetContentRegionAvail(ctx)
    local button_count = #categories
    local spacing = 4
    local button_width = math.floor((avail_width - (button_count - 1) * spacing) / button_count)
    button_width = math.max(button_width, 30)
    
    for i, cat in ipairs(categories) do
        if i > 1 then 
            r.ImGui_SameLine(ctx, 0, spacing) 
        end
        
        local is_active = (ai_samples.active_category == cat)
        local count = ai_samples.category_counts[cat] or 0
        local label = cat:sub(1, 3):upper()
        
        local cat_color = get_category_color(cat)
        
        if is_active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), cat_color)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0xFFFFFFFF)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 2)
        else
            local dimmed = r.ImGui_ColorConvertDouble4ToU32(
                ((cat_color >> 24) & 0xFF) / 255 * 0.5,
                ((cat_color >> 16) & 0xFF) / 255 * 0.5,
                ((cat_color >> 8) & 0xFF) / 255 * 0.5,
                0.7
            )
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), dimmed)
        end
        
        if r.ImGui_Button(ctx, label .. "##cat_" .. cat, button_width, 20) then
            set_category_filter(cat)
        end
        
        if is_active then
            r.ImGui_PopStyleVar(ctx, 1)
            r.ImGui_PopStyleColor(ctx, 2)
        else
            r.ImGui_PopStyleColor(ctx, 1)
        end
        
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_BeginTooltip(ctx)
            r.ImGui_Text(ctx, cat:upper() .. (count > 0 and " (" .. count .. ")" or ""))
            r.ImGui_EndTooltip(ctx)
        end
    end
end

local function draw_ai_category_buttons_vertical(ctx, hsv_to_color, accent_hue, button_height)
    local accent_color = hsv_to_color(accent_hue, 1.0, 1.0)
    button_height = button_height or 22
    
    local drum_categories = {"kick", "tom", "snare", "percussion", "hihat", "cymbal", "drumloop"}
    local other_categories = {"bass", "synth", "pad", "keys", "guitar", "strings", "vocal", "fx", "loop", "other"}
    
    local avail_width = r.ImGui_GetContentRegionAvail(ctx)
    
    local is_all_active = (ai_samples.active_category == "all")
    local all_count = ai_samples.total_count or 0
    
    local all_bg = is_all_active and accent_color or r.ImGui_ColorConvertDouble4ToU32(0.35, 0.35, 0.35, 1.0)
    local all_text = get_contrast_text_color(all_bg)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), all_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), all_text)
    
    if r.ImGui_Button(ctx, "ALL (" .. all_count .. ")##cat_all", avail_width, button_height) then
        set_category_filter("all")
    end
    r.ImGui_PopStyleColor(ctx, 2)
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_TextDisabled(ctx, "DRUMS")
    
    for _, cat in ipairs(drum_categories) do
        local is_active = (ai_samples.active_category == cat)
        local count = ai_samples.category_counts[cat] or 0
        
        if count > 0 or is_active then
            local label = string.format("%s (%d)", cat:upper(), count)
            
            local cat_color = get_category_color(cat)
            local dimmed = r.ImGui_ColorConvertDouble4ToU32(
                ((cat_color >> 24) & 0xFF) / 255 * 0.4,
                ((cat_color >> 16) & 0xFF) / 255 * 0.4,
                ((cat_color >> 8) & 0xFF) / 255 * 0.4,
                0.9
            )
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), dimmed)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            
            if is_active then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0xFFFFFFFF)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 2)
            end
            
            local btn_x, btn_y = r.ImGui_GetCursorScreenPos(ctx)
            
            if r.ImGui_Button(ctx, label .. "##cat_" .. cat, avail_width, button_height) then
                set_category_filter(cat)
            end
            
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local stripe_width = 4
            r.ImGui_DrawList_AddRectFilled(draw_list, btn_x, btn_y, btn_x + stripe_width, btn_y + button_height, cat_color)
            
            if is_active then
                r.ImGui_PopStyleVar(ctx, 1)
                r.ImGui_PopStyleColor(ctx, 3)
            else
                r.ImGui_PopStyleColor(ctx, 2)
            end
        end
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Separator(ctx)
    r.ImGui_TextDisabled(ctx, "INSTRUMENTS & OTHER")
    
    for _, cat in ipairs(other_categories) do
        local is_active = (ai_samples.active_category == cat)
        local count = ai_samples.category_counts[cat] or 0
        
        if count > 0 or is_active then
            local label = string.format("%s (%d)", cat:upper(), count)
            
            local cat_color = get_category_color(cat)
            local dimmed = r.ImGui_ColorConvertDouble4ToU32(
                ((cat_color >> 24) & 0xFF) / 255 * 0.4,
                ((cat_color >> 16) & 0xFF) / 255 * 0.4,
                ((cat_color >> 8) & 0xFF) / 255 * 0.4,
                0.9
            )
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), dimmed)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            
            if is_active then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0xFFFFFFFF)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 2)
            end
            
            local btn_x, btn_y = r.ImGui_GetCursorScreenPos(ctx)
            
            if r.ImGui_Button(ctx, label .. "##cat_" .. cat, avail_width, button_height) then
                set_category_filter(cat)
            end
            
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local stripe_width = 4
            r.ImGui_DrawList_AddRectFilled(draw_list, btn_x, btn_y, btn_x + stripe_width, btn_y + button_height, cat_color)
            
            if is_active then
                r.ImGui_PopStyleVar(ctx, 1)
                r.ImGui_PopStyleColor(ctx, 3)
            else
                r.ImGui_PopStyleColor(ctx, 2)
            end
        end
    end
end

local function draw_ai_filter_options(ctx)
    local changed = false
    
    local drums_val
    changed, drums_val = r.ImGui_Checkbox(ctx, "Drums Only", ai_samples.drums_only)
    if changed then
        set_drums_only(drums_val)
    end
    
    r.ImGui_SameLine(ctx)
    
    local loop_val
    changed, loop_val = r.ImGui_Checkbox(ctx, "Loops", ai_samples.show_loops_only)
    if changed then
        if loop_val then ai_samples.show_oneshots_only = false end
        set_loops_filter(loop_val, ai_samples.show_oneshots_only)
    end
    
    r.ImGui_SameLine(ctx)
    
    local oneshot_val
    changed, oneshot_val = r.ImGui_Checkbox(ctx, "One-shots", ai_samples.show_oneshots_only)
    if changed then
        if oneshot_val then ai_samples.show_loops_only = false end
        set_loops_filter(ai_samples.show_loops_only, oneshot_val)
    end
    
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, string.format("| %d samples", #ai_samples.filtered_samples))
end

local function draw_ai_sample_list(ctx, play_callback, current_playing_file, auto_play)
    if r.ImGui_BeginChild(ctx, "ai_sample_list", 0, 0, 1) then
        
        local max_visible = 100
        local visible_count = 0
        
        for i, sample in ipairs(ai_samples.filtered_samples) do
            if visible_count >= max_visible then
                r.ImGui_TextDisabled(ctx, string.format("... and %d more samples", #ai_samples.filtered_samples - max_visible))
                break
            end
            visible_count = visible_count + 1
            
            local cat_icon = get_category_icon(sample.category)
            
            local label = string.format("[%s] %s", cat_icon, sample.name)
            
            local extra_info = {}
            if sample.pitch_note then
                table.insert(extra_info, sample.pitch_note)
            end
            if sample.bpm then
                table.insert(extra_info, sample.bpm .. "bpm")
            end
            if sample.duration then
                table.insert(extra_info, string.format("%.2fs", sample.duration))
            end
            
            if #extra_info > 0 then
                label = label .. "  " .. table.concat(extra_info, " | ")
            end
            
            local is_selected = (current_playing_file == sample.path)
            
            local primary_color = get_category_color(sample.category)
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local start_x, start_y = r.ImGui_GetCursorScreenPos(ctx)
            local dot_radius = 4
            local dot_spacing = 10
            local dot_y = start_y + 8
            
            local all_cats = {sample.category}
            if sample.secondary_categories then
                for _, sec_cat in ipairs(sample.secondary_categories) do
                    table.insert(all_cats, sec_cat)
                end
            end
            local dots_width = #all_cats * dot_spacing + 4
            
            r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + dots_width)
            
            if r.ImGui_Selectable(ctx, label .. "##ai_" .. i, is_selected) then
                ai_samples.selected_index = i
                if play_callback and auto_play then
                    play_callback(sample.path)
                end
            end
            
            local dot_x = start_x + 4
            for _, cat in ipairs(all_cats) do
                local cat_color = get_category_color(cat)
                r.ImGui_DrawList_AddCircleFilled(draw_list, dot_x, dot_y, dot_radius, cat_color)
                dot_x = dot_x + dot_spacing
            end
            
            if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceAllowNullID()) then
                r.ImGui_SetDragDropPayload(ctx, "REAPER_MEDIAFOLDER", sample.path)
                r.ImGui_Text(ctx, sample.name)
                r.ImGui_EndDragDropSource(ctx)
            end
            
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_BeginTooltip(ctx)
                r.ImGui_Text(ctx, "Category: " .. sample.category)
                if sample.subcategory then
                    r.ImGui_Text(ctx, "Type: " .. sample.subcategory)
                end
                r.ImGui_Text(ctx, string.format("Duration: %.2fs", sample.duration or 0))
                
                r.ImGui_Separator(ctx)
                r.ImGui_Text(ctx, "Audio Properties:")
                
                if sample.brightness then
                    local brightness_pct = (sample.brightness or 0) * 100
                    r.ImGui_Text(ctx, string.format("  Brightness: %.0f%%", brightness_pct))
                end
                if sample.harmonicity then
                    local harm_pct = (sample.harmonicity or 0) * 100
                    r.ImGui_Text(ctx, string.format("  Harmonicity: %.0f%%", harm_pct))
                end
                if sample.noisiness then
                    local noise_pct = (sample.noisiness or 0) * 100
                    r.ImGui_Text(ctx, string.format("  Noisiness: %.0f%%", noise_pct))
                end
                if sample.crest_factor_db then
                    r.ImGui_Text(ctx, string.format("  Crest Factor: %.1f dB", sample.crest_factor_db))
                end
                if sample.attack_time then
                    r.ImGui_Text(ctx, string.format("  Attack: %.0f ms", (sample.attack_time or 0) * 1000))
                end
                if sample.decay_time then
                    r.ImGui_Text(ctx, string.format("  Decay: %.0f ms", (sample.decay_time or 0) * 1000))
                end
                if sample.peak_db then
                    r.ImGui_Text(ctx, string.format("  Peak: %.1f dB", sample.peak_db))
                end
                if sample.rms_db then
                    r.ImGui_Text(ctx, string.format("  RMS: %.1f dB", sample.rms_db))
                end
                
                if sample.folder and sample.folder ~= "" then
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "Folder: " .. sample.folder)
                end
                if sample.tags and #sample.tags > 0 then
                    r.ImGui_Text(ctx, "Tags: " .. table.concat(sample.tags, ", "))
                end
                if sample.confidence then
                    r.ImGui_Text(ctx, string.format("Confidence: %.0f%%", (sample.confidence or 0) * 100))
                end
                r.ImGui_EndTooltip(ctx)
            end
        end
        
        r.ImGui_EndChild(ctx)
    end
end

local function draw_ai_no_database_message(ctx)
    r.ImGui_TextWrapped(ctx, "No AI sample database found.\n\nTo create one:\n\n1. Install Python with librosa:\n   pip install librosa numpy\n\n2. Run the analyzer:\n   python analyze_samples.py <folder>\n\n3. Copy sample_database.json to the Media script folder")
    
    r.ImGui_Separator(ctx)
    
    if r.ImGui_Button(ctx, "Open Analyzer Folder") then
        local analyzer_folder = ai_samples.db_path:match("(.+)[/\\]")
        if analyzer_folder then
            r.CF_ShellExecute(analyzer_folder)
        end
    end
end

return {
    ai_samples = ai_samples,
    CHARACTER_TAGS = CHARACTER_TAGS,
    
    init = init_ai_samples,
    load_database = load_ai_database,
    reload_database = reload_ai_database,
    filter = filter_ai_samples,
    
    set_category = set_category_filter,
    set_drums_only = set_drums_only,
    set_loops_filter = set_loops_filter,
    toggle_character_tag = toggle_character_tag,
    clear_character_tags = clear_character_tags,
    set_sort = set_sort,
    
    get_sample = get_sample_by_index,
    get_filtered = function() return ai_samples.filtered_samples end,
    get_count = function() return #ai_samples.filtered_samples end,
    
    get_category_color = get_category_color,
    get_category_icon = get_category_icon,
    is_drum_category = is_drum_category,
    
    draw_category_buttons = draw_ai_category_buttons,
    draw_category_buttons_vertical = draw_ai_category_buttons_vertical,
    draw_character_tags = draw_character_tag_buttons,
    draw_filter_options = draw_ai_filter_options,
    draw_sample_list = draw_ai_sample_list,
    draw_no_database = draw_ai_no_database_message,
    
    is_loaded = function() return ai_samples.db_loaded end
}
