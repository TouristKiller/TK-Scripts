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
    -- Beat counts a loop of unknown tempo is allowed to be. Powers of two only:
    -- adding 3, 6 and 12 for waltz time makes the field so dense that a plain
    -- four-beat loop starts matching six beats at a wrong tempo instead.
    guess_beats  = { 2, 4, 8, 16, 32, 64 },
    sep          = package.config:sub(1, 1),
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
    key               = nil,      -- the session's key, nil until one is set
    key_style         = "scale",  -- "scale" maps degrees, "root" only transposes
    key_sync          = true,
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
    -- Negative means beats rather than bars: see H.quantize_qn. In 4/4 it lands
    -- on the same grid as 1/4; in 7/8 it is the only one that makes sense.
    { label = "1 beat", value = -1 },
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
local function channel_luminance(value)
    local level = value / 255
    if level <= 0.03928 then return level / 12.92 end
    return ((level + 0.055) / 1.055) ^ 2.4
end

function H.luminance(color)
    return 0.2126 * channel_luminance((color >> 24) & 0xFF)
        + 0.7152 * channel_luminance((color >> 16) & 0xFF)
        + 0.0722 * channel_luminance((color >> 8) & 0xFF)
end

-- The WCAG contrast ratio, 1 for two identical colours and 21 for black on white.
function H.contrast(first, second)
    local lighter, darker = H.luminance(first), H.luminance(second)
    if lighter < darker then lighter, darker = darker, lighter end
    return (lighter + 0.05) / (darker + 0.05)
end

-- Whichever ink reads better on this background, measured rather than guessed
-- from a brightness threshold. A threshold gets the mid tones wrong, and those
-- are exactly the track colours: a middle grey scores 3.9 with the white a
-- threshold picks and 4.6 with the dark ink it passes over.
function H.readable_on(background)
    local dark, light = 0x14171CFF, 0xFFFFFFFF
    if H.contrast(dark, background) >= H.contrast(light, background) then return dark end
    return light
end

-- A colour can land in the dead zone where neither ink clears the readability
-- bar however it is chosen. A flat middle grey is the worst of them, at 4.49
-- against the 4.5 the standard asks for. Such a fill is shaded away from its own
-- ink until it clears, which costs a shift you can barely see in exactly the
-- colours where the alternative is text you have to squint at. Returns the fill
-- to paint and the ink to write on it.
function H.legible_fill(color)
    local ink = H.readable_on(color)
    local fill, guard = color, 0
    while H.contrast(ink, fill) < 4.5 and guard < 8 do
        fill = H.mix(fill, H.away_from(ink), 0.06)
        guard = guard + 1
    end
    return fill, H.readable_on(fill)
end

-- The ink's opposite. Shading a background towards it deepens the contrast the
-- ink already has, so a hover or a raised tile gets its visible change for free
-- instead of paying for it in readability - which is what shading towards the
-- ink does, and it costs exactly the tenth of a point that fails the standard.
function H.away_from(ink)
    if ink == 0xFFFFFFFF then return 0x14171CFF end
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

-- The launch grid in quarter notes at this point in the song, or 0 for off. A
-- negative setting means one denominator unit - an eighth in 6/8, a quarter in
-- 4/4 - which is what the meter itself counts, where a fraction of a bar is a
-- number an odd meter cannot use.
function H.quantize_qn(time)
    local value = L.quantize or 1
    if value == 0 then return 0 end
    if value < 0 then
        local _, denom = r.TimeMap_GetTimeSigAtTime(0, time)
        denom = (denom and denom > 0) and denom or 4
        return 4 / denom
    end
    return value * H.qn_per_bar(time)
end

function H.boundary_after(from_time, allow_now)
    local step = H.quantize_qn(from_time)
    if step <= 0 then
        return allow_now and from_time or (from_time + H.lead())
    end
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

-- Lanes set aside by H.follow_track_list because their track went. Their clips
-- are still on a hidden track, waiting for an undo to bring the track back.
-- Only the ones whose track is really gone. A lane set aside because its track
-- is merely hidden from the panel is not lost and must never be offered up for
-- deletion - unhiding the track brings it straight back.
function H.orphan_count()
    local count = 0
    for guid in pairs(L.orphans or {}) do
        if not H.track_from_guid(guid) then count = count + 1 end
    end
    return count
end

-- Only when the user says so. Undoing the track deletion is the other way out
-- of this, and it is the one that keeps the clips.
function H.forget_orphans()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local removed = 0
    for guid, lane in pairs(L.orphans or {}) do
        if not H.track_from_guid(guid) then
            local track = H.lane_track(lane)
            if track then r.DeleteTrack(track) end
            L.orphans[guid] = nil
            removed = removed + 1
        end
    end
    H.prune_folder()
    H.fix_folder_depths()
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Forget launcher lanes", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    H.save()
    L.status = removed == 1 and "Forgot 1 lane" or ("Forgot " .. tostring(removed) .. " lanes")
end

function H.lane_label(lane)
    local track = H.target_track(lane)
    if not track then return lane.name .. " (missing)" end
    return H.track_name(track, lane.name)
end

-- What a hidden track is called. Named here rather than at the point of
-- creation so that renaming the track it feeds can keep it in step without the
-- two spellings drifting apart.
function H.lane_track_name(target)
    return "TK Launcher: " .. H.track_name(target, "Track")
end

function H.create_lane_track(target)
    local index = r.CountTracks(0)
    r.InsertTrackAtIndex(index, false)
    local track = r.GetTrack(0, index)
    if not track then return nil end
    r.GetSetMediaTrackInfo_String(track, "P_NAME", H.lane_track_name(target), true)
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

-- Behind the project, the hidden tracks should read in the same order as the
-- lanes they feed. Moving the block to the end keeps whatever order they were
-- made in, which since they are made at the first clip and taken away at the
-- last is the order clips happened to be dropped in.
function H.lane_tracks_need_order()
    local previous = 0
    for _, lane in ipairs(L.lanes) do
        local track = H.lane_track(lane)
        if track then
            local number = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
            if number < previous then return true end
            previous = number
        end
    end
    return false
end

