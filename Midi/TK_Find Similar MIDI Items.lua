-- @description TK Find Similar MIDI Items
-- @author TouristKiller
-- @version 1.8
-- @changelog:
--[[     
    v1.8:
    + Added "NEW" button to clear all results and start a fresh search
    
    v1.7:
    + Added Track Selector popup - easily select which tracks to search
    + Track selector shows track number, name and color
    + Search/filter tracks by name in the popup
    + Select All / Deselect All / Invert buttons for quick selection
    + Only tracks containing MIDI items are shown
    + Added progress indicator during analysis - UI no longer freezes
    + Analysis runs in steps allowing real-time progress feedback
    + Added "Lock" checkbox in Track Batch mode to lock the reference track
    
    v1.6:
    + Fix: "Replace Phrase" now correctly handles time selections with leading silence
    + Fix: Multi-match items now sort based on their best match
    
    v1.5:
    + UI Overhaul: Compact layout, collapsible settings, improved button organization
    + Improved Sorting: Fixed sorting for items with identical similarity scores (Track # priority)
    + Workflow: Single-click details for single matches, auto-reselect reference after replace
    
    v1.4:
    + Added Track Batch Mode: Select a track (without selecting items) to scan all items on that track
    + Results are now grouped by Reference Item in Batch Mode
    + Matches are now grouped by source track when copying
    
    v1.3:
    + Added "Max Similarity" threshold
    + Added global settings persistence (Save/Load options)
    + Added "Show Reference" button
    + Improved UI with tooltips and collapsible options
    
    v1.2:
    + Added Note Range Filter (ignore keyswitches)
    + Added "Pin to Top" option for created tracks
    
    v1.1:
    + Added pattern matching with offset detection
    + Can now find similar patterns even if notes are shifted in time
    + Added segment matching - find partial matches within larger items
    + Search modes: Full Item / Segment (find reference pattern in larger items)
    + Added Time Selection mode - use time selection within item as search pattern
    + Fixed segment matching - extra notes in matched section now reduce similarity score
    
    v1.0:
    + Initial release
    + Find MIDI items similar to reference item
    + Percentage-based similarity threshold
    + Overlay comparison with detailed statistics
    + Color coding by similarity percentage
    + Select, color, and delete similar items
]]--

local r = reaper
local has_sws = r.BR_GetMediaItemGUID ~= nil

if not has_sws then
    r.ShowMessageBox("This script requires the SWS Extension.\nPlease install it from https://www.sws-extension.org/", "SWS Required", 0)
    return
end

local ctx = r.ImGui_CreateContext('TK Find Similar MIDI Items')
local threshold = 70
local max_threshold = 100
local results = {}
local match_groups = {}
local is_batch_mode = false
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
local reference_mode = 0 -- 0: Single Item, 1: Track Batch
local time_sel_start = 0
local time_sel_end = 0
local time_sel_valid = false
local current_ref_notes = nil
local current_ref_length = 0
local make_pooled = true
local move_to_subproject = false
local filter_min_pitch = 0
local filter_max_pitch = 127
local save_settings = true
local show_settings = true
local locked_ref_track = nil
local lock_ref_track = false

local show_track_selector = false
local track_filter_text = ""
local selected_search_tracks = {}
local use_track_filter = false

local is_analyzing = false
local analyze_progress = 0
local analyze_total = 0
local analyze_status = ""
local analyze_state = nil

local EXT_SECTION = "TK_FindSimilarMIDIItems"

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
    btn_dark = 0x2A4065FF,
    btn_dark_hover = 0x3A5075FF,
    btn_dark_active = 0x1A3055FF,
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
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8, 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupBorderSize(), 1.0)
end

local function PopTheme()
    r.ImGui_PopStyleColor(ctx, 23)
    r.ImGui_PopStyleVar(ctx, 8)
end

local function DrawTooltip(text)
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, text)
        r.ImGui_EndTooltip(ctx)
    end
end

local function SaveSettings()
    r.SetExtState(EXT_SECTION, "threshold", tostring(threshold), true)
    r.SetExtState(EXT_SECTION, "max_threshold", tostring(max_threshold), true)
    r.SetExtState(EXT_SECTION, "make_pooled", tostring(make_pooled), true)
    r.SetExtState(EXT_SECTION, "move_to_subproject", tostring(move_to_subproject), true)
    r.SetExtState(EXT_SECTION, "filter_min_pitch", tostring(filter_min_pitch), true)
    r.SetExtState(EXT_SECTION, "filter_max_pitch", tostring(filter_max_pitch), true)
    r.SetExtState(EXT_SECTION, "search_mode", tostring(search_mode), true)
    r.SetExtState(EXT_SECTION, "reference_mode", tostring(reference_mode), true)
    r.SetExtState(EXT_SECTION, "show_settings", tostring(show_settings), true)
end

local function LoadSettings()
    if r.HasExtState(EXT_SECTION, "threshold") then threshold = tonumber(r.GetExtState(EXT_SECTION, "threshold")) end
    if r.HasExtState(EXT_SECTION, "max_threshold") then max_threshold = tonumber(r.GetExtState(EXT_SECTION, "max_threshold")) end
    if r.HasExtState(EXT_SECTION, "make_pooled") then make_pooled = r.GetExtState(EXT_SECTION, "make_pooled") == "true" end
    if r.HasExtState(EXT_SECTION, "move_to_subproject") then move_to_subproject = r.GetExtState(EXT_SECTION, "move_to_subproject") == "true" end
    if r.HasExtState(EXT_SECTION, "filter_min_pitch") then filter_min_pitch = tonumber(r.GetExtState(EXT_SECTION, "filter_min_pitch")) end
    if r.HasExtState(EXT_SECTION, "filter_max_pitch") then filter_max_pitch = tonumber(r.GetExtState(EXT_SECTION, "filter_max_pitch")) end
    if r.HasExtState(EXT_SECTION, "search_mode") then search_mode = tonumber(r.GetExtState(EXT_SECTION, "search_mode")) end
    if r.HasExtState(EXT_SECTION, "reference_mode") then reference_mode = tonumber(r.GetExtState(EXT_SECTION, "reference_mode")) end
    if r.HasExtState(EXT_SECTION, "show_settings") then show_settings = r.GetExtState(EXT_SECTION, "show_settings") == "true" end
end

local function GetNoteName(pitch)
    local notes = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
    local octave = math.floor(pitch / 12) - 1 
    local note_idx = (pitch % 12) + 1
    return string.format("%s%d (%d)", notes[note_idx], octave, pitch)
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
            
            if pitch < filter_min_pitch or pitch > filter_max_pitch then
                include_note = false
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
    return notes, pattern_length, first_note_time
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

