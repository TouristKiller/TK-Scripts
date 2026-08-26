-- TK Project Clips - Clip Launcher (phase 1, in-song model)
--
-- Engine model
--   * Every launcher column owns one hidden "lane" track that sends into a real
--     project track, so the clip is heard through that track's FX chain.
--   * Clip library items live muted and stacked at time zero on the hidden lane
--     track, and are never moved. They are the definition of a slot, not the
--     playback, and nothing addresses them by position.
--   * Launching copies the library item into a short-lived "voice" item placed
--     on the next bar boundary of the project's own grid, ahead of the play
--     cursor. The outgoing voice is trimmed to end on that same boundary.
--     Because both edits are committed before the play cursor arrives, the
--     switch is sample-accurate; no per-frame muting is involved.
--   * A track is owned either by the arrangement or by the launcher, and the
--     handover is scheduled on a boundary too: every arrangement item that
--     starts after the boundary is muted up front (exact), and only an item
--     straddling the boundary is switched when the play cursor reaches it.
--   * Original mute states are mirrored into project ext state while a takeover
--     is live, so a crash or a forced quit can still be repaired on next load.
--   * A voice is timeline media, so an arrangement loop jumping back before its
--     start would leave nothing to play. A clip launched inside a loop region
--     therefore also gets a filler covering loop start up to the launch point;
--     once the loop has come round, that filler is stretched over the whole
--     region and replaces the launch item, so every pass starts the clip at the
--     loop start instead of restarting it halfway.

local r = reaper
local Launcher = {}
local H = {}
local UI = {}

local C = {
    proj_section = "TK_PROJECT_CLIPS_LAUNCHER",
    ext_section  = "TK_PROJECT_CLIPS_LAUNCHER",
    track_ext    = "P_EXT:TK_CLIP_LAUNCHER",
    folder_ext   = "P_EXT:TK_CLIP_LAUNCHER_FOLDER",
    min_lead     = 0.30,   -- floor; the working value is L.lead
    harvest_pad  = 0.10,
    voice_length = 300,
    voice_extend = 300,
    voice_margin = 60,
    max_rows     = 32,
    cell_w       = 138,
    cell_h       = 30,
    cell_h_big   = 64,
    scene_w      = 78,
    fade         = 0.005,
    follow_lead  = 1.20,
    -- Payload types a dragged file can arrive under, in the order they are tried.
    drop_types   = { "TK_WORKBENCH_MEDIA_FILE", "REAPER_MEDIAFOLDER", "text/uri-list",
                     "UTF8_STRING", "TEXT", "FILE_PATH", "FILES" },
}

local L = {
    loaded            = false,
    active            = false,
    rows              = 8,
    quantize          = 1,
    follow_enabled    = true,
    lead              = 0,   -- 0 = derive it from the media buffer
    lanes             = {},
    status            = "",
    roll_guard        = 0,
    last_heard        = nil,
    proj              = nil,
    -- Arrangement mute: silences the song on every track without touching the
    -- tracks themselves, so the launcher stays audible through its sends.
    recording         = false,
    restored_guids    = {},
    record_stop_at    = nil,
    captured          = {},
    arrangement_muted = false,
    -- Remembered so the launcher opens the way it was left, and starts muted
    -- unless told otherwise: jamming over a silent song is the common case.
    mute_song_default = true,
    global_mutes      = {},
    global_switch     = nil,
    big_cells         = true,
    tempo_sync        = true,
    file_prompt       = nil,
    chain_prompt      = nil,
    rename_prompt     = nil,
    colour_target     = nil,
    colour_request    = false,
    track_count       = -1,
    tidy_wanted       = false,
    drag_path         = nil,
    hover_cell        = nil,
    checked           = nil,
    cursor            = { lane = 1, row = 1 },
    keys              = nil,
    scenes            = {},
    scene_run         = nil,
    alt_down          = false,
    over_ui           = false,
    drag_out          = nil,
    rects             = {},
    rect_count        = 0,
}

-- What happens when a scene has played its rounds. One rule, used by both the
-- player and the writer, so a written arrangement can never disagree with what
-- you hear.
local FOLLOW_OPTIONS = {
    { key = "stop",   label = "Stop" },
    { key = "next",   label = "Next scene" },
    { key = "prev",   label = "Previous scene" },
    { key = "first",  label = "First scene" },
    { key = "self",   label = "Repeat this scene" },
    { key = "random", label = "Random scene" },
}

-- Retrigger grid for one-shots: a kick that is not a loop still has to land in
-- the rhythm, and tempo matching cannot help with a sample that has no tempo.
local REPEAT_OPTIONS = {
    { label = "Off",    qn = 0 },
    { label = "1/16",   qn = 0.25 },
    { label = "1/8",    qn = 0.5 },
    { label = "1/4",    qn = 1 },
    { label = "1/2",    qn = 2 },
    { label = "1 bar",  qn = 4 },
    { label = "2 bars", qn = 8 },
}

-- How long a clip must exist before the play cursor reaches it. REAPER reads
-- media ahead of the cursor, and an item created inside that window misses the
-- start of its own audio. Machine and buffer settings decide how much is
-- needed, so it is a setting rather than a constant. A launch that cannot make
-- the deadline waits for the next boundary instead of arriving damaged.
local LEAD_OPTIONS = {
    { label = "Auto",   value = 0 },
    { label = "0.25 s", value = 0.25 },
    { label = "0.5 s",  value = 0.5 },
    { label = "1 s",    value = 1.0 },
    { label = "1.5 s",  value = 1.5 },
    { label = "2 s",    value = 2.0 },
}

-- A fixed set rather than a full picker: twelve hues that stay apart from each
-- other on a tinted cell, and no nested colour popup inside a menu.
local CLIP_COLOURS = {
    0xE05252FF, 0xE0813FFF, 0xE0B03FFF, 0xD9D24AFF,
    0x8FC64AFF, 0x4FB870FF, 0x3FB8A8FF, 0x3FA6D9FF,
    0x4F79D9FF, 0x8A5FD9FF, 0xC25FD9FF, 0xD94F97FF,
}

local QUANTIZE_OPTIONS = {
    { label = "Off",    value = 0 },
    { label = "1/4",    value = 0.25 },
    { label = "1/2",    value = 0.5 },
    { label = "1 bar",  value = 1 },
    { label = "2 bars", value = 2 },
    { label = "4 bars", value = 4 },
    { label = "8 bars", value = 8 },
}

--------------------------------------------------------------------------------
-- small utilities
--------------------------------------------------------------------------------

function H.valid_item(item)
    return item ~= nil and r.ValidatePtr2(0, item, "MediaItem*")
end

function H.valid_track(track)
    return track ~= nil and r.ValidatePtr2(0, track, "MediaTrack*")
end

function H.item_from_guid(guid)
    if not guid or guid == "" then return nil end
    local item = r.BR_GetMediaItemByGUID(0, guid)
    if H.valid_item(item) then return item end
    return nil
end

function H.track_from_guid(guid)
    if not guid or guid == "" then return nil end
    local track = r.BR_GetMediaTrackByGUID(0, guid)
    if H.valid_track(track) then return track end
    return nil
end

function H.track_name(track, fallback)
    if not H.valid_track(track) then return fallback or "?" end
    local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    if name and name ~= "" then return name end
    local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
    return "Track " .. tostring(index)
end

function H.item_name(item, fallback)
    if not H.valid_item(item) then return fallback or "Clip" end
    local take = r.GetActiveTake(item)
    if not take then return fallback or "Clip" end
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if name and name ~= "" then return name end
    return fallback or "Clip"
end

function H.item_is_midi(item)
    if not H.valid_item(item) then return false end
    local take = r.GetActiveTake(item)
    return take ~= nil and r.TakeIsMIDI(take)
end

function H.native_color(native, fallback)
    if not native or native == 0 then return fallback end
    local red, green, blue = r.ColorFromNative(native)
    return (red << 24) | (green << 16) | (blue << 8) | 0xFF
end

function H.mix(first, second, amount)
    local inverse = 1 - amount
    local red = math.floor((((first >> 24) & 0xFF) * inverse) + (((second >> 24) & 0xFF) * amount))
    local green = math.floor((((first >> 16) & 0xFF) * inverse) + (((second >> 16) & 0xFF) * amount))
    local blue = math.floor((((first >> 8) & 0xFF) * inverse) + (((second >> 8) & 0xFF) * amount))
    return (red << 24) | (green << 16) | (blue << 8) | 0xFF
end

-- Centre text on a point using its real measured height, snapped to whole
-- pixels so glyphs stay crisp at any UI scale.
function H.text_centered(draw_list, center_x, center_y, color, text)
    local text_width, text_height = r.ImGui_CalcTextSize(UI.ctx, text)
    local x = math.floor(center_x - text_width * 0.5 + 0.5)
    local y = math.floor(center_y - text_height * 0.5 + 0.5)
    r.ImGui_DrawList_AddText(draw_list, x, y, color, text)
end

-- Near-black or near-white, whichever stands out against the given background.
-- A playing cell is already tinted with the track colour, so anything drawn in
-- that same colour disappears into it.
function H.readable_on(background)
    local red = (background >> 24) & 0xFF
    local green = (background >> 16) & 0xFF
    local blue = (background >> 8) & 0xFF
    if red * 0.299 + green * 0.587 + blue * 0.114 >= 140 then return 0x14171CFF end
    return 0xFFFFFFFF
end

function H.truncate(text, max_width)
    text = tostring(text or "")
    if max_width <= 0 then return "" end
    if r.ImGui_CalcTextSize(UI.ctx, text) <= max_width then return text end
    while #text > 1 and r.ImGui_CalcTextSize(UI.ctx, text .. "..") > max_width do
        text = text:sub(1, #text - 1)
    end
    return text .. ".."
end

--------------------------------------------------------------------------------
-- transport / timing
--------------------------------------------------------------------------------

-- Position the audio engine has already reached: everything scheduled must land
-- comfortably after this.
function H.schedule_pos()
    if (r.GetPlayState() & 1) ~= 1 then return nil end
    if r.GetPlayPosition2 then return r.GetPlayPosition2() end
    return r.GetPlayPosition()
end

-- Latency compensated position: what the user is actually hearing right now.
-- Used for cleanup so a voice is never removed while it is still audible.
function H.heard_pos()
    if (r.GetPlayState() & 1) ~= 1 then return nil end
    return r.GetPlayPosition()
end

function H.qn_per_bar(time)
    local num, denom = r.TimeMap_GetTimeSigAtTime(0, time)
    num = (num and num > 0) and num or 4
    denom = (denom and denom > 0) and denom or 4
    return num * (4 / denom)
end

-- Boundary on the project's own bar grid. With allow_now the boundary the given
-- time already sits on counts (used when the transport is stopped and there is
-- no scheduling deadline yet).
-- REAPER reads media a window ahead of the play cursor and does not come back
-- for anything that appears inside it, so the run-up a clip needs tracks that
-- window: measured at a 1200 ms media buffer, 1.5 s worked and 1.0 s did not.
function H.buffer_ms()
    if not r.SNM_GetIntConfigVar then return nil end
    local value = r.SNM_GetIntConfigVar("workbufmsex", -1)
    if not value or value <= 0 or value > 20000 then return nil end
    return value
end

function H.auto_lead()
    local buffer = H.buffer_ms()
    if not buffer then return 1.5 end
    return math.max(0.3, math.min(4.0, (buffer / 1000) + 0.3))
end

-- The media buffer is a global REAPER preference, not project data, so the
-- value it had before this script ever touched it is kept in global ext state
-- and can always be put back -- including from a later session.
function H.buffer_can_write()
    return r.SNM_SetIntConfigVar ~= nil and H.buffer_ms() ~= nil
end

function H.buffer_original()
    local stored = tonumber(r.GetExtState(C.ext_section, "media_buffer_original") or "")
    if stored and stored > 0 then return math.floor(stored) end
    return nil
end

function H.set_buffer_ms(value)
    if not H.buffer_can_write() then return false end
    value = math.floor(math.max(50, math.min(10000, value)))
    if not H.buffer_original() then
        local current = H.buffer_ms()
        if current then r.SetExtState(C.ext_section, "media_buffer_original", tostring(current), true) end
    end
    local ok = r.SNM_SetIntConfigVar("workbufmsex", value)
    L.status = ok and ("Media buffer set to " .. tostring(value) .. " ms") or "Could not change the media buffer"
    return ok
end

function H.restore_buffer()
    local original = H.buffer_original()
    if not original or not H.buffer_can_write() then return end
    if r.SNM_SetIntConfigVar("workbufmsex", original) then
        r.DeleteExtState(C.ext_section, "media_buffer_original", true)
        L.status = "Media buffer restored to " .. tostring(original) .. " ms"
    end
end

function H.lead()
    local value = L.lead or 0
    if value <= 0 then value = H.auto_lead() end
    return math.max(C.min_lead, value)
end

function H.boundary_after(from_time, allow_now)
    if L.quantize <= 0 then
        return allow_now and from_time or (from_time + H.lead())
    end
    local step = L.quantize * H.qn_per_bar(from_time)
    if step <= 0 then return from_time + H.lead() end
    local from_qn = r.TimeMap2_timeToQN(0, from_time)
    local index = math.floor(from_qn / step)
    if not allow_now then index = index + 1 end
    local time = r.TimeMap2_QNToTime(0, index * step)
    if allow_now then
        if time < from_time - 0.001 then
            time = r.TimeMap2_QNToTime(0, (index + 1) * step)
        end
        return time
    end
    local guard = 0
    while time - from_time < H.lead() and guard < 64 do
        index = index + 1
        time = r.TimeMap2_QNToTime(0, index * step)
        guard = guard + 1
    end
    return time
end

function H.song_bar(time)
    if not time then return nil end
    local per_bar = H.qn_per_bar(time)
    if per_bar <= 0 then return nil end
    return math.floor(r.TimeMap2_timeToQN(0, time) / per_bar) + 1
end

-- Every clip in the library sits stacked at time zero. Nothing addresses these
-- items by position -- slots are looked up by row, copies and sweeps go by guid
-- -- so spreading them out only made the hidden lane track as long as the row
-- count times the spacing, plus the tail of the last clip. Stacked, the track
-- reaches no further than the single longest clip on it.
function H.park_position()
    return 0
end

--------------------------------------------------------------------------------
-- items
--------------------------------------------------------------------------------

-- Chunk copy keeps take FX, stretch markers, pitch and rate intact. GUIDs are
-- regenerated so the copy is an independent item (and unpooled for MIDI).
function H.copy_item(item, track, position)
    if not H.valid_item(item) or not H.valid_track(track) then return nil end
    local ok, chunk = r.GetItemStateChunk(item, "", false)
    if not ok or not chunk then return nil end
    chunk = chunk:gsub("(\n%s*I?GUID )%b{}", function(prefix) return prefix .. r.genGuid("") end)
    local copy = r.AddMediaItemToTrack(track)
    if not copy then return nil end
    r.SetItemStateChunk(copy, chunk, false)
    r.SetMediaItemInfo_Value(copy, "D_POSITION", position)
    r.SetMediaItemInfo_Value(copy, "C_LOCK", 0)
    -- The chunk carries the selected state of the item it came from. Left as is,
    -- every clip and every voice would join the user's item selection, and the
    -- next "add selected item(s)" would pick up our own copies as well.
    r.SetMediaItemSelected(copy, false)
    return copy
end

function H.delete_item(item)
    if not H.valid_item(item) then return end
    local track = r.GetMediaItemTrack(item)
    if H.valid_track(track) then r.DeleteTrackMediaItem(track, item) end
end

function H.trim_to(item, time)
    if not H.valid_item(item) then return false end
    local position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
    local length = time - position
    if length <= 0.0001 then return false end
    r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", C.fade)
    r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", -1)
    if r.UpdateItemInProject then r.UpdateItemInProject(item) end
    return true
end

--------------------------------------------------------------------------------
-- lanes
--------------------------------------------------------------------------------

function H.lane_track(lane)
    return H.track_from_guid(lane.lane_guid)
end

function H.target_track(lane)
    return H.track_from_guid(lane.track_guid)
end

function H.lane_color(lane)
    local track = H.target_track(lane)
    if not track then return UI.colors.accent end
    return H.native_color(r.GetTrackColor(track), UI.colors.accent)
end

-- A lane whose target track is gone can never sound again: REAPER removed the
-- send with the track. It is not removed automatically, because undoing a track
-- deletion brings the track back under the same guid and the lane simply works
-- again -- destroying it here would throw the clips away for good.
function H.lane_orphaned(lane)
    return H.target_track(lane) == nil
end

function H.orphan_count()
    local count = 0
    for _, lane in ipairs(L.lanes) do
        if H.lane_orphaned(lane) then count = count + 1 end
    end
    return count
end

function H.remove_orphan_lanes()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local removed = 0
    for index = #L.lanes, 1, -1 do
        if H.lane_orphaned(L.lanes[index]) then
            H.remove_lane(index)
            removed = removed + 1
        end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Remove dead launcher lanes", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    H.save()
    L.status = removed == 1 and "Removed 1 dead lane" or ("Removed " .. tostring(removed) .. " dead lanes")
end

function H.lane_label(lane)
    local track = H.target_track(lane)
    if not track then return lane.name .. " (missing)" end
    return H.track_name(track, lane.name)
end

function H.create_lane_track(target)
    local index = r.CountTracks(0)
    r.InsertTrackAtIndex(index, false)
    local track = r.GetTrack(0, index)
    if not track then return nil end
    r.GetSetMediaTrackInfo_String(track, "P_NAME", "TK Launcher: " .. H.track_name(target, "Track"), true)
    r.GetSetMediaTrackInfo_String(track, C.track_ext, "1", true)
    r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", H.lanes_visible() and 1 or 0)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
    r.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
    local send = r.CreateTrackSend(track, target)
    if send and send >= 0 then
        r.SetTrackSendInfo_Value(track, 0, send, "I_MIDIFLAGS", 0)
        r.SetTrackSendInfo_Value(track, 0, send, "I_SRCCHAN", 0)
    end
    return track
end

function H.is_folder_track(track)
    if not H.valid_track(track) then return false end
    local ok, value = r.GetSetMediaTrackInfo_String(track, C.folder_ext, "", false)
    return ok and value == "1"
end

function H.folder_track()
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if H.is_folder_track(track) then return track, index end
    end
    return nil
end

-- One parent for the whole block, so the lanes read as a single group instead of
-- a row of loose tracks whenever they are made visible. It carries no audio: the
-- lanes have their parent send off and feed their targets directly.
function H.ensure_folder()
    if #L.lanes == 0 then return nil end
    local existing = H.folder_track()
    if existing then return existing end
    local at = nil
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if H.is_lane_track(track) and not H.is_folder_track(track) then at = index break end
    end
    if not at then return nil end
    r.InsertTrackAtIndex(at, false)
    local folder = r.GetTrack(0, at)
    if not folder then return nil end
    r.GetSetMediaTrackInfo_String(folder, "P_NAME", "TK LAUNCHER", true)
    r.GetSetMediaTrackInfo_String(folder, C.track_ext, "1", true)
    r.GetSetMediaTrackInfo_String(folder, C.folder_ext, "1", true)
    r.SetMediaTrackInfo_Value(folder, "B_SHOWINTCP", H.lanes_visible() and 1 or 0)
    r.SetMediaTrackInfo_Value(folder, "B_SHOWINMIXER", 0)
    r.SetMediaTrackInfo_Value(folder, "B_MAINSEND", 0)
    return folder
end

-- The folder only ever claims depth while a lane directly below it is closed off
-- in the same pass, so a miscount can never swallow a user track.
function H.fix_folder_depths()
    local folder, folder_index = H.folder_track()
    if not folder then return end
    local last_lane = nil
    for index = folder_index + 1, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if H.is_lane_track(track) and not H.is_folder_track(track) then
            r.SetMediaTrackInfo_Value(track, "I_FOLDERDEPTH", 0)
            last_lane = track
        else
            break
        end
    end
    if last_lane then
        r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 1)
        r.SetMediaTrackInfo_Value(last_lane, "I_FOLDERDEPTH", -1)
    else
        r.SetMediaTrackInfo_Value(folder, "I_FOLDERDEPTH", 0)
    end
end