function H.tidy_lane_tracks()
    if not r.ReorderSelectedTracks then return end
    if not H.lanes_need_tidy() and not H.lane_tracks_need_order() then
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
    -- One at a time, walking the lanes in order: each move puts that track last,
    -- so the one moved last ends up last. That leaves the block behind the
    -- project and in lane order in the same pass. Anything set aside - a lane
    -- whose track went - is swept up first, so it cannot land in the middle.
    local strays = {}
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if H.is_lane_track(track) then strays[track] = true end
    end
    local ordered = {}
    for _, lane in ipairs(L.lanes) do
        local track = H.lane_track(lane)
        if track then
            strays[track] = nil
            ordered[#ordered + 1] = track
        end
    end
    local function send_to_back(track)
        r.SetTrackSelected(track, true)
        r.ReorderSelectedTracks(r.CountTracks(0), 0)
        r.SetTrackSelected(track, false)
    end
    for track in pairs(strays) do
        if H.valid_track(track) then send_to_back(track) end
    end
    for _, track in ipairs(ordered) do
        if H.valid_track(track) then send_to_back(track) end
    end
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

-- A lane is a row against a track, and nothing more until it holds a clip. The
-- hidden track that carries the clips is made by H.ensure_lane_track when the
-- first one lands: every track has a lane now, and a project full of empty rows
-- has no business being a project full of empty tracks.
function H.add_lane(target)
    if not H.valid_track(target) then return nil end
    local existing = H.lane_for_track(target)
    if existing then return existing end
    local lane = {
        name = H.track_name(target, "Track"),
        track_guid = r.GetTrackGUID(target),
        slots = {},
        owner = "arrangement",
    }
    L.lanes[#L.lanes + 1] = lane
    return lane
end

-- Made on demand, and only where a clip is actually being put into the lane.
-- Everywhere else a missing lane track means the lane is empty, which the
-- callers already had to cope with for a lane whose track the user deleted.
function H.ensure_lane_track(lane)
    if not lane then return nil end
    local track = H.lane_track(lane)
    if track then return track end
    local target = H.target_track(lane)
    if not target then return nil end
    track = H.create_lane_track(target)
    if not track then return nil end
    lane.lane_guid = r.GetTrackGUID(track)
    L.tidy_wanted = true
    return track
end

-- Every slot emptied, the lane itself left standing. Removing a lane is not a
-- thing any more - that is deleting the track - so this is what the menu offers
-- in its place.
function H.clear_lane(lane)
    if not lane then return 0 end
    local cleared = 0
    for index = #lane.slots, 1, -1 do
        local slot = lane.slots[index]
        if slot then
            H.clear_slot(lane, slot.row)
            cleared = cleared + 1
        end
    end
    H.prune_lane_track(lane)
    return cleared
end

-- The other half of making the hidden track only when a clip needs one: when
-- the last clip goes, the track goes with it, and the next clip makes a fresh
-- one. Called only from the routes where the user emptied something, so it
-- lands inside their own undo step - a sweep of its own would delete the track
-- a frame later and cost two undos to get a clip back.
--
-- The item count is checked rather than trusted: a voice still sounding, a wrap
-- copy or a stray left by a previous session all live on this track, and none
-- of them are slots.
function H.prune_lane_track(lane)
    if not lane or not lane.lane_guid then return false end
    if #lane.slots > 0 then return false end
    if lane.current or lane.pending or lane.switch or lane.hold then return false end
    local track = H.lane_track(lane)
    if not track then
        lane.lane_guid = nil
        return false
    end
    if (r.CountTrackMediaItems(track) or 0) > 0 then return false end
    H.release_now(lane)
    r.DeleteTrack(track)
    lane.lane_guid = nil
    H.prune_folder()
    H.fix_folder_depths()
    return true
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
    local lane_track = H.ensure_lane_track(lane)
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

-- Last resort for a file that states its tempo nowhere: assume it is a loop of a
-- whole number of beats and read the tempo back out of its length. Which count
-- it is cannot be known - a 4 beat loop at 90 and an 8 beat loop at 180 are the
-- same audio - so the candidate that needs the least stretching wins. Never
-- fewer than two beats, which is what keeps a one-shot off the grid, and never
-- more than double or half speed, because past that the guess is worthless.
-- A long one-shot can still be caught by this; that is what the clip menu's
-- "Play at original speed" is for.
function H.guess_bpm(source)
    local project_bpm = r.Master_GetTempo and r.Master_GetTempo() or nil
    if not project_bpm or project_bpm <= 0 then return nil end
    local length, length_is_qn = r.GetMediaSourceLength(source)
    if not length or length <= 0 or length_is_qn then return nil end
    -- Only guess inside the window a loop actually lives in. Under a second it is
    -- a drum hit; over twenty it is a stem, an ambience or a recording, none of
    -- which should be quietly resampled. Both bounds are odds, not proof: a long
    -- one-shot inside the window still reads as a loop to anything that has only
    -- the length to go on.
    if length < 1.0 or length > 20.0 then return nil end
    local best, best_distance = nil, nil
    for _, beats in ipairs(C.guess_beats) do
        local bpm = beats * 60 / length
        if bpm >= 50 and bpm <= 220 then
            -- Compared in log space so that half speed and double speed count as
            -- equally far off, which they are.
            local distance = math.abs(math.log(bpm / project_bpm))
            if not best_distance or distance < best_distance then
                best, best_distance = bpm, distance
            end
        end
    end
    if not best then return nil end
    local rate = project_bpm / best
    if rate < 0.5 or rate > 2 then return nil end
    return best
end

-- Same metadata keys the TK media browsers read, so a file dropped here lands at
-- the same rate it would when dropped straight into the arrange. The file name
-- is a second chance: loop packs often carry the tempo only in the name. Returns
-- the tempo and whether it had to be guessed.
function H.file_bpm(source, path)
    if r.GetMediaFileMetadata then
        -- An ACID one-shot says outright that it is not a loop. Stretching one
        -- to the grid is always wrong, whatever else the file claims.
        local flagged, one_shot = r.GetMediaFileMetadata(source, "ACID:oneshot")
        if flagged and flagged ~= 0 and one_shot and one_shot ~= "" and one_shot ~= "0" then
            return nil
        end
        local keys = { "ACID:tempo", "ID3:TBPM", "VORBIS:BPM", "VORBIS:TEMPO", "XMP:dm/tempo" }
        for _, key in ipairs(keys) do
            local ok, value = r.GetMediaFileMetadata(source, key)
            if ok and ok ~= 0 and value and value ~= "" then
                local bpm = tonumber((tostring(value):gsub(",", "."):match("[%d%.]+")))
                if bpm and bpm > 0 then return bpm end
            end
        end
        -- Plenty of ACID loops carry the beat count but no tempo. With the
        -- source length that is an exact reading, not a guess.
        local counted, beats = r.GetMediaFileMetadata(source, "ACID:beats")
        beats = counted and counted ~= 0 and tonumber((tostring(beats or ""):match("[%d%.]+"))) or nil
        if beats and beats > 0 then
            local length, length_is_qn = r.GetMediaSourceLength(source)
            if length and length > 0 and not length_is_qn then
                local bpm = beats * 60 / length
                if bpm >= 20 and bpm <= 400 then return bpm end
            end
        end
    end
    local name = ((path or ""):match("([^/\\]+)$") or ""):lower()
    local bpm = tonumber(name:match("(%d+%.?%d*)%s*bpm")) or tonumber(name:match("bpm[%s_%-]*(%d+%.?%d*)"))
    if bpm and bpm >= 40 and bpm <= 300 then return bpm end
    local guessed = H.guess_bpm(source)
    if guessed then return guessed, true end
    return nil
end

-- Returns the playrate that puts this file at the project tempo, and whether the
-- tempo behind it was guessed rather than read. Nil when it should not stretch.
function H.tempo_match_rate(source, path)
    if not L.tempo_sync then return nil end
    local file_bpm, guessed = H.file_bpm(source, path)
    if not file_bpm then return nil end
    local project_bpm = r.Master_GetTempo and r.Master_GetTempo() or nil
    if not project_bpm or project_bpm <= 0 then return nil end
    local rate = project_bpm / file_bpm
    if rate < 0.05 or rate > 20 or math.abs(rate - 1) < 0.0005 then return nil end
    return rate, guessed
end

-- Build a library item straight from a file. Deliberately not InsertMedia: that
-- one works off the edit cursor and the track selection, both of which belong to
-- the user while they are jamming.
function H.assign_path(lane, row, path)
    local lane_track = H.ensure_lane_track(lane)
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
    local matched_bpm, guessed_bpm = nil, nil
    if not is_midi then
        local rate, guessed = H.tempo_match_rate(source, path)
        if rate then
            r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
            r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
            length = (length or 0) / rate
            matched_bpm = true
            guessed_bpm = guessed and true or nil
        end
    end
    length = math.max(0.05, length or 0.05)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
    r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
    local name = path:match("([^/\\]+)$") or path
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
    local key_from_file, key_origin = H.file_key(source, path)
    lane.slots[#lane.slots + 1] = {
        row = row,
        guid = r.BR_GetMediaItemGUID(item),
        name = name,
        is_midi = is_midi,
        length = length,
        loop = true,
        loop_len = length,
        tempo_matched = matched_bpm and true or nil,
        tempo_guessed = guessed_bpm,
        key = key_from_file,
    }
    -- A MIDI file says nothing about itself, so where the name did not either,
    -- the notes are asked. Audio is left alone: without the notes there is
    -- nothing to read and a guess from a waveform would be a coin toss.
    if is_midi then
        local slot = lane.slots[#lane.slots]
        if not slot.key or key_origin == "folder" then
            -- The notes outrank a shelf label. A pack files a mixolydian vamp
            -- under "A major" because it has nowhere else to put it, and taking
            -- that literally would map its flat seventh as a major seventh.
            local from_notes = H.notes_key(take)
            if from_notes then
                slot.key = from_notes
                slot.key_guessed = true
            elseif key_origin == "folder" then
                -- Notes that fit no scale cannot carry the folder's claim about
                -- the mode, but its root is the very thing they could not give.
                slot.root = slot.key.root
                slot.key = nil
            end
        end
    end
    -- Quietly: an import can bring in dozens of clips and the status line is not
    -- a log. What was fitted is visible in each clip's own menu.
    if is_midi and L.key_sync then H.fit_slot_to_key(lane, row, true) end
    return true
end

-- Sets the library item's playrate and keeps its length honest: the item covers
-- the same audio, so the length moves with the rate it is played at. Everything
-- downstream reads the length back off the item, so nothing else needs telling.
function H.set_slot_rate(lane, row, rate)
    local slot = H.slot(lane, row)
    local item = slot and H.item_from_guid(slot.guid) or nil
    local take = item and r.GetActiveTake(item) or nil
    if not take or not rate or rate <= 0 then return false end
    local current = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
    if current <= 0 then current = 1 end
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    r.Undo_BeginBlock()
    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
    r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
    if length > 0 then
        r.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.05, length * current / rate))
    end
    r.Undo_EndBlock("Change launcher clip playrate", -1)
    r.UpdateArrange()
    slot.tempo_matched = math.abs(rate - 1) > 0.0005 and true or nil
    if not slot.tempo_matched then slot.tempo_guessed = nil end
    H.save()
    return true
end

-- The manual half of Sync BPM, from the clip menu: for a clip that came in
-- unstretched because the toggle was off at the time, or that was played back at
-- its original speed and should be fitted after all.
function H.fit_slot_to_tempo(lane, row)
    local slot = H.slot(lane, row)
    local item = slot and H.item_from_guid(slot.guid) or nil
    local take = item and r.GetActiveTake(item) or nil
    local source = take and r.GetMediaItemTake_Source(take) or nil
    if not source then return false end
    local path = nil
    if r.GetMediaSourceFileName then
        local name = r.GetMediaSourceFileName(source)
        if type(name) == "string" and name ~= "" then path = name end
    end
    local bpm, guessed = H.file_bpm(source, path)
    local project_bpm = r.Master_GetTempo and r.Master_GetTempo() or nil
    if not bpm or not project_bpm or project_bpm <= 0 then
        L.status = "No tempo to read from that clip"
        return false
    end
    local rate = project_bpm / bpm
    if rate < 0.05 or rate > 20 then
        L.status = "That clip is too far from the project tempo to fit"
        return false
    end
    if not H.set_slot_rate(lane, row, rate) then return false end
    slot.tempo_guessed = guessed and true or nil
    L.status = guessed
        and string.format("Fitted at a guessed %.1f BPM", bpm)
        or string.format("Fitted from %.1f BPM", bpm)
    H.save()
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
    local lane_track = H.ensure_lane_track(to_lane)
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
    -- The lane it came from may have just lost its last clip.
    if not copy and from_lane ~= to_lane then H.prune_lane_track(from_lane) end
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
-- Where a bar should be measured: what you are hearing while it rolls, and the
-- edit cursor when it does not. A project with a meter change has no single
-- answer, and time zero is the one place that is almost never the right one.
function H.meter_position()
    if r.GetPlayState() & 1 == 1 then return H.heard_pos() or 0 end
    return r.GetCursorPosition() or 0
end

function H.meter_label(position)
    local num, denom = r.TimeMap_GetTimeSigAtTime(0, position or H.meter_position())
    num = (num and num > 0) and num or 4
    denom = (denom and denom > 0) and denom or 4
    return string.format("%d/%d", math.floor(num + 0.5), math.floor(denom + 0.5))
end

-- How long the clip loops, said in the units the meter actually counts. A three
-- beat loop in a four four session is not "1 bar", and rounding it up to one is
-- how a launcher quietly lies about what you are hearing.
function H.clip_length_text(slot)
    local loop = slot and H.slot_loop(slot) or 0
    if loop <= 0 then return nil end
    local position = H.meter_position()
    local qn = r.TimeMap2_timeToQN(0, position + loop) - r.TimeMap2_timeToQN(0, position)
    local per_bar = H.qn_per_bar(position)
    if per_bar <= 0 or qn <= 0 then return nil end
    local bars = qn / per_bar
    local whole_bars = math.floor(bars + 0.5)
    if whole_bars >= 1 and math.abs(bars - whole_bars) < 0.02 then
        return whole_bars .. (whole_bars == 1 and " bar" or " bars")
    end
    local _, denom = r.TimeMap_GetTimeSigAtTime(0, position)
    denom = (denom and denom > 0) and denom or 4
    local beats = qn / (4 / denom)
    local whole_beats = math.floor(beats + 0.5)
    if whole_beats >= 1 and math.abs(beats - whole_beats) < 0.03 then
        return whole_beats .. (whole_beats == 1 and " beat" or " beats")
    end
    return string.format("%.2f bars", bars)
end

function H.scene_bars(row, position)
    local longest = 0
    for _, lane in ipairs(L.lanes) do
        local slot = H.slot(lane, row)
        local length = slot and H.slot_loop(slot) or 0
        if length > longest then longest = length end
    end
    if longest <= 0 then return nil end
    position = position or H.meter_position()
    local per_bar = H.qn_per_bar(position)
    if per_bar <= 0 then return nil end
    local from = r.TimeMap2_timeToQN(0, position)
    local bars = (r.TimeMap2_timeToQN(0, position + longest) - from) / per_bar
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
    local bars = H.scene_bars(row, r.GetCursorPosition())
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
        local bars = H.scene_bars(row, position) or 1
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
        local bars = H.scene_bars(row, position + H.bars_to_time(position, bars_done))
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
    for _, lane in ipairs(L.lanes) do
        H.clear_slot(lane, row)
        H.prune_lane_track(lane)
    end
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
function H.step_count(step_qn, position)
    if not step_qn or step_qn <= 0 then return 0 end
    local count = math.floor((H.qn_per_bar(position or H.meter_position()) / step_qn) + 0.5)
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
    local bars = H.scene_bars(row, time)
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
        key = L.key and { root = L.key.root, mode = L.key.mode } or nil,
        key_style = L.key_style,
        key_sync = L.key_sync and true or false,
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
                tempo_matched = slot.tempo_matched and true or nil,
                tempo_guessed = slot.tempo_guessed and true or nil,
                key = slot.key and { root = slot.key.root, mode = slot.key.mode } or nil,
                key_guessed = slot.key_guessed and true or nil,
                root = slot.root,
                key_applied = slot.key_applied and
                    { root = slot.key_applied.root, mode = slot.key_applied.mode, style = slot.key_applied.style } or nil,
                pitches = slot.pitches,
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
            match = lane.match,
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

--------------------------------------------------------------------------------
-- key and mode: fitting a MIDI clip to the session it lands in
--------------------------------------------------------------------------------

C.note_names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
C.modes = {
    { key = "major",      short = "Major",      label = "Major / Ionian",  degrees = { 0, 2, 4, 5, 7, 9, 11 } },
    { key = "dorian",     short = "Dorian",     label = "Dorian",          degrees = { 0, 2, 3, 5, 7, 9, 10 } },
    { key = "phrygian",   short = "Phrygian",   label = "Phrygian",        degrees = { 0, 1, 3, 5, 7, 8, 10 } },
    { key = "lydian",     short = "Lydian",     label = "Lydian",          degrees = { 0, 2, 4, 6, 7, 9, 11 } },
    { key = "mixolydian", short = "Mixolydian", label = "Mixolydian",      degrees = { 0, 2, 4, 5, 7, 9, 10 } },
    { key = "minor",      short = "Minor",      label = "Minor / Aeolian", degrees = { 0, 2, 3, 5, 7, 8, 10 } },
    { key = "locrian",    short = "Locrian",    label = "Locrian",         degrees = { 0, 1, 3, 5, 6, 8, 10 } },
}

-- Written out rather than derived: "m" is minor and "M" is major, which no
-- case-insensitive rule can tell apart.
C.mode_words = {
    major = "major", maj = "major", ionian = "major", ion = "major",
    minor = "minor", min = "minor", aeolian = "minor", aeo = "minor",
    dorian = "dorian", dor = "dorian",
    phrygian = "phrygian", phryg = "phrygian", phr = "phrygian",
    lydian = "lydian", lyd = "lydian",
    mixolydian = "mixolydian", mixolydean = "mixolydian", mixo = "mixolydian", mix = "mixolydian",
    locrian = "locrian", loc = "locrian",
}

-- Anything read back from a file goes through here: a key from disk is data,
-- and an unknown mode falls back rather than reaching the mapping.
function H.key_from(data)
    if type(data) ~= "table" then return nil end
    local root = tonumber(data.root)
    if not root then return nil end
    return { root = math.floor(root) % 12, mode = H.mode_entry(tostring(data.mode or "major")).key }
end

function H.mode_entry(mode)
    for _, entry in ipairs(C.modes) do
        if entry.key == mode then return entry end
    end
    return C.modes[1]
end

function H.key_label(key)
    if not key then return "no key" end
    return (C.note_names[(key.root % 12) + 1] or "?") .. " " .. H.mode_entry(key.mode).short
end

function H.note_number(letter, accidental)
    local base = ({ C = 0, D = 2, E = 4, F = 5, G = 7, A = 9, B = 11 })[letter:upper()]
    if not base then return nil end
    if accidental == "#" then base = base + 1 elseif accidental == "b" then base = base - 1 end
    return base % 12
end

-- Reads "F#m", "Fmin", "Gb lydian", "A". Without a mode word it is only a key at
-- all when the caller says so: in a file name, a bare "B" is far more likely to
-- be the start of a word than the key of the loop.
function H.parse_key(text, need_mode)
    text = tostring(text or ""):gsub("[_%-]", " "):match("^%s*(.-)%s*$")
    if text == "" then return nil end
    local letter, accidental, rest = text:match("^([A-Ga-g])%s*([#b]?)%s*(.*)$")
    if not letter then return nil end
    local root = H.note_number(letter, accidental)
    if not root then return nil end
    -- Chord names carry an extension the key does not care about: Fm7 is the
    -- same key as Fm, Cmaj9 the same as Cmaj.
    rest = rest:match("^%s*(.-)%s*$"):gsub("%d+$", "")
    if rest == "" then
        if need_mode then return nil end
        return { root = root, mode = "major" }
    end
    if rest == "m" then return { root = root, mode = "minor" } end
    if rest == "M" then return { root = root, mode = "major" } end
    local mode = C.mode_words[rest:lower()]
    if not mode then return nil end
    return { root = root, mode = mode }
end

-- The folder a file sits in. Loop libraries are filed by key, and that label is
-- a claim about the tonic rather than about the notes: a vamp on A with a flat
-- seventh goes under "A major" because no pack has a folder called Mixolydian,
-- and filing it by its notes, under D, would put it where nobody working in A
-- would look. Read two levels up, since packs nest as often as not.
function H.folder_key(path)
    if not path or path == "" then return nil end
    local folder = path:match("^(.*)[/\\][^/\\]*$")
    for _ = 1, 2 do
        if not folder or folder == "" then return nil end
        local name = folder:match("([^/\\]+)$")
        if name then
            -- A whole folder name may be nothing but the key, where a bare "A"
            -- does mean A major - unlike a word inside a file name.
            local key = H.parse_key(name, false)
            if key then return key end
            local tokens = {}
            for token in name:gmatch("[^%s_%-%.%(%)%[%]]+") do tokens[#tokens + 1] = token end
            for index, token in ipairs(tokens) do
                key = H.parse_key(token, true)
                    or (tokens[index + 1] and H.parse_key(token .. " " .. tokens[index + 1], true))
                if key then return key end
            end
        end
        folder = folder:match("^(.*)[/\\][^/\\]*$")
    end
    return nil
end

-- Metadata first, then the file name, then the folder it was filed in. Returns
-- the key and where it came from, because the three carry different weight: a
-- MIDI file's own notes outrank a shelf label, and nothing outranks metadata.
function H.file_key(source, path)
    if r.GetMediaFileMetadata and source then
        local keys = { "ACID:key", "ID3:TKEY", "VORBIS:KEY", "XMP:dm/key", "RIFF:IKEY", "key" }
        for _, name in ipairs(keys) do
            local ok, value = r.GetMediaFileMetadata(source, name)
            if ok and ok ~= 0 and value and value ~= "" then
                local key = H.parse_key(value, false)
                if key then return key, "metadata" end
            end
        end
    end
    local name = (path or ""):match("([^/\\]+)$") or ""
    name = name:gsub("%.%w+$", "")
    local tokens = {}
    for token in name:gmatch("[^%s_%-%.%(%)%[%]]+") do tokens[#tokens + 1] = token end
    for index, token in ipairs(tokens) do
        -- One word for "Fm", two for "D dorian", which is just as common a way
        -- to write it in a file name.
        local key = H.parse_key(token, true)
            or (tokens[index + 1] and H.parse_key(token .. " " .. tokens[index + 1], true))
        if key then return key, "name" end
    end
    local folder = H.folder_key(path)
    if folder then return folder, "folder" end
    return nil
end

-- Degree mapping rather than nudging every note to its nearest neighbour: when
-- both scales are known, the first degree of the source belongs on the first
-- degree of the target. That is what turns F Dorian into C Lydian the way a
-- musician would hear it - F G Ab Bb C D Eb becomes C D E F# G A B - where
-- snapping by distance leaves it a coin toss whether Eb lands on E or on D.
-- A note outside the source scale keeps its distance from the degree below it.
function H.map_pitch(pitch, from, to, style)
    local base = to.root - from.root
    if base > 6 then base = base - 12 elseif base < -6 then base = base + 12 end
    if style ~= "scale" then return math.max(0, math.min(127, pitch + base)) end
    local source = H.mode_entry(from.mode).degrees
    local target = H.mode_entry(to.mode).degrees
    local relative = (pitch - from.root) % 12
    local octave = math.floor((pitch - from.root) / 12)
    local index, offset = 1, relative
    for step = #source, 1, -1 do
        if relative >= source[step] then
            index, offset = step, relative - source[step]
            break
        end
    end
    local result = to.root + octave * 12 + target[index] + offset
    -- The same correction for every note, so the melody keeps its shape instead
    -- of some notes jumping an octave and others not.
    if to.root - from.root > 6 then
        result = result - 12
    elseif to.root - from.root < -6 then
        result = result + 12
    end
    while result < 0 do result = result + 12 end
    while result > 127 do result = result - 12 end
    return result
end

function H.pitch_list(text)
    local pitches = {}
    for value in tostring(text or ""):gmatch("%-?%d+") do pitches[#pitches + 1] = tonumber(value) end
    return pitches
end

-- The clip's own notes are kept the moment it is first fitted, and every later
-- fit starts from them again. Without that, fitting a clip twice would stack one
-- mapping on top of the other and there would be no way back to what it was.
function H.slot_originals(slot, take, notes)
    local originals = H.pitch_list(slot.pitches)
    if #originals == notes then return originals end
    originals = {}
    for index = 0, notes - 1 do
        local ok, _, _, _, _, _, pitch = r.MIDI_GetNote(take, index)
        originals[index + 1] = ok and pitch or 60
    end
    slot.pitches = table.concat(originals, ",")
    return originals
end

function H.write_pitches(take, notes, pitch_of)
    r.MIDI_DisableSort(take)
    for index = 0, notes - 1 do
        local ok, selected, muted, startppq, endppq, channel, _, velocity = r.MIDI_GetNote(take, index)
        if ok then
            r.MIDI_SetNote(take, index, selected, muted, startppq, endppq, channel,
                pitch_of(index + 1), velocity, true)
        end
    end
    r.MIDI_Sort(take)
end

function H.slot_take(slot)
    local item = slot and H.item_from_guid(slot.guid) or nil
    return item and r.GetActiveTake(item) or nil
end

function H.midi_notes(take)
    if not take or not r.MIDI_CountEvts then return 0 end
    local ok, notes = r.MIDI_CountEvts(take)
    if not ok or not notes then return 0 end
    return notes
end

-- What a MIDI clip does not say, its notes can still tell. Every scale that the
-- notes actually fit is scored, and the tonic decides between them: the seven
-- modes of one scale hold the same seven notes, so membership alone can never
-- separate C major from D Dorian - only which note the music leans on can.
-- Nothing is returned unless the notes really do sit in a scale, because a
-- confident wrong key is worse than none.
-- How much a note behaves like the tonic. Weight in the music, weight in the
-- bass line, and the two places a loop is most likely to state its key: the
-- chord it opens on and the chord it lands on. The fifth counts a little, since
-- a tonic is usually accompanied by its dominant.
function H.tonic_score(root, weight, total, line, lowest)
    local score = (weight[root] / total) * 0.45
        + (weight[(root + 7) % 12] / total) * 0.10
    if lowest and lowest % 12 == root then score = score + 0.05 end
    if line then
        -- How much of the bass line a note holds counts, but not as much as
        -- where the loop begins: a vamp that sits twice as long on its fourth
        -- as on its tonic is ordinary, and reading the most-played bass note as
        -- the tonic turned an A D G D vamp into D major.
        score = score + (line.weight[root] / line.total) * 0.30
        -- The opening chord outweighs the closing one. A loop comes back round
        -- to its first chord every cycle, which makes that the point it resolves
        -- to; ending somewhere else is what a loop does to turn around, and
        -- weighing the two equally read A D Bm F#m as F# minor.
        if line.first % 12 == root then score = score + 0.30 end
        if line.last % 12 == root then score = score + 0.10 end
    end
    return score
end

-- Naming a chord is a closed question in a way that naming a key is not: a set
-- of pitch classes has a name, and that is the end of it. Listed plainest first,
-- because that decides which reading wins when two roots both explain the notes
-- - C E G with C in the bass is a C, not an Em with an added sixth.
C.chord_shapes = {
    { name = "",       intervals = { 0, 4, 7 } },
    { name = "m",      intervals = { 0, 3, 7 } },
    { name = "5",      intervals = { 0, 7 } },
    { name = "7",      intervals = { 0, 4, 7, 10 } },
    { name = "maj7",   intervals = { 0, 4, 7, 11 } },
    { name = "m7",     intervals = { 0, 3, 7, 10 } },
    { name = "6",      intervals = { 0, 4, 7, 9 } },
    { name = "m6",     intervals = { 0, 3, 7, 9 } },
    { name = "sus4",   intervals = { 0, 5, 7 } },
    { name = "sus2",   intervals = { 0, 2, 7 } },
    { name = "dim",    intervals = { 0, 3, 6 } },
    { name = "aug",    intervals = { 0, 4, 8 } },
    { name = "add9",   intervals = { 0, 2, 4, 7 } },
    { name = "madd9",  intervals = { 0, 2, 3, 7 } },
    { name = "7sus4",  intervals = { 0, 5, 7, 10 } },
    { name = "m7b5",   intervals = { 0, 3, 6, 10 } },
    { name = "dim7",   intervals = { 0, 3, 6, 9 } },
    { name = "mMaj7",  intervals = { 0, 3, 7, 11 } },
    { name = "9",      intervals = { 0, 2, 4, 7, 10 } },
    { name = "maj9",   intervals = { 0, 2, 4, 7, 11 } },
    { name = "m9",     intervals = { 0, 2, 3, 7, 10 } },
    { name = "7omit5", intervals = { 0, 4, 10 } },
    { name = "maj7omit5", intervals = { 0, 4, 11 } },
    { name = "m7omit5", intervals = { 0, 3, 10 } },
}

local function shape_fits(shape, present, root)
    local wanted = 0
    for _, interval in ipairs(shape.intervals) do
        if not present[(root + interval) % 12] then return false end
        wanted = wanted + 1
    end
    local held = 0
    for pitch_class = 0, 11 do
        if present[pitch_class] then held = held + 1 end
    end
    return held == wanted
end

-- Takes the pitch classes sounding together and the note in the bass. A root
-- other than the bass gives a slash chord, which is how an inversion reads.
function H.chord_name(classes, bass)
    local present, held = {}, 0
    for _, pitch_class in ipairs(classes or {}) do
        local reduced = pitch_class % 12
        if not present[reduced] then
            present[reduced] = true
            held = held + 1
        end
    end
    if held == 0 then return "?" end
    if held == 1 then return C.note_names[bass % 12 + 1] end
    local best = nil
    for root = 0, 11 do
        if present[root] then
            for index, shape in ipairs(C.chord_shapes) do
                if shape_fits(shape, present, root) then
                    -- The bass is the root unless the notes say otherwise, and
                    -- among equals the plainer name wins.
                    local score = (root == bass % 12 and 100 or 0) - index
                    if not best or score > best.score then
                        best = { score = score, root = root, name = shape.name }
                    end
                end
            end
        end
    end
    if not best then return C.note_names[bass % 12 + 1] .. "?" end
    local label = C.note_names[best.root + 1] .. best.name
    if best.root ~= bass % 12 then label = label .. "/" .. C.note_names[bass % 12 + 1] end
    return label
end

-- Groups the notes into one span each, with a little tolerance so a chord played
-- a hair early still belongs to the beat it was aimed at. A span that holds
-- nothing is never created, so a held chord stays one chord.
local function group_events(events, window)
    local groups, order = {}, {}
    for _, event in ipairs(events) do
        local index = math.floor(event.qn / window + 0.02)
        local group = groups[index]
        if not group then
            group = { at = event.at, bass = event.pitch, duration = event.duration, classes = {} }
            groups[index] = group
            order[#order + 1] = index
        end
        if event.pitch < group.bass then group.bass = event.pitch end
        if event.duration > group.duration then group.duration = event.duration end
        group.classes[#group.classes + 1] = event.pitch % 12
    end
    table.sort(order)
    local chords = {}
    for _, index in ipairs(order) do chords[#chords + 1] = groups[index] end
    return chords
end

-- How much of this grouping reads as harmony rather than as loose notes.
local function chord_share(chords)
    local named = 0
    for _, chord in ipairs(chords) do
        local seen, distinct = {}, 0
        for _, pitch_class in ipairs(chord.classes) do
            if not seen[pitch_class] then
                seen[pitch_class] = true
                distinct = distinct + 1
            end
        end
        if distinct >= 3 and not H.chord_name(chord.classes, chord.bass):find("?", 1, true) then
            named = named + 1
        end
    end
    return named / math.max(1, #chords)
end

-- The span is chosen by the music rather than fixed. A quarter note is right for
-- block chords, but an arpeggio in eighths spreads one chord over two quarters
-- and reading it a quarter at a time turns it into a row of single notes. Wider
-- spans are tried and kept only where they actually name chords, which is what
-- stops a plain melody from being bundled into harmony it does not have.
function H.group_by_harmony(events)
    local best, best_share = nil, -1
    for _, window in ipairs({ 1, 2, 4 }) do
        local chords = group_events(events, window)
        local share = chord_share(chords)
        if share > best_share + 0.001 then
            best, best_share = chords, share
        end
    end
    return best or group_events(events, 1)
end

-- The bass line, which is where harmony states its roots, read a quarter note at
-- a time. Harmony rarely moves faster than that in loop material, and reading it
-- note by note turned an arpeggio into a row of single notes: the chord list
-- became the melody, and every passing note counted as a bass.
-- The lowest note of each quarter is its bass. "The last note" is no substitute:
-- inside a chord that is whichever note the take happens to list last, and it
-- was picking inner voices as the tonic.
function H.chord_line(take, originals)
    local notes = H.midi_notes(take)
    if notes < 1 then return nil end
    local events = {}
    for index = 0, notes - 1 do
        local ok, _, muted, startppq, endppq, _, pitch = r.MIDI_GetNote(take, index)
        if originals then pitch = originals[index + 1] or pitch end
        if ok and not muted and pitch then
            local at = startppq or 0
            local qn = at / 960
            if r.MIDI_GetProjQNFromPPQPos then
                qn = r.MIDI_GetProjQNFromPPQPos(take, at) or qn
            end
            events[#events + 1] = { at = at, qn = qn, pitch = pitch,
                                    duration = math.max(1, (endppq or 0) - (startppq or 0)) }
        end
    end
    if #events == 0 then return nil end
    table.sort(events, function(left, right)
        if left.at ~= right.at then return left.at < right.at end
        return left.pitch < right.pitch
    end)
    local chords = H.group_by_harmony(events)
    local weight, total = {}, 0
    for pitch_class = 0, 11 do weight[pitch_class] = 0 end
    for _, chord in ipairs(chords) do
        weight[chord.bass % 12] = weight[chord.bass % 12] + chord.duration
        total = total + chord.duration
    end
    if total <= 0 then return nil end
    return { weight = weight, total = total, chords = chords,
             first = chords[1].bass, last = chords[#chords].bass, count = #chords }
end

-- The chords a clip actually holds, as a line of text. Repeats are collapsed:
-- four bars of A is one A, which is how anyone would write it down. Named from
-- the clip's own notes, so a fitted clip still shows what it is rather than
-- what it was moved to.
function H.chord_progression(slot, limit)
    local take = H.slot_take(slot)
    local notes = H.midi_notes(take)
    if notes == 0 then return nil end
    local originals = H.pitch_list(slot.pitches)
    if #originals ~= notes then originals = nil end
    local line = H.chord_line(take, originals)
    if not line or not line.chords then return nil end
    local names, previous = {}, nil
    for _, chord in ipairs(line.chords) do
        local name = H.chord_name(chord.classes, chord.bass)
        if name ~= previous then
            names[#names + 1] = name
            previous = name
        end
    end
    if #names == 0 then return nil end
    limit = limit or 10
    local shown = #names > limit and limit or #names
    local text = table.concat(names, " - ", 1, shown)
    if #names > shown then text = text .. " ..." end
    return text
end

-- Originals, when given, replace the pitches in the take. A clip that has been
-- fitted holds notes that were moved, and reading its key back off those would
-- answer with the key it was fitted to rather than the key it is in.
function H.notes_key(take, originals)
    local notes = H.midi_notes(take)
    if notes < 3 then return nil end
    local weight, total = {}, 0
    for pitch_class = 0, 11 do weight[pitch_class] = 0 end
    local first_pitch, last_pitch, lowest, first_at, last_at
    for index = 0, notes - 1 do
        local ok, _, muted, startppq, endppq, _, pitch = r.MIDI_GetNote(take, index)
        if originals then pitch = originals[index + 1] or pitch end
        if ok and not muted and pitch then
            -- By duration, not by count: a passing sixteenth carries less than a
            -- held root, and that is exactly the difference we are after.
            local duration = math.max(1, (endppq or 0) - (startppq or 0))
            weight[pitch % 12] = weight[pitch % 12] + duration
            total = total + duration
            if not first_at or startppq < first_at then first_at, first_pitch = startppq, pitch end
            if not last_at or startppq > last_at then last_at, last_pitch = startppq, pitch end
            if not lowest or pitch < lowest then lowest = pitch end
        end
    end
    if total <= 0 then return nil end
    local line = H.chord_line(take, originals)
    local best, best_score = nil, nil
    local closest, closest_fit = nil, 0
    for root = 0, 11 do
        for _, entry in ipairs(C.modes) do
            local inside = 0
            for _, degree in ipairs(entry.degrees) do inside = inside + weight[(root + degree) % 12] end
            local fit = inside / total
            if fit > closest_fit then
                closest, closest_fit = { root = root, mode = entry.key }, fit
            end
            if fit >= 0.9 then
                local score = fit + H.tonic_score(root, weight, total, line, lowest)
                -- Between two readings the evidence cannot separate, the common
                -- one. Small on purpose: it is meant to break a tie, not to
                -- outvote the music. At 0.05 it read an A Mixolydian vamp as D
                -- major purely for being a major key.
                if entry.key == "major" or entry.key == "minor" then score = score + 0.02 end
                if not best_score or score > best_score then
                    best, best_score = { root = root, mode = entry.key }, score
                end
            end
        end
    end
    -- Failing, it still says how close it got. "No scale fits" is a dead end;
    -- "the closest holds three quarters of the notes" tells you the clip is
    -- chromatic and that naming one key for it is your call, not a detection.
    return best, closest, closest_fit
end

-- The tonic on its own, with no scale to satisfy. A chromatic progression has no
-- single key, but it does still lean on a note - and transposing to the root is
-- the one style that needs nothing more than that.
function H.notes_root(take, originals)
    local notes = H.midi_notes(take)
    if notes < 3 then return nil end
    local weight, total = {}, 0
    for pitch_class = 0, 11 do weight[pitch_class] = 0 end
    local first_pitch, last_pitch, lowest, first_at, last_at
    for index = 0, notes - 1 do
        local ok, _, muted, startppq, endppq, _, pitch = r.MIDI_GetNote(take, index)
        if originals then pitch = originals[index + 1] or pitch end
        if ok and not muted and pitch then
            local duration = math.max(1, (endppq or 0) - (startppq or 0))
            weight[pitch % 12] = weight[pitch % 12] + duration
            total = total + duration
            if not first_at or startppq < first_at then first_at, first_pitch = startppq, pitch end
            if not last_at or startppq > last_at then last_at, last_pitch = startppq, pitch end
            if not lowest or pitch < lowest then lowest = pitch end
        end
    end
    if total <= 0 then return nil end
    local line = H.chord_line(take, originals)
    local best, best_score = nil, nil
    for root = 0, 11 do
        local score = H.tonic_score(root, weight, total, line, lowest)
        if not best_score or best_score < score then best, best_score = root, score end
    end
    return best
end

-- REAPER's MIDI functions read an in-project take. A clip built straight from a
-- .mid file keeps its notes in the file, where MIDI_CountEvts finds nothing at
-- all: the count comes back zero however full the clip is, so its key cannot be
-- read and its notes cannot be written. Gluing hands the item an in-project take
-- holding the same notes, which is what dragging a .mid into a project does
-- anyway - and the launcher already glues every clip it captures for its own
-- reasons, which is why those have always worked and dropped files have not.
-- The glue replaces the item, so the slot is pointed at the new one.
function H.ensure_in_project_midi(slot)
    local item = H.item_from_guid(slot.guid)
    if not H.valid_item(item) then return nil end
    local take = r.GetActiveTake(item)
    if not take or not r.TakeIsMIDI or not r.TakeIsMIDI(take) then return take end
    if H.midi_notes(take) > 0 then return take end
    local glued, changed = H.trim_midi_source(item)
    if not H.valid_item(glued) then return take end
    if changed then
        slot.guid = r.BR_GetMediaItemGUID(glued)
        slot.entry = nil
        H.save()
    end
    return r.GetActiveTake(glued)
end

function H.read_slot_key(lane, row)
    local slot = H.slot(lane, row)
    if not slot or not slot.is_midi then return false end
    local take = H.ensure_in_project_midi(slot)
    local notes = H.midi_notes(take)
    if notes == 0 then
        L.status = "No notes could be read from that clip"
        return false
    end
    local originals = H.slot_originals(slot, take, notes)
    local key, closest, fit = H.notes_key(take, originals)
    if not key then
        -- Two different questions, and reporting only the first one left the menu
        -- saying the clip leans on F while this said the closest scale was C
        -- Major - both true, about different things. The tonic is read and kept
        -- here as well, so the reading is of some use rather than a dead end.
        local root = H.notes_root(take, originals)
        if root then
            slot.root = root
            slot.key = nil
            slot.chords = nil
            H.save()
        end
        local leans = root and (" They lean on " .. (C.note_names[root + 1] or "?")
            .. ", so transposing works even though mapping degrees does not.") or ""
        if closest then
            L.status = string.format("These notes fit no one scale: the closest is %s, holding %d%% of them.%s",
                H.key_label(closest), math.floor(fit * 100 + 0.5), leans)
        else
            L.status = "Those notes do not sit in one scale clearly enough to name it." .. leans
        end
        return false
    end
    slot.key = key
    slot.key_guessed = true
    slot.root = nil
    if slot.key_applied then H.fit_slot_to_key(lane, row, true) end
    H.save()
    L.status = (slot.name or "Clip") .. " reads as " .. H.key_label(key)
    return true
end

-- Whether this clip already sits where fitting it would put it. The style counts
-- as much as the key: the same session key mapped by degree and transposed by
-- root land in different places, so switching style leaves real work to do.
function H.key_fit_is_current(slot, style)
    local applied = slot and slot.key_applied
    if not applied or not L.key then return false end
    return applied.root == L.key.root
        and applied.mode == L.key.mode
        and (applied.style or "scale") == (style or L.key_style or "scale")
end

function H.fit_slot_to_key(lane, row, quiet, style_override)
    local slot = H.slot(lane, row)
    if not slot or not slot.is_midi then return false end
    if not L.key then
        if not quiet then L.status = "Set the session key first" end
        return false
    end
    local take = H.ensure_in_project_midi(slot)
    local notes = H.midi_notes(take)
    if notes == 0 then
        if not quiet then L.status = "No notes could be read from that clip" end
        return false
    end
    -- Taken before anything is read or written. Everything below works from the
    -- clip's own notes, never from what is in the take at this moment: fitting a
    -- clip twice would otherwise measure the result of the first fit and answer
    -- a different question the second time.
    local originals = H.slot_originals(slot, take, notes)
    local style = style_override or L.key_style or "scale"
    local from = slot.key
    -- Only where the mode is not consulted. A tonic that was inferred says
    -- nothing about which scale the clip is in, so handing it to degree mapping
    -- as though it were major would map degrees the music never had.
    if not from and style == "root" and slot.root then
        from = { root = slot.root, mode = "major" }
    end
    if not from and slot.is_midi then
        -- Nothing said it, so read it off the notes. Marked as read rather than
        -- stated, and the clip's menu shows which of the two it was.
        local key, closest, fit = H.notes_key(take, originals)
        if key then
            slot.key = key
            slot.key_guessed = true
            from = key
        elseif style == "root" then
            -- No single scale, but transposing the root does not need one. Only
            -- the tonic is kept, with no mode: naming a mode here would be a
            -- claim about the music that its notes do not support. Kept all the
            -- same, so the next fit asks the clip rather than the notes.
            -- The folder first, and only here. Reaching this point means the
            -- notes fit no scale at all, and on music like that a shelf label
            -- written by a person is better evidence of where home is than
            -- anything weighing can infer - a chromatic descent leans nowhere in
            -- particular. Where a scale did fit, this branch is never reached
            -- and the notes keep the last word.
            local filed = H.folder_key(H.slot_source_path(slot))
            local root = filed and filed.root or H.notes_root(take, originals)
            if root then
                slot.root = root
                from = { root = root, mode = "major" }
            end
        elseif not quiet and closest then
            local leaning = H.notes_root(take, originals)
            L.status = string.format(
                "These notes fit no one scale: the closest is %s, holding %d%% of them.%s",
                H.key_label(closest), math.floor(fit * 100 + 0.5),
                leaning and (" They lean on " .. (C.note_names[leaning + 1] or "?")
                    .. ", so use transpose only, or set the key by hand.") or "")
            return false
        end
    end
    if not from then
        if not quiet then
            L.status = "Cannot tell what key that clip is in. Set it in the clip's menu."
        end
        return false
    end
    local to = L.key
    r.Undo_BeginBlock()
    H.write_pitches(take, notes, function(index)
        return H.map_pitch(originals[index] or 60, from, to, style)
    end)
    r.Undo_EndBlock("Fit launcher clip to the session key", -1)
    slot.key_applied = { root = to.root, mode = to.mode, style = style }
    slot.chords = nil
    slot.scale_known = nil
    slot.key_read = nil
    H.save()
    if not quiet then
        L.status = string.format("%s fitted from %s to %s", slot.name or "Clip",
            H.key_label(from), H.key_label(to))
    end
    return true
end

function H.unfit_slot_key(lane, row)
    local slot = H.slot(lane, row)
    if not slot or not slot.key_applied then return false end
    local take = H.slot_take(slot)
    local notes = H.midi_notes(take)
    local originals = H.pitch_list(slot.pitches)
    if notes == 0 or #originals ~= notes then
        slot.key_applied = nil
        L.status = "That clip has changed since it was fitted"
        return false
    end
    r.Undo_BeginBlock()
    H.write_pitches(take, notes, function(index) return originals[index] end)
    r.Undo_EndBlock("Launcher clip back to its own key", -1)
    slot.key_applied = nil
    slot.chords = nil
    slot.scale_known = nil
    slot.key_read = nil
    H.save()
    L.status = (slot.name or "Clip") .. " back in " .. H.key_label(slot.key)
    return true
end

-- Every MIDI clip that knows its key, in one go. What the session key is for.
function H.set_slot_key(lane, row, root, mode)
    local slot = H.slot(lane, row)
    if not slot then return end
    local current = slot.key or { root = 0, mode = "major" }
    slot.key = { root = root or current.root, mode = mode or current.mode }
    slot.key_guessed = nil
    slot.root = nil
    slot.chords = nil
    slot.scale_known = nil
    slot.key_read = nil
    -- Already fitted means the mapping it was fitted with was read off the old
    -- key. Redone from the clip's own notes, so nothing stacks.
    if slot.key_applied then H.fit_slot_to_key(lane, row, true) end
    H.save()
    L.status = (slot.name or "Clip") .. " is in " .. H.key_label(slot.key)
end

function H.fit_all_to_key()
    if not L.key then
        L.status = "Set the session key first"
        return
    end
    local fitted, unknown = 0, 0
    for _, lane in ipairs(L.lanes) do
        for _, slot in ipairs(lane.slots) do
            -- Asked rather than pre-judged: a clip that states no key still has
            -- its notes, and fit_slot_to_key is the one that knows to read them.
            -- Testing slot.key here is what made this skip every clip whose key
            -- was never written down, which is most of them.
            if slot.is_midi then
                if H.fit_slot_to_key(lane, slot.row, true) then
                    fitted = fitted + 1
                else
                    unknown = unknown + 1
                end
            end
        end
    end
    L.status = string.format("%d clips fitted to %s", fitted, H.key_label(L.key))
    if unknown > 0 then
        L.status = L.status .. string.format(", %d whose key could not be read", unknown)
    end
end

--------------------------------------------------------------------------------
-- clip sets: the grid as a file of its own, so it can travel to another project
--------------------------------------------------------------------------------

-- The file a clip plays from, or nil when it lives only in this project: an
-- in-project MIDI take has no file to point at. A trimmed clip plays through a
-- section source, which has no file of its own either, but its parent does.
function H.slot_source_path(slot)
    local item = H.item_from_guid(slot.guid)
    local take = item and r.GetActiveTake(item) or nil
    local source = take and r.GetMediaItemTake_Source(take) or nil
    local guard = 0
    while source and guard < 4 do
        if (r.GetMediaSourceType(source, "") or "") ~= "SECTION" then break end
        if not r.GetMediaSourceParent then return nil end
        source = r.GetMediaSourceParent(source)
        guard = guard + 1
    end
    if not source or not r.GetMediaSourceFileName then return nil end
    local path = r.GetMediaSourceFileName(source)
    if type(path) ~= "string" or path == "" or not r.file_exists(path) then return nil end
    return path
end

-- What a set stores per clip on top of its settings: where the audio is, and
-- which part of it this clip plays. The trim is written in source seconds rather
-- than project seconds, so it survives landing in a project at another tempo.
function H.slot_export(slot)
    local path = H.slot_source_path(slot)
    if not path then return nil end
    local item = H.item_from_guid(slot.guid)
    local take = item and r.GetActiveTake(item) or nil
    if not take then return nil end
    local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
    if rate <= 0 then rate = 1 end
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    return {
        row = slot.row,
        name = slot.name,
        path = path,
        offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0,
        span = length * rate,
        loop = slot.loop and true or false,
        key = slot.key and { root = slot.key.root, mode = slot.key.mode } or nil,
        repeat_qn = slot.repeat_qn,
        steps = H.steps_to_text(slot.steps),
        follow = slot.follow,
        plays = slot.plays,
        color = slot.color,
        gain = slot.gain,
    }
end

function H.set_payload()
    local data = {
        format = "tk_clip_set",
        version = 1,
        rows = L.rows,
        quantize = L.quantize,
        follow = L.follow_enabled and true or false,
        tempo_sync = L.tempo_sync and true or false,
        big_cells = L.big_cells and true or false,
        scenes = {},
        lanes = {},
    }
    for row, entry in pairs(L.scenes or {}) do
        if entry.follow ~= "stop" or (entry.plays or 1) ~= 1 then
            data.scenes[#data.scenes + 1] = { row = row, follow = entry.follow, plays = entry.plays }
        end
    end
    local skipped = 0
    for _, lane in ipairs(L.lanes) do
        local track = H.target_track(lane)
        local slots = {}
        for _, slot in ipairs(lane.slots) do
            local exported = H.slot_export(slot)
            if exported then slots[#slots + 1] = exported else skipped = skipped + 1 end
        end
        data.lanes[#data.lanes + 1] = {
            name = lane.name,
            -- The track this lane looks for in the next project. Its own track's
            -- name by default, but kept as its own field so a lane can be told to
            -- hunt for something else.
            match = lane.match or (track and H.track_name(track, lane.name)) or lane.name,
            slots = slots,
        }
    end
    return data, skipped
end

function H.export_set(path)
    if not path or path == "" then return false end
    if not path:lower():match("%.tkclips$") then path = path .. ".tkclips" end
    local data, skipped = H.set_payload()
    local ok, encoded = pcall(UI.json.encode, data)
    if not ok or not encoded then
        L.status = "Could not build the clip set"
        return false
    end
    local file = io.open(path, "w")
    if not file then
        L.status = "Could not write " .. path
        return false
    end
    file:write(encoded)
    file:close()
    local clips = 0
    for _, lane in ipairs(data.lanes) do clips = clips + #lane.slots end
    L.status = string.format("Saved %d clips in %d lanes", clips, #data.lanes)
    if skipped > 0 then
        L.status = L.status .. string.format(", %d left behind that exist only in this project", skipped)
    end
    return true
end

-- Never matches the launcher's own hidden lane tracks: they are named after the
-- tracks they feed, and a lane pointing at a lane is nonsense. An exact match
-- wins over one that only agrees on case.
function H.track_by_name(name)
    if not name or name == "" then return nil end
    local wanted = name:lower()
    local fallback = nil
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        if not H.is_lane_track(track) then
            local track_name = H.track_name(track, "")
            if track_name == name then return track end
            if not fallback and track_name:lower() == wanted then fallback = track end
        end
    end
    return fallback
end

-- Columns read left to right and tracks read top to bottom; when those two
-- disagree the grid is unreadable, whatever each lane is correctly bound to.
-- Lanes whose track has gone sort to the end and keep their order among
-- themselves, so a dead lane never jumps around while it waits to be cleared.
function H.sort_lanes_by_track()
    local order = {}
    for index, lane in ipairs(L.lanes) do
        local track = H.target_track(lane)
        local number = track and math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0) or nil
        order[lane] = { number = number or math.huge, index = index }
    end
    table.sort(L.lanes, function(left, right)
        local a, b = order[left], order[right]
        if a.number ~= b.number then return a.number < b.number end
        return a.index < b.index
    end)
    if L.cursor then
        L.cursor.lane = math.max(1, math.min(L.cursor.lane or 1, #L.lanes))
    end
end

-- Columns and tracks are one thing: the grid reads left to right, the arrange
-- reads top to bottom, and two orders that can drift apart is a puzzle nobody
-- asked for. Lanes cannot be reordered by hand, so there is no deliberate order
-- to lose here - the order they had was only the order they happened to be added
-- in. Cheap enough to check every frame; it sorts only when something moved, and
-- saves quietly so that reordering tracks does not mark the project dirty.
-- The grid is the track list. Every track has a lane, in track order, the way
-- Ableton, Bitwig and Waveform all work - which is what makes lining the rows
-- up with the arrange possible at all. Choosing which tracks got a lane left
-- gaps, and every row below a gap sat a track's height off.
--
-- A lane whose track is gone is set aside rather than destroyed: undoing a
-- track deletion brings it back under the same guid, and its clips are still on
-- the hidden track waiting for it.
-- Rename a track and its lane follows, hidden track and all. Both are written
-- only where they differ, so this costs a read per lane and nothing else.
function H.follow_track_name(lane, track)
    local name = H.track_name(track, "Track")
    if lane.name ~= name then lane.name = name end
    local hidden = H.lane_track(lane)
    if not hidden then return end
    local wanted = H.lane_track_name(track)
    local _, current = r.GetSetMediaTrackInfo_String(hidden, "P_NAME", "", false)
    if current ~= wanted then
        r.GetSetMediaTrackInfo_String(hidden, "P_NAME", wanted, true)
    end
end

function H.follow_track_list()
    local ordered, seen = {}, {}
    for _, lane in ipairs(L.lanes) do
        if lane.track_guid then seen[lane.track_guid] = lane end
    end
    L.orphans = L.orphans or {}
    for index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, index)
        -- The track panel, not the raw track list. A track hidden from the TCP
        -- would otherwise take a row that has nothing beside it, which is the
        -- gap this whole change is here to remove. Its lane waits with the rest.
        local shown = track and not H.is_lane_track(track)
            and (r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") or 0) > 0.5
        if shown then
            local guid = r.GetTrackGUID(track)
            local lane = seen[guid] or L.orphans[guid]
            if lane then
                L.orphans[guid] = nil
            else
                lane = {
                    name = H.track_name(track, "Track"),
                    track_guid = guid,
                    slots = {},
                    owner = "arrangement",
                }
            end
            seen[guid] = nil
            H.follow_track_name(lane, track)
            ordered[#ordered + 1] = lane
        end
    end
    -- Whatever is left over has lost its track since the last look.
    local changed = #ordered ~= #L.lanes
    for guid, lane in pairs(seen) do
        L.orphans[guid] = lane
        changed = true
    end
    if not changed then
        for index, lane in ipairs(ordered) do
            if L.lanes[index] ~= lane then changed = true break end
        end
    end
    if not changed then return end
    L.lanes = ordered
    -- The hidden tracks read in lane order, so a lane order that just changed
    -- means they have to be walked back into line. Nothing else notices: moving
    -- tracks about leaves the track count alone.
    L.tidy_wanted = true
    if L.cursor then
        L.cursor.lane = math.max(1, math.min(L.cursor.lane or 1, math.max(1, #L.lanes)))
    end
    H.save(true)
end

function H.keep_lane_order()
    H.follow_track_list()
end

-- Index is where the track belongs in the project, not just how many there are:
-- a set is a layout, and appending everything at the end throws that layout away.
function H.create_named_track(name, index)
    local count = r.CountTracks(0)
    index = math.max(0, math.min(math.floor(index or count), count))
    r.InsertTrackAtIndex(index, true)
    local track = r.GetTrack(0, index)
    if not track then return nil end
    r.GetSetMediaTrackInfo_String(track, "P_NAME", name, true)
    return track
end

-- The settings a set carries for one clip, put onto the clip that was just built
-- from its file. The trim goes on last: it is held in source seconds, so it has
-- to be divided by whatever playrate this project's tempo asked for.
function H.apply_stored_slot(lane, row, stored)
    local slot = H.slot(lane, row)
    if not slot then return end
    if type(stored.name) == "string" and stored.name ~= "" then slot.name = stored.name end
    slot.loop = stored.loop ~= false
    slot.key = H.key_from(stored.key) or slot.key
    slot.repeat_qn = tonumber(stored.repeat_qn)
    slot.steps = H.steps_from_text(stored.steps)
    slot.follow = stored.follow
    slot.plays = tonumber(stored.plays)
    slot.color = tonumber(stored.color)
    slot.gain = tonumber(stored.gain)
    local item = H.item_from_guid(slot.guid)
    local take = item and r.GetActiveTake(item) or nil
    if not take then return end
    local span = tonumber(stored.span)
    if span and span > 0 then
        local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
        if rate <= 0 then rate = 1 end
        local source = r.GetMediaItemTake_Source(take)
        local source_length = source and r.GetMediaSourceLength(source) or 0
        local offset = math.max(0, tonumber(stored.offset) or 0)
        if offset > 0.0001 or (source_length > 0 and span < source_length - 0.0001) then
            r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", offset)
            r.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.05, span / rate))
        end
    end
    if slot.name then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", slot.name, true) end
end

-- Clips are built with H.assign_path, the same route a file dropped on a slot
-- takes, so a set can only ever produce clips this launcher already knows how to
-- make. Lanes are added to what is already here rather than replacing it.
function H.import_set(path, create_missing)
    local file = io.open(path, "r")
    if not file then
        L.status = "Could not read " .. path
        return false
    end
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(UI.json.decode, content)
    if not ok or type(data) ~= "table" or type(data.lanes) ~= "table" then
        L.status = "That file is not a clip set"
        return false
    end
    local was_empty = #L.lanes == 0
    local needed = L.rows
    for _, entry in ipairs(data.lanes) do
        for _, stored in ipairs(entry.slots or {}) do
            local row = math.floor(tonumber(stored.row) or 1)
            if row > needed then needed = row end
        end
    end
    L.rows = math.max(L.rows, math.min(needed, C.max_rows))
    -- Timing belongs to the set, but only where there is nothing to disturb.
    if was_empty then
        L.quantize = tonumber(data.quantize) or L.quantize
        if type(data.follow) == "boolean" then L.follow_enabled = data.follow end
        if type(data.tempo_sync) == "boolean" then L.tempo_sync = data.tempo_sync end
        if type(data.big_cells) == "boolean" then L.big_cells = data.big_cells end
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    -- Every track is resolved and created before a single lane exists. Doing both
    -- in one pass would interleave the new tracks with the launcher's own hidden
    -- ones, and a created track appended at the end lands in a different column
    -- than the set was built with - while reproducing that layout is the whole
    -- point of loading a set.
    local resolved, missing_tracks = {}, {}
    local first_match = nil
    for index, entry in ipairs(data.lanes) do
        resolved[index] = H.track_by_name(entry.match or entry.name)
        if resolved[index] and not first_match then
            first_match = math.floor(r.GetMediaTrackInfo_Value(resolved[index], "IP_TRACKNUMBER") or 1) - 1
        end
    end
    -- Do the tracks that were found sit in the project in the order the set has
    -- them? If they do, the set's layout can be rebuilt around them and a created
    -- track belongs in its own place among them. If they do not, that layout is
    -- out of reach whatever we do, and inserting between existing tracks would
    -- renumber them for nothing: it is what makes one track appear to move while
    -- its neighbour stays put. Then everything created goes at the end instead and
    -- not a single existing track shifts.
    local in_set_order, previous = true, 0
    for index = 1, #data.lanes do
        local track = resolved[index]
        if track then
            local number = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
            if number < previous then in_set_order = false break end
            previous = number
        end
    end
    -- Lanes that come before the first track that was found go in front of it.
    local insert_at = r.CountTracks(0)
    if in_set_order and first_match then insert_at = math.max(0, first_match) end
    for index, entry in ipairs(data.lanes) do
        local wanted = entry.match or entry.name
        if resolved[index] then
            -- Track numbers are one based, so the number itself is the index of
            -- the slot just behind that track.
            if in_set_order then
                local number = math.floor(r.GetMediaTrackInfo_Value(resolved[index], "IP_TRACKNUMBER") or 1)
                insert_at = math.max(insert_at, number)
            end
        elseif create_missing then
            resolved[index] = H.create_named_track(wanted, insert_at)
            if resolved[index] then insert_at = insert_at + 1 end
        else
            missing_tracks[#missing_tracks + 1] = tostring(wanted)
        end
    end
    local added, missing_files = 0, 0
    for index, entry in ipairs(data.lanes) do
        local track = resolved[index]
        if track then
            local lane = H.lane_for_track(track) or H.add_lane(track)
            if lane then
                lane.match = entry.match or entry.name
                for _, stored in ipairs(entry.slots or {}) do
                    local row = math.floor(tonumber(stored.row) or 0)
                    local usable = row >= 1 and row <= L.rows
                        and type(stored.path) == "string" and r.file_exists(stored.path)
                    if usable and H.assign_path(lane, row, stored.path) then
                        H.apply_stored_slot(lane, row, stored)
                        added = added + 1
                    else
                        missing_files = missing_files + 1
                    end
                end
            end
        end
    end
    L.scenes = L.scenes or {}
    for _, scene in ipairs(data.scenes or {}) do
        local row = math.floor(tonumber(scene.row) or 0)
        if row >= 1 and row <= L.rows and not L.scenes[row] then
            L.scenes[row] = { follow = scene.follow or "stop", plays = tonumber(scene.plays) or 1 }
        end
    end
    -- A set whose tracks sit in another order than the project's cannot have both
    -- its own layout and the project's, and the project's is the one you are
    -- looking at while you play. Done on every load, not only into an empty grid:
    -- loading a second set is exactly where the two orders drift apart, and a
    -- column that sits five places away from its own track is unreadable.
    H.sort_lanes_by_track()
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Load launcher clip set", -1)
    H.tidy_lane_tracks()
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    H.save()
    local report = { string.format("Loaded %d clips", added) }
    if #missing_tracks > 0 then
        report[#report + 1] = string.format("no track named %s", table.concat(missing_tracks, ", "))
    end
    if missing_files > 0 then
        report[#report + 1] = string.format("%d clips skipped, their file was not found", missing_files)
    end
    L.status = table.concat(report, "; ")
    return true
end

-- Asked before anything is touched. Loading a set fills the rows it uses, and a
-- clip already sitting in one of them is replaced.
function H.load_set(path)
    if #L.lanes > 0 and r.MB then
        local answer = r.MB("Load this clip set?\n\nIts lanes are added to the ones already here, and a clip"
            .. " sitting in a row the set uses is replaced.", "Load clip set", 1)
        if answer ~= 1 then return end
    end
    H.import_set(path, L.set_create_tracks and true or false)
end

--------------------------------------------------------------------------------
-- the clip set library: one folder per production, plus what everyone shares
--------------------------------------------------------------------------------
-- A set in the library root is available to every project. A set in a subfolder
-- belongs to that folder, and a project sees it only while it is the folder that
-- project works in. That is the whole scoping rule: the folder is the production,
-- so nothing has to be tagged, moved or written into the set files themselves.

function H.library_folder()
    local stored = r.GetExtState(C.ext_section, "library")
    if stored and stored ~= "" then return stored end
    return r.GetResourcePath() .. C.sep .. "TK Clip Sets"
end

-- Which folder this project works in. Kept in the project rather than in the
-- script: it belongs to this project, and every episode of a series can name the
-- same folder without them knowing about each other.
function H.project_folder_name()
    local ok, value = r.GetProjExtState(0, C.proj_section, "collection")
    if ok and ok ~= 0 and type(value) == "string" and value ~= "" then return value end
    return nil
end

function H.set_project_folder(name)
    r.SetProjExtState(0, C.proj_section, "collection", name or "")
    if r.MarkProjectDirty then r.MarkProjectDirty(0) end
    L.status = name and ("This project works in " .. name) or "This project is not in a folder"
end

function H.project_folder_path()
    local name = H.project_folder_name()
    if not name then return nil end
    return H.library_folder() .. C.sep .. name
end

local function set_entries(folder)
    local sets, index = {}, 0
    while true do
        local file = r.EnumerateFiles(folder, index)
        if not file then break end
        if file:lower():match("%.tkclips$") then
            sets[#sets + 1] = { name = file:gsub("%.%w+$", ""), path = folder .. C.sep .. file }
        end
        index = index + 1
    end
    table.sort(sets, function(left, right) return left.name:lower() < right.name:lower() end)
    return sets
end

-- Read from disk rather than remembered, so a set dropped in the folder by hand
-- shows up. Only on opening the menu and on demand: this is disk work, not
-- something to repeat every frame.
function H.scan_library()
    local root = H.library_folder()
    if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(root, 0) end
    local library = { root = root, folders = {}, shared = set_entries(root) }
    local index = 0
    while true do
        local name = r.EnumerateSubdirectories(root, index)
        if not name then break end
        library.folders[#library.folders + 1] = { name = name, sets = set_entries(root .. C.sep .. name) }
        index = index + 1
    end
    table.sort(library.folders, function(left, right) return left.name:lower() < right.name:lower() end)
    L.library = library
end

function H.ask_set(mode, path)
    L.set_prompt = { mode = mode, path = path }
end

-- Every dialog here is modal, so they run from update() before the frame starts,
-- the same way the file and rename prompts do. Opening one from inside the popup
-- would leave the ImGui frame half built for as long as it is up.
function H.run_set_prompt()
    local prompt = L.set_prompt
    if not prompt then return end
    L.set_prompt = nil
    if prompt.mode == "load" and prompt.path then
        H.load_set(prompt.path)
        return
    end
    local nul = string.char(0)
    local filter = "TK clip set (*.tkclips)" .. nul .. "*.tkclips" .. nul
    local folder = H.project_folder_path() or H.library_folder()
    if prompt.mode == "save" then
        if not r.JS_Dialog_BrowseForSaveFile then return end
        local suggested = "clips.tkclips"
        if r.GetProjectName then
            local project = r.GetProjectName(0, "")
            if type(project) == "string" and project ~= "" then
                suggested = project:gsub("%.[Rr][Pp][Pp]$", "") .. ".tkclips"
            end
        end
        local ok, path = r.JS_Dialog_BrowseForSaveFile("Save clip set", folder, suggested, filter)
        if ok and path and path ~= "" then
            H.export_set(path)
            H.scan_library()
        end
        return
    end
    if r.JS_Dialog_BrowseForOpenFiles then
        local ok, path = r.JS_Dialog_BrowseForOpenFiles("Load clip set", folder, "", filter, false)
        if ok and path and path ~= "" then H.load_set(path) end
        return
    end
    if not r.GetUserFileNameForRead then return end
    local ok, path = r.GetUserFileNameForRead("", "Load clip set", "tkclips")
    if ok and path and path ~= "" then H.load_set(path) end
end

function H.ask_library_folder()
    L.library_prompt = true
end

function H.run_library_prompt()
    if not L.library_prompt then return end
    L.library_prompt = nil
    if not r.JS_Dialog_BrowseForFolder then return end
    local ok, path = r.JS_Dialog_BrowseForFolder("Where the clip sets live", H.library_folder())
    if ok and path and path ~= "" then
        r.SetExtState(C.ext_section, "library", path, true)
        H.scan_library()
        L.status = "Clip sets now come from " .. path
    end
end

function H.ask_new_folder()
    L.new_folder_prompt = true
end

function H.run_new_folder_prompt()
    if not L.new_folder_prompt then return end
    L.new_folder_prompt = nil
    if not r.GetUserInputs then return end
    local ok, answer = r.GetUserInputs("New clip set folder", 1, "Name:,extrawidth=180", "")
    if not ok then return end
    answer = tostring(answer or ""):match("^%s*(.-)%s*$")
    -- Everything a path separator or a wildcard would break, refused rather than
    -- silently turned into something else.
    if answer == "" or answer:match('[/\\:%*%?"<>|]') then
        L.status = "That is not a folder name"
        return
    end
    local path = H.library_folder() .. C.sep .. answer
    if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path, 0) end
    H.scan_library()
    H.set_project_folder(answer)
end

function H.ask_match(lane)
    L.match_prompt = lane
end

function H.run_match_prompt()
    local lane = L.match_prompt
    if not lane then return end
    L.match_prompt = nil
    if not r.GetUserInputs then return end
    local still_there = false
    for _, entry in ipairs(L.lanes) do
        if entry == lane then still_there = true break end
    end
    if not still_there then return end
    local track = H.target_track(lane)
    local current = lane.match or (track and H.track_name(track, lane.name)) or lane.name
    local ok, answer = r.GetUserInputs("Lane matching", 1, "Track name to look for:,extrawidth=180", current)
    if not ok then return end
    answer = tostring(answer or ""):match("^%s*(.-)%s*$")
    lane.match = (answer ~= "" and answer ~= current) and answer or nil
    H.save()
    L.status = lane.match and ("This lane looks for a track named " .. lane.match)
        or "This lane looks for its own track's name again"
end

function H.draw_key_popup()
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_key") then return end
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "What key this session is in")
    r.ImGui_Separator(UI.ctx)
    local root = L.key and L.key.root or 0
    local mode = L.key and L.key.mode or "major"
    for index, name in ipairs(C.note_names) do
        local selected = L.key ~= nil and root == index - 1
        if selected then
            r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
            r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
        end
        -- The id goes on the stack rather than into the label. Appending "##id"
        -- to a name that ends in a sharp makes "C#" .. "##..." read as "C" plus
        -- an id, because ImGui cuts the label at the first "##" it finds - which
        -- is why every sharp was missing from these buttons.
        r.ImGui_PushID(UI.ctx, "key_root_" .. index)
        if r.ImGui_Button(UI.ctx, name, UI.rounded(34), UI.rounded(24)) then
            L.key = { root = index - 1, mode = mode }
            H.save()
        end
        r.ImGui_PopID(UI.ctx)
        if selected then r.ImGui_PopStyleColor(UI.ctx, 2) end
        if index % 6 ~= 0 then r.ImGui_SameLine(UI.ctx, 0, UI.rounded(3)) end
    end
    r.ImGui_Spacing(UI.ctx)
    for _, entry in ipairs(C.modes) do
        if r.ImGui_MenuItem(UI.ctx, entry.label, nil, L.key ~= nil and mode == entry.key) then
            L.key = { root = root, mode = entry.key }
            H.save()
        end
    end
    r.ImGui_Separator(UI.ctx)
    if r.ImGui_MenuItem(UI.ctx, "Map the scale degrees", nil, (L.key_style or "scale") == "scale") then
        L.key_style = "scale"
        H.save()
    end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "The first degree of the clip becomes the first degree of the session:\nF Dorian arrives as C Lydian, not as C Dorian")
    end
    if r.ImGui_MenuItem(UI.ctx, "Transpose to the root only", nil, L.key_style == "root") then
        L.key_style = "root"
        H.save()
    end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "One interval for every note, so the clip keeps its own mode:\nF Dorian arrives as C Dorian")
    end
    r.ImGui_Separator(UI.ctx)
    if r.ImGui_MenuItem(UI.ctx, "Fit clips on import", nil, L.key_sync and true or false) then
        L.key_sync = not L.key_sync
        H.save()
    end
    if r.ImGui_MenuItem(UI.ctx, "Fit every clip now") then H.fit_all_to_key() end
    if L.key and r.ImGui_MenuItem(UI.ctx, "No session key") then
        L.key = nil
        H.save()
    end
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "MIDI clips only. Audio keeps its own pitch.")
    r.ImGui_EndPopup(UI.ctx)
end

function H.draw_set_popup()
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_set") then return end
    if not L.library then H.scan_library() end
    local library = L.library
    local folder_name = H.project_folder_name()

    if r.ImGui_BeginMenu(UI.ctx, "This project works in: " .. (folder_name or "no folder")) then
        if r.ImGui_MenuItem(UI.ctx, "No folder", nil, folder_name == nil) then
            H.set_project_folder(nil)
        end
        for _, folder in ipairs(library.folders) do
            if r.ImGui_MenuItem(UI.ctx, folder.name, nil, folder_name == folder.name) then
                H.set_project_folder(folder.name)
            end
        end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "New folder...") then H.ask_new_folder() end
        r.ImGui_EndMenu(UI.ctx)
    end
    r.ImGui_Separator(UI.ctx)

    -- This project's own folder first: on a series that is what you reach for,
    -- and what everyone shares is the same list every day.
    local listed = 0
    for _, folder in ipairs(library.folders) do
        local mine = folder.name == folder_name
        if (mine or L.set_show_all) and #folder.sets > 0 then
            r.ImGui_TextColored(UI.ctx, mine and UI.colors.accent or UI.colors.text_dim, folder.name)
            for _, set in ipairs(folder.sets) do
                if r.ImGui_MenuItem(UI.ctx, "   " .. set.name) then H.ask_set("load", set.path) end
                listed = listed + 1
            end
        end
    end
    if #library.shared > 0 then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Every project")
        for _, set in ipairs(library.shared) do
            if r.ImGui_MenuItem(UI.ctx, "   " .. set.name) then H.ask_set("load", set.path) end
            listed = listed + 1
        end
    end
    if listed == 0 then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "No sets here yet. Save one to start.")
    end

    r.ImGui_Separator(UI.ctx)
    if r.ImGui_MenuItem(UI.ctx, "Save set...") then H.ask_set("save") end
    if r.ImGui_MenuItem(UI.ctx, "Load a file...") then H.ask_set("load") end
    r.ImGui_Separator(UI.ctx)
    if r.ImGui_MenuItem(UI.ctx, "Show every folder", nil, L.set_show_all and true or false) then
        L.set_show_all = not L.set_show_all
        r.SetExtState(C.ext_section, "set_show_all", L.set_show_all and "1" or "0", true)
    end
    if r.ImGui_MenuItem(UI.ctx, "Create missing tracks on load", nil, L.set_create_tracks and true or false) then
        L.set_create_tracks = not L.set_create_tracks
        r.SetExtState(C.ext_section, "set_create_tracks", L.set_create_tracks and "1" or "0", true)
    end
    if r.ImGui_MenuItem(UI.ctx, "Refresh") then H.scan_library() end
    if r.ImGui_MenuItem(UI.ctx, "Where the sets live...") then H.ask_library_folder() end
    if r.CF_ShellExecute and r.ImGui_MenuItem(UI.ctx, "Open that folder") then
        r.CF_ShellExecute(library.root)
    end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, library.root)
    end
    r.ImGui_EndPopup(UI.ctx)
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
    L.orphans = {}
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
        L.key = H.key_from(data.key)
        L.key_style = data.key_style == "root" and "root" or "scale"
        L.key_sync = data.key_sync ~= false
        for _, stored in ipairs(data.lanes or {}) do
            -- The target track is what a lane is; the hidden track that carries
            -- its clips only exists once it has some, so a lane without one is
            -- an empty lane and still worth loading for what it remembers.
            if H.track_from_guid(stored.track_guid) then
                local lane = {
                    name = stored.name or "Lane",
                    match = type(stored.match) == "string" and stored.match ~= "" and stored.match or nil,
                    track_guid = stored.track_guid,
                    lane_guid = H.track_from_guid(stored.lane_guid) and stored.lane_guid or nil,
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
                            tempo_matched = slot.tempo_matched and true or nil,
                            tempo_guessed = slot.tempo_guessed and true or nil,
                            key = H.key_from(slot.key),
                            key_guessed = slot.key_guessed and true or nil,
                            root = tonumber(slot.root) and math.floor(tonumber(slot.root)) % 12 or nil,
                            key_applied = H.key_from(slot.key_applied) and {
                                root = H.key_from(slot.key_applied).root,
                                mode = H.key_from(slot.key_applied).mode,
                                style = slot.key_applied.style == "root" and "root" or "scale",
                            } or nil,
                            pitches = type(slot.pitches) == "string" and slot.pitches or nil,
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
    -- Straight away, so the grid is the track list from the first frame rather
    -- than showing the empty-project notice until the next tick comes round.
    H.follow_track_list()
    H.sweep_stray_voices()
    -- If a previous session was interrupted mid takeover, give the arrangement
    -- its mute states back before anything else happens.
    H.repair_restore_state()
end

--------------------------------------------------------------------------------
-- grid drawing
--------------------------------------------------------------------------------

-- Read once when the clip menu opens. Naming the chords and reading a key both
-- walk every note in the clip, and a popup redraws every frame.
function H.refresh_clip_reading(slot)
    local held = H.midi_notes(H.slot_take(slot))
    if slot.chords ~= nil and slot.chords_count == held then return end
    slot.chords = H.chord_progression(slot) or false
    local originals = H.pitch_list(slot.pitches)
    if #originals ~= held then originals = nil end
    -- Kept apart from slot.key on purpose: this is what the notes say, not what
    -- the clip has been told it is. Opening a menu should state things, not
    -- decide them.
    slot.key_read = H.notes_key(H.slot_take(slot), originals) or false
    slot.scale_known = (slot.key ~= nil) or (slot.key_read ~= false)
    slot.chords_count = held
end

-- Tempo and key are each a subject of their own, and most of the time neither is
-- what the menu was opened for. Each lives in a submenu, with its state in the
-- label so it can still be read without opening anything.
function H.draw_clip_tempo_menu(lane, row, slot)
    if slot.sectioned then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Loops the trimmed length, not the whole file")
    end
    if slot.tempo_matched then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, slot.tempo_guessed
            and "Stretched to project tempo, tempo guessed from its length"
            or "Stretched to project tempo on import")
        if r.ImGui_MenuItem(UI.ctx, "Play at original speed") then
            H.set_slot_rate(lane, row, 1)
        end
    elseif not slot.is_midi then
        if r.ImGui_MenuItem(UI.ctx, "Fit to project tempo") then
            H.fit_slot_to_tempo(lane, row)
        end
    end
end

-- What the clip is, then what can be done with it, then how to correct the
-- reading if it is wrong. Everything above the first separator only reports.
function H.draw_clip_key_menu(lane, row, slot)
    local key_text = "Does not say what key it is in"
    if slot.key then
        key_text = (slot.key_guessed and "Reads as " or "In ") .. H.key_label(slot.key)
    elseif slot.key_read then
        key_text = "Reads as " .. H.key_label(slot.key_read)
    elseif slot.root then
        key_text = "No one scale: these notes lean on " .. (C.note_names[slot.root + 1] or "?")
    end
    if slot.key_applied then
        key_text = key_text .. ", playing in " .. H.key_label(slot.key_applied)
    end
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, key_text)
    if slot.chords then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Chords: " .. slot.chords)
    end
    -- Said out loud rather than left to a greyed item and a tooltip: the reason
    -- one of the two routes is unavailable is a fact about the music, and you
    -- should not have to hover to learn it.
    if slot.scale_known == false then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
            "These notes fit no one scale, so only transposing is possible")
    end
    r.ImGui_Separator(UI.ctx)
    -- Both routes, spelled out. Which one the session prefers is a setting in
    -- another menu, and leaving that to be discovered meant that clicking Fit on
    -- a chromatic clip did nothing at all. Each is ticked when the clip already
    -- sits there and greyed when it cannot go there.
    if L.key then
        local label = "Fit to " .. H.key_label(L.key)
        local mapped = H.key_fit_is_current(slot, "scale")
        if r.ImGui_MenuItem(UI.ctx, label .. ", map the scale degrees", nil,
                mapped, slot.scale_known and not mapped) then
            H.fit_slot_to_key(lane, row, false, "scale")
        end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, slot.scale_known
                and "Recast into the session's mode: the first degree of the clip\nbecomes the first degree of the session"
                or "Not possible for this clip: its notes fit no single scale,\nso there are no degrees to map")
        end
        local moved = H.key_fit_is_current(slot, "root")
        if r.ImGui_MenuItem(UI.ctx, label .. ", transpose only", nil, moved, not moved) then
            H.fit_slot_to_key(lane, row, false, "root")
        end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "Move every note by the same interval, so the clip keeps\nits own character and only changes key")
        end
    end
    if slot.key_applied then
        if r.ImGui_MenuItem(UI.ctx, "Back to its own key") then H.unfit_slot_key(lane, row) end
    end
    r.ImGui_Separator(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "If that reading is wrong")
    if r.ImGui_BeginMenu(UI.ctx, "This clip's root") then
        for index, name in ipairs(C.note_names) do
            if r.ImGui_MenuItem(UI.ctx, name, nil, slot.key ~= nil and slot.key.root == index - 1) then
                H.set_slot_key(lane, row, index - 1, nil)
            end
        end
        r.ImGui_EndMenu(UI.ctx)
    end
    if r.ImGui_BeginMenu(UI.ctx, "This clip's mode") then
        for _, entry in ipairs(C.modes) do
            if r.ImGui_MenuItem(UI.ctx, entry.label, nil, slot.key ~= nil and slot.key.mode == entry.key) then
                H.set_slot_key(lane, row, nil, entry.key)
            end
        end
        r.ImGui_EndMenu(UI.ctx)
    end
    if r.ImGui_MenuItem(UI.ctx, "Read the key from its notes") then
        H.read_slot_key(lane, row)
    end
end

function H.slot_context(lane, lane_index, row, slot)
    if not r.ImGui_BeginPopupContextItem(UI.ctx, "##launch_ctx_" .. lane_index .. "_" .. row) then return false end
    if slot then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, slot.name)
        local length_text = H.clip_length_text(slot)
        if length_text then
            r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Loops " .. length_text)
        end
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
        r.ImGui_Separator(UI.ctx)
        if slot.trim_failed then
            r.ImGui_TextColored(UI.ctx, UI.colors.warning or UI.colors.danger, "Loops the whole source: trimming this clip failed")
        end
        if slot.tempo_matched or slot.sectioned or not slot.is_midi then
            if r.ImGui_BeginMenu(UI.ctx, "Tempo: " .. (slot.tempo_matched and "stretched to the project" or "as recorded")) then
                H.draw_clip_tempo_menu(lane, row, slot)
                r.ImGui_EndMenu(UI.ctx)
            end
        end
        if slot.is_midi then
            H.refresh_clip_reading(slot)
            local known = slot.key or (slot.key_read or nil)
            local key_label = "Key: not known"
            if known then
                key_label = "Key: " .. H.key_label(known)
            elseif slot.root then
                key_label = "Key: no one scale, leans on " .. (C.note_names[slot.root + 1] or "?")
            end
            if r.ImGui_BeginMenu(UI.ctx, key_label) then
                H.draw_clip_key_menu(lane, row, slot)
                r.ImGui_EndMenu(UI.ctx)
            end
        end
        r.ImGui_Separator(UI.ctx)
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
            H.prune_lane_track(lane)
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

-- How far the clip was moved, in semitones, or nil when nothing was applied.
-- Taken between the key the clip is in and the key it was fitted to, so it
-- answers the same question for both routes.
function H.key_shift(slot)
    local applied = slot and slot.key_applied
    local from = applied and ((slot.key and slot.key.root) or slot.root)
    if not applied or not from then return nil end
    local base = applied.root - from
    if base > 6 then base = base - 12 elseif base < -6 then base = base + 12 end
    return base
end

function H.key_state_text(slot)
    local applied = slot and slot.key_applied
    if not applied then return "" end
    local shift = H.key_shift(slot)
    local playing = "\nPlaying in " .. H.key_label(applied)
    if (applied.style or "scale") ~= "root" then return playing .. ", scale degrees mapped" end
    if not shift then return playing .. ", transposed" end
    if shift == 0 then return playing .. ", which is where it already sat" end
    return string.format("%s, transposed %d semitone%s %s", playing,
        math.abs(shift), math.abs(shift) == 1 and "" or "s", shift > 0 and "up" or "down")
end

-- A mark in the corner for a clip that is not playing what its file holds. Two
-- shapes rather than one, because the two routes do different things: a triangle
-- for a clip moved bodily, pointing the way it went, and two bars for one recast
-- onto another scale. Drawn rather than written: at six pixels a glyph is at the
-- mercy of whichever font is loaded.
function H.draw_key_mark(draw_list, slot, x, y, width, background)
    if not slot or not slot.key_applied then return end
    local ink = H.mix(background, H.readable_on(background), 0.75)
    local size = UI.scaled(3)
    local right = x + width - UI.scaled(5)
    local top = y + UI.scaled(4)
    if (slot.key_applied.style or "scale") == "root" then
        local shift = H.key_shift(slot) or 0
        if shift == 0 then
            r.ImGui_DrawList_AddRectFilled(draw_list, right - size, top + size * 0.5,
                right + size, top + size * 0.5 + UI.scaled(1.2), ink)
        elseif shift > 0 then
            r.ImGui_DrawList_AddTriangleFilled(draw_list, right - size, top + size,
                right + size, top + size, right, top - size * 0.6, ink)
        else
            r.ImGui_DrawList_AddTriangleFilled(draw_list, right - size, top - size * 0.6,
                right + size, top - size * 0.6, right, top + size, ink)
        end
    else
        local bar = UI.scaled(1.2)
        r.ImGui_DrawList_AddRectFilled(draw_list, right - size, top - size * 0.4,
            right + size, top - size * 0.4 + bar, ink)
        r.ImGui_DrawList_AddRectFilled(draw_list, right - size, top + size * 0.6,
            right + size, top + size * 0.6 + bar, ink)
    end
end

function H.draw_cell(lane, lane_index, row, box_height)
    local width = UI.rounded(C.cell_w)
    local height = box_height or H.cell_height()
    local x, y = r.ImGui_GetCursorScreenPos(UI.ctx)
    -- Asked before the button, not after: IsRectVisible measures from wherever
    -- the cursor is, and the button moves it on to the next cell. Asked
    -- afterwards, every cell reports on its neighbour - and the last one in the
    -- grid, having no neighbour, never drew its waveform.
    local visible = r.ImGui_IsRectVisible(UI.ctx, width, height)
    r.ImGui_InvisibleButton(UI.ctx, "##launch_cell_" .. lane_index .. "_" .. row, width, height)
    local hovered = r.ImGui_IsItemHovered(UI.ctx)
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
    -- An empty tile has its own colour in the theme, apart from the panel it
    -- sits on: a grid of empty slots is most of what you look at.
    local background = UI.colors.clip_bg or UI.colors.child_bg
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
        H.draw_key_mark(draw_list, slot, x, y, width, background)
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
        r.ImGui_SetTooltip(UI.ctx, slot.name .. key_hint .. H.key_state_text(slot) .. follow_note
            .. "\nClick to launch  |  right-click for options"
            .. "\nAlt-drag to another slot to move it, onto the arrange to place it"
            .. "\nDelete empties the outlined slot"
            .. "\nHold Ctrl while dropping on a slot to copy instead")
    end
end

-- Width and height are given rather than assumed: turned on its side this cell
-- is a column header above a clip column, not a row label beside one.
function H.draw_scene_cell(row, box_width, box_height)
    local width = box_width or UI.rounded(C.scene_w)
    local height = box_height or H.cell_height()
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

-- The corner where the scene column meets the lane headers. The table freezes
-- it, so it is the one spot that is always on screen whichever way the grid is
-- scrolled - which makes it the right home for where the song is and what it is
-- counting in. At the end of the toolbar both sat behind every button that can
-- fold away when the window narrows.
-- How tall a lane row is. Following the track means reading the height REAPER
-- gives its TCP, in REAPER's own pixels: the whole point is to line up with the
-- track panel beside it, so this deliberately does not take the script's UI
-- scale. Clamped at both ends - a track collapsed to nothing would leave a row
-- with no room for a clip in it, and a very tall one would push the rest of the
-- grid off screen.
function H.lane_row_height(lane)
    if not L.lane_track_height then return H.cell_height() end
    local track = H.target_track(lane)
    if not track then return H.cell_height() end
    local height = r.GetMediaTrackInfo_Value(track, "I_TCPH") or 0
    if height <= 0 then return H.cell_height() end
    return math.max(UI.rounded(22), math.min(height, UI.rounded(400)))
end

-- What a table row costs on top of the cell drawn inside it. Measured rather
-- than assumed: it is cell padding, and possibly a border, and a theme is free
-- to change either. The measurement subtracts the height this row was actually
-- drawn at, so it stays exact even though the rows differ in height.
function H.note_row_pitch(y, drawn)
    if L.last_row_y and L.last_row_height then
        local measured = (y - L.last_row_y) - L.last_row_height
        if measured >= 0 and measured < UI.rounded(40)
            and math.abs(measured - (L.row_overhead or 0)) > 0.5 then
            L.row_overhead = measured
        end
    end
    L.last_row_y, L.last_row_height = y, drawn
end

-- The height to draw a cell at so that the row it sits in ends up the height the
-- track is. Only while following the track: everywhere else the cell height is
-- the answer and there is nothing to line up with.
function H.lane_draw_height(target)
    if not L.lane_track_height then return target end
    return math.max(UI.rounded(18), target - (L.row_overhead or 0))
end

--------------------------------------------------------------------------------
-- scrolling in step with the arrange
--------------------------------------------------------------------------------
-- Matched by track rather than by pixel. A pixel mapping would only hold if
-- every project track had a lane, in the same order; anchoring on "which track
-- is at the top" works with half the tracks laned and needs no such promise.

function H.arrange_window()
    if not r.JS_Window_FindChildByID then return nil end
    if L.arrange_hwnd and r.ValidatePtr and r.ValidatePtr(L.arrange_hwnd, "HWND") then
        return L.arrange_hwnd
    end
    L.arrange_hwnd = r.JS_Window_FindChildByID(r.GetMainHwnd(), 0x3E8)
    return L.arrange_hwnd
end

-- Which of the two bars above the grid are showing. Stored as a number because
-- it always was: 0, 1 and 2 keep the meaning they had before "toolbar only"
-- joined them, so a saved setting still says what it used to.
C.chrome_all, C.chrome_title, C.chrome_none, C.chrome_toolbar = 0, 1, 2, 3
C.chrome_states = {
    { value = 0, label = "Title bar and toolbar" },
    { value = 1, label = "Title bar only" },
    { value = 3, label = "Toolbar only" },
    { value = 2, label = "Neither" },
}

function H.chrome_label(value)
    for _, state in ipairs(C.chrome_states) do
        if state.value == value then return state.label end
    end
    return C.chrome_states[1].label
end

-- Opened out in the grid's own window; see the caret in the corner.
function H.draw_chrome_popup()
    if L.chrome_request then
        r.ImGui_OpenPopup(UI.ctx, "##launch_chrome")
        L.chrome_request = nil
    end
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_chrome") then return end
    r.ImGui_Text(UI.ctx, "Show above the grid")
    r.ImGui_Separator(UI.ctx)
    local chrome = L.chrome or 0
    for _, state in ipairs(C.chrome_states) do
        if r.ImGui_MenuItem(UI.ctx, state.label, nil, chrome == state.value) then
            Launcher.set_chrome(state.value)
        end
    end
    r.ImGui_EndPopup(UI.ctx)
end

-- Which tracks move when the arrange scrolls, and which are held at the top.
-- A master left in the track list moves; a pinned one does not, and neither
-- does a pinned track. REAPER reports no flag for any of that, so it is read
-- from behaviour: on a scroll, a track in the scrolling area moves by exactly
-- as much. Sampled once a frame, because we scroll the arrange ourselves.
function H.sample_pinning()
    local frame = (r.ImGui_GetFrameCount and r.ImGui_GetFrameCount(UI.ctx)) or 0
    if L.pin_frame == frame then return end
    L.pin_frame = frame
    local position = H.arrange_scroll_pos() or 0
    local shift = position - (L.pin_scroll or position)
    local scrolled = math.abs(shift) > 2
    local was, now, moves = L.pin_y or {}, {}, scrolled and {} or L.pin_moves
    for index = -1, r.CountTracks(0) - 1 do
        local track = (index == -1) and (r.GetMasterTrack and r.GetMasterTrack(0)) or r.GetTrack(0, index)
        local shown = track and (index == -1 or r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1)
        if shown then
            local y = r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0
            now[track] = y
            if scrolled and was[track] then
                moves[track] = math.abs((y - was[track]) + shift) <= 2
            end
        end
    end
    L.pin_y, L.pin_moves, L.pin_scroll = now, moves, position
end

-- The height of the ruler and of anything pinned under it: where the scrolling
-- track area starts inside the arrange window. A track sitting at the top of it
-- reads as this, not as zero, and the user sets the ruler by hand - so it is
-- derived every time from a track's position plus how far the arrange is
-- scrolled, which cancels out. Asked of the tracks that actually scroll and the
-- highest of those wins: measuring from one that is held at the top would put
-- everything above it into the answer and lean the rows over by that much.
function H.arrange_view_top()
    H.sample_pinning()
    local position = H.arrange_scroll_pos() or 0
    local best
    local moves = L.pin_moves or {}
    for track, y in pairs(L.pin_y or {}) do
        if moves[track] then
            local top = y + position
            if not best or top < best then best = top end
        end
    end
    if best then return best end
    local track = r.GetTrack(0, 0)
    if not track then return 0 end
    return (r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0) + position
end

-- How far down the arrange can be dragged. REAPER lets the track panel run on
-- past the last track, and the grid stopping with its last row against the
-- bottom is what made the two drift apart down there. Win32 counts a
-- proportional scrollbar so that the furthest position is max less one page.
function H.arrange_scroll_max()
    local hwnd = H.arrange_window()
    if not hwnd or not r.JS_Window_GetScrollInfo then return nil end
    local ok, _, page, _, maximum = r.JS_Window_GetScrollInfo(hwnd, "v")
    if not ok or not maximum or not page then return nil end
    return math.max(0, maximum - page + 1)
end

-- Empty space under the last row, so the grid reaches as far down as the
-- arrange does. Measured rather than calculated, the way the gap above the
-- first row is: what the grid can do is only known once it has been laid out,
-- so this frame's answer comes from last frame's measurement and settles at
-- once.
function H.tail_gap()
    if not L.align_to_arrange or not L.scenes_as_columns then return 0 end
    local theirs = H.arrange_scroll_max()
    local mine = r.ImGui_GetScrollMaxY and r.ImGui_GetScrollMaxY(UI.ctx)
    if not theirs or not mine then return L.tail or 0 end
    local natural = mine - (L.tail or 0)
    -- Not as far as the arrange, but that less whatever the space above the
    -- first row already carries: those pixels are travelled by the space
    -- closing up, not by the grid scrolling, so counting them twice let the
    -- grid run past the arrange at the very bottom.
    local carried = math.min(H.align_above(), L.align_gap or 0)
    L.tail = math.max(0, math.min(UI.rounded(4000), theirs - carried - natural))
    return L.tail
end

function H.arrange_scroll_pos()
    local hwnd = H.arrange_window()
    if not hwnd or not r.JS_Window_GetScrollInfo then return nil end
    local ok, position = r.JS_Window_GetScrollInfo(hwnd, "v")
    if not ok then return nil end
    return position
end

-- Where each lane row starts inside the table, and how tall the whole thing is.
-- Where the top lane's track actually starts on screen. The arrange window's own
-- rectangle plus the track's offset inside it: the ruler above the tracks is a
-- height the user sets by hand, so this moves whenever they change it.
function H.arrange_track_top()
    local hwnd = H.arrange_window()
    if not hwnd or not r.JS_Window_GetRect then return nil end
    -- The first lane, to match the first row. Asking which lane is currently at
    -- the top of the arrange gives a different answer once the ruler has pushed
    -- every track below it, and then the gap was measured between one lane's
    -- track and another lane's row - which is the jump.
    local lane = L.lanes[1]
    local track = lane and H.target_track(lane)
    if not track then return nil end
    local ok, _, top = r.JS_Window_GetRect(hwnd)
    if not ok then return nil end
    return top + (r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0)
end

-- The gap above the first row, grown until the row starts where its track does.
-- Corrected rather than calculated: the answer depends on the height of our own
-- bars, on the ruler, and on where the window sits, so it is measured from the
-- result and nudged, which settles in a frame and follows the ruler being
-- dragged. Only ever grows the header row - space above the window cannot be
-- taken away, and the caret in the corner is there to fold our own bars off.
-- Whatever sits above the first lane's track inside the scrolling area: a
-- master left in the track list, and any track that has no lane. It scrolls
-- away in the arrange, and since the grid has no row for it, the gap above the
-- first row is what has to give way in its place.
-- The first lane whose track is not held at the top. Everything above it is
-- pinned, and a pinned row has to be measured from, not scrolled past.
function H.first_scrolling_lane()
    H.sample_pinning()
    local moves = L.pin_moves or {}
    for index, lane in ipairs(L.lanes) do
        local track = H.target_track(lane)
        if track and moves[track] ~= false then return index end
    end
    return 1
end

function H.align_above()
    local lane = L.lanes[H.first_scrolling_lane()]
    local track = lane and H.target_track(lane)
    if not track then return 0 end
    local position = H.arrange_scroll_pos() or 0
    return math.max(0, (r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0) + position - H.arrange_view_top())
end

-- What is drawn, as against what is stored. The stored gap is the one that puts
-- the first row on its track while nothing is scrolled; scrolling then eats
-- into it, because on screen that space is the master band and the master
-- scrolls away with everything else.
function H.align_shown(stored)
    local position = H.arrange_scroll_pos() or 0
    return math.max(0, (stored or 0) - math.min(position, H.align_above()))
end

function H.align_offset()
    if not L.align_to_arrange or not L.scenes_as_columns then return 0 end
    -- The gap lives above the first row, so it only means anything while the
    -- grid is at the top. Scrolled down it is off screen anyway, and measuring
    -- there would chase a row that is no longer the one being looked at.
    local scrolled = (r.ImGui_GetScrollY and r.ImGui_GetScrollY(UI.ctx)) or 0
    if scrolled > 2 then return H.align_shown(L.align_gap) end
    -- And only while the arrange is at its top as well. Scrolled, the track has
    -- moved up the screen for a reason that scrolling answers; correcting the
    -- gap here would swallow that movement and pull the rows up with it.
    local theirs = H.arrange_scroll_pos()
    if theirs and theirs > 2 then return H.align_shown(L.align_gap) end
    local wanted = H.arrange_track_top()
    if not wanted or not L.first_row_y then return H.align_shown(L.align_gap) end
    local drift = wanted - L.first_row_y
    if math.abs(drift) > 1 then
        L.align_gap = math.max(0, math.min(UI.rounded(400), (L.align_gap or 0) + drift))
    end
    return H.align_shown(L.align_gap)
end

function H.lane_offsets()
    local offsets, y = {}, 0
    for index, lane in ipairs(L.lanes) do
        offsets[index] = y
        y = y + H.lane_draw_height(H.lane_row_height(lane)) + (L.row_overhead or 0)
    end
    return offsets, y
end

function H.lane_at_offset(offsets, y)
    local best = 1
    for index, offset in ipairs(offsets) do
        if offset <= y + 2 then best = index end
    end
    return best
end

-- The topmost lane whose track is at or above the top of the track panel.
function H.lane_at_arrange_top()
    local view_top = H.arrange_view_top()
    local moves = L.pin_moves or {}
    local best, best_y = nil, nil
    for index, lane in ipairs(L.lanes) do
        local track = H.target_track(lane)
        -- A pinned track never reaches the top of the scrolling area, however
        -- its position reads: it is above that area, not in it.
        if track and moves[track] ~= false then
            local y = (r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0) - view_top
            if y <= 2 and (not best_y or y > best_y) then best, best_y = index, y end
        end
    end
    return best or 1
end

-- Residual is how far into that lane's row the grid has already scrolled. Aiming
-- at the top of the track instead would only ever line up when the grid happens
-- to sit exactly on a row boundary, which is the slack you feel while dragging.
function H.scroll_arrange_to_track(track, residual)
    local hwnd = H.arrange_window()
    if not hwnd or not r.JS_Window_SetScrollPos or not track then return end
    local position = H.arrange_scroll_pos()
    if not position then return end
    -- I_TCPY counts from the top of the scrolling track area, so it already
    -- says how far this track is from where the grid's top row sits. What it
    -- does not know is the band above the first lane's track - a master left in
    -- the list. Scrolling the arrange, the space above the first row closes up
    -- and carries the rows over that band; driving the other way that space
    -- never moves on its own, so anything it cannot cover has to come off here.
    -- Without this the arrange was sent the whole band too far, which with no
    -- space to give is exactly the height of the master.
    local shortfall = 0
    if L.align_to_arrange and L.scenes_as_columns then
        shortfall = math.max(0, H.align_above() - (L.align_gap or 0))
    end
    local offset = (r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0) + (residual or 0) - shortfall
    -- Close enough is left alone: REAPER scrolls in its own steps, and chasing
    -- the last two pixels is what makes two views fight each other.
    if math.abs(offset) < 3 then return end
    -- Whole pixels: track heights and our own scroll are both fractional, and
    -- the scrollbar takes an integer or throws - which aborts the frame with
    -- the grid's table still open.
    r.JS_Window_SetScrollPos(hwnd, "v", math.floor(math.max(0, position + offset) + 0.5))
end

-- One side moves per frame, ours first. Both remembered positions are read back
-- afterwards, so the move we just caused is not read as the other side moving.
function H.sync_scroll()
    local mode = L.scroll_sync or "off"
    if mode == "off" or not L.scenes_as_columns or #L.lanes == 0 then return end
    if not r.ImGui_GetScrollY then return end
    local mine = r.ImGui_GetScrollY(UI.ctx) or 0
    local theirs = H.arrange_scroll_pos()
    if not theirs then return end
    local offsets = H.lane_offsets()
    local moved_mine = L.sync_mine and math.abs(mine - L.sync_mine) > 2
    local moved_theirs = L.sync_theirs and math.abs(theirs - L.sync_theirs) > 2
    if moved_mine and mode == "both" then
        local index = H.lane_at_offset(offsets, mine)
        local lane = L.lanes[index]
        if lane then
            H.scroll_arrange_to_track(H.target_track(lane), mine - (offsets[index] or 0))
        end
        L.sync_mine = mine
        L.sync_theirs = H.arrange_scroll_pos() or theirs
    elseif moved_theirs then
        local index = H.lane_at_arrange_top()
        local track = L.lanes[index] and H.target_track(L.lanes[index])
        if offsets[index] and r.ImGui_SetScrollY then
            -- Where that track sits inside its own row, carried across, so the
            -- two stay level between row boundaries as well as on them.
            local into_row = H.arrange_view_top()
                - (track and r.GetMediaTrackInfo_Value(track, "I_TCPY") or 0)
            -- What the gap above the first row could not swallow. It stands in
            -- for the master band while that scrolls past, but only as far as
            -- it goes; short of it, the grid starts scrolling that much sooner.
            local spare = math.max(0, math.min(theirs, H.align_above()) - (L.align_gap or 0))
            -- Measured from the first lane that scrolls: any pinned lane above
            -- it stays where it is in the arrange, so its height is not part of
            -- what the grid has to scroll past.
            local anchor = offsets[H.first_scrolling_lane()] or 0
            -- Added after the floor, not inside it: while the band is still
            -- going past, the row-and-track sum is negative, and folding the
            -- spare in there would let the floor swallow it.
            local target = math.max(0, offsets[index] - anchor + into_row) + spare
            -- Never further than the grid can actually go. The arrange holds
            -- more than the grid does - the lane tracks when they are shown, or
            -- simply a taller window with nothing to scroll - and asking for a
            -- position out of reach made the next frame read the shortfall as
            -- the user moving the grid, which dragged the arrange back up. Now
            -- the grid runs out quietly and the arrange keeps going.
            local limit = r.ImGui_GetScrollMaxY and r.ImGui_GetScrollMaxY(UI.ctx)
            if limit then target = math.max(0, math.min(target, limit)) end
            r.ImGui_SetScrollY(UI.ctx, target)
            -- What was asked for, not what ImGui still reports: it applies a
            -- scroll at the end of the frame, so reading it back here returns
            -- the old position and the next frame reads our own move as yours.
            L.sync_mine = target
        else
            L.sync_mine = mine
        end
        L.sync_theirs = theirs
    else
        L.sync_mine, L.sync_theirs = mine, theirs
    end
end

function H.draw_grid_corner(box_width, box_height)
    local width = box_width or UI.rounded(C.scene_w)
    local height = box_height or UI.rounded(C.cell_h)
    local x, y = r.ImGui_GetCursorScreenPos(UI.ctx)
    r.ImGui_Dummy(UI.ctx, width, height)
    local hovered = r.ImGui_IsItemHovered(UI.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(UI.ctx)
    local playing = (r.GetPlayState() & 1) == 1
    local bar = H.song_bar(H.heard_pos())
    local top = bar and ("Bar " .. tostring(bar)) or "Stopped"
    local meter = H.meter_label()
    local _, line_height = r.ImGui_CalcTextSize(UI.ctx, "A")
    local ink = (playing and bar) and UI.colors.accent or UI.colors.text_dim
    -- Centred in a cell's worth at the top, not in the whole box. Lining the
    -- rows up with the arrange grows this cell downwards, and the readout
    -- belongs beside the scene buttons rather than halfway down the empty space.
    local band = math.min(height, UI.rounded(C.cell_h))
    if line_height * 2 + UI.scaled(2) <= band then
        H.text_centered(draw_list, x + width * 0.5, y + band * 0.5 - line_height * 0.55, ink, top)
        H.text_centered(draw_list, x + width * 0.5, y + band * 0.5 + line_height * 0.55,
            UI.colors.text_dim, meter)
    else
        -- One line when two will not fit: the bar is the half you glance at.
        H.text_centered(draw_list, x + width * 0.5, y + band * 0.5, ink, top .. "  " .. meter)
    end
    -- A caret in the corner, folding the bars above away. Hit-tested by hand
    -- rather than as a widget: the corner itself is a plain spacer, so nothing
    -- competes for the click.
    local size = UI.scaled(9)
    local mark_x, mark_y = x + UI.scaled(3), y + UI.scaled(3)
    local over_mark = r.ImGui_IsMouseHoveringRect
        and r.ImGui_IsMouseHoveringRect(UI.ctx, mark_x, mark_y, mark_x + size, mark_y + size)
    local chrome = L.chrome or 0
    local mark_ink = over_mark and UI.colors.accent or UI.colors.text_dim
    local half = size * 0.32
    local centre_x, centre_y = mark_x + size * 0.5, mark_y + size * 0.5
    -- Pointing down while both bars are showing, up once anything is folded
    -- away. Four states are too many to read off a shape, so the caret says
    -- only whether something is hidden and the menu says what.
    if chrome == C.chrome_all then
        r.ImGui_DrawList_AddTriangleFilled(draw_list, centre_x - half, centre_y - half * 0.7,
            centre_x + half, centre_y - half * 0.7, centre_x, centre_y + half, mark_ink)
    else
        r.ImGui_DrawList_AddTriangleFilled(draw_list, centre_x - half, centre_y + half * 0.7,
            centre_x + half, centre_y + half * 0.7, centre_x, centre_y - half, mark_ink)
    end
    if over_mark and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(UI.ctx, 0) then
        -- Asked for here, opened outside the table: a popup opened from inside
        -- the table's own scrolling window gets an id the grid cannot match.
        L.chrome_request = true
    end
    if over_mark then
        r.ImGui_SetTooltip(UI.ctx, "Showing " .. H.chrome_label(chrome) .. " - click to choose")
    elseif hovered then
        r.ImGui_SetTooltip(UI.ctx, "Where the song is, and the time signature it is counting in")
    end
end

-- Solo reads and writes REAPER's own field rather than a copy of our own, so
-- the header agrees with the track panel however the solo got there.
function H.lane_soloed(lane)
    local track = H.target_track(lane)
    if not track then return false end
    return (r.GetMediaTrackInfo_Value(track, "I_SOLO") or 0) > 0.5
end

function H.toggle_lane_solo(lane)
    local track = H.target_track(lane)
    if not track then return end
    local on = H.lane_soloed(lane)
    if r.CSurf_OnSoloChange then
        -- Through the control surface layer, so REAPER honours its own solo
        -- preference and anything listening hears about it.
        r.CSurf_OnSoloChange(track, on and 0 or 1)
    else
        r.SetMediaTrackInfo_Value(track, "I_SOLO", on and 0 or 1)
    end
    r.UpdateArrange()
end

function H.reset_lane_volume(lane)
    local track = H.target_track(lane)
    if not track then return end
    r.SetMediaTrackInfo_Value(track, "D_VOL", 1)
    r.Undo_OnStateChange2(0, "Track volume")
end

-- The target track's volume, on REAPER's own fader travel so the knob sits
-- where the TCP fader sits. Hit-tested by hand, like everything else in a lane
-- header: the header is a single ImGui item, and a real widget here would take
-- the header's clicks with it.
function H.draw_lane_volume(lane, lane_index, x, y, width, background, ink, tinted)
    local track = H.target_track(lane)
    if not track then return end
    local radius = UI.scaled(5)
    local bar = UI.scaled(4)
    local pad = radius + UI.scaled(3)
    local left, right = x + pad, x + width - pad
    if right - left < UI.scaled(20) then return end

    local volume = r.GetMediaTrackInfo_Value(track, "D_VOL") or 1
    local db = volume > 0.0000001 and (20 * math.log(volume, 10)) or -150
    local position = math.max(0, math.min(1, (r.DB2SLIDER(db) or 0) / 1000))

    local reach = UI.scaled(4)
    local over = r.ImGui_IsMouseHoveringRect
        and r.ImGui_IsMouseHoveringRect(UI.ctx, x, y - radius - reach, x + width, y + radius + reach)
    local drag = L.vol_drag
    local dragging = drag and drag.lane == lane_index

    local function apply(wanted)
        wanted = math.max(0, math.min(1, wanted))
        r.SetMediaTrackInfo_Value(track, "D_VOL", 10 ^ ((r.SLIDER2DB(wanted * 1000) or 0) / 20))
        return wanted
    end

    -- Read before the drag, not after. The second press of a double click
    -- also reports as an ordinary click, so a drag started here first would
    -- swallow the double click every time.
    if over and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(UI.ctx, 0) then
        r.SetMediaTrackInfo_Value(track, "D_VOL", 1)
        r.Undo_OnStateChange2(0, "Track volume")
        position = math.max(0, math.min(1, (r.DB2SLIDER(0) or 0) / 1000))
        L.vol_drag = nil
        dragging = false
    elseif over and not dragging and r.ImGui_IsMouseClicked(UI.ctx, 0) then
        -- Where it was and where the pointer was, so the knob moves with the
        -- hand rather than jumping under it. A click that does not move is
        -- then no change at all, which is what leaves room for the double.
        L.vol_drag = { lane = lane_index, from = r.ImGui_GetMousePos(UI.ctx), position = position }
        dragging = true
    elseif dragging then
        if r.ImGui_IsMouseDown(UI.ctx, 0) then
            local mouse_x = r.ImGui_GetMousePos(UI.ctx)
            position = apply(drag.position + (mouse_x - drag.from) / (right - left))
        else
            L.vol_drag = nil
            dragging = false
            -- One undo point for the whole drag, the way REAPER's own fader
            -- behaves, and none at all for a press that never moved.
            if math.abs(position - drag.position) > 0.0005 then
                r.Undo_OnStateChange2(0, "Track volume")
            end
        end
    end
    local draw_list = r.ImGui_GetWindowDrawList(UI.ctx)
    -- On a tinted header the track colour IS the background, so a fader
    -- filled with it comes out identical to what it sits on. Same rule as
    -- everything else in a coloured header: the foreground is derived from
    -- the background it lands on. Groove, fill and knob are three steps in
    -- the same direction, so the order reads whether the track is near black
    -- or near white.
    local colour = tinted and H.mix(background, ink, 0.75) or H.lane_color(lane)
    -- The groove is lifted off whatever the header is painted with, so it reads
    -- on a tinted header and on the plain one alike.
    local groove = tinted and H.mix(background, ink, 0.28)
        or H.mix(UI.colors.child_bg, UI.colors.text, 0.10)
    local knob_x = left + (right - left) * position
    r.ImGui_DrawList_AddRectFilled(draw_list, left, y - bar * 0.5, right, y + bar * 0.5, groove, bar * 0.5)
    if knob_x > left then
        r.ImGui_DrawList_AddRectFilled(draw_list, left, y - bar * 0.5, knob_x, y + bar * 0.5, colour, bar * 0.5)
    end
    local knob_ink = (over or dragging) and UI.colors.accent or (tinted and ink or UI.colors.text)
    r.ImGui_DrawList_AddCircleFilled(draw_list, knob_x, y, radius, knob_ink)
    -- A ring in the header's own colour, so the knob stays a separate thing
    -- from the bar it sits on however close the two tints end up.
    r.ImGui_DrawList_AddCircle(draw_list, knob_x, y, radius,
        tinted and background or UI.colors.border, 0, UI.scaled(1))

    if over or dragging then
        local shown = db <= -144 and "-inf dB" or string.format("%+.1f dB", db)
        r.ImGui_SetTooltip(UI.ctx, H.lane_label(lane) .. "  " .. shown
            .. "\nDrag to set  |  double click for 0 dB")
    end
    -- Whether the pointer is on the fader, which is what the header needs to
    -- know before it treats a click as its own. Not whether one was drawn.
    return (over or dragging) and true or false
end

function H.draw_lane_header(lane, lane_index, box_width, box_height)
    local width = box_width or UI.rounded(C.cell_w)
    local height = box_height or UI.rounded(C.cell_h)
    local x, y = r.ImGui_GetCursorScreenPos(UI.ctx)
    r.ImGui_InvisibleButton(UI.ctx, "##launch_head_" .. lane_index, width, height)
    local hovered = r.ImGui_IsItemHovered(UI.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(UI.ctx)
    local orphaned = H.lane_orphaned(lane)
    local color = orphaned and UI.colors.danger or H.lane_color(lane)
    local owned = lane.owner == "launcher"
    -- Filling the header with the track colour means nothing in it can be styled
    -- from the theme any more: a track can be any colour, so every foreground is
    -- derived from the background it actually lands on. A dead lane keeps the
    -- danger colour, which is the one case the track colour must not win.
    local tinted = L.color_headers and not orphaned
    local background, ink
    if tinted then
        local fill, fill_ink = H.legible_fill(color)
        -- Hover shades away from the ink: a pale track pales further, a dark one
        -- deepens. The change is as visible as shading the other way and the text
        -- gets easier to read rather than harder.
        background = hovered and H.mix(fill, H.away_from(fill_ink), 0.10) or fill
        ink = H.readable_on(background)
    else
        background = hovered and UI.colors.card_hover or UI.colors.card_bg
    end
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, background, UI.scaled(4))
    if not tinted then
        r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + UI.scaled(3), y + height, color, UI.scaled(4))
    end
    local edge, edge_width
    if tinted then
        edge = (owned or orphaned) and ink or H.mix(background, ink, 0.28)
        edge_width = (owned or orphaned) and UI.scaled(2) or UI.scaled(1)
    else
        edge = (owned or orphaned) and color or UI.colors.border
        edge_width = (owned or orphaned) and UI.scaled(2) or UI.scaled(1)
    end
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, edge, UI.scaled(4), 0, edge_width)
    local label_color = orphaned and UI.colors.danger or (ink or (owned and color or UI.colors.text))
    -- Centred rather than pinned near the top: turned on its side a lane header
    -- is as tall as a clip row, which in waveform cells is twice this height.
    local _, label_height = r.ImGui_CalcTextSize(UI.ctx, "A")
    -- A strip at the foot for the fader, but only where the row is tall enough
    -- to give it up without squeezing the name. Everything above is centred in
    -- what is left, so a short row looks exactly as it did.
    local strip = 0
    if L.lane_volume and not orphaned then
        local wanted = UI.scaled(18)
        if height >= label_height + wanted + UI.scaled(8) then strip = wanted end
    end
    local top_h = height - strip
    r.ImGui_DrawList_AddText(draw_list, x + UI.scaled(10),
        math.floor(y + (top_h - label_height) * 0.5 + 0.5), label_color,
        H.truncate(H.lane_label(lane), width - UI.scaled(76)))

    -- The two little squares at the right of a header. Drawn on top of the
    -- header button rather than as widgets of their own, so the header keeps a
    -- single ImGui id and the clicks stay ours to sort out.
    local badge = UI.rounded(16)
    local badge_y = math.floor(y + (top_h - badge) * 0.5 + 0.5)
    local function draw_badge(right_inset, glyph, active, active_bg, tip, on_click)
        local bx = math.floor(x + width - UI.scaled(right_inset) + 0.5)
        local over = r.ImGui_IsMouseHoveringRect(UI.ctx, bx, badge_y, bx + badge, badge_y + badge)
        -- On a tinted header a badge cannot borrow the theme's dark tile: on a
        -- dark track colour it would vanish into it. It is lifted off the
        -- background it actually sits on, and its glyph read back off that.
        local bg
        if active then
            bg = active_bg
        elseif tinted then
            bg = H.mix(background, H.away_from(ink), over and 0.30 or 0.18)
        else
            bg = over and UI.colors.card_hover or UI.colors.child_bg
        end
        r.ImGui_DrawList_AddRectFilled(draw_list, bx, badge_y, bx + badge, badge_y + badge, bg, UI.scaled(3))
        local edge = over and UI.colors.accent or (tinted and H.mix(background, ink, 0.45) or UI.colors.border)
        r.ImGui_DrawList_AddRect(draw_list, bx, badge_y, bx + badge, badge_y + badge, edge, UI.scaled(3), 0, UI.scaled(1))
        local glyph_ink = active and UI.colors.badge_text or (tinted and H.readable_on(bg) or UI.colors.text_dim)
        H.text_centered(draw_list, bx + badge * 0.5, badge_y + badge * 0.5, glyph_ink, glyph)
        if over and r.ImGui_IsMouseClicked(UI.ctx, 0) then on_click() end
        if over then r.ImGui_SetTooltip(UI.ctx, tip) end
        return over
    end

    local silenced = H.lane_silenced(lane)
    local badge_hovered = draw_badge(44, "A", silenced, UI.colors.danger,
        silenced and "This track's arrangement is muted, clips still play\nClick to let the arrangement through"
            or "Mute this track's arrangement, keep its clips audible",
        function() H.toggle_lane_arrangement(lane) end)

    local soloed = H.lane_soloed(lane)
    local solo_hovered = draw_badge(64, "S", soloed, UI.colors.accent,
        soloed and "Soloed  |  click to release" or "Solo this track",
        function() H.toggle_lane_solo(lane) end)
    badge_hovered = badge_hovered or solo_hovered
    if L.recording or #L.captured > 0 then
        local count = H.captured_for(H.target_track(lane))
        local live = (lane.current and lane.current.started) and "+" or ""
        local text = tostring(count) .. live
        local text_width, text_height = r.ImGui_CalcTextSize(UI.ctx, text)
        local count_ink = count > 0 and UI.colors.accent or UI.colors.text_dim
        if tinted then count_ink = count > 0 and ink or H.mix(background, ink, 0.72) end
        r.ImGui_DrawList_AddText(draw_list, x + width - UI.scaled(82) - text_width,
            math.floor(y + (top_h - text_height) * 0.5 + 0.5), count_ink, text)
    end

    local stop_x = x + width - UI.scaled(15)
    local stop_y = y + top_h * 0.5
    local stop_size = UI.scaled(4)
    local stop_ink = owned and UI.colors.danger or UI.colors.text_dim
    if tinted and not owned then stop_ink = H.mix(background, ink, 0.72) end
    r.ImGui_DrawList_AddRectFilled(draw_list, stop_x - stop_size, stop_y - stop_size, stop_x + stop_size, stop_y + stop_size, stop_ink)
    local on_fader = false
    if strip > 0 then
        on_fader = H.draw_lane_volume(lane, lane_index, x + UI.scaled(6),
            math.floor(y + top_h + strip * 0.5 + 0.5), width - UI.scaled(12),
            background, ink, tinted)
    end
    if not badge_hovered and not on_fader and r.ImGui_IsItemClicked(UI.ctx, 0) then
        H.stop_lane(lane)
        -- And bring the track with it: with the track panel collapsed away,
        -- the header is the only handle on that track left.
        local track = H.target_track(lane)
        if track then
            r.SetOnlyTrackSelected(track)
            r.UpdateArrange()
        end
    end
    if r.ImGui_BeginPopupContextItem(UI.ctx, "##launch_head_ctx_" .. lane_index) then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, H.lane_label(lane))
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Stop lane") then H.stop_lane(lane) end
        if r.ImGui_MenuItem(UI.ctx, "Mute this track's arrangement", nil, H.lane_silenced(lane)) then
            H.toggle_lane_arrangement(lane)
        end
        local track = H.target_track(lane)
        local at_unity = not track or math.abs((r.GetMediaTrackInfo_Value(track, "D_VOL") or 1) - 1) < 0.0005
        if r.ImGui_MenuItem(UI.ctx, "Reset volume to 0 dB", nil, false, not at_unity) then
            H.reset_lane_volume(lane)
        end
        if r.ImGui_MenuItem(UI.ctx, "Solo this track", nil, H.lane_soloed(lane)) then
            H.toggle_lane_solo(lane)
        end
        if r.ImGui_MenuItem(UI.ctx, "Name to look for in another project...") then
            H.ask_match(lane)
        end
        if r.ImGui_MenuItem(UI.ctx, "Select target track") then
            if track then r.SetOnlyTrackSelected(track) r.UpdateArrange() end
        end
        r.ImGui_Separator(UI.ctx)
        -- Removing a lane is deleting the track now, which is REAPER's job.
        -- Emptying one is still ours.
        local filled = #lane.slots > 0
        if r.ImGui_MenuItem(UI.ctx, "Clear this lane's clips", nil, false, filled) then
            r.Undo_BeginBlock()
            local cleared = H.clear_lane(lane)
            r.Undo_EndBlock("Clear launcher lane", -1)
            H.save()
            r.UpdateArrange()
            L.status = cleared == 1 and "Cleared 1 clip" or ("Cleared " .. tostring(cleared) .. " clips")
        end
        r.ImGui_EndPopup(UI.ctx)
    end
    if hovered and not on_fader then
        r.ImGui_SetTooltip(UI.ctx, H.lane_label(lane) .. (owned and "\nLauncher owns this track  |  click to hand it back" or "\nPlaying its arrangement"))
    end
end

--------------------------------------------------------------------------------
-- public interface
--------------------------------------------------------------------------------

function Launcher.init(context)
    UI = context
    -- How the set menu behaves is a habit, not a property of a project, so it
    -- lives with the script rather than in the project file.
    L.color_headers = r.GetExtState(C.ext_section, "color_headers") == "1"
    L.lane_volume = r.GetExtState(C.ext_section, "lane_volume") ~= "0"
    L.scenes_as_columns = r.GetExtState(C.ext_section, "scenes_as_columns") == "1"
    L.lane_track_height = r.GetExtState(C.ext_section, "lane_track_height") == "1"
    L.align_to_arrange = r.GetExtState(C.ext_section, "align_to_arrange") == "1"
    L.chrome = math.max(0, math.min(3, math.floor(tonumber(r.GetExtState(C.ext_section, "chrome")) or 0)))
    local sync = r.GetExtState(C.ext_section, "scroll_sync")
    L.scroll_sync = (sync == "follow" or sync == "both") and sync or "off"
    L.set_show_all = r.GetExtState(C.ext_section, "set_show_all") == "1"
    L.set_create_tracks = r.GetExtState(C.ext_section, "set_create_tracks") == "1"
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
    H.run_set_prompt()
    H.run_match_prompt()
    H.run_library_prompt()
    H.run_new_folder_prompt()
    H.update_external_drag()
    H.update_drag_out()
    local track_count = r.CountTracks(0)
    if track_count ~= L.track_count then
        L.track_count = track_count
        L.tidy_wanted = true
    end
    if L.tidy_wanted then H.tidy_lane_tracks() end
    H.keep_lane_order()
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
    local step = H.quantize_qn(from)
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

-- Opening a popup from inside another popup would give it an id built on the
-- open popup's stack, and the toolbar's own BeginPopup would never match it.
-- The overflow menu therefore asks for a popup by name and the bar opens it.
function H.request_popup(name)
    L.popup_request = name
end

-- Fills the bar from the left with whatever fits and folds the rest into a menu.
-- A group boundary gets a wider gap; items marked keep are paid for before
-- anything else, so even a narrow window still shows what you reach for while a
-- clip is playing.
function H.draw_toolbar_row(items, tail_width)
    local gap = UI.rounded(8)
    local group_gap = UI.rounded(20)
    local overflow_width = UI.rounded(30)
    local available = r.ImGui_GetContentRegionAvail(UI.ctx)

    local function spacing(item, previous)
        if not previous then return 0 end
        return item.group ~= previous.group and group_gap or gap
    end

    local total, previous = 0, nil
    for _, item in ipairs(items) do
        total = total + item.width + spacing(item, previous)
        previous = item
    end
    local budget = available - (tail_width or 0)
    local overflowing = total > budget
    if overflowing then budget = budget - overflow_width - gap end

    local reserved = 0
    previous = nil
    for _, item in ipairs(items) do
        if item.keep then reserved = reserved + item.width + spacing(item, previous) end
        previous = item
    end

    local used, drawn, spill, stopped = 0, nil, {}, false
    for _, item in ipairs(items) do
        local cost = item.width + spacing(item, drawn)
        local fits = not overflowing
        if item.keep then
            reserved = math.max(0, reserved - item.width - gap)
            fits = true
        elseif stopped then
            -- Once one item has fallen off the end, everything after it follows.
            -- Letting a narrower button jump the queue leaves a hole in an order
            -- people read from left to right, and the bar stops being a list.
            fits = false
        elseif not fits then
            fits = (used + cost + reserved) <= budget
            if not fits then stopped = true end
        end
        if fits then
            if drawn then r.ImGui_SameLine(UI.ctx, 0, spacing(item, drawn)) end
            item.draw()
            used = used + cost
            drawn = item
        else
            spill[#spill + 1] = item
        end
    end

    local any = drawn ~= nil
    if #spill > 0 then
        if any then r.ImGui_SameLine(UI.ctx, 0, gap) end
        if r.ImGui_Button(UI.ctx, "...", overflow_width, UI.rounded(26)) then
            r.ImGui_OpenPopup(UI.ctx, "##launch_overflow")
        end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "The rest of the toolbar, which the window is too narrow to show")
        end
        any = true
        if r.ImGui_BeginPopup(UI.ctx, "##launch_overflow") then
            local group = nil
            for _, item in ipairs(spill) do
                if group and item.group ~= group then r.ImGui_Separator(UI.ctx) end
                group = item.group
                item.menu()
            end
            r.ImGui_EndPopup(UI.ctx)
        end
    end
    return any
end

-- Three groups, in the order you meet them: what you touch while a clip is
-- playing, what builds the grid, and what is set once per project. The last
-- group is also the first to fold away, which is why it comes last.
function H.toolbar_items()
    local items = {}
    local function add(item) items[#items + 1] = item end

    local armed = L.recording
    local record_label = "Record"
    if L.record_stop_at then
        record_label = "Stopping"
    elseif armed then
        record_label = "Recording " .. tostring(H.take_count())
    end
    add({ group = 1, width = UI.rounded(armed and 104 or 88), keep = true,
        draw = function()
            if armed then
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.danger)
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.danger)
            end
            if r.ImGui_Button(UI.ctx, record_label, UI.rounded(armed and 104 or 88), UI.rounded(26)) then
                H.set_recording(not armed)
            end
            if armed then r.ImGui_PopStyleColor(UI.ctx, 2) end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Keep what you play instead of clearing it away.\nClips are already sitting at the right place in time, so this only\nstops them being removed when they finish. Arm it first and then\nplay, or arm it while something is already running; both work.\nThe count includes clips still sounding. Stop to decide what to\ndo with the take.")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, record_label, nil, armed) then H.set_recording(not armed) end
        end })

    if #L.captured > 0 and not L.recording then
        add({ group = 1, width = UI.rounded(78), keep = true,
            draw = function()
                if r.ImGui_Button(UI.ctx, "Keep " .. tostring(#L.captured), UI.rounded(78), UI.rounded(26)) then H.keep_take() end
                if r.ImGui_IsItemHovered(UI.ctx) then
                    r.ImGui_SetTooltip(UI.ctx, "Move the captured clips onto their own tracks and unmute them")
                end
            end,
            menu = function()
                if r.ImGui_MenuItem(UI.ctx, "Keep " .. tostring(#L.captured) .. " captured clips") then H.keep_take() end
            end })
        add({ group = 1, width = UI.rounded(72), keep = true,
            draw = function()
                if r.ImGui_Button(UI.ctx, "Discard", UI.rounded(72), UI.rounded(26)) then H.discard_take() end
            end,
            menu = function()
                if r.ImGui_MenuItem(UI.ctx, "Discard the take") then H.discard_take() end
            end })
    end

    add({ group = 1, width = UI.rounded(74), keep = true,
        draw = function()
            if r.ImGui_Button(UI.ctx, "Stop all", UI.rounded(74), UI.rounded(26)) then H.stop_all_quantized() end
            if r.ImGui_IsItemHovered(UI.ctx) then r.ImGui_SetTooltip(UI.ctx, "Every lane returns to its arrangement on the next boundary") end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Stop all") then H.stop_all_quantized() end
        end })

    -- Captured before the button: clicking it flips the flag, and testing the
    -- flag again afterwards would skip the pop and unbalance the style stack.
    local song_muted = L.arrangement_muted
    add({ group = 1, width = UI.rounded(102),
        draw = function()
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
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Mute song", nil, song_muted) then H.toggle_arrangement_mute() end
        end })

    add({ group = 1, width = UI.rounded(66),
        draw = function()
            if r.ImGui_Button(UI.ctx, "Reset", UI.rounded(66), UI.rounded(26)) then H.reset_all() end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Everything back to normal, right now.\nClips stop, every muted arrangement item is restored,\nper track mutes are cleared and the song mute goes off.\nPlayback keeps rolling.")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Reset everything") then H.reset_all() end
        end })

    local orphans = H.orphan_count()
    if orphans > 0 then
        local label = orphans == 1 and "Forget 1 lane" or ("Forget " .. tostring(orphans) .. " lanes")
        add({ group = 2, width = UI.rounded(120), keep = true,
            draw = function()
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.danger)
                if r.ImGui_Button(UI.ctx, label, UI.rounded(120), UI.rounded(26)) then H.forget_orphans() end
                r.ImGui_PopStyleColor(UI.ctx, 1)
                if r.ImGui_IsItemHovered(UI.ctx) then
                    r.ImGui_SetTooltip(UI.ctx, "Their track was deleted, so these lanes are off the grid.\nUndo the track deletion and they come back with their clips;\nthis throws the clips away for good.")
                end
            end,
            menu = function()
                if r.ImGui_MenuItem(UI.ctx, label) then H.forget_orphans() end
            end })
    end

    add({ group = 2, width = UI.rounded(76),
        draw = function()
            if r.ImGui_Button(UI.ctx, "+ Scene", UI.rounded(76), UI.rounded(26)) then H.scene_from_cursor(nil) end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Take a slice of the arrangement at the edit cursor into the next free row.\nWhatever each track is playing there becomes a clip, and tracks without a lane get one.")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Take a scene from the edit cursor") then H.scene_from_cursor(nil) end
        end })

    add({ group = 2, width = UI.rounded(70),
        draw = function()
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
        end,
        menu = function()
            r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, tostring(L.rows) .. " scene rows")
            if r.ImGui_MenuItem(UI.ctx, "One row more", nil, false, L.rows < C.max_rows) then
                L.rows = L.rows + 1
                H.save()
            end
            if r.ImGui_MenuItem(UI.ctx, "One row fewer", nil, false, L.rows > 1) then
                L.rows = L.rows - 1
                H.save()
            end
        end })

    -- Quantize, run-up and buffer are one subject: when a clip is allowed to
    -- start. They live behind one button, which carries the quantize in its
    -- label because that is the one you reach for mid-jam.
    local quantize_label = "1 bar"
    for _, option in ipairs(QUANTIZE_OPTIONS) do
        if math.abs(option.value - L.quantize) < 0.001 then quantize_label = option.label break end
    end
    add({ group = 3, width = UI.rounded(120),
        draw = function()
            if r.ImGui_Button(UI.ctx, "Timing: " .. quantize_label, UI.rounded(120), UI.rounded(26)) then
                r.ImGui_OpenPopup(UI.ctx, "##launch_timing")
            end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Launch quantize, clip run-up and REAPER's media buffer")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Timing: " .. quantize_label .. "...") then H.request_popup("##launch_timing") end
        end })

    local following = L.follow_enabled
    add({ group = 3, width = UI.rounded(88),
        draw = function()
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
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Follow actions", nil, following) then
                L.follow_enabled = not following
                if not L.follow_enabled then L.scene_run = nil end
                H.save()
            end
        end })

    local key_label = L.key and ("Key: " .. H.key_label(L.key)) or "Key: off"
    add({ group = 3, width = UI.rounded(112),
        draw = function()
            if L.key then
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
            end
            if r.ImGui_Button(UI.ctx, key_label, UI.rounded(112), UI.rounded(26)) then
                r.ImGui_OpenPopup(UI.ctx, "##launch_key")
            end
            if L.key then r.ImGui_PopStyleColor(UI.ctx, 2) end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "The key this session is in. A MIDI clip that says what key it is in\nis fitted to it, either by mapping its scale degrees or by transposing\nits root. Every clip keeps its own notes, so it can always go back.")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, key_label .. "...") then H.request_popup("##launch_key") end
        end })

    local tempo_sync = L.tempo_sync
    add({ group = 3, width = UI.rounded(84),
        draw = function()
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
                r.ImGui_SetTooltip(UI.ctx, "Stretch imported audio to the project tempo, pitch preserved.\nReads the tempo from the file's metadata or its name, and failing that\nguesses it from the length. Applies on import; per clip it can be undone\nor applied afterwards from the clip's right-click menu.")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Sync BPM on import", nil, tempo_sync) then
                L.tempo_sync = not L.tempo_sync
                H.save()
            end
        end })

    add({ group = 3, width = UI.rounded(56),
        draw = function()
            if r.ImGui_Button(UI.ctx, "Set", UI.rounded(56), UI.rounded(26)) then
                L.library = nil
                r.ImGui_OpenPopup(UI.ctx, "##launch_set")
            end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Save this grid as a clip set, or load one into this project.\nA set is a file of its own, so the same clips can be opened in\nany project; each lane finds its track there by name.")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Clip sets...") then
                L.library = nil
                H.request_popup("##launch_set")
            end
        end })

    local lanes_shown = H.lanes_visible()
    add({ group = 3, width = UI.rounded(96),
        draw = function()
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
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Show the lane tracks", nil, lanes_shown) then
                H.set_lanes_visible(not lanes_shown)
            end
        end })

    add({ group = 3, width = UI.rounded(92),
        draw = function()
            if r.ImGui_Button(UI.ctx, L.big_cells and "Waveforms" or "Compact", UI.rounded(92), UI.rounded(26)) then
                L.big_cells = not L.big_cells
                H.save(true)
            end
            if r.ImGui_IsItemHovered(UI.ctx) then r.ImGui_SetTooltip(UI.ctx, "Switch between waveform cells and a dense name-only grid") end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Waveform cells", nil, L.big_cells) then
                L.big_cells = not L.big_cells
                H.save(true)
            end
        end })

    return items
end

function Launcher.draw_toolbar()
    -- Asked for from inside the overflow menu, opened out here where the popups
    -- themselves live.
    if L.popup_request then
        r.ImGui_OpenPopup(UI.ctx, L.popup_request)
        L.popup_request = nil
    end
    H.draw_toolbar_row(H.toolbar_items(), 0)
    -- Drawn whether or not their buttons made it into the bar: a popup opened
    -- from the overflow menu still has to find its window here.
    H.draw_timing_popup()
    H.draw_key_popup()
    H.draw_set_popup()
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
    H.prune_lane_track(lane)
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

    -- The arrows follow the screen rather than the data: left is left whichever
    -- way round the grid is. The letter rows keep their meaning instead - they
    -- fire lanes, and a lane is a lane in both layouts.
    local function step(axis, delta)
        if axis == "lane" then
            cursor.lane = math.max(1, math.min(#L.lanes, cursor.lane + delta))
        else
            cursor.row = math.max(1, math.min(L.rows, cursor.row + delta))
        end
    end
    local across = L.scenes_as_columns and "row" or "lane"
    local down = L.scenes_as_columns and "lane" or "row"
    if H.pressed(keys.left) then step(across, -1) end
    if H.pressed(keys.right) then step(across, 1) end
    if H.pressed(keys.up) then step(down, -1) end
    if H.pressed(keys.down) then step(down, 1) end
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

-- Ctrl and the wheel scrolls sideways. ImGui has already put that same wheel
-- into the vertical scroll by the time this runs, so the vertical position is
-- put back where it was: doing both at once is what made a sideways scroll drift
-- down the grid, which only showed up once there were enough lanes to scroll.
function H.wheel_scroll()
    if not r.ImGui_GetMouseWheel or not r.ImGui_SetScrollX then return end
    if not r.ImGui_IsWindowHovered(UI.ctx) then return end
    local current = r.ImGui_GetScrollY and r.ImGui_GetScrollY(UI.ctx) or 0
    local mouse = r.JS_Mouse_GetState and r.JS_Mouse_GetState(4 | 8) or 0
    local ctrl = (mouse & 4) == 4
    -- Shift and the wheel is ImGui's own way of scrolling sideways. It should
    -- leave the vertical position alone by itself; putting it back costs nothing
    -- where it already does, and fixes it where it does not.
    local shift = (mouse & 8) == 8
    local wheel = r.ImGui_GetMouseWheel(UI.ctx) or 0
    if wheel == 0 or not (ctrl or shift) then
        L.scroll_y = current
        return
    end
    if r.ImGui_SetScrollY then r.ImGui_SetScrollY(UI.ctx, L.scroll_y or current) end
    if ctrl then
        local step = UI.rounded(C.cell_w) * 0.75
        r.ImGui_SetScrollX(UI.ctx, (r.ImGui_GetScrollX(UI.ctx) or 0) - wheel * step)
    end
end

function Launcher.draw()
    if not L.loaded then H.load() end
    if #L.lanes == 0 then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "This project has no tracks yet.")
        r.ImGui_Spacing(UI.ctx)
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "1. Add a track in REAPER. Every track is a lane here, in the same order.")
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "2. Fill a slot: drag a file onto it from a media browser, click it with items")
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
    -- Two ways round. Ableton puts the scenes down the left and a lane per
    -- column; Bitwig turns that on its side, which reads like the track panel it
    -- sits under. Only the frame changes: a clip keeps its size either way, and
    -- every cell draws itself into the box it is given.
    local sideways = L.scenes_as_columns
    local columns = sideways and (L.rows + 1) or (#L.lanes + 1)
    -- The table owns both scroll directions, which is what lets it freeze the
    -- first column and the header row: a frozen row is only possible when the
    -- table is the thing scrolling, not the window around it.
    local flags = r.ImGui_TableFlags_SizingFixedFit()
        | r.ImGui_TableFlags_ScrollX() | r.ImGui_TableFlags_ScrollY()
    local hidden = UI.hide_scrollbar and UI.hide_scrollbar() or false
    if hidden and r.ImGui_StyleVar_ScrollbarSize then
        r.ImGui_PushStyleVar(UI.ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    end
    -- ImGui's own cell padding is 4 across and 2 down, so the tiles sat twice as
    -- far apart sideways as they did up and down. Squared off against the
    -- vertical, which is the one that has to keep step with the track heights.
    local padded = false
    if r.ImGui_StyleVar_CellPadding and r.ImGui_GetStyleVar then
        local _, pad_y = r.ImGui_GetStyleVar(UI.ctx, r.ImGui_StyleVar_CellPadding())
        if pad_y then
            r.ImGui_PushStyleVar(UI.ctx, r.ImGui_StyleVar_CellPadding(), pad_y, pad_y)
            padded = true
        end
    end
    if r.ImGui_BeginTable(UI.ctx, "launcher_grid", columns, flags) then
        local head_w = UI.rounded(sideways and C.cell_w or C.scene_w)
        r.ImGui_TableSetupColumn(UI.ctx, "##head", r.ImGui_TableColumnFlags_WidthFixed(), head_w)
        for index = 1, (sideways and L.rows or #L.lanes) do
            r.ImGui_TableSetupColumn(UI.ctx, "##col" .. index, r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(C.cell_w))
        end
        if r.ImGui_TableSetupScrollFreeze then r.ImGui_TableSetupScrollFreeze(UI.ctx, 1, 1) end
        H.wheel_scroll()
        H.handle_keys()
        r.ImGui_TableNextRow(UI.ctx)
        r.ImGui_TableNextColumn(UI.ctx)
        H.draw_grid_corner(head_w, UI.rounded(C.cell_h) + H.align_offset())
        if sideways then
            -- Scenes across the top, one clip column each.
            for row = 1, L.rows do
                r.ImGui_TableNextColumn(UI.ctx)
                H.draw_scene_cell(row, UI.rounded(C.cell_w), UI.rounded(C.cell_h))
            end
            H.sync_scroll()
            L.last_row_y, L.last_row_height = nil, nil
            for lane_index, lane in ipairs(L.lanes) do
                local drawn = H.lane_draw_height(H.lane_row_height(lane))
                r.ImGui_TableNextRow(UI.ctx)
                r.ImGui_TableNextColumn(UI.ctx)
                local _, row_y = r.ImGui_GetCursorScreenPos(UI.ctx)
                -- Inside the row, not before it. Read before TableNextRow the
                -- cursor is still in the header row, and that height does not
                -- move when the gap grows - so the correction never arrived and
                -- the gap ran away to its limit the moment a track sat below it.
                if lane_index == 1 then L.first_row_y = row_y end
                H.note_row_pitch(row_y, drawn)
                r.ImGui_PushID(UI.ctx, lane_index)
                H.draw_lane_header(lane, lane_index, head_w, drawn)
                r.ImGui_PopID(UI.ctx)
                for row = 1, L.rows do
                    r.ImGui_TableNextColumn(UI.ctx)
                    r.ImGui_PushID(UI.ctx, lane_index * 1000 + row)
                    H.draw_cell(lane, lane_index, row, drawn)
                    r.ImGui_PopID(UI.ctx)
                end
            end
            local tail = H.tail_gap()
            if tail > 0 then
                r.ImGui_TableNextRow(UI.ctx)
                r.ImGui_TableNextColumn(UI.ctx)
                r.ImGui_Dummy(UI.ctx, head_w, tail)
            end
        else
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
        end
        r.ImGui_EndTable(UI.ctx)
    end
    H.draw_chrome_popup()
    if padded then r.ImGui_PopStyleVar(UI.ctx) end
    if hidden and r.ImGui_StyleVar_ScrollbarSize then r.ImGui_PopStyleVar(UI.ctx) end
    -- Cleared after every cell has had its chance to see the release.
end

-- Read and set from the Settings window, which lives in the main script.
function Launcher.color_headers()
    return L.color_headers and true or false
end

function Launcher.lane_volume()
    return L.lane_volume and true or false
end

function Launcher.set_lane_volume(value)
    L.lane_volume = value and true or false
    r.SetExtState(C.ext_section, "lane_volume", L.lane_volume and "1" or "0", true)
end

function Launcher.set_color_headers(value)
    L.color_headers = value and true or false
    r.SetExtState(C.ext_section, "color_headers", L.color_headers and "1" or "0", true)
end

function Launcher.scenes_as_columns()
    return L.scenes_as_columns and true or false
end

function Launcher.set_scenes_as_columns(value)
    L.scenes_as_columns = value and true or false
    r.SetExtState(C.ext_section, "scenes_as_columns", L.scenes_as_columns and "1" or "0", true)
end

function Launcher.lane_track_height()
    return L.lane_track_height and true or false
end

function Launcher.set_lane_track_height(value)
    L.lane_track_height = value and true or false
    r.SetExtState(C.ext_section, "lane_track_height", L.lane_track_height and "1" or "0", true)
end

-- 0 shows both bars, 1 keeps the title bar and folds the toolbar away, 2 hides
-- both. Only ever applied in the launcher view: hiding the title bar takes the
-- view tabs with it, and the arrow that brings them back lives in the grid.
function Launcher.chrome()
    return L.chrome or 0
end

function Launcher.set_chrome(value)
    value = math.floor(tonumber(value) or 0)
    L.chrome = (value >= 0 and value <= 3) and value or 0
    r.SetExtState(C.ext_section, "chrome", tostring(L.chrome), true)
end

function Launcher.align_to_arrange()
    return L.align_to_arrange and true or false
end

function Launcher.set_align_to_arrange(value)
    L.align_to_arrange = value and true or false
    r.SetExtState(C.ext_section, "align_to_arrange", L.align_to_arrange and "1" or "0", true)
    L.align_gap = 0
end

function Launcher.scroll_sync()
    return L.scroll_sync or "off"
end

function Launcher.set_scroll_sync(mode)
    L.scroll_sync = (mode == "follow" or mode == "both") and mode or "off"
    r.SetExtState(C.ext_section, "scroll_sync", L.scroll_sync, true)
    L.sync_mine, L.sync_theirs = nil, nil
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
