-- @description TK Find Similar MIDI Items
-- @author TouristKiller
-- @version 1.3
-- @changelog:
--[[     
    + Initial release
    + Find MIDI items similar to reference item
    + Percentage-based similarity threshold
    + Overlay comparison with detailed statistics
    + Color coding by similarity percentage
    + Select, color, and delete similar items
    + v1.1: Added pattern matching with offset detection
    + v1.1: Can now find similar patterns even if notes are shifted in time
    + v1.2: Added segment matching - find partial matches within larger items
    + v1.2: Search modes: Full Item / Segment (find reference pattern in larger items)
    + v1.3: Added Time Selection mode - use time selection within item as search pattern
]]--

local r = reaper
local has_sws = r.BR_GetMediaItemGUID ~= nil

if not has_sws then
    r.ShowMessageBox("This script requires the SWS Extension.\nPlease install it from https://www.sws-extension.org/", "SWS Required", 0)
    return
end

local ctx = r.ImGui_CreateContext('TK Find Similar MIDI Items')
local threshold = 70
local results = {}
local reference_item = nil
local reference_guid = nil
local show_main_window = true
local font = nil
local title_font = nil
local font_loaded = false
local title_font_loaded = false
local original_colors = {}
local colors_applied = false
local search_mode = 0
local time_sel_start = 0
local time_sel_end = 0
local time_sel_valid = false
local current_ref_notes = nil
local current_ref_length = 0

local COLORS = {
    bg_window = 0x0F0F17FF,
    bg_child = 0x1A1B26FF,
    bg_popup = 0x1A1B26FF,
    bg_frame = 0x232433FF,
    bg_frame_hover = 0x2D2F42FF,
    bg_frame_active = 0x363850FF,
    bg_header = 0x2A2C40FF,
    bg_header_hover = 0x353751FF,
    bg_header_active = 0x404261FF,
    btn_primary = 0x4A6FA5FF,
    btn_primary_hover = 0x5A7FB8FF,
    btn_primary_active = 0x3A5F95FF,
    accent_blue = 0x7AA2F7FF,
    accent_green = 0x9ECE6AFF,
    accent_yellow = 0xE0AF68FF,
    accent_red = 0xF7768EFF,
    accent_purple = 0xBB9AF7FF,
    accent_cyan = 0x7DCFFFFF,
    text_primary = 0xFFFFFFFF,
    text_secondary = 0xA9B1D6FF,
    text_muted = 0x565F89FF,
    border = 0x414868FF,
    border_light = 0x565F89FF,
    slider_grab = 0x7AA2F7FF,
    slider_grab_active = 0x89B4FAFF,
    scrollbar = 0x414868FF,
    scrollbar_hover = 0x565F89FF,
    scrollbar_active = 0x7AA2F7FF,
    title_bg = 0x1A1B26FF,
    title_bg_active = 0x24283BFF,
    separator = 0x414868FF,
    resize_grip = 0x414868AA,
    resize_grip_hover = 0x7AA2F7CC,
    resize_grip_active = 0x7AA2F7FF,
    check_mark = 0x7AA2F7FF,
    tab = 0x24283BFF,
    tab_hover = 0x414868FF,
    tab_active = 0x7AA2F7FF,
}

local function ApplyTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COLORS.bg_window)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COLORS.bg_child)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), COLORS.bg_popup)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COLORS.bg_frame)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), COLORS.bg_frame_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COLORS.bg_frame_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(), COLORS.title_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(), COLORS.title_bg_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COLORS.bg_header)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), COLORS.bg_header_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), COLORS.bg_header_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.btn_primary)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.btn_primary_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.btn_primary_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), COLORS.slider_grab)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), COLORS.slider_grab_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COLORS.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_primary)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), COLORS.text_muted)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLORS.check_mark)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), COLORS.separator)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGrip(), COLORS.resize_grip)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ResizeGripHovered(), COLORS.resize_grip_hover)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 6.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 12)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupBorderSize(), 1.0)
end

local function PopTheme()
    r.ImGui_PopStyleColor(ctx, 23)
    r.ImGui_PopStyleVar(ctx, 8)
end