local function CalculateSimilarityWithOffset(notes1, notes2, offset)
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
    local max_notes = math.max(#notes1, #notes2)
    local similarity = (total_score / max_notes) * 100
    similarity = math.max(0, math.min(100, similarity))
    return similarity, stats
end

local function FindBestOffset(notes1, notes2)
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
        local similarity, stats = CalculateSimilarityWithOffset(notes1, notes2, offset)
        if similarity > best_similarity then
            best_similarity = similarity
            best_offset = offset
            best_stats = stats
        end
    end
    best_stats.offset = best_offset
    return best_similarity, best_offset, best_stats
end

local function FindAllSegmentMatches(ref_notes, compare_notes, min_thresh, max_thresh)
    if not ref_notes or not compare_notes or #ref_notes == 0 or #compare_notes == 0 then
        return {}
    end
    
    local ref_length = 0
    for _, note in ipairs(ref_notes) do
        local note_end = note.start_rel + note.duration
        if note_end > ref_length then ref_length = note_end end
    end

    local function CalculateSegSim(offset)
        local exact, good, partial, matched, avg_overlap = MatchNotesWithOffset(ref_notes, compare_notes, offset)
        local segment_start = -offset
        local segment_end = segment_start + ref_length + 0.1
        
        local notes_in_segment = 0
        for _, note in ipairs(compare_notes) do
            local note_start = note.start_rel
            local note_end = note.start_rel + note.duration
            if note_start < segment_end and note_end > segment_start then
                notes_in_segment = notes_in_segment + 1
            end
        end

        local extra_in_segment = math.max(0, notes_in_segment - matched)
        local missing = #ref_notes - matched
        
        local exact_score = exact * 1.0
        local good_score = good * 0.8
        local partial_score = partial * 0.4
        local total_score = exact_score + good_score + partial_score
        
        local total_notes_in_comparison = #ref_notes + extra_in_segment
        local similarity = 0
        if total_notes_in_comparison > 0 then
            similarity = (total_score / total_notes_in_comparison) * 100
        end
        
        local stats = {
            exact_matches = exact,
            good_matches = good,
            partial_matches = partial,
            extra_notes = extra_in_segment,
            missing_notes = missing,
            total_ref = #ref_notes,
            matched_notes = matched,
            segment_start = segment_start
        }
        return similarity, stats
    end

    local candidates = {}
    for _, c_note in ipairs(compare_notes) do
        local ref_first = ref_notes[1]
        if c_note.pitch == ref_first.pitch then
            local offset = ref_first.start_rel - c_note.start_rel
            local similarity, stats = CalculateSegSim(offset)
            
            if similarity >= min_thresh and similarity <= max_thresh then
                table.insert(candidates, {
                    similarity = similarity,
                    offset = offset,
                    segment_start = c_note.start_rel,
                    stats = stats
                })
            end
        end
    end

    table.sort(candidates, function(a, b) return a.similarity > b.similarity end)

    local final_matches = {}
    local occupied_ranges = {} 

    for _, cand in ipairs(candidates) do
        local c_start = cand.segment_start
        local c_end = c_start + ref_length
        
        local is_overlapping = false
        for _, range in ipairs(occupied_ranges) do
            if (c_start < range[2]) and (c_end > range[1]) then
                is_overlapping = true
                break
            end
        end

        if not is_overlapping then
            table.insert(final_matches, cand)
            table.insert(occupied_ranges, {c_start, c_end})
        end
    end

    table.sort(final_matches, function(a, b) return a.segment_start < b.segment_start end)

    return final_matches
end

local function CalculateSimilarity(notes1, notes2, length1, length2, mode_override)
    local mode = mode_override or search_mode
    if mode == 0 then
        local sim, offset, stats = FindBestOffset(notes1, notes2)
        if sim >= threshold and sim <= max_threshold then
            return {{similarity=sim, offset=offset, stats=stats, segment_start=0}}
        else
            return {}
        end
    else
        return FindAllSegmentMatches(notes1, notes2, threshold, max_threshold)
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

local AnalyzeStep

local function StartAnalysis()
    if is_analyzing then return end
    
    if colors_applied then
        ClearColors()
    end
    results = {}
    match_groups = {}
    reference_item = nil
    is_batch_mode = false
    
    local track_mode_items = {}
    
    if reference_mode == 0 then
        local ref_item = GetSelectedMIDIItem()
        if not ref_item then
            r.ShowMessageBox("Please select a MIDI item as reference.", "No Item Selected", 0)
            return
        end
        table.insert(track_mode_items, ref_item)
        is_batch_mode = false
    else
        local track = nil
        if lock_ref_track and locked_ref_track and r.ValidatePtr2(0, locked_ref_track, "MediaTrack*") then
            track = locked_ref_track
        else
            track = r.GetSelectedTrack(0, 0)
        end
        if not track then
             r.ShowMessageBox("Please select a Track to scan all items.", "No Track Selected", 0)
             return
        end
        
        local count = r.CountTrackMediaItems(track)
        for i = 0, count - 1 do
            local item = r.GetTrackMediaItem(track, i)
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                table.insert(track_mode_items, item)
            end
        end
        
        if #track_mode_items == 0 then
            r.ShowMessageBox("Selected track has no MIDI items.", "No Items", 0)
            return
        end
        is_batch_mode = true
    end

    local selected_tracks = {}
    if use_track_filter then
        for guid, _ in pairs(selected_search_tracks) do
            local num_tracks = r.CountTracks(0)
            for i = 0, num_tracks - 1 do
                local tr = r.GetTrack(0, i)
                if r.GetTrackGUID(tr) == guid then
                    selected_tracks[tr] = true
                    break
                end
            end
        end
        local count = 0
        for _ in pairs(selected_tracks) do count = count + 1 end
        if count == 0 then
            r.ShowMessageBox("Track filter is enabled but no tracks are selected.\n\nPlease open the Track Selector and select at least one track.", "No Tracks Selected", 0)
            return
        end
    end

    local all_compare_items = {}
    local num_items = r.CountMediaItems(0)
    for i = 0, num_items - 1 do
        local item = r.GetMediaItem(0, i)
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            table.insert(all_compare_items, item)
        end
    end

    analyze_state = {
        track_mode_items = track_mode_items,
        selected_tracks = selected_tracks,
        use_track_filter = use_track_filter,
        all_compare_items = all_compare_items,
        processed_guids = {},
        ref_index = 1,
        compare_index = 1,
        current_ref_item = nil,
        current_ref_guid = nil,
        current_ref_notes = nil,
        current_ref_length = nil,
        current_ref_first_note_time = nil,
        group_results = {},
        phase = "ref_setup"
    }
    
    analyze_total = #track_mode_items * #all_compare_items
    analyze_progress = 0
    analyze_status = "Starting..."
    is_analyzing = true
    
    r.defer(AnalyzeStep)
end

AnalyzeStep = function()
    if not is_analyzing or not analyze_state then
        is_analyzing = false
        analyze_state = nil
        return
    end
    
    local state = analyze_state
    local items_per_step = 20
    local processed_this_step = 0
    
    while processed_this_step < items_per_step do
        if state.phase == "ref_setup" then
            if state.ref_index > #state.track_mode_items then
                state.phase = "done"
                break
            end
            
            state.current_ref_item = state.track_mode_items[state.ref_index]
            state.current_ref_guid = r.BR_GetMediaItemGUID(state.current_ref_item)
            
            if state.processed_guids[state.current_ref_guid] then
                state.ref_index = state.ref_index + 1
                processed_this_step = processed_this_step + 1
            else
                local current_ref_take = r.GetActiveTake(state.current_ref_item)
                
                if is_batch_mode then
                    state.current_ref_notes, state.current_ref_length, state.current_ref_first_note_time = ExtractMIDINotes(current_ref_take)
                else
                    time_sel_valid = false
                    if search_mode == 2 then
                        local ts_start, ts_end, valid = GetTimeSelection(state.current_ref_item)
                        if not valid then
                            r.ShowMessageBox("Please make a time selection within the selected MIDI item.", "No Time Selection", 0)
                            is_analyzing = false
                            analyze_state = nil
                            analyze_status = ""
                            return
                        end
                        time_sel_start = ts_start
                        time_sel_end = ts_end
                        time_sel_valid = true
                        state.current_ref_notes, state.current_ref_length, state.current_ref_first_note_time = ExtractMIDINotes(current_ref_take, ts_start, ts_end)
                    else
                        state.current_ref_notes, state.current_ref_length, state.current_ref_first_note_time = ExtractMIDINotes(current_ref_take)
                    end
                end

                if state.current_ref_notes and #state.current_ref_notes > 0 then
                    if not is_batch_mode then
                        reference_item = state.current_ref_item
                        reference_guid = state.current_ref_guid
                        current_ref_notes = state.current_ref_notes
                        current_ref_length = state.current_ref_length
                    end
                    
                    state.group_results = {}
                    state.compare_index = 1
                    state.phase = "comparing"
                else
                    state.ref_index = state.ref_index + 1
                end
                processed_this_step = processed_this_step + 1
            end
            
        elseif state.phase == "comparing" then
            if state.compare_index > #state.all_compare_items then
                state.phase = "finalize_group"
            else
                local item = state.all_compare_items[state.compare_index]
                local item_guid = r.BR_GetMediaItemGUID(item)
                local is_ref_item = (item_guid == state.current_ref_guid)
                
                local effective_mode = search_mode
                if is_batch_mode and search_mode == 2 then
                    effective_mode = 0 
                end
                
                if not is_ref_item or (search_mode == 1 or search_mode == 2) then
                    local process_item = true
                    local target_track = r.GetMediaItem_Track(item)
                    
                    if state.use_track_filter then
                        if not state.selected_tracks[target_track] then
                            process_item = false
                        end
                    end
                    
                    if is_batch_mode and process_item then
                        local ref_track = r.GetMediaItem_Track(state.current_ref_item)
                        if target_track == ref_track then
                            process_item = false
                        end
                    end
                    
                    if process_item then
                        local take = r.GetActiveTake(item)
                        if take and r.TakeIsMIDI(take) then
                            local notes, item_length = ExtractMIDINotes(take)
                            if notes then
                                local matches = CalculateSimilarity(state.current_ref_notes, notes, state.current_ref_length, item_length, effective_mode)
                                
                                if is_ref_item and #matches > 0 then
                                    local filtered_matches = {}
                                    for _, m in ipairs(matches) do
                                        local is_self = false
                                        local match_start = m.segment_start or 0
                                        local tolerance = 0.05
                                        
                                        if effective_mode == 0 then
                                            is_self = true
                                        elseif search_mode == 2 and time_sel_valid then
                                            local ref_first_note = state.current_ref_first_note_time or time_sel_start
                                            if math.abs(match_start - ref_first_note) < tolerance then
                                                is_self = true
                                            end
                                        elseif search_mode == 1 then
                                            local ref_first_note = state.current_ref_first_note_time or 0
                                            if math.abs(match_start - ref_first_note) < tolerance then
                                                is_self = true
                                            end
                                        end
                                        
                                        if not is_self then
                                            table.insert(filtered_matches, m)
                                        end
                                    end
                                    matches = filtered_matches
                                end
                                
                                if #matches > 0 then
                                    local best_sim = 0
                                    for _, m in ipairs(matches) do
                                        if m.similarity > best_sim then best_sim = m.similarity end
                                    end
                                    
                                    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
                                    local track = r.GetMediaItem_Track(item)
                                    local _, track_name = r.GetTrackName(track)
                                    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
                                    table.insert(state.group_results, {
                                        item = item,
                                        guid = item_guid,
                                        matches = matches,
                                        max_similarity = best_sim,
                                        position = pos,
                                        track_name = track_name,
                                        track_num = track_num
                                    })
                                end
                            end
                        end
                    end
                end
                
                state.compare_index = state.compare_index + 1
                analyze_progress = ((state.ref_index - 1) * #state.all_compare_items) + state.compare_index
                processed_this_step = processed_this_step + 1
            end
            
        elseif state.phase == "finalize_group" then
            table.sort(state.group_results, function(a, b)
                local sim_a = a.max_similarity
                local sim_b = b.max_similarity
                
                if sim_a > 99.999 then sim_a = 100 end
                if sim_b > 99.999 then sim_b = 100 end
                
                local bin_a = math.floor(sim_a * 10000)
                local bin_b = math.floor(sim_b * 10000)
                
                if bin_a ~= bin_b then
                    return bin_a > bin_b
                end
                
                if a.track_num ~= b.track_num then
                    return a.track_num < b.track_num
                end
                
                return a.position < b.position
            end)
            
            if #state.group_results > 0 then
                local take = r.GetActiveTake(state.current_ref_item)
                local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
                table.insert(match_groups, {
                    ref_item = state.current_ref_item,
                    ref_guid = state.current_ref_guid,
                    ref_name = take_name,
                    matches = state.group_results,
                    ref_notes = state.current_ref_notes,
                    ref_length = state.current_ref_length,
                    ref_silence = (state.current_ref_first_note_time or 0) - (time_sel_start or 0)
                })
                
                state.processed_guids[state.current_ref_guid] = true
                
                if is_batch_mode then
                    local ref_track = r.GetMediaItem_Track(state.current_ref_item)
                    for _, res in ipairs(state.group_results) do
                        local res_item = r.BR_GetMediaItemByGUID(0, res.guid)
                        if res_item then
                            local res_track = r.GetMediaItem_Track(res_item)
                            if res_track == ref_track and res.max_similarity >= 99.0 then
                                state.processed_guids[res.guid] = true
                            end
                        end
                    end
                end
            end
            
            state.ref_index = state.ref_index + 1
            state.phase = "ref_setup"
            processed_this_step = processed_this_step + 1
            
        elseif state.phase == "done" then
            break
        end
    end
    
    if state.phase == "done" then
        if not is_batch_mode and #match_groups > 0 then
            results = match_groups[1].matches
        end
        
        local total_matches = 0
        for _, group in ipairs(match_groups) do
            total_matches = total_matches + #group.matches
        end
        
        analyze_status = string.format("Done! %d matches", total_matches)
        is_analyzing = false
        analyze_state = nil
    else
        local pct = 0
        if analyze_total > 0 then
            pct = math.floor((analyze_progress / analyze_total) * 100)
        end
        analyze_status = string.format("Analyzing... %d%%", pct)
        r.defer(AnalyzeStep)
    end
end

local function AnalyzeItems()
    StartAnalysis()
end

local function SelectSimilar()
    r.Undo_BeginBlock()
    r.SelectAllMediaItems(0, false)
    local count = 0
    for _, group in ipairs(match_groups) do
        for _, result in ipairs(group.matches) do
            local item = r.BR_GetMediaItemByGUID(0, result.guid)
            if item then
                r.SetMediaItemSelected(item, true)
                count = count + 1
            end
        end
    end
    r.Undo_EndBlock("Select Similar MIDI Items", -1)
    r.UpdateArrange()
end

local function DeleteSimilar()
    local total_matches = 0
    for _, group in ipairs(match_groups) do
        total_matches = total_matches + #group.matches
    end

    local answer = r.ShowMessageBox(
        "Are you sure you want to delete " .. total_matches .. " similar MIDI item(s)?\n\nThis action can be undone with Ctrl+Z.",
        "Confirm Delete",
        4
    )
    if answer ~= 6 then
        return
    end
    r.Undo_BeginBlock()
    local count = 0
    for _, group in ipairs(match_groups) do
        for _, result in ipairs(group.matches) do
            local item = r.BR_GetMediaItemByGUID(0, result.guid)
            if item then
                local track = r.GetMediaItem_Track(item)
                r.DeleteTrackMediaItem(track, item)
                count = count + 1
            end
        end
    end
    results = {}
    match_groups = {}
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
        for _, group in ipairs(match_groups) do
            for _, result in ipairs(group.matches) do
                local item = r.BR_GetMediaItemByGUID(0, result.guid)
                if item then
                    local orig_color = r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")
                    original_colors[result.guid] = orig_color
                end
            end
        end
    end
    local count = 0
    for _, group in ipairs(match_groups) do
        for _, result in ipairs(group.matches) do
            local item = r.BR_GetMediaItemByGUID(0, result.guid)
            if item then
                local color = GetSimilarityColor(result.max_similarity)
                r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color)
                count = count + 1
            end
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
    for _, group in ipairs(match_groups) do
        for _, result in ipairs(group.matches) do
            local item = r.BR_GetMediaItemByGUID(0, result.guid)
            if item then
                local orig_color = original_colors[result.guid] or 0
                r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", orig_color)
                count = count + 1
            end
        end
    end
    colors_applied = false
    original_colors = {}
    r.Undo_EndBlock("Restore Original Item Colors", -1)
    r.UpdateArrange()
end

local function ResetState()
    ClearColors()
    results = {}
    match_groups = {}
    is_batch_mode = false
    reference_item = nil
    reference_guid = nil
    current_ref_notes = nil
    current_ref_length = 0
    time_sel_start = 0
    time_sel_end = 0
    time_sel_valid = false
    locked_ref_track = nil
    lock_ref_track = false
    is_analyzing = false
    analyze_progress = 0
    analyze_total = 0
    analyze_status = ""
    analyze_state = nil
    selected_search_tracks = {}
    use_track_filter = false
    track_filter_text = ""
    r.SelectAllMediaItems(0, false)
    r.UpdateArrange()
end

local function ZoomToReference()
    if reference_item and r.ValidatePtr2(0, reference_item, "MediaItem*") then
        local pos = r.GetMediaItemInfo_Value(reference_item, "D_POSITION")
        local track = r.GetMediaItem_Track(reference_item)
        
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(reference_item, true)
        r.SetOnlyTrackSelected(track)
        
        if search_mode == 2 and time_sel_valid then
             local ts_start = pos + time_sel_start
             local ts_end = pos + time_sel_end
             r.GetSet_LoopTimeRange(true, false, ts_start, ts_end, false)
             r.SetEditCurPos(ts_start, true, false)
        else
             r.SetEditCurPos(pos, true, false)
        end
        
        r.Main_OnCommand(40913, 0) 
        r.Main_OnCommand(r.NamedCommandLookup("_SWS_HSCROLLPLAY50"), 0) 
        r.UpdateArrange()
    end
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

local function ReplaceWithReference(pooled)
    r.Undo_BeginBlock()
    local count = 0
    
    -- Collect all potential replacement actions
    local all_actions = {}
    for g_idx, group in ipairs(match_groups) do
        for r_idx, result in ipairs(group.matches) do
            table.insert(all_actions, {
                similarity = result.max_similarity,
                group_idx = g_idx,
                result_idx = r_idx,
                guid = result.guid
            })
        end
    end
    
    -- Sort by similarity (highest first)
    table.sort(all_actions, function(a, b) return a.similarity > b.similarity end)
    
    local processed_guids = {}
    
    for _, action in ipairs(all_actions) do
        if not processed_guids[action.guid] then
            local group = match_groups[action.group_idx]
            local result = group.matches[action.result_idx]
            local ref_item = group.ref_item
            
            if ref_item and r.ValidatePtr2(0, ref_item, "MediaItem*") then
                local target_item = r.BR_GetMediaItemByGUID(0, result.guid)
                if target_item then
                    r.SelectAllMediaItems(0, false)
                    r.SetMediaItemSelected(ref_item, true)
                    r.Main_OnCommand(40698, 0) -- Copy
                    
                    local track = r.GetMediaItem_Track(target_item)
                    local pos = r.GetMediaItemInfo_Value(target_item, "D_POSITION")
                    
                    r.DeleteTrackMediaItem(track, target_item)
                    
                    r.SetOnlyTrackSelected(track)
                    r.SetEditCurPos(pos, false, false)
                    
                    if pooled then
                        r.Main_OnCommand(41072, 0) 
                    else
                        r.Main_OnCommand(40058, 0) 
                    end
                    
                    count = count + 1
                    processed_guids[action.guid] = true
                end
            end
        end
    end
    
    results = {} 
    match_groups = {}
    
    if reference_item and r.ValidatePtr2(0, reference_item, "MediaItem*") then
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(reference_item, true)
        local track = r.GetMediaItem_Track(reference_item)
        r.SetOnlyTrackSelected(track)
    end
    
    r.Undo_EndBlock("Replace Similar Items with Reference", -1)
    r.UpdateArrange()
end

local function ReplaceSingleItem(group_index, match_index, pooled)
    local group = match_groups[group_index]
    if not group then return end
    
    local ref_item = group.ref_item
    if not ref_item or not r.ValidatePtr2(0, ref_item, "MediaItem*") then return end
    
    local result = group.matches[match_index]
    if not result then return end

    r.Undo_BeginBlock()
    
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(ref_item, true)
    r.Main_OnCommand(40698, 0) 
    
    local target_item = r.BR_GetMediaItemByGUID(0, result.guid)
    if target_item then
        local track = r.GetMediaItem_Track(target_item)
        local pos = r.GetMediaItemInfo_Value(target_item, "D_POSITION")
        
        r.DeleteTrackMediaItem(track, target_item)
        
        r.SetOnlyTrackSelected(track)
        r.SetEditCurPos(pos, false, false)
        
        if pooled then
            r.Main_OnCommand(41072, 0) 
        else
            r.Main_OnCommand(40058, 0) 
        end
    end
    
    table.remove(group.matches, match_index)
    if #group.matches == 0 then
        table.remove(match_groups, group_index)
    end
    
    if not is_batch_mode and #match_groups > 0 then
        results = match_groups[1].matches
    else
        results = {}
    end
    
    r.PreventUIRefresh(-1)

    if ref_item and r.ValidatePtr2(0, ref_item, "MediaItem*") then
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(ref_item, true)
        local track = r.GetMediaItem_Track(ref_item)
        r.SetOnlyTrackSelected(track)
    end
    
    r.Undo_EndBlock("Replace Item with Reference", -1)
    r.UpdateArrange()
end

local function DoReplacePhrase(target_item, match, pooled, silence_offset)
    if not target_item then return nil end
    
    local track = r.GetMediaItem_Track(target_item)
    local item_pos = r.GetMediaItemInfo_Value(target_item, "D_POSITION")
    local original_len = r.GetMediaItemInfo_Value(target_item, "D_LENGTH")
    local original_end = item_pos + original_len
    
    -- Adjust split_start by subtracting the silence prefix of the reference
    -- match.segment_start is where the first note should be
    -- We paste the clipboard which starts at (first_note - silence)
    local actual_silence = silence_offset or 0
    local split_start = item_pos + match.segment_start - actual_silence
    local split_end = split_start + current_ref_length 
    
    local item_to_delete = target_item
    
    -- If split_start is before item start, we can't split before item.
    -- But this shouldn't happen if match is valid within item.
    -- However, if silence pushes it back, we need to be careful.
    if split_start < item_pos then split_start = item_pos end
    
    if split_start > item_pos + 0.001 then
        item_to_delete = r.SplitMediaItem(target_item, split_start)
    end
    
    local new_item = nil
    
    if item_to_delete then
        local curr_pos = r.GetMediaItemInfo_Value(item_to_delete, "D_POSITION")
        local curr_len = r.GetMediaItemInfo_Value(item_to_delete, "D_LENGTH")
        local curr_end = curr_pos + curr_len
        
        if split_end < (curr_end - 0.001) then
            r.SplitMediaItem(item_to_delete, split_end)
        end
        
        r.DeleteTrackMediaItem(track, item_to_delete)
        
        r.SetOnlyTrackSelected(track)
        r.SetEditCurPos(split_start, false, false)
        
        if pooled then
            r.Main_OnCommand(41072, 0) 
        else
            r.Main_OnCommand(40058, 0) 
        end
        
        local pasted_item = r.GetSelectedMediaItem(0, 0)
        if pasted_item then
            local track_items_count = r.CountTrackMediaItems(track)
            for i = 0, track_items_count - 1 do
                local tr_item = r.GetTrackMediaItem(track, i)
                local tr_pos = r.GetMediaItemInfo_Value(tr_item, "D_POSITION")
                local tr_len = r.GetMediaItemInfo_Value(tr_item, "D_LENGTH")
                local tr_end = tr_pos + tr_len
                
                if tr_item == pasted_item then
                    r.SetMediaItemSelected(tr_item, true)
                elseif math.abs(tr_end - split_start) < 0.001 then
                    -- Left neighbor: must start >= original start
                    if tr_pos >= item_pos - 0.001 then
                        r.SetMediaItemSelected(tr_item, true)
                    end
                elseif math.abs(tr_pos - split_end) < 0.001 then
                    -- Right neighbor: must end <= original end
                    if tr_end <= original_end + 0.001 then
                        r.SetMediaItemSelected(tr_item, true)
                    end
                end
            end
            r.Main_OnCommand(41588, 0) 
            new_item = r.GetSelectedMediaItem(0, 0)
        end
    end
    
    return new_item
end

local function CopyItemToClipboard(ref_item)
    if not ref_item then return false end
    
    r.SelectAllMediaItems(0, false)
    
    if search_mode == 2 and time_sel_valid then
        local cur_ts_start, cur_ts_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        
        local ref_pos = r.GetMediaItemInfo_Value(ref_item, "D_POSITION")
        local target_ts_start = ref_pos + time_sel_start
        local target_ts_end = ref_pos + time_sel_end
        
        r.GetSet_LoopTimeRange(true, false, target_ts_start, target_ts_end, false)
        
        r.SetMediaItemSelected(ref_item, true)
        r.Main_OnCommand(40060, 0) 
        
        r.GetSet_LoopTimeRange(true, false, cur_ts_start, cur_ts_end, false)
    else
        r.SetMediaItemSelected(ref_item, true)
        r.Main_OnCommand(40698, 0) 
    end
    return true
end

local function ReplacePhrase(group_index, result_index, match_index, pooled)
    local group = match_groups[group_index]
    if not group then return end
    
    local result = group.matches[result_index]
    if not result then return end
    
    local match = result.matches[match_index]
    local target_item = r.BR_GetMediaItemByGUID(0, result.guid)
    
    if not target_item then return end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local ref_item = group.ref_item
    if ref_item and r.ValidatePtr2(0, ref_item, "MediaItem*") then
        CopyItemToClipboard(ref_item)
        
        current_ref_length = group.ref_length
        
        DoReplacePhrase(target_item, match, pooled, group.ref_silence)
    end
    
    table.remove(group.matches, result_index)
    if #group.matches == 0 then
        table.remove(match_groups, group_index)
    end
    
    if not is_batch_mode and #match_groups > 0 then
        results = match_groups[1].matches
    else
        results = {}
    end
    
    r.PreventUIRefresh(-1)

    if ref_item and r.ValidatePtr2(0, ref_item, "MediaItem*") then
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(ref_item, true)
        local track = r.GetMediaItem_Track(ref_item)
        r.SetOnlyTrackSelected(track)
    end
    
    r.Undo_EndBlock("Replace Phrase with Reference", -1)
    r.UpdateArrange()
end

local function ReplaceAllPhrases(pooled)
    if #match_groups == 0 then return end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    -- Collect all phrase actions
    local all_actions = {}
    for g_idx, group in ipairs(match_groups) do
        for r_idx, result in ipairs(group.matches) do
            for m_idx, match in ipairs(result.matches) do
                table.insert(all_actions, {
                    similarity = match.similarity,
                    group_idx = g_idx,
                    result_idx = r_idx,
                    match_idx = m_idx,
                    guid = result.guid
                })
            end
        end
    end
    
    -- Sort by similarity (highest first)
    table.sort(all_actions, function(a, b) return a.similarity > b.similarity end)
    
    local processed_items = {} -- To prevent editing an item twice and losing the pointer
    
    for _, action in ipairs(all_actions) do
        -- If we already touched this item in this batch, skip it
        -- This is safer because splitting changes GUIDs
        if not processed_items[action.guid] then
            local group = match_groups[action.group_idx]
            local result = group.matches[action.result_idx]
            local match = result.matches[action.match_idx]
            local ref_item = group.ref_item
            
            if ref_item and r.ValidatePtr2(0, ref_item, "MediaItem*") then
                local target_item = r.BR_GetMediaItemByGUID(0, result.guid)
                
                if target_item then
                    CopyItemToClipboard(ref_item)
                    
                    current_ref_length = group.ref_length
                    
                    local new_item = DoReplacePhrase(target_item, match, pooled, group.ref_silence)
                    if new_item then
                        processed_items[action.guid] = true
                    end
                end
            end
        end
    end
    
    results = {}
    match_groups = {}
    
    r.PreventUIRefresh(-1)

    if reference_item and r.ValidatePtr2(0, reference_item, "MediaItem*") then
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(reference_item, true)
        local track = r.GetMediaItem_Track(reference_item)
        r.SetOnlyTrackSelected(track)
    end
    
    r.Undo_EndBlock("Replace All Phrases", -1)
    r.UpdateArrange()
end

local function CopyMatchesToNewTrack(as_subproject, force_pin)
    if #match_groups == 0 then return end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local created_tracks = {}
    
    for _, group in ipairs(match_groups) do
        local ref_item = group.ref_item
        if ref_item and r.ValidatePtr2(0, ref_item, "MediaItem*") then
            -- Group results by source track
            local matches_by_track = {}
            local track_order = {} 
            
            for _, result in ipairs(group.matches) do
                local item = r.BR_GetMediaItemByGUID(0, result.guid)
                if item then
                    local track = r.GetMediaItem_Track(item)
                    if not matches_by_track[track] then
                        matches_by_track[track] = {
                            name = result.track_name,
                            items = {}
                        }
                        table.insert(track_order, track)
                    end
                    table.insert(matches_by_track[track].items, result)
                end
            end
            
            -- Copy Reference
            r.SelectAllMediaItems(0, false)
            r.SetMediaItemSelected(ref_item, true)
            r.Main_OnCommand(40698, 0) -- Copy
            
            -- Create Reference Track
            local insert_idx = r.CountTracks(0)
            r.InsertTrackAtIndex(insert_idx, true)
            local ref_track = r.GetTrack(0, insert_idx)
            
            local ref_name = group.ref_name or "Reference"
            r.GetSetMediaTrackInfo_String(ref_track, "P_NAME", "REF: " .. ref_name, true)
            
            local ref_pos = r.GetMediaItemInfo_Value(ref_item, "D_POSITION")
            local ref_paste_pos = ref_pos
            if not is_batch_mode and search_mode == 2 and time_sel_valid then
                ref_paste_pos = ref_pos + time_sel_start
            end
            
            r.SetOnlyTrackSelected(ref_track)
            r.SetEditCurPos(ref_paste_pos, false, false)
            r.Main_OnCommand(40058, 0) -- Paste
            
            table.insert(created_tracks, ref_track)
            
            -- Create tracks for matches
            for _, source_track in ipairs(track_order) do
                local track_data = matches_by_track[source_track]
                
                insert_idx = r.CountTracks(0)
                r.InsertTrackAtIndex(insert_idx, true)
                local new_track = r.GetTrack(0, insert_idx)
                r.GetSetMediaTrackInfo_String(new_track, "P_NAME", "Matches: " .. track_data.name, true)
                
                for _, result in ipairs(track_data.items) do
                    local target_item = r.BR_GetMediaItemByGUID(0, result.guid)
                    if target_item then 
                        local item_pos = r.GetMediaItemInfo_Value(target_item, "D_POSITION")
                        
                        for _, match in ipairs(result.matches) do
                            local paste_pos = item_pos + match.segment_start
                            
                            r.SetOnlyTrackSelected(new_track)
                            r.SetEditCurPos(paste_pos, false, false)
                            r.Main_OnCommand(40058, 0) -- Paste
                        end
                    end
                end
                
                table.insert(created_tracks, new_track)
            end
        end
    end
    
    if as_subproject then
        r.SetOnlyTrackSelected(created_tracks[1])
        for i = 2, #created_tracks do
            r.SetTrackSelected(created_tracks[i], true)
        end
        r.Main_OnCommand(41997, 0) -- Track: Move tracks to new subproject
    end
    
    if reference_guid then
        local ref_item_restore = r.BR_GetMediaItemByGUID(0, reference_guid)
        if ref_item_restore then
            r.SelectAllMediaItems(0, false)
            r.SetMediaItemSelected(ref_item_restore, true)
        end
    end
    
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Copy Matches to " .. (as_subproject and "Subproject" or "New Tracks"), -1)
    r.UpdateArrange()

    if force_pin and not as_subproject then
        for i = #created_tracks, 1, -1 do
            local tr = created_tracks[i]
            if r.ValidatePtr2(0, tr, "MediaTrack*") then
                r.SetOnlyTrackSelected(tr)
                r.Main_OnCommand(40000, 0) -- Pin to top
            end
        end
    end
end

local function DrawColorLegend()
    r.ImGui_Spacing(ctx)
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
end

local function GetAllTracksWithMIDI()
    local tracks = {}
    local num_tracks = r.CountTracks(0)
    for i = 0, num_tracks - 1 do
        local track = r.GetTrack(0, i)
        local has_midi = false
        local item_count = r.CountTrackMediaItems(track)
        for j = 0, item_count - 1 do
            local item = r.GetTrackMediaItem(track, j)
            local take = r.GetActiveTake(item)
            if take and r.TakeIsMIDI(take) then
                has_midi = true
                break
            end
        end
        if has_midi then
            local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
            local _, track_name = r.GetTrackName(track)
            local track_color = r.GetTrackColor(track)
            table.insert(tracks, {
                track = track,
                num = track_num,
                name = track_name,
                color = track_color
            })
        end
    end
    return tracks
end

local function DrawTrackSelectorPopup()
    if not show_track_selector then return end
    
    r.ImGui_SetNextWindowSize(ctx, 400, 450, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, 'Select Tracks to Search', true, r.ImGui_WindowFlags_None())
    
    if visible then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_cyan)
        r.ImGui_Text(ctx, "Track Selection")
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
        r.ImGui_Text(ctx, "Search:")
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local changed_filter, new_filter = r.ImGui_InputText(ctx, "##trackfilter", track_filter_text)
        if changed_filter then
            track_filter_text = new_filter
        end
        
        r.ImGui_Spacing(ctx)
        
        local tracks = GetAllTracksWithMIDI()
        local filtered_tracks = {}
        local filter_lower = track_filter_text:lower()
        
        for _, t in ipairs(tracks) do
            if filter_lower == "" or t.name:lower():find(filter_lower, 1, true) then
                table.insert(filtered_tracks, t)
            end
        end
        
        if r.ImGui_Button(ctx, "Select All", 90, 0) then
            for _, t in ipairs(filtered_tracks) do
                local guid = r.GetTrackGUID(t.track)
                selected_search_tracks[guid] = true
            end
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Deselect All", 100, 0) then
            for _, t in ipairs(filtered_tracks) do
                local guid = r.GetTrackGUID(t.track)
                selected_search_tracks[guid] = nil
            end
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Invert", 70, 0) then
            for _, t in ipairs(filtered_tracks) do
                local guid = r.GetTrackGUID(t.track)
                if selected_search_tracks[guid] then
                    selected_search_tracks[guid] = nil
                else
                    selected_search_tracks[guid] = true
                end
            end
        end
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        
        local selected_count = 0
        for _ in pairs(selected_search_tracks) do
            selected_count = selected_count + 1
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_muted)
        r.ImGui_Text(ctx, string.format("Selected: %d tracks | Showing: %d/%d tracks with MIDI", selected_count, #filtered_tracks, #tracks))
        r.ImGui_PopStyleColor(ctx, 1)
        
        r.ImGui_Separator(ctx)
        
        local child_height = r.ImGui_GetContentRegionAvail(ctx) - 35
        if r.ImGui_BeginChild(ctx, "##tracklist", -1, child_height, 1) then
            for _, t in ipairs(filtered_tracks) do
                local guid = r.GetTrackGUID(t.track)
                local is_selected = selected_search_tracks[guid] == true
                
                r.ImGui_PushID(ctx, guid)
                
                local draw_list = r.ImGui_GetWindowDrawList(ctx)
                local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
                
                if t.color ~= 0 then
                    local rr = (t.color & 0xFF)
                    local gg = ((t.color >> 8) & 0xFF)
                    local bb = ((t.color >> 16) & 0xFF)
                    local color_hex = (rr << 24) | (gg << 16) | (bb << 8) | 0xFF
                    r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy + 2, cx + 12, cy + 18, color_hex)
                else
                    r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy + 2, cx + 12, cy + 18, 0x666666FF)
                end
                
                r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + 18)
                
                local changed_cb, new_cb = r.ImGui_Checkbox(ctx, string.format("%02d: %s", t.num, t.name), is_selected)
                if changed_cb then
                    if new_cb then
                        selected_search_tracks[guid] = true
                    else
                        selected_search_tracks[guid] = nil
                    end
                end
                
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        local btn_width = 120
        local total_width = btn_width * 2 + 10
        local avail = r.ImGui_GetContentRegionAvail(ctx)
        r.ImGui_SetCursorPosX(ctx, (avail - total_width) / 2 + r.ImGui_GetCursorPosX(ctx))
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.accent_green)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xAEDE7AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x8EBE5AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x000000FF)
        if r.ImGui_Button(ctx, "Apply", btn_width, 0) then
            use_track_filter = selected_count > 0
            show_track_selector = false
        end
        r.ImGui_PopStyleColor(ctx, 4)
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, "Cancel", btn_width, 0) then
            show_track_selector = false
        end
        
        r.ImGui_End(ctx)
    end
    
    if not open then
        show_track_selector = false
    end
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
        
        r.ImGui_SameLine(ctx)
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        local btn_size = 18
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + avail_w - btn_size)
        
        local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_InvisibleButton(ctx, "##collapse_btn", btn_size, btn_size) then
            show_settings = not show_settings
        end
        
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local col = COLORS.accent_cyan
        local center_x = cursor_x + btn_size * 0.5
        local center_y = cursor_y + btn_size * 0.5
        local w = btn_size * 0.6
        local h = btn_size * 0.3
        
        if show_settings then
            -- Pointing Up /\
            r.ImGui_DrawList_AddLine(draw_list, center_x - w/2, center_y + h/2, center_x, center_y - h/2, col, 2.0)
            r.ImGui_DrawList_AddLine(draw_list, center_x, center_y - h/2, center_x + w/2, center_y + h/2, col, 2.0)
        else
            -- Pointing Down \/
            r.ImGui_DrawList_AddLine(draw_list, center_x - w/2, center_y - h/2, center_x, center_y + h/2, col, 2.0)
            r.ImGui_DrawList_AddLine(draw_list, center_x, center_y + h/2, center_x + w/2, center_y - h/2, col, 2.0)
        end

        if title_font then
            r.ImGui_PopFont(ctx)
        end
        r.ImGui_Separator(ctx)
        
        if show_settings then
            r.ImGui_Spacing(ctx)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
            r.ImGui_Text(ctx, "Reference Mode:")
            r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_SameLine(ctx, 150)
            r.ImGui_SetNextItemWidth(ctx, -1)
            local changed_ref, new_ref = r.ImGui_Combo(ctx, '##refmode', reference_mode, "Single Item (Selected)\0Track Batch (Selected Track)\0")
            if changed_ref then
                reference_mode = new_ref
                lock_ref_track = false
                locked_ref_track = nil
            end

            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
            r.ImGui_Text(ctx, "Search Mode:")
            r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_SameLine(ctx, 150)
            r.ImGui_SetNextItemWidth(ctx, -1)
            
            -- Adjust search mode if incompatible with reference mode
            if reference_mode == 1 and search_mode == 2 then
                search_mode = 0
            end
            
            local search_options = "Full Item Match\0Phrase Match (find pattern in larger items)\0Time Selection (use time selection as pattern)\0"
            if reference_mode == 1 then
                search_options = "Full Item Match\0Phrase Match (find pattern in larger items) (Batch)\0"
            end
            
            local changed_mode, new_mode = r.ImGui_Combo(ctx, '##searchmode', search_mode, search_options)
            if changed_mode then
                search_mode = new_mode
            end
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
            r.ImGui_Text(ctx, "Min Similarity:")
            r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_SameLine(ctx, 150)
            r.ImGui_SetNextItemWidth(ctx, -1)
            local changed, new_threshold = r.ImGui_SliderInt(ctx, '##threshold', threshold, 0, max_threshold, '%d%%')
            if changed then
                threshold = new_threshold
            end
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
            r.ImGui_Text(ctx, "Max Similarity:")
            r.ImGui_PopStyleColor(ctx, 1)
            r.ImGui_SameLine(ctx, 150)
            r.ImGui_SetNextItemWidth(ctx, -1)
            local changed_max, new_max = r.ImGui_SliderInt(ctx, '##max_threshold', max_threshold, threshold, 100, '%d%%')
            if changed_max then
                max_threshold = new_max
            end
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
            r.ImGui_Text(ctx, "Note Range Filter:")
            r.ImGui_PopStyleColor(ctx, 1)
            
            r.ImGui_PushItemWidth(ctx, -1)
            local changed_min_pitch, new_min_pitch = r.ImGui_SliderInt(ctx, "##minpitch", filter_min_pitch, 0, 127, "Min: " .. GetNoteName(filter_min_pitch))
            if changed_min_pitch then
                filter_min_pitch = new_min_pitch
                if filter_min_pitch > filter_max_pitch then filter_max_pitch = filter_min_pitch end
            end
            
            local changed_max_pitch, new_max_pitch = r.ImGui_SliderInt(ctx, "##maxpitch", filter_max_pitch, 0, 127, "Max: " .. GetNoteName(filter_max_pitch))
            if changed_max_pitch then
                filter_max_pitch = new_max_pitch
                if filter_max_pitch < filter_min_pitch then filter_min_pitch = filter_max_pitch end
            end
            r.ImGui_PopItemWidth(ctx)

            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
            r.ImGui_Text(ctx, "Track Filter:")
            r.ImGui_PopStyleColor(ctx, 1)
            
            local filter_status = "All tracks"
            if use_track_filter then
                local count = 0
                for _ in pairs(selected_search_tracks) do count = count + 1 end
                filter_status = string.format("%d tracks selected", count)
            end
            
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), use_track_filter and COLORS.accent_green or COLORS.text_muted)
            r.ImGui_Text(ctx, "(" .. filter_status .. ")")
            r.ImGui_PopStyleColor(ctx, 1)
            
            if r.ImGui_Button(ctx, "Select Tracks...", -1, 0) then
                show_track_selector = true
            end
            DrawTooltip("Open a window to select specific tracks to search.\nOnly tracks with MIDI items are shown.")
            
            if use_track_filter then
                r.ImGui_SameLine(ctx)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.accent_red)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF8899FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xE75668FF)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
                if r.ImGui_SmallButton(ctx, "Clear") then
                    use_track_filter = false
                    selected_search_tracks = {}
                end
                r.ImGui_PopStyleColor(ctx, 4)
                DrawTooltip("Clear track selection filter and search all tracks.")
            end

            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)
        end
        local ref_text = "No reference selected"
        local show_lock_checkbox = false
        local current_batch_track = nil
        if reference_mode == 1 then
             if lock_ref_track and locked_ref_track and r.ValidatePtr2(0, locked_ref_track, "MediaTrack*") then
                 current_batch_track = locked_ref_track
             else
                 current_batch_track = r.GetSelectedTrack(0, 0)
             end
             if current_batch_track then
                 local _, track_name = r.GetTrackName(current_batch_track)
                 ref_text = "Batch: '" .. track_name .. "'"
                 show_lock_checkbox = true
             else
                 ref_text = "Batch Mode: No track selected"
             end
        else
            local display_item = reference_item
            if not display_item or not r.ValidatePtr2(0, display_item, "MediaItem*") then
                display_item = GetSelectedMIDIItem()
            end
            if display_item and r.ValidatePtr2(0, display_item, "MediaItem*") then
                local ref_take = r.GetActiveTake(display_item)
                if ref_take then
                    local _, take_name = r.GetSetMediaItemTakeInfo_String(ref_take, "P_NAME", "", false)
                    local ref_track = r.GetMediaItem_Track(display_item)
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
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_purple)
        r.ImGui_Text(ctx, ref_text)
        r.ImGui_PopStyleColor(ctx, 1)
        
        if show_lock_checkbox and current_batch_track then
            r.ImGui_SameLine(ctx)
            local changed_lock, new_lock = r.ImGui_Checkbox(ctx, "Lock", lock_ref_track)
            if changed_lock then
                lock_ref_track = new_lock
                if lock_ref_track then
                    locked_ref_track = current_batch_track
                else
                    locked_ref_track = nil
                end
            end
            DrawTooltip("Lock the reference track so you can select other tracks to search without changing the reference.")
        end
        
        if reference_item and r.ValidatePtr2(0, reference_item, "MediaItem*") then
             r.ImGui_SameLine(ctx)
             
             r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0)
             r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COLORS.accent_cyan)
             r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_cyan)
             r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 1)
             r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0)
             
             if r.ImGui_SmallButton(ctx, "Show##Ref") then
                 ZoomToReference()
             end
             
             r.ImGui_PopStyleVar(ctx, 2)
             r.ImGui_PopStyleColor(ctx, 3)
             
             DrawTooltip("Zoom to and select the reference item.")
        end

        if search_mode == 2 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_muted)
            r.ImGui_Text(ctx, "Make a time selection within the item before searching")
            r.ImGui_PopStyleColor(ctx, 1)
        end
        r.ImGui_Spacing(ctx)
        local avail_width = r.ImGui_GetContentRegionAvail(ctx)
        
        if is_analyzing then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.text_muted)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.text_muted)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.text_muted)
            r.ImGui_Button(ctx, 'Analyzing...', avail_width, 32)
            r.ImGui_PopStyleColor(ctx, 3)
            
            local pct = 0
            if analyze_total > 0 then
                pct = analyze_progress / analyze_total
            end
            r.ImGui_ProgressBar(ctx, pct, avail_width, 18, analyze_status)
        else
            local btn_width = (avail_width - 6) * 0.75
            local new_btn_width = (avail_width - 6) * 0.25
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            if r.ImGui_Button(ctx, 'Find Similar Items', btn_width, 32) then
                AnalyzeItems()
            end
            DrawTooltip("Analyze selected items and find matches based on current settings.")
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.btn_dark)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.btn_dark_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.btn_dark_active)
            if r.ImGui_Button(ctx, 'NEW', new_btn_width, 32) then
                ResetState()
            end
            DrawTooltip("Clear all results and start a new search.")
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_PopStyleColor(ctx, 1)
            
            if analyze_status ~= "" then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_green)
                r.ImGui_Text(ctx, analyze_status)
                r.ImGui_PopStyleColor(ctx, 1)
            end
        end
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
        local total_matches = 0
        for _, group in ipairs(match_groups) do
            total_matches = total_matches + #group.matches
        end
        r.ImGui_Text(ctx, string.format("Found: %d similar items", total_matches))
        r.ImGui_PopStyleColor(ctx, 1)
        DrawColorLegend()
        
        local footer_height = 0
        if total_matches > 0 then
            footer_height = 65
        end
        
        if r.ImGui_BeginChild(ctx, 'results_list', 0, -footer_height, 1) then
            for g_idx, group in ipairs(match_groups) do
                r.ImGui_PushID(ctx, g_idx)
                local show_group = true
                if is_batch_mode or #match_groups > 1 then
                    local group_title = string.format("Ref: %s (%d matches)", group.ref_name, #group.matches)
                    show_group = r.ImGui_TreeNode(ctx, group_title)
                end
                
                if show_group then
                    for i, result in ipairs(group.matches) do
                        local item = r.BR_GetMediaItemByGUID(0, result.guid)
                        if item then
                            local match_count = #result.matches
                            local best_match = result.matches[1]
                            
                            local sim_color
                            if result.max_similarity >= 95 then
                                sim_color = COLORS.accent_green
                            elseif result.max_similarity >= 85 then
                                sim_color = COLORS.accent_cyan
                            elseif result.max_similarity >= 75 then
                                sim_color = COLORS.accent_yellow
                            else
                                sim_color = COLORS.accent_red
                            end
                            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), sim_color)
                            
                            local header_text = string.format("%d. [%d] %s @ %s", i, result.track_num, result.track_name, FormatTime(result.position))
                            if match_count > 1 then
                                header_text = header_text .. string.format(" (%d matches, max %.1f%%)", match_count, result.max_similarity)
                            else
                                header_text = header_text .. string.format(" [%.1f%%]", best_match.similarity)
                            end

                            r.ImGui_PushID(ctx, i)
                            local node_open = r.ImGui_TreeNode(ctx, header_text)
                            
                            if r.ImGui_IsItemHovered(ctx) then
                                r.ImGui_SetTooltip(ctx, string.format("Exact Similarity: %.5f%%", result.max_similarity))
                            end

                            if node_open then
                                r.ImGui_PopStyleColor(ctx, 1)
                                
                                for m_idx, match in ipairs(result.matches) do
                                    r.ImGui_PushID(ctx, m_idx)
                                    
                                    local show_content = true
                                    if match_count > 1 then
                                        local match_title = string.format("Match %d: %.1f%% at %.2fs", m_idx, match.similarity, match.segment_start)
                                        show_content = r.ImGui_TreeNode(ctx, match_title)
                                    end
                                    
                                    if show_content then
                                        local stats = match.stats
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.text_secondary)
                                        r.ImGui_Text(ctx, string.format("   Notes: Ref=%d  Matched=%d", stats.total_ref, stats.matched_notes))
                                        if stats.avg_overlap and stats.avg_overlap > 0 then
                                            r.ImGui_Text(ctx, string.format("   Avg overlap: %.0f%%", stats.avg_overlap))
                                        end
                                        if match.offset and math.abs(match.offset) >= 0.001 then
                                            r.ImGui_Text(ctx, string.format("   Time offset: %.3f seconds", match.offset))
                                        end
                                        r.ImGui_PopStyleColor(ctx, 1)
                                        
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_green)
                                        r.ImGui_Text(ctx, string.format("   Exact: %d", stats.exact_matches or 0))
                                        r.ImGui_PopStyleColor(ctx, 1)
                                        r.ImGui_SameLine(ctx)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_cyan)
                                        r.ImGui_Text(ctx, string.format("  Good: %d", stats.good_matches or 0))
                                        r.ImGui_PopStyleColor(ctx, 1)
                                        r.ImGui_SameLine(ctx)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_yellow)
                                        r.ImGui_Text(ctx, string.format("  Partial: %d", stats.partial_matches or 0))
                                        r.ImGui_PopStyleColor(ctx, 1)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COLORS.accent_red)
                                        r.ImGui_Text(ctx, string.format("   Missing: %d  Extra: %d", stats.missing_notes or 0, stats.extra_notes or 0))
                                        r.ImGui_PopStyleColor(ctx, 1)

                                        r.ImGui_Spacing(ctx)
                                        
                                        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
                                        local btn_w = (avail_w - 8) / 2
                                        
                                        -- Row 1: Select Item, Replace Item
                                        if r.ImGui_Button(ctx, 'Select Item', btn_w, 22) then
                                            ZoomToItem(item, match.segment_start)
                                        end
                                        DrawTooltip("Select and show this specific match.")
                                        
                                        r.ImGui_SameLine(ctx, 0, 8)
                                        
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.btn_dark)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.btn_dark_hover)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.btn_dark_active)
                                        
                                        if r.ImGui_Button(ctx, 'Replace Item', btn_w, 22) then
                                            ReplaceSingleItem(g_idx, i, false)
                                        end
                                        if r.ImGui_IsItemClicked(ctx, 1) then
                                            ReplaceSingleItem(g_idx, i, true)
                                        end
                                        DrawTooltip("Replace the entire item with a COPY of the reference.\nRight-click for POOLED copy.")
                                        
                                        r.ImGui_PopStyleColor(ctx, 3)
                                        
                                        -- Row 2: Select Phrase, Replace Phrase
                                        if r.ImGui_Button(ctx, 'Select Phrase', btn_w, 22) then
                                            ZoomAndSelectPhrase(item, match.segment_start, group.ref_notes, match.offset)
                                        end
                                        DrawTooltip("Select the time range of this phrase.")
                                        
                                        r.ImGui_SameLine(ctx, 0, 8)
                                        
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.btn_dark)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.btn_dark_hover)
                                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.btn_dark_active)
                                        
                                        if r.ImGui_Button(ctx, 'Replace Phrase', btn_w, 22) then
                                            ReplacePhrase(g_idx, i, m_idx, false)
                                        end
                                        if r.ImGui_IsItemClicked(ctx, 1) then
                                            ReplacePhrase(g_idx, i, m_idx, true)
                                        end
                                        DrawTooltip("Replace this phrase with a COPY of the reference.\nRight-click for POOLED copy.")
                                        
                                        r.ImGui_PopStyleColor(ctx, 3)
                                        
                                        if match_count > 1 then
                                            r.ImGui_TreePop(ctx)
                                        end
                                    end
                                    r.ImGui_PopID(ctx)
                                end
                                
                                r.ImGui_TreePop(ctx)
                            else
                                r.ImGui_PopStyleColor(ctx, 1)
                            end
                            r.ImGui_PopID(ctx)
                        end
                    end
                    if is_batch_mode or #match_groups > 1 then
                        r.ImGui_TreePop(ctx)
                    end
                end
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndChild(ctx)
        end
        
        if total_matches > 0 then
            r.ImGui_Spacing(ctx)
            local btn_avail_width = r.ImGui_GetContentRegionAvail(ctx)
            local btn_spacing = 8
            
            local btn_width_3 = (btn_avail_width - (btn_spacing * 2)) / 3
            local btn_width_2 = (btn_avail_width - btn_spacing) / 2
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
            
            -- Row 1: Select All, Replace, Delete All
            if r.ImGui_Button(ctx, 'Select All', btn_width_3, 22) then
                SelectSimilar()
            end
            DrawTooltip("Select all found items in the arrange view.")
            
            r.ImGui_SameLine(ctx, 0, btn_spacing)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.btn_dark)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COLORS.btn_dark_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COLORS.btn_dark_active)
            
            if search_mode == 0 then
                if r.ImGui_Button(ctx, 'Replace', btn_width_3, 22) then
                    local answer = r.ShowMessageBox("Replace all found items with a COPY of the reference?", "Confirm Replace", 4)
                    if answer == 6 then ReplaceWithReference(false) end
                end
                if r.ImGui_IsItemClicked(ctx, 1) then
                    local answer = r.ShowMessageBox("Replace all found items with a POOLED copy of the reference?\n(Changes to one will affect all)", "Confirm Replace (Pooled)", 4)
                    if answer == 6 then ReplaceWithReference(true) end
                end
                DrawTooltip("Replace all found items with the reference item.\nRight-click to Replace with Pooled copies.")
            else
                if r.ImGui_Button(ctx, 'Replace Phrases', btn_width_3, 22) then
                    local answer = r.ShowMessageBox("Replace ALL found phrases with a COPY of the reference?\nThis will modify multiple items.", "Confirm Replace All", 4)
                    if answer == 6 then ReplaceAllPhrases(false) end
                end
                if r.ImGui_IsItemClicked(ctx, 1) then
                    local answer = r.ShowMessageBox("Replace ALL found phrases with a POOLED copy of the reference?\nThis will modify multiple items.", "Confirm Replace All (Pooled)", 4)
                    if answer == 6 then ReplaceAllPhrases(true) end
                end
                DrawTooltip("Replace all found phrases with the reference.\nRight-click to Replace with Pooled copies.")
            end
            
            r.ImGui_SameLine(ctx, 0, btn_spacing)
            
            if r.ImGui_Button(ctx, 'Delete All', btn_width_3, 22) then
                DeleteSimilar()
            end
            DrawTooltip("Delete all found items from the project (Destructive!).")
            r.ImGui_PopStyleColor(ctx, 3) -- Pop btn_dark
            
            -- Row 2: Color Similar, Copy to Track, Copy to Sub
            if r.ImGui_Button(ctx, 'Color Similar', btn_width_3, 22) then
                ColorSimilar()
            end
            if r.ImGui_IsItemClicked(ctx, 1) then
                ClearColors()
            end
            DrawTooltip("Color code found items based on similarity percentage.\nRight-click to Clear Colors.")
            
            r.ImGui_SameLine(ctx, 0, btn_spacing)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.btn_primary)
            if r.ImGui_Button(ctx, 'Copy to Track', btn_width_3, 22) then
                CopyMatchesToNewTrack(false, false)
            end
            if r.ImGui_IsItemClicked(ctx, 1) then
                CopyMatchesToNewTrack(false, true)
            end
            DrawTooltip("Copy found matches to new tracks.\nRight-click to Copy and Pin to Top.")
            
            r.ImGui_SameLine(ctx, 0, btn_spacing)
            
            if r.ImGui_Button(ctx, 'Copy to Sub', btn_width_3, 22) then
                CopyMatchesToNewTrack(true, false)
            end
            DrawTooltip("Copy found matches to a new subproject.")
            r.ImGui_PopStyleColor(ctx, 1) -- Pop btn_primary
            
            r.ImGui_PopStyleColor(ctx, 1) -- Pop text color
            r.ImGui_Dummy(ctx, 0, 2) -- Extra space at bottom
        end
        r.ImGui_End(ctx)
    end
    
    DrawTrackSelectorPopup()
    
    PopTheme()
    if font then
        r.ImGui_PopFont(ctx)
    end
    if open then
        r.defer(loop)
    end
end

local function OnExit()
    SaveSettings()
    if colors_applied then
        ClearColors()
    end
end

LoadSettings()
r.atexit(OnExit)
r.defer(loop)