-- Read the state off the tracks themselves rather than storing it, so the button
-- still tells the truth after the user toggles visibility in the Track Manager.
function H.lanes_visible()
    local folder = H.folder_track()
    if folder then return (r.GetMediaTrackInfo_Value(folder, "B_SHOWINTCP") or 0) > 0.5 end
    for _, lane in ipairs(L.lanes) do
        local track = H.lane_track(lane)
        if track then return (r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") or 0) > 0.5 end
    end
    return false
end

function H.set_lanes_visible(visible)
    local value = visible and 1 or 0
    r.PreventUIRefresh(1)
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if H.is_lane_track(track) then
            r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", value)
            if H.is_folder_track(track) and visible then
                r.SetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT", 0)
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    L.status = visible and "Launcher tracks shown" or "Launcher tracks hidden"
end

function H.prune_folder()
    if #L.lanes > 0 then return end
    local folder = H.folder_track()
    if folder then r.DeleteTrack(folder) end
end

-- REAPER appends new tracks at the end, so a track the user adds lands after the
-- hidden lane tracks: their numbering jumps a block and the lanes end up sitting
-- in the middle of the project. Keeping the lanes last is what stops that, and a
-- folder would not help -- its children keep their own track numbers too.
function H.lanes_need_tidy()
    local seen_lane = false
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if H.is_lane_track(track) then
            seen_lane = true
        elseif seen_lane then
            return true
        end
    end
    return false
end

function H.tidy_lane_tracks()
    if not r.ReorderSelectedTracks then return end
    if not H.lanes_need_tidy() then
        if H.ensure_folder() then H.fix_folder_depths() end
        L.tidy_wanted = false
        return
    end
    -- Never reshuffle the project while clips are sounding; retry once idle.
    for _, lane in ipairs(L.lanes) do
        if lane.current or lane.pending then
            L.tidy_wanted = true
            return
        end
    end
    local selected = {}
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if r.IsTrackSelected(track) then selected[#selected + 1] = track end
    end
    r.PreventUIRefresh(1)
    r.Main_OnCommand(40297, 0)
    local any = false
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if H.is_lane_track(track) then
            r.SetTrackSelected(track, true)
            any = true
        end
    end
    if any then r.ReorderSelectedTracks(r.CountTracks(0), 0) end
    r.Main_OnCommand(40297, 0)
    for _, track in ipairs(selected) do
        if H.valid_track(track) then r.SetTrackSelected(track, true) end
    end
    H.ensure_folder()
    H.fix_folder_depths()
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    L.tidy_wanted = false
    L.track_count = r.CountTracks(0)
end

function H.add_lane(target)
    if not H.valid_track(target) then return nil end
    for _, lane in ipairs(L.lanes) do
        if H.target_track(lane) == target then
            L.status = "That track already has a lane"
            return nil
        end
    end
    local lane_track = H.create_lane_track(target)
    if not lane_track then return nil end
    local lane = {
        name = H.track_name(target, "Track"),
        track_guid = r.GetTrackGUID(target),
        lane_guid = r.GetTrackGUID(lane_track),
        slots = {},
        owner = "arrangement",
    }
    L.lanes[#L.lanes + 1] = lane
    return lane
end

function H.remove_lane(lane_index)
    local lane = L.lanes[lane_index]
    if not lane then return end
    H.release_now(lane)
    H.harvest_lane(lane, true)
    local track = H.lane_track(lane)
    if track then r.DeleteTrack(track) end
    table.remove(L.lanes, lane_index)
    H.prune_folder()
    H.fix_folder_depths()
end

--------------------------------------------------------------------------------
-- slots
--------------------------------------------------------------------------------

function H.cell_height()
    return UI.rounded(L.big_cells and C.cell_h_big or C.cell_h)
end

-- The preview drawers borrowed from the Items view work on a card entry. The
-- library item never changes once assigned, so its guid doubles as cache key.
function H.slot_entry(slot, color)
    local entry = slot.entry
    if not entry then
        entry = { guid = slot.guid, cache_key = slot.guid .. "|launcher", has_track_color = true }
        slot.entry = entry
    end
    entry.is_midi = slot.is_midi
    entry.track_color = color
    return entry
end

-- A slot whose clip has gone -- undone, or deleted by hand -- is marked rather
-- than removed. Removing it would lose the slot for good the moment the user
-- redoes, and the clip would come back to a grid that had forgotten it. Checked
-- on a timer, because resolving every clip on every frame is not free.
function H.refresh_missing(now)
    if L.checked and now - L.checked < 0.5 then return end
    L.checked = now
    for _, lane in ipairs(L.lanes) do
        for _, slot in ipairs(lane.slots) do
            slot.missing = H.item_from_guid(slot.guid) == nil
        end
    end
end

function H.slot(lane, row)
    for _, entry in ipairs(lane.slots) do
        if entry.row == row then return entry end
    end
    return nil
end

function H.clear_slot(lane, row)
    for index = #lane.slots, 1, -1 do
        local entry = lane.slots[index]
        if entry.row == row then
            H.delete_item(H.item_from_guid(entry.guid))
            table.remove(lane.slots, index)
        end
    end
    if lane.current and lane.current.row == row then
        H.kill_voice(lane.current)
        lane.current = nil
    end
    if lane.pending and lane.pending.row == row then
        H.kill_voice(lane.pending)
        lane.pending = nil
    end
    if not lane.hold and not lane.current and not lane.pending then H.release_now(lane) end
end

-- Source length expressed in timeline seconds, so a MIDI source (measured in
-- quarter notes) and an audio source can be compared with the item the same way.
function H.source_seconds(item, take)
    local source = r.GetMediaItemTake_Source(take)
    if not source then return nil end
    local length, length_is_qn = r.GetMediaSourceLength(source)
    if not length or length <= 0 then return nil end
    if length_is_qn then
        local position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
        local qn = r.TimeMap2_timeToQN(0, position)
        length = r.TimeMap2_QNToTime(0, qn + length) - position
    end
    local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
    if rate <= 0 then rate = 1 end
    return length / rate
end

-- How often the clip actually comes round. A loop source repeats every source
-- length, so an item stretched out to four bars from a one bar loop repeats
-- every bar, not every four. The item length says nothing about that.
function H.loop_period(item, take)
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    if length <= 0 then return nil end
    local source_length = H.source_seconds(item, take)
    if source_length and source_length > 0 and source_length < length - 0.0001 then
        return source_length
    end
    return length
end

-- Read from the library item every time rather than trusted from when the clip
-- was added. A clip whose timebase follows the tempo changes duration when the
-- project tempo changes, and a stored number of seconds silently goes stale.
-- The stored value is kept as a fallback and refreshed here.
function H.slot_lengths(slot)
    local item = H.item_from_guid(slot.guid)
    local take = item and r.GetActiveTake(item) or nil
    if item and take then
        local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
        local period = H.loop_period(item, take)
        if length > 0 then
            slot.length = length
            slot.loop_len = period or length
            return length, slot.loop_len
        end
    end
    return slot.length or 0, slot.loop_len or slot.length or 0
end

function H.slot_loop(slot)
    return select(2, H.slot_lengths(slot))
end

function H.is_trimmed(item, take)
    local source_length = H.source_seconds(item, take)
    if not source_length then return false end
    local offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    return offset > 0.0001 or length < source_length - 0.0001
end

-- MIDI has no section source, so the content is rendered into a new source. For
-- in-project MIDI that writes nothing to disk. It replaces the item, so the
-- caller must use the returned one, and it runs through the item selection,
-- which is saved and put back.
-- Always run, never conditional. Whether an in-project MIDI item is trimmed
-- cannot be told apart from its source length: REAPER reports that length as
-- the item's own, so the test always said no and nothing ever happened.
-- Rendering the item to a fresh source is a no-op when it was not trimmed, so
-- there is nothing to detect in the first place.
function H.trim_midi_source(item)
    if not H.valid_item(item) then return item, false end
    local selected = {}
    for index = 0, r.CountSelectedMediaItems(0) - 1 do
        selected[#selected + 1] = r.GetSelectedMediaItem(0, index)
    end
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    local muted = r.GetMediaItemInfo_Value(item, "B_MUTE") or 0
    r.SetMediaItemInfo_Value(item, "B_MUTE", 0)
    -- Loop off while rendering, so what comes out is the span the item shows
    -- and not a repeat of it.
    local looped = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") or 0
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
    -- Glue is a REAPER action, and an action will not touch an item on a track
    -- it cannot see. The lane track is hidden by design, so it is shown for the
    -- length of the render and hidden again straight after.
    local track = r.GetMediaItemTrack(item)
    local shown = track and (r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") or 0) or 1
    if track and shown < 0.5 then
        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
        r.TrackList_AdjustWindows(false)
    end
    -- Every clip in a lane is stacked on the same spot, and glue takes in what
    -- it overlaps. The item is moved to empty ground first, so the render can
    -- only ever contain the one clip.
    local home = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
    local clear = home
    if track then
        for index = 0, r.CountTrackMediaItems(track) - 1 do
            local other = r.GetTrackMediaItem(track, index)
            local finish = (r.GetMediaItemInfo_Value(other, "D_POSITION") or 0)
                + (r.GetMediaItemInfo_Value(other, "D_LENGTH") or 0)
            if finish > clear then clear = finish end
        end
        clear = clear + 10
        r.SetMediaItemInfo_Value(item, "D_POSITION", clear)
    end
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    r.Main_OnCommand(40362, 0)
    local glued = r.GetSelectedMediaItem(0, 0)
    if not H.valid_item(glued) then glued = item end
    r.SelectAllMediaItems(0, false)
    for _, previous in ipairs(selected) do
        if H.valid_item(previous) then r.SetMediaItemSelected(previous, true) end
    end
    if track and shown < 0.5 and H.valid_track(track) then
        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
        r.TrackList_AdjustWindows(false)
    end
    if not H.valid_item(glued) then
        if H.valid_item(item) then r.SetMediaItemInfo_Value(item, "D_POSITION", home) end
        return item, false
    end
    r.SetMediaItemInfo_Value(glued, "D_POSITION", home)
    r.SetMediaItemInfo_Value(glued, "B_MUTE", muted)
    r.SetMediaItemInfo_Value(glued, "B_LOOPSRC", looped)
    r.SetMediaItemInfo_Value(glued, "D_LENGTH", length)
    -- A different item means the render happened; that is as much as can
    -- honestly be checked here.
    return glued, glued ~= item
end

-- An item trimmed shorter than its source is a window onto that source. REAPER's
-- loop source repeats the whole source, not the window, so a clip trimmed to one
-- bar of a two bar file loops two bars. Wrapping the take in a section source
-- makes that window the whole clip, which is what the arrange was showing.
function H.apply_section(item)
    if not r.CF_PCM_Source_SetSectionInfo or not r.PCM_Source_CreateFromType then return false end
    local take = r.GetActiveTake(item)
    if not take or r.TakeIsMIDI(take) then return false end
    local source = r.GetMediaItemTake_Source(take)
    if not source then return false end
    local source_length, length_is_qn = r.GetMediaSourceLength(source)
    if length_is_qn or not source_length or source_length <= 0 then return false end
    local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
    if rate <= 0 then rate = 1 end
    local offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    -- Section bounds are measured in source time, so the play rate counts.
    local length = (r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0) * rate
    if length <= 0 then return false end
    if not H.is_trimmed(item, take) then return false end
    -- The section needs its own copy of the source. There is no duplicate call in
    -- ReaScript, so it is rebuilt from the file the source points at; a source
    -- that is not a plain file (already a section, or reversed) is left alone.
    local kind = r.GetMediaSourceType(source, "") or ""
    if kind == "SECTION" or kind == "" then return false end
    local path = r.GetMediaSourceFileName(source, "")
    if not path or path == "" then return false end
    local copy = r.PCM_Source_CreateFromFile(path)
    if not copy then return false end
    local section = r.PCM_Source_CreateFromType("SECTION")
    if not section then
        pcall(r.PCM_Source_Destroy, copy)
        return false
    end
    local ok = pcall(r.CF_PCM_Source_SetSectionInfo, section, copy, offset, length, false)
    if not ok then
        pcall(r.PCM_Source_Destroy, section)
        pcall(r.PCM_Source_Destroy, copy)
        return false
    end
    r.SetMediaItemTake_Source(take, section)
    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
    return true
end

function H.assign_slot(lane, row, source_item)
    local lane_track = H.lane_track(lane)
    if not lane_track or not H.valid_item(source_item) then return false end
    H.clear_slot(lane, row)
    local library = H.copy_item(source_item, lane_track, H.park_position())
    if not library then return false end
    local length = r.GetMediaItemInfo_Value(library, "D_LENGTH") or 0
    -- Make the clip loop what the arrange showed rather than the whole source.
    local trimmed = false
    local midi_trim_failed = false
    local take = r.GetActiveTake(library)
    if take and r.TakeIsMIDI(take) then
        library, trimmed = H.trim_midi_source(library)
        midi_trim_failed = not trimmed
    else
        trimmed = H.apply_section(library)
    end
    if not H.valid_item(library) then return false end
    r.SetMediaItemInfo_Value(library, "D_LENGTH", length)
    r.SetMediaItemInfo_Value(library, "B_MUTE", 1)
    r.SetMediaItemInfo_Value(library, "B_LOOPSRC", 1)
    -- Cleared here as well: a voice is a chunk copy of this item, so a fade left
    -- on the library would travel into every clip made from it.
    r.SetMediaItemInfo_Value(library, "D_FADEINLEN", 0)
    r.SetMediaItemInfo_Value(library, "D_FADEINLEN_AUTO", -1)
    lane.slots[#lane.slots + 1] = {
        row = row,
        guid = r.BR_GetMediaItemGUID(library),
        name = H.item_name(source_item, "Clip"),
        is_midi = H.item_is_midi(library),
        length = length,
        loop = true,
        loop_len = H.loop_period(library, r.GetActiveTake(library)),
        sectioned = trimmed or nil,
        trim_failed = midi_trim_failed or nil,
    }
    return true
end

--------------------------------------------------------------------------------
-- taking clips in from outside
--------------------------------------------------------------------------------

-- Same metadata keys the TK media browsers read, so a file dropped here lands at
-- the same rate it would when dropped straight into the arrange. The file name
-- is a second chance: loop packs often carry the tempo only in the name.
function H.file_bpm(source, path)
    if r.GetMediaFileMetadata then
        local keys = { "ACID:tempo", "ID3:TBPM", "VORBIS:BPM", "VORBIS:TEMPO", "XMP:dm/tempo" }
        for _, key in ipairs(keys) do
            local ok, value = r.GetMediaFileMetadata(source, key)
            if ok and ok ~= 0 and value and value ~= "" then
                local bpm = tonumber((tostring(value):gsub(",", "."):match("[%d%.]+")))
                if bpm and bpm > 0 then return bpm end
            end
        end
    end
    local name = ((path or ""):match("([^/\\]+)$") or ""):lower()
    local bpm = tonumber(name:match("(%d+%.?%d*)%s*bpm")) or tonumber(name:match("bpm[%s_%-]*(%d+%.?%d*)"))
    if bpm and bpm >= 40 and bpm <= 300 then return bpm end
    return nil
end

-- Returns the playrate that puts this file at the project tempo, or nil.
function H.tempo_match_rate(source, path)
    if not L.tempo_sync then return nil end
    local file_bpm = H.file_bpm(source, path)
    if not file_bpm then return nil end
    local project_bpm = r.Master_GetTempo and r.Master_GetTempo() or nil
    if not project_bpm or project_bpm <= 0 then return nil end
    local rate = project_bpm / file_bpm
    if rate < 0.05 or rate > 20 or math.abs(rate - 1) < 0.0005 then return nil end
    return rate
end

-- Build a library item straight from a file. Deliberately not InsertMedia: that
-- one works off the edit cursor and the track selection, both of which belong to
-- the user while they are jamming.
function H.assign_path(lane, row, path)
    local lane_track = H.lane_track(lane)
    if not lane_track or not path or path == "" then return false end
    local source = r.PCM_Source_CreateFromFile(path)
    if not source then return false end
    local kind = r.GetMediaSourceType(source, "") or ""
    if kind == "" or kind == "EMPTY" then
        r.PCM_Source_Destroy(source)
        return false
    end
    H.clear_slot(lane, row)
    local position = H.park_position()
    local item = r.AddMediaItemToTrack(lane_track)
    if not item then
        r.PCM_Source_Destroy(source)
        return false
    end
    local take = r.AddTakeToMediaItem(item)
    r.SetMediaItemTake_Source(take, source)
    r.SetMediaItemInfo_Value(item, "D_POSITION", position)
    local length, length_is_qn = r.GetMediaSourceLength(source)
    local is_midi = kind:find("MIDI") ~= nil
    if length_is_qn then
        local qn = r.TimeMap2_timeToQN(0, position)
        length = r.TimeMap2_QNToTime(0, qn + length) - position
    end
    -- MIDI already follows the project tempo; only audio needs stretching.
    local matched_bpm = nil
    if not is_midi then
        local rate = H.tempo_match_rate(source, path)
        if rate then
            r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
            r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
            length = (length or 0) / rate
            matched_bpm = true
        end
    end
    length = math.max(0.05, length or 0.05)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
    r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
    local name = path:match("([^/\\]+)$") or path
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
    lane.slots[#lane.slots + 1] = {
        row = row,
        guid = r.BR_GetMediaItemGUID(item),
        name = name,
        is_midi = is_midi,
        length = length,
        loop = true,
        loop_len = length,
        tempo_matched = matched_bpm and true or nil,
    }
    return true
end

function H.assign_paths(lane, row, paths)
    if not paths or #paths == 0 then return end
    -- One drop can arrive twice: as an ImGui payload and again through the
    -- TK_DRAG protocol. Ignore an identical repeat on the same cell.
    local stamp = tostring(lane) .. "/" .. tostring(row) .. "/" .. table.concat(paths, "|")
    local now = r.time_precise()
    if L.last_drop == stamp and (now - (L.last_drop_at or 0)) < 0.5 then return end
    L.last_drop, L.last_drop_at = stamp, now
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local added = 0
    for index, path in ipairs(paths) do
        local target_row = row + index - 1
        if target_row > L.rows then break end
        if H.assign_path(lane, target_row, path) then added = added + 1 end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Add clips to launcher", -1)
    r.UpdateArrange()
    if added == 0 then
        L.status = "Could not read that file"
    else
        L.status = added == 1 and "Clip added to launcher" or (tostring(added) .. " clips added to launcher")
        H.save()
    end
end

function H.find_slot_by_guid(guid)
    for _, lane in ipairs(L.lanes) do
        for _, slot in ipairs(lane.slots) do
            if slot.guid == guid then return lane, slot end
        end
    end
    return nil
end

-- Moving a clip between slots is almost pure bookkeeping: every library item is
-- parked at the same spot, so only the row changes, plus the track itself when
-- the clip lands in another lane.
function H.move_slot(from_lane, from_slot, to_lane, to_row, copy)
    if not from_lane or not from_slot or not to_lane then return end
    if from_lane == to_lane and from_slot.row == to_row and not copy then return end
    local item = H.item_from_guid(from_slot.guid)
    if not item then return end
    local lane_track = H.lane_track(to_lane)
    if not lane_track then return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    -- A clip that is sounding cannot quietly change place underneath the engine.
    if (from_lane.current and from_lane.current.row == from_slot.row)
        or (from_lane.pending and from_lane.pending.row == from_slot.row) then
        H.harvest_lane(from_lane, true)
    end
    H.clear_slot(to_lane, to_row)
    if copy then
        local duplicate = H.copy_item(item, lane_track, H.park_position())
        if duplicate then
            r.SetMediaItemInfo_Value(duplicate, "B_MUTE", 1)
            to_lane.slots[#to_lane.slots + 1] = {
                row = to_row,
                guid = r.BR_GetMediaItemGUID(duplicate),
                name = from_slot.name,
                is_midi = from_slot.is_midi,
                length = from_slot.length,
                loop = from_slot.loop,
                tempo_matched = from_slot.tempo_matched,
            }
        end
    else
        if to_lane ~= from_lane then
            r.MoveMediaItemToTrack(item, lane_track)
            for index = #from_lane.slots, 1, -1 do
                if from_lane.slots[index] == from_slot then table.remove(from_lane.slots, index) end
            end
            to_lane.slots[#to_lane.slots + 1] = from_slot
        end
        from_slot.row = to_row
        from_slot.entry = nil
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock(copy and "Copy launcher clip" or "Move launcher clip", -1)
    r.UpdateArrange()
    H.save()
    L.status = copy and "Clip copied" or "Clip moved"
end

-- Turns whatever a drop carried into a list of paths that exist on disk. A text
-- payload can be newline or NUL separated, quoted, or a file:// URI.
function H.payload_paths(payload)
    local paths = {}
    local text = tostring(payload or "")
    if text == "" then return paths end
    text = text:gsub("%z", "\n"):gsub("\r", "")
    for line in text:gmatch("[^\n]+") do
        local candidate = line:match("^%s*(.-)%s*$") or ""
        candidate = candidate:gsub('^"', ""):gsub('"$', ""):gsub("^<", ""):gsub(">$", "")
        if candidate:lower():match("^file://") then
            candidate = candidate:gsub("^%a+://", ""):gsub("^localhost/", "")
            candidate = candidate:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
            candidate = candidate:gsub("^/(%a:)", "%1")
        end
        if candidate ~= "" and r.file_exists(candidate) then paths[#paths + 1] = candidate end
    end
    return paths
end

-- A file drop from outside. REAPER's own Media Explorer does not deliver the
-- plain file payload the way Windows Explorer does, so the named types are asked
-- for as well, and if it is none of those, GetDragDropPayload reports whatever
-- type is actually in flight and that one is accepted. This is the sweep TK Kit
-- Maker uses, which is why the Media Explorer has always worked there.
function H.accept_file_drop(lane, row)
    if not r.ImGui_BeginDragDropTarget then return end
    if not r.ImGui_BeginDragDropTarget(UI.ctx) then return end
    if r.ImGui_AcceptDragDropPayload then
        local ok, payload = r.ImGui_AcceptDragDropPayload(UI.ctx, "TK_LAUNCHER_CLIP")
        if ok and payload and payload ~= "" then
            local from_lane, from_slot = H.find_slot_by_guid(payload)
            if from_lane and from_slot then
                local copy = r.JS_Mouse_GetState and (r.JS_Mouse_GetState(4) & 4) == 4
                H.move_slot(from_lane, from_slot, lane, row, copy)
            end
        end
    end
    local paths = {}
    if r.ImGui_AcceptDragDropPayloadFiles and r.ImGui_GetDragDropPayloadFile then
        -- Two returns: the flag first, then the count. Reading the flag as the
        -- count is why this route silently never fired.
        local accepted, count = r.ImGui_AcceptDragDropPayloadFiles(UI.ctx)
        if accepted and tonumber(count) then
            for index = 0, tonumber(count) - 1 do
                local got, filename = r.ImGui_GetDragDropPayloadFile(UI.ctx, index)
                if got and type(filename) == "string" and filename ~= "" then
                    paths[#paths + 1] = filename
                end
            end
        end
    end
    if #paths == 0 and r.ImGui_AcceptDragDropPayload then
        for _, payload_type in ipairs(C.drop_types) do
            local ok, payload = r.ImGui_AcceptDragDropPayload(UI.ctx, payload_type)
            if ok then
                paths = H.payload_paths(payload)
                if #paths > 0 then break end
            end
        end
    end
    if #paths == 0 and r.ImGui_GetDragDropPayload and r.ImGui_AcceptDragDropPayload then
        local ok, payload_type = r.ImGui_GetDragDropPayload(UI.ctx)
        if ok and payload_type and payload_type ~= "" then
            local got, payload = r.ImGui_AcceptDragDropPayload(UI.ctx, payload_type)
            if got then paths = H.payload_paths(payload) end
        end
    end
    r.ImGui_EndDragDropTarget(UI.ctx)
    if #paths > 0 then H.assign_paths(lane, row, paths) end
end

-- TK drag protocol: TK Media Browser and the Workbench media browser advertise
-- the file they are dragging in ExtState and refresh a heartbeat every frame.
-- No OS drag involved, so this keeps working while this window is docked.
function H.tk_drag_path()
    local path = r.GetExtState("TK_DRAG", "path")
    if not path or path == "" then return nil end
    local heartbeat = tonumber(r.GetExtState("TK_DRAG", "heartbeat") or "")
    if not heartbeat or (r.time_precise() - heartbeat) > 0.5 then return nil end
    return path
end

-- Fallback for the release hit test, in case ImGui reports no hover for a drag
-- that started in another script's window.
function H.cell_at_mouse()
    if not r.GetMousePosition then return nil end
    local mouse_x, mouse_y = r.GetMousePosition()
    if not mouse_x then return nil end
    for index = 1, (L.rect_count or 0) do
        local rect = L.rects[index]
        if mouse_x >= rect.x1 and mouse_x <= rect.x2 and mouse_y >= rect.y1 and mouse_y <= rect.y2 then
            return rect.lane, rect.row
        end
    end
    return nil
end

function H.update_external_drag()
    local path = H.tk_drag_path()
    if path then
        L.drag_path = path
        return
    end
    if not L.drag_path then return end
    -- The sender clears its ExtState on release, so this is the drop.
    local dropped = L.drag_path
    L.drag_path = nil
    local lane, row = nil, nil
    if L.hover_cell then
        lane, row = L.hover_cell.lane, L.hover_cell.row
    else
        lane, row = H.cell_at_mouse()
    end
    if lane and row then H.assign_paths(lane, row, { dropped }) end
end

-- Only ever queued here: GetUserFileNameForRead is a blocking modal dialog, and
-- opening one from inside a menu leaves the ImGui frame half built for as long
-- as the dialog is up. It runs from update(), before the frame starts.
function H.pick_file(lane, row)
    if not r.GetUserFileNameForRead then return end
    L.file_prompt = { lane = lane, row = row }
end

function H.run_file_prompt()
    local prompt = L.file_prompt
    if not prompt then return end
    L.file_prompt = nil
    local lane_still_there = false
    for _, lane in ipairs(L.lanes) do
        if lane == prompt.lane then lane_still_there = true break end
    end
    if not lane_still_there then return end
    local ok, path = r.GetUserFileNameForRead("", "Add clip to launcher", "")
    if ok and path and path ~= "" then H.assign_paths(prompt.lane, prompt.row, { path }) end
end

--------------------------------------------------------------------------------
-- scenes taken from the arrangement
--------------------------------------------------------------------------------

-- Length of the longest clip in a row, in whole bars rounded up: the span a
-- scene needs before every clip in it has come round at least once. Shorter
-- clips loop, so they fill that span by themselves.
function H.scene_bars(row)
    local longest = 0
    for _, lane in ipairs(L.lanes) do
        local slot = H.slot(lane, row)
        local length = slot and H.slot_loop(slot) or 0
        if length > longest then longest = length end
    end
    if longest <= 0 then return nil end
    local per_bar = H.qn_per_bar(0)
    if per_bar <= 0 then return nil end
    local zero = r.TimeMap2_timeToQN(0, 0)
    local bars = (r.TimeMap2_timeToQN(0, longest) - zero) / per_bar
    return math.max(1, math.ceil(bars - 0.01))
end

function H.scene_filled(row)
    for _, lane in ipairs(L.lanes) do
        if H.slot(lane, row) then return true end
    end
    return false
end

function H.scene_settings(row)
    L.scenes = L.scenes or {}
    local entry = L.scenes[row]
    if not entry then
        entry = { follow = "stop", plays = 1 }
        L.scenes[row] = entry
    end
    return entry
end

function H.scene_plays(row)
    local plays = math.floor(H.scene_settings(row).plays or 1)
    if plays < 1 then plays = 1 end
    return plays
end

function H.filled_rows()
    local rows = {}
    for row = 1, L.rows do
        if H.scene_filled(row) then rows[#rows + 1] = row end
    end
    return rows
end

-- The single source of truth for what follows a scene. Empty rows are skipped:
-- a gap in the grid is not a section of the song.
function H.next_scene_after(row)
    local follow = H.scene_settings(row).follow or "stop"
    if follow == "stop" then return nil end
    if follow == "self" then return H.scene_filled(row) and row or nil end
    local rows = H.filled_rows()
    if #rows == 0 then return nil end
    if follow == "first" then return rows[1] end
    if follow == "random" then
        if #rows == 1 then return rows[1] end
        local pick = rows[math.random(#rows)]
        local guard = 0
        while pick == row and guard < 8 do
            pick = rows[math.random(#rows)]
            guard = guard + 1
        end
        return pick
    end
    local index = nil
    for position, value in ipairs(rows) do
        if value == row then index = position break end
    end
    if not index then return rows[1] end
    if follow == "next" then return rows[(index % #rows) + 1] end
    if follow == "prev" then return rows[((index - 2) % #rows) + 1] end
    return nil
end

-- The same rule as for scenes, but inside one lane: what plays next in this
-- column. Empty rows are skipped, so a column with clips on rows 1, 4 and 5
-- cycles through those three.
function H.lane_rows(lane)
    local rows = {}
    for row = 1, L.rows do
        if H.slot(lane, row) then rows[#rows + 1] = row end
    end
    return rows
end

function H.next_slot_after(lane, row)
    local slot = H.slot(lane, row)
    local follow = slot and slot.follow or "stop"
    if follow == "stop" then return nil end
    if follow == "self" then return row end
    local rows = H.lane_rows(lane)
    if #rows == 0 then return nil end
    if follow == "first" then return rows[1] end
    if follow == "random" then
        if #rows == 1 then return rows[1] end
        local pick, guard = rows[math.random(#rows)], 0
        while pick == row and guard < 8 do
            pick = rows[math.random(#rows)]
            guard = guard + 1
        end
        return pick
    end
    local index = nil
    for position, value in ipairs(rows) do
        if value == row then index = position break end
    end
    if not index then return rows[1] end
    if follow == "next" then return rows[(index % #rows) + 1] end
    if follow == "prev" then return rows[((index - 2) % #rows) + 1] end
    return nil
end

-- How long one round of a clip lasts, which is not the same thing for all three
-- kinds: a loop comes round every loop length, a retriggering one-shot every
-- bar because that is what its pattern spans, and a plain one-shot once.
function H.clip_cycle(slot)
    if slot.loop then return H.slot_loop(slot) end
    if slot.repeat_qn and slot.repeat_qn > 0 then
        return H.bars_to_time(0, 1)
    end
    return select(1, H.slot_lengths(slot))
end

function H.clip_plays(slot)
    local plays = math.floor(slot.plays or 1)
    if plays < 1 then plays = 1 end
    return plays
end

function H.begin_clip_run(lane, voice)
    local slot = H.slot(lane, voice.row)
    if not slot or (slot.follow or "stop") == "stop" then
        lane.run = nil
        return
    end
    local cycle = H.clip_cycle(slot)
    if not cycle or cycle <= 0 then
        lane.run = nil
        return
    end
    lane.run = { row = voice.row, start = voice.at, cycle = cycle, plays = H.clip_plays(slot) }
end

function H.update_clip_follow(lane, now)
    if not L.follow_enabled then return end
    local run = lane.run
    if not run or lane.pending then return end
    local finish = run.start + run.cycle * run.plays
    local lead = math.min(math.max(C.follow_lead, H.lead()), math.max(0.3, (finish - run.start) * 0.5))
    if now < finish - lead then return end
    local next_row = H.next_slot_after(lane, run.row)
    lane.run = nil
    r.PreventUIRefresh(1)
    if next_row then
        H.commit(lane, next_row, finish)
    else
        H.close_voice_at(lane.current, finish)
        if not lane.hold then H.schedule_owner(lane, "arrangement", finish) end
    end
    r.PreventUIRefresh(-1)
end

function H.first_free_row()
    for row = 1, L.rows do
        local free = true
        for _, lane in ipairs(L.lanes) do
            if H.slot(lane, row) then free = false break end
        end
        if free then return row end
    end
    return nil
end

function H.item_under(track, position)
    for index = 0, r.CountTrackMediaItems(track) - 1 do
        local item = r.GetTrackMediaItem(track, index)
        local start = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
        local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
        if position >= start and position < start + length then return item end
    end
    return nil
end

function H.lane_for_track(track)
    for _, lane in ipairs(L.lanes) do
        if H.target_track(lane) == track then return lane end
    end
    return nil
end

-- A vertical slice of the arrangement becomes a row: whatever each track is
-- playing at the edit cursor lands in that track's column, and tracks without a
-- lane yet get one. Tracks with nothing under the cursor are simply skipped.
function H.scene_from_cursor(row)
    local cursor = r.GetCursorPosition()
    local found = {}
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if not H.is_lane_track(track) then
            local item = H.item_under(track, cursor)
            if item then found[#found + 1] = { track = track, item = item } end
        end
    end
    if #found == 0 then
        L.status = "No items under the edit cursor"
        return
    end
    row = row or H.first_free_row()
    if not row then
        if L.rows < C.max_rows then
            L.rows = L.rows + 1
            row = L.rows
        else
            L.status = "No free scene row left"
            return
        end
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local added = 0
    for _, entry in ipairs(found) do
        local lane = H.lane_for_track(entry.track) or H.add_lane(entry.track)
        if lane and H.assign_slot(lane, row, entry.item) then added = added + 1 end
    end
    H.tidy_lane_tracks()
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Add launcher scene from cursor", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    H.save()
    local bars = H.scene_bars(row)
    L.status = "Scene " .. tostring(row) .. ": " .. tostring(added) .. " clips"
        .. (bars and (", " .. tostring(bars) .. (bars == 1 and " bar" or " bars")) or "")
end

-- Length of `bars` bars starting at `position`, read off the project grid so a
-- tempo change inside the span is accounted for.
function H.bars_to_time(position, bars)
    local per_bar = H.qn_per_bar(position)
    if per_bar <= 0 then return 0 end
    local qn = r.TimeMap2_timeToQN(0, position)
    return r.TimeMap2_QNToTime(0, qn + bars * per_bar) - position
end

-- The reverse of taking a scene from the arrangement: put the clips back onto
-- their own tracks at the edit cursor. Every looping clip in the scene gets the
-- scene length, so the short ones loop until the longest has come round.
function H.write_one(library, target, slot, position, length, into)
    local copy = H.copy_item(library, target, position)
    if not copy then return nil end
    r.SetMediaItemInfo_Value(copy, "B_MUTE", 0)
    r.SetMediaItemInfo_Value(copy, "B_LOOPSRC", slot.loop and 1 or 0)
    r.SetMediaItemInfo_Value(copy, "D_LENGTH", math.max(0.05, length))
    r.SetMediaItemInfo_Value(copy, "D_VOL", slot.gain or 1)
    if into then into[#into + 1] = copy end
    return copy
end

-- A retriggering one-shot is a pattern, not a single hit, so writing it out has
-- to lay down the same grid the launcher would have played. Without this a kick
-- set to retrigger came out as one lonely hit at the start of the scene.
function H.write_clip(target, slot, position, length, into)
    local library = H.item_from_guid(slot.guid)
    if not H.valid_track(target) or not library then return nil end
    local item_length = select(1, H.slot_lengths(slot))
    if slot.loop then
        return H.write_one(library, target, slot, position, length, into)
    end
    if not slot.repeat_qn or slot.repeat_qn <= 0 then
        return H.write_one(library, target, slot, position, item_length, into)
    end
    local first, guard = nil, 0
    local qn = r.TimeMap2_timeToQN(0, position)
    local finish = position + length
    while guard < 512 do
        local at = r.TimeMap2_QNToTime(0, qn)
        if at >= finish - 0.0001 then break end
        if H.step_on(slot, qn) then
            local hit = H.write_one(library, target, slot, at, math.min(item_length, finish - at), into)
            first = first or hit
        end
        qn = qn + slot.repeat_qn
        guard = guard + 1
    end
    return first
end

function H.select_written(items)
    if #items == 0 then return end
    r.SelectAllMediaItems(0, false)
    for _, item in ipairs(items) do
        if H.valid_item(item) then r.SetMediaItemSelected(item, true) end
    end
end

function H.write_scene(row)
    local bars = H.scene_bars(row)
    if not bars then
        L.status = "Scene " .. tostring(row) .. " is empty"
        return
    end
    local position = r.GetCursorPosition()
    local length = H.bars_to_time(position, bars)
    if length <= 0 then return end
    local written = {}
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for _, lane in ipairs(L.lanes) do
        local slot = H.slot(lane, row)
        if slot then H.write_clip(H.target_track(lane), slot, position, length, written) end
    end
    H.select_written(written)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Write launcher scene to arrangement", -1)
    if #written > 0 then
        -- Park the cursor at the end so scenes can be chained into a song.
        r.SetEditCurPos(position + length, false, false)
    end
    r.UpdateArrange()
    L.status = "Wrote " .. tostring(#written) .. " clips, " .. tostring(bars) .. (bars == 1 and " bar" or " bars")
end

function H.write_slot(lane, row)
    local slot = H.slot(lane, row)
    if not slot then return end
    local position = r.GetCursorPosition()
    local length = select(1, H.slot_lengths(slot))
    if slot.loop then
        local bars = H.scene_bars(row) or 1
        length = H.bars_to_time(position, bars)
    end
    local written = {}
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    H.write_clip(H.target_track(lane), slot, position, length, written)
    H.select_written(written)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Write launcher clip to arrangement", -1)
    r.UpdateArrange()
    L.status = #written > 0 and ("Wrote " .. slot.name) or "Could not write that clip"
end

-- Dragging a clip onto the arrange. ImGui only supplies the drag itself; the
-- drop lands on a REAPER window, so the target track and position come from the
-- main script's arrange hit test and the release is detected by hand.
-- Bars and beats if REAPER will give them, otherwise just the bar number.
function H.position_label(position)
    local ok, text = pcall(r.format_timestr_pos, position, "", 2)
    if ok and type(text) == "string" and text ~= "" then return text end
    local bar = H.song_bar(position)
    return bar and ("bar " .. tostring(bar)) or ""
end

function H.begin_clip_drag(lane, row, slot)
    if not r.ImGui_BeginDragDropSource then return end
    if r.ImGui_BeginDragDropSource(UI.ctx, r.ImGui_DragDropFlags_SourceAllowNullID()) then
        L.drag_out = { lane = lane, row = row, name = slot.name, cursor = r.GetCursorPosition() }
        r.ImGui_SetDragDropPayload(UI.ctx, "TK_LAUNCHER_CLIP", slot.guid)
        r.ImGui_TextColored(UI.ctx, UI.colors.accent, "CLIP")
        r.ImGui_Text(UI.ctx, H.truncate(slot.name, UI.rounded(220)))
        r.ImGui_EndDragDropSource(UI.ctx)
    end
end

function H.update_drag_out()
    if not L.drag_out then return end
    local target, position = nil, nil
    if UI.drop_target and not L.over_ui then target, position = UI.drop_target() end
    if r.JS_Mouse_GetState(1) == 1 then
        if target and position then
            -- The edit cursor doubles as the drop marker: it is REAPER's own
            -- vertical line, so the landing point is visible across every track
            -- without painting anything over the arrange.
            if not L.drag_out.marker or math.abs(L.drag_out.marker - position) > 0.0001 then
                L.drag_out.marker = position
                r.SetEditCurPos(position, false, false)
            end
            L.status = "Drop on " .. H.track_name(target, "track") .. "  |  " .. H.position_label(position)
        else
            L.status = "Drag onto the arrange view"
        end
        return
    end
    local drag = L.drag_out
    L.drag_out = nil
    L.status = ""
    local slot = H.slot(drag.lane, drag.row)
    if not slot or not target or not position then
        -- Cancelled: put the edit cursor back where the user had it.
        if drag.marker and drag.cursor then r.SetEditCurPos(drag.cursor, false, false) end
        return
    end
    local written = {}
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    H.write_clip(target, slot, position, math.max(0.05, select(1, H.slot_lengths(slot))), written)
    H.select_written(written)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Drop launcher clip on arrange", -1)
    r.UpdateArrange()
    L.status = #written > 0 and ("Dropped " .. slot.name) or "Could not drop that clip"
end

-- The written arrangement follows exactly the rule the player follows, so the
-- two cannot drift apart. A chain that never ends is bounded by a bar count the
-- user gives; a random follow rolls the dice once and keeps that answer.
function H.write_chain(row, max_bars)
    if not H.scene_filled(row) then
        L.status = "Scene " .. tostring(row) .. " is empty"
        return
    end
    local position = r.GetCursorPosition()
    local written, bars_done, guard = 0, 0, 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local all = {}
    while row and bars_done < max_bars and guard < 512 do
        local bars = H.scene_bars(row)
        if not bars then break end
        for _ = 1, H.scene_plays(row) do
            if bars_done >= max_bars then break end
            local length = H.bars_to_time(position, bars)
            for _, lane in ipairs(L.lanes) do
                local slot = H.slot(lane, row)
                if slot then
                    if H.write_clip(H.target_track(lane), slot, position, length, all) then written = written + 1 end
                end
            end
            position = position + length
            bars_done = bars_done + bars
        end
        row = H.next_scene_after(row)
        guard = guard + 1
    end
    H.select_written(all)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Write launcher scene chain to arrangement", -1)
    if written > 0 then r.SetEditCurPos(position, false, false) end
    r.UpdateArrange()
    L.status = "Wrote " .. tostring(written) .. " clips over " .. tostring(bars_done) .. " bars"
end

-- Queued rather than run: GetUserInputs blocks, and a modal dialog opened from
-- inside a menu leaves the ImGui frame half built for as long as it is up.
function H.ask_write_chain(row)
    L.chain_prompt = { row = row }
end

function H.ask_rename(lane, row)
    L.rename_prompt = { lane = lane, row = row }
end

function H.run_rename_prompt()
    local prompt = L.rename_prompt
    if not prompt then return end
    L.rename_prompt = nil
    if not r.GetUserInputs then return end
    local slot = H.slot(prompt.lane, prompt.row)
    if not slot then return end
    local ok, answer = r.GetUserInputs("Rename clip", 1, "Name:,extrawidth=180", slot.name or "")
    if not ok then return end
    answer = tostring(answer or ""):match("^%s*(.-)%s*$")
    if answer == "" then return end
    slot.name = answer
    H.save()
    L.status = "Renamed to " .. answer
end

function H.run_chain_prompt()
    local prompt = L.chain_prompt
    if not prompt then return end
    L.chain_prompt = nil
    if not r.GetUserInputs then return end
    local ok, answer = r.GetUserInputs("Write scene chain", 1, "Length in bars:", "64")
    if not ok then return end
    local bars = math.floor(tonumber(answer) or 0)
    if bars < 1 then
        L.status = "Give a length of at least one bar"
        return
    end
    H.write_chain(prompt.row, bars)
end

function H.clear_scene(row)
    r.Undo_BeginBlock()
    for _, lane in ipairs(L.lanes) do H.clear_slot(lane, row) end
    r.Undo_EndBlock("Clear launcher scene", -1)
    H.save()
    r.UpdateArrange()
end

function H.selected_items()
    local items = {}
    for index = 0, r.CountSelectedMediaItems(0) - 1 do
        items[#items + 1] = r.GetSelectedMediaItem(0, index)
    end
    table.sort(items, function(left, right)
        return (r.GetMediaItemInfo_Value(left, "D_POSITION") or 0) < (r.GetMediaItemInfo_Value(right, "D_POSITION") or 0)
    end)
    return items
end

function H.assign_from_selection(lane, row)
    local items = H.selected_items()
    if #items == 0 then
        L.status = "Select one or more items in the arrange view first"
        return
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local added = 0
    for index, item in ipairs(items) do
        local target_row = row + index - 1
        if target_row > L.rows then break end
        if H.assign_slot(lane, target_row, item) then added = added + 1 end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Add clips to launcher", -1)
    r.UpdateArrange()
    L.status = added == 1 and "Clip added to launcher" or (tostring(added) .. " clips added to launcher")
    H.save()
end

--------------------------------------------------------------------------------
-- track ownership: arrangement vs launcher
--------------------------------------------------------------------------------

-- Every item on the track, including the ones already behind the play cursor.
-- Skipping those was wrong: they are silent now, but the moment an arrangement
-- loop comes round, or the cursor is moved back, they play again -- which showed
-- up as half a track being muted and the other half not.
function H.arrangement_items(track)
    local items = {}
    if not H.valid_track(track) then return items end
    for index = 0, r.CountTrackMediaItems(track) - 1 do
        items[#items + 1] = r.GetTrackMediaItem(track, index)
    end
    return items
end

-- Only an item the boundary falls inside has to wait for the play cursor.
-- Everything else -- already finished, or not started yet -- can be switched
-- straight away, which is both exact and loop proof.
function H.straddles(item, time)
    local position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    return position < time and position + length > time
end

-- Mirror of every mute state the launcher has changed, so an interrupted
-- session can be repaired instead of leaving the arrangement silent.
-- Merged into what is already stored, never overwritten. The live tables can
-- lose entries -- a project switch, a take that was kept, a lane that went away
-- -- and an overwrite would take the record of those mutes down with them,
-- leaving items muted with nothing left to restore them from. Entries are
-- dropped only where the mute has actually been put back.
function H.save_restore_state()
    local merged = {}
    local order = {}
    local retval, encoded = r.GetProjExtState(0, C.proj_section, "restore")
    if retval and retval > 0 and encoded and encoded ~= "" then
        local ok, stored = pcall(UI.json.decode, encoded)
        if ok and type(stored) == "table" then
            for _, entry in ipairs(stored) do
                if entry.guid and merged[entry.guid] == nil then
                    merged[entry.guid] = tonumber(entry.mute) or 0
                    order[#order + 1] = entry.guid
                end
            end
        end
    end
    local function remember(guid, mute)
        if not guid then return end
        if merged[guid] == nil then order[#order + 1] = guid end
        merged[guid] = mute
    end
    for _, lane in ipairs(L.lanes) do
        for _, entry in ipairs(lane.origin_mutes or {}) do remember(entry.guid, entry.mute) end
    end
    for guid, mute in pairs(L.global_mutes) do remember(guid, mute) end
    for _, guid in ipairs(L.restored_guids or {}) do
        merged[guid] = nil
    end
    L.restored_guids = {}
    local list = {}
    for _, guid in ipairs(order) do
        if merged[guid] ~= nil then list[#list + 1] = { guid = guid, mute = merged[guid] } end
    end
    if #list == 0 then
        r.SetProjExtState(0, C.proj_section, "restore", "")
        return
    end
    local ok2, out = pcall(UI.json.encode, list)
    if ok2 and out then r.SetProjExtState(0, C.proj_section, "restore", out) end
end

function H.repair_restore_state()
    local retval, encoded = r.GetProjExtState(0, C.proj_section, "restore")
    if not retval or retval <= 0 or not encoded or encoded == "" then return 0 end
    local restored = 0
    local ok, list = pcall(UI.json.decode, encoded)
    if ok and type(list) == "table" then
        for _, entry in ipairs(list) do
            local item = H.item_from_guid(entry.guid)
            if item then
                r.SetMediaItemInfo_Value(item, "B_MUTE", tonumber(entry.mute) or 0)
                restored = restored + 1
            end
        end
    end
    r.SetProjExtState(0, C.proj_section, "restore", "")
    L.restored_guids = {}
    return restored
end

-- What an arrangement item goes back to when the launcher lets go of it: its
-- own original state, unless the whole arrangement is muted, in which case it
-- stays silent and its original is handed back to the global registry.
function H.restore_value(entry)
    if L.arrangement_muted then
        L.global_mutes[entry.guid] = entry.mute
        return 1
    end
    L.global_mutes[entry.guid] = nil
    L.restored_guids = L.restored_guids or {}
    L.restored_guids[#L.restored_guids + 1] = entry.guid
    return entry.mute
end

-- Roll back the part of a scheduled handover that was already applied to items
-- lying past the boundary, returning them to the owner the lane has right now.
function H.undo_pre_apply(lane)
    local switch = lane.switch
    if not switch then return end
    local muted_now = lane.owner == "launcher"
    for _, entry in ipairs(lane.origin_mutes or {}) do
        local item = H.item_from_guid(entry.guid)
        if item and not H.straddles(item, switch.at) then
            r.SetMediaItemInfo_Value(item, "B_MUTE", muted_now and 1 or H.restore_value(entry))
        end
    end
    lane.switch = nil
end

-- Schedule the track handover on the same boundary the clip switches on.
function H.schedule_owner(lane, to, time)
    local target = H.target_track(lane)
    if not target then return end
    if lane.switch then H.undo_pre_apply(lane) end
    if lane.owner == to then return end
    if to == "launcher" and not lane.origin_mutes then
        lane.origin_mutes = {}
        for _, item in ipairs(H.arrangement_items(target)) do
            local guid = r.BR_GetMediaItemGUID(item)
            -- If the global arrangement mute already silenced this item, take
            -- its true original along rather than recording the muted state.
            local original = L.global_mutes[guid]
            if original ~= nil then
                L.global_mutes[guid] = nil
            elseif (r.GetMediaItemInfo_Value(item, "B_MUTE") or 0) > 0.5 then
                -- Muted by the user: leave it alone, and leave it untracked so
                -- handing the track back cannot unmute it.
                original = nil
            else
                original = 0
            end
            if original ~= nil then
                lane.origin_mutes[#lane.origin_mutes + 1] = { guid = guid, mute = original }
            end
        end
        H.save_restore_state()
    end
    local pending = {}
    for _, entry in ipairs(lane.origin_mutes or {}) do
        local item = H.item_from_guid(entry.guid)
        if item then
            local value = (to == "launcher") and 1 or H.restore_value(entry)
            if H.straddles(item, time) then
                pending[#pending + 1] = { guid = entry.guid, value = value }
            else
                r.SetMediaItemInfo_Value(item, "B_MUTE", value)
            end
        end
    end
    lane.switch = { to = to, at = time, pending = pending }
end

function H.apply_switch(lane)
    local switch = lane.switch
    if not switch then return end
    for _, entry in ipairs(switch.pending) do
        local item = H.item_from_guid(entry.guid)
        if item then r.SetMediaItemInfo_Value(item, "B_MUTE", entry.value) end
    end
    lane.owner = switch.to
    lane.switch = nil
    if lane.owner == "arrangement" then
        lane.origin_mutes = nil
        H.save_restore_state()
    end
end

-- Hand the track back immediately, without waiting for a boundary.
function H.release_now(lane)
    lane.switch = nil
    if lane.origin_mutes then
        for _, entry in ipairs(lane.origin_mutes) do
            local item = H.item_from_guid(entry.guid)
            if item then r.SetMediaItemInfo_Value(item, "B_MUTE", H.restore_value(entry)) end
        end
        lane.origin_mutes = nil
        H.save_restore_state()
    end
    lane.owner = "arrangement"
end

--------------------------------------------------------------------------------
-- arrangement mute: the whole song silenced, the launcher still audible
--------------------------------------------------------------------------------

function H.is_lane_track(track)
    if not H.valid_track(track) then return false end
    local ok, value = r.GetSetMediaTrackInfo_String(track, C.track_ext, "", false)
    return ok and value == "1"
end

-- Items a lane already holds are left alone; that lane owns their originals.
function H.lane_held_guids()
    local held = {}
    for _, lane in ipairs(L.lanes) do
        for _, entry in ipairs(lane.origin_mutes or {}) do held[entry.guid] = true end
    end
    return held
end

-- Muting arrangement *items* instead of tracks is what makes this possible at
-- all: the clip arrives on a send, which a track mute would kill as well.
function H.set_arrangement_muted(muted, time)
    if muted == L.arrangement_muted then return end
    L.arrangement_muted = muted
    L.global_switch = nil
    local pending = {}
    if muted then
        local held = H.lane_held_guids()
        for index = 0, r.CountTracks(0) - 1 do
            local track = r.GetTrack(0, index)
            if not H.is_lane_track(track) then
                for _, item in ipairs(H.arrangement_items(track)) do
                    local guid = r.BR_GetMediaItemGUID(item)
                    local already = (r.GetMediaItemInfo_Value(item, "B_MUTE") or 0) > 0.5
                    -- Items the user muted themselves stay untracked, so turning
                    -- the song mute off again cannot unmute them.
                    if not held[guid] and L.global_mutes[guid] == nil and not already then
                        L.global_mutes[guid] = 0
                        if H.straddles(item, time) then
                            pending[#pending + 1] = { guid = guid, value = 1 }
                        else
                            r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
                        end
                    end
                end
            end
        end
    else
        for guid, original in pairs(L.global_mutes) do
            local item = H.item_from_guid(guid)
            if item then
                if H.straddles(item, time) then
                    pending[#pending + 1] = { guid = guid, value = original, release = true }
                else
                    r.SetMediaItemInfo_Value(item, "B_MUTE", original)
                    L.global_mutes[guid] = nil
                end
            else
                L.global_mutes[guid] = nil
            end
        end
    end
    if #pending > 0 then L.global_switch = { at = time, pending = pending } end
    H.save_restore_state()
    r.UpdateArrange()
end

function H.apply_global_switch()
    local switch = L.global_switch
    if not switch then return end
    for _, entry in ipairs(switch.pending) do
        local item = H.item_from_guid(entry.guid)
        if item then r.SetMediaItemInfo_Value(item, "B_MUTE", entry.value) end
        if entry.release then L.global_mutes[entry.guid] = nil end
    end
    L.global_switch = nil
    H.save_restore_state()
end

function H.restore_arrangement_mute()
    L.global_switch = nil
    L.restored_guids = L.restored_guids or {}
    for guid, original in pairs(L.global_mutes) do
        local item = H.item_from_guid(guid)
        if item then r.SetMediaItemInfo_Value(item, "B_MUTE", original) end
        L.restored_guids[#L.restored_guids + 1] = guid
    end
    L.global_mutes = {}
    L.arrangement_muted = false
    H.save_restore_state()
end

-- Is this lane's target track silenced right now, counting a handover that is
-- scheduled but has not landed yet?
function H.lane_silenced(lane)
    if lane.switch then return lane.switch.to == "launcher" end
    return lane.owner == "launcher"
end

-- Per track version of the song mute. `hold` marks it as a deliberate choice so
-- the automatic hand-back (when a clip stops) leaves it alone.
function H.toggle_lane_arrangement(lane)
    local now = H.schedule_pos()
    local time = now and H.boundary_after(now, false) or r.GetCursorPosition()
    r.PreventUIRefresh(1)
    if H.lane_silenced(lane) then
        lane.hold = false
        H.schedule_owner(lane, "arrangement", time)
        L.status = H.lane_label(lane) .. ": arrangement back"
    else
        lane.hold = true
        H.schedule_owner(lane, "launcher", time)
        L.status = H.lane_label(lane) .. ": arrangement muted"
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

function H.toggle_arrangement_mute()
    local now = H.schedule_pos()
    local time = now and H.boundary_after(now, false) or r.GetCursorPosition()
    H.set_arrangement_muted(not L.arrangement_muted, time)
    L.mute_song_default = L.arrangement_muted and true or false
    H.save()
    L.status = L.arrangement_muted and "Arrangement muted, launcher stays audible" or "Arrangement back"
end

--------------------------------------------------------------------------------
-- voices
--------------------------------------------------------------------------------

-- The one place a voice is thrown away, which makes it the one place recording
-- has to intervene: while armed, a voice that actually sounded is kept instead
-- of deleted. It already sits at the right position with the right length, so
-- there is nothing to reconstruct afterwards.
function H.kill_voice(voice, lane)
    if not voice then return end
    if L.recording and voice.started and lane then
        H.capture_voice(voice, lane)
        return
    end
    H.delete_item(voice.item)
    H.delete_item(voice.wrap)
    for _, media in ipairs(voice.hits or {}) do H.delete_item(media) end
    voice.item, voice.wrap, voice.hits = nil, nil, nil
end

function H.capture_voice(voice, lane)
    local target = H.target_track(lane)
    local function take(media)
        if H.valid_item(media) then
            r.SetMediaItemInfo_Value(media, "B_MUTE", 1)
            L.captured[#L.captured + 1] = { item = media, track = target }
        end
    end
    take(voice.item)
    take(voice.wrap)
    for _, media in ipairs(voice.hits or {}) do take(media) end
    voice.item, voice.wrap, voice.hits = nil, nil, nil
end

-- The loop the transport is repeating over, if any. A clip launched inside it
-- has to cover the whole region, otherwise the loop jumps back to a stretch of
-- timeline where the clip simply does not exist yet.
function H.loop_region()
    if not r.GetSetRepeat or r.GetSetRepeat(-1) ~= 1 then return nil end
    local loop_start, loop_end = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
    if not loop_start or not loop_end or loop_end - loop_start < 0.25 then return nil end
    return loop_start, loop_end
end

function H.item_end(media)
    if not H.valid_item(media) then return nil end
    return (r.GetMediaItemInfo_Value(media, "D_POSITION") or 0) + (r.GetMediaItemInfo_Value(media, "D_LENGTH") or 0)
end

function H.voice_end(voice)
    local latest = nil
    for _, field in ipairs({ "item", "wrap" }) do
        local finish = H.item_end(voice[field])
        if finish and (not latest or finish > latest) then latest = finish end
    end
    for _, media in ipairs(voice.hits or {}) do
        local finish = H.item_end(media)
        if finish and (not latest or finish > latest) then latest = finish end
    end
    -- A retriggering one-shot keeps producing hits, so it is never finished
    -- until it is closed off.
    if voice.repeat_qn and not voice.closing then return math.huge end
    return latest
end

-- Fill the stretch between the loop start and the launch point, so the next
-- time round the clip is already playing when the loop comes back.
function H.build_wrap(lane, voice)
    if not voice or voice.wrap or not voice.looped then return end
    local loop_start, loop_end = H.loop_region()
    if not loop_start or voice.at - loop_start < 0.05 or voice.at >= loop_end then return end
    local lane_track = H.lane_track(lane)
    local library = H.item_from_guid(voice.slot_guid or "")
    if not lane_track or not library then return end
    local wrap = H.copy_item(library, lane_track, loop_start)
    if not wrap then return end
    r.SetMediaItemInfo_Value(wrap, "B_MUTE", 0)
    r.SetMediaItemInfo_Value(wrap, "B_LOOPSRC", 1)
    r.SetMediaItemInfo_Value(wrap, "D_LENGTH", voice.at - loop_start)
    r.SetMediaItemInfo_Value(wrap, "D_FADEINLEN", 0)
    r.SetMediaItemInfo_Value(wrap, "D_FADEOUTLEN", C.fade)
    r.SetMediaItemInfo_Value(wrap, "D_FADEINLEN_AUTO", -1)
    r.SetMediaItemInfo_Value(wrap, "D_FADEOUTLEN_AUTO", -1)
    if r.UpdateItemInProject then r.UpdateItemInProject(wrap) end
    voice.wrap = wrap
end

-- Once the loop has actually come back round, the filler becomes the clip: it
-- is stretched over the whole loop region and the original launch item goes.
-- From here on every pass starts the clip cleanly at the loop start.
function H.promote_wrap(lane, heard)
    local voice = lane.current
    if not voice or not H.valid_item(voice.wrap) or not H.valid_item(voice.item) then return end
    local loop_start, loop_end = H.loop_region()
    if not loop_start then return end
    local position = r.GetMediaItemInfo_Value(voice.item, "D_POSITION") or 0
    if position - heard < 0.25 then return end
    r.SetMediaItemInfo_Value(voice.wrap, "D_LENGTH", math.max(0.05, loop_end - loop_start))
    voice.closing = nil
    H.delete_item(voice.item)
    voice.item = voice.wrap
    voice.wrap = nil
    voice.at = loop_start
end

-- End everything the outgoing voice occupies at `time`. Items reaching past it
-- are trimmed, items placed after it are dropped, and items that have already
-- finished are left to the harvest, which clears them before the loop could
-- bring them back.
function H.close_voice_at(voice, time)
    local restore = {}
    if not voice then return restore end
    local function close(field)
        local media = voice[field]
        if not H.valid_item(media) then return end
        local position = r.GetMediaItemInfo_Value(media, "D_POSITION") or 0
        local length = r.GetMediaItemInfo_Value(media, "D_LENGTH") or 0
        if position >= time then
            H.delete_item(media)
            voice[field] = nil
        elseif position + length > time then
            restore[#restore + 1] = {
                item = media,
                length = length,
                fade = r.GetMediaItemInfo_Value(media, "D_FADEOUTLEN"),
            }
            H.trim_to(media, time)
            voice.closing = true
        end
    end
    close("item")
    close("wrap")
    for index = #(voice.hits or {}), 1, -1 do
        local media = voice.hits[index]
        if H.valid_item(media) then
            local position = r.GetMediaItemInfo_Value(media, "D_POSITION") or 0
            local length = r.GetMediaItemInfo_Value(media, "D_LENGTH") or 0
            if position >= time then
                H.delete_item(media)
                table.remove(voice.hits, index)
            elseif position + length > time then
                H.trim_to(media, time)
            end
        else
            table.remove(voice.hits, index)
        end
    end
    if voice.hits then voice.closing = true end
    return restore
end

-- Undo a launch that has not been reached by the play cursor yet.
function H.cancel_pending(lane)
    local pending = lane.pending
    if not pending then return end
    H.kill_voice(pending)
    for _, entry in ipairs(pending.restore or {}) do
        if H.valid_item(entry.item) then
            r.SetMediaItemInfo_Value(entry.item, "D_LENGTH", entry.length)
            if entry.fade then r.SetMediaItemInfo_Value(entry.item, "D_FADEOUTLEN", entry.fade) end
        end
    end
    lane.pending = nil
end

function H.commit(lane, row, time)
    local slot = H.slot(lane, row)
    local lane_track = H.lane_track(lane)
    local library = slot and H.item_from_guid(slot.guid) or nil
    if not slot or not lane_track or not library then return false end

    H.cancel_pending(lane)

    -- Close the outgoing voice first so the two never overlap (which would make
    -- REAPER build an auto-crossfade between them).
    local restore = H.close_voice_at(lane.current, time)

    local voice = H.copy_item(library, lane_track, time)
    if not voice then return false end
    r.SetMediaItemInfo_Value(voice, "B_MUTE", 0)
    r.SetMediaItemInfo_Value(voice, "B_LOOPSRC", slot.loop and 1 or 0)
    local item_length, loop_length = H.slot_lengths(slot)
    r.SetMediaItemInfo_Value(voice, "D_LENGTH", slot.loop and C.voice_length or math.max(0.01, item_length))
    -- No fade in: the clip begins on a boundary and has to arrive at full level.
    -- A fade out is a different matter, that one covers a cut mid waveform.
    r.SetMediaItemInfo_Value(voice, "D_FADEINLEN", 0)
    r.SetMediaItemInfo_Value(voice, "D_FADEINDIR", 0)
    r.SetMediaItemInfo_Value(voice, "D_FADEOUTLEN", C.fade)
    r.SetMediaItemInfo_Value(voice, "D_FADEINLEN_AUTO", -1)
    r.SetMediaItemInfo_Value(voice, "D_FADEOUTLEN_AUTO", -1)
    r.SetMediaItemInfo_Value(voice, "D_VOL", slot.gain or 1)
    if r.UpdateItemInProject then r.UpdateItemInProject(voice) end

    if slot.repeat_qn and slot.repeat_qn > 0 and not slot.loop
        and not H.step_on(slot, r.TimeMap2_timeToQN(0, time)) then
        -- The clip lands on a step that is off, so it is placed but silent; the
        -- pattern takes over from the next step onwards.
        r.SetMediaItemInfo_Value(voice, "B_MUTE", 1)
    end
    lane.pending = {
        item = voice,
        row = row,
        at = time,
        length = loop_length,
        looped = slot.loop and true or false,
        slot_guid = slot.guid,
        restore = restore,
        gain = slot.gain,
        repeat_qn = (not slot.loop and slot.repeat_qn and slot.repeat_qn > 0) and slot.repeat_qn or nil,
        steps = slot.steps,
        next_hit_qn = (not slot.loop and slot.repeat_qn and slot.repeat_qn > 0)
            and (r.TimeMap2_timeToQN(0, time) + slot.repeat_qn) or nil,
        hits = {},
    }
    H.fill_hits(lane, lane.pending, time)
    H.schedule_owner(lane, "launcher", time)
    return true
end

-- A looping voice only claims a few minutes of timeline at a time and grows as
-- the play cursor approaches its end, so a jam does not inflate the project.
function H.extend_voice(lane, heard)
    local voice = lane.current
    if not voice or voice.closing or not voice.looped then return end
    if lane.pending or lane.switch then return end
    if not H.valid_item(voice.item) then return end
    local position = r.GetMediaItemInfo_Value(voice.item, "D_POSITION") or 0
    local length = r.GetMediaItemInfo_Value(voice.item, "D_LENGTH") or 0
    if position + length - heard > C.voice_margin then return end
    r.SetMediaItemInfo_Value(voice.item, "D_LENGTH", length + C.voice_extend)
end

-- Launches that were waiting for the loop to come round. The play cursor is a
-- frame or so past the loop start by now, so the clip begins a few milliseconds
-- in; everywhere else a launch still lands exactly on the boundary.
function H.run_queued(heard)
    local loop_start = H.loop_region()
    if not loop_start then
        for _, lane in ipairs(L.lanes) do lane.queued = nil end
        return
    end
    for _, lane in ipairs(L.lanes) do
        local queued = lane.queued
        if queued then
            lane.queued = nil
            if queued.stop then
                H.cancel_pending(lane)
                H.close_voice_at(lane.current, loop_start)
                if not lane.hold then H.schedule_owner(lane, "arrangement", loop_start) end
            else
                H.commit(lane, queued.row, loop_start)
            end
        end
    end
    r.UpdateArrange()
end

-- One hit per retrigger, always placed ahead of the play cursor so each one is
-- as exact as a launch. Only a few seconds are scheduled at a time: a jam would
-- otherwise fill the timeline with hundreds of items nobody has reached yet.
-- A retrigger is a pattern, not only an interval: how many steps fit in a bar
-- at the chosen division, and which of them fire. The steps are anchored to the
-- project grid rather than to the launch, so step one is the downbeat and a
-- snare on two and four lands on two and four whenever you start it.
function H.step_count(step_qn)
    if not step_qn or step_qn <= 0 then return 0 end
    local count = math.floor((H.qn_per_bar(0) / step_qn) + 0.5)
    return math.max(1, math.min(16, count))
end

function H.step_on(slot, qn)
    local step = slot.repeat_qn
    if not step or step <= 0 then return true end
    local steps = slot.steps
    if not steps or #steps == 0 then return true end
    local index = (math.floor((qn / step) + 0.0001) % #steps) + 1
    return steps[index] ~= false
end

-- Shared by the scheduler and by commit, so the first hits are put down at the
-- same moment the clip itself is, with the same run-up. Made only at promotion
-- they had none, and the first bar of a retriggered one-shot stayed silent.
function H.fill_hits(lane, voice, from)
    if not voice or voice.closing or not voice.repeat_qn or voice.repeat_qn <= 0 then return end
    local slot_of_voice = { repeat_qn = voice.repeat_qn, steps = voice.steps }
    local library = H.item_from_guid(voice.slot_guid or "")
    local lane_track = H.lane_track(lane)
    if not library or not lane_track then return end
    voice.hits = voice.hits or {}
    local horizon = from + H.lead() + 3
    local guard = 0
    while voice.next_hit_qn and guard < 32 do
        local time = r.TimeMap2_QNToTime(0, voice.next_hit_qn)
        if time > horizon then break end
        if time > from and H.step_on(slot_of_voice, voice.next_hit_qn) then
            local hit = H.copy_item(library, lane_track, time)
            if hit then
                r.SetMediaItemInfo_Value(hit, "B_MUTE", 0)
                r.SetMediaItemInfo_Value(hit, "B_LOOPSRC", 0)
                r.SetMediaItemInfo_Value(hit, "D_LENGTH", math.max(0.01, voice.length or 0.01))
                r.SetMediaItemInfo_Value(hit, "D_FADEINLEN", 0)
                r.SetMediaItemInfo_Value(hit, "D_FADEINLEN_AUTO", -1)
                r.SetMediaItemInfo_Value(hit, "D_FADEOUTLEN_AUTO", -1)
                r.SetMediaItemInfo_Value(hit, "D_VOL", voice.gain or 1)
                if r.UpdateItemInProject then r.UpdateItemInProject(hit) end
                voice.hits[#voice.hits + 1] = hit
            end
        end
        voice.next_hit_qn = voice.next_hit_qn + voice.repeat_qn
        guard = guard + 1
    end
end

function H.extend_repeats(lane, heard)
    local voice = lane.current
    if not voice or voice.closing or not voice.repeat_qn or voice.repeat_qn <= 0 then return end
    local library = H.item_from_guid(voice.slot_guid or "")
    local lane_track = H.lane_track(lane)
    if not library or not lane_track then return end
    voice.hits = voice.hits or {}
    -- Spent hits are cleared here rather than through the harvest, so recording
    -- has to be honoured here as well. Without it a retriggered one-shot kept
    -- only the few hits that happened to still be alive when the take ended.
    for index = #voice.hits, 1, -1 do
        local media = voice.hits[index]
        local finish = H.item_end(media)
        if not finish or heard > finish + C.harvest_pad then
            if L.recording and voice.started and H.valid_item(media) then
                r.SetMediaItemInfo_Value(media, "B_MUTE", 1)
                L.captured[#L.captured + 1] = { item = media, track = H.target_track(lane) }
            else
                H.delete_item(media)
            end
            table.remove(voice.hits, index)
        end
    end
    H.fill_hits(lane, voice, heard)
end

-- Gain is a mixer control, so it has to be heard while it is being turned. The
-- value is carried on the voice; when the slot no longer matches it, every item
-- the voice owns is brought into line. Nothing is written unless it changed.
function H.sync_gain(lane)
    local voice = lane.current
    if not voice or not voice.row then return end
    local slot = H.slot(lane, voice.row)
    if not slot then return end
    local wanted = slot.gain or 1
    if math.abs((voice.gain or 1) - wanted) < 0.0001 then return end
    voice.gain = wanted
    for _, field in ipairs({ "item", "wrap" }) do
        if H.valid_item(voice[field]) then r.SetMediaItemInfo_Value(voice[field], "D_VOL", wanted) end
    end
    for _, media in ipairs(voice.hits or {}) do
        if H.valid_item(media) then r.SetMediaItemInfo_Value(media, "D_VOL", wanted) end
    end
end

function H.harvest_lane(lane, force)
    local heard = H.heard_pos()
    local function finished(voice)
        if not voice then return false end
        if force or not heard then return true end
        local finish = H.voice_end(voice)
        if not finish then return true end
        return heard > finish + C.harvest_pad
    end
    -- Voices that were replaced are only removed once the play cursor the user
    -- actually hears has passed their trimmed end, never on the scheduling
    -- position (which runs ahead by the output latency).
    if force then
        lane.queued = nil
        lane.run = nil
    end
    lane.retired = lane.retired or {}
    for index = #lane.retired, 1, -1 do
        if finished(lane.retired[index]) then
            H.kill_voice(lane.retired[index], lane)
            table.remove(lane.retired, index)
        end
    end
    if finished(lane.pending) then
        H.kill_voice(lane.pending, lane)
        lane.pending = nil
    end
    if finished(lane.current) then
        H.kill_voice(lane.current, lane)
        lane.current = nil
    end
    -- A one-shot that ran out hands the track back on its own, unless the user
    -- deliberately muted this track's arrangement.
    if not lane.hold and not lane.current and not lane.pending and not lane.switch and lane.owner == "launcher" then
        H.release_now(lane)
    end
end

function H.harvest_all(force)
    for _, lane in ipairs(L.lanes) do H.harvest_lane(lane, force) end
end

--------------------------------------------------------------------------------
-- launching
--------------------------------------------------------------------------------

-- Returns the boundary to launch on plus whether the transport still has to be
-- started.
-- Returns the boundary to launch on, whether the transport still has to be
-- started, and whether the launch belongs to the next pass of an arrangement
-- loop. That last case matters: a boundary at or past the loop end is never
-- reached, because the transport jumps back just before it, so a launch
-- scheduled there would sit queued forever.
function H.launch_time()
    local now = H.schedule_pos()
    if not now then return H.boundary_after(r.GetCursorPosition(), true), true, false end
    local time = H.boundary_after(now, false)
    local loop_start, loop_end = H.loop_region()
    if loop_start and now >= loop_start and now < loop_end and time >= loop_end - 0.01 then
        return loop_start, false, true
    end
    return time, false, false
end

function H.roll_transport()
    if (r.GetPlayState() & 1) == 1 then return end
    if r.OnPlayButton then r.OnPlayButton() else r.Main_OnCommand(1007, 0) end
    -- The transport needs a moment to report "playing"; without this grace
    -- period the next update() would read "stopped" and harvest the voice we
    -- just scheduled.
    L.roll_guard = r.time_precise() + 1.5
end

function H.launch(lane, row)
    local slot_check = H.slot(lane, row)
    if slot_check and slot_check.missing then
        L.status = "That clip is gone from the project; clear the slot or redo the deletion"
        return
    end
    if H.lane_orphaned(lane) then
        L.status = "That lane's track is gone; remove the lane or undo the deletion"
        return
    end
    local time, needs_roll, at_wrap = H.launch_time()
    if at_wrap then
        lane.queued = { row = row }
        local slot = H.slot(lane, row)
        L.status = "Queued " .. (slot and slot.name or "clip") .. " for the top of the loop"
        return
    end
    r.PreventUIRefresh(1)
    local ok = H.commit(lane, row, time)
    r.PreventUIRefresh(-1)
    if not ok then
        L.status = "Could not launch that slot"
        return
    end
    if needs_roll then H.roll_transport() end
    r.UpdateArrange()
    local slot = H.slot(lane, row)
    L.status = "Launched " .. (slot and slot.name or "clip")
end

-- A scene is a section of the song, so an empty slot means "this track is not
-- part of it" and its lane stops on the same boundary. Without that a clip from
-- the previous scene would play straight through the next one.
function H.scene_commit(row, time)
    local launched, stopped = 0, 0
    for _, lane in ipairs(L.lanes) do
        if not H.lane_orphaned(lane) then
            if H.slot(lane, row) then
                if H.commit(lane, row, time) then launched = launched + 1 end
            elseif lane.current or lane.pending then
                lane.run = nil
                H.cancel_pending(lane)
                H.close_voice_at(lane.current, time)
                if not lane.hold then H.schedule_owner(lane, "arrangement", time) end
                stopped = stopped + 1
            end
        end
    end
    return launched, stopped
end

-- Remember what is running so the follow action knows when its turn comes.
function H.begin_scene_run(row, time)
    local bars = H.scene_bars(row)
    if not bars then
        L.scene_run = nil
        return
    end
    L.scene_run = { row = row, start = time, bars = bars, plays = H.scene_plays(row) }
end

function H.scene_run_end()
    local run = L.scene_run
    if not run then return nil end
    return run.start + H.bars_to_time(run.start, run.bars * run.plays)
end

-- Scheduled a beat ahead of the changeover, so the next scene is committed
-- before the play cursor reaches it and lands exactly on the boundary.
function H.update_follow()
    if not L.follow_enabled then return end
    local run = L.scene_run
    if not run then return end
    local now = H.schedule_pos()
    if not now then return end
    local finish = H.scene_run_end()
    if not finish then return end
    -- Scheduled well ahead, not just before the changeover: an item that appears
    -- a moment before the play cursor reaches it has not been buffered yet, and
    -- comes in late. Short scenes fall back to half their own length.
    local lead = math.min(math.max(C.follow_lead, H.lead()), math.max(0.3, (finish - run.start) * 0.5))
    if now < finish - lead then return end
    local next_row = H.next_scene_after(run.row)
    L.scene_run = nil
    r.PreventUIRefresh(1)
    if next_row then
        -- Reported the same way as a scene you launch yourself: a follow action
        -- is the same event, it just was not you who pressed it.
        local launched, stopped = H.scene_commit(next_row, finish)
        H.begin_scene_run(next_row, finish)
        L.status = "Scene " .. tostring(next_row) .. ": " .. tostring(launched) .. " playing"
            .. (stopped > 0 and (", " .. tostring(stopped) .. " stopped") or "")
    else
        for _, lane in ipairs(L.lanes) do
            H.cancel_pending(lane)
            H.close_voice_at(lane.current, finish)
            if not lane.hold then H.schedule_owner(lane, "arrangement", finish) end
        end
        L.status = "Scene chain finished"
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
end

function H.launch_scene(row)
    local time, needs_roll, at_wrap = H.launch_time()
    if at_wrap then
        local queued = 0
        for _, lane in ipairs(L.lanes) do
            if not H.lane_orphaned(lane) then
                if H.slot(lane, row) then
                    lane.queued = { row = row }
                    queued = queued + 1
                elseif lane.current or lane.pending then
                    lane.queued = { stop = true }
                    queued = queued + 1
                end
            end
        end
        L.status = queued > 0 and ("Scene " .. tostring(row) .. " queued for the top of the loop")
            or ("Scene " .. tostring(row) .. " is empty")
        return
    end
    r.PreventUIRefresh(1)
    if needs_roll then H.harvest_all(true) end
    local launched, stopped = H.scene_commit(row, time)
    r.PreventUIRefresh(-1)
    if launched == 0 and stopped == 0 then
        L.status = "Scene " .. tostring(row) .. " is empty"
        return
    end
    if launched > 0 then H.begin_scene_run(row, time) else L.scene_run = nil end
    if needs_roll and launched > 0 then H.roll_transport() end
    r.UpdateArrange()
    L.status = "Scene " .. tostring(row) .. ": " .. tostring(launched) .. " playing"
        .. (stopped > 0 and (", " .. tostring(stopped) .. " stopped") or "")
end

function H.stop_lane(lane)
    lane.run = nil
    local now = H.schedule_pos()
    if not now then
        H.harvest_lane(lane, true)
        H.release_now(lane)
        r.UpdateArrange()
        return
    end
    local time = H.boundary_after(now, false)
    r.PreventUIRefresh(1)
    H.cancel_pending(lane)
    H.close_voice_at(lane.current, time)
    -- A deliberately muted arrangement stays muted; stopping the clip is not a
    -- request to hand the track back.
    if not lane.hold then H.schedule_owner(lane, "arrangement", time) end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    L.status = lane.hold and "Lane stops on the next boundary" or "Lane returns to the arrangement on the next boundary"
end

function H.stop_all_quantized()
    local now = H.schedule_pos()
    if not now then
        H.reset_all()
        return
    end
    local time = H.boundary_after(now, false)
    r.PreventUIRefresh(1)
    for _, lane in ipairs(L.lanes) do
        H.cancel_pending(lane)
        H.close_voice_at(lane.current, time)
        if not lane.hold then H.schedule_owner(lane, "arrangement", time) end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    L.scene_run = nil
    L.status = "All lanes return to the arrangement on the next boundary"
end

-- The recovery button. Everything the launcher changed goes back at once: clips
-- stop, every muted arrangement item is restored, deliberate per track mutes are
-- cleared and the song mute goes off. The transport keeps rolling, so the song
-- simply continues.
function H.reset_all()
    r.PreventUIRefresh(1)
    L.arrangement_muted = false
    L.scene_run = nil
    for _, lane in ipairs(L.lanes) do
        lane.hold = false
        H.harvest_lane(lane, true)
        H.release_now(lane)
    end
    H.restore_arrangement_mute()
    -- Anything the live tables lost track of is still listed in the project
    -- mirror; this is what makes Reset a real safety net rather than a tidy up.
    local repaired = H.repair_restore_state()
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    L.status = repaired > 0
        and ("Reset: " .. tostring(repaired) .. " muted items restored")
        or "Reset: nothing was left to restore"
end

--------------------------------------------------------------------------------
-- persistence
--------------------------------------------------------------------------------

-- `quiet` is for changes that are pure display state. Everything else marks the
-- project dirty: grid data lives in project ext state, and a change that never
-- touched an item would otherwise be lost without REAPER even offering to save.
-- Stored as a run of ones and zeroes: an array with false in it encodes badly,
-- and a short string is easy to read back and easy to eyeball in a project file.
function H.steps_to_text(steps)
    if not steps or #steps == 0 then return nil end
    local out = {}
    for index = 1, #steps do out[index] = steps[index] == false and "0" or "1" end
    local text = table.concat(out)
    if not text:find("0") then return nil end
    return text
end

function H.steps_from_text(text)
    if type(text) ~= "string" or text == "" then return nil end
    local steps = {}
    for index = 1, #text do steps[index] = text:sub(index, index) ~= "0" end
    return steps
end

function H.save(quiet)
    local data = {
        rows = L.rows,
        quantize = L.quantize,
        follow = L.follow_enabled and true or false,
        lead = L.lead,
        mute_song = L.mute_song_default and true or false,
        big_cells = L.big_cells and true or false,
        scenes = {},
        tempo_sync = L.tempo_sync and true or false,
        lanes = {},
    }
    for row, entry in pairs(L.scenes or {}) do
        if entry.follow ~= "stop" or (entry.plays or 1) ~= 1 then
            data.scenes[#data.scenes + 1] = { row = row, follow = entry.follow, plays = entry.plays }
        end
    end
    for _, lane in ipairs(L.lanes) do
        local slots = {}
        for _, slot in ipairs(lane.slots) do
            slots[#slots + 1] = {
                row = slot.row,
                guid = slot.guid,
                name = slot.name,
                is_midi = slot.is_midi and true or false,
                length = slot.length,
                loop = slot.loop and true or false,
                loop_len = slot.loop_len,
                repeat_qn = slot.repeat_qn,
                steps = H.steps_to_text(slot.steps),
                follow = slot.follow,
                plays = slot.plays,
                color = slot.color,
                gain = slot.gain,
            }
        end
        data.lanes[#data.lanes + 1] = {
            name = lane.name,
            track_guid = lane.track_guid,
            lane_guid = lane.lane_guid,
            slots = slots,
        }
    end
    local ok, encoded = pcall(UI.json.encode, data)
    if ok and encoded then
        r.SetProjExtState(0, C.proj_section, "grid", encoded)
        if not quiet and r.MarkProjectDirty then r.MarkProjectDirty(0) end
    end
end

-- Anything on a lane track that is not a known library item is a voice left
-- behind by a previous session.
function H.sweep_stray_voices()
    for _, lane in ipairs(L.lanes) do
        local track = H.lane_track(lane)
        if track then
            local known = {}
            for _, slot in ipairs(lane.slots) do known[slot.guid] = true end
            for index = r.CountTrackMediaItems(track) - 1, 0, -1 do
                local item = r.GetTrackMediaItem(track, index)
                if not known[r.BR_GetMediaItemGUID(item)] then
                    r.DeleteTrackMediaItem(track, item)
                end
            end
        end
    end
end

-- Switching project tabs invalidates every stored item and track pointer, so
-- the grid is dropped without touching them and reloaded from the new project.
function H.project_changed()
    local proj = r.EnumProjects(-1, "")
    if proj == L.proj then return false end
    L.proj = proj
    L.lanes = {}
    L.loaded = false
    L.status = ""
    return true
end

function H.load()
    L.loaded = true
    L.proj = r.EnumProjects(-1, "")
    L.lanes = {}
    local retval, encoded = r.GetProjExtState(0, C.proj_section, "grid")
    local data = nil
    if retval and retval > 0 and encoded and encoded ~= "" then
        local ok, decoded = pcall(UI.json.decode, encoded)
        if ok and type(decoded) == "table" then data = decoded end
    end
    if data then
        L.rows = math.floor(tonumber(data.rows) or 8)
        L.quantize = tonumber(data.quantize) or 1
        L.follow_enabled = data.follow ~= false
        L.lead = tonumber(data.lead) or 0
        L.mute_song_default = data.mute_song ~= false
        L.big_cells = data.big_cells ~= false
        L.scenes = {}
        for _, entry in ipairs(data.scenes or {}) do
            local row = math.floor(tonumber(entry.row) or 0)
            if row > 0 then
                L.scenes[row] = { follow = entry.follow or "stop", plays = math.floor(tonumber(entry.plays) or 1) }
            end
        end
        L.tempo_sync = data.tempo_sync ~= false
        for _, stored in ipairs(data.lanes or {}) do
            if H.track_from_guid(stored.lane_guid) and H.track_from_guid(stored.track_guid) then
                local lane = {
                    name = stored.name or "Lane",
                    track_guid = stored.track_guid,
                    lane_guid = stored.lane_guid,
                    slots = {},
                    owner = "arrangement",
                }
                for _, slot in ipairs(stored.slots or {}) do
                    local item = H.item_from_guid(slot.guid)
                    if item then
                        r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
                        local slot_take = r.GetActiveTake(item)
                        if not slot.loop_len and slot_take then
                            slot.loop_len = H.loop_period(item, slot_take)
                        end
                        -- Also migrates libraries saved by an older layout.
                        local parked = H.park_position()
                        if (r.GetMediaItemInfo_Value(item, "D_POSITION") or 0) ~= parked then
                            r.SetMediaItemInfo_Value(item, "D_POSITION", parked)
                        end
                        lane.slots[#lane.slots + 1] = {
                            row = math.floor(tonumber(slot.row) or 1),
                            guid = slot.guid,
                            name = slot.name or "Clip",
                            is_midi = slot.is_midi and true or false,
                            length = tonumber(slot.length) or 0,
                            loop = slot.loop ~= false,
                            loop_len = tonumber(slot.loop_len),
                            repeat_qn = tonumber(slot.repeat_qn),
                            steps = H.steps_from_text(slot.steps),
                            follow = slot.follow,
                            plays = tonumber(slot.plays),
                            color = tonumber(slot.color),
                            gain = tonumber(slot.gain),
                        }
                    end
                end
                L.lanes[#L.lanes + 1] = lane
            end
        end
    end
    if L.rows < 1 or L.rows > C.max_rows then L.rows = 8 end
    H.sweep_stray_voices()
    -- If a previous session was interrupted mid takeover, give the arrangement
    -- its mute states back before anything else happens.
    H.repair_restore_state()
end

--------------------------------------------------------------------------------
-- grid drawing
--------------------------------------------------------------------------------

function H.slot_context(lane, lane_index, row, slot)
    if not r.ImGui_BeginPopupContextItem(UI.ctx, "##launch_ctx_" .. lane_index .. "_" .. row) then return false end
    if slot then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, slot.name)
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Launch") then H.launch(lane, row) end
        if r.ImGui_MenuItem(UI.ctx, "Stop lane") then H.stop_lane(lane) end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Rename...") then H.ask_rename(lane, row) end
        if r.ImGui_MenuItem(UI.ctx, "Colour...") then
            L.colour_target = { lane = lane, row = row }
            L.colour_request = true
        end
        r.ImGui_Separator(UI.ctx)
        if slot.sectioned then
            r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Loops the trimmed length, not the whole file")
        elseif slot.trim_failed then
            r.ImGui_TextColored(UI.ctx, UI.colors.warning or UI.colors.danger, "Loops the whole source: trimming this clip failed")
        end
        if slot.tempo_matched then
            r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Stretched to project tempo on import")
        end
        if r.ImGui_MenuItem(UI.ctx, "Loop clip", nil, slot.loop) then
            slot.loop = not slot.loop
            H.save()
        end
        if r.ImGui_BeginMenu(UI.ctx, "When it has played") then
            for _, option in ipairs(FOLLOW_OPTIONS) do
                if r.ImGui_MenuItem(UI.ctx, option.label, nil, (slot.follow or "stop") == option.key) then
                    slot.follow = option.key
                    H.save()
                end
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_BeginMenu(UI.ctx, "Play " .. tostring(H.clip_plays(slot)) .. "x") then
            for times = 1, 8 do
                if r.ImGui_MenuItem(UI.ctx, tostring(times) .. "x", nil, H.clip_plays(slot) == times) then
                    slot.plays = times
                    H.save()
                end
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_BeginMenu(UI.ctx, "Gain") then
            local db = 20 * math.log(math.max(0.0001, slot.gain or 1), 10)
            r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(160))
            local changed, value = r.ImGui_SliderDouble(UI.ctx, "dB##clip_gain", db, -24, 12, "%.1f")
            if changed then
                slot.gain = (math.abs(value) < 0.05) and nil or 10 ^ (value / 20)
                H.save()
            end
            if r.ImGui_MenuItem(UI.ctx, "Reset to 0 dB") then
                slot.gain = nil
                H.save()
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_BeginMenu(UI.ctx, "Retrigger every", not slot.loop) then
            for _, option in ipairs(REPEAT_OPTIONS) do
                local active = (slot.repeat_qn or 0) == option.qn
                if r.ImGui_MenuItem(UI.ctx, option.label, nil, active) then
                    slot.repeat_qn = option.qn > 0 and option.qn or nil
                    slot.steps = nil
                    H.save()
                end
            end
            local count = H.step_count(slot.repeat_qn)
            if count > 1 then
                r.ImGui_Separator(UI.ctx)
                r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Which steps of the bar fire")
                slot.steps = slot.steps or {}
                for step = 1, count do
                    local on = slot.steps[step] ~= false
                    if on then
                        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
                        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
                    end
                    if r.ImGui_Button(UI.ctx, tostring(step) .. "##step" .. step, UI.rounded(26), UI.rounded(24)) then
                        slot.steps[step] = not on
                        H.save()
                    end
                    if on then r.ImGui_PopStyleColor(UI.ctx, 2) end
                    if step % 8 ~= 0 and step < count then r.ImGui_SameLine(UI.ctx, 0, UI.rounded(3)) end
                end
                if r.ImGui_MenuItem(UI.ctx, "All steps on") then
                    slot.steps = nil
                    H.save()
                end
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_MenuItem(UI.ctx, "Replace with selected item") then
            H.assign_from_selection(lane, row)
        end
        if r.ImGui_MenuItem(UI.ctx, "Replace with file...") then H.pick_file(lane, row) end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Write clip to arrangement at cursor") then H.write_slot(lane, row) end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Clear slot") then
            r.Undo_BeginBlock()
            H.clear_slot(lane, row)
            r.Undo_EndBlock("Clear launcher slot", -1)
            H.save()
            r.UpdateArrange()
        end
    else
        if r.ImGui_MenuItem(UI.ctx, "Add selected item(s) here") then H.assign_from_selection(lane, row) end
        if r.ImGui_MenuItem(UI.ctx, "Add file...") then H.pick_file(lane, row) end
    end
    r.ImGui_EndPopup(UI.ctx)
    return true
end

-- Swatches for speed, a full picker for everything else. ColorEdit4 is given
-- the colour as it is, with only NoInputs: adding NoAlpha changes what format
-- it expects and hands back shifted channels.
function H.draw_colour_popup()
    if L.colour_request then
        r.ImGui_OpenPopup(UI.ctx, "##clip_colour")
        L.colour_request = false
    end
    if not r.ImGui_BeginPopup(UI.ctx, "##clip_colour") then return end
    local target = L.colour_target
    local slot = target and H.slot(target.lane, target.row) or nil
    if not slot then
        r.ImGui_EndPopup(UI.ctx)
        return
    end
    r.ImGui_TextColored(UI.ctx, UI.colors.accent, slot.name)
    r.ImGui_Separator(UI.ctx)
    for index, colour in ipairs(CLIP_COLOURS) do
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), colour)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_ButtonHovered(), H.mix(colour, 0xFFFFFFFF, 0.25))
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_ButtonActive(), colour)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(),
            slot.color == colour and UI.colors.text or UI.colors.border)
        if r.ImGui_Button(UI.ctx, "##colour" .. index, UI.rounded(28), UI.rounded(24)) then
            slot.color = colour
            H.save()
        end
        r.ImGui_PopStyleColor(UI.ctx, 4)
        if index % 6 ~= 0 then r.ImGui_SameLine(UI.ctx, 0, UI.rounded(3)) end
    end
    r.ImGui_Spacing(UI.ctx)
    if r.ImGui_ColorEdit4 then
        local changed, picked = r.ImGui_ColorEdit4(UI.ctx, "Any colour##clip_pick",
            slot.color or H.lane_color(target.lane), r.ImGui_ColorEditFlags_NoInputs())
        if changed then
            slot.color = (picked & 0xFFFFFF00) | 0xFF
            H.save()
        end
    end
    r.ImGui_Separator(UI.ctx)
    if r.ImGui_MenuItem(UI.ctx, "Use the track colour", nil, slot.color == nil) then
        slot.color = nil
        H.save()
    end
    r.ImGui_EndPopup(UI.ctx)
end

function H.draw_cell(lane, lane_index, row)
    local width = UI.rounded(C.cell_w)
    local height = H.cell_height()
    local x, y = r.ImGui_GetCursorScreenPos(UI.ctx)
    r.ImGui_InvisibleButton(UI.ctx, "##launch_cell_" .. lane_index .. "_" .. row, width, height)
    local hovered = r.ImGui_IsItemHovered(UI.ctx)
    local visible = r.ImGui_IsRectVisible(UI.ctx, width, height)
    local draw_list = r.ImGui_GetWindowDrawList(UI.ctx)
    local slot = H.slot(lane, row)
    if hovered then L.hover_cell = { lane = lane, row = row } end
    L.rect_count = (L.rect_count or 0) + 1
    local rect = L.rects[L.rect_count]
    if not rect then rect = {} L.rects[L.rect_count] = rect end
    rect.x1, rect.y1, rect.x2, rect.y2, rect.lane, rect.row = x, y, x + width, y + height, lane, row
    local drop_target = L.drag_path ~= nil and hovered
    -- A clip may carry its own colour; without one it borrows the lane's.
    local color = (slot and slot.color) or H.lane_color(lane)
    local playing = lane.current ~= nil and lane.current.row == row
    local pending = (lane.pending ~= nil and lane.pending.row == row)
        or (lane.queued ~= nil and lane.queued.row == row)
    local blink = (r.time_precise() % 0.6) < 0.3

    local orphaned = H.lane_orphaned(lane) or (slot and slot.missing)
    if orphaned then color = UI.colors.text_dim end
    local background = UI.colors.child_bg
    if slot then background = H.mix(UI.colors.card_bg, color, orphaned and 0.10 or (hovered and 0.34 or 0.20)) end
    if playing then background = H.mix(UI.colors.card_bg, color, 0.62) end
    if pending and blink then background = H.mix(background, 0xFFFFFFFF, 0.22) end

    local border = UI.colors.border
    if playing then border = color elseif pending then border = blink and color or UI.colors.border end
    if slot and slot.missing then border = UI.colors.danger end
    if drop_target then
        border = UI.colors.accent
        background = H.mix(background, UI.colors.accent, 0.35)
    end

    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, background, UI.scaled(4))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, border, UI.scaled(4), 0, (playing or pending or drop_target) and UI.scaled(2) or UI.scaled(1))
    -- Where the keys will land. Drawn inside the border so it never competes
    -- with the state of the cell itself.
    if L.cursor.lane == lane_index and L.cursor.row == row then
        local inset = UI.scaled(3)
        r.ImGui_DrawList_AddRect(draw_list, x + inset, y + inset, x + width - inset, y + height - inset,
            H.readable_on(background), UI.scaled(3), 0, UI.scaled(1))
    end
    H.accept_file_drop(lane, row)

    if not slot then
        if hovered then
            H.text_centered(draw_list, x + width * 0.5, y + height * 0.5, UI.colors.text_dim, "+")
        end
    else
        -- The play position bar owns a strip along the bottom, so nothing else
        -- is laid out into it and the name cannot be struck through.
        local bar_strip = UI.scaled(8)
        local _, text_height = r.ImGui_CalcTextSize(UI.ctx, "A")
        local label_y = math.floor(y + (height - bar_strip - text_height) * 0.5 + 0.5)
        if L.big_cells then
            -- Waveform on top, name underneath, the same reading order as the
            -- cards in the Items view.
            local pad = UI.scaled(4)
            label_y = y + height - bar_strip - text_height - UI.scaled(2)
            if visible and UI.preview then
                local preview_height = (label_y - UI.scaled(4)) - (y + pad)
                if preview_height > UI.scaled(8) then
                    UI.preview(draw_list, H.slot_entry(slot, color), x + pad, y + pad, width - pad * 2, preview_height)
                end
            end
            r.ImGui_DrawList_AddLine(draw_list, x + UI.scaled(4), label_y - UI.scaled(3), x + width - UI.scaled(4), label_y - UI.scaled(3), UI.colors.border, UI.scaled(1))
        end
        local glyph_x = x + UI.scaled(8)
        local glyph_y = label_y + text_height * 0.5
        local size = UI.scaled(4)
        if playing then
            r.ImGui_DrawList_AddRectFilled(draw_list, glyph_x - size * 0.7, glyph_y - size * 0.7, glyph_x + size * 0.7, glyph_y + size * 0.7, color)
        else
            local glyph_color = (slot.loop or slot.repeat_qn) and color or UI.colors.text_dim
            r.ImGui_DrawList_AddTriangleFilled(draw_list, glyph_x - size * 0.6, glyph_y - size, glyph_x - size * 0.6, glyph_y + size, glyph_x + size, glyph_y, glyph_color)
            if slot.repeat_qn then
                r.ImGui_DrawList_AddCircleFilled(draw_list, glyph_x + size * 1.9, glyph_y, size * 0.45, glyph_color)
            end
        end
        r.ImGui_DrawList_AddText(draw_list, x + UI.scaled(20), label_y, UI.colors.text, H.truncate(slot.name, width - UI.scaled(30)))
        if slot.is_midi and not L.big_cells then
            r.ImGui_DrawList_AddRectFilled(draw_list, x + width - UI.scaled(9), y + UI.scaled(9), x + width - UI.scaled(5), y + UI.scaled(13), UI.colors.accent_soft)
        end
        if playing and H.valid_item(lane.current.item) and H.slot_loop(slot) > 0 then
            local heard = H.heard_pos()
            local start = r.GetMediaItemInfo_Value(lane.current.item, "D_POSITION")
            -- For a retriggering one-shot the grid is the beat, not the sample.
            local span = H.slot_loop(slot)
            if span <= 0 then span = slot.length end
            if slot.repeat_qn and start then
                local step = r.TimeMap2_QNToTime(0, r.TimeMap2_timeToQN(0, start) + slot.repeat_qn) - start
                if step > 0 then span = step end
            end
            if heard and start and heard >= start then
                local phase = ((heard - start) % span) / span
                -- Sits clear of the rounded corner, on its own track, in a
                -- colour picked to survive whatever the lane colour is.
                local bar_height = math.max(2, UI.scaled(3))
                local inset = UI.scaled(5)
                local bar_y = y + height - bar_height - UI.scaled(3)
                local bar_left = x + inset
                local bar_right = x + width - inset
                local fill = H.readable_on(background)
                local gutter = (fill & 0xFFFFFF00) | 0x3A
                r.ImGui_DrawList_AddRectFilled(draw_list, bar_left, bar_y, bar_right, bar_y + bar_height, gutter, bar_height * 0.5)
                r.ImGui_DrawList_AddRectFilled(draw_list, bar_left, bar_y, bar_left + (bar_right - bar_left) * phase, bar_y + bar_height, fill, bar_height * 0.5)
            end
        end
    end

    -- Clicking and dragging start with the same press, and by the time a drag is
    -- recognised the clip may already be playing -- with the transport stopped it
    -- starts the moment it is launched. So the two gestures are separated up
    -- front by a held modifier instead of afterwards.
    if L.alt_down then
        if slot then H.begin_clip_drag(lane, row, slot) end
    elseif r.ImGui_IsItemClicked(UI.ctx, 0) then
        L.cursor.lane, L.cursor.row = lane_index, row
        if slot then H.launch(lane, row) else H.assign_from_selection(lane, row) end
    end
    H.slot_context(lane, lane_index, row, slot)
    if hovered and slot then
        local grid_rows = { "QWERTYUI", "ASDFGHJK", "ZXCVBNM," }
        local key_hint = ""
        if row <= 3 and lane_index <= 8 then
            key_hint = "  (key " .. grid_rows[row]:sub(lane_index, lane_index) .. ")"
        end
        local follow_note = ""
        if (slot.follow or "stop") ~= "stop" then
            for _, option in ipairs(FOLLOW_OPTIONS) do
                if option.key == slot.follow then
                    follow_note = "\nPlays " .. tostring(H.clip_plays(slot)) .. "x, then: " .. option.label
                        .. (L.follow_enabled and "" or "  (follow is off)")
                    break
                end
            end
        end
        if slot.missing then
            r.ImGui_SetTooltip(UI.ctx, slot.name .. "\nThis clip is no longer in the project. Redo the deletion to get it\nback, or right-click to clear the slot.")
            return
        end
        r.ImGui_SetTooltip(UI.ctx, slot.name .. key_hint .. follow_note .. "\nClick to launch  |  right-click for options"
            .. "\nAlt-drag to another slot to move it, onto the arrange to place it"
            .. "\nDelete empties the outlined slot"
            .. "\nHold Ctrl while dropping on a slot to copy instead")
    end
end

function H.draw_scene_cell(row)
    local width = UI.rounded(C.scene_w)
    local height = H.cell_height()
    local x, y = r.ImGui_GetCursorScreenPos(UI.ctx)
    r.ImGui_InvisibleButton(UI.ctx, "##launch_scene_" .. row, width, height)
    local hovered = r.ImGui_IsItemHovered(UI.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(UI.ctx)
    local filled = false
    for _, lane in ipairs(L.lanes) do
        if H.slot(lane, row) then filled = true break end
    end
    local background = hovered and UI.colors.card_hover or UI.colors.card_bg
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, background, UI.scaled(4))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, UI.colors.border, UI.scaled(4), 0, UI.scaled(1))
    local label = tostring(row)
    local label_width, label_height = r.ImGui_CalcTextSize(UI.ctx, label)
    local label_x = x + UI.scaled(8)
    r.ImGui_DrawList_AddText(draw_list, label_x, math.floor(y + (height - label_height) * 0.5 + 0.5), filled and UI.colors.text or UI.colors.text_dim, label)
    if filled then
        local glyph_x = x + width - UI.scaled(14)
        local glyph_y = y + height * 0.5
        local size = UI.scaled(4)
        r.ImGui_DrawList_AddTriangleFilled(draw_list, glyph_x - size * 0.6, glyph_y - size, glyph_x - size * 0.6, glyph_y + size, glyph_x + size, glyph_y, UI.colors.accent)
    end
    local bars = H.scene_bars(row)
    if bars then
        -- Only drawn when it actually fits beside the row number: a three digit
        -- bar count in a narrow column would otherwise run into it.
        local text = tostring(bars) .. "b"
        local text_width, text_height = r.ImGui_CalcTextSize(UI.ctx, text)
        local text_x = x + width - text_width - UI.scaled(20)
        if text_x > label_x + label_width + UI.scaled(6) then
            r.ImGui_DrawList_AddText(draw_list, math.floor(text_x + 0.5),
                math.floor(y + (height - text_height) * 0.5 + 0.5), UI.colors.text_dim, text)
        end
    end
    if r.ImGui_IsItemClicked(UI.ctx, 0) then H.launch_scene(row) end
    if r.ImGui_BeginPopupContextItem(UI.ctx, "##launch_scene_ctx_" .. row) then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Scene " .. label .. (bars and ("  |  " .. tostring(bars) .. " bars") or ""))
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Launch scene") then H.launch_scene(row) end
        local settings = H.scene_settings(row)
        if r.ImGui_BeginMenu(UI.ctx, "When it has played") then
            for _, option in ipairs(FOLLOW_OPTIONS) do
                if r.ImGui_MenuItem(UI.ctx, option.label, nil, settings.follow == option.key) then
                    settings.follow = option.key
                    H.save()
                end
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_BeginMenu(UI.ctx, "Play " .. tostring(H.scene_plays(row)) .. "x") then
            for times = 1, 8 do
                if r.ImGui_MenuItem(UI.ctx, tostring(times) .. "x", nil, H.scene_plays(row) == times) then
                    settings.plays = times
                    H.save()
                end
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Write this scene only, at cursor") then H.write_scene(row) end
        if r.ImGui_MenuItem(UI.ctx, "Write the whole chain from here...") then H.ask_write_chain(row) end
        if r.ImGui_MenuItem(UI.ctx, "Fill scene from arrangement at cursor") then H.scene_from_cursor(row) end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Clear scene") then H.clear_scene(row) end
        r.ImGui_EndPopup(UI.ctx)
    end
    if hovered then
        local settings = H.scene_settings(row)
        local follow_label = "Stop"
        for _, option in ipairs(FOLLOW_OPTIONS) do
            if option.key == settings.follow then follow_label = option.label break end
        end
        r.ImGui_SetTooltip(UI.ctx, "Launch scene " .. label .. "  (key " .. tostring(row % 10) .. ")"
            .. (bars and (" (" .. tostring(bars) .. " bars)") or "")
            .. "\nPlays " .. tostring(H.scene_plays(row)) .. "x, then: " .. follow_label
            .. (L.follow_enabled and "" or "  (follow is off)")
            .. "\nRight-click to change that, or to write the chain into the arrangement")
    end
end

function H.draw_lane_header(lane, lane_index)
    local width = UI.rounded(C.cell_w)
    local height = UI.rounded(C.cell_h)
    local x, y = r.ImGui_GetCursorScreenPos(UI.ctx)
    r.ImGui_InvisibleButton(UI.ctx, "##launch_head_" .. lane_index, width, height)
    local hovered = r.ImGui_IsItemHovered(UI.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(UI.ctx)
    local orphaned = H.lane_orphaned(lane)
    local color = orphaned and UI.colors.danger or H.lane_color(lane)
    local owned = lane.owner == "launcher"
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, hovered and UI.colors.card_hover or UI.colors.card_bg, UI.scaled(4))
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + UI.scaled(3), y + height, color, UI.scaled(4))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, (owned or orphaned) and color or UI.colors.border, UI.scaled(4), 0, (owned or orphaned) and UI.scaled(2) or UI.scaled(1))
    r.ImGui_DrawList_AddText(draw_list, x + UI.scaled(10), y + UI.scaled(7), orphaned and UI.colors.danger or (owned and color or UI.colors.text), H.truncate(H.lane_label(lane), width - UI.scaled(56)))

    -- Arrangement toggle for this one track. Drawn on top of the header button
    -- rather than as its own widget, so the header keeps a single ImGui id.
    local silenced = H.lane_silenced(lane)
    local badge = UI.rounded(16)
    local badge_x = math.floor(x + width - UI.scaled(44) + 0.5)
    local badge_y = math.floor(y + (height - badge) * 0.5 + 0.5)
    local badge_hovered = r.ImGui_IsMouseHoveringRect(UI.ctx, badge_x, badge_y, badge_x + badge, badge_y + badge)
    local badge_bg = silenced and UI.colors.danger or (badge_hovered and UI.colors.card_hover or UI.colors.child_bg)
    r.ImGui_DrawList_AddRectFilled(draw_list, badge_x, badge_y, badge_x + badge, badge_y + badge, badge_bg, UI.scaled(3))
    r.ImGui_DrawList_AddRect(draw_list, badge_x, badge_y, badge_x + badge, badge_y + badge, badge_hovered and UI.colors.accent or UI.colors.border, UI.scaled(3), 0, UI.scaled(1))
    H.text_centered(draw_list, badge_x + badge * 0.5, badge_y + badge * 0.5, silenced and UI.colors.badge_text or UI.colors.text_dim, "A")
    if badge_hovered and r.ImGui_IsMouseClicked(UI.ctx, 0) then H.toggle_lane_arrangement(lane) end
    if badge_hovered then
        r.ImGui_SetTooltip(UI.ctx, silenced and "This track's arrangement is muted, clips still play\nClick to let the arrangement through" or "Mute this track's arrangement, keep its clips audible")
    end

    if L.recording or #L.captured > 0 then
        local count = H.captured_for(H.target_track(lane))
        local live = (lane.current and lane.current.started) and "+" or ""
        local text = tostring(count) .. live
        local text_width, text_height = r.ImGui_CalcTextSize(UI.ctx, text)
        r.ImGui_DrawList_AddText(draw_list, x + width - UI.scaled(62) - text_width,
            math.floor(y + (height - text_height) * 0.5 + 0.5),
            count > 0 and UI.colors.accent or UI.colors.text_dim, text)
    end

    local stop_x = x + width - UI.scaled(15)
    local stop_y = y + height * 0.5
    local stop_size = UI.scaled(4)
    r.ImGui_DrawList_AddRectFilled(draw_list, stop_x - stop_size, stop_y - stop_size, stop_x + stop_size, stop_y + stop_size, owned and UI.colors.danger or UI.colors.text_dim)
    if not badge_hovered and r.ImGui_IsItemClicked(UI.ctx, 0) then H.stop_lane(lane) end
    if r.ImGui_BeginPopupContextItem(UI.ctx, "##launch_head_ctx_" .. lane_index) then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, H.lane_label(lane))
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Stop lane") then H.stop_lane(lane) end
        if r.ImGui_MenuItem(UI.ctx, "Mute this track's arrangement", nil, H.lane_silenced(lane)) then
            H.toggle_lane_arrangement(lane)
        end
        if r.ImGui_MenuItem(UI.ctx, "Select target track") then
            local track = H.target_track(lane)
            if track then r.SetOnlyTrackSelected(track) r.UpdateArrange() end
        end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Remove lane and its clips") then
            r.Undo_BeginBlock()
            H.remove_lane(lane_index)
            r.Undo_EndBlock("Remove launcher lane", -1)
            H.save()
            r.UpdateArrange()
        end
        r.ImGui_EndPopup(UI.ctx)
    end
    if hovered then
        r.ImGui_SetTooltip(UI.ctx, H.lane_label(lane) .. (owned and "\nLauncher owns this track  |  click to hand it back" or "\nPlaying its arrangement"))
    end
end

--------------------------------------------------------------------------------
-- public interface
--------------------------------------------------------------------------------

function Launcher.init(context)
    UI = context
    return Launcher
end

function Launcher.set_active(active)
    active = active and true or false
    if active == L.active then return end
    L.active = active
    if active then
        H.project_changed()
        if not L.loaded then H.load() end
        L.track_count = -1
        L.tidy_wanted = true
        L.status = ""
        if L.mute_song_default and not L.arrangement_muted then
            local now = H.schedule_pos()
            H.set_arrangement_muted(true, now or r.GetCursorPosition())
        end
    else
        H.reset_all()
        L.status = ""
    end
end

function Launcher.update()
    if not L.active then return end
    if H.project_changed() then return end
    if not L.loaded then H.load() end
    H.refresh_missing(r.time_precise())
    H.run_file_prompt()
    H.run_chain_prompt()
    H.run_rename_prompt()
    H.update_external_drag()
    H.update_drag_out()
    local track_count = r.CountTracks(0)
    if track_count ~= L.track_count then
        L.track_count = track_count
        L.tidy_wanted = true
    end
    if L.tidy_wanted then H.tidy_lane_tracks() end
    local now = H.schedule_pos()
    if not now then
        if r.time_precise() >= L.roll_guard then
            -- Nothing is rolling, so anything still scheduled lands right away.
            if L.global_switch then H.apply_global_switch() end
            for _, lane in ipairs(L.lanes) do
                if lane.switch then H.apply_switch(lane) end
                H.harvest_lane(lane, true)
            end
        end
        L.last_heard = nil
        return
    end
    if L.global_switch and now >= L.global_switch.at then H.apply_global_switch() end
    H.update_follow()
    if L.record_stop_at then
        local heard = H.heard_pos()
        if not heard then
            H.finish_recording(L.record_stop_at)
        elseif heard >= L.record_stop_at then
            H.finish_recording(L.record_stop_at)
        end
    end
    -- A jump backwards means the arrangement loop came round.
    local heard = H.heard_pos()
    if heard and L.last_heard and heard < L.last_heard - 0.05 then
        for _, lane in ipairs(L.lanes) do H.promote_wrap(lane, heard) end
        H.run_queued(heard)
    end
    L.last_heard = heard
    for _, lane in ipairs(L.lanes) do
        if lane.pending and now >= lane.pending.at then
            -- The outgoing voice was trimmed to end exactly here, but it is
            -- still audible for one output-latency window, so it retires
            -- instead of being deleted straight away.
            if lane.current then
                lane.retired = lane.retired or {}
                lane.retired[#lane.retired + 1] = lane.current
            end
            lane.current = lane.pending
            lane.current.started = true
            lane.pending = nil
            H.build_wrap(lane, lane.current)
            H.begin_clip_run(lane, lane.current)
        end
        if lane.switch and now >= lane.switch.at then H.apply_switch(lane) end
        H.update_clip_follow(lane, now)
        H.sync_gain(lane)
        if heard then
            H.extend_voice(lane, heard)
            H.extend_repeats(lane, heard)
        end
        H.harvest_lane(lane, false)
    end
end

-- Deliberately a panel with an explanation rather than a bare number: this
-- changes a REAPER preference that applies to every project, and it stays
-- changed after this script is closed.
function H.draw_buffer_section()
    local current = H.buffer_ms()
    local original = H.buffer_original()
    r.ImGui_TextColored(UI.ctx, UI.colors.accent, "Media buffer")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "REAPER reads media this far ahead of the play cursor. A clip placed")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "inside that window is missed, so the launcher gives every clip a")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "run-up of the buffer plus a little. A smaller buffer means you can")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "launch closer to the beat; a larger one is safer on a slow disk or")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "a heavy project. It does not affect latency.")
    r.ImGui_Spacing(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.danger, "This is a global REAPER preference, not part of this project.")
    r.ImGui_TextColored(UI.ctx, UI.colors.danger, "It stays changed after you close the launcher.")
    r.ImGui_Spacing(UI.ctx)
    r.ImGui_Separator(UI.ctx)
    if current then
        r.ImGui_Text(UI.ctx, "Now: " .. tostring(current) .. " ms  ->  run-up "
            .. string.format("%.2f", H.auto_lead()) .. " s")
    end
    r.ImGui_Spacing(UI.ctx)
    for _, value in ipairs({ 200, 400, 600, 800, 1200, 2000 }) do
        local label = tostring(value) .. " ms"
        local active = current == value
        if active then
            r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
            r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
        end
        if r.ImGui_Button(UI.ctx, label, UI.rounded(72), UI.rounded(24)) then H.set_buffer_ms(value) end
        if active then r.ImGui_PopStyleColor(UI.ctx, 2) end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "Run-up would become " .. string.format("%.2f", math.max(0.3, math.min(4.0, value / 1000 + 0.3))) .. " s")
        end
        if value ~= 2000 then r.ImGui_SameLine(UI.ctx, 0, UI.rounded(4)) end
    end
    r.ImGui_Spacing(UI.ctx)
    r.ImGui_Separator(UI.ctx)
    if original then
        if r.ImGui_Button(UI.ctx, "Restore your original (" .. tostring(original) .. " ms)", UI.rounded(240), UI.rounded(26)) then
            H.restore_buffer()
        end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "The value this preference had before the launcher first changed it")
        end
    else
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Unchanged by the launcher, so there is nothing to restore.")
    end
end

--------------------------------------------------------------------------------
-- recording the performance
--------------------------------------------------------------------------------

-- What is still sounding when recording stops is most of the take, and it has
-- not been cleared away yet, so it would never reach the capture. A copy of the
-- part that has played is taken instead, and the clip itself carries on.
function H.capture_playing(lane, now)
    local target = H.target_track(lane)
    local lane_track = H.lane_track(lane)
    if not target or not lane_track then return 0, 1 end
    local taken, missed = 0, 0
    local function snapshot(media)
        if not H.valid_item(media) then return end
        local position = r.GetMediaItemInfo_Value(media, "D_POSITION") or 0
        local length = r.GetMediaItemInfo_Value(media, "D_LENGTH") or 0
        if position >= now then return end
        local copy = H.copy_item(media, lane_track, position)
        if not copy then
            missed = missed + 1
            return
        end
        r.SetMediaItemInfo_Value(copy, "D_LENGTH", math.max(0.01, math.min(length, now - position)))
        r.SetMediaItemInfo_Value(copy, "B_MUTE", 1)
        r.SetMediaItemInfo_Value(copy, "B_LOOPSRC", (r.GetMediaItemInfo_Value(media, "B_LOOPSRC") or 0) > 0.5 and 1 or 0)
        if r.UpdateItemInProject then r.UpdateItemInProject(copy) end
        L.captured[#L.captured + 1] = { item = copy, track = target }
        taken = taken + 1
    end
    -- Everything of this lane that is still on the timeline and has sounded,
    -- not only what happens to be the current voice at this instant.
    local function walk(voice)
        if not voice or not voice.started then return end
        snapshot(voice.item)
        snapshot(voice.wrap)
        for _, media in ipairs(voice.hits or {}) do snapshot(media) end
    end
    walk(lane.current)
    for _, voice in ipairs(lane.retired or {}) do walk(voice) end
    return taken, missed
end

-- Counts what the take will hold, not only what has already been gathered: a
-- clip that is sounding right now is part of it too, it just has not finished
-- yet. Without that the counter reads zero while the first clip plays, which
-- looks exactly like recording not working.
function H.take_count()
    local count = #L.captured
    for _, lane in ipairs(L.lanes) do
        if lane.current and lane.current.started then count = count + 1 end
    end
    return count
end

-- The next boundary on the grid, with no run-up applied: this is where the take
-- ends, not where something has to be scheduled.
function H.next_musical_boundary(from)
    if L.quantize <= 0 then return from end
    local step = L.quantize * H.qn_per_bar(from)
    if step <= 0 then return from end
    local index = math.floor(r.TimeMap2_timeToQN(0, from) / step) + 1
    return r.TimeMap2_QNToTime(0, index * step)
end

function H.finish_recording(at)
    L.recording = false
    L.record_stop_at = nil
    local missed, snapped = 0, 0
    if at then
        r.PreventUIRefresh(1)
        for _, lane in ipairs(L.lanes) do
            local lane_taken, lane_missed = H.capture_playing(lane, at)
            snapped = snapped + (lane_taken or 0)
            missed = missed + (lane_missed or 0)
        end
        -- Everything ends on the same line, so the take is a whole number of
        -- bars however the individual clips happened to be running.
        for _, entry in ipairs(L.captured) do
            if H.valid_item(entry.item) then
                local finish = H.item_end(entry.item)
                if finish and finish > at then H.trim_to(entry.item, at) end
            end
        end
        r.PreventUIRefresh(-1)
    end
    -- Muted the moment recording stops, so a captured take cannot sound again
    -- on the next pass while you are still deciding what to do with it.
    for _, entry in ipairs(L.captured) do
        if H.valid_item(entry.item) then r.SetMediaItemInfo_Value(entry.item, "B_MUTE", 1) end
    end
    L.status = #L.captured > 0
        and ("Captured " .. tostring(#L.captured) .. " clips, " .. tostring(snapped)
            .. " of them still playing: keep or discard")
        or "Nothing was captured"
    if missed > 0 then
        L.status = L.status .. "  (" .. tostring(missed) .. " could not be captured)"
    end
    r.UpdateArrange()
end

-- Per lane, what the take holds for it. Shown on the lane header while a take
-- is being made, so a lane that stops contributing is visible at the moment it
-- happens rather than after the fact.
function H.captured_for(track)
    if not track then return 0 end
    local count = 0
    for _, entry in ipairs(L.captured) do
        if entry.track == track then count = count + 1 end
    end
    return count
end

function H.set_recording(on)
    if on then
        L.recording = true
        L.record_stop_at = nil
        L.status = "Recording: clips you play are kept"
        return
    end
    -- Pressed while already winding down: stop where we are instead.
    if L.record_stop_at then
        H.finish_recording(H.heard_pos())
        return
    end
    local heard = H.heard_pos()
    if not heard then
        H.finish_recording(nil)
        return
    end
    L.record_stop_at = H.next_musical_boundary(heard)
    L.status = "Recording stops at the end of this bar"
end

-- Keeping a take means the arrangement it replaced stays replaced. The muted
-- items are handed over: they keep their mute and the launcher stops tracking
-- them, so a later Reset does not bring them back on top of the recording.
-- They are still there, so unmuting them by hand remains possible.
function H.commit_mutes(tracks)
    for _, lane in ipairs(L.lanes) do
        local target = H.target_track(lane)
        if target and tracks[target] then lane.origin_mutes = nil end
    end
    for guid in pairs(L.global_mutes) do
        local item = H.item_from_guid(guid)
        if item and tracks[r.GetMediaItemTrack(item)] then L.global_mutes[guid] = nil end
    end
    H.save_restore_state()
end

function H.keep_take()
    if #L.captured == 0 then return end
    local kept = {}
    local touched = {}
    local total = #L.captured
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for _, entry in ipairs(L.captured) do
        if H.valid_item(entry.item) and H.valid_track(entry.track) then
            r.MoveMediaItemToTrack(entry.item, entry.track)
            r.SetMediaItemInfo_Value(entry.item, "B_MUTE", 0)
            kept[#kept + 1] = entry.item
            touched[entry.track] = true
        end
    end
    H.commit_mutes(touched)
    H.select_written(kept)
    L.captured = {}
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Keep launcher performance", -1)
    r.UpdateArrange()
    L.status = "Kept " .. tostring(#kept) .. " of " .. tostring(total)
        .. " clips on their own tracks; the arrangement they replaced stays muted"
end

function H.discard_take()
    if #L.captured == 0 then return end
    local count = #L.captured
    r.PreventUIRefresh(1)
    for _, entry in ipairs(L.captured) do H.delete_item(entry.item) end
    L.captured = {}
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    L.status = "Discarded " .. tostring(count) .. " captured clips"
end

function H.draw_timing_popup()
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_timing") then return end

    r.ImGui_TextColored(UI.ctx, UI.colors.accent, "Launch quantize")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Clips wait for this boundary on the project's own bar grid.")
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(120))
    local label = "1 bar"
    for _, option in ipairs(QUANTIZE_OPTIONS) do
        if math.abs(option.value - L.quantize) < 0.001 then label = option.label break end
    end
    if r.ImGui_BeginCombo(UI.ctx, "##launch_quantize", label) then
        for _, option in ipairs(QUANTIZE_OPTIONS) do
            local selected = math.abs(option.value - L.quantize) < 0.001
            if r.ImGui_Selectable(UI.ctx, option.label, selected) then
                L.quantize = option.value
                H.save()
            end
            if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
        end
        r.ImGui_EndCombo(UI.ctx)
    end

    r.ImGui_Spacing(UI.ctx)
    r.ImGui_Separator(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.accent, "Clip run-up")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "How far ahead a clip is put on the timeline before it plays. Too")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "little and REAPER has not read its start yet, so the clip comes in")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "late. A launch too close to the boundary waits for the next one.")
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(120))
    local lead_label = "Auto"
    for _, option in ipairs(LEAD_OPTIONS) do
        if math.abs(option.value - (L.lead or 0)) < 0.001 then lead_label = option.label break end
    end
    if r.ImGui_BeginCombo(UI.ctx, "##launch_lead", lead_label) then
        for _, option in ipairs(LEAD_OPTIONS) do
            local selected = math.abs(option.value - (L.lead or 0)) < 0.001
            if r.ImGui_Selectable(UI.ctx, option.label, selected) then
                L.lead = option.value
                H.save()
            end
            if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
        end
        r.ImGui_EndCombo(UI.ctx)
    end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "in use: " .. string.format("%.2f", H.lead()) .. " s")

    if H.buffer_can_write() then
        r.ImGui_Spacing(UI.ctx)
        r.ImGui_Separator(UI.ctx)
        H.draw_buffer_section()
    end
    r.ImGui_EndPopup(UI.ctx)
end

function Launcher.draw_toolbar()
    local gap = UI.rounded(8)
    -- Quantize, run-up and buffer are one subject: when a clip is allowed to
    -- start. They live behind one button, which carries the quantize in its
    -- label because that is the one you reach for mid-jam.
    local quantize_label = "1 bar"
    for _, option in ipairs(QUANTIZE_OPTIONS) do
        if math.abs(option.value - L.quantize) < 0.001 then quantize_label = option.label break end
    end
    if r.ImGui_Button(UI.ctx, "Timing: " .. quantize_label, UI.rounded(120), UI.rounded(26)) then
        r.ImGui_OpenPopup(UI.ctx, "##launch_timing")
    end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Launch quantize, clip run-up and REAPER's media buffer")
    end
    H.draw_timing_popup()

    r.ImGui_SameLine(UI.ctx, 0, gap)
    local following = L.follow_enabled
    if following then
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
    end
    if r.ImGui_Button(UI.ctx, following and "Follow on" or "Follow off", UI.rounded(88), UI.rounded(26)) then
        L.follow_enabled = not following
        if not L.follow_enabled then L.scene_run = nil end
        H.save()
    end
    if following then r.ImGui_PopStyleColor(UI.ctx, 2) end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Whether a scene moves on by itself when it has played its rounds.\nOff means a scene keeps playing until you launch something else, which\nis what you want while building or auditioning; the follow actions\nthemselves stay set.")
    end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    local armed = L.recording
    if armed then
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.danger)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.danger)
    end
    local record_label = "Record"
    if L.record_stop_at then
        record_label = "Stopping"
    elseif armed then
        record_label = "Recording " .. tostring(H.take_count())
    end
    if r.ImGui_Button(UI.ctx, record_label, UI.rounded(armed and 104 or 88), UI.rounded(26)) then
        H.set_recording(not armed)
    end
    if armed then r.ImGui_PopStyleColor(UI.ctx, 2) end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Keep what you play instead of clearing it away.\nClips are already sitting at the right place in time, so this only\nstops them being removed when they finish. Arm it first and then\nplay, or arm it while something is already running; both work.\nThe count includes clips still sounding. Stop to decide what to\ndo with the take.")
    end

    if #L.captured > 0 and not L.recording then
        r.ImGui_SameLine(UI.ctx, 0, gap)
        if r.ImGui_Button(UI.ctx, "Keep " .. tostring(#L.captured), UI.rounded(78), UI.rounded(26)) then H.keep_take() end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "Move the captured clips onto their own tracks and unmute them")
        end
        r.ImGui_SameLine(UI.ctx, 0, UI.rounded(4))
        if r.ImGui_Button(UI.ctx, "Discard", UI.rounded(72), UI.rounded(26)) then H.discard_take() end
    end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    if r.ImGui_Button(UI.ctx, "Stop all", UI.rounded(74), UI.rounded(26)) then H.stop_all_quantized() end
    if r.ImGui_IsItemHovered(UI.ctx) then r.ImGui_SetTooltip(UI.ctx, "Every lane returns to its arrangement on the next boundary") end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    -- Captured before the button: clicking it flips the flag, and testing the
    -- flag again afterwards would skip the pop and unbalance the style stack.
    local song_muted = L.arrangement_muted
    if song_muted then
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
    end
    if r.ImGui_Button(UI.ctx, song_muted and "Song muted" or "Mute song", UI.rounded(102), UI.rounded(26)) then
        H.toggle_arrangement_mute()
    end
    if song_muted then r.ImGui_PopStyleColor(UI.ctx, 2) end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Silence the whole arrangement while the launcher keeps playing.\nMutes the items, not the tracks, so the clips still come through.")
    end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    if r.ImGui_Button(UI.ctx, "Reset", UI.rounded(66), UI.rounded(26)) then H.reset_all() end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Everything back to normal, right now.\nClips stop, every muted arrangement item is restored,\nper track mutes are cleared and the song mute goes off.\nPlayback keeps rolling.")
    end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    if r.ImGui_Button(UI.ctx, "+ Lane", UI.rounded(66), UI.rounded(26)) then
        local count = r.CountSelectedTracks(0)
        if count == 0 then
            L.status = "Select one or more tracks in REAPER first"
        else
            r.Undo_BeginBlock()
            r.PreventUIRefresh(1)
            for index = 0, count - 1 do H.add_lane(r.GetSelectedTrack(0, index)) end
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("Add launcher lane", -1)
            H.tidy_lane_tracks()
            r.TrackList_AdjustWindows(false)
            H.save()
            L.status = "Lane added"
        end
    end
    if r.ImGui_IsItemHovered(UI.ctx) then r.ImGui_SetTooltip(UI.ctx, "Create a launcher lane for every selected track") end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    if r.ImGui_Button(UI.ctx, "+ Scene", UI.rounded(76), UI.rounded(26)) then
        H.scene_from_cursor(nil)
    end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Take a slice of the arrangement at the edit cursor into the next free row.\nWhatever each track is playing there becomes a clip, and tracks without a lane get one.")
    end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    if r.ImGui_Button(UI.ctx, "-", UI.rounded(24), UI.rounded(26)) then
        if L.rows > 1 then L.rows = L.rows - 1 H.save() end
    end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(3))
    r.ImGui_Text(UI.ctx, tostring(L.rows))
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(3))
    if r.ImGui_Button(UI.ctx, "+", UI.rounded(24), UI.rounded(26)) then
        if L.rows < C.max_rows then L.rows = L.rows + 1 H.save() end
    end
    if r.ImGui_IsItemHovered(UI.ctx) then r.ImGui_SetTooltip(UI.ctx, "Number of scene rows") end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    local tempo_sync = L.tempo_sync
    if tempo_sync then
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
    end
    if r.ImGui_Button(UI.ctx, "Sync BPM", UI.rounded(84), UI.rounded(26)) then
        L.tempo_sync = not L.tempo_sync
        H.save()
    end
    if tempo_sync then r.ImGui_PopStyleColor(UI.ctx, 2) end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Stretch imported audio to the project tempo, pitch preserved.\nUses the tempo in the file's metadata or its name; applies on import.")
    end

    local orphans = H.orphan_count()
    if orphans > 0 then
        r.ImGui_SameLine(UI.ctx, 0, gap)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.danger)
        local label = orphans == 1 and "Remove 1 dead lane" or ("Remove " .. tostring(orphans) .. " dead lanes")
        if r.ImGui_Button(UI.ctx, label, UI.rounded(150), UI.rounded(26)) then H.remove_orphan_lanes() end
        r.ImGui_PopStyleColor(UI.ctx, 1)
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "Their track was deleted, so these lanes can never sound again.\nUndo the track deletion instead and they come back by themselves.")
        end
    end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    local lanes_shown = H.lanes_visible()
    if lanes_shown then
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
    end
    if r.ImGui_Button(UI.ctx, lanes_shown and "Hide tracks" or "Show tracks", UI.rounded(96), UI.rounded(26)) then
        H.set_lanes_visible(not lanes_shown)
    end
    if lanes_shown then r.ImGui_PopStyleColor(UI.ctx, 2) end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Show or hide the TK LAUNCHER folder and its lane tracks in the arrange view.\nThey stay out of the mixer either way.")
    end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    if r.ImGui_Button(UI.ctx, L.big_cells and "Waveforms" or "Compact", UI.rounded(92), UI.rounded(26)) then
        L.big_cells = not L.big_cells
        H.save(true)
    end
    if r.ImGui_IsItemHovered(UI.ctx) then r.ImGui_SetTooltip(UI.ctx, "Switch between waveform cells and a dense name-only grid") end

    r.ImGui_SameLine(UI.ctx, 0, gap)
    local heard = H.heard_pos()
    local bar = H.song_bar(heard)
    if bar then
        r.ImGui_TextColored(UI.ctx, UI.colors.accent, "Bar " .. tostring(bar))
    else
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Stopped")
    end
end

-- ImGui scrolls horizontally on shift plus wheel by itself, but only when it
-- decides the region qualifies. Ctrl plus wheel is handled here so there is a
-- modifier that always works, and ctrl is not spoken for elsewhere in the grid.
--------------------------------------------------------------------------------
-- playing it from the keyboard
--------------------------------------------------------------------------------
-- Three blocks of keys, built once and only from names this ReaImGui actually
-- has, so a missing one drops out instead of taking the script down.

function H.key(name)
    local getter = r["ImGui_Key_" .. name]
    if not getter then return nil end
    local ok, value = pcall(getter)
    if ok then return value end
    return nil
end

function H.build_keys()
    if L.keys then return L.keys end
    local keys = { scenes = {}, grid = {} }
    for index, name in ipairs({ "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }) do
        keys.scenes[index] = H.key(name)
    end
    local rows = {
        { "Q", "W", "E", "R", "T", "Y", "U", "I" },
        { "A", "S", "D", "F", "G", "H", "J", "K" },
        { "Z", "X", "C", "V", "B", "N", "M", "Comma" },
    }
    for row, names in ipairs(rows) do
        keys.grid[row] = {}
        for column, name in ipairs(names) do keys.grid[row][column] = H.key(name) end
    end
    keys.left = H.key("LeftArrow")
    keys.right = H.key("RightArrow")
    keys.up = H.key("UpArrow")
    keys.down = H.key("DownArrow")
    keys.undo = H.key("Z")
    keys.redo = H.key("Y")
    keys.enter = H.key("Enter")
    keys.delete = H.key("Delete")
    keys.backspace = H.key("Backspace")
    keys.keypad_enter = H.key("KeypadEnter")
    L.keys = keys
    return keys
end

function H.pressed(key)
    if not key then return false end
    return r.ImGui_IsKeyPressed(UI.ctx, key)
end

-- Emptying a slot from the keyboard. It goes through the undo history like the
-- menu does, so a mistaken press is one Ctrl+Z away.
function H.clear_cell(lane_index, row)
    local lane = L.lanes[lane_index]
    local slot = lane and H.slot(lane, row) or nil
    if not slot then return end
    local name = slot.name
    r.Undo_BeginBlock()
    H.clear_slot(lane, row)
    r.Undo_EndBlock("Clear launcher slot", -1)
    H.save()
    r.UpdateArrange()
    L.status = "Cleared " .. name
end

function H.fire_cell(lane_index, row, stop)
    local lane = L.lanes[lane_index]
    if not lane then return end
    if stop then
        H.stop_lane(lane)
    elseif H.slot(lane, row) then
        H.launch(lane, row)
    else
        H.assign_from_selection(lane, row)
    end
end

-- The letter block is a launchpad: three rows by eight lanes, reachable with two
-- hands. Everything beyond that is reachable with the arrows, so a big grid is
-- never out of reach even though the block does not grow.
function H.handle_keys()
    if not r.ImGui_IsKeyPressed or #L.lanes == 0 then return end
    if r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(UI.ctx) then return end
    -- Ctrl or Alt held means the key belongs to a shortcut, not to the grid.
    -- Without this, Ctrl+Z launches whatever sits on the Z key instead of
    -- undoing, and the same goes for every other combination.
    local ctrl, alt, shift_held = false, false, false
    if r.JS_Mouse_GetState then
        local mods = r.JS_Mouse_GetState(4 | 8 | 16)
        ctrl = (mods & 4) == 4
        shift_held = (mods & 8) == 8
        alt = (mods & 16) == 16
    end
    if ctrl or alt then
        -- REAPER never sees these while this window has focus, so undo and redo
        -- are passed on rather than swallowed. Everything else under a modifier
        -- is simply left alone.
        local keys = H.build_keys()
        if ctrl and not alt then
            if keys.undo and r.ImGui_IsKeyPressed(UI.ctx, keys.undo) then
                r.Main_OnCommand(shift_held and 40030 or 40029, 0)
            elseif keys.redo and r.ImGui_IsKeyPressed(UI.ctx, keys.redo) then
                r.Main_OnCommand(40030, 0)
            end
        end
        return
    end
    local keys = H.build_keys()
    local cursor = L.cursor
    cursor.lane = math.max(1, math.min(#L.lanes, cursor.lane or 1))
    cursor.row = math.max(1, math.min(L.rows, cursor.row or 1))
    local shift = r.JS_Mouse_GetState and (r.JS_Mouse_GetState(8) & 8) == 8

    if H.pressed(keys.left) then cursor.lane = math.max(1, cursor.lane - 1) end
    if H.pressed(keys.right) then cursor.lane = math.min(#L.lanes, cursor.lane + 1) end
    if H.pressed(keys.up) then cursor.row = math.max(1, cursor.row - 1) end
    if H.pressed(keys.down) then cursor.row = math.min(L.rows, cursor.row + 1) end
    if H.pressed(keys.enter) or H.pressed(keys.keypad_enter) then
        H.fire_cell(cursor.lane, cursor.row, shift)
    end
    if H.pressed(keys.delete) or H.pressed(keys.backspace) then
        H.clear_cell(cursor.lane, cursor.row)
    end

    for row, names in ipairs(keys.grid) do
        for column, key in ipairs(names) do
            if H.pressed(key) and L.lanes[column] and row <= L.rows then
                cursor.lane, cursor.row = column, row
                H.fire_cell(column, row, shift)
            end
        end
    end

    for row, key in ipairs(keys.scenes) do
        if H.pressed(key) and row <= L.rows then
            cursor.row = row
            if shift then H.stop_all_quantized() else H.launch_scene(row) end
        end
    end
end

function H.wheel_scroll()
    if not r.ImGui_GetMouseWheel or not r.ImGui_SetScrollX then return end
    if not r.ImGui_IsWindowHovered(UI.ctx) then return end
    local ctrl = r.JS_Mouse_GetState and (r.JS_Mouse_GetState(4) & 4) == 4
    if not ctrl then return end
    local vertical = r.ImGui_GetMouseWheel(UI.ctx)
    if not vertical or vertical == 0 then return end
    local step = UI.rounded(C.cell_w) * 0.75
    r.ImGui_SetScrollX(UI.ctx, r.ImGui_GetScrollX(UI.ctx) - vertical * step)
end

function Launcher.draw()
    if not L.loaded then H.load() end
    if #L.lanes == 0 then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "No launcher lanes yet.")
        r.ImGui_Spacing(UI.ctx)
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "1. Select the track you want to play clips through in REAPER.")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "2. Press \"+ Lane\" above to create a hidden lane that feeds it.")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "3. Fill a slot: drag a file onto it from a media browser, click it with items")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "   selected in the arrange view, or right-click it for \"Add file...\".")
        r.ImGui_Spacing(UI.ctx)
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Alt-drag a clip out of the grid to drop it into the arrange.")
        r.ImGui_Spacing(UI.ctx)
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Keys: 1-0 launch scenes. QWERTY / ASDFGH / ZXCVBN launch the first three")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "rows of the first eight lanes. Arrows move the outlined cell, Enter fires it,")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Delete empties it. Holding Shift turns a launch into a stop. Ctrl or Alt means the")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "key is a shortcut, not a clip: Ctrl+Z undoes, Ctrl+Y or Ctrl+Shift+Z redoes.")
        r.ImGui_Spacing(UI.ctx)
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Launching a clip mutes that track's arrangement items until you hand it back;")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "every other track keeps playing the song.")
        return
    end

    H.draw_colour_popup()
    L.hover_cell = nil
    L.rect_count = 0
    L.alt_down = r.JS_Mouse_GetState and (r.JS_Mouse_GetState(16) & 16) == 16 or false
    L.over_ui = r.ImGui_IsWindowHovered and r.ImGui_IsWindowHovered(UI.ctx, r.ImGui_HoveredFlags_AnyWindow()) or false
    local columns = #L.lanes + 1
    -- The table owns both scroll directions, which is what lets it freeze the
    -- scene column and the lane headers: a frozen row is only possible when the
    -- table is the thing scrolling, not the window around it.
    local flags = r.ImGui_TableFlags_SizingFixedFit()
        | r.ImGui_TableFlags_ScrollX() | r.ImGui_TableFlags_ScrollY()
    local hidden = UI.hide_scrollbar and UI.hide_scrollbar() or false
    if hidden and r.ImGui_StyleVar_ScrollbarSize then
        r.ImGui_PushStyleVar(UI.ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    end
    if r.ImGui_BeginTable(UI.ctx, "launcher_grid", columns, flags) then
        r.ImGui_TableSetupColumn(UI.ctx, "##scene", r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(C.scene_w))
        for lane_index = 1, #L.lanes do
            r.ImGui_TableSetupColumn(UI.ctx, "##lane" .. lane_index, r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(C.cell_w))
        end
        if r.ImGui_TableSetupScrollFreeze then r.ImGui_TableSetupScrollFreeze(UI.ctx, 1, 1) end
        H.wheel_scroll()
        H.handle_keys()
        r.ImGui_TableNextRow(UI.ctx)
        r.ImGui_TableNextColumn(UI.ctx)
        r.ImGui_Dummy(UI.ctx, UI.rounded(C.scene_w), UI.rounded(C.cell_h))
        for lane_index, lane in ipairs(L.lanes) do
            r.ImGui_TableNextColumn(UI.ctx)
            r.ImGui_PushID(UI.ctx, lane_index)
            H.draw_lane_header(lane, lane_index)
            r.ImGui_PopID(UI.ctx)
        end
        for row = 1, L.rows do
            r.ImGui_TableNextRow(UI.ctx)
            r.ImGui_TableNextColumn(UI.ctx)
            H.draw_scene_cell(row)
            for lane_index, lane in ipairs(L.lanes) do
                r.ImGui_TableNextColumn(UI.ctx)
                r.ImGui_PushID(UI.ctx, lane_index * 1000 + row)
                H.draw_cell(lane, lane_index, row)
                r.ImGui_PopID(UI.ctx)
            end
        end
        r.ImGui_EndTable(UI.ctx)
    end
    if hidden and r.ImGui_StyleVar_ScrollbarSize then r.ImGui_PopStyleVar(UI.ctx) end
    -- Cleared after every cell has had its chance to see the release.
end

function Launcher.status()
    return L.status
end

function Launcher.is_active()
    return L.active
end

function Launcher.shutdown()
    -- Captured clips live on the hidden lane tracks until they are kept, and the
    -- sweep on the next load would remove them without a word. Better to drop
    -- them here, where the button that could have saved them was in plain sight.
    H.discard_take()
    L.recording = false
    L.record_stop_at = nil
    if not L.active then return end
    H.reset_all()
    L.active = false
end

return Launcher