local function ExtractMIDINotes(take, filter_start, filter_end)
    if not take or not r.TakeIsMIDI(take) then return nil end
    local notes = {}
    local _, note_count = r.MIDI_CountEvts(take)
    if note_count == 0 then return nil end
    local item = r.GetMediaItemTake_Item(take)
    local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local use_filter = filter_start and filter_end and filter_end > filter_start
    local first_note_time = nil
    for i = 0, note_count - 1 do
        local retval, selected, muted, startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, i)
        if retval then
            local start_time = r.MIDI_GetProjTimeFromPPQPos(take, startppq) - item_pos
            local end_time = r.MIDI_GetProjTimeFromPPQPos(take, endppq) - item_pos
            local duration = end_time - start_time
            local include_note = true
            if use_filter then
                local note_end = start_time + duration
                if start_time >= filter_end or note_end <= filter_start then
                    include_note = false
                end
            end
            if include_note then
                if first_note_time == nil then
                    first_note_time = start_time
                end
                table.insert(notes, {
                    pitch = pitch,
                    velocity = vel,
                    start_rel = start_time,
                    duration = duration,
                    channel = chan,
                    original_start = start_time
                })
            end
        end
    end
    if use_filter and #notes > 0 and first_note_time then
        for _, note in ipairs(notes) do
            note.start_rel = note.start_rel - first_note_time
        end
    end
    table.sort(notes, function(a, b) return a.start_rel < b.start_rel end)
    local pattern_length = item_length
    if use_filter then
        pattern_length = filter_end - filter_start
    end
    return notes, pattern_length
end

local function CalculateNoteOverlap(n1, n2)
    local start1, end1 = n1.start_rel, n1.start_rel + n1.duration
    local start2, end2 = n2.start_rel, n2.start_rel + n2.duration
    local overlap_start = math.max(start1, start2)
    local overlap_end = math.min(end1, end2)
    if overlap_start >= overlap_end then
        return 0, 0, 0
    end
    local overlap_duration = overlap_end - overlap_start
    local union_start = math.min(start1, start2)
    local union_end = math.max(end1, end2)
    local union_duration = union_end - union_start
    local overlap_ratio = overlap_duration / union_duration
    local start_diff = math.abs(start1 - start2)
    local end_diff = math.abs(end1 - end2)
    return overlap_ratio, start_diff, end_diff
end

local function MatchNotesWithOffset(ref_notes, compare_notes, offset)
    if not ref_notes or not compare_notes or #ref_notes == 0 or #compare_notes == 0 then
        return 0, 0, 0, 0, 0
    end
    local time_tolerance = 0.02
    local used_compare = {}
    local exact_matches = 0
    local good_matches = 0
    local partial_matches = 0
    local total_overlap = 0
    local match_count = 0
    for _, n1 in ipairs(ref_notes) do
        local best_score = 0
        local best_idx = nil
        local best_overlap = 0
        for j, n2 in ipairs(compare_notes) do
            if not used_compare[j] then
                local n2_shifted = {
                    pitch = n2.pitch,
                    start_rel = n2.start_rel + offset,
                    duration = n2.duration
                }
                if n1.pitch == n2_shifted.pitch then
                    local overlap_ratio, start_diff, end_diff = CalculateNoteOverlap(n1, n2_shifted)
                    if overlap_ratio > 0 then
                        local position_score = 0
                        if start_diff < time_tolerance and end_diff < time_tolerance then
                            position_score = 1.0
                        elseif start_diff < time_tolerance then
                            position_score = 0.7 + (0.2 * overlap_ratio)
                        elseif overlap_ratio > 0.8 then
                            position_score = 0.6 + (0.2 * overlap_ratio)
                        else
                            position_score = 0.3 + (0.4 * overlap_ratio)
                        end
                        if position_score > best_score then
                            best_score = position_score
                            best_idx = j
                            best_overlap = overlap_ratio
                        end
                    end
                end
            end
        end
        if best_idx then
            used_compare[best_idx] = true
            total_overlap = total_overlap + best_overlap
            match_count = match_count + 1
            if best_score >= 0.95 then
                exact_matches = exact_matches + 1
            elseif best_score >= 0.7 then
                good_matches = good_matches + 1
            else
                partial_matches = partial_matches + 1
            end
        end
    end
    local avg_overlap = match_count > 0 and (total_overlap / match_count * 100) or 0
    return exact_matches, good_matches, partial_matches, match_count, avg_overlap
