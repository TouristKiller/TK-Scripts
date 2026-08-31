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
local ChordTimeline = require("chord_timeline")
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
    -- Half the space between two clip tiles: a table puts this much on each
    -- side of every cell. ImGui's own default is 4 across and 2 down, which is
    -- both uneven and roomier than a grid of clips wants.
    cell_gap     = 1,
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
    guide_guid        = nil,
    guide_events      = nil,
    guide_scan_at     = 0,
    -- The automation clip being drawn into out in the arrange, if any, and the
    -- envelope ranges read for the ones that are only playing.
    autom_edit        = nil,
    env_ranges        = nil,
    autom_files       = nil,
    autom_save_prompt = nil,
    file_prompt       = nil,
    chain_prompt      = nil,
    rename_prompt     = nil,
    lane_name_prompt  = nil,
    lane_colour_prompt = nil,
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
    midi_enabled      = false,
    midi_window_open  = false,
    midi_device_name  = "",
    midi_channel      = 0,
    midi_base_note    = 36,
    midi_layout       = "pads",
    midi_keyboard_mode = "octaves",
    midi_pad_mode     = "clips",
    midi_columns      = 8,
    midi_rows         = 8,
    midi_orientation  = "lanes",
    midi_lane_bank    = 0,
    midi_scene_bank   = 0,
    midi_last_retval  = nil,
    midi_pressed      = {},
    midi_commands     = {},
    midi_command_pressed = {},
    midi_learn        = nil,
    midi_base_learn   = false,
    midi_learn_retval = nil,
    midi_presets      = {},
    midi_preset_name  = "",
    midi_preset_selected = nil,
    -- Lighting the pads of a Launchpad: which output, whether to send at all,
    -- which family it belongs to, and the grid it lays its notes out in.
    midi_out_name     = "",
    midi_out_index    = nil,
    midi_feedback     = false,
    midi_lp_family    = "mk3",
    midi_lp_origin    = nil,
    midi_lp_step      = nil,
    lp_map            = nil,
    lp_shadow         = nil,
    lp_sent           = nil,
}

local MIDI_COMMANDS = {
    { key = "lane_prev", label = "Previous lane bank" },
    { key = "lane_next", label = "Next lane bank" },
    { key = "scene_prev", label = "Previous scene bank" },
    { key = "scene_next", label = "Next scene bank" },
    { key = "launch_scene", label = "Launch active scene" },
    { key = "stop_lane", label = "Stop active lane" },
    { key = "stop_all", label = "Stop all" },
    { key = "record", label = "Record" },
}

for row = 1, C.max_rows do
    MIDI_COMMANDS[#MIDI_COMMANDS + 1] = {
        key = "launch_scene_" .. tostring(row),
        label = "Launch scene " .. tostring(row),
        scene = row,
    }
end

-- What happens when a scene has played its rounds. One rule, used by both the
-- player and the writer, so a written arrangement can never disagree with what
-- you hear.
-- Where a clip or a scene goes once it has played. "Next scene" is the row
-- straight below, empty or not; "Next scene with a clip" walks on until it
-- finds one, which is what you want when a lane only speaks up now and then.
-- That second one is a clip's business: a scene chain already skips the scenes
-- that are empty, because an empty scene is not a section of a song.
local FOLLOW_OPTIONS = {
    { key = "stop",   label = "Stop" },
    { key = "next",   label = "Next scene" },
    { key = "fill",   label = "Next scene with a clip", clips_only = true },
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

function H.guide_track()
    return H.track_from_guid(L.guide_guid)
end

function H.refresh_guide(force)
    local track = H.guide_track()
    if not track then
        L.guide_events = nil
        return nil
    end
    local now = r.time_precise()
    if not force and L.guide_events and now < (L.guide_scan_at or 0) then return L.guide_events end
    local chord_options = { include_bass = true, allow_rootless = true, minimum_confidence = 0.55 }
    if L.key and (L.key.mode == "major" or L.key.mode == "minor") then
        chord_options.key_root = L.key.root
        chord_options.key_mode = L.key.mode
    end
    L.guide_events = ChordTimeline.build(L.guide_guid, {
        minimum_duration = 0.05,
        attack_tolerance = 0.03,
        include_muted = true,
        chord_options = chord_options,
    }, force) or {}
    L.guide_scan_at = now + 0.25
    return L.guide_events
end

function H.guide_at(position)
    if not L.guide_guid then return nil, nil end
    position = position or 0
    local events = H.refresh_guide(false) or {}
    local current, next_chord = ChordTimeline.at(events, position)
    if current then return current, next_chord end
    for _, event in ipairs(events) do
        if event.start <= position then
            current = event
        elseif not next_chord then
            next_chord = event
            break
        end
    end
    return current, next_chord
end

function H.chord_root(chord)
    if not chord then return nil end
    if tonumber(chord.root) then return math.floor(tonumber(chord.root)) % 12 end
    local letter, accidental = tostring(chord.name or ""):match("^%s*([A-Ga-g])([#b]?)")
    return letter and H.note_number(letter, accidental) or nil
end

function H.set_guide_track(track)
    L.guide_guid = H.valid_track(track) and r.GetTrackGUID(track) or nil
    L.guide_events = nil
    L.guide_scan_at = 0
    ChordTimeline.invalidate()
    H.save()
end

function H.is_chord_item(item)
    if not H.valid_item(item) then return false end
    local ok, value = r.GetSetMediaItemInfo_String(item, "P_EXT:TK_PROJECT_CLIPS_CHORD_ITEM", "", false)
    return ok and value == "1"
end

function H.remove_chord_items(track, undo)
    if not H.valid_track(track) then return 0 end
    if undo then r.Undo_BeginBlock() end
    local removed = 0
    for index = r.CountTrackMediaItems(track) - 1, 0, -1 do
        local item = r.GetTrackMediaItem(track, index)
        if H.is_chord_item(item) then
            r.DeleteTrackMediaItem(track, item)
            removed = removed + 1
        end
    end
    if undo then
        r.Undo_EndBlock("Remove chord guide items", -1)
        r.UpdateArrange()
    end
    return removed
end

function H.chord_item_color()
    local native = r.GetThemeColor("col_mi_label", 0)
    local red, green, blue = r.ColorFromNative(native)
    local brightness = red * 0.299 + green * 0.587 + blue * 0.114
    local level = brightness >= 128 and 24 or 235
    return (r.ColorToNative(level, level, level) or 0) | 0x1000000
end

function H.create_chord_items()
    local track = H.guide_track()
    if not track then return end
    local events = H.refresh_guide(true) or {}
    if #events == 0 then
        L.status = "No chords recognized on the guide track"
        return
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    H.remove_chord_items(track, false)
    local made = 0
    for index, event in ipairs(events) do
        local stop = events[index + 1] and events[index + 1].start or event.stop
        if stop and stop > event.start then
            local item = r.AddMediaItemToTrack(track)
            if item then
                r.SetMediaItemInfo_Value(item, "D_POSITION", event.start)
                r.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.05, stop - event.start))
                r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", H.chord_item_color())
                r.GetSetMediaItemInfo_String(item, "P_NOTES", event.name, true)
                r.GetSetMediaItemInfo_String(item, "P_EXT:TK_PROJECT_CLIPS_CHORD_ITEM", "1", true)
                r.SetMediaItemSelected(item, false)
                made = made + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Create chord guide items", -1)
    r.UpdateArrange()
    L.status = "Created " .. tostring(made) .. " chord items"
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
function H.text_centered(draw_list, center_x, center_y, color, text, nudge)
    local text_width, text_height = r.ImGui_CalcTextSize(UI.ctx, text)
    local x = math.floor(center_x - text_width * 0.5 + 0.5)
    local y = math.floor(center_y - text_height * 0.5 + (nudge or 0) + 0.5)
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

-- REAPER numbers measures from one in TimeMap_QNToMeasures and from zero in
-- TimeMap_GetMeasureInfo. Rather than take that on trust, ask both about the
-- same measure once and keep the difference. An off-by-one here would put
-- every launch a whole bar out, which is exactly the kind of fault that looks
-- like a timing problem and is not one.
function H.measure_offset()
    if L.measure_offset then return L.measure_offset end
    L.measure_offset = -1
    if r.TimeMap_QNToMeasures and r.TimeMap_GetMeasureInfo then
        local measure, from_qn = r.TimeMap_QNToMeasures(0, 8)
        if measure and from_qn then
            for _, guess in ipairs({ -1, 0 }) do
                local _, qn = r.TimeMap_GetMeasureInfo(0, measure + guess)
                if qn and math.abs(qn - from_qn) < 0.001 then
                    L.measure_offset = guess
                    break
                end
            end
        end
    end
    return L.measure_offset
end
-- Where a time sits counted in real measures - the ones REAPER draws - with
-- the fraction through the current one. Measures are not a fixed number of
-- quarter notes: after a 4/4 to 3/4 change, counting quarter notes from the
-- start of the song has drifted off the bar lines for good.
function H.measure_pos(time)
    if not r.TimeMap_QNToMeasures then return nil end
    local qn = r.TimeMap2_timeToQN(0, time)
    local measure, from_qn, to_qn = r.TimeMap_QNToMeasures(0, qn)
    if not (measure and from_qn and to_qn) or to_qn <= from_qn then return nil end
    return measure + H.measure_offset() + (qn - from_qn) / (to_qn - from_qn)
end

-- The way back. Everything goes through quarter notes rather than the time
-- TimeMap_GetMeasureInfo hands back, so a fraction of a measure and a whole one
-- are worked out the same way.
function H.measure_pos_time(pos)
    if not r.TimeMap_GetMeasureInfo then return nil end
    local whole = math.floor(pos)
    local _, from_qn, to_qn = r.TimeMap_GetMeasureInfo(0, whole)
    if not (from_qn and to_qn) or to_qn <= from_qn then return nil end
    return r.TimeMap2_QNToTime(0, from_qn + (pos - whole) * (to_qn - from_qn))
end

-- Where a time sits on the launch grid, counted in lines. The four places that
-- need a boundary want different things from it - the line before, the next
-- one, the nearest one - and expressing all of them as arithmetic on one index
-- keeps that difference where it belongs and out of the grid itself.
--
-- Bar line mode counts the measures REAPER actually draws. Every other setting
-- is a fixed number of quarter notes counted from the start of the song, which
-- is the same thing only while the meter never changes; after a 4/4 to 3/4
-- change that count has drifted off the bar lines for good.
function H.grid_index(from_time)
    -- Every positive setting is a count of bars, whole or fractional, so all of
    -- them ride the real measures. Only the beat setting is a raw note value.
    local value = L.quantize or 1
    if value > 0 then
        local pos = H.measure_pos(from_time)
        if pos then return pos / value end
    end
    local step = H.quantize_qn(from_time)
    if step <= 0 then return nil end
    return r.TimeMap2_timeToQN(0, from_time) / step
end

-- The time of one whole line. from_time only says which grid is meant; on the
-- quarter note grids it also carries the meter the step was measured in.
function H.grid_time(from_time, line)
    local value = L.quantize or 1
    if value > 0 then
        local time = H.measure_pos_time(line * value)
        if time then return time end
    end
    local step = H.quantize_qn(from_time)
    if step <= 0 then return from_time end
    return r.TimeMap2_QNToTime(0, line * step)
end
function H.boundary_after(from_time, allow_now)
    local index = H.grid_index(from_time)
    if not index then
        return allow_now and from_time or (from_time + H.lead())
    end
    local line = math.floor(index)
    if not allow_now then line = line + 1 end
    local time = H.grid_time(from_time, line)
    if allow_now then
        if time < from_time - 0.001 then time = H.grid_time(from_time, line + 1) end
        return time
    end
    local guard = 0
    while time - from_time < H.lead() and guard < 64 do
        line = line + 1
        time = H.grid_time(from_time, line)
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
    -- An envelope lane keeps its clips on the hidden track of the lane it
    -- hangs under. It has no audio of its own to route anywhere, and a second
    -- hidden track per envelope would be a track list nobody asked for.
    if lane.parent then
        local shared = H.ensure_lane_track(lane.parent)
        lane.lane_guid = lane.parent.lane_guid
        return shared
    end
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
    if not lane then return false end
    if lane.parent then return H.prune_lane_track(lane.parent) end
    if not lane.lane_guid then return false end
    if #lane.slots > 0 then return false end
    -- The envelope lanes under it keep their anchors on the same track.
    for _, sub in ipairs(lane.envs or {}) do
        if #sub.slots > 0 or sub.current or sub.pending then return false end
    end
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
    for _, sub in ipairs(lane.envs or {}) do sub.lane_guid = nil end
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
    -- The drawn preview is cached under this key, and a clip's guid does not
    -- change when its notes do - so editing one in the MIDI editor left the old
    -- picture on screen until the script was restarted. The notes' own hash goes
    -- into the key, looked at a few times a second rather than every frame:
    -- reading it walks the take, and only what is on screen gets here at all.
    if slot.is_midi and r.MIDI_GetHash then
        local now = r.time_precise()
        if not slot.midi_checked or now - slot.midi_checked > 0.4 then
            slot.midi_checked = now
            local item = H.item_from_guid(slot.guid)
            local take = item and r.GetActiveTake(item) or nil
            if take and r.TakeIsMIDI(take) then
                local ok, hash = r.MIDI_GetHash(take, true, "")
                if ok and hash and hash ~= slot.midi_hash then
                    slot.midi_hash = hash
                    entry.cache_key = slot.guid .. "|launcher|" .. hash
                end
            end
        end
    end
    return entry
end

-- A slot whose clip has gone -- undone, or deleted by hand -- is marked rather
-- than removed. Removing it would lose the slot for good the moment the user
-- redoes, and the clip would come back to a grid that had forgotten it. Checked
-- on a timer, because resolving every clip on every frame is not free.
function H.refresh_missing(now)
    if L.checked and now - L.checked < 0.5 then return end
    L.checked = now
    for _, lane in ipairs(H.holders()) do
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
    -- An automation clip is as long as its bars say, whatever the item that
    -- carries its guid happens to measure.
    if H.autom(slot) then
        local length = H.autom_length(slot)
        slot.length, slot.loop_len = length, length
        return length, length
    end
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
    -- Judged on the result, not on the mechanism. Glue handing back a fresh
    -- item only says something happened; what matters is whether the take still
    -- needs trimming afterwards. A recorded clip comes in already gluable, so
    -- the old test could call a perfectly trimmed clip a failure.
    local glued_take = r.GetActiveTake(glued)
    if not glued_take then return glued, false end
    return glued, not H.is_trimmed(glued, glued_take)
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
    if H.is_env_lane(lane) and not L.autom_building then
        L.status = "That is an automation lane; it takes curves, not media"
        return false
    end
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
    if H.is_env_lane(lane) then
        L.status = "That is an automation lane; it takes curves, not files"
        return false
    end
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
-- Playing a take faster or slower. The item is kept as long as what it now
-- plays, so a clip that took two bars at half speed takes one at full.
function H.apply_take_rate(item, take, rate)
    local current = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
    if current <= 0 then current = 1 end
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
    r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
    if length > 0 then
        r.SetMediaItemInfo_Value(item, "D_LENGTH", math.max(0.05, length * current / rate))
    end
end

function H.set_slot_rate(lane, row, rate)
    local slot = H.slot(lane, row)
    local item = slot and H.item_from_guid(slot.guid) or nil
    local take = item and r.GetActiveTake(item) or nil
    if not take or not rate or rate <= 0 then return false end
    r.Undo_BeginBlock()
    H.apply_take_rate(item, take, rate)
    r.Undo_EndBlock("Change launcher clip playrate", -1)
    r.UpdateArrange()
    slot.tempo_matched = math.abs(rate - 1) > 0.0005 and true or nil
    if not slot.tempo_matched then slot.tempo_guessed = nil end
    H.save()
    return true
end

-- Speed is a multiplier laid over whatever the clip already sits at, not a rate
-- of its own. A clip stretched to the project tempo keeps that stretch when it
-- is played at half speed; setting the rate outright would throw it away.
C.speeds = { 0.25, 0.5, 0.75, 1, 1.5, 2 }

C.new_clip_bars = { 1, 2, 4, 8 }

-- How a clip answers to being played. Toggle is the default because a second
-- click meaning stop is what everything else does; restart is Ableton's default
-- and a gesture worth keeping; gate needs the clip gate effect, since letting go
-- has to be heard now and the timeline is written ahead.
C.launch_modes = {
    { key = "toggle",  label = "Click starts, click stops",
      hint = "A second click stops it on the next bar line" },
    { key = "restart", label = "Click starts, click restarts",
      hint = "A second click fires it again from the top" },
    { key = "gate",    label = "Hold to play",
      hint = "Plays while the mouse is held and stops the moment it is let go" },
}

function H.launch_mode_label(key)
    for _, entry in ipairs(C.launch_modes) do
        if entry.key == key then return entry.label end
    end
    return C.launch_modes[1].label
end

function H.slot_speed(slot)
    return slot and slot.speed or 1
end