end

local function CalculateSimilarityWithOffset(notes1, notes2, offset, segment_mode)
    if not notes1 or not notes2 or #notes1 == 0 or #notes2 == 0 then
        return 0, {}
    end
    local exact, good, partial, matched, avg_overlap = MatchNotesWithOffset(notes1, notes2, offset)
    local missing = #notes1 - matched
    local extra = #notes2 - matched
    local stats = {
        exact_matches = exact,
        good_matches = good,
        partial_matches = partial,
        pitch_only = 0,
        extra_notes = extra,
        missing_notes = missing,
        total_ref = #notes1,
        total_compared = #notes2,
        avg_overlap = avg_overlap,
        offset = offset,
        matched_notes = matched,
        score_breakdown = ""
    }
    local exact_score = exact * 1.0
    local good_score = good * 0.8
    local partial_score = partial * 0.4
    local total_score = exact_score + good_score + partial_score
    local similarity
    if segment_mode then
        similarity = (#notes1 > 0) and (total_score / #notes1 * 100) or 0
    else
        local max_notes = math.max(#notes1, #notes2)
        similarity = (total_score / max_notes) * 100
    end
    similarity = math.max(0, math.min(100, similarity))
    return similarity, stats
end

local function FindBestOffset(notes1, notes2, segment_mode)
    if not notes1 or not notes2 or #notes1 == 0 or #notes2 == 0 then
        return 0, 0, {}
    end
    local best_similarity = 0
    local best_offset = 0
    local best_stats = {}
    local offsets_to_try = {0}
    for _, n1 in ipairs(notes1) do
        for _, n2 in ipairs(notes2) do
            if n1.pitch == n2.pitch then
                local offset = n1.start_rel - n2.start_rel
                local found = false
                for _, existing in ipairs(offsets_to_try) do
                    if math.abs(existing - offset) < 0.01 then
                        found = true
                        break
                    end
                end
                if not found then
                    table.insert(offsets_to_try, offset)
                end
            end
        end
    end
    for _, offset in ipairs(offsets_to_try) do
        local similarity, stats = CalculateSimilarityWithOffset(notes1, notes2, offset, segment_mode)
        if similarity > best_similarity then
            best_similarity = similarity
            best_offset = offset
            best_stats = stats
        end
    end
    best_stats.offset = best_offset
    return best_similarity, best_offset, best_stats
end

local function FindSegmentMatch(ref_notes, compare_notes)
    if not ref_notes or not compare_notes or #ref_notes == 0 or #compare_notes == 0 then
        return 0, 0, 0, {}
    end
    if #ref_notes > #compare_notes then
        return 0, 0, 0, {}
    end
    local best_similarity = 0
    local best_offset = 0
    local best_segment_start = 0
    local best_stats = {}
    for _, c_note in ipairs(compare_notes) do
        local ref_first = ref_notes[1]
        if c_note.pitch == ref_first.pitch then
            local offset = ref_first.start_rel - c_note.start_rel
            local similarity, stats = CalculateSimilarityWithOffset(ref_notes, compare_notes, offset, true)
            if similarity > best_similarity then
                best_similarity = similarity
                best_offset = offset
                best_segment_start = c_note.start_rel
                best_stats = stats
                best_stats.segment_start = best_segment_start
            end
        end
    end
    if best_similarity < threshold then
        for i, c_note in ipairs(compare_notes) do
            for j, ref_note in ipairs(ref_notes) do
                if c_note.pitch == ref_note.pitch then
                    local offset = ref_note.start_rel - c_note.start_rel
                    local found = false
                    if math.abs(offset - best_offset) < 0.01 then
                        found = true
                    end
                    if not found then
                        local similarity, stats = CalculateSimilarityWithOffset(ref_notes, compare_notes, offset, true)
                        if similarity > best_similarity then
                            best_similarity = similarity
                            best_offset = offset
                            best_segment_start = c_note.start_rel
                            best_stats = stats
                            best_stats.segment_start = best_segment_start
                        end
                    end
                end
            end
        end
    end
    best_stats.offset = best_offset
    best_stats.segment_start = best_segment_start
    return best_similarity, best_offset, best_segment_start, best_stats
end

local function CalculateSimilarity(notes1, notes2, length1, length2)
    if search_mode == 0 then
        return FindBestOffset(notes1, notes2, false)
    else
        local sim, offset, seg_start, stats = FindSegmentMatch(notes1, notes2)
        return sim, offset, stats
    end
end

local function GetSelectedMIDIItem()
    local count = r.CountSelectedMediaItems(0)
    if count == 0 then return nil end
    for i = 0, count - 1 do
        local item = r.GetSelectedMediaItem(0, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            return item
        end
    end
    return nil
end

local ClearColors

local function GetTimeSelection(item)
    local ts_start, ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ts_end <= ts_start then
        return nil, nil, false
    end
    local item_pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local item_length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
    local item_end = item_pos + item_length
    if ts_start >= item_end or ts_end <= item_pos then
        return nil, nil, false
    end
    local rel_start = math.max(0, ts_start - item_pos)
    local rel_end = math.min(item_length, ts_end - item_pos)
    if rel_end <= rel_start then
        return nil, nil, false
    end
    return rel_start, rel_end, true
end

local function AnalyzeItems()
    if colors_applied then
        ClearColors()
    end
    results = {}
    local ref_item = GetSelectedMIDIItem()
    if not ref_item then
        r.ShowMessageBox("Please select a MIDI item as reference first.", "No Reference", 0)
        return
    end
    reference_item = ref_item
    reference_guid = r.BR_GetMediaItemGUID(ref_item)
    local ref_take = r.GetActiveTake(ref_item)
    local ref_notes, ref_length
    time_sel_valid = false
    if search_mode == 2 then
        local ts_start, ts_end, valid = GetTimeSelection(ref_item)
        if not valid then
            r.ShowMessageBox("Please make a time selection within the selected MIDI item.", "No Time Selection", 0)
            return
        end
        time_sel_start = ts_start
        time_sel_end = ts_end
        time_sel_valid = true
        ref_notes, ref_length = ExtractMIDINotes(ref_take, ts_start, ts_end)
    else
        ref_notes, ref_length = ExtractMIDINotes(ref_take)
    end
    if not ref_notes or #ref_notes == 0 then
        if search_mode == 2 then
            r.ShowMessageBox("No MIDI notes found within the time selection.", "No Notes", 0)
        else
            r.ShowMessageBox("Reference item has no MIDI notes.", "No Notes", 0)
        end
        return
    end
    current_ref_notes = ref_notes
    current_ref_length = ref_length
    local num_items = r.CountMediaItems(0)
    for i = 0, num_items - 1 do
        local item = r.GetMediaItem(0, i)
        local item_guid = r.BR_GetMediaItemGUID(item)
        if item_guid ~= reference_guid then
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                local notes, item_length = ExtractMIDINotes(take)
                if notes then
                    local similarity, offset, stats = CalculateSimilarity(ref_notes, notes, ref_length, item_length)
                    if similarity >= threshold then
                        local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                        local track = r.GetMediaItem_Track(item)
                        local _, track_name = r.GetTrackName(track)
                        table.insert(results, {
                            item = item,
                            guid = item_guid,
                            similarity = similarity,
                            stats = stats,
                            offset = offset,
                            position = pos,
                            track_name = track_name,
                            segment_start = stats.segment_start
                        })
                    end
                end
            end
        end
    end
    table.sort(results, function(a, b) return a.similarity > b.similarity end)
end

local function SelectSimilar()
    r.Undo_BeginBlock()
    r.SelectAllMediaItems(0, false)
    local count = 0
    for _, result in ipairs(results) do
        local item = r.BR_GetMediaItemByGUID(0, result.guid)
        if item then
            r.SetMediaItemSelected(item, true)
            count = count + 1
        end
    end
    r.Undo_EndBlock("Select Similar MIDI Items", -1)
    r.UpdateArrange()
end

local function DeleteSimilar()
    local answer = r.ShowMessageBox(
        "Are you sure you want to delete " .. #results .. " similar MIDI item(s)?\n\nThis action can be undone with Ctrl+Z.",
        "Confirm Delete",
        4
    )
    if answer ~= 6 then
        return
    end
    r.Undo_BeginBlock()
    local count = 0
    for _, result in ipairs(results) do
        local item = r.BR_GetMediaItemByGUID(0, result.guid)
        if item then
            local track = r.GetMediaItem_Track(item)
            r.DeleteTrackMediaItem(track, item)
            count = count + 1
        end
    end
    results = {}
    r.Undo_EndBlock("Delete Similar MIDI Items", -1)
    r.UpdateArrange()
end

local function GetSimilarityColor(similarity)
    if similarity >= 95 then
        return r.ColorToNative(0, 200, 0) | 0x1000000
    elseif similarity >= 85 then
        return r.ColorToNative(0, 180, 220) | 0x1000000
    elseif similarity >= 75 then
        return r.ColorToNative(220, 200, 0) | 0x1000000
    else
        return r.ColorToNative(220, 100, 0) | 0x1000000
    end
end

local function ColorSimilar()
    r.Undo_BeginBlock()
    if not colors_applied then
        original_colors = {}
        for _, result in ipairs(results) do
            local item = r.BR_GetMediaItemByGUID(0, result.guid)
            if item then
                local orig_color = r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
                original_colors[result.guid] = orig_color
            end
        end
    end
    local count = 0
    for _, result in ipairs(results) do
        local item = r.BR_GetMediaItemByGUID(0, result.guid)
        if item then
            local color = GetSimilarityColor(result.similarity)
            r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
            count = count + 1
        end
    end
    colors_applied = true
    r.Undo_EndBlock("Color Similar MIDI Items", -1)
    r.UpdateArrange()
end

ClearColors = function()
    if not colors_applied then return end
    r.Undo_BeginBlock()
    local count = 0
    for _, result in ipairs(results) do
        local item = r.BR_GetMediaItemByGUID(0, result.guid)
        if item then
            local orig_color = original_colors[result.guid] or 0
            r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", orig_color)
            count = count + 1
        end
    end
    colors_applied = false
    original_colors = {}
    r.Undo_EndBlock("Restore Original Item Colors", -1)
    r.UpdateArrange()
end

local function ZoomToItem(item, segment_start)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local track = r.GetMediaItem_Track(item)
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    r.SetOnlyTrackSelected(track)
    local target_pos = pos
    if segment_start and segment_start > 0 then
        target_pos = pos + segment_start
    end
    r.SetEditCurPos(target_pos, true, false)
    r.Main_OnCommand(40913, 0)
    r.Main_OnCommand(r.NamedCommandLookup("_SWS_HSCROLLPLAY50"), 0)
    r.UpdateArrange()
end

local function ZoomAndSelectPhrase(item, segment_start, ref_notes, offset)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local track = r.GetMediaItem_Track(item)
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    r.SetOnlyTrackSelected(track)
    local phrase_start = pos
    local phrase_end = pos
    if ref_notes and #ref_notes > 0 then
        local first_note_time = ref_notes[1].start_rel
        local last_note = ref_notes[#ref_notes]
        local last_note_end = last_note.start_rel + last_note.duration
        local actual_offset = offset or 0
        phrase_start = pos + first_note_time - actual_offset
        phrase_end = pos + last_note_end - actual_offset
    elseif segment_start then
        phrase_start = pos + segment_start
        if time_sel_valid then
            local duration = time_sel_end - time_sel_start
            phrase_end = phrase_start + duration
        else
            phrase_end = phrase_start + 1
        end
    end
    r.GetSet_LoopTimeRange(true, false, phrase_start, phrase_end, false)
    local target_pos = phrase_start
    r.SetEditCurPos(target_pos, true, false)
    r.Main_OnCommand(40913, 0)
    r.Main_OnCommand(r.NamedCommandLookup("_SWS_HSCROLLPLAY50"), 0)
    r.UpdateArrange()
end

local function FormatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local secs = seconds - (minutes * 60)
    return string.format("%d:%05.2f", minutes, secs)
end

local function FormatOffset(offset)
    if math.abs(offset) < 0.001 then
        return "aligned"
    elseif offset > 0 then
        return string.format("+%.2fs", offset)
    else
        return string.format("%.2fs", offset)
    end
end

local function DrawColorLegend()
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Color Legend:")
    r.ImGui_SameLine(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local box_w, box_h = 14, 14
    local spacing = 85
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + box_w, y + box_h, 0x00C800FF)
    r.ImGui_SetCursorScreenPos(ctx, x + box_w + 4, y)
    r.ImGui_Text(ctx, "95%+")
    r.ImGui_SameLine(ctx)
    x = x + spacing
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + box_w, y + box_h, 0x00B4DCFF)
    r.ImGui_SetCursorScreenPos(ctx, x + box_w + 4, y)
    r.ImGui_Text(ctx, "85%+")
    r.ImGui_SameLine(ctx)
    x = x + spacing
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + box_w, y + box_h, 0xDCC800FF)
    r.ImGui_SetCursorScreenPos(ctx, x + box_w + 4, y)
    r.ImGui_Text(ctx, "75%+")
    r.ImGui_SameLine(ctx)
    x = x + spacing
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + box_w, y + box_h, 0xC86400FF)
    r.ImGui_SetCursorScreenPos(ctx, x + box_w + 4, y)
    r.ImGui_Text(ctx, "<75%")
    r.ImGui_NewLine(ctx)
end

local function loop()
    if not font_loaded then
        font = r.ImGui_CreateFont('Consolas', 14)
        if font then
            r.ImGui_Attach(ctx, font)
        end
        font_loaded = true
    end
    if not title_font_loaded then
        title_font = r.ImGui_CreateFont('Consolas', 18)
        if title_font then
            r.ImGui_Attach(ctx, title_font)
        end
        title_font_loaded = true
    end
    if font then
        r.ImGui_PushFont(ctx, font, 14)
    end
    ApplyTheme()
    r.ImGui_SetNextWindowSize(ctx, 540, 540, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'TK Find Similar MIDI Items', true, r.ImGui_WindowFlags_None())
    if visible then
        if title_font then
            r.ImGui_PushFont(ctx, title_font, 18)
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_cyan)
        r.ImGui_Text(ctx, "Find Similar MIDI Items")
        r.ImGui_PopStyleColor(ctx, 1)
        if title_font then
            r.ImGui_PopFont(ctx)
        end
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
        r.ImGui_Text(ctx, "Search Mode:")
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local changed_mode, new_mode = r.ImGui_Combo(ctx, '##searchmode', search_mode, "Full Item Match\0Segment Match (find pattern in larger items)\0Time Selection (use time selection as pattern)\0")
        if changed_mode then
            search_mode = new_mode
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
        r.ImGui_Text(ctx, "Similarity Threshold:")
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local changed, new_threshold = r.ImGui_SliderInt(ctx, '##threshold', threshold, 0, 100, '%d%%')
        if changed then
            threshold = new_threshold
        end
        r.ImGui_Spacing(ctx)
        local ref_text = "No reference selected"
        if reference_item and r.ValidatePtr2(0, reference_item, "MediaItem*") then
            local ref_take = r.GetActiveTake(reference_item)
            if ref_take then
                local _, take_name = r.GetSetMediaItemTakeInfo_String(ref_take, "P_NAME", "", false)
                local ref_track = r.GetMediaItem_Track(reference_item)
                local _, track_name = r.GetTrackName(ref_track)
                if take_name and take_name ~= "" then
                    ref_text = "Reference: " .. take_name .. " (" .. track_name .. ")"
                else
                    ref_text = "Reference: [unnamed] (" .. track_name .. ")"
                end
                if time_sel_valid and search_mode == 2 then
                    ref_text = ref_text .. string.format(" [%.2fs - %.2fs]", time_sel_start, time_sel_end)
                end
            end
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_purple)
        r.ImGui_Text(ctx, ref_text)
        r.ImGui_PopStyleColor(ctx, 1)
        if search_mode == 2 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_muted)
            r.ImGui_Text(ctx, "Make a time selection within the item before searching")
            r.ImGui_PopStyleColor(ctx, 1)
        end
        r.ImGui_Spacing(ctx)
        local avail_width = r.ImGui_GetContentRegionAvail(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
        if r.ImGui_Button(ctx, 'Find Similar Items', avail_width, 32) then
            AnalyzeItems()
        end
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
        r.ImGui_Text(ctx, string.format("Found: %d similar items", #results))
        r.ImGui_PopStyleColor(ctx, 1)
        DrawColorLegend()
        r.ImGui_Spacing(ctx)
        if #results > 0 then
            local btn_avail_width = r.ImGui_GetContentRegionAvail(ctx)
            local btn_spacing = 8
            local btn_count = 4
            local btn_width = (btn_avail_width - (btn_spacing * (btn_count - 1))) / btn_count
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            if r.ImGui_Button(ctx, 'Select All', btn_width, 28) then
                SelectSimilar()
            end
            r.ImGui_SameLine(ctx, 0, btn_spacing)
            if r.ImGui_Button(ctx, 'Color Similar', btn_width, 28) then
                ColorSimilar()
            end
            r.ImGui_SameLine(ctx, 0, btn_spacing)
            if r.ImGui_Button(ctx, 'Clear Colors', btn_width, 28) then
                ClearColors()
            end
            r.ImGui_SameLine(ctx, 0, btn_spacing)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.accent_red)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF8899FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xDD5566FF)
            if r.ImGui_Button(ctx, 'Delete All', btn_width, 28) then
                DeleteSimilar()
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_Spacing(ctx)
        end
        if r.ImGui_BeginChild(ctx, 'results_list', 0, 0, 1) then
            for i, result in ipairs(results) do
                local item = r.BR_GetMediaItemByGUID(0, result.guid)
                if item then
                    local sim_color
                    if result.similarity >= 95 then
                        sim_color = COLORS.accent_green
                    elseif result.similarity >= 85 then
                        sim_color = COLORS.accent_cyan
                    elseif result.similarity >= 75 then
                        sim_color = COLORS.accent_yellow
                    else
                        sim_color = COLORS.accent_red
                    end
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sim_color)
                    local offset_str = FormatOffset(result.offset or 0)
                    local header_text
                    if search_mode == 1 and result.segment_start and result.segment_start > 0 then
                        header_text = string.format("%d. [%.1f%%] %s @ %s (segment @ %.2fs)",
                            i, result.similarity, result.track_name, FormatTime(result.position), result.segment_start)
                    else
                        header_text = string.format("%d. [%.1f%%] %s @ %s (%s)",
                            i, result.similarity, result.track_name, FormatTime(result.position), offset_str)
                    end
                    if r.ImGui_TreeNode(ctx, header_text) then
                        r.ImGui_PopStyleColor(ctx, 1)
                        local stats = result.stats
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
                        r.ImGui_Text(ctx, string.format("   Notes: Ref=%d  Compare=%d  Matched=%d",
                            stats.total_ref or 0, stats.total_compared or 0, stats.matched_notes or 0))
                        if stats.avg_overlap and stats.avg_overlap > 0 then
                            r.ImGui_Text(ctx, string.format("   Avg overlap: %.0f%%", stats.avg_overlap))
                        end
                        if result.offset and math.abs(result.offset) >= 0.001 then
                            r.ImGui_Text(ctx, string.format("   Time offset: %.3f seconds", result.offset))
                        end
                        if search_mode == 1 and result.segment_start and result.segment_start > 0 then
                            r.ImGui_Text(ctx, string.format("   Segment found at: %.3f seconds in item", result.segment_start))
                        end
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_green)
                        r.ImGui_Text(ctx, string.format("   Exact (same pitch+start+end): %d", stats.exact_matches or 0))
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_cyan)
                        r.ImGui_Text(ctx, string.format("   Good (same pitch, overlap >70%%): %d", stats.good_matches or 0))
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_yellow)
                        r.ImGui_Text(ctx, string.format("   Partial (same pitch, some overlap): %d", stats.partial_matches or 0))
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_red)
                        r.ImGui_Text(ctx, string.format("   Missing: %d  Extra: %d", stats.missing_notes or 0, stats.extra_notes or 0))
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_Spacing(ctx)
                        if r.ImGui_Button(ctx, 'Zoom##' .. i) then
                            ZoomToItem(item, result.segment_start)
                        end
                        r.ImGui_SameLine(ctx)
                        if r.ImGui_Button(ctx, 'Zoom + Select Phrase##' .. i) then
                            ZoomAndSelectPhrase(item, result.segment_start, current_ref_notes, result.offset)
                        end
                        r.ImGui_TreePop(ctx)
                    else
                        r.ImGui_PopStyleColor(ctx, 1)
                    end
                end
            end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_End(ctx)
    end
    PopTheme()
    if font then
        r.ImGui_PopFont(ctx)
    end
    if open then
        r.defer(loop)
    end
end

r.defer(loop)