function H.set_slot_speed(lane, row, speed)
    local slot = H.slot(lane, row)
    local item = slot and H.item_from_guid(slot.guid) or nil
    local take = item and r.GetActiveTake(item) or nil
    if not take or not speed or speed <= 0 then return false end
    local was = H.slot_speed(slot)
    if math.abs(speed - was) < 0.0005 then return false end
    local current = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
    if current <= 0 then current = 1 end
    r.Undo_BeginBlock()
    H.apply_take_rate(item, take, current * speed / was)
    r.Undo_EndBlock("Change launcher clip speed", -1)
    r.UpdateArrange()
    slot.speed = math.abs(speed - 1) > 0.0005 and speed or nil
    slot.length, slot.loop_len = nil, nil
    H.save()
    L.status = string.format("%s at %gx", slot.name or "Clip", speed)
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
    for _, lane in ipairs(H.holders()) do
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
    -- A curve belongs in an automation lane and a sound does not, whichever
    -- way round the drag went.
    if H.is_env_lane(to_lane) ~= (H.autom(from_slot) ~= nil) then
        L.status = H.autom(from_slot) and "An automation clip belongs in an automation lane"
            or "That is an automation lane; it takes curves, not media"
        return
    end
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
                kind = from_slot.kind,
                autom = H.copy_autom(from_slot.autom),
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
    -- A clip that landed in another automation lane takes that lane's
    -- parameter: the lane is what the cells under it automate.
    if H.is_env_lane(to_lane) then
        local landed = H.slot(to_lane, to_row)
        local autom = H.autom(landed)
        if autom and not H.same_target(autom.target, to_lane.target) then
            autom.target = to_lane.target
            landed.name = H.autom_target_label(to_lane.target)
        end
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
    for _, lane in ipairs(H.holders()) do
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
    for _, lane in ipairs(H.holders()) do
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
    if follow == "next" or follow == "fill" then return rows[(index % #rows) + 1] end
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

-- What a clip hands over to once it has played its rounds. Read literally: the
-- scene below this one, the one above it, the first. The rows of the grid are
-- the scenes, so "next scene" means the cell one row down in this same lane -
-- and a lane that has nothing there is a lane sitting that scene out, which is
-- stopping rather than hunting further down for the next clip it can find.
--
-- Random is the exception. A random empty row would only ever mean stop, so
-- that one still picks from the rows this lane has actually filled.
-- Follow is one switch for the whole grid, and it is in the toolbar. Turned off
-- there, every one of these settings is stored and ignored, which reads exactly
-- like a follow action that does not work.
function H.draw_follow_warning()
    if L.follow_enabled then return end
    r.ImGui_Separator(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.warning or UI.colors.danger,
        "Follow is switched off for the whole grid")
    if r.ImGui_MenuItem(UI.ctx, "Switch follow on") then
        L.follow_enabled = true
        H.save()
        L.status = "Follow is on: clips and scenes hand over again"
    end
end

function H.next_slot_after(lane, row)
    local slot = H.slot(lane, row)
    local follow = slot and slot.follow or "stop"
    if follow == "stop" then return nil end
    if follow == "self" then return row end
    if follow == "random" then
        local rows = H.lane_rows(lane)
        if #rows == 0 then return nil end
        if #rows == 1 then return rows[1] end
        local pick, guard = rows[math.random(#rows)], 0
        while pick == row and guard < 8 do
            pick = rows[math.random(#rows)]
            guard = guard + 1
        end
        return pick
    end
    -- Past the empty rows to the next clip this lane has, and round to the top
    -- when there is none below: that makes a lane with a handful of clips play
    -- through them for as long as you leave it alone.
    if follow == "fill" then
        for step = 1, L.rows do
            local at = ((row - 1 + step) % L.rows) + 1
            if H.slot(lane, at) then return at end
        end
        return nil
    end
    local wanted = nil
    if follow == "first" then wanted = 1
    elseif follow == "next" then wanted = row + 1
    elseif follow == "prev" then wanted = row - 1 end
    if not wanted or wanted < 1 or wanted > L.rows then return nil end
    return H.slot(lane, wanted) and wanted or nil
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
        -- A clip that hands over to the next one takes its curves with it. An
        -- envelope lane that reaches the end of its own run moves on alone;
        -- pulling the track's clip along behind a curve is not what a follow
        -- action on that curve means.
        if H.is_env_lane(lane) then
            H.commit(lane, next_row, finish)
        else
            H.commit_group(lane, next_row, finish)
        end
    else
        H.close_voice_at(lane.current, finish)
        if not lane.hold then H.schedule_owner(lane, "arrangement", finish) end
        -- A clip that has played its rounds takes its curves with it.
        for _, sub in ipairs(H.stopped_with(lane)) do
            sub.run = nil
            H.cancel_pending(sub)
            H.close_voice_at(sub.current, finish)
        end
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
    -- A curve is written as an automation item on the same envelope it would
    -- have been launched onto. It is not media, so it never joins the selection
    -- the written clips get.
    local autom = H.autom(slot)
    if autom then
        if not H.valid_track(target) then return nil end
        local env = H.autom_env(target, autom.target, true)
        if not env then return nil end
        local clip = H.autom_length(slot, position)
        H.autom_insert(env, autom.target, slot, position, clip,
            slot.loop and math.max(clip, length) or nil,
            C.autom_write_name .. ": " .. (slot.name or "clip"))
        return nil
    end
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
    for _, lane in ipairs(H.holders()) do
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
    L.status = (#written > 0 or H.autom(slot)) and ("Wrote " .. slot.name) or "Could not write that clip"
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
    L.status = (#written > 0 or H.autom(slot)) and ("Dropped " .. slot.name) or "Could not drop that clip"
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
            for _, lane in ipairs(H.holders()) do
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

function H.ask_lane_name(lane)
    L.lane_name_prompt = lane
end

function H.run_lane_name_prompt()
    local lane = L.lane_name_prompt
    if not lane then return end
    L.lane_name_prompt = nil
    local track = H.target_track(lane)
    if not track or not r.GetUserInputs then return end
    local current = H.track_name(track, lane.name)
    local ok, answer = r.GetUserInputs("Rename lane and track", 1, "Name:,extrawidth=180", current)
    if not ok then return end
    answer = tostring(answer or ""):match("^%s*(.-)%s*$")
    if answer == "" or answer == current then return end
    r.Undo_BeginBlock()
    r.GetSetMediaTrackInfo_String(track, "P_NAME", answer, true)
    lane.name = answer
    local hidden = H.lane_track(lane)
    if hidden then r.GetSetMediaTrackInfo_String(hidden, "P_NAME", H.lane_track_name(track), true) end
    H.save()
    r.Undo_EndBlock("Rename launcher lane and track", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    L.status = "Renamed lane and track to " .. answer
end

function H.ask_lane_colour(lane)
    L.lane_colour_prompt = lane
end

function H.run_lane_colour_prompt()
    local lane = L.lane_colour_prompt
    if not lane then return end
    L.lane_colour_prompt = nil
    local track = H.target_track(lane)
    if not track or not r.GR_SelectColor then return end
    local red, green, blue = r.ColorFromNative(r.GetTrackColor(track))
    local ok, colour = r.GR_SelectColor(r.GetMainHwnd(), r.ColorToNative(red, green, blue))
    if ok == 0 then return end
    r.Undo_BeginBlock()
    r.SetTrackColor(track, colour | 0x1000000)
    if r.MarkProjectDirty then r.MarkProjectDirty(0) end
    r.Undo_EndBlock("Set launcher lane and track colour", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    L.status = "Changed lane and track colour"
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
    for _, lane in ipairs(H.holders()) do
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
    if L.defer_restore_save then
        L.restore_save_dirty = true
        return
    end
    L.restore_save_dirty = false
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
    if voice.ai then
        H.autom_delete(voice.ai)
        voice.ai = nil
    end
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
    -- A curve that was playing while the take ran stays where it is and keeps
    -- what it did to the parameter. Renamed, so the stray sweep leaves it alone.
    if voice.ai then
        local index = H.autom_index(voice.ai)
        if index and r.GetSetAutomationItemInfo_String then
            r.GetSetAutomationItemInfo_String(voice.ai.env, index, "P_POOL_NAME", C.autom_write_name, true)
        end
        voice.ai = nil
    end
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
    if voice.ai then
        local finish = H.autom_end(voice.ai)
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
    -- Only media is filled in behind the loop start. An automation clip
    -- launched inside a loop region starts where it was launched on every pass.
    if voice.ai then return end
    local loop_start, loop_end = H.loop_region()
    if not loop_start or voice.at - loop_start < 0.05 or voice.at >= loop_end then return end
    local lane_track = H.lane_track(lane)
    local library = H.item_from_guid(voice.slot_guid or "")
    if not lane_track or not library then return end
    local wrap = H.copy_item(library, lane_track, loop_start)
    if not wrap then return end
    H.apply_chord_follow(wrap, H.slot_by_guid(voice.slot_guid))
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
    -- A curve ends the same way a clip does: cut off on the boundary if it is
    -- already running, dropped outright if it had not started yet.
    if voice.ai then
        local at = H.autom_start(voice.ai)
        if not at then
            voice.ai = nil
        elseif at >= time then
            H.autom_delete(voice.ai)
            voice.ai = nil
        else
            H.autom_trim(voice.ai, time)
        end
    end
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
    if H.autom(slot) then return H.commit_autom(lane, row, time, slot) end
    local lane_track = H.lane_track(lane)
    local library = slot and H.item_from_guid(slot.guid) or nil
    if not slot or not lane_track or not library then return false end

    H.cancel_pending(lane)

    -- Close the outgoing voice first so the two never overlap (which would make
    -- REAPER build an auto-crossfade between them).
    local restore = H.close_voice_at(lane.current, time)

    local voice = H.copy_item(library, lane_track, time)
    if not voice then return false end
    H.apply_chord_follow(voice, slot)
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
    -- Anything launched here is meant to be heard, so the gate must be open.
    -- Releasing a held clip leaves it shut - that is what makes the silence
    -- immediate - and nothing else would ever open it again, so every later
    -- clip in that lane would play into a closed door.
    H.open_gate_for(lane)
    return true
end

-- A looping voice only claims a few minutes of timeline at a time and grows as
-- the play cursor approaches its end, so a jam does not inflate the project.
function H.extend_voice(lane, heard)
    local voice = lane.current
    if not voice or voice.closing or not voice.looped then return end
    if lane.pending or lane.switch then return end
    if voice.ai then
        H.autom_extend(voice.ai, heard)
        return
    end
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
        for _, lane in ipairs(H.holders()) do lane.queued = nil end
        return
    end
    for _, lane in ipairs(H.holders()) do
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
    local horizon = from + H.lead() + 1
    local guard = 0
    while voice.next_hit_qn and guard < 32 do
        local time = r.TimeMap2_QNToTime(0, voice.next_hit_qn)
        if time > horizon then break end
        if time > from and H.step_on(slot_of_voice, voice.next_hit_qn) then
            local hit = H.copy_item(library, lane_track, time)
            if hit then
                H.apply_chord_follow(hit, H.slot_by_guid(voice.slot_guid))
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
    local loop_start, loop_end = H.loop_region()
    -- Spent hits are cleared here rather than through the harvest, so recording
    -- has to be honoured here as well. Without it a retriggered one-shot kept
    -- only the few hits that happened to still be alive when the take ended.
    for index = #voice.hits, 1, -1 do
        local media = voice.hits[index]
        local finish = H.item_end(media)
        local position = H.valid_item(media) and r.GetMediaItemInfo_Value(media, "D_POSITION") or nil
        local repeats_with_transport = position and loop_start
            and position >= loop_start and position < loop_end
        if not repeats_with_transport and (not finish or heard > finish + C.harvest_pad) then
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
    for _, lane in ipairs(H.holders()) do H.harvest_lane(lane, force) end
end

--------------------------------------------------------------------------------
-- automation clips
--------------------------------------------------------------------------------

-- A clip that is a curve rather than media. The slot still owns a library item
-- -- a blank, muted one on the lane track -- so everything the grid already does
-- by guid keeps working: undo, "this clip is gone", dragging between slots, the
-- set files. Launching it does not copy that item anywhere; it puts an
-- automation item on an envelope of the lane's own target track, on the same
-- bar line every other clip lands on.
--
-- The curve is the launcher's own data (times as a fraction of the clip, values
-- normalised to 0..1) rather than a REAPER pool. A pool only exists while an
-- instance of it does, so keeping clips as pools would mean parking an instance
-- somewhere for every slot, and a pool's numbers are read in whatever envelope
-- it lands on. As fractions the same clip can be pointed at another parameter,
-- and it stretches when the clip is made longer or the tempo changes.
--
-- Automation goes on the target track, not on the hidden lane track: a send
-- carries audio, not a fader move. So an automation clip does not take the
-- track off the arrangement the way a media clip does - the song keeps playing
-- underneath, which is the point of automating it.

C.autom_voice_name = "TK clip voice"  -- pool name of a playing instance
C.autom_edit_name  = "TK clip edit"   -- pool name of the one being drawn into
C.autom_write_name = "TK clip"        -- pool name of one written to the arrangement
C.autom_targets = {
    { kind = "vol", label = "Volume", chunk = "<VOLENV2", action = 40406, min = 0, max = 2 },
    { kind = "pan", label = "Pan",    chunk = "<PANENV2", action = 40407, min = -1, max = 1 },
}

function H.autom(slot)
    if not slot or slot.kind ~= "automation" then return nil end
    return slot.autom
end

-- Automation clips do not sit in the track's own lane. They sit in a lane of
-- their own underneath it, one per envelope, the way the arrange puts envelope
-- lanes under a track -- so a curve can run while the track's own clip plays,
-- instead of taking its place.
--
-- Such a lane is deliberately shaped like a lane: slots, current, pending,
-- retired, run, queued. The engine takes one without knowing the difference.
-- It carries its parent's two track guids as well, so every accessor that reads
-- those keeps working unchanged: the target track is the same track, and the
-- anchors live on the same hidden track.

function H.is_env_lane(holder)
    return holder ~= nil and holder.parent ~= nil
end

function H.env_lanes(lane)
    return (lane and lane.envs) or {}
end

-- Every lane and every envelope lane under it, in the order they are drawn.
-- Rebuilt rather than kept: lanes themselves are rebuilt from the track list
-- whenever the project changes, and a stale list of holders would outlive them.
function H.holders()
    local list = {}
    for _, lane in ipairs(L.lanes) do
        list[#list + 1] = lane
        for _, sub in ipairs(lane.envs or {}) do list[#list + 1] = sub end
    end
    return list
end

-- A number that is never a lane index. The cursor, the record marks and the
-- keyboard grid all count lanes, and none of them may take an envelope lane for
-- one; ImGui only wants the id to be unique.
function H.env_lane_id(lane_index, sub_index)
    return -((lane_index or 0) * 64 + (sub_index or 1))
end

function H.same_target(first, second)
    if not first or not second or first.kind ~= second.kind then return false end
    if first.kind == "fx" then
        return first.fx == second.fx and (first.param or 0) == (second.param or 0)
    end
    return true
end

function H.env_lane_label(sub)
    return H.autom_target_label(sub and sub.target)
end

function H.env_lane_for(lane, target, create)
    if not lane or H.is_env_lane(lane) then return nil end
    for _, sub in ipairs(lane.envs or {}) do
        if H.same_target(sub.target, target) then return sub end
    end
    if not create then return nil end
    lane.envs = lane.envs or {}
    local sub = {
        parent = lane,
        target = target,
        name = H.autom_target_label(target),
        follow_parent = true,
        paused = false,
        track_guid = lane.track_guid,
        lane_guid = lane.lane_guid,
        slots = {},
        retired = {},
        owner = "arrangement",
    }
    lane.envs[#lane.envs + 1] = sub
    return sub
end

-- Emptied, then dropped. The clips go with it: an envelope lane is the clips,
-- and leaving them somewhere invisible would be worse than saying goodbye.
function H.remove_env_lane(sub)
    local lane = sub and sub.parent
    if not lane then return end
    r.Undo_BeginBlock()
    H.harvest_lane(sub, true)
    for index = #sub.slots, 1, -1 do
        H.clear_slot(sub, sub.slots[index].row)
    end
    for index = #(lane.envs or {}), 1, -1 do
        if lane.envs[index] == sub then table.remove(lane.envs, index) end
    end
    H.prune_lane_track(lane)
    r.Undo_EndBlock("Remove launcher automation lane", -1)
    r.UpdateArrange()
    H.save()
    L.status = "Automation lane removed"
end

function H.autom_ready()
    return (r.InsertAutomationItem and r.CountAutomationItems and r.InsertEnvelopePointEx
        and r.GetSetAutomationItemInfo and r.GetEnvelopeStateChunk) and true or false
end

function H.autom_kind(target)
    for _, entry in ipairs(C.autom_targets) do
        if entry.kind == (target and target.kind) then return entry end
    end
    return nil
end

function H.autom_target_label(target)
    if not target then return "nothing" end
    local entry = H.autom_kind(target)
    if entry then return entry.label end
    local fx = target.fx_name and (target.fx_name .. ": ") or ""
    return fx .. (target.param_name or ("parameter " .. tostring(target.param or 0)))
end

function H.fx_index_by_guid(track, guid)
    if not guid or not r.TrackFX_GetFXGUID then return nil end
    for index = 0, (r.TrackFX_GetCount(track) or 0) - 1 do
        if r.TrackFX_GetFXGUID(track, index) == guid then return index end
    end
    return nil
end

-- The envelope a clip points at, made if it is not there yet. An FX parameter
-- has GetFXEnvelope, which creates one on request; volume and pan have no call
-- of their own, so they go through the action that shows them - and only when
-- the envelope is really absent, because that action is a toggle.
function H.autom_env(track, target, create)
    if not H.valid_track(track) or not target then return nil end
    local entry = H.autom_kind(target)
    if not entry then
        local index = H.fx_index_by_guid(track, target.fx)
        if not index or not r.GetFXEnvelope then return nil end
        return r.GetFXEnvelope(track, index, math.floor(target.param or 0), create and true or false)
    end
    local env = r.GetTrackEnvelopeByChunkName(track, entry.chunk)
    if env or not create then return env end
    local selected = {}
    for index = 0, (r.CountSelectedTracks(0) or 0) - 1 do
        selected[#selected + 1] = r.GetSelectedTrack(0, index)
    end
    r.SetOnlyTrackSelected(track)
    r.Main_OnCommand(entry.action, 0)
    env = r.GetTrackEnvelopeByChunkName(track, entry.chunk)
    r.SetTrackSelected(track, false)
    for _, kept in ipairs(selected) do
        if H.valid_track(kept) then r.SetTrackSelected(kept, true) end
    end
    return env
end

-- An envelope you are about to draw into has to be on screen, and in a lane of
-- its own. Making one through the action leaves it visible, GetFXEnvelope does
-- not, and either can end up drawn over the track's own items - which on a
-- track of ordinary height is a curve you cannot get a mouse on. Its own lane
-- is also where every other program puts one, and it is what the grid's
-- alignment already measures.
function H.env_show(env)
    if not env or not r.BR_EnvAlloc or not r.BR_EnvSetProperties then return end
    local handle = r.BR_EnvAlloc(env, false)
    if not handle then return end
    local active, visible, armed, in_lane, lane_height, shape,
        _, _, _, _, fader = r.BR_EnvGetProperties(handle)
    if active and visible and in_lane then
        r.BR_EnvFree(handle, false)
        return
    end
    -- Height 0 means "whatever REAPER uses", which is what a lane made by hand
    -- gets; only a lane squeezed to nothing is given a workable size.
    local height = (lane_height and lane_height > 0 and lane_height < 24) and 0 or lane_height or 0
    r.BR_EnvSetProperties(handle, true, true, armed, true, height, shape, fader)
    r.BR_EnvFree(handle, true)
    if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
    r.UpdateArrange()
end

-- What the parameter's own range is. SWS knows it exactly, including the
-- project's volume envelope range; without it the ranges above are the fallback
-- and an FX parameter is 0..1, which it always is.
function H.env_range(env, target)
    -- Cached per envelope: a launch converts every point in the curve, and
    -- allocating an SWS envelope handle for each of them is work for nothing.
    -- Ranges are a project setting, so the cache is dropped when a project is.
    L.env_ranges = L.env_ranges or {}
    local key = tostring(env)
    local cached = L.env_ranges[key]
    if cached then return cached[1], cached[2] end
    local entry = H.autom_kind(target)
    local low, high = entry and entry.min or 0, entry and entry.max or 1
    if r.BR_EnvAlloc then
        local handle = r.BR_EnvAlloc(env, false)
        if handle then
            local _, _, _, _, _, _, minimum, maximum = r.BR_EnvGetProperties(handle)
            r.BR_EnvFree(handle, false)
            if type(minimum) == "number" and type(maximum) == "number" and maximum > minimum then
                low, high = minimum, maximum
            end
        end
    end
    L.env_ranges[key] = { low, high }
    return low, high
end

function H.env_to_unit(env, target, value)
    local mode = r.GetEnvelopeScalingMode and r.GetEnvelopeScalingMode(env) or 0
    local real = value or 0
    if mode ~= 0 and r.ScaleFromEnvelopeMode then real = r.ScaleFromEnvelopeMode(mode, real) end
    local low, high = H.env_range(env, target)
    if high <= low then return 0 end
    return math.max(0, math.min(1, (real - low) / (high - low)))
end

function H.unit_to_env(env, target, unit)
    local low, high = H.env_range(env, target)
    local real = low + math.max(0, math.min(1, unit or 0)) * (high - low)
    local mode = r.GetEnvelopeScalingMode and r.GetEnvelopeScalingMode(env) or 0
    if mode ~= 0 and r.ScaleToEnvelopeMode then real = r.ScaleToEnvelopeMode(mode, real) end
    return real
end

-- A new clip starts as a flat line where the parameter stands now, so drawing
-- into it is a change from what you were already hearing.
function H.autom_flat(env, target)
    local unit = 0.5
    if env and r.Envelope_Evaluate then
        local _, value = r.Envelope_Evaluate(env, r.GetCursorPosition() or 0, 0, 0)
        if type(value) == "number" then unit = H.env_to_unit(env, target, value) end
    end
    return { { t = 0, v = unit }, { t = 1, v = unit } }
end

-- A copy deep enough that two slots never share a curve: the grid hands these
-- tables straight to the menus, and a copied clip has to be its own from then on.
function H.copy_autom(autom)
    if type(autom) ~= "table" then return nil end
    local target = autom.target or {}
    local points = {}
    for _, point in ipairs(autom.points or {}) do
        points[#points + 1] = { t = point.t, v = point.v, s = point.s, n = point.n }
    end
    return {
        bars = autom.bars,
        target = { kind = target.kind, fx = target.fx, param = target.param,
                   fx_name = target.fx_name, param_name = target.param_name },
        points = points,
    }
end

-- The same table read back off disk, where every field is whatever the file
-- said it was. A curve that does not survive this is a flat line, not an error.
function H.read_autom(stored)
    local target = type(stored) == "table" and type(stored.target) == "table" and stored.target or {}
    local kind = target.kind == "fx" and "fx" or (H.autom_kind(target) and target.kind or "vol")
    local points = {}
    local listed = (type(stored) == "table" and type(stored.points) == "table") and stored.points or {}
    for _, point in ipairs(listed) do
        local at = type(point) == "table" and tonumber(point.t) or nil
        local value = type(point) == "table" and tonumber(point.v) or nil
        if at and value then
            points[#points + 1] = {
                t = math.max(0, math.min(1, at)),
                v = math.max(0, math.min(1, value)),
                s = tonumber(point.s) and math.floor(tonumber(point.s)) or nil,
                n = tonumber(point.n),
            }
        end
    end
    if #points == 0 then points = { { t = 0, v = 0.5 }, { t = 1, v = 0.5 } } end
    return {
        bars = math.max(1, math.floor(tonumber(type(stored) == "table" and stored.bars) or 1)),
        target = {
            kind = kind,
            fx = type(target.fx) == "string" and target.fx or nil,
            param = tonumber(target.param) and math.floor(tonumber(target.param)) or nil,
            fx_name = type(target.fx_name) == "string" and target.fx_name or nil,
            param_name = type(target.param_name) == "string" and target.param_name or nil,
        },
        points = points,
    }
end

-- REAPER's own automation item files: the ones the envelope lane's "Load/save
-- automation item" saves, in the AutomationItems folder of the resource path,
-- subfolders and all. Read once per session, the same way the FX chains are.
--
-- The format is a header and a list of points:
--   SRCLEN <length in QN>
--   PPT <position in QN> <value> <shape> <tension> ...
-- and the values are already normalised 0..1, because a pool has to be able to
-- land on any envelope. That is exactly how a clip stores its curve, so a file
-- comes in without being converted at all.
function H.autom_files()
    if L.autom_files ~= nil then return L.autom_files end
    L.autom_files = false
    if not r.EnumerateFiles then return false end
    local root = r.GetResourcePath() .. C.sep .. "AutomationItems"
    local function walk(folder, name)
        local node = { name = name, files = {}, folders = {} }
        local index = 0
        while true do
            local file = r.EnumerateFiles(folder, index)
            if not file then break end
            if file:lower():sub(-15) == ".reaperautoitem" then
                node.files[#node.files + 1] = { name = file:sub(1, -16), path = folder .. C.sep .. file }
            end
            index = index + 1
        end
        index = 0
        while true do
            local sub = r.EnumerateSubdirectories and r.EnumerateSubdirectories(folder, index)
            if not sub then break end
            local child = walk(folder .. C.sep .. sub, sub)
            if child then node.folders[#node.folders + 1] = child end
            index = index + 1
        end
        if #node.files == 0 and #node.folders == 0 then return nil end
        table.sort(node.files, function(a, b) return a.name:lower() < b.name:lower() end)
        table.sort(node.folders, function(a, b) return a.name:lower() < b.name:lower() end)
        return node
    end
    L.autom_files = walk(root, "AutomationItems") or false
    return L.autom_files
end

-- One file as a curve. Times come back as a fraction of the item's own length
-- so the clip can be any number of bars, and the length itself is reported in
-- quarter notes for whoever wants to keep it.
function H.read_autom_file(path)
    local file = io.open(path, "r")
    if not file then return nil end
    local content = file:read("*a")
    file:close()
    if not content then return nil end
    local span = tonumber(content:match("SRCLEN%s+([%d%.%-]+)")) or 0
    local points = {}
    for at, value, shape, tension in content:gmatch("PPT%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)") do
        local position, level = tonumber(at), tonumber(value)
        if position and level then
            points[#points + 1] = {
                t = span > 0 and math.max(0, math.min(1, position / span)) or 0,
                v = math.max(0, math.min(1, level)),
                s = tonumber(shape) and math.floor(tonumber(shape)) ~= 0 and math.floor(tonumber(shape)) or nil,
                n = tonumber(tension) and math.abs(tonumber(tension)) > 0.0001 and tonumber(tension) or nil,
            }
        end
    end
    if #points == 0 then return nil end
    table.sort(points, function(first, second) return first.t < second.t end)
    return points, span
end

-- Whole quarter notes into bars, because a clip is a number of bars.
function H.bars_from_qn(span)
    local per_bar = H.qn_per_bar(H.meter_position())
    if not span or span <= 0 or not per_bar or per_bar <= 0 then return nil end
    return math.max(1, math.floor(span / per_bar + 0.5))
end

function H.apply_autom_file(holder, row, path, name)
    local slot = H.slot(holder, row)
    local autom = H.autom(slot)
    if not autom then return false end
    local points, span = H.read_autom_file(path)
    if not points then
        L.status = "Could not read " .. (name or path)
        return false
    end
    autom.points = points
    autom.bars = H.bars_from_qn(span) or autom.bars
    if name and name ~= "" then slot.name = name end
    H.save()
    L.status = "Loaded " .. (name or "automation item") .. "  |  "
        .. tostring(#points) .. " points, " .. tostring(H.autom_bars(slot))
        .. (H.autom_bars(slot) == 1 and " bar" or " bars")
    return true
end

-- A new clip straight from a file: made at the length the file says it is, so
-- a four bar sweep arrives as a four bar clip.
function H.new_autom_from_file(holder, row, target, path, name)
    local points, span = H.read_autom_file(path)
    if not points then
        L.status = "Could not read " .. (name or path)
        return false
    end
    local slot = H.new_autom_clip(holder, row, target, H.bars_from_qn(span))
    if not slot then return false end
    slot.autom.points = points
    if name and name ~= "" then slot.name = name end
    H.save()
    L.status = "Loaded " .. (name or "automation item") .. " into its own lane"
    return true
end

function H.autom_root()
    return r.GetResourcePath() .. C.sep .. "AutomationItems"
end

-- Whatever a clip is called, made safe to be a file name. Windows keeps a short
-- list of characters to itself, and a name that is nothing but those would
-- otherwise write a file called ".ReaperAutoItem".
function H.safe_file_name(name)
    local text = tostring(name or "")
    text = text:gsub('[<>:"/|?*]', " "):gsub("\\", " "):gsub("%c", " ")
    text = text:gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if text == "" then text = "clip" end
    return text
end

-- A clip written back out as one of REAPER's own automation items, so a curve
-- you built here can be dropped on any envelope in any project later. The same
-- three lines the loader reads: how long it is in quarter notes, the LFO header
-- REAPER writes and ignores, and a point per line.
function H.write_autom_file(path, slot)
    local autom = H.autom(slot)
    if not autom or not path or path == "" then return false end
    local per_bar = H.qn_per_bar(H.meter_position())
    if not per_bar or per_bar <= 0 then per_bar = 4 end
    local span = per_bar * H.autom_bars(slot)
    local lines = { string.format("SRCLEN %.10g", span), "LFO 0 0 0 0 0 0 0" }
    for _, point in ipairs(H.autom_points(slot)) do
        lines[#lines + 1] = string.format("PPT %.10g %.10g %d %.6g 0",
            math.max(0, math.min(1, point.t or 0)) * span,
            math.max(0, math.min(1, point.v or 0)),
            math.floor(point.s or 0), point.n or 0)
    end
    local file = io.open(path, "w")
    if not file then return false end
    file:write(table.concat(lines, "\n") .. "\n")
    file:close()
    return true
end

function H.ask_autom_save(lane, row)
    L.autom_save_prompt = { lane = lane, row = row }
end

-- Modal, so it runs from update() before the frame starts, the way every other
-- dialog here does.
function H.run_autom_save_prompt()
    local prompt = L.autom_save_prompt
    if not prompt then return end
    L.autom_save_prompt = nil
    local slot = H.slot(prompt.lane, prompt.row)
    if not H.autom(slot) then return end
    local folder = H.autom_root()
    if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(folder, 0) end
    local suggested = H.safe_file_name(slot.name) .. ".ReaperAutoItem"
    local path = nil
    if r.JS_Dialog_BrowseForSaveFile then
        local nul = string.char(0)
        local filter = "REAPER automation item (*.ReaperAutoItem)" .. nul .. "*.ReaperAutoItem" .. nul
        local ok, chosen = r.JS_Dialog_BrowseForSaveFile("Save automation item", folder, suggested, filter)
        if not ok or not chosen or chosen == "" then return end
        path = chosen
    else
        -- Without js_ReaScriptAPI there is no save dialog, so the name is asked
        -- for and the file lands in the folder itself.
        if not r.GetUserInputs then return end
        local ok, answer = r.GetUserInputs("Save automation item", 1, "Name:,extrawidth=180", slot.name or "")
        if not ok then return end
        answer = tostring(answer or ""):match("^%s*(.-)%s*$")
        if answer == "" then return end
        path = folder .. C.sep .. H.safe_file_name(answer) .. ".ReaperAutoItem"
    end
    if path:lower():sub(-15) ~= ".reaperautoitem" then path = path .. ".ReaperAutoItem" end
    if not H.write_autom_file(path, slot) then
        L.status = "Could not write " .. path
        return
    end
    -- Read the folder again, so what you just saved is in the load menus.
    L.autom_files = nil
    L.status = "Saved " .. (path:match("([^/\\]+)$") or path)
end

-- The folder tree as menus. Files first, then the folders under them, which is
-- how the FX browser lists its own folders.
function H.draw_autom_file_menu(node, key, pick, nested)
    if not node then return end
    for index, file in ipairs(node.files) do
        if r.ImGui_MenuItem(UI.ctx, file.name .. "##ai" .. key .. index) then pick(file) end
    end
    for index, folder in ipairs(node.folders) do
        if r.ImGui_BeginMenu(UI.ctx, folder.name .. "##aidir" .. key .. index) then
            H.draw_autom_file_menu(folder, key .. "_" .. index, pick, true)
            r.ImGui_EndMenu(UI.ctx)
        end
    end
    -- The folder is read once and kept, so there has to be a way to say that it
    -- changed. Saving a shape out of REAPER's envelope lane is something you do
    -- in the middle of a session, not before one.
    if not nested then
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Look at the folder again##ai" .. key) then
            L.autom_files = nil
            L.status = "Automation items read again"
        end
    end
end

function H.autom_points(slot)
    local autom = H.autom(slot)
    local points = autom and autom.points
    if type(points) ~= "table" or #points < 1 then return { { t = 0, v = 0.5 }, { t = 1, v = 0.5 } } end
    return points
end

function H.autom_bars(slot)
    local autom = H.autom(slot)
    return math.max(1, math.floor(tonumber(autom and autom.bars) or 1))
end

-- Read from bars every time rather than from the library item: the item is only
-- there to be a guid, and a clip written in bars has to follow the tempo.
function H.autom_length(slot, position)
    position = position or r.GetCursorPosition() or 0
    local length = H.bars_to_time(position, H.autom_bars(slot))
    if not length or length <= 0 then length = slot.length or 2 end
    return math.max(0.05, length)
end

function H.autom_index(handle)
    if not handle or not handle.env or not r.CountAutomationItems then return nil end
    local count = r.CountAutomationItems(handle.env) or 0
    for index = 0, count - 1 do
        local pool = math.floor(r.GetSetAutomationItemInfo(handle.env, index, "D_POOL_ID", 0, false) or -1)
        if pool == handle.pool then return index end
    end
    -- The pool id did not answer. An item still carrying our name and sitting
    -- where we put it is the one we mean; it is only ever a moment old.
    if not handle.name or not handle.at or not r.GetSetAutomationItemInfo_String then return nil end
    for index = 0, count - 1 do
        local ok, name = r.GetSetAutomationItemInfo_String(handle.env, index, "P_POOL_NAME", "", false)
        if ok and name == handle.name then
            local at = r.GetSetAutomationItemInfo(handle.env, index, "D_POSITION", 0, false) or -1
            if math.abs(at - handle.at) < 0.002 then return index end
        end
    end
    return nil
end

-- One instance of a clip's curve, laid down on an envelope. Every instance is
-- its own pool: nothing here wants two of them to share their points, and an
-- unpooled item can be thrown away without asking what else is using it.
--
-- The points go in while the item is still exactly one clip long. Written into
-- an item already stretched out to a voice length they would be one long pass
-- instead of the loop the clip is.
function H.autom_insert(env, target, slot, position, clip_length, total_length, name)
    if not H.autom_ready() or not env then return nil end
    local index = r.InsertAutomationItem(env, -1, position, clip_length)
    if not index or index < 0 then return nil end
    -- A new automation item collects whatever the envelope already had under
    -- it. The clip is the curve, not the track's own automation, so that goes.
    if r.DeleteEnvelopePointRangeEx then
        r.DeleteEnvelopePointRangeEx(env, index, position - 1, position + clip_length + 1)
    end
    local qn = r.TimeMap2_timeToQN(0, position + clip_length) - r.TimeMap2_timeToQN(0, position)
    if qn > 0 then r.GetSetAutomationItemInfo(env, index, "D_POOL_QNLEN", qn, true) end
    local function write(origin)
        for _, point in ipairs(H.autom_points(slot)) do
            local at = origin + math.max(0, math.min(1, point.t or 0)) * clip_length
            r.InsertEnvelopePointEx(env, index, at, H.unit_to_env(env, target, point.v),
                math.floor(point.s or 0), point.n or 0, false, true)
        end
        if r.Envelope_SortPointsEx then r.Envelope_SortPointsEx(env, index) end
    end
    write(position)
    -- Points in an automation item are timed from the start of the project. If
    -- that leaves the item empty they were wanted from its own start instead;
    -- an item that came out with nothing in it would play as no automation at
    -- all, which is the one outcome worth spending a second attempt on.
    if r.CountEnvelopePointsEx and (r.CountEnvelopePointsEx(env, index) or 0) == 0 then
        write(0)
    end
    if r.GetSetAutomationItemInfo_String and name then
        r.GetSetAutomationItemInfo_String(env, index, "P_POOL_NAME", name, true)
    end
    if total_length and total_length > clip_length + 0.0001 then
        r.GetSetAutomationItemInfo(env, index, "D_LOOPSRC", 1, true)
        r.GetSetAutomationItemInfo(env, index, "D_LENGTH", total_length, true)
    else
        r.GetSetAutomationItemInfo(env, index, "D_LOOPSRC", 0, true)
    end
    local pool = math.floor(r.GetSetAutomationItemInfo(env, index, "D_POOL_ID", 0, false) or -1)
    -- Where it went and what it is called are kept as a second way of finding
    -- it back. A pool id is the sharp handle, but it is REAPER's number, and an
    -- item we cannot find again is one we can neither trim nor remove.
    return { env = env, pool = pool, at = position, name = name }
end

function H.autom_trim(handle, time)
    local index = H.autom_index(handle)
    if not index then return end
    local at = r.GetSetAutomationItemInfo(handle.env, index, "D_POSITION", 0, false) or 0
    local length = time - at
    if length <= 0.0001 then return end
    r.GetSetAutomationItemInfo(handle.env, index, "D_LENGTH", length, true)
end

function H.autom_end(handle)
    local index = H.autom_index(handle)
    if not index then return nil end
    return (r.GetSetAutomationItemInfo(handle.env, index, "D_POSITION", 0, false) or 0)
        + (r.GetSetAutomationItemInfo(handle.env, index, "D_LENGTH", 0, false) or 0)
end

function H.autom_start(handle)
    local index = H.autom_index(handle)
    if not index then return nil end
    return r.GetSetAutomationItemInfo(handle.env, index, "D_POSITION", 0, false) or 0
end

function H.autom_extend(handle, heard)
    local index = H.autom_index(handle)
    if not index then return end
    local at = r.GetSetAutomationItemInfo(handle.env, index, "D_POSITION", 0, false) or 0
    local length = r.GetSetAutomationItemInfo(handle.env, index, "D_LENGTH", 0, false) or 0
    if at + length - heard > C.voice_margin then return end
    r.GetSetAutomationItemInfo(handle.env, index, "D_LENGTH", length + C.voice_extend, true)
end

-- REAPER has no call for removing an automation item. In the envelope's chunk
-- an instance is a single POOLEDENVINST line whose first field is its pool, so
-- the line goes and the chunk is put back. Checked afterwards: if the surgery
-- missed, the item is shrunk away instead of being left playing.
function H.autom_delete(handle)
    if not handle or not handle.env then return true end
    local index = H.autom_index(handle)
    if not index then return true end
    local ok, chunk = r.GetEnvelopeStateChunk(handle.env, "", false)
    if ok and chunk and chunk ~= "" then
        local lines = {}
        for line in (chunk .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
        local marks = {}
        for number, line in ipairs(lines) do
            local first = line:match("^%s*POOLEDENVINST%s+(%S+)")
            if first then marks[#marks + 1] = { at = number, pool = tonumber(first) } end
        end
        local chosen = nil
        for _, mark in ipairs(marks) do
            if mark.pool == handle.pool then chosen = mark.at break end
        end
        -- Falls back to counting them off in order, which is the order
        -- CountAutomationItems reports them in.
        if not chosen and marks[index + 1] then chosen = marks[index + 1].at end
        if chosen then
            table.remove(lines, chosen)
            r.SetEnvelopeStateChunk(handle.env, table.concat(lines, "\n"), false)
        end
    end
    local left = H.autom_index(handle)
    if left then
        r.GetSetAutomationItemInfo(handle.env, left, "D_LOOPSRC", 0, true)
        r.GetSetAutomationItemInfo(handle.env, left, "D_LENGTH", 0.0001, true)
        return false
    end
    return true
end

-- Voices left behind by a crash or a forced quit, found by the name their pool
-- carries. Run on load, the same way stray media voices are swept.
function H.sweep_stray_autom()
    if not H.autom_ready() or not r.GetSetAutomationItemInfo_String then return end
    local function sweep(env)
        local guard = 0
        while guard < 64 do
            guard = guard + 1
            local found = nil
            local drawing = L.autom_edit and L.autom_edit.handle and L.autom_edit.handle.pool or nil
            for index = 0, (r.CountAutomationItems(env) or 0) - 1 do
                local ok, name = r.GetSetAutomationItemInfo_String(env, index, "P_POOL_NAME", "", false)
                if ok and (name == C.autom_voice_name or name == C.autom_edit_name) then
                    local pool = math.floor(r.GetSetAutomationItemInfo(env, index, "D_POOL_ID", 0, false) or -1)
                    -- The one being drawn into right now is not a leftover.
                    if pool ~= drawing then
                        found = pool
                        break
                    end
                end
            end
            if not found then return end
            if not H.autom_delete({ env = env, pool = found }) then return end
        end
    end
    for index = 0, (r.CountTracks(0) or 0) - 1 do
        local track = r.GetTrack(0, index)
        for slot = 0, (r.CountTrackEnvelopes(track) or 0) - 1 do
            sweep(r.GetTrackEnvelope(track, slot))
        end
    end
end

-- Launching one. Mirrors H.commit: the outgoing voice is closed on the same
-- boundary the new one starts on, and both edits are committed before the play
-- cursor gets there.
function H.commit_autom(lane, row, time, slot)
    local autom = H.autom(slot)
    local target = H.target_track(lane)
    if not autom or not target then return false end
    if not H.autom_ready() then
        L.status = "This REAPER cannot place automation items"
        return false
    end
    local env = H.autom_env(target, autom.target, true)
    if not env then
        L.status = "Could not find " .. H.autom_target_label(autom.target) .. " on " .. H.lane_label(lane)
        return false
    end
    H.cancel_pending(lane)
    local restore = H.close_voice_at(lane.current, time)
    local length = H.autom_length(slot, time)
    local handle = H.autom_insert(env, autom.target, slot, time, length,
        slot.loop and C.voice_length or nil, C.autom_voice_name)
    if not handle then
        L.status = "Could not place that automation clip"
        return false
    end
    lane.pending = {
        ai = handle,
        row = row,
        at = time,
        length = length,
        looped = slot.loop and true or false,
        slot_guid = slot.guid,
        restore = restore,
        hits = {},
    }
    -- A curve is not a takeover: the track's own items keep playing under it.
    -- If a media clip in this lane had the arrangement muted, this hands it back.
    if not lane.hold then H.schedule_owner(lane, "arrangement", time) end
    -- The gate is a door on the track's audio. An envelope lane has none of
    -- its own, and opening the track's from here would undo a held clip.
    if not H.is_env_lane(lane) then H.open_gate_for(lane) end
    return true
end

-- Making one. It never lands in the track's own lane: an automation clip goes
-- into the envelope lane for its parameter, which is made if this is the first
-- clip to want it. The library item is a blank MIDI item like an empty clip's,
-- kept muted and parked; nothing ever plays it, it is what the slot is called by.
function H.new_autom_clip(holder, row, target, bars)
    if not H.autom_ready() or not r.CreateNewMIDIItemInProj then
        L.status = "This REAPER cannot place automation items"
        return false
    end
    local parent = H.is_env_lane(holder) and holder.parent or holder
    local lane = H.env_lane_for(parent, target, true)
    if not lane then
        L.status = "Could not make an automation lane there"
        return false
    end
    local track = H.target_track(lane)
    local env = track and H.autom_env(track, target, true)
    if not env then
        L.status = "Could not make that envelope on " .. H.lane_label(lane)
        return false
    end
    H.env_show(env)
    local lane_track = H.ensure_lane_track(lane)
    if not lane_track then
        L.status = "Could not make a lane track for this clip"
        return false
    end
    local position = r.GetCursorPosition() or 0
    bars = bars or H.scene_bars(row, position) or 1
    local length = H.bars_to_time(position, bars)
    if not length or length <= 0 then length = 2 end
    r.Undo_BeginBlock()
    local park = H.park_position()
    local blank = r.CreateNewMIDIItemInProj(lane_track, park, park + length, false)
    -- The one item an envelope lane is allowed to be handed: its own anchor.
    L.autom_building = true
    local made = blank and H.assign_slot(lane, row, blank) or false
    L.autom_building = nil
    if H.valid_item(blank) then r.DeleteTrackMediaItem(lane_track, blank) end
    r.Undo_EndBlock("New launcher automation clip", -1)
    r.UpdateArrange()
    local slot = made and H.slot(lane, row) or nil
    if not slot then
        L.status = "Could not make an automation clip"
        return false
    end
    slot.kind = "automation"
    -- The anchor happens to be MIDI; the clip is not, and every menu that reads
    -- notes has to leave it alone. What trimming that blank item did or failed
    -- to do is not this clip's business either.
    slot.is_midi = false
    slot.sectioned = nil
    slot.trim_failed = nil
    slot.name = H.autom_target_label(target)
    slot.loop = true
    slot.autom = { target = target, bars = bars, points = H.autom_flat(env, target) }
    H.save()
    L.status = slot.name .. " automation clip, in its own lane under "
        .. H.lane_label(lane) .. "  |  right-click it and pick Edit curve to draw"
    return slot
end

function H.repoint_env_lane(sub, target)
    if not sub or not target then return end
    sub.target = target
    sub.name = H.autom_target_label(target)
    for _, slot in ipairs(sub.slots) do
        local autom = H.autom(slot)
        if autom then
            local was = H.autom_target_label(autom.target)
            autom.target = target
            if slot.name == was then slot.name = sub.name end
        end
    end
    H.save()
    L.status = "That lane now automates " .. sub.name
end

function H.repoint_autom(lane, row, target)
    local slot = H.slot(lane, row)
    local autom = H.autom(slot)
    if not autom or not target then return end
    local was = H.autom_target_label(autom.target)
    autom.target = target
    if slot.name == was then slot.name = H.autom_target_label(target) end
    H.save()
    L.status = slot.name .. " now automates " .. H.autom_target_label(target)
end

function H.set_autom_bars(lane, row, bars)
    local slot = H.slot(lane, row)
    local autom = H.autom(slot)
    if not autom then return end
    autom.bars = math.max(1, math.floor(bars or 1))
    H.save()
end

-- The parameter you last moved, but only when it is on this lane's own track:
-- a descriptor pointing at a plugin the track does not have would resolve to
-- nothing at launch, and there is nothing useful to say about that afterwards.
function H.last_touched_target(track)
    if not r.GetLastTouchedFX or not H.valid_track(track) then return nil end
    local ok, track_number, fx_index, param = r.GetLastTouchedFX()
    if not ok or not track_number or track_number < 1 then return nil end
    local touched = r.GetTrack(0, track_number - 1)
    if touched ~= track then return nil end
    local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
    local _, param_name = r.TrackFX_GetParamName(track, fx_index, param, "")
    return {
        kind = "fx",
        fx = r.TrackFX_GetFXGUID and r.TrackFX_GetFXGUID(track, fx_index) or nil,
        param = math.floor(param or 0),
        fx_name = H.fx_short_name(fx_name),
        param_name = param_name ~= "" and param_name or nil,
    }
end

-- Drawing the curve happens in the arrange, where the envelope is: an
-- automation item is put down at the edit cursor with the clip in it, and the
-- toolbar grows a Done and a Cancel until you say which it is.
function H.edit_autom(lane, row)
    local slot = H.slot(lane, row)
    local autom = H.autom(slot)
    if not autom then
        L.status = "That slot is not an automation clip"
        return
    end
    if not H.autom_ready() then
        L.status = "This REAPER cannot place automation items"
        return
    end
    if L.autom_edit then H.finish_autom_edit(false) end
    local track = H.target_track(lane)
    local env = track and H.autom_env(track, autom.target, true)
    if not env then
        L.status = "Could not find " .. H.autom_target_label(autom.target) .. " on " .. H.lane_label(lane)
        return
    end
    H.env_show(env)
    local position = r.GetCursorPosition() or 0
    local length = H.autom_length(slot, position)
    r.Undo_BeginBlock()
    local handle = H.autom_insert(env, autom.target, slot, position, length, nil, C.autom_edit_name)
    r.Undo_EndBlock("Edit launcher automation clip", -1)
    if not handle then
        L.status = "Could not place that automation clip"
        return
    end
    local index = H.autom_index(handle)
    if index then r.GetSetAutomationItemInfo(handle.env, index, "D_UISEL", 1, true) end
    if r.SetCursorContext then r.SetCursorContext(2, env) end
    -- Scrolled to, not only placed: the cursor may well be off screen, and an
    -- item you cannot see reads exactly like one that was never made.
    if track and r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(track) end
    r.SetEditCurPos(position, true, false)
    L.autom_edit = { guid = slot.guid, handle = handle, at = position, length = length, name = slot.name }
    r.UpdateArrange()
    L.status = "Drawing " .. slot.name .. " on " .. H.autom_target_label(autom.target)
        .. " at " .. H.position_label(position) .. "  |  Curve done keeps it, Cancel throws it away"
end

-- Points come back the way they went in: by the item's own index, which counts
-- in project time. Its length comes back too, so stretching the item in the
-- arrange is how a clip is made longer.
function H.autom_read(handle, index, target, position, length)
    local env = handle.env
    local at = r.GetSetAutomationItemInfo(env, index, "D_POSITION", 0, false) or position
    -- How long the clip now is. The item is put down unlooped, so what is on
    -- screen is one pass and its own length is the measure; a looped one would
    -- be several passes, and only the pool length says how long one of them is.
    local span = r.GetSetAutomationItemInfo(env, index, "D_LENGTH", 0, false) or 0
    if (r.GetSetAutomationItemInfo(env, index, "D_LOOPSRC", 0, false) or 0) > 0.5 then
        local qn = r.GetSetAutomationItemInfo(env, index, "D_POOL_QNLEN", 0, false) or 0
        span = qn > 0 and (r.TimeMap2_QNToTime(0, r.TimeMap2_timeToQN(0, at) + qn) - at) or 0
    end
    if span <= 0 then span = length end
    -- A point in an automation item is timed from the start of the project.
    -- Read from the start of the item as well and the better answer kept: the
    -- two only differ by the item's position, and a reading that throws every
    -- point away is a reading that was measured from the wrong place.
    local function gather(origin)
        local found = {}
        for point = 0, (r.CountEnvelopePointsEx(env, index) or 0) - 1 do
            local ok, time, value, shape, tension = r.GetEnvelopePointEx(env, index, point)
            if ok then
                local fraction = ((time or 0) - origin) / span
                if fraction > -0.0001 and fraction < 1.0001 then
                    found[#found + 1] = {
                        t = math.max(0, math.min(1, fraction)),
                        v = H.env_to_unit(env, target, value or 0),
                        s = (shape and shape ~= 0) and math.floor(shape) or nil,
                        n = (tension and math.abs(tension) > 0.0001) and tension or nil,
                    }
                end
            end
        end
        return found
    end
    local points = gather(at)
    if #points == 0 and at > 0.0001 then points = gather(0) end
    table.sort(points, function(first, second) return first.t < second.t end)
    -- Rounded to whole bars, because that is the only length a clip has. Half a
    -- bar longer in the arrange is a bar longer here, or no change at all.
    local bars = nil
    local per_bar = H.qn_per_bar(at)
    if per_bar and per_bar > 0 then
        local spanned = r.TimeMap2_timeToQN(0, at + span) - r.TimeMap2_timeToQN(0, at)
        bars = math.max(1, math.floor(spanned / per_bar + 0.5))
    end
    return points, bars
end

function H.selected_autom_item()
    local selected = {}
    for track_index = -1, (r.CountTracks(0) or 0) - 1 do
        local track = track_index < 0 and r.GetMasterTrack(0) or r.GetTrack(0, track_index)
        for env_index = 0, (track and r.CountTrackEnvelopes(track) or 0) - 1 do
            local env = r.GetTrackEnvelope(track, env_index)
            for item_index = 0, (env and r.CountAutomationItems(env) or 0) - 1 do
                if (r.GetSetAutomationItemInfo(env, item_index, "D_UISEL", 0, false) or 0) > 0.5 then
                    selected[#selected + 1] = { env = env, index = item_index }
                end
            end
        end
    end
    if #selected == 1 then return selected[1], 1 end
    return nil, #selected
end

function H.import_selected_autom(lane, row)
    if not H.is_env_lane(lane) then return false end
    local selected, count = H.selected_autom_item()
    if count == 0 then
        L.status = "Select an automation item in the arrange first"
        return false
    end
    if count > 1 then
        L.status = "Select only one automation item"
        return false
    end
    local track = H.target_track(lane)
    local wanted_env = track and H.autom_env(track, lane.target, false)
    if not wanted_env or selected.env ~= wanted_env then
        L.status = "The selected automation item belongs to a different envelope"
        return false
    end
    local position = r.GetSetAutomationItemInfo(selected.env, selected.index, "D_POSITION", 0, false) or 0
    local length = r.GetSetAutomationItemInfo(selected.env, selected.index, "D_LENGTH", 0, false) or 0
    local points, bars = H.autom_read({ env = selected.env }, selected.index, lane.target, position, length)
    local slot = H.new_autom_clip(lane, row, lane.target, bars or 1)
    if not slot then return false end
    slot.autom.points = points
    slot.autom.bars = bars or 1
    H.save()
    L.status = "Automation item added: " .. tostring(#points) .. " points, "
        .. tostring(slot.autom.bars) .. (slot.autom.bars == 1 and " bar" or " bars")
    return true
end

-- The item being drawn into can go without us: deleted by hand, or undone.
-- Left standing, the toolbar would keep offering a Done for something that is
-- not there and the clip's own Edit entry would stay greyed out for good.
function H.watch_autom_edit()
    local edit = L.autom_edit
    if not edit then return end
    if H.autom_index(edit.handle) then return end
    L.autom_edit = nil
    L.status = (edit.name or "That curve") .. " is no longer in the arrange, so the clip is as it was"
end

function H.finish_autom_edit(keep)
    local edit = L.autom_edit
    L.autom_edit = nil
    if not edit then return end
    if keep then
        local _, slot = H.find_slot_by_guid(edit.guid)
        local autom = H.autom(slot)
        local index = H.autom_index(edit.handle)
        if autom and index then
            local points, bars = H.autom_read(edit.handle, index, autom.target, edit.at, edit.length)
            if points and #points > 0 then
                autom.points = points
                if bars then autom.bars = bars end
                H.save()
                L.status = slot.name .. ": " .. tostring(#points) .. " points, " .. tostring(H.autom_bars(slot))
                    .. (H.autom_bars(slot) == 1 and " bar" or " bars")
            else
                L.status = "That automation item has no points, so the clip is as it was"
            end
        end
    else
        L.status = "Curve left as it was"
    end
    H.autom_delete(edit.handle)
    r.UpdateArrange()
end

function H.draw_autom_target_menu(track, pick, key)
    for index, entry in ipairs(C.autom_targets) do
        if r.ImGui_MenuItem(UI.ctx, entry.label .. "##" .. key .. index) then pick({ kind = entry.kind }) end
    end
    r.ImGui_Separator(UI.ctx)
    local touched = H.last_touched_target(track)
    if touched then
        if r.ImGui_MenuItem(UI.ctx, H.autom_target_label(touched) .. "##" .. key .. "fx") then pick(touched) end
    else
        r.ImGui_MenuItem(UI.ctx, "Touch a plugin knob on this track first", nil, false, false)
    end
end

-- Target first, then how long: the parameter is what the clip is, the length is
-- a number you may well change again once the curve is drawn.
function H.draw_new_autom_menu(lane, row)
    local track = H.target_track(lane)
    local function lengths(label, target, key)
        if r.ImGui_BeginMenu(UI.ctx, label .. "##new_autom" .. key) then
            for _, bars in ipairs(C.new_clip_bars) do
                local text = bars == 1 and "1 bar" or (tostring(bars) .. " bars")
                if r.ImGui_MenuItem(UI.ctx, text .. "##new_autom" .. key) then
                    H.new_autom_clip(lane, row, target, bars)
                end
            end
            r.ImGui_Separator(UI.ctx)
            if r.ImGui_MenuItem(UI.ctx, "As long as this scene##new_autom" .. key) then
                H.new_autom_clip(lane, row, target, nil)
            end
            -- A shape off the shelf. It brings its own length, so it does not
            -- belong under the bar counts above but beside them.
            local files = H.autom_files()
            if files then
                r.ImGui_Separator(UI.ctx)
                if r.ImGui_BeginMenu(UI.ctx, "From an automation item##new_autom" .. key) then
                    H.draw_autom_file_menu(files, "new" .. key, function(file)
                        H.new_autom_from_file(lane, row, target, file.path, file.name)
                    end)
                    r.ImGui_EndMenu(UI.ctx)
                end
            end
            r.ImGui_EndMenu(UI.ctx)
        end
    end
    for index, entry in ipairs(C.autom_targets) do
        lengths(entry.label, { kind = entry.kind }, tostring(index))
    end
    r.ImGui_Separator(UI.ctx)
    local touched = H.last_touched_target(track)
    if touched then
        lengths(H.autom_target_label(touched), touched, "fx")
    else
        r.ImGui_MenuItem(UI.ctx, "Touch a plugin knob on this track first", nil, false, false)
    end
end

-- The curve, drawn into a cell the way a waveform is. Square points are drawn
-- square; every other shape reads as the line it mostly is.
function H.draw_autom_curve(draw_list, slot, x, y, width, height, ink)
    if width <= 2 or height <= 2 then return end
    local top, bottom = y + UI.scaled(2), y + height - UI.scaled(2)
    local span = bottom - top
    if span <= 1 then return end
    local floor_ink = (ink & 0xFFFFFF00) | 0x30
    r.ImGui_DrawList_AddLine(draw_list, x, bottom, x + width, bottom, floor_ink, UI.scaled(1))
    local thickness = UI.scaled(1.5)
    local previous = nil
    for _, point in ipairs(H.autom_points(slot)) do
        local at = x + math.max(0, math.min(1, point.t or 0)) * width
        local level = bottom - math.max(0, math.min(1, point.v or 0)) * span
        if not previous then
            if at > x + 0.5 then
                r.ImGui_DrawList_AddLine(draw_list, x, level, at, level, ink, thickness)
            end
        elseif (previous.shape or 0) == 1 then
            r.ImGui_DrawList_AddLine(draw_list, previous.x, previous.y, at, previous.y, ink, thickness)
            r.ImGui_DrawList_AddLine(draw_list, at, previous.y, at, level, ink, thickness)
        else
            r.ImGui_DrawList_AddLine(draw_list, previous.x, previous.y, at, level, ink, thickness)
        end
        previous = { x = at, y = level, shape = point.s }
    end
    if previous and previous.x < x + width - 0.5 then
        r.ImGui_DrawList_AddLine(draw_list, previous.x, previous.y, x + width, previous.y, ink, thickness)
    end
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

-- Started from where the clip was put, not from wherever REAPER last left off.
-- Launching with the transport stopped writes the voice at the edit cursor, but
-- pressing play does not have to begin there - that depends on a preference -
-- and when the two disagree the clip sits somewhere the take never reaches.
function H.roll_transport(at)
    -- The seek happens whether or not the transport is already rolling. It is
    -- only ever asked for when the clip was placed at the edit cursor rather
    -- than at the play position, and then the two must be brought together: a
    -- clip sitting eighty seconds from the play cursor is never heard and never
    -- lands in a take. Deciding that from the play state was the mistake - it
    -- can read stopped one moment and playing the next.
    local rolling = (r.GetPlayState() & 1) == 1
    if rolling then
        if at and r.SetEditCurPos then r.SetEditCurPos(at, false, true) end
        return
    end
    -- The third argument is the one that matters: it seeks the play position,
    -- not just the edit cursor. Without it REAPER starts wherever it likes -
    -- usually where it last stopped - and the clip sits somewhere the take
    -- never reaches. Done again after the play command, because a stopped
    -- transport has no position to seek until it has one.
    if at and r.SetEditCurPos then r.SetEditCurPos(at, false, true) end
    if r.OnPlayButton then r.OnPlayButton() else r.Main_OnCommand(1007, 0) end
    if at and r.SetEditCurPos then r.SetEditCurPos(at, false, true) end
    -- The transport needs a moment to report "playing"; without this grace
    -- period the next update() would read "stopped" and harvest the voice we
    -- just scheduled.
    L.roll_guard = r.time_precise() + 1.5
end

-- A clip and the curves that belong to it: the lane, plus the envelope lanes
-- under it. Launching the clip launches the curves in its row with it. The
-- other way round it does not work: firing a curve moves that one lane to that
-- row and leaves everything else exactly as it was, which is what makes an
-- envelope lane usable as a lane rather than as a second scene column.
--
-- Launching only ever starts things. A curve keeps running when the clip above
-- it moves to a row that has none, because stopping in this launcher is always
-- something you ask for: a stop square, a track stop (which takes its curves
-- with it), or the empty cell of a scene, which is the scene's own rule.
function H.group_of(holder)
    local lane = H.is_env_lane(holder) and holder.parent or holder
    local group = { lane }
    for _, sub in ipairs(lane.envs or {}) do group[#group + 1] = sub end
    return group, lane
end

-- Everything this row has in the group. Called for a track clip; an envelope
-- lane launches on its own, so it never comes through here.
function H.commit_group(holder, row, time)
    local launched = false
    for _, member in ipairs(H.group_of(holder)) do
        if (not H.is_env_lane(member) or (member.follow_parent ~= false and not member.paused))
            and H.slot(member, row) and H.commit(member, row, time) then launched = true end
    end
    return launched
end

function H.queue_group(holder, row)
    for _, member in ipairs(H.group_of(holder)) do
        if (not H.is_env_lane(member) or (member.follow_parent ~= false and not member.paused))
            and H.slot(member, row) then
            member.queued = { row = row }
        end
    end
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
    -- A track clip takes the curves in its row along; a curve goes alone.
    local alone = H.is_env_lane(lane)
    if at_wrap then
        if alone then lane.queued = { row = row } else H.queue_group(lane, row) end
        local slot = H.slot(lane, row)
        L.status = "Queued " .. (slot and slot.name or "clip") .. " for the top of the loop"
        return
    end
    r.PreventUIRefresh(1)
    -- Written out: with "and ... or ...", a commit that returned false would
    -- fall through and launch the whole group after all.
    local ok
    if alone then
        ok = H.commit(lane, row, time)
    else
        ok = H.commit_group(lane, row, time)
    end
    r.PreventUIRefresh(-1)
    if not ok then
        L.status = "Could not launch that slot"
        return
    end
    if needs_roll then H.roll_transport(time) end
    r.UpdateArrange()
    local slot = H.slot(lane, row)
    L.status = "Launched " .. (slot and slot.name or "clip")
end

-- A scene is a section of the song, so an empty slot means "this track is not
-- part of it" and its lane stops on the same boundary. Without that a clip from
-- the previous scene would play straight through the next one.
function H.scene_commit(row, time)
    local launched, stopped = 0, 0
    local already_deferred = L.defer_restore_save
    L.defer_restore_save = true
    for _, lane in ipairs(H.holders()) do
        if not H.lane_orphaned(lane) then
            if H.is_env_lane(lane) and lane.paused then
                lane.queued = nil
            elseif H.slot(lane, row) then
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
    L.defer_restore_save = already_deferred
    if not already_deferred and L.restore_save_dirty then H.save_restore_state() end
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
        for _, lane in ipairs(H.holders()) do
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
        for _, lane in ipairs(H.holders()) do
            if not H.lane_orphaned(lane) then
                if H.is_env_lane(lane) and lane.paused then
                    lane.queued = nil
                elseif H.slot(lane, row) then
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
    if needs_roll and launched > 0 then H.roll_transport(time) end
    r.UpdateArrange()
    L.status = "Scene " .. tostring(row) .. ": " .. tostring(launched) .. " playing"
        .. (stopped > 0 and (", " .. tostring(stopped) .. " stopped") or "")
end

-- Given a time, the lane ends there; given none, on the next bar line. A gate
-- released mid-bar wants the first: the sound has already stopped, and a voice
-- left running to the bar line would be kept as part of the take.
-- Stopping a track stops what it was automating as well. Stopping one
-- envelope lane leaves the rest of the group alone.
function H.stopped_with(lane)
    local also = {}
    if not H.is_env_lane(lane) then
        for _, sub in ipairs(lane.envs or {}) do also[#also + 1] = sub end
    end
    return also
end

function H.stop_lane(lane, at)
    lane.run = nil
    lane.queued = nil
    local now = H.schedule_pos()
    if not now then
        H.harvest_lane(lane, true)
        H.release_now(lane)
        for _, sub in ipairs(H.stopped_with(lane)) do
            sub.run = nil
            H.harvest_lane(sub, true)
        end
        r.UpdateArrange()
        return
    end
    local time = at or H.boundary_after(now, false)
    r.PreventUIRefresh(1)
    for _, sub in ipairs(H.stopped_with(lane)) do
        sub.run = nil
        sub.queued = nil
        H.cancel_pending(sub)
        H.close_voice_at(sub.current, time)
    end
    H.cancel_pending(lane)
    H.remember_stopped_voice(lane, lane.current, time)
    H.close_voice_at(lane.current, time)
    -- A deliberately muted arrangement stays muted; stopping the clip is not a
    -- request to hand the track back.
    if not lane.hold then H.schedule_owner(lane, "arrangement", time) end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    if H.is_env_lane(lane) then
        -- Nothing is handed back here: an automation lane never took the
        -- arrangement off the track in the first place.
        L.status = at and "Automation lane stopped"
            or "Automation lane stops on the next boundary"
    elseif at then
        L.status = lane.hold and "Lane stopped" or "Lane returned to the arrangement"
    else
        L.status = lane.hold and "Lane stops on the next boundary" or "Lane returns to the arrangement on the next boundary"
    end
end

function H.stop_all_quantized()
    local now = H.schedule_pos()
    if not now then
        H.reset_all()
        return
    end
    local time = H.boundary_after(now, false)
    r.PreventUIRefresh(1)
    for _, lane in ipairs(H.holders()) do
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
    for _, lane in ipairs(H.holders()) do
        lane.hold = false
        H.harvest_lane(lane, true)
        H.release_now(lane)
    end
    H.restore_arrangement_mute()
    -- Curves nothing is holding on to any more go the same way, apart from one
    -- that is being drawn into: Reset is not a request to lose that.
    H.sweep_stray_autom()
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
        guide_guid = L.guide_guid,
        lanes = {},
    }
    for row, entry in pairs(L.scenes or {}) do
        if entry.follow ~= "stop" or (entry.plays or 1) ~= 1 then
            data.scenes[#data.scenes + 1] = { row = row, follow = entry.follow, plays = entry.plays }
        end
    end
    for _, lane in ipairs(L.lanes) do
        local envs = {}
        for _, sub in ipairs(lane.envs or {}) do
            envs[#envs + 1] = {
                name = sub.name,
                follow_parent = sub.follow_parent ~= false,
                paused = sub.paused and true or nil,
                target = H.read_autom({ target = sub.target }).target,
                slots = H.saved_slots(sub),
            }
        end
        data.lanes[#data.lanes + 1] = {
            name = lane.name,
            match = lane.match,
            track_guid = lane.track_guid,
            lane_guid = lane.lane_guid,
            slots = H.saved_slots(lane),
            envs = #envs > 0 and envs or nil,
        }
    end
    local ok, encoded = pcall(UI.json.encode, data)
    if ok and encoded then
        r.SetProjExtState(0, C.proj_section, "grid", encoded)
        if not quiet and r.MarkProjectDirty then r.MarkProjectDirty(0) end
    end
end

-- One holder's clips as plain data. Written for lanes and for the envelope
-- lanes under them, which store exactly the same thing.
function H.saved_slots(holder)
    local slots = {}
    for _, slot in ipairs(holder.slots) do
        slots[#slots + 1] = {
            row = slot.row,
            guid = slot.guid,
            name = slot.name,
            is_midi = slot.is_midi and true or false,
            length = slot.length,
            loop = slot.loop and true or false,
            loop_len = slot.loop_len,
            tempo_matched = slot.tempo_matched and true or nil,
            speed = slot.speed or nil,
            launch_mode = slot.launch_mode or nil,
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
            chord_follow = slot.chord_follow,
            kind = slot.kind,
            autom = H.autom(slot) and H.copy_autom(slot.autom) or nil,
        }
    end
    return slots
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

function H.degree_index(key, pitch_class)
    if not key then return nil end
    local relative = (pitch_class - key.root) % 12
    for index, degree in ipairs(H.mode_entry(key.mode).degrees) do
        if degree == relative then return index end
    end
    return nil
end

function H.shift_scale_degree(pitch, key, degree_shift)
    local degrees = H.mode_entry(key.mode).degrees
    local relative = pitch - key.root
    local octave = math.floor(relative / 12)
    local pitch_class = relative % 12
    local index, offset = 1, pitch_class
    for step = #degrees, 1, -1 do
        if pitch_class >= degrees[step] then
            index, offset = step, pitch_class - degrees[step]
            break
        end
    end
    local absolute = octave * #degrees + index - 1 + degree_shift
    local target_octave = math.floor(absolute / #degrees)
    local target_index = (absolute % #degrees) + 1
    local result = key.root + target_octave * 12 + degrees[target_index] + offset
    while result < 0 do result = result + 12 end
    while result > 127 do result = result - 12 end
    return result
end

function H.slot_by_guid(guid)
    for _, lane in ipairs(H.holders()) do
        for _, slot in ipairs(lane.slots or {}) do
            if slot.guid == guid then return slot end
        end
    end
    return nil
end

function H.detach_midi_source(media)
    local take = H.valid_item(media) and r.GetActiveTake(media) or nil
    if not take or not r.TakeIsMIDI(take) or not r.MIDI_GetAllEvts or not r.MIDI_SetAllEvts then return false end
    local ok, events = r.MIDI_GetAllEvts(take, "")
    if not ok then return false end
    local track = r.GetMediaItemTrack(media)
    local position = r.GetMediaItemInfo_Value(media, "D_POSITION") or 0
    local length = math.max(0.05, r.GetMediaItemInfo_Value(media, "D_LENGTH") or 0.05)
    local temporary = r.CreateNewMIDIItemInProj(track, position, position + length, false)
    local temporary_take = temporary and r.GetActiveTake(temporary) or nil
    if not temporary_take then return false end
    local written = r.MIDI_SetAllEvts(temporary_take, events)
    if written then r.MIDI_Sort(temporary_take) end
    local source = written and r.GetMediaItemTake_Source(temporary_take) or nil
    if source then r.SetMediaItemTake_Source(take, source) end
    r.DeleteTrackMediaItem(track, temporary)
    return source ~= nil
end

function H.apply_chord_follow(media, slot)
    if not H.valid_item(media) or not slot or not slot.is_midi or not slot.chord_follow then return end
    local source_root = slot.key_applied and slot.key_applied.root
        or (slot.key and slot.key.root) or slot.root
    if source_root == nil then return end
    if not H.detach_midi_source(media) then return end
    local take = r.GetActiveTake(media)
    local notes = H.midi_notes(take)
    if notes < 1 then return end
    local pitches = {}
    for index = 0, notes - 1 do
        local ok, _, _, start_ppq, _, _, pitch = r.MIDI_GetNote(take, index)
        local result = ok and pitch or 60
        if ok then
            local chord = select(1, H.guide_at(r.MIDI_GetProjTimeFromPPQPos(take, start_ppq)))
            local target_root = H.chord_root(chord)
            if target_root ~= nil then
                local source_degree = slot.chord_follow == "scale" and H.degree_index(L.key, source_root) or nil
                local target_degree = slot.chord_follow == "scale" and H.degree_index(L.key, target_root) or nil
                if source_degree and target_degree then
                    local shift = target_degree - source_degree
                    if shift > 3 then shift = shift - 7 elseif shift < -3 then shift = shift + 7 end
                    result = H.shift_scale_degree(pitch, L.key, shift)
                else
                    local shift = target_root - source_root
                    if shift > 6 then shift = shift - 12 elseif shift < -6 then shift = shift + 12 end
                    result = math.max(0, math.min(127, pitch + shift))
                end
            end
        end
        pitches[index + 1] = result
    end
    H.write_pitches(take, notes, function(index) return pitches[index] end)
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
        local restored, changed = 0, 0
        for _, lane in ipairs(L.lanes) do
            for _, slot in ipairs(lane.slots) do
                if slot.key_applied then
                    if H.unfit_slot_key(lane, slot.row) then
                        restored = restored + 1
                    else
                        changed = changed + 1
                    end
                end
            end
        end
        L.status = string.format("%d clips restored to their own key", restored)
        if changed > 0 then
            L.status = L.status .. string.format(", %d changed since fitting", changed)
        end
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
    -- An automation clip has no file behind it: the curve is the clip, so it
    -- travels in the set itself and lands in the next project as it stands.
    local autom = H.autom(slot)
    if autom then
        return {
            row = slot.row,
            name = slot.name,
            kind = "automation",
            autom = H.copy_autom(autom),
            loop = slot.loop and true or false,
            follow = slot.follow,
            plays = slot.plays,
            color = slot.color,
        }
    end
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
        -- Carried as its own field: the span above is in source seconds, so the
        -- next project works out its own tempo stretch and would otherwise lose
        -- the speed the clip was deliberately set to.
        speed = slot.speed or nil,
        key = slot.key and { root = slot.key.root, mode = slot.key.mode } or nil,
        repeat_qn = slot.repeat_qn,
        steps = H.steps_to_text(slot.steps),
        follow = slot.follow,
        plays = slot.plays,
        color = slot.color,
        gain = slot.gain,
        chord_follow = slot.chord_follow,
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
        -- The automation clips travel in the same list. They carry their own
        -- parameter, so loading the set is what puts the envelope lanes back.
        for _, sub in ipairs(lane.envs or {}) do
            for _, slot in ipairs(sub.slots) do
                local exported = H.slot_export(slot)
                if exported then slots[#slots + 1] = exported else skipped = skipped + 1 end
            end
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
    slot.chord_follow = stored.chord_follow == "root" and "root"
        or (stored.chord_follow == "scale" and "scale" or nil)
    local speed = tonumber(stored.speed)
    local item = H.item_from_guid(slot.guid)
    local take = item and r.GetActiveTake(item) or nil
    if not take then return end
    -- After the tempo stretch below, so the two multiply rather than fight.
    local function set_speed()
        if not speed or speed <= 0 or math.abs(speed - 1) < 0.0005 then return end
        local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
        if rate <= 0 then rate = 1 end
        H.apply_take_rate(item, take, rate * speed)
        slot.speed = speed
    end
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
    set_speed()
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
        if L.quantize < 0 and L.quantize ~= -1 then L.quantize = 1 end
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
    local added, missing_files, missing_params = 0, 0, 0
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
                    if stored.kind == "automation" then
                        -- The curve comes back whole; what may not be here is
                        -- the plugin it points at, and then there is no
                        -- envelope to put it on.
                        local wanted = H.read_autom(stored.autom)
                        local landed = row >= 1 and row <= L.rows
                            and H.new_autom_clip(lane, row, wanted.target, wanted.bars) or nil
                        local sub = H.env_lane_for(lane, wanted.target, false)
                        if landed and sub and H.autom(landed) then
                            landed.autom.points = wanted.points
                            H.apply_stored_slot(sub, row, stored)
                            added = added + 1
                        else
                            missing_params = missing_params + 1
                        end
                    elseif usable and H.assign_path(lane, row, stored.path) then
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
    if missing_params > 0 then
        report[#report + 1] = string.format("%d automation clips skipped, their parameter is not on that track", missing_params)
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

function H.draw_guide_popup()
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_guide") then return end
    local track = H.guide_track()
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "MIDI chord guide track")
    local current, next_chord = H.guide_at(H.schedule_pos() or r.GetCursorPosition())
    if current then r.ImGui_Text(UI.ctx, "Current: " .. current.name) end
    if next_chord then r.ImGui_Text(UI.ctx, "Next: " .. next_chord.name) end
    r.ImGui_Separator(UI.ctx)
    if r.ImGui_MenuItem(UI.ctx, "No guide track", nil, track == nil) then H.set_guide_track(nil) end
    for index = 0, r.CountTracks(0) - 1 do
        local candidate = r.GetTrack(0, index)
        if candidate and not H.is_lane_track(candidate) then
            if r.ImGui_MenuItem(UI.ctx, H.track_name(candidate, "Track"), nil, candidate == track) then
                H.set_guide_track(candidate)
            end
        end
    end
    if track then
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Create/update chord items") then H.create_chord_items() end
        if r.ImGui_MenuItem(UI.ctx, "Remove chord items") then
            local removed = H.remove_chord_items(track, true)
            L.status = "Removed " .. tostring(removed) .. " chord items"
        end
    end
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
            -- The envelope lanes under this one park their anchors here too.
            for _, sub in ipairs(lane.envs or {}) do
                for _, slot in ipairs(sub.slots) do known[slot.guid] = true end
            end
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
    -- Its envelope belongs to the project we just left, and so does the item it
    -- put there; that project sweeps it up when the launcher next opens on it.
    L.autom_edit = nil
    L.env_ranges = nil
    L.guide_events = nil
    L.guide_scan_at = 0
    ChordTimeline.invalidate()
    return true
end

function H.load()
    L.loaded = true
    L.proj = r.EnumProjects(-1, "")
    L.lanes = {}
    L.orphans = {}
    L.guide_guid = nil
    L.guide_events = nil
    L.guide_scan_at = 0
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
        L.guide_guid = H.track_from_guid(data.guide_guid) and data.guide_guid or nil
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
                H.load_slots(lane, stored.slots)
                -- The envelope lanes under this one, each with its own clips.
                -- A lane whose parameter cannot be resolved is still kept: the
                -- plugin may come back, and its clips are the user's work.
                for _, kept in ipairs(stored.envs or {}) do
                    local target = H.read_autom({ target = kept.target }).target
                    local sub = H.env_lane_for(lane, target, true)
                    if sub then
                        if type(kept.name) == "string" and kept.name ~= "" then sub.name = kept.name end
                        sub.follow_parent = kept.follow_parent ~= false
                        sub.paused = kept.paused == true
                        H.load_slots(sub, kept.slots)
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
    H.sweep_stray_autom()
    -- If a previous session was interrupted mid takeover, give the arrangement
    -- its mute states back before anything else happens.
    H.repair_restore_state()
end

-- One holder's clips, read back off what H.saved_slots wrote. A clip whose
-- library item is not in the project any more is dropped here rather than
-- carried as a slot pointing at nothing.
function H.load_slots(holder, stored_slots)
    for _, slot in ipairs(stored_slots or {}) do
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
            holder.slots[#holder.slots + 1] = {
                row = math.floor(tonumber(slot.row) or 1),
                guid = slot.guid,
                name = slot.name or "Clip",
                is_midi = slot.is_midi and true or false,
                length = tonumber(slot.length) or 0,
                loop = slot.loop ~= false,
                loop_len = tonumber(slot.loop_len),
                tempo_matched = slot.tempo_matched and true or nil,
                speed = tonumber(slot.speed),
                launch_mode = slot.launch_mode,
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
                chord_follow = slot.chord_follow == "root" and "root"
                    or (slot.chord_follow == "scale" and "scale" or nil),
                kind = slot.kind == "automation" and "automation" or nil,
                autom = slot.kind == "automation" and H.read_autom(slot.autom) or nil,
            }
        end
    end
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

-- Opened unless this very lane is being held right now. Cheap: it does nothing
-- at all on a lane that has no gate, which is nearly all of them.
function H.open_gate_for(lane)
    if not lane then return end
    local held = L.gate_held
    if held and held.holder == lane then return end
    if not H.lane_gate(lane, false) then return end
    H.set_lane_gate(lane, true)
end
-- Holding a clip open. The timeline voice runs on as usual - it has to, it is
-- already written - and the gate is what you actually hear stop. Closing it and
-- stopping the lane are two separate things: one is immediate, the other lands
-- on the next bar line and tidies up.
function H.gate_press(lane, lane_index, row)
    local held = L.gate_held
    if held and (held.holder ~= lane or held.row ~= row) then H.gate_release() end
    L.gate_held = { holder = lane, lane = lane_index, row = row }
    -- An automation lane has no audio to shut. Its door is the automation item
    -- itself, which is cut off where the finger let go, so the gate effect is
    -- only for the lanes that carry sound.
    if not H.is_env_lane(lane) then H.set_lane_gate(lane, true) end
    if not H.slot_is_live(lane, row) then H.launch(lane, row) end
end

function H.gate_release()
    local held = L.gate_held
    if not held then return end
    L.gate_held = nil
    local lane = held.holder or L.lanes[held.lane]
    if not lane then return end
    if not H.is_env_lane(lane) then H.set_lane_gate(lane, false) end
    -- Ended where the finger let go, in heard time. Not the scheduling
    -- position: that runs ahead by the output latency, so it would keep a
    -- sliver more than was played - and a voice whose bar line has not arrived
    -- yet lies entirely beyond it, which closing throws away outright. So a tap
    -- before the bar line cancels the launch instead of playing a moment of it.
    -- For a clip the gate has already silenced the sound, so this trim is not
    -- heard. For a curve there is nothing to silence: the automation item ends
    -- here, the block already rendered keeps whatever it had, and the parameter
    -- is back on the track's own envelope from the next one.
    H.stop_lane(lane, H.heard_pos())
end

-- The release is watched here as well as in the cell. A cell scrolled out of
-- view is not drawn, and a mouse let go over another window is not the cell's to
-- notice - either way the sound must stop.
function H.watch_gate()
    if not L.gate_held then return end
    if L.gate_held.midi then return end
    if r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(UI.ctx, 0) then return end
    H.gate_release()
end
-- What a click on a clip that is already going should do. Stopping is the
-- default because that is what a second click means everywhere else; restarting
-- is kept as a choice because retriggering a clip on the beat is a gesture of
-- its own, and Ableton makes it the default for the same reason.
function H.slot_is_live(lane, row)
    if lane.pending and lane.pending.row == row then return "pending" end
    if lane.current and lane.current.row == row and not lane.current.closing then
        return "playing"
    end
    return nil
end

-- A click on a clip, whatever state it is in.
function H.click_slot(lane, lane_index, row, slot)
    local live = H.slot_is_live(lane, row)
    if live == "pending" then
        -- Waiting for its bar line and clicked again: take the queue back rather
        -- than stop a lane that may still be playing something else.
        H.cancel_pending(lane)
        L.status = (slot.name or "Clip") .. " no longer queued"
        return
    end
    if live == "playing" and (slot.launch_mode or "toggle") ~= "restart" then
        H.stop_lane(lane)
        return
    end
    if H.is_env_lane(lane) and lane.paused then
        lane.paused = false
        H.save()
    end
    H.launch(lane, row)
end
-- A blank MIDI clip to draw into, the way a session view makes one from an
-- empty slot. Its length follows the scene it lands in, so a grid stays square;
-- an empty scene falls back to a single bar.
function H.new_midi_clip(lane, lane_index, row, bars)
    local track = H.ensure_lane_track(lane)
    if not track then
        L.status = "Could not make a lane track for this clip"
        return false
    end
    if not r.CreateNewMIDIItemInProj then
        L.status = "This REAPER cannot create MIDI items"
        return false
    end
    local position = r.GetCursorPosition() or 0
    -- Given a number of bars, or left to follow the scene it lands in. Ableton
    -- makes every new clip one bar and lets you drag the loop brace afterwards;
    -- until this launcher can do that dragging, choosing up front matters more.
    local length = H.bars_to_time(position, bars or H.scene_bars(row, position) or 1)
    if not length or length <= 0 then length = 2 end
    r.Undo_BeginBlock()
    local park = H.park_position()
    local blank = r.CreateNewMIDIItemInProj(track, park, park + length, false)
    local made = blank and H.assign_slot(lane, row, blank) or false
    -- The clip is a copy of this one, so the original goes; the same dance the
    -- recorded takes do.
    if H.valid_item(blank) then r.DeleteTrackMediaItem(track, blank) end
    r.Undo_EndBlock("New launcher MIDI clip", -1)
    r.UpdateArrange()
    if not made then
        L.status = "Could not make an empty clip"
        return false
    end
    local slot = H.slot(lane, row)
    if slot then
        slot.name = "MIDI"
        local item = H.item_from_guid(slot.guid)
        local take = item and r.GetActiveTake(item)
        if take then r.GetSetMediaItemTakeInfo_String(take, "P_NAME", slot.name, true) end
    end
    H.save()
    -- Opened straight away: an empty clip is only useful once there is
    -- something in it, and that is the next thing anyone would do.
    H.edit_slot_midi(lane, row)
    return true
end
function H.slot_context(lane, lane_index, row, slot)
    if not r.ImGui_BeginPopupContextItem(UI.ctx, "##launch_ctx_" .. lane_index .. "_" .. row) then return false end
    local autom = H.autom(slot)
    if slot then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, slot.name)
        if autom then
            r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Automates " .. H.autom_target_label(autom.target))
        end
        local length_text = H.clip_length_text(slot)
        if length_text then
            r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Loops " .. length_text)
        end
        if slot.trim_failed then
            r.ImGui_TextColored(UI.ctx, UI.colors.warning or UI.colors.danger, "Loops the whole source: trimming this clip failed")
        end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Launch") then H.launch(lane, row) end
        if r.ImGui_MenuItem(UI.ctx, "Stop lane") then H.stop_lane(lane) end
        r.ImGui_Separator(UI.ctx)
        -- When it plays. The trigger decides what a click does; the rest decide
        -- what happens once it has started.
        local mode = slot.launch_mode or "toggle"
        if r.ImGui_BeginMenu(UI.ctx, "Trigger: " .. H.launch_mode_label(mode)) then
            for _, entry in ipairs(C.launch_modes) do
                if r.ImGui_MenuItem(UI.ctx, entry.label, nil, mode == entry.key) then
                    slot.launch_mode = entry.key ~= "toggle" and entry.key or nil
                    H.save()
                end
                if r.ImGui_IsItemHovered(UI.ctx) then r.ImGui_SetTooltip(UI.ctx, entry.hint) end
            end
            r.ImGui_EndMenu(UI.ctx)
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
            -- Said here as well as in the toolbar: with follow switched off for
            -- the grid, choosing one of these does nothing at all, and the
            -- toolbar that says so can be folded away.
            H.draw_follow_warning()
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
        if r.ImGui_BeginMenu(UI.ctx, "Retrigger every", not slot.loop and not autom) then
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
        -- What the curve is: where it is drawn, how long it runs, and which
        -- parameter it lands on. A media clip has none of these.
        if autom then
            r.ImGui_Separator(UI.ctx)
            local editing = L.autom_edit ~= nil and L.autom_edit.guid == slot.guid
            -- The way out of drawing sits here as well as in the toolbar: that
            -- bar can be switched off, and this menu is where the clip is.
            if editing then
                if r.ImGui_MenuItem(UI.ctx, "Curve done") then H.finish_autom_edit(true) end
                if r.ImGui_MenuItem(UI.ctx, "Cancel drawing") then H.finish_autom_edit(false) end
            elseif r.ImGui_MenuItem(UI.ctx, "Edit curve...") then
                H.edit_autom(lane, row)
            end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Puts the clip on its envelope at the edit cursor to draw into.\nCurve done takes it back in; Cancel throws it away. Both are here\nand in the toolbar. Making it longer or shorter there makes the\nclip longer or shorter.")
            end
            if r.ImGui_MenuItem(UI.ctx, "Save as automation item...") then
                H.ask_autom_save(lane, row)
            end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Write this curve into REAPER's AutomationItems folder, so it can\nbe dropped on any envelope in any project - and picked up again\nby Load automation item here.")
            end
            local files = H.autom_files()
            if files and r.ImGui_BeginMenu(UI.ctx, "Load automation item") then
                H.draw_autom_file_menu(files, "slot" .. lane_index .. "_" .. row, function(file)
                    H.apply_autom_file(lane, row, file.path, file.name)
                end)
                r.ImGui_EndMenu(UI.ctx)
            end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, "Replace this clip's curve with one of REAPER's own automation\nitems, and take its length with it.")
            end
            local bars = H.autom_bars(slot)
            if r.ImGui_BeginMenu(UI.ctx, "Length: " .. tostring(bars) .. (bars == 1 and " bar" or " bars")) then
                for _, choice in ipairs(C.new_clip_bars) do
                    local text = choice == 1 and "1 bar" or (tostring(choice) .. " bars")
                    if r.ImGui_MenuItem(UI.ctx, text, nil, bars == choice) then
                        H.set_autom_bars(lane, row, choice)
                    end
                end
                r.ImGui_EndMenu(UI.ctx)
            end
            if r.ImGui_BeginMenu(UI.ctx, "Point at") then
                H.draw_autom_target_menu(H.target_track(lane), function(target)
                    H.repoint_autom(lane, row, target)
                end, "point")
                r.ImGui_EndMenu(UI.ctx)
            end
        end
        r.ImGui_Separator(UI.ctx)
        -- How it sounds. Speed and tempo are both the rate it runs at, so they
        -- sit together instead of three groups apart.
        if not autom and r.ImGui_BeginMenu(UI.ctx, "Gain") then
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
        local speed = H.slot_speed(slot)
        if not autom and r.ImGui_BeginMenu(UI.ctx, string.format("Speed: %gx", speed)) then
            for _, value in ipairs(C.speeds) do
                if r.ImGui_MenuItem(UI.ctx, string.format("%gx", value), nil,
                        math.abs(value - speed) < 0.0005) then
                    H.set_slot_speed(lane, row, value)
                end
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        if not autom and (slot.tempo_matched or slot.sectioned or not slot.is_midi) then
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
            local chord_follow = slot.chord_follow or "off"
            local chord_label = chord_follow == "scale" and "Scale degree"
                or (chord_follow == "root" and "Root" or "Off")
            if r.ImGui_BeginMenu(UI.ctx, "Chord follow: " .. chord_label) then
                if r.ImGui_MenuItem(UI.ctx, "Off", nil, chord_follow == "off") then
                    slot.chord_follow = nil
                    H.save()
                end
                if r.ImGui_MenuItem(UI.ctx, "Root", nil, chord_follow == "root") then
                    slot.chord_follow = "root"
                    H.save()
                end
                if r.ImGui_MenuItem(UI.ctx, "Scale degree", nil, chord_follow == "scale", L.key ~= nil) then
                    slot.chord_follow = "scale"
                    H.save()
                end
                r.ImGui_EndMenu(UI.ctx)
            end
        end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Rename...") then H.ask_rename(lane, row) end
        if r.ImGui_MenuItem(UI.ctx, "Colour...") then
            L.colour_target = { lane = lane, row = row }
            L.colour_request = true
        end
        r.ImGui_Separator(UI.ctx)
        -- What is in the slot: opening it, or putting something else there.
        if slot.is_midi and r.ImGui_MenuItem(UI.ctx, "Edit in MIDI editor") then
            H.edit_slot_midi(lane, row)
        end
        if not autom and r.ImGui_MenuItem(UI.ctx, "Replace with selected item") then
            H.assign_from_selection(lane, row)
        end
        if not autom and r.ImGui_MenuItem(UI.ctx, "Replace with file...") then H.pick_file(lane, row) end
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
    elseif H.is_env_lane(lane) then
        -- An empty cell in an envelope lane can only become one thing, and the
        -- parameter is already decided by the lane it sits in.
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, H.lane_label(lane) .. "  |  " .. H.env_lane_label(lane))
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_BeginMenu(UI.ctx, "New automation clip") then
            for _, bars in ipairs(C.new_clip_bars) do
                local label = bars == 1 and "1 bar" or (tostring(bars) .. " bars")
                if r.ImGui_MenuItem(UI.ctx, label) then
                    H.new_autom_clip(lane, row, lane.target, bars)
                end
            end
            r.ImGui_Separator(UI.ctx)
            if r.ImGui_MenuItem(UI.ctx, "As long as this scene") then
                H.new_autom_clip(lane, row, lane.target, nil)
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        local files = H.autom_files()
        if files and r.ImGui_BeginMenu(UI.ctx, "From an automation item") then
            H.draw_autom_file_menu(files, "envcell", function(file)
                H.new_autom_from_file(lane, row, lane.target, file.path, file.name)
            end)
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "REAPER's own automation items, from the AutomationItems folder\nin the resource path and everything under it. The file says how\nlong it is, so the clip arrives at that many bars.")
        end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Remove this automation lane and its clips") then
            H.remove_env_lane(lane)
        end
    else
        if H.slot_mark(lane_index, row) then
            if r.ImGui_MenuItem(UI.ctx, "Cancel recording into this slot") then
                H.cancel_slot_record(lane_index, row)
            end
            r.ImGui_Separator(UI.ctx)
        end
        if r.ImGui_MenuItem(UI.ctx, "Add selected item(s) here") then H.assign_from_selection(lane, row) end
        if r.ImGui_MenuItem(UI.ctx, "Add file...") then H.pick_file(lane, row) end
        if r.ImGui_BeginMenu(UI.ctx, "New empty MIDI clip") then
            for _, bars in ipairs(C.new_clip_bars) do
                local label = bars == 1 and "1 bar" or (tostring(bars) .. " bars")
                if r.ImGui_MenuItem(UI.ctx, label) then
                    H.new_midi_clip(lane, lane_index, row, bars)
                end
            end
            r.ImGui_Separator(UI.ctx)
            if r.ImGui_MenuItem(UI.ctx, "As long as this scene") then
                H.new_midi_clip(lane, lane_index, row)
            end
            r.ImGui_EndMenu(UI.ctx)
        end
        if H.autom_ready() and r.ImGui_BeginMenu(UI.ctx, "New automation clip") then
            H.draw_new_autom_menu(lane, row)
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "A clip that is a curve rather than a sound. Launching it puts an\nautomation item on that parameter's envelope, on the same bar line\neverything else lands on; stopping the lane takes it away again.")
        end
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
    local size = UI.scaled(5)
    local right = x + width - UI.scaled(7)
    local top = y + UI.scaled(7)
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
        local bar = UI.scaled(2)
        r.ImGui_DrawList_AddRectFilled(draw_list, right - size, top - size * 0.4,
            right + size, top - size * 0.4 + bar, ink)
        r.ImGui_DrawList_AddRectFilled(draw_list, right - size, top + size * 0.6,
            right + size, top + size * 0.6 + bar, ink)
    end
end

function H.draw_chord_follow_mark(draw_list, slot, x, y, width, height, background)
    if not slot or not slot.is_midi then return end
    local active = slot.chord_follow == "root" or slot.chord_follow == "scale"
    local badge_width = UI.scaled(28)
    local badge_height = math.min(UI.scaled(18), height - UI.scaled(4))
    if badge_height < UI.scaled(12) then return end
    local badge_right = x + width - UI.scaled(slot.key_applied and 16 or 3)
    local badge_left = badge_right - badge_width
    local badge_top = y + UI.scaled(2)
    local badge_bottom = badge_top + badge_height
    local badge_bg = active and H.mix(background, H.readable_on(background), 0.22)
        or H.mix(background, H.readable_on(background), 0.10)
    local ink = H.readable_on(badge_bg)
    if not active then ink = H.mix(badge_bg, ink, 0.58) end
    r.ImGui_DrawList_AddRectFilled(draw_list, badge_left, badge_top, badge_right, badge_bottom,
        badge_bg, UI.scaled(3))
    r.ImGui_DrawList_AddRect(draw_list, badge_left, badge_top, badge_right, badge_bottom,
        active and ink or H.mix(badge_bg, ink, 0.38), UI.scaled(3), 0, UI.scaled(active and 1.5 or 1))
    local size = badge_height * 0.34
    local center_y = (badge_top + badge_bottom) * 0.5
    local chord_x = badge_left + badge_width * 0.31
    local radius = math.max(UI.scaled(1.2), size * 0.22)
    local left_x, left_y = chord_x - size * 0.55, center_y + size * 0.55
    local top_x, top_y = chord_x, center_y - size * 0.55
    local lower_x, lower_y = chord_x + size * 0.55, center_y + size * 0.55
    local stroke = UI.scaled(1.6)
    r.ImGui_DrawList_AddLine(draw_list, left_x, left_y, top_x, top_y, ink, stroke)
    r.ImGui_DrawList_AddLine(draw_list, top_x, top_y, lower_x, lower_y, ink, stroke)
    r.ImGui_DrawList_AddLine(draw_list, lower_x, lower_y, left_x, left_y, ink, stroke)
    r.ImGui_DrawList_AddCircleFilled(draw_list, left_x, left_y, radius, ink)
    r.ImGui_DrawList_AddCircleFilled(draw_list, top_x, top_y, radius, ink)
    r.ImGui_DrawList_AddCircleFilled(draw_list, lower_x, lower_y, radius, ink)
    if slot.chord_follow == "root" then
        local arrow_x = badge_left + badge_width * 0.70
        r.ImGui_DrawList_AddLine(draw_list, arrow_x - size * 0.5, center_y,
            arrow_x + size * 0.25, center_y, ink, UI.scaled(2))
        r.ImGui_DrawList_AddTriangleFilled(draw_list, arrow_x + size * 0.1, center_y - size * 0.45,
            arrow_x + size * 0.1, center_y + size * 0.45, arrow_x + size * 0.75, center_y, ink)
    elseif slot.chord_follow == "scale" then
        local bar_x = badge_left + badge_width * 0.61
        local bar_right = badge_right - UI.scaled(4)
        r.ImGui_DrawList_AddLine(draw_list, bar_x, center_y - size * 0.3,
            bar_right, center_y - size * 0.3, ink, UI.scaled(2))
        r.ImGui_DrawList_AddLine(draw_list, bar_x, center_y + size * 0.3,
            bar_right, center_y + size * 0.3, ink, UI.scaled(2))
    else
        local cross_x = badge_left + badge_width * 0.72
        r.ImGui_DrawList_AddLine(draw_list, cross_x - size * 0.55, center_y - size * 0.55,
            cross_x + size * 0.55, center_y + size * 0.55, ink, UI.scaled(2))
        r.ImGui_DrawList_AddLine(draw_list, cross_x - size * 0.55, center_y + size * 0.55,
            cross_x + size * 0.55, center_y - size * 0.55, ink, UI.scaled(2))
    end
end

function H.draw_cell(lane, lane_index, row, box_height, box_width)
    local width = box_width or UI.rounded(C.cell_w)
    local height = box_height or H.cell_height()
    local env_lane = H.is_env_lane(lane)
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
    -- The clip whose curve is out in the arrange being drawn into, blinking so
    -- it is clear which cell the automation item in front of you belongs to.
    local drawing = slot ~= nil and L.autom_edit ~= nil and L.autom_edit.guid == slot.guid
    if drawing and blink then border = UI.colors.accent end
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

    local record_dot = false
    if not slot then
        -- A record ring in every empty slot of an armed track, the way a session
        -- view shows one. Hit-tested by hand like the badges in a header: the
        -- cell is one item and its click already means something else.
        local mark = not env_lane and H.slot_mark(lane_index, row) or nil
        if not env_lane and (mark or H.track_armed(H.target_track(lane))) then
            local radius = math.min(UI.scaled(7), math.min(width, height) * 0.22)
            local dot_x, dot_y = x + width * 0.5, y + height * 0.5
            record_dot = r.ImGui_IsMouseHoveringRect
                and r.ImGui_IsMouseHoveringRect(UI.ctx, dot_x - radius - UI.scaled(3),
                    dot_y - radius - UI.scaled(3), dot_x + radius + UI.scaled(3), dot_y + radius + UI.scaled(3))
            local waiting = mark and not mark.to
            local ink = UI.colors.danger
            if not mark then ink = record_dot and UI.colors.danger or H.mix(background, UI.colors.danger, 0.55) end
            if waiting and blink then ink = H.mix(ink, 0xFFFFFFFF, 0.45) end
            -- Hollow and blinking while the count-in runs, solid once the take
            -- is actually being written, so the two states cannot be confused.
            local counting_in = mark and not mark.to and L.rec_arm and mark.from == L.rec_arm
            if mark and not counting_in then
                r.ImGui_DrawList_AddCircleFilled(draw_list, dot_x, dot_y, radius, ink)
            else
                r.ImGui_DrawList_AddCircle(draw_list, dot_x, dot_y, radius, ink, 0, UI.scaled(1.6))
            end
            if record_dot then
                local counting = mark and not mark.to and L.rec_arm and mark.from == L.rec_arm
                local says
                if counting then
                    says = "Counting in  |  the take starts on the next bar"
                elseif waiting then
                    says = "Recording  |  click again to stop on the nearest bar"
                elseif mark then
                    says = "Finishing  |  the clip lands in a moment"
                else
                    says = "Record into this slot  |  starts on the next bar"
                end
                r.ImGui_SetTooltip(UI.ctx, says)
            end
        elseif hovered then
            H.text_centered(draw_list, x + width * 0.5, y + height * 0.5, UI.colors.text_dim, "+")
        end
    else
        -- The play position bar owns a strip along the bottom, so nothing else
        -- is laid out into it and the name cannot be struck through.
        local _, text_height = r.ImGui_CalcTextSize(UI.ctx, "A")
        local bar_strip = height >= text_height + UI.scaled(12) and UI.scaled(8) or 0
        local label_y = math.floor(y + math.max(UI.scaled(1), (height - bar_strip - text_height) * 0.5) + 0.5)
        if L.big_cells then
            -- Waveform on top, name underneath, the same reading order as the
            -- cards in the Items view.
            local pad = UI.scaled(4)
            label_y = math.max(y + UI.scaled(1), y + height - bar_strip - text_height - UI.scaled(2))
            local preview_height = (label_y - UI.scaled(4)) - (y + pad)
            if visible and H.autom(slot) then
                if preview_height > UI.scaled(8) then
                    H.draw_autom_curve(draw_list, slot, x + pad, y + pad, width - pad * 2,
                        preview_height, H.readable_on(background))
                end
            elseif visible and UI.preview then
                if preview_height > UI.scaled(8) then
                    UI.preview(draw_list, H.slot_entry(slot, color), x + pad, y + pad, width - pad * 2, preview_height)
                end
            end
            if label_y - UI.scaled(3) > y then
                r.ImGui_DrawList_AddLine(draw_list, x + UI.scaled(4), label_y - UI.scaled(3), x + width - UI.scaled(4), label_y - UI.scaled(3), UI.colors.border, UI.scaled(1))
            end
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
            local midi_y = math.min(y + UI.scaled(15), y + height - UI.scaled(5))
            r.ImGui_DrawList_AddRectFilled(draw_list, x + width - UI.scaled(9), midi_y, x + width - UI.scaled(5), midi_y + UI.scaled(4), UI.colors.accent_soft)
        end
        -- A small rising line in the corner of a flat cell, where a big one
        -- draws the whole curve: an automation clip has no waveform to tell it
        -- apart from a media one.
        if H.autom(slot) and not L.big_cells then
            local mark_y = math.min(y + UI.scaled(15), y + height - UI.scaled(5))
            r.ImGui_DrawList_AddLine(draw_list, x + width - UI.scaled(11), mark_y + UI.scaled(4),
                x + width - UI.scaled(5), mark_y, UI.colors.accent_soft, UI.scaled(1.5))
        end
        H.draw_key_mark(draw_list, slot, x, y, width, background)
        H.draw_chord_follow_mark(draw_list, slot, x, y, width, height, background)
        local running = playing and (H.valid_item(lane.current.item)
            or (lane.current.ai ~= nil and H.autom_index(lane.current.ai) ~= nil))
        if running and height >= text_height + UI.scaled(10) and H.slot_loop(slot) > 0 then
            local heard = H.heard_pos()
            local start = lane.current.ai and H.autom_start(lane.current.ai)
                or r.GetMediaItemInfo_Value(lane.current.item, "D_POSITION")
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
    -- A gate clip answers to the press, not the release, so it is dealt with
    -- before the ordinary click gesture gets a look in.
    if slot and slot.launch_mode == "gate" and not L.alt_down then
        local pressed = r.ImGui_IsItemActivated and r.ImGui_IsItemActivated(UI.ctx)
        if pressed then
            L.cursor.lane, L.cursor.row = lane_index, row
            H.gate_press(lane, lane_index, row)
        end
    end
    if L.alt_down then
        if slot then H.begin_clip_drag(lane, row, slot) end
    elseif r.ImGui_IsItemClicked(UI.ctx, 0) then
        L.cursor.lane, L.cursor.row = lane_index, row
        if slot then
            if slot.launch_mode ~= "gate" then H.click_slot(lane, lane_index, row, slot) end
        elseif record_dot then
            local mark = H.slot_mark(lane_index, row)
            if mark and not mark.to then
                H.slot_record_stop(lane_index, row)
            elseif not mark then
                H.slot_record_start(lane_index, row)
            end
        else
            if env_lane then H.import_selected_autom(lane, row) else H.assign_from_selection(lane, row) end
        end
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
        local autom_note = ""
        if H.autom(slot) then
            local bars = H.autom_bars(slot)
            autom_note = "\nAutomates " .. H.autom_target_label(H.autom(slot).target)
                .. "  |  " .. tostring(bars) .. (bars == 1 and " bar" or " bars")
                .. "\nStarts with the clip in this row above it. Clicked on its own it moves"
                .. "\nonly this lane here, and leaves everything else playing."
        elseif not env_lane then
            -- What this clip will take along, so the link is visible before you
            -- press anything.
            local curves = 0
            for _, sub in ipairs(lane.envs or {}) do
                if H.slot(sub, row) then curves = curves + 1 end
            end
            if curves > 0 then
                autom_note = "\nTakes " .. tostring(curves)
                    .. (curves == 1 and " automation clip" or " automation clips") .. " in this row with it"
            end
        end
        r.ImGui_SetTooltip(UI.ctx, slot.name .. key_hint .. H.key_state_text(slot) .. follow_note .. autom_note
            .. (slot.is_midi and ("\nChord follow: " .. (slot.chord_follow == "scale" and "scale degree"
                or (slot.chord_follow == "root" and "root" or "off"))) or "")
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
    for _, lane in ipairs(H.holders()) do
        if H.slot(lane, row) then filled = true break end
    end
    local background = hovered and UI.colors.card_hover or UI.colors.card_bg
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, background, UI.scaled(4))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, UI.colors.border, UI.scaled(4), 0, UI.scaled(1))
    local label = tostring(row)
    local label_width, label_height = r.ImGui_CalcTextSize(UI.ctx, label)
    -- The play triangle leads, the scene number follows it. Reading order is
    -- what the cell does and then which one it is, and the space it used to
    -- take at the right belongs to the bar count.
    local size = UI.scaled(4)
    local label_x = x + UI.scaled(20)
    if filled then
        local glyph_x = x + UI.scaled(10)
        local glyph_y = y + height * 0.5
        r.ImGui_DrawList_AddTriangleFilled(draw_list, glyph_x - size * 0.6, glyph_y - size, glyph_x - size * 0.6, glyph_y + size, glyph_x + size, glyph_y, UI.colors.accent)
    end
    r.ImGui_DrawList_AddText(draw_list, label_x, math.floor(y + (height - label_height) * 0.5 + 0.5), filled and UI.colors.text or UI.colors.text_dim, label)
    local bars = H.scene_bars(row)
    if bars then
        -- Only drawn when it actually fits beside the row number: a three digit
        -- bar count in a narrow column would otherwise run into it.
        local text = tostring(bars) .. "b"
        local text_width, text_height = r.ImGui_CalcTextSize(UI.ctx, text)
        local text_x = x + width - text_width - UI.scaled(8)
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
                if not option.clips_only
                    and r.ImGui_MenuItem(UI.ctx, option.label, nil, settings.follow == option.key) then
                    settings.follow = option.key
                    H.save()
                end
            end
            H.draw_follow_warning()
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
-- How much room a track takes in the track panel, envelope lanes included.
-- REAPER reports two heights: one of I_TCPH and I_WNDH counts the envelope
-- lanes shown under a track and the other does not. Rather than trust which is
-- which, the taller wins - with no envelopes showing the two are equal and
-- nothing changes.
function H.lane_row_height(lane)
    if not L.lane_track_height then return H.cell_height() end
    local track = H.target_track(lane)
    if not track then return H.cell_height() end
    local height = math.max(r.GetMediaTrackInfo_Value(track, "I_TCPH") or 0,
        r.GetMediaTrackInfo_Value(track, "I_WNDH") or 0)
    if height <= 0 then return H.cell_height() end
    return math.max(UI.rounded(22), math.min(height, UI.rounded(400)))
end
-- The track's own strip, without the envelope lanes underneath it. I_TCPH is
-- the panel without them, I_WNDH the whole thing including them, so the two
-- together say how the row has to be divided.
function H.lane_body_height(lane)
    if not L.lane_track_height then return H.cell_height() end
    local track = H.target_track(lane)
    if not track or #(lane.envs or {}) == 0 then return H.lane_row_height(lane) end
    local panel = r.GetMediaTrackInfo_Value(track, "I_TCPH") or 0
    if panel <= 0 then return H.lane_row_height(lane) end
    return math.max(UI.rounded(22), math.min(panel, UI.rounded(400)))
end

-- What one envelope lane is worth on screen. The space the envelope lanes share
-- is what the track's window height has over its panel height; our lanes split
-- it evenly, which is right whenever they are the envelope lanes on show. A
-- track with envelope lanes of its own as well is the one case this only
-- approximates, and it costs nothing but a row that does not line up exactly.
function H.env_row_height(sub)
    local loose = math.max(UI.rounded(20), math.floor(H.cell_height() * 0.6))
    if not L.lane_track_height then return loose end
    local lane = sub and sub.parent
    local track = lane and H.target_track(lane)
    if not track then return loose end
    local space = (r.GetMediaTrackInfo_Value(track, "I_WNDH") or 0)
        - (r.GetMediaTrackInfo_Value(track, "I_TCPH") or 0)
    local count = #(lane.envs or {})
    if space <= 0 or count < 1 then return loose end
    if not r.BR_EnvAlloc or not r.BR_EnvGetProperties then
        return math.max(UI.rounded(20), math.min(math.floor(space / count), UI.rounded(400)))
    end
    local frame = r.ImGui_GetFrameCount and r.ImGui_GetFrameCount(UI.ctx) or 0
    L.env_height_cache = L.env_height_cache or {}
    local cached = L.env_height_cache[lane]
    if cached and cached.frame == frame and cached.space == space and cached.count == count then
        local height = cached.values[sub]
        return height or loose
    end
    local heights = {}
    local fixed, automatic = 0, 0
    for index, member in ipairs(lane.envs or {}) do
        local height = 0
        local env = H.autom_env(track, member.target, false)
        local handle = env and r.BR_EnvAlloc(env, false) or nil
        if handle then
            local _, visible, _, in_lane, lane_height = r.BR_EnvGetProperties(handle)
            r.BR_EnvFree(handle, false)
            if visible and in_lane and lane_height and lane_height > 0 then height = lane_height end
        end
        heights[index] = height
        if height > 0 then fixed = fixed + height else automatic = automatic + 1 end
    end
    local values = {}
    for candidate, member in ipairs(lane.envs or {}) do
        local height = heights[candidate]
        if automatic > 0 and fixed < space then
            if height <= 0 then height = (space - fixed) / automatic end
        elseif fixed > 0 then
            height = height > 0 and (height * space / fixed) or (space / count)
        else
            height = space / count
        end
        values[member] = math.max(UI.rounded(20), math.min(math.floor(height + 0.5), UI.rounded(400)))
    end
    L.env_height_cache[lane] = { frame = frame, space = space, count = count, values = values }
    return values[sub] or loose
end

function H.lane_draw_height(target)
    if not L.lane_track_height then return target end
    return math.max(UI.rounded(18), target - (L.row_overhead or 0))
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

-- Opened out in the grid's own window, for the same reason the chrome menu is:
-- a popup asked for from inside the table gets an id the grid cannot match.
function H.draw_fx_popup()
    if L.fx_request then
        r.ImGui_OpenPopup(UI.ctx, "##launch_fx")
        L.fx_lane = L.fx_request
        L.fx_request = nil
    end
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_fx") then return end
    local lane = L.lanes[L.fx_lane or 0]
    local track = lane and H.target_track(lane)
    if track then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, H.lane_label(lane))
        r.ImGui_Separator(UI.ctx)
        if H.draw_fx_current(track) then r.ImGui_Separator(UI.ctx) end
        H.draw_fx_menu(track)
    end
    r.ImGui_EndPopup(UI.ctx)
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
        y = y + H.lane_draw_height(H.lane_body_height(lane)) + (L.row_overhead or 0)
        -- The envelope lanes underneath take their own rows, and the arrange
        -- they are lined up with counts them too.
        for _, sub in ipairs(lane.envs or {}) do
            y = y + H.lane_draw_height(H.env_row_height(sub)) + (L.row_overhead or 0)
        end
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

-- Is the grid making any sound, or about to. Used to say whether the corner's
-- stop square has anything to stop.
function H.anything_playing()
    for _, lane in ipairs(H.holders()) do
        if lane.current or lane.pending or lane.queued then return true end
    end
    return false
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
    -- A stop square in the corner, beside the bar count. The toolbar has one
    -- too, but that bar can be folded away and this readout cannot: wherever
    -- you can see where the song is, you can stop it.
    local stop_box = UI.rounded(15)
    local over_stop = false
    local stop_room = width >= stop_box + UI.rounded(52)
    local reserve = stop_room and (stop_box + UI.scaled(6)) or 0
    local centre = x + (width - reserve) * 0.5
    if line_height * 2 + UI.scaled(2) <= band then
        H.text_centered(draw_list, centre, y + band * 0.5 - line_height * 0.55, ink, top)
        H.text_centered(draw_list, centre, y + band * 0.5 + line_height * 0.55,
            UI.colors.text_dim, meter)
    else
        -- One line when two will not fit: the bar is the half you glance at.
        H.text_centered(draw_list, centre, y + band * 0.5, ink, top .. "  " .. meter)
    end
    if stop_room then
        local live = H.anything_playing()
        local bx = math.floor(x + width - UI.scaled(4) - stop_box + 0.5)
        local by = math.floor(y + band * 0.5 - stop_box * 0.5 + 0.5)
        local over = r.ImGui_IsMouseHoveringRect
            and r.ImGui_IsMouseHoveringRect(UI.ctx, bx, by, bx + stop_box, by + stop_box)
        over_stop = over and true or false
        r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + stop_box, by + stop_box,
            over and UI.colors.card_hover or UI.colors.child_bg, UI.scaled(3))
        r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + stop_box, by + stop_box,
            over and UI.colors.accent or UI.colors.border, UI.scaled(3), 0, UI.scaled(1))
        local inset = stop_box * 0.3
        r.ImGui_DrawList_AddRectFilled(draw_list, bx + inset, by + inset,
            bx + stop_box - inset, by + stop_box - inset,
            live and (over and UI.colors.accent or UI.colors.text) or UI.colors.text_dim)
        if over then
            r.ImGui_SetTooltip(UI.ctx, live
                and "Stop everything  |  every lane returns to the arrangement on the next boundary"
                or "Stop everything  |  nothing is playing from the grid")
            if r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(UI.ctx, 0) then
                H.stop_all_quantized()
            end
        end
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
    elseif hovered and not over_stop then
        r.ImGui_SetTooltip(UI.ctx, "Where the song is, and the time signature it is counting in")
    end
end

-- The FX folders TK FX Browser keeps, read straight from its own file so there
-- is no second list to maintain. Derived from where this module sits rather
-- than from a folder name, and read once: the browser's folders do not change
-- while a session runs.
function H.fx_folder_file()
    local here = debug.getinfo(1, "S").source:match("@?(.*[\\/])")
    if not here then return nil end
    -- .../TK Scripts/Media/TK_PROJECT_CLIPS/ -> .../TK Scripts/
    local root = here:match("^(.*[\\/])[^\\/]+[\\/][^\\/]+[\\/]$")
    if not root then return nil end
    return root .. "FX" .. C.sep .. "custom_folders.json"
end

function H.fx_folders()
    if L.fx_folders ~= nil then return L.fx_folders end
    L.fx_folders = false
    local path = H.fx_folder_file()
    if not path then return false end
    local file = io.open(path, "r")
    if not file then return false end
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(UI.json.decode, content)
    if not ok or type(data) ~= "table" then return false end
    -- Sorted by key, which is what the numbered prefixes in those names are for.
    local names = {}
    for name in pairs(data) do names[#names + 1] = name end
    if #names == 0 then return false end
    table.sort(names)
    L.fx_folders = { data = data, order = names }
    return L.fx_folders
end

-- The plugin list Sexan's FX Browser Parser builds, which is the same list TK
-- FX Browser and the Workbench racks use. Read rather than rebuilt: working it
-- out from the installed names gives a Developer list full of JSFX suffixes
-- like "12ch" and no Category at all, because REAPER hands neither to a script.
function H.fx_source()
    if L.fx_source ~= nil then return L.fx_source end
    L.fx_source = false
    local path = r.GetResourcePath() .. C.sep .. "Scripts" .. C.sep .. "Sexan_Scripts"
        .. C.sep .. "FX" .. C.sep .. "Sexan_FX_Browser_ParserV7.lua"
    local probe = io.open(path, "r")
    if not probe then return false end
    probe:close()
    if not pcall(dofile, path) then return false end
    if type(ReadFXFile) ~= "function" then return false end
    local ok, plugins, categories = pcall(ReadFXFile)
    if not ok or type(categories) ~= "table" then return false end
    -- The parser hands back its own headings; only these four are of use here.
    local wanted = { ["CATEGORY"] = "category", ["DEVELOPER"] = "developer",
        ["FOLDERS"] = "folders", ["ALL PLUGINS"] = "all" }
    local groups = {}
    for _, category in ipairs(categories) do
        local kind = wanted[tostring(category and category.name or ""):upper()]
        if kind and type(category.list) == "table" then
            local bucket = {}
            for _, entry in ipairs(category.list) do
                local label = tostring(entry and entry.name or "")
                local list = type(entry and entry.fx) == "table" and entry.fx or {}
                if label ~= "" and #list > 0 then
                    bucket[#bucket + 1] = { label = label, plugins = list }
                end
            end
            table.sort(bucket, function(a, b) return a.label:lower() < b.label:lower() end)
            groups[kind] = bucket
        end
    end
    if not next(groups) then return false end
    L.fx_source = { groups = groups, plugins = type(plugins) == "table" and plugins or {} }
    return L.fx_source
end
-- Favourites and recents live in TK FX Browser's own folder, next to the
-- custom folders we already read, so this is the dependency we already have
-- rather than a new one on any single script.
function H.fx_user_list(file)
    local base = H.fx_folder_file()
    if not base then return nil end
    local path = base:gsub("custom_folders%.json$", file)
    local handle = io.open(path, "r")
    if not handle then return nil end
    local names = {}
    for line in handle:lines() do
        local name = line:gsub("^%s+", ""):gsub("%s+$", "")
        if name ~= "" then names[#names + 1] = name end
    end
    handle:close()
    if #names == 0 then return nil end
    return names
end

-- Our own recents, so the list still works for someone without the browser and
-- reflects what was added from here. Merged in front of the shared one.
function H.recent_fx()
    local mine = {}
    for name in (r.GetExtState(C.ext_section, "fx_recent") or ""):gmatch("[^\n]+") do
        if name ~= "" then mine[#mine + 1] = name end
    end
    local seen = {}
    for _, name in ipairs(mine) do seen[name] = true end
    for _, name in ipairs(H.fx_user_list("recent_plugins.txt") or {}) do
        if not seen[name] then mine[#mine + 1] = name seen[name] = true end
    end
    return mine
end

function H.note_recent_fx(name)
    local kept = { name }
    for line in (r.GetExtState(C.ext_section, "fx_recent") or ""):gmatch("[^\n]+") do
        if line ~= "" and line ~= name and #kept < 20 then kept[#kept + 1] = line end
    end
    r.SetExtState(C.ext_section, "fx_recent", table.concat(kept, "\n"), true)
end

-- REAPER's own chain folder, walked once. Nothing else owns these.
function H.fx_chains()
    if L.fx_chains ~= nil then return L.fx_chains end
    L.fx_chains = false
    local root = r.GetResourcePath() .. C.sep .. "FXChains"
    local found = {}
    local function walk(folder, prefix)
        local index = 0
        while true do
            local name = r.EnumerateFiles and r.EnumerateFiles(folder, index)
            if not name then break end
            if name:lower():sub(-9) == ".rfxchain" then
                found[#found + 1] = prefix .. name
            end
            index = index + 1
        end
        index = 0
        while true do
            local name = r.EnumerateSubdirectories and r.EnumerateSubdirectories(folder, index)
            if not name then break end
            walk(folder .. C.sep .. name, prefix .. name .. "/")
            index = index + 1
        end
    end
    walk(root, "")
    if #found == 0 then return false end
    table.sort(found, function(a, b) return a:lower() < b:lower() end)
    L.fx_chains = found
    return found
end

-- A chain is added by its name like any other FX; REAPER wants the bare file
-- name when the path with folders does not take.
function H.add_fx_chain(track, relative)
    if not track or not relative then return end
    r.Undo_BeginBlock()
    local index = r.TrackFX_AddByName(track, relative, false, -1)
    if index < 0 then
        local bare = relative:match("([^/\\]+)$")
        if bare and bare ~= relative then index = r.TrackFX_AddByName(track, bare, false, -1) end
    end
    r.Undo_EndBlock("Add FX chain", -1)
    L.status = index >= 0 and ("Added " .. relative) or ("Could not add " .. relative)
end
function H.add_fx(track, name)
    if not track or not name or name == "" then return end
    r.Undo_BeginBlock()
    local index = r.TrackFX_AddByName(track, name, false, -1)
    r.Undo_EndBlock("Add FX", -1)
    if index and index >= 0 then
        H.note_recent_fx(name)
        L.status = "Added " .. name
        r.TrackFX_Show(track, index, 3)
    else
        L.status = "Could not add " .. name
    end
end

function H.open_fx_chain(track)
    if not track then return end
    r.TrackFX_Show(track, 0, 1)
end

-- What the track already has, so the button answers "what is on here?" as well
-- as "give me another". A click opens that plugin's own floating window, and
-- closes it again if it was the one already showing.
function H.toggle_fx_window(track, index)
    if not track then return end
    local open = r.TrackFX_GetOpen and r.TrackFX_GetOpen(track, index)
    r.TrackFX_Show(track, index, open and 2 or 3)
end

function H.toggle_fx_bypass(track, index)
    if not track then return end
    local enabled = r.TrackFX_GetEnabled(track, index)
    r.TrackFX_SetEnabled(track, index, not enabled)
end

-- The format prefix REAPER puts in front goes: a column of "VST3:" is noise
-- when every line in the list is a plugin already.
function H.fx_short_name(name)
    name = tostring(name or "")
    local rest = name:match("^[%a%d]+:%s+(.+)$")
    return rest or name
end

function H.draw_fx_current(track)
    local count = track and r.TrackFX_GetCount(track) or 0
    if count <= 0 then return false end
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
        "On this track  -  click opens it, right click bypasses")
    for index = 0, count - 1 do
        local _, name = r.TrackFX_GetFXName(track, index, "")
        local enabled = r.TrackFX_GetEnabled(track, index)
        local offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, index)
        local note = offline and "offline" or (not enabled and "bypassed") or nil
        local open = r.TrackFX_GetOpen and r.TrackFX_GetOpen(track, index) or false
        if r.ImGui_MenuItem(UI.ctx, H.fx_short_name(name) .. "##cur" .. index, note, open) then
            H.toggle_fx_window(track, index)
        end
        -- Right click stays inside the popup, so a few can be flipped in one go.
        if r.ImGui_IsItemHovered(UI.ctx) and r.ImGui_IsMouseClicked(UI.ctx, 1) then
            H.toggle_fx_bypass(track, index)
        end
    end
    return true
end

-- One folder and everything under it. Recursive, because the browser's folders
-- nest a few levels deep.
function H.draw_fx_folder(track, node, key)
    local plugins = node.plugins
    if type(plugins) == "table" then
        for index, name in ipairs(plugins) do
            if r.ImGui_MenuItem(UI.ctx, name .. "##fx" .. key .. index) then H.add_fx(track, name) end
        end
    end
    local subfolders = node.subfolders
    if type(subfolders) ~= "table" then return end
    local names = {}
    for name in pairs(subfolders) do names[#names + 1] = name end
    table.sort(names)
    for index, name in ipairs(names) do
        if r.ImGui_BeginMenu(UI.ctx, name .. "##sub" .. key .. index) then
            H.draw_fx_folder(track, subfolders[name], key .. "_" .. index)
            r.ImGui_EndMenu(UI.ctx)
        end
    end
end

-- A plain list of plugins as menu entries.
function H.draw_fx_list(track, names, key)
    for index, name in ipairs(names) do
        if r.ImGui_MenuItem(UI.ctx, tostring(name) .. "##" .. key .. index) then
            H.add_fx(track, tostring(name))
        end
    end
end

function H.draw_fx_group(track, bucket, key)
    for index, entry in ipairs(bucket) do
        if r.ImGui_BeginMenu(UI.ctx, entry.label .. "##" .. key .. index) then
            H.draw_fx_list(track, entry.plugins, key .. index .. "_")
            r.ImGui_EndMenu(UI.ctx)
        end
    end
end

-- Your own folders first, then the parser's four headings in the order the FX
-- browser shows them, then the way out to the chain.
function H.draw_fx_menu(track)
    local mine = H.fx_folders()
    if mine then
        for index, name in ipairs(mine.order) do
            if r.ImGui_BeginMenu(UI.ctx, name .. "##top" .. index) then
                H.draw_fx_folder(track, mine.data[name], tostring(index))
                r.ImGui_EndMenu(UI.ctx)
            end
        end
        r.ImGui_Separator(UI.ctx)
    end
    local quick = {
        { "Favorites", H.fx_user_list("favorite_plugins.txt") },
        { "Recent", H.recent_fx() },
    }
    local shown = false
    for _, entry in ipairs(quick) do
        local names = entry[2]
        if names and #names > 0 then
            shown = true
            if r.ImGui_BeginMenu(UI.ctx, entry[1]) then
                H.draw_fx_list(track, names, entry[1])
                r.ImGui_EndMenu(UI.ctx)
            end
        end
    end
    local chains = H.fx_chains()
    if chains and r.ImGui_BeginMenu(UI.ctx, "FX chains") then
        shown = true
        for index, relative in ipairs(chains) do
            local label = relative:gsub("%.RfxChain$", ""):gsub("%.rfxchain$", "")
            if r.ImGui_MenuItem(UI.ctx, label .. "##chain" .. index) then
                H.add_fx_chain(track, relative)
            end
        end
        r.ImGui_EndMenu(UI.ctx)
    end
    if shown then r.ImGui_Separator(UI.ctx) end
    local source = H.fx_source()
    if source then
        for _, heading in ipairs({ { "Category", "category" }, { "Developer", "developer" },
                { "Folders", "folders" }, { "All plugins", "all" } }) do
            local bucket = source.groups[heading[2]]
            if bucket and #bucket > 0 and r.ImGui_BeginMenu(UI.ctx, heading[1]) then
                H.draw_fx_group(track, bucket, heading[2])
                r.ImGui_EndMenu(UI.ctx)
            end
        end
        r.ImGui_Separator(UI.ctx)
    end
    if r.ImGui_MenuItem(UI.ctx, "Open FX chain...") then H.open_fx_chain(track) end
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

-- The header of an envelope lane. Set back from the track's own header the way
-- the arrange sets an envelope lane back from its track: a dimmer fill, the
-- track's colour only as a stripe, the parameter's name, and a stop square.
-- Everything a lane header carries about audio -- solo, the fader, the FX
-- picker, the arrangement badge -- belongs to the track, not to a curve.
function H.draw_env_header(sub, id, box_width, box_height)
    local width = box_width or UI.rounded(C.cell_w)
    local height = box_height or UI.rounded(C.cell_h)
    local x, y = r.ImGui_GetCursorScreenPos(UI.ctx)
    r.ImGui_InvisibleButton(UI.ctx, "##launch_envhead_" .. id, width, height)
    local hovered = r.ImGui_IsItemHovered(UI.ctx)
    local draw_list = r.ImGui_GetWindowDrawList(UI.ctx)
    local color = H.lane_color(sub)
    local playing = sub.current ~= nil
    local active = playing or sub.pending ~= nil or sub.queued ~= nil
    local background = H.mix(UI.colors.child_bg, color, hovered and 0.24 or 0.13)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, background, UI.scaled(4))
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + UI.scaled(3), y + height,
        H.mix(color, background, 0.35), UI.scaled(4))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height,
        playing and color or UI.colors.border, UI.scaled(4), 0,
        playing and UI.scaled(2) or UI.scaled(1))
    local ink = H.readable_on(background)
    local _, text_height = r.ImGui_CalcTextSize(UI.ctx, "A")
    local mid = math.floor(y + height * 0.5 + 0.5)
    -- The same rising line an automation clip carries in its corner.
    local mark = x + UI.scaled(9)
    r.ImGui_DrawList_AddLine(draw_list, mark, mid + UI.scaled(3), mark + UI.scaled(7), mid - UI.scaled(3),
        H.mix(ink, color, 0.45), UI.scaled(1.5))
    r.ImGui_DrawList_AddText(draw_list, x + UI.scaled(21), math.floor(mid - text_height * 0.5 + 0.5),
        ink, H.truncate(sub.name or H.env_lane_label(sub), width - UI.scaled(50)))

    local box = UI.rounded(14)
    local bx = math.floor(x + width - UI.scaled(6) - box + 0.5)
    local by = math.floor(mid - box * 0.5 + 0.5)
    local over = r.ImGui_IsMouseHoveringRect(UI.ctx, bx, by, bx + box, by + box)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + box, by + box,
        over and UI.colors.card_hover or UI.colors.child_bg, UI.scaled(3))
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + box, by + box,
        over and UI.colors.accent or UI.colors.border, UI.scaled(3), 0, UI.scaled(1))
    local inset = box * 0.3
    if sub.paused and not active then
        local bar_width = math.max(1, UI.scaled(2))
        local gap = UI.scaled(2)
        local center = bx + box * 0.5
        r.ImGui_DrawList_AddRectFilled(draw_list, center - gap - bar_width, by + inset,
            center - gap, by + box - inset, UI.colors.accent)
        r.ImGui_DrawList_AddRectFilled(draw_list, center + gap, by + inset,
            center + gap + bar_width, by + box - inset, UI.colors.accent)
    else
        r.ImGui_DrawList_AddRectFilled(draw_list, bx + inset, by + inset, bx + box - inset, by + box - inset,
            playing and color or UI.colors.text_dim)
    end
    if over then
        r.ImGui_SetTooltip(UI.ctx, active and "Stop this automation lane"
            or (sub.paused and "Resume automatic playback" or "Pause automatic playback"))
        if r.ImGui_IsMouseClicked(UI.ctx, 0) then
            if active then
                H.stop_lane(sub)
            else
                sub.paused = not sub.paused
                H.save()
                L.status = sub.paused and "Automation lane paused" or "Automation lane resumed"
            end
        end
    elseif hovered then
        r.ImGui_SetTooltip(UI.ctx, (sub.name or "Automation") .. "  |  " .. H.lane_label(sub)
            .. "\nAn automation lane: its clips run on this track's envelope while\nthe track's own clip keeps playing.\nRight-click for what it points at."
            .. "\nFollow parent clip: " .. (sub.follow_parent ~= false and "on" or "off")
            .. "\nAutomatic playback: " .. (sub.paused and "paused" or "ready"))
    end
    if r.ImGui_BeginPopupContextItem(UI.ctx, "##launch_envhead_ctx_" .. id) then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, H.lane_label(sub) .. "  |  " .. H.env_lane_label(sub))
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Follow parent clip", nil, sub.follow_parent ~= false) then
            sub.follow_parent = sub.follow_parent == false
            H.save()
        end
        if r.ImGui_MenuItem(UI.ctx, "Stop lane") then H.stop_lane(sub) end
        if r.ImGui_MenuItem(UI.ctx, "Show this envelope in the arrange") then
            H.env_show(H.autom_env(H.target_track(sub), sub.target, true))
        end
        if r.ImGui_BeginMenu(UI.ctx, "Point at") then
            H.draw_autom_target_menu(H.target_track(sub), function(target)
                H.repoint_env_lane(sub, target)
            end, "envhead" .. id)
            r.ImGui_EndMenu(UI.ctx)
        end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Remove this automation lane and its clips") then
            H.remove_env_lane(sub)
        end
        r.ImGui_EndPopup(UI.ctx)
    end
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
        H.truncate(H.lane_label(lane), width - UI.scaled(80)))

    -- The two little squares at the right of a header. Drawn on top of the
    -- header button rather than as widgets of their own, so the header keeps a
    -- single ImGui id and the clicks stay ours to sort out.
    local badge = UI.rounded(16)
    local badge_y = math.floor(y + (top_h - badge) * 0.5 + 0.5)
    -- One drawer for every square in a header, so the rule that decides black
    -- or white text cannot drift apart between them.
    local function draw_badge_at(bx, by, glyph, active, active_bg, tip, on_click)
        local over = r.ImGui_IsMouseHoveringRect(UI.ctx, bx, by, bx + badge, by + badge)
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
        r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + badge, by + badge, bg, UI.scaled(3))
        local edge = over and UI.colors.accent or (tinted and H.mix(background, ink, 0.45) or UI.colors.border)
        r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + badge, by + badge, edge, UI.scaled(3), 0, UI.scaled(1))
        local glyph_ink = active and UI.colors.badge_text or (tinted and H.readable_on(bg) or UI.colors.text_dim)
        local mid_x, mid_y = bx + badge * 0.5, by + badge * 0.5
        if glyph == "stop" then
            -- A square rather than a letter, but the same box and the same ink.
            local half = badge * 0.28
            r.ImGui_DrawList_AddRectFilled(draw_list, mid_x - half, mid_y - half, mid_x + half, mid_y + half, glyph_ink)
        else
            -- Nudged up a pixel. Centring puts the middle of the line box on
            -- the middle of the badge, but a capital has no descender, so its
            -- ink does not fill that box evenly and reads as sitting low.
            -- One number, here, if it ever wants adjusting.
            H.text_centered(draw_list, mid_x, mid_y, glyph_ink, glyph, -UI.scaled(1))
        end
        if over and r.ImGui_IsMouseClicked(UI.ctx, 0) then on_click() end
        if over then r.ImGui_SetTooltip(UI.ctx, tip) end
        return over
    end

    local function draw_badge(right_inset, glyph, active, active_bg, tip, on_click)
        return draw_badge_at(math.floor(x + width - UI.scaled(right_inset) + 0.5), badge_y,
            glyph, active, active_bg, tip, on_click)
    end

    local track_for_fx = H.target_track(lane)
    local silenced = H.lane_silenced(lane)
    local badge_hovered = draw_badge(46, "A", silenced, UI.colors.danger,
        silenced and "This track's arrangement is muted, clips still play\nClick to let the arrangement through"
            or "Mute this track's arrangement, keep its clips audible",
        function() H.toggle_lane_arrangement(lane) end)

    local soloed = H.lane_soloed(lane)
    local solo_hovered = draw_badge(68, "S", soloed, UI.colors.accent,
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
        r.ImGui_DrawList_AddText(draw_list, x + width - UI.scaled(86) - text_width,
            math.floor(y + (top_h - text_height) * 0.5 + 0.5), count_ink, text)
    end

    local stop_hovered = draw_badge(24, "stop", owned, UI.colors.danger,
        owned and "The launcher owns this track  |  click to hand it back"
            or "Stop this lane",
        function() H.stop_lane(lane) end)
    badge_hovered = badge_hovered or stop_hovered
    local on_fader = false
    if strip > 0 then
        local mid = math.floor(y + top_h + strip * 0.5 + 0.5)
        local box = UI.rounded(16)
        local fx_x = math.floor(x + width - UI.scaled(6) - box + 0.5)
        local fx_y = math.floor(mid - box * 0.5 + 0.5)
        on_fader = H.draw_lane_volume(lane, lane_index, x + UI.scaled(6), mid,
            width - UI.scaled(18) - box, background, ink, tinted)
        -- The picker sits beside the fader rather than on the row above: the
        -- name, the solo, the arrangement badge and the stop square already
        -- have that row full.
        local count = track_for_fx and r.TrackFX_GetCount(track_for_fx) or 0
        local over_fx = draw_badge_at(fx_x, fx_y, count > 0 and tostring(count) or "fx",
            false, nil,
            count > 0 and (tostring(count)
                .. " FX on this track  |  click to open one or add  |  right click for the chain")
                or "Add FX  |  right click for the chain",
            function() L.fx_request = lane_index end)
        if over_fx then
            on_fader = true
            if r.ImGui_IsMouseClicked(UI.ctx, 1) then H.open_fx_chain(track_for_fx) end
        end
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
        if r.ImGui_MenuItem(UI.ctx, "Rename lane and track...") then H.ask_lane_name(lane) end
        if r.ImGui_MenuItem(UI.ctx, "Change lane and track colour...") then H.ask_lane_colour(lane) end
        r.ImGui_Separator(UI.ctx)
        if r.ImGui_MenuItem(UI.ctx, "Stop lane") then H.stop_lane(lane) end
        if r.ImGui_MenuItem(UI.ctx, "Mute this track's arrangement", nil, H.lane_silenced(lane)) then
            H.toggle_lane_arrangement(lane)
        end
        local track = H.target_track(lane)
        local at_unity = not track or math.abs((r.GetMediaTrackInfo_Value(track, "D_VOL") or 1) - 1) < 0.0005
        if track and (r.TrackFX_GetCount(track) or 0) > 0
                and r.ImGui_BeginMenu(UI.ctx, "FX on this track") then
            H.draw_fx_current(track)
            r.ImGui_EndMenu(UI.ctx)
        end
        if r.ImGui_BeginMenu(UI.ctx, "Add FX") then
            H.draw_fx_menu(track)
            r.ImGui_EndMenu(UI.ctx)
        end
        -- An empty automation lane, ready to be filled. The other way round -
        -- making a clip and letting it make its lane - is in the cell menus.
        if H.autom_ready() and r.ImGui_BeginMenu(UI.ctx, "Add automation lane") then
            H.draw_autom_target_menu(track, function(target)
                local sub = H.env_lane_for(lane, target, true)
                H.env_show(H.autom_env(track, target, true))
                H.save()
                L.status = sub and ("Automation lane on " .. H.autom_target_label(target)) or ""
            end, "addenv" .. lane_index)
            r.ImGui_EndMenu(UI.ctx)
        end
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
-- the clip gate
--------------------------------------------------------------------------------
-- A voice is written onto the timeline about a second and a half ahead of the
-- play cursor, so letting go of a key cannot stop it there - the audio is
-- already buffered. An effect in the signal path can, because it works on the
-- sound as it passes. This is that effect: carried as text, written into
-- REAPER's own Effects folder the first time a lane needs one.
--
-- It goes on the hidden lane track, before the send that feeds the real track.
-- Not on the TK LAUNCHER folder: lane tracks have their main send off and reach
-- their target through an explicit send, so no audio passes through the folder.
C.gate_file = "TK_Clip_Gate.jsfx"
C.gate_name = "TK Clip Gate"
C.gate_mark = "TK_CLIP_GATE_VERSION:3"
C.gate_source = [==[
desc:TK Clip Gate
// TK_CLIP_GATE_VERSION:3
// Carried by TK Project Clips and written into REAPER's Effects folder when a
// lane first needs one. It does one thing: open or shut. The launcher owns the
// slider; nothing here is meant to be reached for by hand.

slider1:open=1<0,1,1>-Open

@init
gain = 1;
target = 1;
// Five milliseconds: long enough to lose the click, short enough to feel
// immediate under a finger.
ramp = 1 / max(1, srate * 0.005);
// One slot per note per channel, to remember what was let through. Shutting the
// gate has to send a note off for each of them, or the instrument downstream
// holds that note for ever - it never hears the clip stop.
held = 0;
memset(held, 0, 16 * 128);
was_open = 1;

@slider
target = open;

@block
opened = target >= 0.5;
while (midirecv(offs, msg1, msg2, msg3)) (
  status = msg1 & 0xF0;
  chan = msg1 & 0x0F;
  status == 0x90 && msg3 > 0 ? (
    // A note on only passes while the gate is open, and is remembered so it can
    // be turned off again.
    opened ? ( held[chan * 128 + msg2] = 1; midisend(offs, msg1, msg2, msg3); );
  ) : (status == 0x80 || (status == 0x90 && msg3 == 0)) ? (
    // A note off always passes: swallowing one is how notes get stuck.
    held[chan * 128 + msg2] = 0;
    midisend(offs, msg1, msg2, msg3);
  ) : (
    opened ? midisend(offs, msg1, msg2, msg3);
  );
);
was_open && !opened ? (
  // Everything that was let through, turned off by name.
  i = 0;
  loop(16 * 128,
    held[i] ? (
      midisend(0, 0x80 + floor(i / 128), i - floor(i / 128) * 128, 0);
      held[i] = 0;
    );
    i += 1;
  );
  // And then the blunt instrument, on every channel: all notes off, all sound
  // off. The list above can only turn off what it saw, and a note that reached
  // the instrument another way - running status, a channel that was already
  // sounding, a note this effect was added underneath - would hang for ever.
  // Two controllers cost nothing and there is no polite way to leave a note on.
  ch = 0;
  loop(16,
    midisend(0, 0xB0 + ch, 123, 0);
    midisend(0, 0xB0 + ch, 120, 0);
    ch += 1;
  );
);
was_open = opened;

@sample
gain < target ? gain = min(target, gain + ramp) : gain = max(target, gain - ramp);
i = 0;
while (i < num_ch) (
  spl(i) *= gain;
  i += 1;
);
]==]

function H.install_gate()
    if L.gate_installed then return true end
    local path = r.GetResourcePath() .. C.sep .. "Effects" .. C.sep .. C.gate_file
    local existing = io.open(path, "rb")
    if existing then
        local body = existing:read("*a") or ""
        existing:close()
        -- Rewritten only when the version marker has moved on, so a user who
        -- has been poking at it keeps their copy until it actually matters.
        if body:find(C.gate_mark, 1, true) then
            L.gate_installed = true
            return true
        end
    end
    local file = io.open(path, "wb")
    if not file then return false end
    file:write(C.gate_source)
    file:close()
    L.gate_installed = true
    return true
end

-- The gate on a lane, if it has one. Found by name rather than remembered, so
-- deleting it by hand in the FX chain is survivable.
function H.lane_gate(lane, create)
    local track = lane and H.lane_track(lane)
    if not track then return nil end
    for index = 0, (r.TrackFX_GetCount(track) or 0) - 1 do
        local ok, name = r.TrackFX_GetFXName(track, index, "")
        if ok and name and name:find(C.gate_name, 1, true) then return index, track end
    end
    if not create then return nil end
    if not H.install_gate() then return nil end
    local index = r.TrackFX_AddByName(track, C.gate_file, false, -1)
    if index < 0 then index = r.TrackFX_AddByName(track, C.gate_name, false, -1) end
    if index < 0 then return nil end
    return index, track
end

function H.set_lane_gate(lane, open)
    local index, track = H.lane_gate(lane, true)
    if not index then return false end
    r.TrackFX_SetParam(track, index, 0, open and 1 or 0)
    return true
end

-- Whether any clip in this lane asks for one.
function H.lane_wants_gate(lane)
    for _, slot in ipairs(lane.slots or {}) do
        if slot.launch_mode == "gate" then return true end
    end
    return false
end

-- Added where it is wanted and taken away where it is not, the same way the
-- hidden track itself comes and goes. Walked a few times a second, not every
-- frame: it reads every effect on every lane.
function H.sync_lane_gates()
    local now = r.time_precise()
    if L.gate_checked and now - L.gate_checked < 0.5 then return end
    L.gate_checked = now
    for _, lane in ipairs(L.lanes) do
        local wanted = H.lane_wants_gate(lane)
        local index, track = H.lane_gate(lane, false)
        if wanted and not index then
            -- Opened as it arrives. The default is open, but a chain restored
            -- from the project can bring back whatever it was left on.
            if H.lane_gate(lane, true) then H.set_lane_gate(lane, true) end
        elseif index and not wanted then
            r.TrackFX_Delete(track, index)
        elseif index then
            -- A gate left shut by a release that nothing followed. Opening it
            -- here catches whatever the launch path missed.
            local held = L.gate_held
            if not (held and held.holder == lane) then H.set_lane_gate(lane, true) end
        end
    end
end
--------------------------------------------------------------------------------
-- recording into a slot
--------------------------------------------------------------------------------
-- Playing a part straight into an empty slot, the way a session view does. What
-- REAPER cannot do is hand a script the audio while it is still being written,
-- so a slot does not fill the moment you stop it: the bars are marked while the
-- transport rolls and every marked slot is cut out of the take once recording
-- stops. One pass can therefore fill several slots across several lanes.

-- The line a recording starts or stops on: always the next one, never the one
-- being stood on. Two reasons it is not H.boundary_after. That one may return
-- the current line, which would start the take under your fingers instead of
-- giving you the bar you asked for; and it adds the media buffer lead, which a
-- clip needs because it is written ahead of the play cursor, while a recording
-- is written behind it and needs none. With the lead in, clicking shortly
-- before a line would silently cost you a whole extra bar.
function H.record_boundary(from_time)
    local index = H.grid_index(from_time)
    if not index then return from_time end
    return H.grid_time(from_time, math.floor(index) + 1)
end
-- Editing a clip's notes without going looking for the lane track it lives on.
-- Opening the editor is a REAPER action, and an action will not touch an item
-- on a track it cannot see, so the lane is shown for as long as the editor is
-- open and hidden again the moment it closes. Hiding it straight away would
-- risk taking the editor down with it.
function H.edit_slot_midi(lane, row)
    local slot = H.slot(lane, row)
    local item = slot and H.item_from_guid(slot.guid)
    if not item then
        L.status = "That clip is not in the project any more"
        return
    end
    local track = r.GetMediaItemTrack(item)
    local hidden = track and (r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") or 0) < 0.5
    if hidden then
        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
        r.TrackList_AdjustWindows(false)
    end
    local kept = L.midi_edit and L.midi_edit.selected or {}
    local hidden_tracks = L.midi_edit and L.midi_edit.hidden_tracks or {}
    if hidden then
        local known = false
        for _, hidden_track in ipairs(hidden_tracks) do
            if hidden_track == track then known = true break end
        end
        if not known then hidden_tracks[#hidden_tracks + 1] = track end
    end
    if not L.midi_edit then
        for index = 0, r.CountSelectedMediaItems(0) - 1 do
            kept[#kept + 1] = r.GetSelectedMediaItem(0, index)
        end
    end
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    -- Item: Open in built-in MIDI editor
    r.Main_OnCommand(40153, 0)
    L.midi_edit = { hidden_tracks = hidden_tracks, selected = kept }
    L.status = "Editing " .. (slot.name or "clip")
end

-- The lane goes back into hiding once the editor is gone. Watched rather than
-- hooked, the same as the transport: nothing tells a script the window closed.
function H.watch_midi_editor()
    local watching = L.midi_edit
    if not watching then return end
    if r.MIDIEditor_GetActive and r.MIDIEditor_GetActive() then return end
    local tracks_hidden = false
    for _, track in ipairs(watching.hidden_tracks or {}) do
        if H.valid_track(track) then
            r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
            tracks_hidden = true
        end
    end
    if tracks_hidden then r.TrackList_AdjustWindows(false) end
    r.SelectAllMediaItems(0, false)
    for _, previous in ipairs(watching.selected or {}) do
        if H.valid_item(previous) then r.SetMediaItemSelected(previous, true) end
    end
    L.midi_edit = nil
end
-- Where a recording ends: the nearest line, not the next one. Stopping is a
-- reaction, so the click lands a moment after the bar you meant to be your
-- last. Always rounding forward then hands you that whole next bar, empty. In
-- the first half of a bar the line just passed is meant; in the second half the
-- bar being played is.
function H.record_stop_boundary(from_time)
    local index = H.grid_index(from_time)
    if not index then return from_time end
    return H.grid_time(from_time, math.floor(index + 0.5))
end
function H.track_armed(track)
    if not track then return false end
    return (r.GetMediaTrackInfo_Value(track, "I_RECARM") or 0) > 0.5
end

function H.slot_mark(lane_index, row)
    for _, mark in ipairs(L.slot_rec or {}) do
        if mark.lane == lane_index and mark.row == row then return mark end
    end
    return nil
end

function H.lane_recording(lane_index)
    for _, mark in ipairs(L.slot_rec or {}) do
        if mark.lane == lane_index and not mark.to then return mark end
    end
    return nil
end


-- REAPER's transport, as actions. Named here because they are the one place
-- this feature reaches out and moves the transport.
C.record_action = 1013
C.play_action = 1007

-- One button does the lot, the way a session view works: this marks the bar the
-- take begins on, gets the transport rolling, and punches in when that bar
-- arrives. Recording is not started on the click itself - that would give you
-- no run-up at all, which is the whole point of a launch quantize.
function H.slot_record_start(lane_index, row)
    local lane = L.lanes[lane_index]
    local track = lane and H.target_track(lane)
    if not track then return false end
    if not H.track_armed(track) then
        L.status = "Arm " .. H.lane_label(lane) .. " in REAPER first"
        return false
    end
    local recording = (r.GetPlayState() & 4) == 4
    local playing = (r.GetPlayState() & 1) == 1
    if not playing then r.Main_OnCommand(C.play_action, 0) end
    -- One lane records one thing at a time; a second slot closes the first.
    local running = H.lane_recording(lane_index)
    local now = playing and H.schedule_pos() or r.GetCursorPosition()
    local at = now and H.record_boundary(now) or nil
    -- A lane handing over to another slot ends where the new one begins, so the
    -- two meet on the line with no gap and no overlap.
    if running then running.to = at end
    if not recording then L.rec_arm = at end
    L.slot_rec = L.slot_rec or {}
    L.slot_rec[#L.slot_rec + 1] = { lane = lane_index, row = row, from = at, track = track }
    L.status = at and ("Recording into " .. H.lane_label(lane) .. " from the next bar")
        or ("Recording into " .. H.lane_label(lane))
    return true
end

-- Punched in a hair before the line rather than on it: REAPER takes a moment to
-- open the file, and the clip is cut to the line afterwards anyway, so a little
-- extra in front of it costs nothing while a little missing would.
function H.punch_in_when_due()
    if not L.rec_arm then return end
    if (r.GetPlayState() & 4) == 4 then L.rec_arm = nil return end
    local now = H.schedule_pos()
    if not now then return end
    if now >= L.rec_arm - 0.05 then
        r.Main_OnCommand(C.record_action, 0)
        L.rec_arm = nil
    end
end
function H.slot_record_stop(lane_index, row)
    local mark = row and H.slot_mark(lane_index, row) or H.lane_recording(lane_index)
    if not mark or mark.to then return false end
    local now = H.schedule_pos()
    -- Never before it began; a stop that early leaves nothing, and the harvest
    -- drops it as empty rather than making a clip of no length.
    local at = now and H.record_stop_boundary(now) or mark.from
    mark.to = math.max(at, mark.from or at)
    return true
end

-- A mark that never reached its own start line has nothing in it.
function H.drop_empty_marks(until_time)
    local kept = {}
    for _, mark in ipairs(L.slot_rec or {}) do
        local ends = mark.to or until_time
        if mark.from and ends and ends - mark.from > 0.05 and mark.from < until_time then
            kept[#kept + 1] = mark
        end
    end
    L.slot_rec = kept
    return kept
end

-- The take recording left behind, and how much of the marked stretch it really
-- holds. Overlap rather than containment: a take can begin a few milliseconds
-- after the bar line it was aimed at, and demanding that it cover the mark
-- exactly threw away good recordings over a rounding.
function H.recorded_item(track, from, to)
    local best, best_overlap, best_from, best_to
    for index = 0, (r.CountTrackMediaItems(track) or 0) - 1 do
        local item = r.GetTrackMediaItem(track, index)
        local at = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
        local finish = at + (r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0)
        local low, high = math.max(at, from), math.min(finish, to)
        local overlap = high - low
        if overlap > 0.05 and (not best_overlap or overlap > best_overlap) then
            best, best_overlap, best_from, best_to = item, overlap, low, high
        end
    end
    return best, best_from, best_to
end

-- Taking a mark back before the take is cut up. Nothing recorded is lost by
-- this: the take on the track keeps whatever was played.
function H.cancel_slot_record(lane_index, row)
    local kept = {}
    for _, mark in ipairs(L.slot_rec or {}) do
        if not (mark.lane == lane_index and mark.row == row) then kept[#kept + 1] = mark end
    end
    L.slot_rec = kept
    L.status = "Recording mark removed"
end
function H.harvest_slot_records()
    local marks = L.slot_rec or {}
    if #marks == 0 then return 0 end
    -- Only what actually came back is struck off; the rest stays for another
    -- try, since the reason for a miss is usually that REAPER has not finished
    -- writing the file yet.
    local taken, missed, left = 0, 0, {}
    -- Which takes were used up and which must stay. One take can feed several
    -- slots, so it is only cleared away once every slot that wanted it has had
    -- it - and never while one of them still has to try again.
    local used, spare = {}, {}
    r.Undo_BeginBlock()
    -- Deliberately not wrapped in PreventUIRefresh. Trimming a MIDI clip has to
    -- show the hidden lane track for a moment, because a REAPER action will not
    -- touch an item on a track it cannot see - and that showing does not take
    -- effect while refreshing is held off, so the trim would fail every time.
    -- This runs once, after recording, so the flicker costs nothing.
    for _, mark in ipairs(marks) do
        local lane = L.lanes[mark.lane]
        local source, have_from, have_to
        if lane and H.valid_track(mark.track) then
            source, have_from, have_to = H.recorded_item(mark.track, mark.from, mark.to)
        end
        if not lane then
            L.rec_why = "that lane is gone"
        elseif not H.valid_track(mark.track) then
            L.rec_why = "that track is gone"
        elseif not source then
            L.rec_why = string.format("no take on %s covering %.2f to %.2f s",
                H.track_name(mark.track, "track"), mark.from or -1, mark.to or -1)
        end
        if source then
            -- Cut from a copy, so the take the user just played stays whole.
            -- Cut to the part the take really holds, not the part asked for.
            local cut_from = have_from or mark.from
            local cut_to = have_to or mark.to
            local slice = H.copy_item(source, mark.track, cut_from)
            if slice then
                local start = r.GetMediaItemInfo_Value(source, "D_POSITION") or 0
                r.SetMediaItemInfo_Value(slice, "D_POSITION", cut_from)
                r.SetMediaItemInfo_Value(slice, "D_LENGTH", cut_to - cut_from)
                local take = r.GetActiveTake(slice)
                if take then
                    local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1
                    local was = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
                    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", was + (cut_from - start) * rate)
                end
                if H.assign_slot(lane, mark.row, slice) then
                    taken = taken + 1
                    used[source] = mark.track
                else
                    missed = missed + 1
                    left[#left + 1] = mark
                    spare[source] = true
                    L.rec_why = "the take could not be turned into a clip"
                end
                r.DeleteTrackMediaItem(mark.track, slice)
            else
                missed = missed + 1
                left[#left + 1] = mark
                spare[source] = true
                L.rec_why = "the take could not be copied"
            end
        else
            missed = missed + 1
            left[#left + 1] = mark
        end
    end
    -- The take on the track, once every slot has taken its cut. The audio
    -- itself stays on disk; this only clears the item out of the arrangement.
    -- Only once nothing is waiting any more. A mark left over will be tried
    -- again, and it can hardly succeed against a take that has been thrown away.
    local cleared = 0
    if L.record_tidy and #left == 0 then
        for item, track in pairs(used) do
            if not spare[item] and H.valid_item(item) and H.valid_track(track) then
                r.DeleteTrackMediaItem(track, item)
                cleared = cleared + 1
            end
        end
    end
    L.slot_rec = left
    r.Undo_EndBlock("Record launcher clips", -1)
    r.UpdateArrange()
    H.save()
    if taken > 0 then
        L.status = taken == 1 and "Recorded 1 clip"
            or ("Recorded " .. tostring(taken) .. " clips")
        if missed > 0 then L.status = L.status .. ", " .. tostring(missed) .. " had nothing to take" end
        if cleared > 0 then
            L.status = L.status .. ", " .. tostring(cleared)
                .. (cleared == 1 and " take cleared from the arrangement" or " takes cleared from the arrangement")
        end
    elseif missed > 0 then
        L.status = "Nothing was recorded into those slots"
    end
    return taken
end

-- Watched rather than hooked: REAPER tells a script nothing when recording
-- ends, so the state is compared with what it was last time round.
function H.watch_recording()
    local state = r.GetPlayState()
    local recording = (state & 4) == 4
    local was = L.was_recording
    L.was_recording = recording
    if recording then
        -- Every mark closed and its last bar line gone by: nothing more is being
        -- played into the grid, so recording stops itself and the clips appear.
        -- Recording is one thing for the whole project, so this waits for the
        -- last lane rather than punching out on the first.
        local marks = L.slot_rec or {}
        if #marks > 0 then
            local latest, open = nil, false
            for _, mark in ipairs(marks) do
                if not mark.to then open = true break end
                if not latest or mark.to > latest then latest = mark.to end
            end
            local now = H.schedule_pos()
            if not open and latest and now and now >= latest then
                r.Main_OnCommand(C.record_action, 0)
            end
        end
        if not was then
            -- A new take measures itself from scratch.
            L.rec_end = nil
            -- Recording has just begun, so anything armed beforehand starts
            -- here, on the first line at or after this point.
            local began = H.schedule_pos()
            for _, mark in ipairs(L.slot_rec or {}) do
                if not mark.from and began then mark.from = H.record_boundary(began) end
            end
        end
        -- How far the take has got. Kept every frame because once the transport
        -- stops there is nothing left to ask: the play position is gone and the
        -- edit cursor has jumped back to where playback began.
        --
        -- The furthest seen, not the last seen. On the frame the user presses
        -- stop REAPER still reports itself as recording while the play position
        -- has already snapped back to the start, and that one reading would
        -- otherwise wipe out every good one before it. A play position never
        -- runs backwards during a take, so anything that does is that snap.
        local at = H.schedule_pos()
        if at and at > (L.rec_end or 0) then L.rec_end = at end
        L.rec_frames = (L.rec_frames or 0) + 1
        L.rec_state = state
        return
    end
    if was then
        -- Not harvested on the spot: REAPER is still closing the file it wrote,
        -- and the item on the track is not finished until it has.
        L.harvest_at = r.time_precise() + 0.25
        L.harvest_tries = 0
        L.rec_seen = L.rec_frames or 0
        L.rec_frames = 0
    end
    if not L.harvest_at or r.time_precise() < L.harvest_at then return end
    local ended = L.rec_end or 0
    for _, mark in ipairs(L.slot_rec or {}) do
        if mark.from and (not mark.to or mark.to > ended) then mark.to = ended end
    end
    local before = #(L.slot_rec or {})
    L.slot_rec_last = {}
    for index, mark in ipairs(L.slot_rec or {}) do L.slot_rec_last[index] = mark end
    if #H.drop_empty_marks(ended) == 0 then
        L.harvest_at = nil
        if before > 0 then
            local first = (L.slot_rec_last or {})[1] or {}
            L.status = string.format(
                "Nothing recorded: mark %.2f..%.2f, take ran to %.2f s, %d frames of recording seen (state %s)",
                first.from or -1, first.to or -1, ended, L.rec_seen or 0, tostring(L.rec_state))
        end
        return
    end
    if H.harvest_slot_records() > 0 then
        L.harvest_at = nil
        return
    end
    -- Nothing came back yet. A few more tries before giving up, in case the
    -- file is large enough that closing it takes a moment.
    L.harvest_tries = (L.harvest_tries or 0) + 1
    if L.harvest_tries >= 20 then
        L.harvest_at = nil
        -- Dropped rather than left standing. Marks that survive a failure make
        -- the grid look stuck, and get harvested by the next unrelated stop.
        L.slot_rec = {}
        L.status = "Recording not picked up: " .. (L.rec_why or "reason unknown")
    else
        L.harvest_at = r.time_precise() + 0.25
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
    L.record_tidy = r.GetExtState(C.ext_section, "record_tidy") == "1"
    L.scenes_as_columns = r.GetExtState(C.ext_section, "scenes_as_columns") == "1"
    L.lane_track_height = r.GetExtState(C.ext_section, "lane_track_height") == "1"
    L.align_to_arrange = r.GetExtState(C.ext_section, "align_to_arrange") == "1"
    L.chrome = math.max(0, math.min(3, math.floor(tonumber(r.GetExtState(C.ext_section, "chrome")) or 0)))
    local sync = r.GetExtState(C.ext_section, "scroll_sync")
    L.scroll_sync = (sync == "follow" or sync == "both") and sync or "off"
    L.set_show_all = r.GetExtState(C.ext_section, "set_show_all") == "1"
    L.set_create_tracks = r.GetExtState(C.ext_section, "set_create_tracks") == "1"
    L.midi_enabled = r.GetExtState(C.ext_section, "midi_enabled") == "1"
    L.midi_device_name = r.GetExtState(C.ext_section, "midi_device_name") or ""
    L.midi_channel = math.max(0, math.min(16, math.floor(tonumber(r.GetExtState(C.ext_section, "midi_channel")) or 0)))
    L.midi_base_note = math.max(0, math.min(127, math.floor(tonumber(r.GetExtState(C.ext_section, "midi_base_note")) or 36)))
    local midi_layout = r.GetExtState(C.ext_section, "midi_layout")
    L.midi_layout = ({ keyboard = true, pads = true, custom = true, launchpad = true })[midi_layout] and midi_layout or "pads"
    local midi_keyboard_mode = r.GetExtState(C.ext_section, "midi_keyboard_mode")
    L.midi_keyboard_mode = midi_keyboard_mode == "active" and "active" or "octaves"
    local midi_pad_mode = r.GetExtState(C.ext_section, "midi_pad_mode")
    L.midi_pad_mode = midi_pad_mode == "scenes" and "scenes" or "clips"
    L.midi_columns = math.max(1, math.min(16, math.floor(tonumber(r.GetExtState(C.ext_section, "midi_columns")) or 8)))
    L.midi_rows = math.max(1, math.min(16, math.floor(tonumber(r.GetExtState(C.ext_section, "midi_rows")) or 8)))
    local midi_orientation = r.GetExtState(C.ext_section, "midi_orientation")
    L.midi_orientation = midi_orientation == "scenes" and "scenes" or "lanes"
    L.midi_lane_bank = math.max(0, math.floor(tonumber(r.GetExtState(C.ext_section, "midi_lane_bank")) or 0))
    L.midi_scene_bank = math.max(0, math.floor(tonumber(r.GetExtState(C.ext_section, "midi_scene_bank")) or 0))
    L.midi_out_name = r.GetExtState(C.ext_section, "midi_out_name") or ""
    L.midi_feedback = r.GetExtState(C.ext_section, "midi_feedback") == "1"
    local lp_family = r.GetExtState(C.ext_section, "midi_lp_family")
    L.midi_lp_family = ({ mk3 = true, mk2 = true, classic = true })[lp_family] and lp_family or "mk3"
    -- Empty means "whatever the family says", which is the case for everyone
    -- whose device is not wired up in some way of its own.
    L.midi_lp_origin = tonumber(r.GetExtState(C.ext_section, "midi_lp_origin"))
    L.midi_lp_step = tonumber(r.GetExtState(C.ext_section, "midi_lp_step"))
    H.load_midi_commands()
    H.load_midi_presets()
    H.reset_midi_input()
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
        -- The output is looked up by name, so a device plugged in after the
        -- last session still lands on the right index.
        if L.midi_feedback then H.lp_start() end
        if L.mute_song_default and not L.arrangement_muted then
            local now = H.schedule_pos()
            H.set_arrangement_muted(true, now or r.GetCursorPosition())
        end
    else
        H.finish_autom_edit(false)
        H.lp_stop()
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
    H.run_autom_save_prompt()
    H.run_lane_name_prompt()
    H.run_lane_colour_prompt()
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
    H.handle_midi()
    H.watch_gate()
    H.sync_lane_gates()
    H.watch_midi_editor()
    H.watch_autom_edit()
    H.lp_refresh(false)
    H.punch_in_when_due()
    H.watch_recording()
    local now = H.schedule_pos()
    if not now then
        if r.time_precise() >= L.roll_guard then
            -- Nothing is rolling, so anything still scheduled lands right away.
            if L.global_switch then H.apply_global_switch() end
            for _, lane in ipairs(H.holders()) do
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
        for _, lane in ipairs(H.holders()) do H.promote_wrap(lane, heard) end
        H.run_queued(heard)
    end
    L.last_heard = heard
    for _, lane in ipairs(H.holders()) do
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
-- A voice stopped part way through a take. Remembered here and cut out when the
-- take is finished, rather than left to the harvest that comes round later:
-- whether that harvest reaches it before the take ends depends on timing the
-- player has no reason to think about, and when it does not, the clip is simply
-- missing from what was recorded.
function H.remember_stopped_voice(lane, voice, until_time)
    if not L.recording or not voice or not voice.started then return end
    L.stopped_voices = L.stopped_voices or {}
    L.stopped_voices[#L.stopped_voices + 1] = { lane = lane, voice = voice, at = until_time }
end

-- What of a voice was inside the take, copied out and set aside. Bounded twice:
-- by where the voice was stopped and by where the take ends, whichever is
-- earlier. Items the harvest has already taken are gone from the voice by then,
-- so there is nothing here to take twice.
function H.capture_span(lane, voice, until_time)
    local target = H.target_track(lane)
    local lane_track = H.lane_track(lane)
    if not target or not lane_track or not voice or not until_time then return 0 end
    local taken = 0
    local function snapshot(media)
        if not H.valid_item(media) then return end
        local position = r.GetMediaItemInfo_Value(media, "D_POSITION") or 0
        local length = r.GetMediaItemInfo_Value(media, "D_LENGTH") or 0
        local finish = math.min(position + length, until_time)
        if finish - position < 0.01 then return end
        local copy = H.copy_item(media, lane_track, position)
        if not copy then return end
        H.detach_midi_source(copy)
        r.SetMediaItemInfo_Value(copy, "D_LENGTH", finish - position)
        r.SetMediaItemInfo_Value(copy, "B_MUTE", 1)
        r.SetMediaItemInfo_Value(copy, "B_LOOPSRC",
            (r.GetMediaItemInfo_Value(media, "B_LOOPSRC") or 0) > 0.5 and 1 or 0)
        if r.UpdateItemInProject then r.UpdateItemInProject(copy) end
        L.captured[#L.captured + 1] = { item = copy, track = target }
        -- The original stays on the lane track; noting it here keeps the sweep
        -- from taking the same performance a second time.
        L.take_sources = L.take_sources or {}
        L.take_sources[media] = true
        taken = taken + 1
    end
    snapshot(voice.item)
    snapshot(voice.wrap)
    for _, media in ipairs(voice.hits or {}) do snapshot(media) end
    return taken
end
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
        H.detach_midi_source(copy)
        r.SetMediaItemInfo_Value(copy, "D_LENGTH", math.max(0.01, math.min(length, now - position)))
        r.SetMediaItemInfo_Value(copy, "B_MUTE", 1)
        r.SetMediaItemInfo_Value(copy, "B_LOOPSRC", (r.GetMediaItemInfo_Value(media, "B_LOOPSRC") or 0) > 0.5 and 1 or 0)
        if r.UpdateItemInProject then r.UpdateItemInProject(copy) end
        L.captured[#L.captured + 1] = { item = copy, track = target }
        L.take_sources = L.take_sources or {}
        L.take_sources[media] = true
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
    local index = H.grid_index(from)
    if not index then return from end
    return H.grid_time(from, math.floor(index) + 1)
end

-- An item the take has claimed is no longer the launcher's to clean up. The
-- voice that was playing it still points at it, and the next tidy-up would
-- delete it - by then it may already have been moved onto a real track, so the
-- recording would simply vanish. Copied items do not need this; swept ones do,
-- because the take keeps the very item that was playing.
function H.forget_item(item)
    if not item then return end
    local function detach(voice)
        if not voice then return end
        if voice.item == item then voice.item = nil end
        if voice.wrap == item then voice.wrap = nil end
        for index = #(voice.hits or {}), 1, -1 do
            if voice.hits[index] == item then table.remove(voice.hits, index) end
        end
    end
    for _, lane in ipairs(L.lanes) do
        detach(lane.current)
        detach(lane.pending)
        for _, voice in ipairs(lane.retired or {}) do detach(voice) end
    end
end
-- The last word on what a take contains, and the one that cannot be argued
-- with: whatever is sitting on a lane track that is not one of its clips is
-- something the launcher put there to be played. The bookkeeping of voices
-- above is quicker and knows more, but it depends on a chain - closing,
-- harvesting, retiring - and if a link in that chain runs at the wrong moment
-- the clip is silently missing from the take. This looks at the timeline
-- itself.
function H.sweep_take_leftovers(from_time, until_time)
    local already = {}
    for _, entry in ipairs(L.captured) do already[entry.item] = true end
    -- Anything the copying routes already took a copy of. Without this the
    -- performance is captured twice: once as their copy, once as the original
    -- still lying on the lane track.
    for item in pairs(L.take_sources or {}) do already[item] = true end
    local taken = 0
    for _, lane in ipairs(L.lanes) do
        local track = H.lane_track(lane)
        local target = H.target_track(lane)
        if track and target then
            local library = {}
            for _, slot in ipairs(lane.slots or {}) do library[slot.guid] = true end
            for index = 0, (r.CountTrackMediaItems(track) or 0) - 1 do
                local item = r.GetTrackMediaItem(track, index)
                local guid = item and r.BR_GetMediaItemGUID and r.BR_GetMediaItemGUID(item)
                local position = item and (r.GetMediaItemInfo_Value(item, "D_POSITION") or 0)
                local length = item and (r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0)
                -- No window is asked of it. The take's start and end are worked
                -- out from the play cursor, and that cursor moves for reasons of
                -- its own - a loop coming round is enough - so a window can end
                -- up nowhere near where the clips were actually played. An item
                -- on a lane track that is not one of its clips can only be there
                -- because the launcher put it there to sound; that is the whole
                -- test.
                if item and not already[item] and not (guid and library[guid]) then
                    H.detach_midi_source(item)
                    if until_time and position < until_time
                        and position + length > until_time then
                        H.trim_to(item, until_time)
                    end
                    r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
                    L.captured[#L.captured + 1] = { item = item, track = target }
                    H.forget_item(item)
                    already[item] = true
                    taken = taken + 1
                end
            end
        end
    end
    return taken
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
        -- Anything stopped part way through, taken up to wherever it was
        -- stopped or the end of the take, whichever came first.
        for _, entry in ipairs(L.stopped_voices or {}) do
            snapped = snapped + H.capture_span(entry.lane, entry.voice, math.min(entry.at or at, at))
        end
        -- And then the timeline itself, for anything the bookkeeping lost.
        snapped = snapped + H.sweep_take_leftovers(L.record_from, at)
        -- Everything ends on the same line, so the take is a whole number of
        -- bars however the individual clips happened to be running.
        for _, entry in ipairs(L.captured) do
            if H.valid_item(entry.item) then
                local finish = H.item_end(entry.item)
                if finish and finish > at then H.trim_to(entry.item, at) end
            end
        end
        r.PreventUIRefresh(-1)
    else
        -- Stopped with no play position to work from. The timeline still knows
        -- what was put on it.
        snapped = snapped + H.sweep_take_leftovers(nil, nil)
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
    L.stopped_voices, L.take_sources = {}, {}
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
        -- Where the take began, for bounding what it may claim later.
        L.record_from = H.heard_pos()
        L.stopped_voices, L.take_sources = {}, {}
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

function H.midi_preset_path()
    return r.GetResourcePath() .. C.sep .. "Data" .. C.sep .. "TK_PROJECT_CLIPS_MIDI_PRESETS.json"
end

function H.sort_midi_presets()
    table.sort(L.midi_presets, function(left, right)
        return tostring(left.name):lower() < tostring(right.name):lower()
    end)
end

function H.load_midi_presets()
    L.midi_presets = {}
    local file = io.open(H.midi_preset_path(), "r")
    if not file then return end
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(UI.json.decode, content)
    if not ok or type(data) ~= "table" or type(data.presets) ~= "table" then return end
    for _, preset in ipairs(data.presets) do
        if type(preset) == "table" and type(preset.name) == "string" and preset.name ~= "" then
            L.midi_presets[#L.midi_presets + 1] = preset
        end
    end
    H.sort_midi_presets()
end

function H.write_midi_presets()
    local ok, encoded = pcall(UI.json.encode, { version = 1, presets = L.midi_presets })
    if not ok or not encoded then return false end
    local folder = r.GetResourcePath() .. C.sep .. "Data"
    if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(folder, 0) end
    local file = io.open(H.midi_preset_path(), "w")
    if not file then return false end
    file:write(encoded)
    file:close()
    return true
end

function H.midi_preset_snapshot(name)
    local commands = {}
    for _, command in ipairs(MIDI_COMMANDS) do
        local binding = L.midi_commands[command.key]
        if binding then
            commands[command.key] = {
                kind = binding.kind,
                number = binding.number,
                channel = binding.channel,
            }
        end
    end
    return {
        name = name,
        enabled = L.midi_enabled,
        device_name = L.midi_device_name,
        channel = L.midi_channel,
        base_note = L.midi_base_note,
        layout = L.midi_layout,
        keyboard_mode = L.midi_keyboard_mode,
        pad_mode = L.midi_pad_mode,
        columns = L.midi_columns,
        rows = L.midi_rows,
        orientation = L.midi_orientation,
        lane_bank = L.midi_lane_bank,
        scene_bank = L.midi_scene_bank,
        out_name = L.midi_out_name,
        feedback = L.midi_feedback,
        lp_family = L.midi_lp_family,
        lp_origin = L.midi_lp_origin,
        lp_step = L.midi_lp_step,
        commands = commands,
    }
end

function H.save_midi_preset(name)
    name = tostring(name or ""):match("^%s*(.-)%s*$")
    if name == "" then
        L.status = "Enter a MIDI preset name first"
        return
    end
    local replacement = H.midi_preset_snapshot(name)
    local replaced = false
    for index, preset in ipairs(L.midi_presets) do
        if preset.name:lower() == name:lower() then
            L.midi_presets[index] = replacement
            replaced = true
            break
        end
    end
    if not replaced then L.midi_presets[#L.midi_presets + 1] = replacement end
    H.sort_midi_presets()
    if not H.write_midi_presets() then
        L.status = "Could not save MIDI presets"
        return
    end
    L.midi_preset_name = name
    L.midi_preset_selected = name
    L.status = "MIDI preset saved: " .. name
end

function H.apply_midi_preset(preset)
    if type(preset) ~= "table" then return end
    if preset.enabled ~= nil then L.midi_enabled = preset.enabled and true or false end
    if type(preset.device_name) == "string" then L.midi_device_name = preset.device_name end
    L.midi_channel = math.max(0, math.min(16, math.floor(tonumber(preset.channel) or 0)))
    L.midi_layout = ({ keyboard = true, pads = true, custom = true, launchpad = true })[preset.layout] and preset.layout or "pads"
    L.midi_keyboard_mode = preset.keyboard_mode == "active" and "active" or "octaves"
    L.midi_pad_mode = preset.pad_mode == "scenes" and "scenes" or "clips"
    L.midi_columns = math.max(1, math.min(16, math.floor(tonumber(preset.columns) or 8)))
    L.midi_rows = math.max(1, math.min(16, math.floor(tonumber(preset.rows) or 8)))
    L.midi_orientation = preset.orientation == "scenes" and "scenes" or "lanes"
    L.midi_base_note = math.max(0, math.min(H.midi_max_base_note(), math.floor(tonumber(preset.base_note) or 36)))
    L.midi_lane_bank = math.max(0, math.floor(tonumber(preset.lane_bank) or 0))
    L.midi_scene_bank = math.max(0, math.floor(tonumber(preset.scene_bank) or 0))
    H.clamp_midi_banks()
    L.midi_commands = {}
    local seen = {}
    for _, command in ipairs(MIDI_COMMANDS) do
        local binding = type(preset.commands) == "table" and preset.commands[command.key] or nil
        local kind = type(binding) == "table" and binding.kind or nil
        local number = type(binding) == "table" and tonumber(binding.number) or nil
        local channel = type(binding) == "table" and tonumber(binding.channel) or nil
        local signature = kind and number and channel and (kind .. ":" .. tostring(channel) .. ":" .. tostring(number)) or nil
        if (kind == "note" or kind == "cc") and number and number >= 0 and number <= 127
            and channel and channel >= 1 and channel <= 16 and not seen[signature] then
            L.midi_commands[command.key] = { kind = kind, number = math.floor(number), channel = math.floor(channel) }
            seen[signature] = true
        end
    end
    -- The pad lighting travels with a preset too: which output it lit, and how
    -- that device lays its grid out.
    if type(preset.lp_family) == "string" then L.midi_lp_family = preset.lp_family end
    L.midi_lp_origin = tonumber(preset.lp_origin)
    L.midi_lp_step = tonumber(preset.lp_step)
    r.SetExtState(C.ext_section, "midi_lp_family", L.midi_lp_family, true)
    r.SetExtState(C.ext_section, "midi_lp_origin", tostring(L.midi_lp_origin or ""), true)
    r.SetExtState(C.ext_section, "midi_lp_step", tostring(L.midi_lp_step or ""), true)
    H.lp_stop()
    if type(preset.out_name) == "string" then L.midi_out_name = preset.out_name end
    L.midi_feedback = preset.feedback and true or false
    r.SetExtState(C.ext_section, "midi_out_name", L.midi_out_name, true)
    r.SetExtState(C.ext_section, "midi_feedback", L.midi_feedback and "1" or "0", true)
    r.SetExtState(C.ext_section, "midi_enabled", L.midi_enabled and "1" or "0", true)
    r.SetExtState(C.ext_section, "midi_device_name", L.midi_device_name, true)
    r.SetExtState(C.ext_section, "midi_channel", tostring(L.midi_channel), true)
    r.SetExtState(C.ext_section, "midi_base_note", tostring(L.midi_base_note), true)
    H.save_midi_mapping()
    if L.midi_feedback then H.lp_start() end
    for _, command in ipairs(MIDI_COMMANDS) do
        local binding = L.midi_commands[command.key]
        local value = binding and (binding.kind .. ":" .. tostring(binding.number) .. ":" .. tostring(binding.channel)) or ""
        r.SetExtState(C.ext_section, "midi_command_" .. command.key, value, true)
    end
    L.midi_learn = nil
    L.midi_base_learn = false
    L.midi_learn_retval = nil
    L.midi_preset_name = preset.name
    L.midi_preset_selected = preset.name
    H.reset_midi_input()
    L.status = "MIDI preset loaded: " .. preset.name
end

function H.delete_midi_preset(name)
    if not name then return end
    for index, preset in ipairs(L.midi_presets) do
        if preset.name == name then
            table.remove(L.midi_presets, index)
            if not H.write_midi_presets() then
                L.status = "Could not update MIDI presets"
                return
            end
            L.midi_preset_selected = nil
            L.midi_preset_name = ""
            L.status = "MIDI preset deleted: " .. name
            return
        end
    end
end

function H.midi_inputs()
    local inputs = {}
    if not (r.GetNumMIDIInputs and r.GetMIDIInputName) then return inputs end
    for device = 0, r.GetNumMIDIInputs() - 1 do
        local ok, name = r.GetMIDIInputName(device, "")
        if ok then inputs[#inputs + 1] = { device = device, name = name } end
    end
    return inputs
end

function H.midi_device()
    if L.midi_device_name == "" then return nil end
    for _, input in ipairs(H.midi_inputs()) do
        if input.name == L.midi_device_name then return input.device end
    end
    return nil
end

function H.reset_midi_input()
    if L.gate_held and L.gate_held.midi then H.gate_release() end
    L.midi_last_retval = r.MIDI_GetRecentInputEvent and (r.MIDI_GetRecentInputEvent(0) or 0) or nil
    L.midi_pressed = {}
    L.midi_command_pressed = {}
end

function H.begin_midi_learn(command)
    L.midi_base_learn = command == "base"
    L.midi_learn = command ~= "base" and command or nil
    L.midi_learn_retval = r.MIDI_GetRecentInputEvent and (r.MIDI_GetRecentInputEvent(0) or 0) or 0
    L.midi_pressed = {}
    L.midi_command_pressed = {}
end

function H.set_midi_enabled(enabled)
    L.midi_enabled = enabled and true or false
    r.SetExtState(C.ext_section, "midi_enabled", L.midi_enabled and "1" or "0", true)
    if L.midi_feedback then
        if L.midi_enabled then H.lp_start() else H.lp_stop() end
    end
    H.reset_midi_input()
end

function H.set_midi_device(name)
    L.midi_device_name = name or ""
    r.SetExtState(C.ext_section, "midi_device_name", L.midi_device_name, true)
    H.reset_midi_input()
end

function H.midi_binding_text(binding)
    if not binding then return "Not assigned" end
    local kind = binding.kind == "cc" and "CC" or "Note"
    return kind .. " " .. tostring(binding.number) .. "  Ch " .. tostring(binding.channel)
end

function H.load_midi_commands()
    L.midi_commands = {}
    for _, command in ipairs(MIDI_COMMANDS) do
        local stored = r.GetExtState(C.ext_section, "midi_command_" .. command.key)
        local kind, number, channel = stored:match("^([a-z]+):(%d+):(%d+)$")
        number, channel = tonumber(number), tonumber(channel)
        if (kind == "note" or kind == "cc") and number and channel then
            L.midi_commands[command.key] = { kind = kind, number = number, channel = channel }
        end
    end
end

function H.set_midi_command(key, binding)
    if binding then
        for _, command in ipairs(MIDI_COMMANDS) do
            local other_key = command.key
            local other = L.midi_commands[other_key]
            if other and other_key ~= key and other.kind == binding.kind and other.channel == binding.channel
                and other.number == binding.number then
                L.midi_commands[other_key] = nil
                r.SetExtState(C.ext_section, "midi_command_" .. other_key, "", true)
            end
        end
    end
    L.midi_commands[key] = binding
    local value = ""
    if binding then
        value = binding.kind .. ":" .. tostring(binding.number) .. ":" .. tostring(binding.channel)
    end
    r.SetExtState(C.ext_section, "midi_command_" .. key, value, true)
    L.midi_learn = nil
    L.midi_learn_retval = nil
    H.reset_midi_input()
end

function H.midi_bank_step(field, delta)
    H.clamp_midi_banks()
    local lane_span, scene_span = H.midi_geometry()
    local span = field == "midi_lane_bank" and lane_span or scene_span
    local total = field == "midi_lane_bank" and #L.lanes or L.rows
    local maximum = math.max(0, math.ceil(total / span) - 1)
    local value = math.max(0, math.min(maximum, L[field] + delta))
    local label = field == "midi_lane_bank" and "lane" or "scene"
    if value == L[field] then
        L.status = "No " .. (delta < 0 and "previous " or "next ") .. label
            .. " bank in the " .. L.midi_layout .. " MIDI layout"
        return
    end
    L[field] = value
    H.save_midi_mapping()
    local lane_offset, scene_offset = H.midi_bank_offsets()
    local lane_span_now, scene_span_now = H.midi_geometry()
    L.status = "MIDI mapping: lanes " .. tostring(lane_offset + 1) .. "-"
        .. tostring(math.min(#L.lanes, lane_offset + lane_span_now)) .. ", scenes "
        .. tostring(scene_offset + 1) .. "-" .. tostring(math.min(L.rows, scene_offset + scene_span_now))
end

function H.run_midi_command(key)
    if key == "lane_prev" then H.midi_bank_step("midi_lane_bank", -1) return end
    if key == "lane_next" then H.midi_bank_step("midi_lane_bank", 1) return end
    if key == "scene_prev" then H.midi_bank_step("midi_scene_bank", -1) return end
    if key == "scene_next" then H.midi_bank_step("midi_scene_bank", 1) return end
    local lane_offset, scene_offset = H.midi_bank_offsets()
    if key == "launch_scene" then H.launch_scene(scene_offset + 1) return end
    if key == "stop_lane" then
        local lane = L.lanes[lane_offset + 1]
        if lane then H.stop_lane(lane) end
        return
    end
    if key == "stop_all" then H.stop_all_quantized() return end
    if key == "record" then H.set_recording(not L.recording) return end
    local scene = tonumber(key:match("^launch_scene_(%d+)$"))
    if scene and scene <= L.rows then H.launch_scene(scene) end
end

function H.midi_command_available(command)
    local octave_mode = L.midi_layout == "keyboard" and L.midi_keyboard_mode == "octaves"
    local pad_scenes = L.midi_layout == "pads" and L.midi_pad_mode == "scenes"
    local pad_clips = L.midi_layout == "pads" and L.midi_pad_mode == "clips"
    if command.scene then return (octave_mode or pad_clips) and command.scene <= L.rows end
    if pad_scenes and (command.key == "lane_prev" or command.key == "lane_next" or command.key == "stop_lane") then
        return false
    end
    if command.key == "scene_prev" or command.key == "scene_next" or command.key == "launch_scene" then
        return not octave_mode
    end
    return true
end

function H.handle_midi_command(kind, channel, number, value)
    if L.midi_learn and value > 0 then
        H.set_midi_command(L.midi_learn, { kind = kind, channel = channel, number = number })
        L.status = "MIDI command assigned"
        return true
    end
    local signature = kind .. ":" .. tostring(channel) .. ":" .. tostring(number)
    if value <= 0 then
        L.midi_command_pressed[signature] = nil
        return false
    end
    for _, command in ipairs(MIDI_COMMANDS) do
        local binding = L.midi_commands[command.key]
        if H.midi_command_available(command) and binding and binding.kind == kind
            and binding.channel == channel and binding.number == number then
            if not L.midi_command_pressed[signature] then
                L.midi_command_pressed[signature] = true
                H.run_midi_command(command.key)
            end
            return true
        end
    end
    return false
end

--------------------------------------------------------------------------------
-- Launchpad: a grid that lights up
--------------------------------------------------------------------------------

-- A Launchpad is not a row of notes. Its pads sit in a grid whose rows step by
-- ten (11 to 88 on a Mini MK3, an X, a Pro MK3 and the RGB MK2) or by sixteen
-- (0 to 119 on the older S and Mini), which is why they never fitted the
-- layouts that count notes one after another. Two numbers describe all of them:
-- the note of the top left pad, and what a row further down adds to it.
--
-- The lights are the other half of it. A script can reach a hardware output:
-- StuffMIDIMessage with 16 plus the device index sends a note, and
-- SendMIDIMessageToHardware sends the SysEx that puts a MK3 into programmer
-- mode. So the grid can show what the launcher knows - what is filled, what is
-- playing, what is still waiting for its bar line.
--
-- None of this could be tried on a real device here. Everything it leans on is
-- therefore a setting rather than a constant: family, output, origin and row
-- step are all in the MIDI window, and there is a test pattern that paints the
-- grid in a known order, so that "the third row is blue and one pad to the
-- left" is enough to put it right.

C.lp_families = {
    { key = "mk3",     label = "Mini MK3 / X / Pro MK3",  origin = 81, step = -10, palette = true,  programmer = true },
    { key = "mk2",     label = "Launchpad MK2 (RGB)",     origin = 81, step = -10, palette = true,  programmer = false },
    { key = "classic", label = "Launchpad S / Mini MK1",  origin = 0,  step = 16,  palette = false, programmer = false },
}

-- Which device is on the other end, read off the output's name. Only the model
-- byte in the middle of the SysEx differs between them.
C.lp_models = {
    { match = "lpminimk3",         id = 0x0D },
    { match = "launchpad mini mk3", id = 0x0D },
    { match = "lpx",               id = 0x0C },
    { match = "launchpad x",       id = 0x0C },
    { match = "lppromk3",          id = 0x0E },
    { match = "launchpad pro mk3", id = 0x0E },
}

-- The RGB models take a palette index. These are the hue groups, each with the
-- bright entry the group starts on and a dimmer one two along, and the point on
-- the colour wheel where one hands over to the next. The breakpoints are not
-- evenly spread on purpose: the palette bunches the greens and blues together,
-- and dividing the wheel into equal shares put pure blue on indigo. If a colour
-- comes out wrong on a real board, it is one number on one of these lines.
C.lp_palette = {
    { upto = 0.045, bright = 5,  dim = 7 },   -- red
    { upto = 0.11,  bright = 9,  dim = 11 },  -- orange
    { upto = 0.21,  bright = 13, dim = 15 },  -- yellow
    { upto = 0.28,  bright = 17, dim = 19 },  -- lime
    { upto = 0.40,  bright = 21, dim = 23 },  -- green
    { upto = 0.46,  bright = 29, dim = 31 },  -- spring
    { upto = 0.55,  bright = 33, dim = 35 },  -- cyan
    { upto = 0.61,  bright = 37, dim = 39 },  -- sky
    { upto = 0.72,  bright = 41, dim = 43 },  -- blue
    { upto = 0.77,  bright = 45, dim = 47 },  -- indigo
    { upto = 0.82,  bright = 49, dim = 51 },  -- purple
    { upto = 0.90,  bright = 53, dim = 55 },  -- magenta
    { upto = 0.96,  bright = 57, dim = 59 },  -- pink
    { upto = 1.01,  bright = 5,  dim = 7 },   -- and round to red again
}

function H.lp_family()
    for _, entry in ipairs(C.lp_families) do
        if entry.key == L.midi_lp_family then return entry end
    end
    return C.lp_families[1]
end

function H.lp_origin()
    local value = tonumber(L.midi_lp_origin)
    if not value then return H.lp_family().origin end
    return math.max(0, math.min(127, math.floor(value)))
end

function H.lp_step()
    local value = tonumber(L.midi_lp_step)
    if not value or value == 0 then return H.lp_family().step end
    return math.floor(value)
end

-- The note a pad carries. Rows count from the top, columns from the left, and
-- column 9 is the strip of scene buttons down the right hand side.
function H.lp_note(row, col)
    local note = H.lp_origin() + row * H.lp_step() + col
    if note < 0 or note > 127 then return nil end
    return note
end

-- The way back, built once and kept until a setting moves.
function H.lp_lookup()
    if L.lp_map then return L.lp_map end
    local map = {}
    for row = 0, 7 do
        for col = 0, 8 do
            local note = H.lp_note(row, col)
            if note then map[note] = { row = row, col = col } end
        end
    end
    L.lp_map = map
    return map
end

function H.lp_forget_map()
    L.lp_map = nil
    L.lp_shadow = nil
end

--------------------------------------------------------------------------------
-- talking to the device
--------------------------------------------------------------------------------

function H.midi_outputs()
    local outputs = {}
    if not (r.GetNumMIDIOutputs and r.GetMIDIOutputName) then return outputs end
    for device = 0, r.GetNumMIDIOutputs() - 1 do
        local ok, name = r.GetMIDIOutputName(device, "")
        if ok and name and name ~= "" then
            outputs[#outputs + 1] = { index = device, name = name }
        end
    end
    return outputs
end

function H.midi_out_device()
    if L.midi_out_name == "" then return nil end
    for _, output in ipairs(H.midi_outputs()) do
        if output.name == L.midi_out_name then return output.index end
    end
    return nil
end

function H.lp_send(status, data1, data2)
    local device = L.midi_out_index
    if not device or not r.StuffMIDIMessage then return end
    r.StuffMIDIMessage(16 + device, status, data1, data2)
end

-- SysEx needs the other call: StuffMIDIMessage carries three bytes and no more.
function H.lp_sysex(bytes)
    local device = L.midi_out_index
    if not device or not r.SendMIDIMessageToHardware then return false end
    local text = {}
    for index = 1, #bytes do text[index] = string.char(bytes[index]) end
    r.SendMIDIMessageToHardware(device, table.concat(text))
    return true
end

function H.lp_model_id()
    local name = (L.midi_out_name or ""):lower()
    for _, model in ipairs(C.lp_models) do
        if name:find(model.match, 1, true) then return model.id end
    end
    return nil
end

-- Programmer mode, so the pads answer to the note grid above rather than to
-- whatever session layout the device woke up in. Only the MK3 generation needs
-- it, and only if we can name the model.
function H.lp_set_programmer(on)
    if not H.lp_family().programmer then return end
    local id = H.lp_model_id()
    if not id then return end
    H.lp_sysex({ 0xF0, 0x00, 0x20, 0x29, 0x02, id, 0x0E, on and 1 or 0, 0xF7 })
end

--------------------------------------------------------------------------------
-- colours
--------------------------------------------------------------------------------

-- Where a colour sits on the wheel, 0 at red and going round through green and
-- blue. Grey answers with nothing, because a grey pad is a pad with no hue to
-- show and the state colour should stand in for it.
function H.hue_of(color)
    local red = ((color >> 24) & 0xFF) / 255
    local green = ((color >> 16) & 0xFF) / 255
    local blue = ((color >> 8) & 0xFF) / 255
    local high = math.max(red, green, blue)
    local low = math.min(red, green, blue)
    local span = high - low
    if span < 0.06 then return nil end
    local hue
    if high == red then hue = ((green - blue) / span) % 6
    elseif high == green then hue = (blue - red) / span + 2
    else hue = (red - green) / span + 4 end
    return (hue / 6) % 1
end

-- A hue as this device can show it. The RGB models get the nearest of thirteen
-- palette hues; the red and green ones get what two lamps can do, which is red,
-- orange, amber and green and no more than that.
function H.lp_colour(color, bright)
    local family = H.lp_family()
    local hue = color and H.hue_of(color) or nil
    if family.palette then
        if not hue then return bright and 3 or 1 end
        for _, entry in ipairs(C.lp_palette) do
            if hue < entry.upto then return bright and entry.bright or entry.dim end
        end
        return bright and 3 or 1
    end
    -- Velocity on the older boards is two lamps and two flags: sixteen times
    -- the green, plus the red, plus twelve. Leave the flags off and the light
    -- lands in a buffer nobody is showing, which looks exactly like a device
    -- that is not listening.
    local red, green = 3, 3
    if hue then
        if hue < 0.05 or hue > 0.92 then red, green = 3, 0
        elseif hue < 0.10 then red, green = 3, 1
        elseif hue < 0.19 then red, green = 3, 3
        elseif hue < 0.45 then red, green = 0, 3
        else red, green = 3, 2 end
    end
    if not bright then
        red = red > 0 and 1 or 0
        green = green > 0 and 1 or 0
    end
    return 16 * green + red + 12
end

function H.lp_off()
    return H.lp_family().palette and 0 or 12
end

--------------------------------------------------------------------------------
-- what the grid should look like
--------------------------------------------------------------------------------

function H.lp_cell_colour(row, col, blink)
    local lane_offset, scene_offset = H.midi_bank_offsets()
    local scene_row = scene_offset + row + 1
    if scene_row > L.rows then return H.lp_off() end
    if col == 8 then
        -- The scene strip: white for a scene that has anything in it, bright
        -- for the one that is running.
        if not H.scene_filled(scene_row) then return H.lp_off() end
        local running = L.scene_run and L.scene_run.row == scene_row
        return H.lp_colour(nil, running and true or false)
    end
    local lane = L.lanes[lane_offset + col + 1]
    if not lane then return H.lp_off() end
    local slot = H.slot(lane, scene_row)
    if not slot then
        -- An armed track shows where a recording would land, the way the grid
        -- draws its record ring in an empty cell.
        if H.slot_mark(lane_offset + col + 1, scene_row) or H.track_armed(H.target_track(lane)) then
            return blink and H.lp_colour(0xFF0000FF, true) or H.lp_off()
        end
        return H.lp_off()
    end
    local color = slot.color or H.lane_color(lane)
    local live = H.slot_is_live(lane, scene_row)
    if live == "pending" or (lane.queued and lane.queued.row == scene_row) then
        return blink and H.lp_colour(color, true) or H.lp_off()
    end
    if live == "playing" then return H.lp_colour(color, true) end
    return H.lp_colour(color, false)
end

-- Only what changed is sent. A Launchpad given all sixty-four pads several
-- times a second falls behind and starts dropping messages, and the grid then
-- lags a beat behind the music, which is worse than no lights at all.
function H.lp_refresh(force)
    -- The lights speak the Launchpad grid, so they only make sense while that
    -- is the layout the notes come in on.
    if L.midi_layout ~= "launchpad" then return end
    if not L.midi_feedback or not L.midi_out_index then return end
    local now = r.time_precise()
    if not force and L.lp_sent and now - L.lp_sent < 0.05 then return end
    L.lp_sent = now
    local blink = (now % 0.6) < 0.3
    L.lp_shadow = L.lp_shadow or {}
    for row = 0, 7 do
        for col = 0, 8 do
            local note = H.lp_note(row, col)
            if note then
                local wanted = H.lp_cell_colour(row, col, blink)
                if force or L.lp_shadow[note] ~= wanted then
                    L.lp_shadow[note] = wanted
                    H.lp_send(0x90, note, wanted)
                end
            end
        end
    end
end

function H.lp_clear()
    local off = H.lp_off()
    L.lp_shadow = {}
    for row = 0, 7 do
        for col = 0, 8 do
            local note = H.lp_note(row, col)
            if note then H.lp_send(0x90, note, off) end
        end
    end
end

-- Paint the grid in an order anyone can describe: row one red, then orange,
-- yellow, green, cyan, blue, purple, white, and the scene strip white as well.
-- What comes back from that says whether the origin, the row step and the
-- palette are right, which is the whole of what cannot be checked from here.
function H.lp_test_pattern()
    if not L.midi_out_index then
        L.status = "Choose a MIDI output first"
        return
    end
    local hues = { 0xFF0000FF, 0xFF8000FF, 0xFFFF00FF, 0x00FF00FF,
                   0x00FFFFFF, 0x0000FFFF, 0xFF00FFFF, 0xFFFFFFFF }
    L.lp_shadow = {}
    for row = 0, 7 do
        for col = 0, 8 do
            local note = H.lp_note(row, col)
            if note then
                local colour = col == 8 and H.lp_colour(nil, true)
                    or H.lp_colour(hues[row + 1], col < 4)
                L.lp_shadow[note] = colour
                H.lp_send(0x90, note, colour)
            end
        end
    end
    L.status = "Test pattern sent: row 1 red, then orange, yellow, green, cyan, blue, purple, white."
        .. " Left half bright, right half dim, scene strip white."
end

function H.lp_start()
    if L.midi_layout ~= "launchpad" then return end
    L.midi_out_index = H.midi_out_device()
    H.lp_forget_map()
    if not L.midi_out_index then return end
    H.lp_set_programmer(true)
    H.lp_refresh(true)
end

function H.lp_stop()
    if L.midi_out_index then
        H.lp_clear()
        H.lp_set_programmer(false)
    end
    L.midi_out_index = nil
    L.lp_shadow = nil
end

function H.set_midi_out(name)
    H.lp_stop()
    L.midi_out_name = name or ""
    r.SetExtState(C.ext_section, "midi_out_name", L.midi_out_name, true)
    if L.midi_feedback then H.lp_start() end
end

function H.set_midi_feedback(on)
    L.midi_feedback = on and true or false
    r.SetExtState(C.ext_section, "midi_feedback", L.midi_feedback and "1" or "0", true)
    if L.midi_feedback then H.lp_start() else H.lp_stop() end
end

function H.set_lp_family(key)
    H.lp_stop()
    L.midi_lp_family = key
    L.midi_lp_origin = nil
    L.midi_lp_step = nil
    r.SetExtState(C.ext_section, "midi_lp_family", key, true)
    r.SetExtState(C.ext_section, "midi_lp_origin", "", true)
    r.SetExtState(C.ext_section, "midi_lp_step", "", true)
    H.lp_forget_map()
    if L.midi_feedback then H.lp_start() end
end

function H.midi_geometry()
    if L.midi_layout == "keyboard" then
        if L.midi_keyboard_mode == "active" then return 12, 1, 12 end
        local scenes = math.max(1, math.min(L.rows, math.floor((128 - L.midi_base_note) / 12)))
        return 12, scenes, scenes * 12
    end
    if L.midi_layout == "pads" then
        if L.midi_pad_mode == "scenes" then return 1, 8, 8 end
        return 8, 1, 8
    end
    -- Eight lanes across and eight scenes down, whatever notes the pads carry.
    if L.midi_layout == "launchpad" then return 8, 8, 64 end
    local columns = math.max(1, math.min(16, L.midi_columns))
    local rows = math.max(1, math.min(16, L.midi_rows))
    local count = math.min(columns * rows, 128 - L.midi_base_note)
    if L.midi_orientation == "scenes" then return rows, columns, count end
    return columns, rows, count
end

function H.midi_requested_notes()
    if L.midi_layout == "keyboard" then return 12 end
    if L.midi_layout == "pads" then return 8 end
    return math.min(128, L.midi_columns * L.midi_rows)
end

function H.midi_max_base_note()
    return 128 - H.midi_requested_notes()
end

function H.midi_bank_offsets()
    local lane_span, scene_span = H.midi_geometry()
    return L.midi_lane_bank * lane_span, L.midi_scene_bank * scene_span
end

function H.clamp_midi_banks()
    local lane_span, scene_span = H.midi_geometry()
    local max_lane_bank = math.max(0, math.ceil(#L.lanes / lane_span) - 1)
    local max_scene_bank = math.max(0, math.ceil(L.rows / scene_span) - 1)
    L.midi_lane_bank = math.max(0, math.min(max_lane_bank, L.midi_lane_bank))
    L.midi_scene_bank = math.max(0, math.min(max_scene_bank, L.midi_scene_bank))
    if L.midi_layout == "pads" and L.midi_pad_mode == "scenes" then L.midi_lane_bank = 0 end
end

function H.save_midi_mapping()
    H.clamp_midi_banks()
    r.SetExtState(C.ext_section, "midi_layout", L.midi_layout, true)
    r.SetExtState(C.ext_section, "midi_keyboard_mode", L.midi_keyboard_mode, true)
    r.SetExtState(C.ext_section, "midi_pad_mode", L.midi_pad_mode, true)
    r.SetExtState(C.ext_section, "midi_columns", tostring(L.midi_columns), true)
    r.SetExtState(C.ext_section, "midi_rows", tostring(L.midi_rows), true)
    r.SetExtState(C.ext_section, "midi_orientation", L.midi_orientation, true)
    r.SetExtState(C.ext_section, "midi_lane_bank", tostring(L.midi_lane_bank), true)
    r.SetExtState(C.ext_section, "midi_scene_bank", tostring(L.midi_scene_bank), true)
    H.lp_forget_map()
    H.reset_midi_input()
end

function H.midi_note_target(note)
    H.clamp_midi_banks()
    if L.midi_layout == "launchpad" then
        local pad = H.lp_lookup()[note]
        -- Column nine is the scene strip, and that is answered elsewhere.
        if not pad or pad.col > 7 then return nil end
        local lane_offset, scene_offset = H.midi_bank_offsets()
        local lane_index = lane_offset + pad.col + 1
        local row = scene_offset + pad.row + 1
        if lane_index > #L.lanes or row > L.rows then return nil end
        return lane_index, row
    end
    local offset = note - L.midi_base_note
    local lane_span, scene_span, note_count = H.midi_geometry()
    if offset < 0 or offset >= note_count then return nil end
    local local_lane, local_scene
    if L.midi_layout == "keyboard" then
        local_lane = offset % 12
        local_scene = L.midi_keyboard_mode == "octaves" and math.floor(offset / 12) or 0
    elseif L.midi_layout == "custom" and L.midi_orientation == "scenes" then
        local_scene = offset % scene_span
        local_lane = math.floor(offset / scene_span)
    else
        local_lane = offset % lane_span
        local_scene = math.floor(offset / lane_span)
    end
    local lane_offset, scene_offset = H.midi_bank_offsets()
    local lane_index = lane_offset + local_lane + 1
    local row = scene_offset + local_scene + 1
    if lane_index > #L.lanes or row > L.rows then return nil end
    return lane_index, row
end

function H.midi_scene_target(note)
    -- The strip down the right hand side of a Launchpad launches scenes, which
    -- is what it is labelled for on every model.
    if L.midi_layout == "launchpad" then
        local pad = H.lp_lookup()[note]
        if not pad or pad.col ~= 8 then return nil end
        local row = select(2, H.midi_bank_offsets()) + pad.row + 1
        return row <= L.rows and row or nil
    end
    if L.midi_layout ~= "pads" or L.midi_pad_mode ~= "scenes" then return nil end
    local offset = note - L.midi_base_note
    if offset < 0 or offset >= 8 then return nil end
    local row = L.midi_scene_bank * 8 + offset + 1
    if row > L.rows then return nil end
    return row
end

function H.handle_midi()
    if (not L.midi_enabled and not L.midi_learn and not L.midi_base_learn)
        or not r.MIDI_GetRecentInputEvent then return end
    local wanted_device = H.midi_device()
    if wanted_device == nil then return end
    if L.midi_last_retval == nil then
        H.reset_midi_input()
        return
    end
    local learn_active = L.midi_learn ~= nil or L.midi_base_learn
    local boundary_retval = learn_active and L.midi_learn_retval or L.midi_last_retval
    local first_retval = nil
    local events = {}
    for index = 0, 127 do
        local retval, rawmsg, _, device = r.MIDI_GetRecentInputEvent(index)
        if index == 0 then first_retval = retval end
        if retval == 0 or retval == boundary_retval then break end
        if device == wanted_device and rawmsg and #rawmsg >= 3 then
            events[#events + 1] = rawmsg
        end
    end
    if first_retval and first_retval ~= 0 then
        L.midi_last_retval = first_retval
        if learn_active then L.midi_learn_retval = first_retval end
    end
    for index = #events, 1, -1 do
        local rawmsg = events[index]
        local status = rawmsg:byte(1)
        local kind = status & 0xF0
        local channel = (status & 0x0F) + 1
        local note = rawmsg:byte(2)
        local velocity = rawmsg:byte(3)
        if L.midi_channel == 0 or channel == L.midi_channel then
            local command_kind = kind == 0xB0 and "cc" or ((kind == 0x90 or kind == 0x80) and "note" or nil)
            local command_value = kind == 0x80 and 0 or velocity
            local command_handled = L.midi_base_learn and true or false
            if L.midi_base_learn and kind == 0x90 and velocity > 0 then
                local maximum = H.midi_max_base_note()
                if note <= maximum then
                    L.midi_base_note = note
                    L.midi_base_learn = false
                    L.midi_learn_retval = nil
                    r.SetExtState(C.ext_section, "midi_base_note", tostring(note), true)
                    H.save_midi_mapping()
                    L.status = "MIDI base note set to " .. tostring(note)
                else
                    L.status = "MIDI note " .. tostring(note) .. " is too high; maximum is " .. tostring(maximum)
                end
            elseif not L.midi_base_learn then
                command_handled = command_kind and H.handle_midi_command(command_kind, channel, note, command_value)
            end
            local scene_row = H.midi_scene_target(note)
            local lane_index, row = H.midi_note_target(note)
            local key = channel * 128 + note
            if not command_handled and kind == 0x90 and velocity > 0 and not L.midi_pressed[key] then
                if scene_row then
                    L.midi_pressed[key] = { scene = scene_row }
                    H.launch_scene(scene_row)
                elseif lane_index then
                    local lane = L.lanes[lane_index]
                    local slot = lane and H.slot(lane, row) or nil
                    if slot then
                        L.cursor.lane, L.cursor.row = lane_index, row
                        L.midi_pressed[key] = { lane = lane, row = row, gate = slot.launch_mode == "gate" }
                        if slot.launch_mode == "gate" then
                            H.gate_press(lane, lane_index, row)
                            if L.gate_held then L.gate_held.midi = true end
                        else
                            H.click_slot(lane, lane_index, row, slot)
                        end
                    else
                        L.status = "MIDI note " .. tostring(note) .. " maps to empty lane "
                            .. tostring(lane_index) .. ", scene " .. tostring(row)
                    end
                end
            elseif (kind == 0x80 or (kind == 0x90 and velocity == 0)) and L.midi_pressed[key] then
                local pressed = L.midi_pressed[key]
                L.midi_pressed[key] = nil
                local held = L.gate_held
                if pressed.gate and held and held.holder == pressed.lane and held.row == pressed.row then
                    H.gate_release()
                end
            end
        end
    end
end

function H.draw_midi_bank(label, field, span, total)
    local bank = L[field]
    local maximum = math.max(0, math.ceil(total / span) - 1)
    local start_index = bank * span + 1
    local end_index = math.min(total, start_index + span - 1)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, label)
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
    if r.ImGui_Button(UI.ctx, "-##" .. field, UI.rounded(24), UI.rounded(22)) and bank > 0 then
        L[field] = bank - 1
        H.save_midi_mapping()
        bank = L[field]
        start_index = bank * span + 1
        end_index = math.min(total, start_index + span - 1)
    end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(4))
    if r.ImGui_Button(UI.ctx, "+##" .. field, UI.rounded(24), UI.rounded(22)) and bank < maximum then
        L[field] = bank + 1
        H.save_midi_mapping()
        bank = L[field]
        start_index = bank * span + 1
        end_index = math.min(total, start_index + span - 1)
    end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
    r.ImGui_Text(UI.ctx, tostring(start_index) .. "-" .. tostring(end_index))
end

function H.draw_midi_command_row(command)
    local binding = L.midi_commands[command.key]
    local learning = L.midi_learn == command.key
    local label = command.label
    if command.key == "scene_prev" and (L.midi_layout ~= "custom" or select(2, H.midi_geometry()) == 1) then
        label = "Previous scene"
    elseif command.key == "scene_next" and (L.midi_layout ~= "custom" or select(2, H.midi_geometry()) == 1) then
        label = "Next scene"
    end
    r.ImGui_TableNextRow(UI.ctx)
    r.ImGui_TableNextColumn(UI.ctx)
    r.ImGui_Text(UI.ctx, label)
    r.ImGui_TableNextColumn(UI.ctx)
    r.ImGui_TextColored(UI.ctx, binding and UI.colors.text or UI.colors.text_dim, H.midi_binding_text(binding))
    r.ImGui_TableNextColumn(UI.ctx)
    if learning then
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
    end
    if r.ImGui_Button(UI.ctx, learning and "Waiting...##" .. command.key or "Learn##" .. command.key,
        UI.rounded(78), UI.rounded(22)) then
        if learning then
            L.midi_learn = nil
            L.midi_learn_retval = nil
        else
            H.begin_midi_learn(command.key)
        end
    end
    if learning then r.ImGui_PopStyleColor(UI.ctx, 2) end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(5))
    if r.ImGui_Button(UI.ctx, "Clear##" .. command.key, UI.rounded(52), UI.rounded(22)) then
        H.set_midi_command(command.key, nil)
    end
end

-- Everything a Launchpad needs, in the order you would set it up: which family
-- it belongs to, where its grid starts, which output to light, and a pattern to
-- prove it. The last two matter most: this could not be tried on a real device,
-- so the window has to be able to tell you what it is doing.
function H.draw_launchpad_setup()
    local family = H.lp_family()
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
    if r.ImGui_BeginCombo(UI.ctx, "##lp_family", family.label) then
        for _, entry in ipairs(C.lp_families) do
            local selected = entry.key == L.midi_lp_family
            if r.ImGui_Selectable(UI.ctx, entry.label, selected) then H.set_lp_family(entry.key) end
            if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
        end
        r.ImGui_EndCombo(UI.ctx)
    end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
        family.palette and "Colour palette" or "Red and green only")

    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(120))
    local origin_changed, origin = r.ImGui_InputInt(UI.ctx, "Top left pad", H.lp_origin())
    if origin_changed then
        L.midi_lp_origin = math.max(0, math.min(127, origin))
        r.SetExtState(C.ext_section, "midi_lp_origin", tostring(L.midi_lp_origin), true)
        H.lp_forget_map()
        if L.midi_feedback then H.lp_start() end
    end
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(120))
    local step_changed, step = r.ImGui_InputInt(UI.ctx, "A row further down", H.lp_step())
    if step_changed and step ~= 0 then
        L.midi_lp_step = math.max(-32, math.min(32, step))
        r.SetExtState(C.ext_section, "midi_lp_step", tostring(L.midi_lp_step), true)
        H.lp_forget_map()
        if L.midi_feedback then H.lp_start() end
    end
    local first, last = H.lp_note(0, 0), H.lp_note(7, 7)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
        "Pads " .. tostring(first or "?") .. " to " .. tostring(last or "?")
        .. ", column nine launches scenes")

    r.ImGui_Spacing(UI.ctx)
    local outputs = H.midi_outputs()
    local out_label = L.midi_out_name ~= "" and L.midi_out_name or "No output - the pads stay dark"
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
    if r.ImGui_BeginCombo(UI.ctx, "##lp_output", out_label) then
        if r.ImGui_Selectable(UI.ctx, "No output - the pads stay dark", L.midi_out_name == "") then
            H.set_midi_out("")
        end
        for _, output in ipairs(outputs) do
            local selected = output.name == L.midi_out_name
            if r.ImGui_Selectable(UI.ctx, output.name, selected) then H.set_midi_out(output.name) end
            if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
        end
        r.ImGui_EndCombo(UI.ctx)
    end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "The port the pads listen on. On Windows a Mini MK3 or an X calls it\nMIDIOUT2, and that second port is the one a DAW is meant to use.")
    end

    local feedback_changed, feedback = r.ImGui_Checkbox(UI.ctx, "Light the pads", L.midi_feedback)
    if feedback_changed then H.set_midi_feedback(feedback) end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Empty is dark, a filled slot glows in its clip's colour, the one that\nis playing is bright, one waiting for its bar line blinks, and an armed\ntrack blinks red. Only pads that change are sent.")
    end

    if r.ImGui_Button(UI.ctx, "Test pattern", UI.rounded(110), UI.rounded(22)) then H.lp_test_pattern() end
    if r.ImGui_IsItemHovered(UI.ctx) then
        r.ImGui_SetTooltip(UI.ctx, "Paints the grid in a known order: row 1 red, then orange, yellow,\ngreen, cyan, blue, purple, white. Left half bright, right half dim,\nand the scene strip white. What you see says whether the top left\npad, the row step and the colours are right.")
    end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
    if r.ImGui_Button(UI.ctx, "All off", UI.rounded(80), UI.rounded(22)) then H.lp_clear() end
    if family.programmer then
        r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
        if r.ImGui_Button(UI.ctx, "Programmer mode", UI.rounded(150), UI.rounded(22)) then
            H.lp_set_programmer(true)
            L.status = H.lp_model_id() and "Programmer mode sent"
                or "This output's name does not say which model it is, so no mode was sent"
        end
        if r.ImGui_IsItemHovered(UI.ctx) then
            r.ImGui_SetTooltip(UI.ctx, "MK3 boards answer to the 11-88 grid only in programmer mode.\nIt is sent when the lights are switched on, and this asks again\nfor a board that was unplugged and put back.")
        end
    end
    if not r.StuffMIDIMessage then
        r.ImGui_TextColored(UI.ctx, UI.colors.danger, "This REAPER cannot send to a MIDI output")
    elseif not r.SendMIDIMessageToHardware and family.programmer then
        r.ImGui_TextColored(UI.ctx, UI.colors.warning or UI.colors.danger,
            "No SysEx from this REAPER: put the board in programmer mode by hand")
    end
end

-- The note the mapping counts from, with a Learn button beside it.
function H.draw_midi_base_note()
    local max_base_note = H.midi_max_base_note()
    if L.midi_base_note > max_base_note then
        L.midi_base_note = max_base_note
        r.SetExtState(C.ext_section, "midi_base_note", tostring(L.midi_base_note), true)
        H.save_midi_mapping()
    end
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
    local note_changed, base_note = r.ImGui_SliderInt(UI.ctx, "Base note", L.midi_base_note, 0, max_base_note)
    if note_changed then
        L.midi_base_learn = false
        L.midi_base_note = base_note
        r.SetExtState(C.ext_section, "midi_base_note", tostring(base_note), true)
        H.save_midi_mapping()
    end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
    local base_learning = L.midi_base_learn
    if base_learning then
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
        r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
    end
    if r.ImGui_Button(UI.ctx, base_learning and "Waiting...##base_note" or "Learn##base_note",
        UI.rounded(82), UI.rounded(22)) then
        if base_learning then
            L.midi_base_learn = false
            L.midi_learn_retval = nil
        else
            H.begin_midi_learn("base")
        end
    end
    if base_learning then r.ImGui_PopStyleColor(UI.ctx, 2) end
    if L.midi_base_learn then
        r.ImGui_TextColored(UI.ctx, UI.colors.accent, "Press the first clip key on the selected controller")
    end
end

function H.draw_midi_popup()
    if not L.midi_window_open then return end
    if r.ImGui_IsPopupOpen and not r.ImGui_IsPopupOpen(UI.ctx, "##launch_midi") then
        r.ImGui_OpenPopup(UI.ctx, "##launch_midi")
    end
    if r.ImGui_SetNextWindowSize then
        r.ImGui_SetNextWindowSize(UI.ctx, UI.rounded(540), 0, r.ImGui_Cond_Appearing())
    end
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_midi") then return end
    if r.ImGui_IsWindowFocused(UI.ctx)
        and r.ImGui_IsKeyPressed(UI.ctx, r.ImGui_Key_Escape()) then
        L.midi_window_open = false
        r.ImGui_CloseCurrentPopup(UI.ctx)
        r.ImGui_EndPopup(UI.ctx)
        return
    end
    local available = r.MIDI_GetRecentInputEvent and r.GetNumMIDIInputs and r.GetMIDIInputName
    r.ImGui_TextColored(UI.ctx, UI.colors.accent, "MIDI Setup")
    r.ImGui_SameLine(UI.ctx)
    r.ImGui_SetCursorPosX(UI.ctx, r.ImGui_GetWindowWidth(UI.ctx) - UI.rounded(30))
    r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.danger)
    r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_ButtonHovered(), H.mix(UI.colors.danger, 0xFFFFFFFF, 0.18))
    r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_ButtonActive(), H.mix(UI.colors.danger, 0x000000FF, 0.18))
    r.ImGui_PushStyleVar(UI.ctx, r.ImGui_StyleVar_FrameRounding(), UI.rounded(9))
    local close_midi = r.ImGui_Button(UI.ctx, "##close_midi", UI.rounded(18), UI.rounded(18))
    r.ImGui_PopStyleVar(UI.ctx)
    r.ImGui_PopStyleColor(UI.ctx, 3)
    if close_midi then
        L.midi_window_open = false
        r.ImGui_CloseCurrentPopup(UI.ctx)
        r.ImGui_EndPopup(UI.ctx)
        return
    end
    r.ImGui_Separator(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Presets")
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
    local preset_label = L.midi_preset_selected or "Choose preset"
    if r.ImGui_BeginCombo(UI.ctx, "##midi_preset", preset_label) then
        for _, preset in ipairs(L.midi_presets) do
            local selected = preset.name == L.midi_preset_selected
            if r.ImGui_Selectable(UI.ctx, preset.name, selected) then H.apply_midi_preset(preset) end
            if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
        end
        r.ImGui_EndCombo(UI.ctx)
    end
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
    local preset_name_changed, preset_name = r.ImGui_InputText(UI.ctx, "##midi_preset_name", L.midi_preset_name)
    if preset_name_changed then L.midi_preset_name = preset_name end
    r.ImGui_SameLine(UI.ctx, 0, UI.rounded(8))
    if r.ImGui_Button(UI.ctx, "Save##midi_preset", UI.rounded(64), UI.rounded(22)) then
        H.save_midi_preset(L.midi_preset_name)
    end
    if L.midi_preset_selected then
        r.ImGui_SameLine(UI.ctx, 0, UI.rounded(6))
        if r.ImGui_Button(UI.ctx, "Delete##midi_preset", UI.rounded(68), UI.rounded(22)) then
            H.delete_midi_preset(L.midi_preset_selected)
        end
    end
    r.ImGui_Separator(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Connection")
    local changed, enabled = r.ImGui_Checkbox(UI.ctx, "Enable MIDI", L.midi_enabled)
    if changed then H.set_midi_enabled(enabled) end
    if not available then
        r.ImGui_TextColored(UI.ctx, UI.colors.danger, "MIDI input API is not available")
        r.ImGui_EndPopup(UI.ctx)
        return
    end
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
    local device_label = L.midi_device_name ~= "" and L.midi_device_name or "Choose controller"
    if r.ImGui_BeginCombo(UI.ctx, "##midi_input", device_label) then
        for _, input in ipairs(H.midi_inputs()) do
            local selected = input.name == L.midi_device_name
            if r.ImGui_Selectable(UI.ctx, input.name, selected) then H.set_midi_device(input.name) end
            if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
        end
        r.ImGui_EndCombo(UI.ctx)
    end
    if L.midi_device_name ~= "" and H.midi_device() == nil then
        r.ImGui_TextColored(UI.ctx, UI.colors.danger, "Controller is not available in REAPER")
    end
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(120))
    local channel_label = L.midi_channel == 0 and "Omni" or ("Channel " .. tostring(L.midi_channel))
    if r.ImGui_BeginCombo(UI.ctx, "##midi_channel", channel_label) then
        if r.ImGui_Selectable(UI.ctx, "Omni", L.midi_channel == 0) then
            L.midi_channel = 0
            r.SetExtState(C.ext_section, "midi_channel", "0", true)
            H.reset_midi_input()
        end
        for channel = 1, 16 do
            if r.ImGui_Selectable(UI.ctx, "Channel " .. tostring(channel), L.midi_channel == channel) then
                L.midi_channel = channel
                r.SetExtState(C.ext_section, "midi_channel", tostring(channel), true)
                H.reset_midi_input()
            end
        end
        r.ImGui_EndCombo(UI.ctx)
    end

    r.ImGui_Spacing(UI.ctx)
    r.ImGui_Separator(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Clip mapping")

    local layout_labels = {
        keyboard = "Keyboard - 12 lanes",
        pads = "Pads - 8 lanes x 1 scene",
        custom = "Grid - custom",
        launchpad = "Launchpad - 8 x 8 with lights",
    }
    r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
    if r.ImGui_BeginCombo(UI.ctx, "##midi_layout", layout_labels[L.midi_layout]) then
        for _, layout in ipairs({ "keyboard", "pads", "custom", "launchpad" }) do
            local selected = L.midi_layout == layout
            if r.ImGui_Selectable(UI.ctx, layout_labels[layout], selected) then
                L.midi_layout = layout
                H.save_midi_mapping()
            end
            if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
        end
        r.ImGui_EndCombo(UI.ctx)
    end

    if L.midi_layout == "keyboard" then
        local keyboard_labels = {
            octaves = "Scene per octave",
            active = "One octave - active scene",
        }
        r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
        if r.ImGui_BeginCombo(UI.ctx, "##midi_keyboard_mode", keyboard_labels[L.midi_keyboard_mode]) then
            for _, mode in ipairs({ "octaves", "active" }) do
                local selected = L.midi_keyboard_mode == mode
                if r.ImGui_Selectable(UI.ctx, keyboard_labels[mode], selected) then
                    L.midi_keyboard_mode = mode
                    L.midi_scene_bank = 0
                    H.save_midi_mapping()
                end
                if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
            end
            r.ImGui_EndCombo(UI.ctx)
        end
    elseif L.midi_layout == "pads" then
        local pad_labels = {
            clips = "Clips in active scene",
            scenes = "Launch scenes",
        }
        r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
        if r.ImGui_BeginCombo(UI.ctx, "##midi_pad_mode", pad_labels[L.midi_pad_mode]) then
            for _, mode in ipairs({ "clips", "scenes" }) do
                local selected = L.midi_pad_mode == mode
                if r.ImGui_Selectable(UI.ctx, pad_labels[mode], selected) then
                    L.midi_pad_mode = mode
                    L.midi_lane_bank = 0
                    L.midi_scene_bank = 0
                    H.save_midi_mapping()
                end
                if selected then r.ImGui_SetItemDefaultFocus(UI.ctx) end
            end
            r.ImGui_EndCombo(UI.ctx)
        end
    elseif L.midi_layout == "custom" then
        r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
        local columns_changed, columns = r.ImGui_SliderInt(UI.ctx, "Columns", L.midi_columns, 1, 16)
        if columns_changed then
            L.midi_columns = columns
            H.save_midi_mapping()
        end
        r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(260))
        local rows_changed, rows = r.ImGui_SliderInt(UI.ctx, "Rows", L.midi_rows, 1, 16)
        if rows_changed then
            L.midi_rows = rows
            H.save_midi_mapping()
        end
        r.ImGui_SetNextItemWidth(UI.ctx, UI.rounded(180))
        local orientation_label = L.midi_orientation == "scenes" and "Scenes across" or "Lanes across"
        if r.ImGui_BeginCombo(UI.ctx, "##midi_orientation", orientation_label) then
            if r.ImGui_Selectable(UI.ctx, "Lanes across", L.midi_orientation == "lanes") then
                L.midi_orientation = "lanes"
                H.save_midi_mapping()
            end
            if r.ImGui_Selectable(UI.ctx, "Scenes across", L.midi_orientation == "scenes") then
                L.midi_orientation = "scenes"
                H.save_midi_mapping()
            end
            r.ImGui_EndCombo(UI.ctx)
        end
    elseif L.midi_layout == "launchpad" then
        H.draw_launchpad_setup()
    end

    -- A Launchpad has no base note: its grid is described by an origin and a
    -- row step of its own, so the slider would be a control for nothing.
    if L.midi_layout ~= "launchpad" then H.draw_midi_base_note() end

    H.clamp_midi_banks()
    local lane_span, scene_span, note_count = H.midi_geometry()
    if L.midi_layout ~= "pads" or L.midi_pad_mode ~= "scenes" then
        H.draw_midi_bank("Lanes", "midi_lane_bank", lane_span, math.max(1, #L.lanes))
    end
    if L.midi_layout ~= "keyboard" or L.midi_keyboard_mode == "active" then
        H.draw_midi_bank("Scenes", "midi_scene_bank", scene_span, math.max(1, L.rows))
    end
    local lane_offset, scene_offset = H.midi_bank_offsets()
    if L.midi_layout ~= "launchpad" then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
            "Notes " .. tostring(L.midi_base_note) .. "-" .. tostring(L.midi_base_note + note_count - 1))
    end
    if L.midi_layout == "pads" and L.midi_pad_mode == "scenes" then
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
            "Mapping: scenes " .. tostring(scene_offset + 1) .. "-"
            .. tostring(math.min(L.rows, scene_offset + scene_span)))
    else
        r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
            "Mapping: lanes " .. tostring(lane_offset + 1) .. "-" .. tostring(math.min(#L.lanes, lane_offset + lane_span))
            .. ", scenes " .. tostring(scene_offset + 1) .. "-" .. tostring(math.min(L.rows, scene_offset + scene_span)))
    end

    r.ImGui_Spacing(UI.ctx)
    r.ImGui_Separator(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Command mapping")
    if L.midi_learn then
        r.ImGui_TextColored(UI.ctx, UI.colors.accent, "Press a MIDI note or CC on the selected controller")
    end
    local command_height = L.midi_layout == "keyboard" and L.midi_keyboard_mode == "octaves"
        and UI.rounded(260) or UI.rounded(210)
    local child_visible = r.ImGui_BeginChild(UI.ctx, "##midi_command_list", 0, command_height, 0)
    if child_visible and r.ImGui_BeginTable(UI.ctx, "##midi_commands", 3, r.ImGui_TableFlags_SizingFixedFit()) then
        r.ImGui_TableSetupColumn(UI.ctx, "Action", r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(178))
        r.ImGui_TableSetupColumn(UI.ctx, "Assignment", r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(142))
        r.ImGui_TableSetupColumn(UI.ctx, "##controls", r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(142))
        for _, command in ipairs(MIDI_COMMANDS) do
            if H.midi_command_available(command) then H.draw_midi_command_row(command) end
        end
        r.ImGui_EndTable(UI.ctx)
    end
    r.ImGui_EndChild(UI.ctx)
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim,
        "Command assignments take priority over clip notes. The input must be enabled in REAPER Preferences > MIDI Devices.")
    r.ImGui_EndPopup(UI.ctx)
end

function H.draw_timing_popup()
    if not r.ImGui_BeginPopup(UI.ctx, "##launch_timing") then return end

    r.ImGui_TextColored(UI.ctx, UI.colors.accent, "Launch quantize")
    r.ImGui_TextColored(UI.ctx, UI.colors.text_dim, "Clips wait for this boundary, on the measures REAPER itself draws.")
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

    -- Only while a curve is out in the arrange being drawn into. Kept, because
    -- the way back from that state cannot be the first thing to fold away.
    if L.autom_edit then
        add({ group = 1, width = UI.rounded(96), keep = true,
            draw = function()
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
                if r.ImGui_Button(UI.ctx, "Curve done", UI.rounded(96), UI.rounded(26)) then
                    H.finish_autom_edit(true)
                end
                r.ImGui_PopStyleColor(UI.ctx, 2)
                if r.ImGui_IsItemHovered(UI.ctx) then
                    r.ImGui_SetTooltip(UI.ctx, "Take " .. (L.autom_edit and L.autom_edit.name or "the curve")
                        .. " back into its clip and clear it out of the arrange")
                end
            end,
            menu = function()
                if r.ImGui_MenuItem(UI.ctx, "Curve done") then H.finish_autom_edit(true) end
            end })
        add({ group = 1, width = UI.rounded(72), keep = true,
            draw = function()
                if r.ImGui_Button(UI.ctx, "Cancel", UI.rounded(72), UI.rounded(26)) then
                    H.finish_autom_edit(false)
                end
                if r.ImGui_IsItemHovered(UI.ctx) then
                    r.ImGui_SetTooltip(UI.ctx, "Leave the clip as it was and clear the drawing out of the arrange")
                end
            end,
            menu = function()
                if r.ImGui_MenuItem(UI.ctx, "Cancel the curve") then H.finish_autom_edit(false) end
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

    add({ group = 3, width = UI.rounded(76),
        draw = function()
            if L.midi_enabled then
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
            end
            if r.ImGui_Button(UI.ctx, L.midi_enabled and "MIDI on" or "MIDI", UI.rounded(76), UI.rounded(26)) then
                L.midi_window_open = true
                r.ImGui_OpenPopup(UI.ctx, "##launch_midi")
            end
            if L.midi_enabled then r.ImGui_PopStyleColor(UI.ctx, 2) end
            if r.ImGui_IsItemHovered(UI.ctx) then
                local labels = { keyboard = "Keyboard", pads = "Pads 8 x 1", custom = "Custom grid" }
                r.ImGui_SetTooltip(UI.ctx, "MIDI controller mapping: " .. (labels[L.midi_layout] or "Custom grid"))
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "MIDI Setup...") then
                H.request_popup("##launch_midi")
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

    local guide_track = H.guide_track()
    add({ group = 3, width = UI.rounded(88),
        draw = function()
            if guide_track then
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Button(), UI.colors.accent_soft)
                r.ImGui_PushStyleColor(UI.ctx, r.ImGui_Col_Border(), UI.colors.accent)
            end
            if r.ImGui_Button(UI.ctx, "Chords", UI.rounded(88), UI.rounded(26)) then
                r.ImGui_OpenPopup(UI.ctx, "##launch_guide")
            end
            if guide_track then r.ImGui_PopStyleColor(UI.ctx, 2) end
            if r.ImGui_IsItemHovered(UI.ctx) then
                r.ImGui_SetTooltip(UI.ctx, guide_track
                    and ("Chord guide: " .. H.track_name(guide_track, "Track"))
                    or "Choose a MIDI track that describes the session harmony")
            end
        end,
        menu = function()
            if r.ImGui_MenuItem(UI.ctx, "Chord guide...") then H.request_popup("##launch_guide") end
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
        if L.popup_request == "##launch_midi" then L.midi_window_open = true end
        r.ImGui_OpenPopup(UI.ctx, L.popup_request)
        L.popup_request = nil
    end
    H.draw_toolbar_row(H.toolbar_items(), 0)
    -- Drawn whether or not their buttons made it into the bar: a popup opened
    -- from the overflow menu still has to find its window here.
    H.draw_timing_popup()
    H.draw_midi_popup()
    H.draw_key_popup()
    H.draw_guide_popup()
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
        return
    end
    -- The same rule as a click, so a key pressed twice behaves the way the
    -- mouse does. Shift is still there to stop a lane outright.
    local slot = H.slot(lane, row)
    if slot then
        H.click_slot(lane, lane_index, row, slot)
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
    -- Every lane plus the envelope lanes under it. Upright they are columns of
    -- their own beside the track's; on its side they are rows underneath it,
    -- which is where the arrange puts them.
    local holders = H.holders()
    local columns = sideways and (L.rows + 1) or (#holders + 1)
    -- The table owns both scroll directions, which is what lets it freeze the
    -- first column and the header row: a frozen row is only possible when the
    -- table is the thing scrolling, not the window around it.
    local flags = r.ImGui_TableFlags_SizingFixedFit()
        | r.ImGui_TableFlags_ScrollX() | r.ImGui_TableFlags_ScrollY()
    local hidden = UI.hide_scrollbar and UI.hide_scrollbar() or false
    if hidden and r.ImGui_StyleVar_ScrollbarSize then
        r.ImGui_PushStyleVar(UI.ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    end
    -- Set outright rather than taken from the theme: ImGui's own is 4 across
    -- and 2 down, which is uneven and roomier than a grid of clips wants. The
    -- row pitch that follows from it is measured, not assumed, so the rows keep
    -- lining up with the track heights whatever this is set to.
    local padded = false
    if r.ImGui_StyleVar_CellPadding then
        local gap = UI.rounded(C.cell_gap)
        r.ImGui_PushStyleVar(UI.ctx, r.ImGui_StyleVar_CellPadding(), gap, gap)
        padded = true
    end
    if r.ImGui_BeginTable(UI.ctx, "launcher_grid", columns, flags) then
        local head_w = UI.rounded(sideways and C.cell_w or C.scene_w)
        r.ImGui_TableSetupColumn(UI.ctx, "##head", r.ImGui_TableColumnFlags_WidthFixed(), head_w)
        if sideways then
            for index = 1, L.rows do
                r.ImGui_TableSetupColumn(UI.ctx, "##col" .. index,
                    r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(C.cell_w))
            end
        else
            for index, holder in ipairs(holders) do
                -- An envelope lane is narrower than a track lane: it holds
                -- curves, and it reads as something hanging off its neighbour.
                local wide = H.is_env_lane(holder) and math.floor(C.cell_w * 0.66) or C.cell_w
                r.ImGui_TableSetupColumn(UI.ctx, "##col" .. index,
                    r.ImGui_TableColumnFlags_WidthFixed(), UI.rounded(wide))
            end
        end
        if r.ImGui_TableSetupScrollFreeze then r.ImGui_TableSetupScrollFreeze(UI.ctx, 1, 1) end
        H.wheel_scroll()
        H.handle_keys()
        r.ImGui_TableNextRow(UI.ctx)
        r.ImGui_TableNextColumn(UI.ctx)
        -- Turned on its side a lane header is as tall as a clip row, with room
        -- to spare for the fader strip. Upright it is one cell tall, which is
        -- not, so it gets that strip added on when the fader is switched on.
        local head_extra = (not sideways and L.lane_volume) and UI.rounded(18) or 0
        local head_h = UI.rounded(C.cell_h) + head_extra
        H.draw_grid_corner(head_w, head_h + H.align_offset())
        if sideways then
            -- Scenes across the top, one clip column each.
            for row = 1, L.rows do
                r.ImGui_TableNextColumn(UI.ctx)
                H.draw_scene_cell(row, UI.rounded(C.cell_w), UI.rounded(C.cell_h))
            end
            H.sync_scroll()
            L.last_row_y, L.last_row_height = nil, nil
            for lane_index, lane in ipairs(L.lanes) do
                local drawn = H.lane_draw_height(H.lane_body_height(lane))
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
                for sub_index, sub in ipairs(lane.envs or {}) do
                    local sub_drawn = H.lane_draw_height(H.env_row_height(sub))
                    local sub_id = H.env_lane_id(lane_index, sub_index)
                    r.ImGui_TableNextRow(UI.ctx)
                    r.ImGui_TableNextColumn(UI.ctx)
                    local _, sub_y = r.ImGui_GetCursorScreenPos(UI.ctx)
                    H.note_row_pitch(sub_y, sub_drawn)
                    r.ImGui_PushID(UI.ctx, sub_id)
                    H.draw_env_header(sub, lane_index .. "_" .. sub_index, head_w, sub_drawn)
                    r.ImGui_PopID(UI.ctx)
                    for row = 1, L.rows do
                        r.ImGui_TableNextColumn(UI.ctx)
                        r.ImGui_PushID(UI.ctx, sub_id * 1000 - row)
                        H.draw_cell(sub, sub_id, row, sub_drawn)
                        r.ImGui_PopID(UI.ctx)
                    end
                end
            end
            local tail = H.tail_gap()
            if tail > 0 then
                r.ImGui_TableNextRow(UI.ctx)
                r.ImGui_TableNextColumn(UI.ctx)
                r.ImGui_Dummy(UI.ctx, head_w, tail)
            end
        else
            local lane_index, sub_index = 0, 0
            local ids = {}
            for index, holder in ipairs(holders) do
                if H.is_env_lane(holder) then
                    sub_index = sub_index + 1
                    ids[index] = H.env_lane_id(lane_index, sub_index)
                else
                    lane_index, sub_index = lane_index + 1, 0
                    ids[index] = lane_index
                end
            end
            for index, holder in ipairs(holders) do
                r.ImGui_TableNextColumn(UI.ctx)
                r.ImGui_PushID(UI.ctx, ids[index])
                if H.is_env_lane(holder) then
                    H.draw_env_header(holder, tostring(index),
                        UI.rounded(math.floor(C.cell_w * 0.66)), head_h)
                else
                    H.draw_lane_header(holder, ids[index], UI.rounded(C.cell_w), head_h)
                end
                r.ImGui_PopID(UI.ctx)
            end
            for row = 1, L.rows do
                r.ImGui_TableNextRow(UI.ctx)
                r.ImGui_TableNextColumn(UI.ctx)
                H.draw_scene_cell(row)
                for index, holder in ipairs(holders) do
                    r.ImGui_TableNextColumn(UI.ctx)
                    r.ImGui_PushID(UI.ctx, ids[index] * 1000 + row)
                    H.draw_cell(holder, ids[index], row, nil,
                        H.is_env_lane(holder) and UI.rounded(math.floor(C.cell_w * 0.66)) or nil)
                    r.ImGui_PopID(UI.ctx)
                end
            end
        end
        r.ImGui_EndTable(UI.ctx)
    end
    H.draw_chrome_popup()
    H.draw_fx_popup()
    if padded then r.ImGui_PopStyleVar(UI.ctx) end
    if hidden and r.ImGui_StyleVar_ScrollbarSize then r.ImGui_PopStyleVar(UI.ctx) end
    -- Cleared after every cell has had its chance to see the release.
end

-- Read and set from the Settings window, which lives in the main script.
function Launcher.color_headers()
    return L.color_headers and true or false
end

function Launcher.record_tidy()
    return L.record_tidy and true or false
end

function Launcher.set_record_tidy(value)
    L.record_tidy = value and true or false
    r.SetExtState(C.ext_section, "record_tidy", L.record_tidy and "1" or "0", true)
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

function Launcher.chord_status()
    local track = H.guide_track()
    if not track then return "", "" end
    local current, next_chord = H.guide_at(H.schedule_pos() or r.GetCursorPosition())
    local text = current and current.name or "-"
    if next_chord then text = text .. "  >  " .. next_chord.name end
    local tooltip = "Guide: " .. H.track_name(track, "Track")
        .. "\nCurrent: " .. (current and current.name or "no recognized chord")
        .. "\nNext: " .. (next_chord and next_chord.name or "-")
    return text, tooltip
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
    -- The pads keep whatever they were last told, so they are cleared and the
    -- device put back the way it was found.
    H.lp_stop()
    if not L.active then return end
    H.reset_all()
    L.active = false
end

return Launcher
