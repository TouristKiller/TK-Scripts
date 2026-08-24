-- @description TK Project Clips
-- @author TouristKiller
-- @version 0.3.0
-- @changelog:
--   + Added a Launcher view that plays clips as a quantized clip grid, so a project can be jammed with like a session view instead of only browsed
--   + Launcher lanes are hidden tracks that send into a real project track, which keeps every clip running through that track's own FX chain and routing
--   + Launcher clips play along with the song on the project's own bar grid, and a launched clip only takes over its own track, so every other track keeps playing the arrangement
--   + Launcher clips are scheduled onto the timeline ahead of the play cursor instead of being muted in real time, so switching clips lands exactly on the bar
--   + Added a Launcher "Mute song" toggle that silences the whole arrangement while the clips keep playing, which muting the tracks themselves cannot do because the clips arrive on a send
--   + Fixed Launcher mutes only covering items past the switching point, which left everything earlier in the song audible and showed up as half a track being muted and the other half not, most visibly after an arrangement loop came round
--   + Launcher mutes now leave items the user muted themselves untracked, so handing a track back can never unmute something that was already off
--   + Launcher Reset now also drains the stored mute mirror, so items whose bookkeeping was lost still get their original state back
--   + Added a per lane "A" button that mutes only that track's arrangement while its clips stay audible, for taking one track out of the song without taking the whole song out
--   + Added a Launcher Reset button that puts everything the launcher touched back at once, which is the recovery route when a lane, a mute or a takeover is left in an unexpected state
--   + Launcher lane tracks are kept at the end of the track list, so a track added while the launcher is open no longer lands behind the hidden tracks and leaves a gap in the visible track numbering
--   + Launcher lane tracks are gathered under one hidden "TK LAUNCHER" folder track, so making them visible shows a single collapsible group instead of a row of loose tracks
--   + Added a Launcher "Show tracks" toggle that reveals the TK LAUNCHER folder and its lanes in the arrange view for inspection, reading its state from the tracks so it stays honest if they are toggled from the Track Manager
--   + A Launcher lane whose track was deleted is now marked as dead straight away, cannot be launched, and can be cleared with one button, instead of silently sitting there until the project is reopened
--   + A clip that has gone from the project, by undo or by hand, is marked as such in its slot and refuses to launch, rather than sitting there looking playable; it is deliberately not removed, because redoing brings the clip back and an emptied slot would not
--   + Dead Launcher lanes are deliberately not removed automatically, because undoing the track deletion brings the track back under the same id and the lane keeps working, while an automatic removal would have thrown its clips away
--   + Added a Launcher "+ Scene" button that takes a slice of the arrangement at the edit cursor into a scene row, creating a lane for every track that has an item there, so a section of a song becomes playable in one click
--   + The Launcher grid can be played from the keyboard: number keys launch scenes, three rows of letters launch the first eight lanes like a pad controller, arrows move an outlined cell and Enter fires it, and holding Shift turns any of those into a stop
--   + Delete or Backspace empties the outlined Launcher slot, through the undo history so a mistaken press is one Ctrl+Z away
--   + Launcher grid keys are ignored while Ctrl or Alt is held, so a shortcut stays a shortcut: Ctrl+Z was launching whatever sat on the Z key instead of undoing
--   + Ctrl+Z, Ctrl+Y and Ctrl+Shift+Z are passed on to REAPER from the Launcher, which otherwise never sees them while the window has focus
--   + Each clip and scene tooltip names the key that fires it, because a shortcut nobody can see does not exist
--   + Added follow actions per scene: a scene plays a set number of times and then moves on to the next, previous, first, random or itself, so a grid of scenes plays a song by itself
--   + Added follow actions per clip as well, moving on within their own lane, so one column can work its way through its clips while the rest of the grid is left alone
--   + A clip's round is measured by what it actually is: a loop by its loop length, a retriggering one-shot by the bar its pattern spans, and a plain one-shot by its own length
--   + Added a Follow switch that stops scenes moving on by themselves without clearing what they were set to, so a scene can be auditioned on its own while the chain stays intact
--   + A scene reached through a follow action now reports what it started and stopped, the same as one launched by hand, instead of only naming itself
--   + A launched Launcher clip now starts at full level: its fade in is cleared and its auto-fade is switched off outright, where before it was set to a zero length that REAPER recalculated back to its default on the next edit, easing every clip in
--   + Launcher clips created during playback are now announced to REAPER as finished items rather than only refreshing the arrange, so the audio engine sees them in time to have their start buffered
--   + Added a Launcher lead setting for how far ahead a clip is put on the timeline before it plays, because a clip created too close to its boundary misses the start of its own audio; a launch that cannot make that deadline now waits for the next boundary rather than coming in late
--   + The Launcher lead defaults to Auto, derived from REAPER's own media buffer size, since that buffer is what decides how much run-up a clip needs; the tooltip reports the buffer it read and the figure it arrived at
--   + Added a Launcher media buffer panel that explains what the buffer does to launch response, sets it to a chosen value, and can put back the value it had before the launcher ever touched it, since it is a global REAPER preference rather than project data
--   + Launch quantize, clip run-up and the media buffer are gathered behind one Timing button, which carries the current quantize in its label since that is the one reached for mid-jam
--   + The Launcher now mutes the song by default when it opens and remembers that choice per project, since jamming over a silent arrangement is the common case
--   + Added a "Write scene chain to arrangement" command that walks those same follow actions without playing them and writes the result at the edit cursor, bounded by a length in bars, so the arrangement can never disagree with what the launcher plays
--   + Writing a retriggering one-shot into the arrangement now lays down the whole pattern instead of a single hit at the start of the scene, so what is written matches what the launcher plays
--   + Renamed the two write commands to say plainly which writes one scene and which follows the chain, since the difference was easy to miss
--   + Added a gain slider per clip that takes effect while the clip is playing, because clips gathered from different sources go through one track and often sit a long way apart in level
--   + Launching a Launcher scene now stops the lanes that have no clip in that row, so a scene behaves as a section of the song instead of letting the previous scene play through it
--   + Fixed Launcher clips blinking forever without starting when they were launched in the last bar of an arrangement loop: the boundary they waited for lay at the loop end, which the transport jumps back before ever reaching, so such a launch is now carried over to the top of the next pass
--   + Launcher scene rows show their length in bars, taken from the longest clip in the row rounded up, which is the span every clip in that scene needs before it has come round once
--   + Launcher scenes and single clips can be written back into the arrangement at the edit cursor, each clip landing on its own track, and the cursor parks at the end so scenes can be chained into a song
--   + Added recording of a live performance: armed, the clips you play are kept rather than cleared away when they finish, and afterwards the take can be kept onto its own tracks or discarded
--   + Recording needed almost no machinery because a playing clip is already an item at the right place in time, so what is recorded is exactly what was heard, including loop lengths and retriggered hits
--   + Keeping a recorded take now also hands over the mutes on the tracks it landed on, so the arrangement it replaced stays out of the way instead of being restored on the next Reset and playing on top of the recording
--   + Stopping a Launcher recording now also captures the clips that are still playing, up to the point reached, instead of only the ones that had already finished, which is why a take could come out empty
--   + Stopping a Launcher recording lets the bar finish rather than cutting the take off mid bar, and trims everything in it to that same line so the take is a whole number of bars; pressing stop again ends it immediately
--   + Fixed Launcher recording losing everything that finished during the take, which is every clip a scene change replaced, so recording a run of scenes kept only whatever happened to be playing when it was stopped
--   + Fixed a retriggered one-shot being recorded as only its last few hits: spent hits are cleared on their own path rather than through the harvest, which recording was not honouring
--   + The Launcher record button counts the clips still sounding as well as the ones already gathered, since a clip that has not finished yet is part of the take too and a counter stuck on zero reads as recording not working
--   + Each lane header shows how much of the take it has contributed while recording, with a plus for a clip still sounding, so a lane that stops contributing shows up while it happens instead of after the take is kept
--   + A clip that could not be captured when a recording stopped is now reported instead of quietly missing from the take
--   + Launcher clips can be dragged straight onto the arrange view, landing on the track and position under the mouse, reusing the same drop hit test and snap the Items view already used
--   + While dragging a Launcher clip onto the arrange the edit cursor follows the snapped drop position as a landing marker, with the target track and bar shown underneath, and it is put back if the drag is cancelled
--   + Dragging a Launcher clip onto the arrange is done with Alt held, which keeps it apart from launching: both gestures start with the same press, and with the transport stopped a clip is already playing before a drag can be recognised
--   + Alt-dragging a Launcher clip onto another slot moves it there, across lanes as well as rows, with Ctrl held to copy instead, so a grid can be rearranged without clearing and refilling slots
--   + Releasing an Alt-drag over the launcher window itself no longer drops the clip into the arrange underneath it
--   + Looping clips written to the arrangement all take the scene length, so the short ones loop until the longest clip in that scene has come round once
--   + Launcher clips launched inside an arrangement loop now keep playing when the loop comes round, and start cleanly at the loop point on every following pass, instead of falling silent until the play cursor returned to where the clip was launched
--   + Launcher cells now draw the clip itself, reusing the waveform and MIDI previews from the Items view, with a Compact toggle for a dense name-only grid
--   + Clips can be renamed and given a colour, either from twelve swatches or picked freely, which the cell, its waveform and its play marker all follow, falling back to the track colour when none is set
--   + The Launcher grid scrolls in both directions once it no longer fits, with scrollbars of its own, shift or ctrl plus the wheel for sideways, and both the scene column and the lane headers frozen so you can always see which row and which track you are looking at
--   + The "hide content scrollbar" setting now applies to the Launcher grid as well
--   + Lane columns used to be squeezed into the available width instead of overflowing, which is why there was nothing to scroll
--   + The play position bar on a playing Launcher clip is now readable and has a strip of its own along the bottom of the cell: it used to be a hairline in the same colour as the cell it was drawn on, running straight through the clip name
--   + The play position bar and the scene length now follow how often a clip actually comes round rather than how long its item is, which differ whenever a loop was stretched out in the arrangement: a one bar loop dragged to four bars still repeats every bar
--   + Clip lengths are read from the clip itself whenever they are needed instead of being remembered from when it was added, so a project tempo change no longer leaves the play position bar, the scene length and the moment scenes switch working from stale figures
--   + Launcher slots now take clips from anywhere: drag a file in from TK Media Browser or the Workbench media browser, drop one from REAPER's Media Explorer or Explorer onto a floating window, or pick a file from the slot menu
--   + Launcher file drags from the TK browsers use the ExtState drag protocol rather than an OS drag, so dropping a clip keeps working while the window is docked
--   + Launcher audio dropped in from a file is stretched to the project tempo with pitch preserved, reading the tempo from the file's metadata or its name, because the media browser's own tempo sync never runs when the launcher builds the item itself
--   + Added a per clip "Retrigger every" setting from 1/16 to 2 bars, so a one-shot such as a kick can be played in time even though tempo matching cannot help a sample that has no tempo of its own; each hit is placed ahead of the play cursor and is as exact as a launch
--   + A retriggering one-shot can now fire on chosen steps of the bar rather than on every one, so a snare can sit on two and four; the steps are anchored to the project grid, so the pattern lands the same way whenever it is started
--   + Fixed a retriggered one-shot staying silent for its first bar: its repeats were only scheduled once the clip started, giving the earliest of them no run-up, so they are now put down at the same moment the clip itself is
--   + A clip added from a trimmed arrange item now loops the trimmed length instead of the whole source, so the clip is what the arrange showed rather than what the source happens to contain: audio is wrapped in a section and MIDI is rendered into a new in-project source, neither of which touches the item it came from
--   + Fixed clips and voices being created already selected, inherited from the item they were copied from, which made a following "add selected item(s)" pick up the launcher's own copies and fill an extra row for every clip already added
--   + Fixed a trimmed MIDI clip never being shortened at all: whether an in-project MIDI item is trimmed cannot be read from its source length, because REAPER reports that as the item's own length, so the check always said no. MIDI clips are now rendered to a fresh source unconditionally, which is a no-op when nothing was trimmed
--   + Rendering a MIDI clip now shows its hidden lane track for the length of the operation, because a REAPER action will not touch an item on a track it cannot see, and moves the clip clear of the others first so the render can never take in the clip stacked beside it
--   + Launcher clips are now stored stacked at the start of the project instead of spread out an hour past the end, so a hidden lane track never reaches further than its longest single clip and adding clips no longer stretches the project length, the arrange scrollbar or a render set to project length
--   + Launcher voices claim a few minutes of timeline at a time and grow while they play, instead of reserving an hour the moment a clip is launched
--   + Launcher mirrors the mute states it changes into the project, so an interrupted session hands the arrangement back on the next load instead of leaving tracks silent
--   + That mirror is now merged rather than overwritten, so losing track of a mute in memory, by a project switch or a kept take, no longer erases the only record of it and leave items muted with no way back
--   + Reset reports how many muted items it put back, or says plainly that there was nothing left to restore
--   + Added smart clip-state filters and persistent sorting for Items and Source Media
--   + Added preview volume, loop preview and optional hidden content scrollbar
--   + Added Source Media selection of all uses, batch clip renaming and missing-media relinking
--   + Improved compact toolbar, Settings layout, track collapse toggle and Escape-key closing
--   + Added live missing-media detection and visual warnings for source and item cards
--   + Fixed conflicting ImGui IDs in clip and source cards
--   + Added standalone theme engine with presets, custom themes and UI scaling
--   + Added Source Media view, item preview and arrange drag-and-drop
--   + Added multi-selection with pooled MIDI, loop, mute, lock and delete actions

local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local separator = package.config:sub(1, 1)
local module_path = script_path .. "TK_PROJECT_CLIPS" .. separator
package.path = module_path .. "?.lua;" .. package.path

local json = require("json")
local Theme = require("theme")
local UIScale = require("ui_scale")
local Launcher = require("launcher")

local config_path = script_path .. "TK_PROJECT_CLIPS_SETTINGS.json"

local function load_config()
    local config = { theme_preset = "Graphite", custom_themes = {}, custom_theme_name = "My Theme" }
    local file = io.open(config_path, "r")
    if not file then return config end
    local content = file:read("*a")
    file:close()
    local ok, decoded = pcall(json.decode, content)
    if not ok or type(decoded) ~= "table" then return config end
    if type(decoded.theme_preset) == "string" then config.theme_preset = decoded.theme_preset end
    if type(decoded.custom_themes) == "table" then config.custom_themes = decoded.custom_themes end
    if type(decoded.custom_theme_name) == "string" then config.custom_theme_name = decoded.custom_theme_name end
    return config
end

local function save_config(config)
    local ok, encoded = pcall(json.encode, config)
    if not ok or not encoded then return false end
    local file = io.open(config_path, "w")
    if not file then return false end
    file:write(encoded .. "\n")
    file:close()
    return true
end

local project_clips_settings = load_config()

local SCRIPT_NAME = "TK Project Clips"
local CARD_WIDTH = 220
local CARD_HEIGHT = 136
local PREVIEW_HEIGHT = 82
local PEAK_COUNT = 112
local EXT_SECTION = "TK_PROJECT_CLIPS"
local theme_preset = Theme.set_preset(project_clips_settings.theme_preset or "Graphite", project_clips_settings.custom_themes)
local UI_SCALE_OPTIONS = {
    { label = "85%", value = 0.85 },
    { label = "100%", value = 1.0 },
    { label = "115%", value = 1.15 },
    { label = "130%", value = 1.3 },
    { label = "150%", value = 1.5 },
    { label = "175%", value = 1.75 },
    { label = "200%", value = 2.0 },
}
local THEME_COLOR_FIELDS = {
    { key = "window_bg", label = "Window" },
    { key = "child_bg", label = "Panel" },
    { key = "popup_bg", label = "Popup" },
    { key = "frame_bg", label = "Frame" },
    { key = "frame_hover", label = "Frame Hover" },
    { key = "header", label = "Header" },
    { key = "header_hover", label = "Header Hover" },
    { key = "separator", label = "Separator" },
    { key = "border", label = "Border" },
    { key = "text", label = "Text" },
    { key = "text_dim", label = "Dim Text" },
    { key = "badge_text", label = "Badge Text" },
    { key = "accent", label = "Accent" },
    { key = "accent_soft", label = "Accent Soft" },
    { key = "warning", label = "Warning" },
    { key = "danger", label = "Danger" },
}

local COLORS = {
    window_bg = Theme.colors.window_bg,
    child_bg = Theme.colors.child_bg,
    card_bg = Theme.colors.frame_bg,
    card_hover = Theme.colors.frame_hover,
    card_selected = Theme.colors.header,
    border = Theme.colors.border,
    text = Theme.colors.text,
    text_dim = Theme.colors.text_dim,
    badge_text = Theme.colors.badge_text,
    accent = Theme.colors.accent,
    accent_soft = Theme.colors.accent_soft,
    audio = 0x73C6A3FF,
    midi = Theme.colors.warning,
    danger = Theme.colors.danger,
    grid = (Theme.colors.separator & 0xFFFFFF00) | 0x28,
}

local saved_color_mode = r.GetExtState(EXT_SECTION, "color_mode")
if saved_color_mode == "" then
    saved_color_mode = r.GetExtState(EXT_SECTION, "use_track_colors") == "0" and "type" or "peaks"
end

local saved_status_filter = r.GetExtState(EXT_SECTION, "status_filter")
if not ({ all = true, pooled = true, looped = true, muted = true, locked = true })[saved_status_filter] then saved_status_filter = "all" end
local saved_item_sort = r.GetExtState(EXT_SECTION, "item_sort")
if not ({ position = true, name = true, length = true })[saved_item_sort] then saved_item_sort = "position" end
local saved_source_sort = r.GetExtState(EXT_SECTION, "source_sort")
if not ({ name = true, uses = true, length = true, type = true })[saved_source_sort] then saved_source_sort = "name" end
local saved_view_mode = r.GetExtState(EXT_SECTION, "view_mode")
if not ({ items = true, sources = true, launcher = true })[saved_view_mode] then saved_view_mode = "items" end

local state = {
    open = true,
    view_mode = saved_view_mode,
    search = "",
    filter = "all",
    status_filter = saved_status_filter,
    item_sort = saved_item_sort,
    source_sort = saved_source_sort,
    sort_descending = r.GetExtState(EXT_SECTION, "sort_descending") == "1",
    hide_content_scrollbar = r.GetExtState(EXT_SECTION, "hide_content_scrollbar") == "1",
    selected_track_only = false,
    snap = true,
    color_mode = saved_color_mode,
    position_mode = r.GetExtState(EXT_SECTION, "position_mode") == "time" and "time" or "bars",
    collapsed_tracks = {},
    items = {},
    groups = {},
    sources = {},
    waveform_cache = {},
    midi_cache = {},
    signature = "",
    last_scan = 0,
    media_availability_signature = "",
    last_media_availability_check = 0,
    drag = nil,
    drag_active = false,
    drag_source_selected = false,
    preview_guid = nil,
    preview_start = nil,
    preview_end = nil,
    preview_saved_cursor = nil,
    preview_base_volume = nil,
    preview_track_states = nil,
    preview_item_states = nil,
    preview_volume = tonumber(r.GetExtState(EXT_SECTION, "preview_volume")) or 100,
    loop_preview = r.GetExtState(EXT_SECTION, "loop_preview") == "1",
    suppress_drag_guid = nil,
    cache_budget = 0,
    status = "",
    theme_preset = theme_preset,
    theme_settings_open = false,
    ui_scale = tonumber(r.GetExtState(EXT_SECTION, "ui_scale")) or 1.0,
    ui_fonts = {},
}

if not r.ImGui_CreateContext then
    r.MB("ReaImGui is required.", SCRIPT_NAME, 0)
    return
end

if not r.BR_GetMediaItemGUID or not r.BR_GetMediaItemByGUID then
    r.MB("SWS Extension is required.", SCRIPT_NAME, 0)
    return
end

if not r.JS_Mouse_GetState or not r.JS_Window_FindChildByID then
    r.MB("js_ReaScriptAPI is required.", SCRIPT_NAME, 0)
    return
end

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local font = r.ImGui_CreateFont("sans-serif", 14)
r.ImGui_Attach(ctx, font)

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

state.ui_scale = clamp(state.ui_scale, 0.85, 2.0)
state.preview_volume = clamp(state.preview_volume, 0, 200)

for track_guid in r.GetExtState(EXT_SECTION, "collapsed_tracks"):gmatch("[^|]+") do
    state.collapsed_tracks[track_guid] = true
end

local function scaled(value)
    return (tonumber(value) or 0) * state.ui_scale
end

local function rounded(value)
    return math.floor(scaled(value) + 0.5)
end

local function ui_scale_label()
    for _, option in ipairs(UI_SCALE_OPTIONS) do
        if math.abs(state.ui_scale - option.value) < 0.01 then return option.label end
    end
    return tostring(math.floor(state.ui_scale * 100 + 0.5)) .. "%"
end

local function set_ui_scale(value)
    state.ui_scale = clamp(tonumber(value) or 1.0, 0.85, 2.0)
    r.SetExtState(EXT_SECTION, "ui_scale", tostring(state.ui_scale), true)
end

local function sync_theme_colors()
    COLORS.window_bg = Theme.colors.window_bg
    COLORS.child_bg = Theme.colors.child_bg
    COLORS.card_bg = Theme.colors.frame_bg
    COLORS.card_hover = Theme.colors.frame_hover
    COLORS.card_selected = Theme.colors.header
    COLORS.border = Theme.colors.border
    COLORS.text = Theme.colors.text
    COLORS.text_dim = Theme.colors.text_dim
    COLORS.badge_text = Theme.colors.badge_text
    COLORS.accent = Theme.colors.accent
    COLORS.accent_soft = Theme.colors.accent_soft
    COLORS.midi = Theme.colors.warning
    COLORS.danger = Theme.colors.danger
    COLORS.grid = (Theme.colors.separator & 0xFFFFFF00) | 0x28
end

local function apply_theme(name)
    state.theme_preset = Theme.set_preset(name, project_clips_settings.custom_themes)
    project_clips_settings.theme_preset = state.theme_preset
    sync_theme_colors()
    if not save_config(project_clips_settings) then state.status = "Could not save theme settings" end
end

local function theme_names()
    local names = {}
    for _, name in ipairs(Theme.get_preset_names()) do names[#names + 1] = name end
    local custom_names = {}
    for name in pairs(project_clips_settings.custom_themes or {}) do custom_names[#custom_names + 1] = name end
    table.sort(custom_names, function(first, second) return first:lower() < second:lower() end)
    for _, name in ipairs(custom_names) do names[#names + 1] = name end
    return names
end

local function save_collapsed_tracks()
    local track_guids = {}
    for track_guid, collapsed in pairs(state.collapsed_tracks) do
        if collapsed then track_guids[#track_guids + 1] = track_guid end
    end
    table.sort(track_guids)
    r.SetExtState(EXT_SECTION, "collapsed_tracks", table.concat(track_guids, "|"), true)
end

local function set_all_tracks_collapsed(collapsed)
    state.collapsed_tracks = {}
    if collapsed then
        for track_index = 0, (r.CountTracks(0) or 0) - 1 do
            local track = r.GetTrack(0, track_index)
            local track_guid = track and r.GetTrackGUID(track) or nil
            if track_guid then state.collapsed_tracks[track_guid] = true end
        end
    end
    save_collapsed_tracks()
end

local function all_tracks_collapsed()
    local track_count = r.CountTracks(0) or 0
    if track_count == 0 then return false end
    for track_index = 0, track_count - 1 do
        local track = r.GetTrack(0, track_index)
        local track_guid = track and r.GetTrackGUID(track) or nil
        if track_guid and not state.collapsed_tracks[track_guid] then return false end
    end
    return true
end

local function get_scaled_font()
    local font_size = math.max(10, math.floor(14 * state.ui_scale + 0.5))
    if state.ui_fonts[font_size] then return state.ui_fonts[font_size], font_size end
    local ok, scaled_font = pcall(r.ImGui_CreateFont, "sans-serif", font_size)
    if not ok or not scaled_font then return nil end
    pcall(r.ImGui_Attach, ctx, scaled_font)
    state.ui_fonts[font_size] = scaled_font
    return scaled_font, font_size
end

local function push_scaled_font()
    local scaled_font, font_size = get_scaled_font()
    if not scaled_font then return false end
    return pcall(r.ImGui_PushFont, ctx, scaled_font, font_size)
end

local function set_action_state(enabled)
    local _, _, section_id, command_id = r.get_action_context()
    if section_id and command_id and command_id > 0 then
        r.SetToggleCommandState(section_id, command_id, enabled and 1 or 0)
        r.RefreshToolbar2(section_id, command_id)
    end
end

local function item_from_guid(guid)
    if not guid or guid == "" then return nil end
    return r.BR_GetMediaItemByGUID(0, guid)
end

local function get_take_name(take, fallback)
    if not take then return fallback end
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    if name and name ~= "" then return name end
    local source = r.GetMediaItemTake_Source(take)
    local path = source and r.GetMediaSourceFileName(source, "") or ""
    local file_name = path and path:match("([^/\\]+)$") or nil
    return file_name and file_name ~= "" and file_name or fallback
end

local function get_track_name(track, index)
    local _, name = r.GetTrackName(track)
    if name and name ~= "" then return name end
    return "Track " .. tostring(index + 1)
end

-- Hidden launcher lane tracks hold the clip library and the voices the launcher
-- spawns; they must never show up as regular project clips.
local launcher_track_cache = {}
local function is_launcher_track(track)
    if not track then return false end
    local cached = launcher_track_cache[track]
    if cached ~= nil then return cached end
    local ok, value = r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_CLIP_LAUNCHER", "", false)
    local flagged = ok and value == "1" or false
    launcher_track_cache[track] = flagged
    return flagged
end

local function native_color(native, fallback)
    if not native or native == 0 then return fallback end
    local red, green, blue = r.ColorFromNative(native)
    return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | 0xFF
end

local function format_length(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds < 10 then return string.format("%.2fs", seconds) end
    if seconds < 60 then return string.format("%.1fs", seconds) end
    return string.format("%d:%02d", math.floor(seconds / 60), math.floor(seconds % 60))
end

local function format_position_time(seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    local minutes = math.floor(seconds / 60)
    return string.format("%d:%05.2f", minutes, seconds - minutes * 60)
end

local function format_position_bars(seconds)
    if not r.TimeMap2_timeToBeats then return format_position_time(seconds) end
    local ok, beat_position, measures, measure_length = pcall(r.TimeMap2_timeToBeats, 0, tonumber(seconds) or 0)
    if not ok or beat_position == nil then return format_position_time(seconds) end
    local measure = math.floor(tonumber(measures) or 0) + 1
    local beat_value = math.max(0, tonumber(beat_position) or 0)
    local beat = math.floor(beat_value) + 1
    local tick = math.floor(((beat_value % 1) * 960) + 0.5)
    if tick >= 960 then beat = beat + 1; tick = 0 end
    local beats_in_measure = math.floor(tonumber(measure_length) or 0)
    if beats_in_measure > 0 and beat > beats_in_measure then measure = measure + 1; beat = 1 end
    return string.format("%d.%d.%03d", measure, beat, tick)
end

local function format_position(seconds)
    return state.position_mode == "time" and format_position_time(seconds) or format_position_bars(seconds)
end

local function pooled_midi_item(item, is_midi)
    if not is_midi then return false end
    local take = r.GetActiveTake(item)
    if take and r.BR_GetMidiTakePoolGUID then
        local pooled, pool_guid = r.BR_GetMidiTakePoolGUID(take)
        return pooled and pool_guid ~= nil and pool_guid ~= ""
    end
    if not r.GetItemStateChunk then return false end
    local ok, chunk = r.GetItemStateChunk(item, "", false)
    return ok and chunk and chunk:find("POOLEDEVTS", 1, true) ~= nil or false
end

local function source_identity(take, is_midi)
    local source = r.GetMediaItemTake_Source(take)
    if not source then return nil end
    local path = ""
    local current_source = source
    for _ = 1, 8 do
        local ok, current_path = pcall(r.GetMediaSourceFileName, current_source, "")
        if ok and current_path and current_path ~= "" and current_path:sub(1, 1) ~= "<" then path = current_path; break end
        if not r.GetMediaSourceParent then break end
        local parent_ok, parent = pcall(r.GetMediaSourceParent, current_source)
        if not parent_ok or not parent or parent == current_source then break end
        current_source = parent
    end
    local source_type = r.GetMediaSourceType(source, "") or (is_midi and "MIDI" or "MEDIA")
    if is_midi then
        if r.BR_GetMidiTakePoolGUID then
            local pooled, pool_guid = r.BR_GetMidiTakePoolGUID(take)
            if pooled and pool_guid and pool_guid ~= "" then return "midi:pool:" .. pool_guid, path, source_type end
        end
        local take_guid = r.BR_GetMediaItemTakeGUID and r.BR_GetMediaItemTakeGUID(take) or tostring(take)
        return "midi:take:" .. tostring(take_guid), path, source_type
    end
    local key = path ~= "" and "file:" .. path:lower() or "source:" .. source_type .. ":" .. tostring(source)
    return key, path, source_type
end

local function media_file_exists(path)
    if not path or path == "" then return true end
    if r.file_exists then return r.file_exists(path) end
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function media_availability_signature()
    local availability = {}
    for item_index = 0, (r.CountMediaItems(0) or 0) - 1 do
        local item = r.GetMediaItem(0, item_index)
        local take = item and r.GetActiveTake(item) or nil
        if take and not r.TakeIsMIDI(take) then
            local _, path = source_identity(take, false)
            if path and path ~= "" then availability[#availability + 1] = path:lower() .. "=" .. (media_file_exists(path) and "1" or "0") end
        end
    end
    table.sort(availability)
    return table.concat(availability, "|")
end

local function item_signature(item, take)
    return table.concat({
        tostring(r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0),
        tostring(r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0),
        tostring(r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1),
    }, "|")
end

local function project_signature()
    local project, project_path = r.EnumProjects(-1, "")
    return table.concat({
        tostring(project),
        tostring(project_path),
        tostring(r.GetProjectStateChangeCount(0) or 0),
        tostring(r.CountMediaItems(0) or 0),
    }, "|")
end

local function scan_project()
    local items = {}
    local groups = {}
    local sources_by_key = {}
    local selected_track = r.GetSelectedTrack(0, 0)
    local search = state.search:lower()
    local item_count = r.CountMediaItems(0) or 0
    launcher_track_cache = {}

    for index = 0, item_count - 1 do
        local item = r.GetMediaItem(0, index)
        local take = item and r.GetActiveTake(item) or nil
        local track = item and r.GetMediaItemTrack(item) or nil
        if take and track and not is_launcher_track(track) then
            local is_midi = r.TakeIsMIDI(take)
            local type_matches = state.filter == "all" or (state.filter == "audio" and not is_midi) or (state.filter == "midi" and is_midi)
            local track_matches = not state.selected_track_only or track == selected_track
            local track_index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 1) - 1
            local name = get_take_name(take, is_midi and "MIDI item" or "Audio item")
            local search_matches = search == "" or name:lower():find(search, 1, true) or get_track_name(track, track_index):lower():find(search, 1, true)
            local looped = (r.GetMediaItemInfo_Value(item, "B_LOOPSRC") or 0) > 0.5
            local pooled = pooled_midi_item(item, is_midi)
            local muted = (r.GetMediaItemInfo_Value(item, "B_MUTE") or 0) > 0.5
            local locked = (r.GetMediaItemInfo_Value(item, "C_LOCK") or 0) > 0.5
            local source_key, source_path, source_type = source_identity(take, is_midi)
            local source_missing = not is_midi and source_path ~= "" and not media_file_exists(source_path)
            local status_matches = state.status_filter == "all"
                or state.status_filter == "pooled" and pooled
                or state.status_filter == "looped" and looped
                or state.status_filter == "muted" and muted
                or state.status_filter == "locked" and locked
            if type_matches and track_matches then
                if source_key then
                    local guid = r.BR_GetMediaItemGUID(item)
                    local source_entry = sources_by_key[source_key]
                    if source_entry then
                        source_entry.usage_count = source_entry.usage_count + 1
                        source_entry.guids[#source_entry.guids + 1] = guid
                    else
                        local source = r.GetMediaItemTake_Source(take)
                        local source_length = source and select(1, r.GetMediaSourceLength(source)) or 0
                        local source_name = source_path ~= "" and (source_path:match("([^/\\]+)$") or name) or name
                        local track_native_color = r.GetTrackColor(track)
                        sources_by_key[source_key] = {
                            guid = guid,
                            guids = { guid },
                            source_key = source_key,
                            name = source_name,
                            path = source_path,
                            missing = source_missing,
                            source_type = source_type,
                            usage_count = 1,
                            is_midi = is_midi,
                            track_index = track_index,
                            track_name = get_track_name(track, track_index),
                            track_color = is_midi and COLORS.midi or COLORS.audio,
                            has_track_color = false,
                            position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0,
                            length = is_midi and (r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0) or source_length,
                            take_count = 1,
                            active_take = 1,
                            looped = false,
                            pooled = pooled,
                            selected = false,
                            cache_key = "source|" .. source_key .. "|" .. item_signature(item, take),
                        }
                    end
                end
            end
            if type_matches and track_matches and search_matches and status_matches then
                local guid = r.BR_GetMediaItemGUID(item)
                local track_name = get_track_name(track, track_index)
                local track_guid = r.GetTrackGUID(track)
                local track_native_color = r.GetTrackColor(track)
                local track_color = native_color(track_native_color, COLORS.accent)
                local take_count = r.CountTakes(item) or 1
                local entry = {
                    guid = guid,
                    name = name,
                    is_midi = is_midi,
                    track_index = track_index,
                    track_name = track_name,
                    source_key = source_key,
                    source_path = source_path,
                    missing = source_missing,
                    track_color = track_color,
                    has_track_color = track_native_color ~= 0,
                    position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0,
                    length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0,
                    take_count = take_count,
                    active_take = math.floor((r.GetMediaItemInfo_Value(item, "I_CURTAKE") or 0) + 1.5),
                    looped = looped,
                    pooled = pooled,
                    muted = muted,
                    locked = locked,
                    selected = r.IsMediaItemSelected(item),
                    cache_key = guid .. "|" .. item_signature(item, take),
                }
                items[#items + 1] = entry
                local group_key = tostring(track_index)
                if not groups[group_key] then
                    groups[group_key] = { index = track_index, guid = track_guid, name = track_name, color = track_color, items = {} }
                end
                groups[group_key].items[#groups[group_key].items + 1] = entry
            end
        end
    end

    local ordered_groups = {}
    for _, group in pairs(groups) do ordered_groups[#ordered_groups + 1] = group end
    table.sort(ordered_groups, function(left, right) return left.index < right.index end)
    for _, group in ipairs(ordered_groups) do
        table.sort(group.items, function(left, right)
            local left_value = state.item_sort == "name" and left.name:lower() or state.item_sort == "length" and left.length or left.position
            local right_value = state.item_sort == "name" and right.name:lower() or state.item_sort == "length" and right.length or right.position
            if left_value == right_value then return left.guid < right.guid end
            if state.sort_descending then return left_value > right_value end
            return left_value < right_value
        end)
    end
    local sources = {}
    for _, source_entry in pairs(sources_by_key) do
        local source_search = source_entry.name:lower() .. "\n" .. source_entry.path:lower() .. "\n" .. source_entry.source_type:lower()
        if search == "" or source_search:find(search, 1, true) then sources[#sources + 1] = source_entry end
    end
    table.sort(sources, function(left, right)
        local left_value = state.source_sort == "uses" and left.usage_count or state.source_sort == "length" and left.length or state.source_sort == "type" and left.source_type:lower() or left.name:lower()
        local right_value = state.source_sort == "uses" and right.usage_count or state.source_sort == "length" and right.length or state.source_sort == "type" and right.source_type:lower() or right.name:lower()
        if left_value == right_value then return left.source_key < right.source_key end
        if state.sort_descending then return left_value > right_value end
        return left_value < right_value
    end)
    state.items = items
    state.groups = ordered_groups
    state.sources = sources
end

local function refresh_if_needed()
    local now = r.time_precise()
    if now - state.last_scan < 0.2 then return end
    state.last_scan = now
    if now - state.last_media_availability_check >= 1 then
        state.last_media_availability_check = now
        local availability_signature = media_availability_signature()
        if availability_signature ~= state.media_availability_signature then
            state.media_availability_signature = availability_signature
            state.signature = ""
        end
    end
    local signature = table.concat({ project_signature(), state.search, state.filter, state.status_filter, state.item_sort, state.source_sort, tostring(state.sort_descending), tostring(state.selected_track_only) }, "|")
    if signature ~= state.signature then
        state.signature = signature
        scan_project()
    end
end

local function build_waveform(entry)
    local peak_count = math.max(48, rounded(PEAK_COUNT))
    local cache_key = entry.cache_key .. "|" .. tostring(peak_count)
    if state.waveform_cache[cache_key] ~= nil then return state.waveform_cache[cache_key] end
    if state.cache_budget <= 0 then return nil end
    state.cache_budget = state.cache_budget - 1
    local item = item_from_guid(entry.guid)
    local take = item and r.GetActiveTake(item) or nil
    if not take then return nil end
    local channels = math.max(1, math.min(2, math.floor(r.GetMediaSourceNumChannels(r.GetMediaItemTake_Source(take)) or 1)))
    local length = math.max(0.001, r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0.001)
    local peak_rate = peak_count / length
    local buffer = r.new_array(peak_count * channels * 2)
    buffer.clear()
    local result = r.GetMediaItemTake_Peaks(take, peak_rate, r.GetMediaItemInfo_Value(item, "D_POSITION") or 0, channels, peak_count, 0, buffer)
    local peaks = {}
    if result and result > 0 then
        for sample = 1, peak_count do
            local peak = 0
            for channel = 1, channels do
                local position = ((sample - 1) * channels) + channel
                peak = math.max(peak, math.abs(buffer[position] or 0), math.abs(buffer[(peak_count * channels) + position] or 0))
            end
            peaks[sample] = clamp(peak, 0, 1)
        end
    end
    if buffer.clear then buffer.clear() end
    state.waveform_cache[cache_key] = peaks
    return peaks
end

local function build_midi(entry)
    if state.midi_cache[entry.cache_key] ~= nil then return state.midi_cache[entry.cache_key] end
    if state.cache_budget <= 0 then return nil end
    state.cache_budget = state.cache_budget - 1
    local item = item_from_guid(entry.guid)
    local take = item and r.GetActiveTake(item) or nil
    if not take then return nil end
    local _, note_count = r.MIDI_CountEvts(take)
    local notes = {}
    local minimum_pitch, maximum_pitch = 127, 0
    local minimum_ppq, maximum_ppq = math.huge, -math.huge
    for note_index = 0, math.min(note_count or 0, 12000) - 1 do
        local ok, _, muted, start_ppq, end_ppq, _, pitch, velocity = r.MIDI_GetNote(take, note_index)
        if ok then
            notes[#notes + 1] = { start_ppq, end_ppq, pitch, velocity, muted }
            minimum_pitch = math.min(minimum_pitch, pitch)
            maximum_pitch = math.max(maximum_pitch, pitch)
            minimum_ppq = math.min(minimum_ppq, start_ppq)
            maximum_ppq = math.max(maximum_ppq, end_ppq)
        end
    end
    local data = {
        notes = notes,
        min_pitch = #notes > 0 and minimum_pitch or 60,
        max_pitch = #notes > 0 and maximum_pitch or 72,
        min_ppq = #notes > 0 and minimum_ppq or 0,
        max_ppq = #notes > 0 and maximum_ppq or 1,
    }
    state.midi_cache[entry.cache_key] = data
    return data
end

local function truncate_text(text, maximum_width)
    if r.ImGui_CalcTextSize(ctx, text) <= maximum_width then return text end
    local shortened = text
    while #shortened > 3 and r.ImGui_CalcTextSize(ctx, shortened .. "...") > maximum_width do
        shortened = shortened:sub(1, -2)
    end
    return shortened .. "..."
end

local function clip_color(entry, fallback)
    if state.color_mode == "peaks" and entry.has_track_color then return entry.track_color end
    if state.color_mode == "tiles" and entry.has_track_color then return 0x101216FF end
    return fallback
end

local function mix_color(first, second, amount)
    amount = clamp(amount, 0, 1)
    local inverse = 1 - amount
    local red = math.floor(((first >> 24) & 0xFF) * inverse + ((second >> 24) & 0xFF) * amount + 0.5)
    local green = math.floor(((first >> 16) & 0xFF) * inverse + ((second >> 16) & 0xFF) * amount + 0.5)
    local blue = math.floor(((first >> 8) & 0xFF) * inverse + ((second >> 8) & 0xFF) * amount + 0.5)
    return (red << 24) | (green << 16) | (blue << 8) | 0xFF
end

local function contrast_color(color, dimmed)
    local red = (color >> 24) & 0xFF
    local green = (color >> 16) & 0xFF
    local blue = (color >> 8) & 0xFF
    local luminance = red * 0.299 + green * 0.587 + blue * 0.114
    if luminance >= 142 then return dimmed and 0x20242ACC or 0x101216FF end
    return dimmed and 0xE8EBF0CC or 0xFFFFFFFF
end

local function inverse_tiles_active(entry)
    return state.color_mode == "tiles" and entry.has_track_color
end

local function clip_grid_color(entry)
    return inverse_tiles_active(entry) and 0x0000002E or COLORS.grid
end

local function clip_text_color(entry, dimmed)
    if inverse_tiles_active(entry) then return contrast_color(entry.track_color, dimmed) end
    return dimmed and COLORS.text_dim or COLORS.text
end

local function draw_audio_preview(draw_list, entry, x, y, width, height)
    local peaks = build_waveform(entry)
    local waveform_color = clip_color(entry, COLORS.audio)
    local center_y = y + height * 0.5
    r.ImGui_DrawList_AddLine(draw_list, x, center_y, x + width, center_y, clip_grid_color(entry), scaled(1))
    if not peaks or #peaks == 0 then
        r.ImGui_DrawList_AddText(draw_list, x + scaled(8), center_y - scaled(8), clip_text_color(entry, true), peaks and "No peaks" or "Loading...")
        return
    end
    local step = width / #peaks
    for index, peak in ipairs(peaks) do
        local px = x + (index - 0.5) * step
        local amplitude = peak * height * 0.43
        r.ImGui_DrawList_AddLine(draw_list, px, center_y - amplitude, px, center_y + amplitude, waveform_color, math.max(scaled(1), step * 0.7))
    end
end

local function draw_midi_preview(draw_list, entry, x, y, width, height)
    local data = build_midi(entry)
    local note_base_color = clip_color(entry, COLORS.midi)
    if not data then
        r.ImGui_DrawList_AddText(draw_list, x + scaled(8), y + height * 0.5 - scaled(8), clip_text_color(entry, true), "Loading...")
        return
    end
    if #data.notes == 0 then
        r.ImGui_DrawList_AddText(draw_list, x + scaled(8), y + height * 0.5 - scaled(8), clip_text_color(entry, true), "No MIDI notes")
        return
    end
    local min_pitch = math.max(0, data.min_pitch - 2)
    local max_pitch = math.min(127, data.max_pitch + 2)
    local pitch_range = math.max(1, max_pitch - min_pitch)
    local ppq_range = math.max(1, data.max_ppq - data.min_ppq)
    for pitch = math.floor(min_pitch / 12) * 12, max_pitch, 12 do
        if pitch >= min_pitch then
            local gy = y + height - ((pitch - min_pitch) / pitch_range) * height
            r.ImGui_DrawList_AddLine(draw_list, x, gy, x + width, gy, clip_grid_color(entry), scaled(1))
        end
    end
    for _, note in ipairs(data.notes) do
        local start_x = x + clamp((note[1] - data.min_ppq) / ppq_range, 0, 1) * width
        local end_x = x + clamp((note[2] - data.min_ppq) / ppq_range, 0, 1) * width
        local note_y = y + height - clamp((note[3] - min_pitch + 1) / pitch_range, 0, 1) * height
        local note_height = math.max(scaled(2), height / math.max(14, pitch_range + 3))
        local alpha = note[5] and 0x66 or clamp(math.floor((note[4] or 96) * 1.5 + 55), 0x70, 0xFF)
        local color = (note_base_color & 0xFFFFFF00) | alpha
        r.ImGui_DrawList_AddRectFilled(draw_list, start_x, note_y, math.max(start_x + scaled(2), end_x), note_y + note_height, color, scaled(1))
    end
end

-- The launcher reuses the card previews, but must not follow the Items view
-- colour mode: its cells are already tinted with the lane colour.
local function launcher_preview(draw_list, entry, x, y, width, height)
    local previous_mode = state.color_mode
    state.color_mode = "peaks"
    if entry.is_midi then
        draw_midi_preview(draw_list, entry, x, y, width, height)
    else
        draw_audio_preview(draw_list, entry, x, y, width, height)
    end
    state.color_mode = previous_mode
end

local function select_and_reveal(entry)
    local item = item_from_guid(entry.guid)
    if not item then return end
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    for _, current in ipairs(state.items) do current.selected = current.guid == entry.guid end
    local track = r.GetMediaItemTrack(item)
    if track then r.SetOnlyTrackSelected(track) end
    local position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
    r.SetEditCurPos(position, true, false)
    r.UpdateArrange()
end

local function select_all_source_uses(entry)
    local selected_guids = {}
    local earliest_position = math.huge
    local selected_count = 0
    r.SelectAllMediaItems(0, false)
    for _, guid in ipairs(entry.guids or {}) do
        local item = item_from_guid(guid)
        if item then
            r.SetMediaItemSelected(item, true)
            selected_guids[guid] = true
            earliest_position = math.min(earliest_position, r.GetMediaItemInfo_Value(item, "D_POSITION") or earliest_position)
            selected_count = selected_count + 1
        end
    end
    for _, current in ipairs(state.items) do current.selected = selected_guids[current.guid] == true end
    if earliest_position < math.huge then r.SetEditCurPos(earliest_position, true, false) end
    state.status = "Selected " .. tostring(selected_count) .. (selected_count == 1 and " source use" or " source uses")
    r.UpdateArrange()
end

local function selected_entries()
    local entries = {}
    for _, entry in ipairs(state.items) do
        if entry.selected and item_from_guid(entry.guid) then entries[#entries + 1] = entry end
    end
    return entries
end

local function select_card(entry, additive)
    local item = item_from_guid(entry.guid)
    if not item then return end
    if not additive then
        r.SelectAllMediaItems(0, false)
        for _, current in ipairs(state.items) do current.selected = false end
    end
    local selected = additive and not entry.selected or true
    r.SetMediaItemSelected(item, selected)
    entry.selected = selected
    if not additive then
        local track = r.GetMediaItemTrack(item)
        if track then r.SetOnlyTrackSelected(track) end
        r.SetEditCurPos(r.GetMediaItemInfo_Value(item, "D_POSITION") or 0, true, false)
    end
    r.UpdateArrange()
end

local function isolate_item_preview(item)
    local source_track = r.GetMediaItemTrack(item)
    if not source_track then return false end
    state.preview_track_states = {}
    state.preview_item_states = {}
    r.PreventUIRefresh(1)
    for track_index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, track_index)
        local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") or 0
        state.preview_track_states[#state.preview_track_states + 1] = { guid = r.GetTrackGUID(track), solo = solo }
        local target_solo = track == source_track and 1 or 0
        if solo ~= target_solo then r.SetMediaTrackInfo_Value(track, "I_SOLO", target_solo) end
    end
    for item_index = 0, r.CountMediaItems(0) - 1 do
        local current_item = r.GetMediaItem(0, item_index)
        local muted = r.GetMediaItemInfo_Value(current_item, "B_MUTE") or 0
        local volume = current_item == item and (r.GetMediaItemInfo_Value(current_item, "D_VOL") or 1) or nil
        state.preview_item_states[#state.preview_item_states + 1] = { guid = r.BR_GetMediaItemGUID(current_item), muted = muted, volume = volume }
        local target_muted = current_item == item and 0 or 1
        if muted ~= target_muted then r.SetMediaItemInfo_Value(current_item, "B_MUTE", target_muted) end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    return true
end

local function restore_item_preview_isolation()
    if not state.preview_track_states and not state.preview_item_states then return end
    local tracks_by_guid = {}
    r.PreventUIRefresh(1)
    for track_index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, track_index)
        tracks_by_guid[r.GetTrackGUID(track)] = track
    end
    for _, saved in ipairs(state.preview_track_states or {}) do
        local track = tracks_by_guid[saved.guid]
        if track then r.SetMediaTrackInfo_Value(track, "I_SOLO", saved.solo) end
    end
    for _, saved in ipairs(state.preview_item_states or {}) do
        local item = item_from_guid(saved.guid)
        if item then
            r.SetMediaItemInfo_Value(item, "B_MUTE", saved.muted)
            if saved.volume ~= nil then r.SetMediaItemInfo_Value(item, "D_VOL", saved.volume) end
        end
    end
    r.PreventUIRefresh(-1)
    state.preview_track_states = nil
    state.preview_item_states = nil
    r.UpdateArrange()
end

local function clear_item_preview(restore_cursor)
    restore_item_preview_isolation()
    if restore_cursor and state.preview_saved_cursor then
        r.SetEditCurPos(state.preview_saved_cursor, false, false)
    end
    state.preview_guid = nil
    state.preview_start = nil
    state.preview_end = nil
    state.preview_saved_cursor = nil
    state.preview_base_volume = nil
end

local function apply_preview_volume()
    local item = item_from_guid(state.preview_guid)
    if not item or state.preview_base_volume == nil then return end
    r.SetMediaItemInfo_Value(item, "D_VOL", state.preview_base_volume * state.preview_volume / 100)
    r.UpdateArrange()
end

local function stop_item_preview()
    if not state.preview_guid then return end
    if r.OnStopButton then r.OnStopButton() else r.Main_OnCommand(1016, 0) end
    clear_item_preview(true)
end

local function start_item_preview(entry)
    if state.preview_guid then stop_item_preview() end
    local item = item_from_guid(entry.guid)
    if not item or not isolate_item_preview(item) then return end
    local play_state = r.GetPlayState and r.GetPlayState() or 0
    if (play_state & 1) == 1 or (play_state & 4) == 4 then
        if r.OnStopButton then r.OnStopButton() else r.Main_OnCommand(1016, 0) end
    end
    state.preview_saved_cursor = r.GetCursorPosition()
    state.preview_guid = entry.guid
    state.preview_base_volume = r.GetMediaItemInfo_Value(item, "D_VOL") or 1
    apply_preview_volume()
    local position = r.GetMediaItemInfo_Value(item, "D_POSITION") or entry.position
    local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") or entry.length
    state.preview_start = position
    state.preview_end = position + length
    r.SetEditCurPos(position, false, false)
    if r.OnPlayButton then r.OnPlayButton() else r.Main_OnCommand(1007, 0) end
end

local function toggle_item_preview(entry)
    if state.preview_guid == entry.guid then stop_item_preview() else start_item_preview(entry) end
end

local function update_item_preview()
    if state.suppress_drag_guid and r.JS_Mouse_GetState(1) == 0 then state.suppress_drag_guid = nil end
    if not state.preview_guid then return end
    local play_state = r.GetPlayState and r.GetPlayState() or 0
    if (play_state & 1) ~= 1 then
        clear_item_preview(true)
        return
    end
    local play_position = r.GetPlayPosition and r.GetPlayPosition() or 0
    if state.preview_end and play_position >= state.preview_end - 0.001 then
        if state.loop_preview and state.preview_start then
            r.SetEditCurPos(state.preview_start, false, true)
        else
            stop_item_preview()
        end
    end
end

local function open_item_editor(entry)
    if state.preview_guid then stop_item_preview() end
    select_and_reveal(entry)
    if entry.is_midi then
        r.Main_OnCommand(40153, 0)
    else
        r.Main_OnCommand(40009, 0)
    end
end

local function toggle_item_loop(entry)
    if state.preview_guid then stop_item_preview() end
    local item = item_from_guid(entry.guid)
    if not item then return end
    local looped = not entry.looped
    r.Undo_BeginBlock()
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", looped and 1 or 0)
    r.Undo_EndBlock(looped and "Enable item source loop" or "Disable item source loop", -1)
    entry.looped = looped
    state.status = looped and "Item loop enabled" or "Item loop disabled"
    state.signature = ""
    state.last_scan = 0
    r.UpdateArrange()
end

local function unpool_item(entry)
    if not entry.is_midi or not entry.pooled then return end
    if state.preview_guid then stop_item_preview() end
    local item = item_from_guid(entry.guid)
    if not item then return end
    local selected_guids = {}
    for index = 0, r.CountSelectedMediaItems(0) - 1 do
        local selected_item = r.GetSelectedMediaItem(0, index)
        selected_guids[r.BR_GetMediaItemGUID(selected_item)] = true
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    r.Main_OnCommand(41613, 0)
    entry.pooled = pooled_midi_item(item, true)
    r.SelectAllMediaItems(0, false)
    for index = 0, r.CountMediaItems(0) - 1 do
        local current = r.GetMediaItem(0, index)
        if selected_guids[r.BR_GetMediaItemGUID(current)] then r.SetMediaItemSelected(current, true) end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Unpool MIDI item", -1)
    state.status = entry.pooled and "Could not unpool MIDI item" or "MIDI item unpooled"
    state.signature = ""
    state.last_scan = 0
    r.UpdateArrange()
end

local function delete_item(entry)
    if state.preview_guid then stop_item_preview() end
    local item = item_from_guid(entry.guid)
    if not item then return end
    local track = r.GetMediaItemTrack(item)
    if not track then return end
    r.Undo_BeginBlock()
    r.DeleteTrackMediaItem(track, item)
    r.Undo_EndBlock("Delete project clip", -1)
    state.waveform_cache[entry.cache_key] = nil
    state.midi_cache[entry.cache_key] = nil
    state.status = "Item deleted"
    state.signature = ""
    state.last_scan = 0
    r.UpdateArrange()
end

local function finish_batch(status)
    state.status = status
    state.signature = ""
    state.last_scan = 0
    r.UpdateArrange()
end

local function batch_set_loop(entries, mode)
    if #entries == 0 then return end
    if state.preview_guid then stop_item_preview() end
    r.Undo_BeginBlock()
    for _, entry in ipairs(entries) do
        local item = item_from_guid(entry.guid)
        if item then
            local current = (r.GetMediaItemInfo_Value(item, "B_LOOPSRC") or 0) > 0.5
            local looped = mode == "toggle" and not current or mode == "enable"
            r.SetMediaItemInfo_Value(item, "B_LOOPSRC", looped and 1 or 0)
            entry.looped = looped
        end
    end
    local label = mode == "toggle" and "Toggle source loop for selected items" or mode == "enable" and "Enable source loop for selected items" or "Disable source loop for selected items"
    r.Undo_EndBlock(label, -1)
    finish_batch(label)
end

local function batch_set_item_flag(entries, property, enabled, label)
    if #entries == 0 then return end
    if state.preview_guid then stop_item_preview() end
    r.Undo_BeginBlock()
    for _, entry in ipairs(entries) do
        local item = item_from_guid(entry.guid)
        if item then r.SetMediaItemInfo_Value(item, property, enabled and 1 or 0) end
    end
    r.Undo_EndBlock(label, -1)
    finish_batch(label)
end

local function batch_rename(entries)
    if #entries == 0 then return end
    local accepted, base_name = r.GetUserInputs("Rename selected clips", 1, "Base name:,extrawidth=220", entries[1].name or "Clip")
    base_name = tostring(base_name or ""):match("^%s*(.-)%s*$") or ""
    if not accepted or base_name == "" then return end
    if state.preview_guid then stop_item_preview() end
    local digits = math.max(2, #tostring(#entries))
    r.Undo_BeginBlock()
    for index, entry in ipairs(entries) do
        local item = item_from_guid(entry.guid)
        local take = item and r.GetActiveTake(item) or nil
        if take then
            local name = #entries == 1 and base_name or base_name .. " " .. string.format("%0" .. tostring(digits) .. "d", index)
            r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
        end
    end
    r.Undo_EndBlock("Rename selected project clips", -1)
    finish_batch("Renamed " .. tostring(#entries) .. (#entries == 1 and " clip" or " clips"))
end

local function relink_entries(entries, replacement_path)
    local replaced = 0
    for _, entry in ipairs(entries) do
        local item = item_from_guid(entry.guid)
        local take = item and r.GetActiveTake(item) or nil
        local source = take and r.PCM_Source_CreateFromFile(replacement_path) or nil
        if take and source then
            r.SetMediaItemTake_Source(take, source)
            replaced = replaced + 1
        end
    end
    if replaced > 0 then
        state.waveform_cache = {}
        state.midi_cache = {}
    end
    return replaced
end

local function choose_replacement(path)
    local accepted, replacement = r.GetUserFileNameForRead(path or "", "Relink missing media", "")
    if not accepted or replacement == "" then return nil end
    return replacement
end

local function relink_missing_selected(entries)
    local by_source = {}
    for _, entry in ipairs(entries) do
        if entry.missing and entry.source_key then
            local group = by_source[entry.source_key]
            if not group then group = { path = entry.source_path, entries = {} }; by_source[entry.source_key] = group end
            group.entries[#group.entries + 1] = entry
        end
    end
    if not next(by_source) then state.status = "No missing media in selection"; return end
    if state.preview_guid then stop_item_preview() end
    local replacements = {}
    for _, group in pairs(by_source) do
        local replacement = choose_replacement(group.path)
        if replacement then replacements[#replacements + 1] = { entries = group.entries, path = replacement } end
    end
    if #replacements == 0 then return end
    local replaced = 0
    r.Undo_BeginBlock()
    for _, replacement in ipairs(replacements) do
        replaced = replaced + relink_entries(replacement.entries, replacement.path)
    end
    r.Undo_EndBlock("Relink missing selected media", -1)
    finish_batch("Relinked " .. tostring(replaced) .. (replaced == 1 and " clip" or " clips"))
end

local function relink_source(entry)
    if not entry.missing then return end
    local replacement = choose_replacement(entry.path)
    if not replacement then return end
    if state.preview_guid then stop_item_preview() end
    local entries = {}
    for _, guid in ipairs(entry.guids or {}) do entries[#entries + 1] = { guid = guid } end
    r.Undo_BeginBlock()
    local replaced = relink_entries(entries, replacement)
    r.Undo_EndBlock("Relink missing source media", -1)
    finish_batch("Relinked " .. tostring(replaced) .. (replaced == 1 and " use" or " uses"))
end

local function batch_unpool(entries)
    if state.preview_guid then stop_item_preview() end
    local eligible = {}
    for _, entry in ipairs(entries) do
        if entry.is_midi and entry.pooled then eligible[#eligible + 1] = entry end
    end
    if #eligible == 0 then return end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for _, entry in ipairs(eligible) do
        local item = item_from_guid(entry.guid)
        if item then
            r.SelectAllMediaItems(0, false)
            r.SetMediaItemSelected(item, true)
            r.Main_OnCommand(41613, 0)
        end
    end
    r.SelectAllMediaItems(0, false)
    for _, entry in ipairs(entries) do
        local item = item_from_guid(entry.guid)
        if item then r.SetMediaItemSelected(item, true) end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Unpool selected MIDI items", -1)
    finish_batch(tostring(#eligible) .. " MIDI item" .. (#eligible == 1 and "" or "s") .. " unpooled")
end

local ITEM_PROPERTIES = { "D_LENGTH", "B_MUTE", "B_LOOPSRC", "C_LOCK", "I_GROUPID", "I_CUSTOMCOLOR", "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINDIR", "D_FADEOUTDIR", "C_FADEINSHAPE", "C_FADEOUTSHAPE" }
local TAKE_PROPERTIES = { "D_PLAYRATE", "D_PITCH", "B_PPITCH", "I_CHANMODE", "D_VOL", "D_PAN", "I_CUSTOMCOLOR" }

local function snapshot_pool_target(entry)
    local item = item_from_guid(entry.guid)
    local take = item and r.GetActiveTake(item) or nil
    local track = item and r.GetMediaItemTrack(item) or nil
    if not item or not take or not track then return nil end
    local snapshot = { guid = entry.guid, track = track, position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0, item_values = {}, take_values = {} }
    for _, key in ipairs(ITEM_PROPERTIES) do snapshot.item_values[key] = r.GetMediaItemInfo_Value(item, key) end
    for _, key in ipairs(TAKE_PROPERTIES) do snapshot.take_values[key] = r.GetMediaItemTakeInfo_Value(take, key) end
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    snapshot.take_name = name or ""
    return snapshot
end

local function apply_pool_target(snapshot, item)
    r.SetMediaItemInfo_Value(item, "D_POSITION", snapshot.position)
    for key, value in pairs(snapshot.item_values) do r.SetMediaItemInfo_Value(item, key, value) end
    local take = r.GetActiveTake(item)
    if take then
        for key, value in pairs(snapshot.take_values) do r.SetMediaItemTakeInfo_Value(take, key, value) end
        r.GetSetMediaItemTakeInfo_String(take, "P_NAME", snapshot.take_name, true)
    end
end

local function batch_pool_to_source(source_entry, entries)
    if #entries < 2 or not source_entry.is_midi then return end
    for _, entry in ipairs(entries) do if not entry.is_midi then return end end
    if state.preview_guid then stop_item_preview() end
    local source_item = item_from_guid(source_entry.guid)
    if not source_item then return end
    local targets = {}
    for _, entry in ipairs(entries) do
        if entry.guid ~= source_entry.guid then
            local snapshot = snapshot_pool_target(entry)
            if snapshot then targets[#targets + 1] = snapshot end
        end
    end
    if #targets == 0 then return end
    local cursor = r.GetCursorPosition()
    local selected_track_guids = {}
    for index = 0, r.CountSelectedTracks(0) - 1 do
        local track = r.GetSelectedTrack(0, index)
        if track then selected_track_guids[#selected_track_guids + 1] = r.GetTrackGUID(track) end
    end
    local result_guids = { source_entry.guid }
    local replaced = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(source_item, true)
    r.Main_OnCommand(40698, 0)
    for _, snapshot in ipairs(targets) do
        local original = item_from_guid(snapshot.guid)
        if original then
            r.SelectAllMediaItems(0, false)
            r.SetOnlyTrackSelected(snapshot.track)
            r.SetEditCurPos(snapshot.position, false, false)
            r.Main_OnCommand(41072, 0)
            local pasted = r.GetSelectedMediaItem(0, 0)
            if pasted and pasted ~= original then
                apply_pool_target(snapshot, pasted)
                local track = r.GetMediaItemTrack(original)
                if track then r.DeleteTrackMediaItem(track, original) end
                result_guids[#result_guids + 1] = r.BR_GetMediaItemGUID(pasted)
                replaced = replaced + 1
            else
                result_guids[#result_guids + 1] = snapshot.guid
            end
        end
    end
    r.SelectAllMediaItems(0, false)
    for _, guid in ipairs(result_guids) do
        local item = item_from_guid(guid)
        if item then r.SetMediaItemSelected(item, true) end
    end
    for track_index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, track_index)
        r.SetTrackSelected(track, false)
    end
    for track_index = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, track_index)
        local guid = r.GetTrackGUID(track)
        for _, selected_guid in ipairs(selected_track_guids) do
            if guid == selected_guid then r.SetTrackSelected(track, true); break end
        end
    end
    r.SetEditCurPos(cursor, false, false)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Pool selected MIDI items to source", -1)
    finish_batch(replaced == #targets and tostring(replaced + 1) .. " MIDI items pooled" or tostring(replaced) .. " of " .. tostring(#targets) .. " MIDI targets pooled")
end

local function batch_delete(entries)
    if #entries == 0 then return end
    if state.preview_guid then stop_item_preview() end
    local deleted = 0
    r.Undo_BeginBlock()
    for _, entry in ipairs(entries) do
        local item = item_from_guid(entry.guid)
        local track = item and r.GetMediaItemTrack(item) or nil
        if item and track then
            r.DeleteTrackMediaItem(track, item)
            state.waveform_cache[entry.cache_key] = nil
            state.midi_cache[entry.cache_key] = nil
            deleted = deleted + 1
        end
    end
    r.Undo_EndBlock("Delete selected project clips", -1)
    finish_batch(tostring(deleted) .. " item" .. (deleted == 1 and "" or "s") .. " deleted")
end

local function begin_item_drag(entry)
    if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceAllowNullID()) then
        state.drag = { guid = entry.guid, is_midi = entry.is_midi, name = entry.name, source_path = entry.source_key and entry.path or nil }
        state.drag_active = true
        r.ImGui_SetDragDropPayload(ctx, "TK_PROJECT_CLIP", entry.guid)
        local pooled = entry.is_midi and r.JS_Mouse_GetState(8) == 8
        r.ImGui_TextColored(ctx, pooled and COLORS.midi or COLORS.text, pooled and "POOLED MIDI" or "COPY")
        r.ImGui_Text(ctx, truncate_text(entry.name, 240))
        r.ImGui_EndDragDropSource(ctx)
    end
end

local function calculate_drop_target()
    local mouse_x, mouse_y = r.GetMousePosition()
    local track = select(1, r.GetTrackFromPoint(mouse_x, mouse_y))
    if not track then return nil, nil end
    local arrange = r.JS_Window_FindChildByID(r.GetMainHwnd(), 0x3E8)
    if not arrange then return nil, nil end
    local ok, left, top, right, bottom = r.JS_Window_GetRect(arrange)
    if not ok or mouse_x < left or mouse_x > right or mouse_y < top or mouse_y > bottom then return nil, nil end
    local start_time, end_time = r.GetSet_ArrangeView2(0, false, 0, 0)
    local position = start_time + ((mouse_x - left) / math.max(1, right - left)) * (end_time - start_time)
    if state.snap then position = r.SnapToGrid(0, position) end
    return track, math.max(0, position)
end

local function paste_dragged_item(track, position, pooled)
    local drag = state.drag
    local source_item = drag and item_from_guid(drag.guid) or nil
    if not drag or not track then return false end
    if state.preview_guid then stop_item_preview() end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    r.SetOnlyTrackSelected(track)
    r.SetEditCurPos(position, false, false)
    if drag.source_path and drag.source_path ~= "" and not drag.is_midi then
        r.InsertMedia(drag.source_path, 0)
    elseif source_item then
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(source_item, true)
        r.Main_OnCommand(40698, 0)
        r.Main_OnCommand(pooled and 41072 or 40058, 0)
    else
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Insert project media", -1)
        return false
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    local undo_label = drag.source_path and not drag.is_midi and "Insert source media" or pooled and "Insert pooled MIDI clip" or "Insert project clip"
    r.Undo_EndBlock(undo_label, -1)
    return true
end

local function update_drag()
    if not state.drag_active or not state.drag then return end
    local mouse_down = r.JS_Mouse_GetState(1) == 1
    if mouse_down then
        local track, position = calculate_drop_target()
        if track and position then
            state.status = state.drag.is_midi and r.JS_Mouse_GetState(8) == 8 and "Release to insert pooled MIDI" or "Release to insert copy"
        else
            state.status = "Drag onto the arrange view"
        end
        return
    end
    local track, position = calculate_drop_target()
    local pooled = state.drag.is_midi and r.JS_Mouse_GetState(8) == 8
    if track and position then paste_dragged_item(track, position, pooled) end
    state.drag = nil
    state.drag_active = false
    state.status = ""
end

Launcher.init({
    ctx = ctx,
    colors = COLORS,
    json = json,
    scaled = scaled,
    rounded = rounded,
    preview = launcher_preview,
    drop_target = calculate_drop_target,
    hide_scrollbar = function() return state.hide_content_scrollbar end,
})

local function filter_button(label, value, width)
    local active = state.filter == value
    if active then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.accent_soft)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COLORS.accent)
    end
    local clicked = r.ImGui_Button(ctx, label, width or rounded(64), rounded(26))
    if active then r.ImGui_PopStyleColor(ctx, 2) end
    if clicked then
        state.filter = value
        state.signature = ""
    end
end

local VIEW_WIDTHS = { items = 74, sources = 112, launcher = 82 }

local function view_button(label, value, count)
    local active = state.view_mode == value
    if active then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COLORS.accent_soft)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COLORS.accent)
    end
    local caption = count and (label .. " " .. tostring(count)) or label
    local clicked = r.ImGui_Button(ctx, caption, rounded(VIEW_WIDTHS[value] or 90), rounded(24))
    if active then r.ImGui_PopStyleColor(ctx, 2) end
    if clicked and not active then
        if state.preview_guid then stop_item_preview() end
        state.view_mode = value
        state.status = ""
        r.SetExtState(EXT_SECTION, "view_mode", value, true)
    end
end

local function draw_header()
    local available = r.ImGui_GetContentRegionAvail(ctx)
    local close_size = rounded(14)
    local settings_size = rounded(14)
    local gap = rounded(8)
    local items_width = rounded(VIEW_WIDTHS.items)
    local sources_width = rounded(VIEW_WIDTHS.sources)
    local launcher_width = rounded(VIEW_WIDTHS.launcher)
    local tabs_width = items_width + sources_width + launcher_width + rounded(14)
    local right_width = tabs_width + settings_size + close_size + gap * 3
    r.ImGui_TextColored(ctx, COLORS.accent, SCRIPT_NAME)
    r.ImGui_SameLine(ctx, math.max(rounded(120), available - right_width))
    view_button("Items", "items", #state.items)
    r.ImGui_SameLine(ctx, 0, rounded(7))
    view_button("Source Media", "sources", #state.sources)
    r.ImGui_SameLine(ctx, 0, rounded(7))
    view_button("Launcher", "launcher", nil)
    r.ImGui_SameLine(ctx, 0, gap)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local settings_x, settings_y = r.ImGui_GetCursorScreenPos(ctx)
    local settings_hovered = r.ImGui_IsMouseHoveringRect(ctx, settings_x, settings_y, settings_x + settings_size, settings_y + settings_size)
    r.ImGui_DrawList_AddCircleFilled(draw_list, settings_x + settings_size * 0.5, settings_y + settings_size * 0.5, settings_size * 0.5, settings_hovered and COLORS.accent or 0xFFFFFFFF)
    r.ImGui_DrawList_AddCircle(draw_list, settings_x + settings_size * 0.5, settings_y + settings_size * 0.5, settings_size * 0.5, COLORS.border, 16, scaled(1))
    if r.ImGui_InvisibleButton(ctx, "##project_clips_settings", settings_size, settings_size) then state.theme_settings_open = true end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Settings") end
    r.ImGui_SameLine(ctx, 0, gap)
    local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
    local hovered = r.ImGui_IsMouseHoveringRect(ctx, close_x, close_y, close_x + close_size, close_y + close_size)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, hovered and mix_color(COLORS.danger, COLORS.text, 0.2) or COLORS.danger)
    r.ImGui_DrawList_AddCircle(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, COLORS.border, 16, scaled(1))
    if r.ImGui_InvisibleButton(ctx, "##project_clips_close", close_size, close_size) then state.open = false end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
end

local function trim_text(value)
    return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function is_reserved_theme_name(name)
    local normalized = trim_text(name):lower()
    if normalized == "unsaved custom" then return true end
    return Theme.is_reserved_preset_name and Theme.is_reserved_preset_name(normalized) or false
end

local function draw_theme_preview()
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local size = rounded(18)
    local gap = rounded(6)
    local swatches = { Theme.colors.window_bg, Theme.colors.child_bg, Theme.colors.frame_bg, Theme.colors.accent, Theme.colors.warning, Theme.colors.danger }
    for index, color in ipairs(swatches) do
        local left = x + (index - 1) * (size + gap)
        r.ImGui_DrawList_AddRectFilled(draw_list, left, y, left + size, y + size, color, scaled(3))
        r.ImGui_DrawList_AddRect(draw_list, left, y, left + size, y + size, COLORS.border, scaled(3), 0, scaled(1))
    end
    r.ImGui_Dummy(ctx, #swatches * (size + gap) - gap, size)
end

local function draw_theme_settings_body()
    r.ImGui_TextColored(ctx, COLORS.text_dim, "Interface")
    r.ImGui_SetNextItemWidth(ctx, rounded(120))
    if r.ImGui_BeginCombo(ctx, "##settings_ui_scale", ui_scale_label()) then
        for _, option in ipairs(UI_SCALE_OPTIONS) do
            local selected = math.abs(state.ui_scale - option.value) < 0.01
            if r.ImGui_Selectable(ctx, option.label, selected) then set_ui_scale(option.value) end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "UI scale") end
    r.ImGui_SameLine(ctx)
    local scrollbar_changed, hide_scrollbar = r.ImGui_Checkbox(ctx, "Hide scrollbar", state.hide_content_scrollbar)
    if scrollbar_changed then
        state.hide_content_scrollbar = hide_scrollbar
        r.SetExtState(EXT_SECTION, "hide_content_scrollbar", hide_scrollbar and "1" or "0", true)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Keep mouse-wheel scrolling without showing the content scrollbar") end
    r.ImGui_SetNextItemWidth(ctx, rounded(150))
    local color_labels = { type = "Type", peaks = "Track peaks", tiles = "Track tiles" }
    if r.ImGui_BeginCombo(ctx, "##settings_clip_color_mode", color_labels[state.color_mode] or "Track peaks") then
        for _, option in ipairs({ { "Type", "type" }, { "Track peaks", "peaks" }, { "Track tiles", "tiles" } }) do
            local selected = state.color_mode == option[2]
            if r.ImGui_Selectable(ctx, option[1], selected) then
                state.color_mode = option[2]
                r.SetExtState(EXT_SECTION, "color_mode", state.color_mode, true)
            end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clip color mode") end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, rounded(100))
    local position_label = state.position_mode == "time" and "Time" or "Bars"
    if r.ImGui_BeginCombo(ctx, "##settings_clip_position_mode", position_label) then
        for _, option in ipairs({ { "Bars", "bars" }, { "Time", "time" } }) do
            local selected = state.position_mode == option[2]
            if r.ImGui_Selectable(ctx, option[1], selected) then
                state.position_mode = option[2]
                r.SetExtState(EXT_SECTION, "position_mode", state.position_mode, true)
            end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Position display") end
    r.ImGui_SetNextItemWidth(ctx, rounded(130))
    local volume_changed, preview_volume = r.ImGui_SliderDouble(ctx, "Preview volume", state.preview_volume, 0, 200, "%.0f%%")
    if volume_changed then
        state.preview_volume = preview_volume
        r.SetExtState(EXT_SECTION, "preview_volume", tostring(preview_volume), true)
        apply_preview_volume()
    end
    r.ImGui_SameLine(ctx)
    local loop_changed, loop_preview = r.ImGui_Checkbox(ctx, "Loop", state.loop_preview)
    if loop_changed then
        state.loop_preview = loop_preview
        r.SetExtState(EXT_SECTION, "loop_preview", loop_preview and "1" or "0", true)
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, COLORS.text_dim, "Preset")
    r.ImGui_SetNextItemWidth(ctx, rounded(220))
    if r.ImGui_BeginCombo(ctx, "##theme_settings_preset", state.theme_preset) then
        for _, name in ipairs(theme_names()) do
            local selected = state.theme_preset == name
            if r.ImGui_Selectable(ctx, name, selected) then
                apply_theme(name)
                if project_clips_settings.custom_themes[name] then project_clips_settings.custom_theme_name = name end
            end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if Theme.is_reaper_theme_preset and Theme.is_reaper_theme_preset(state.theme_preset) then
        if r.ImGui_Button(ctx, "Refresh REAPER Theme", rounded(160), rounded(24)) then
            apply_theme(state.theme_preset)
            state.status = "REAPER theme colors refreshed"
        end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, COLORS.text_dim, "Preview")
    draw_theme_preview()
    r.ImGui_Spacing(ctx)
    local child_visible = r.ImGui_BeginChild(ctx, "##project_clips_theme_colors", 0, rounded(282), 1)
    if child_visible then
        local color_flags = r.ImGui_ColorEditFlags_NoInputs()
        for _, field in ipairs(THEME_COLOR_FIELDS) do
            local changed, value = r.ImGui_ColorEdit4(ctx, field.label .. "##" .. field.key, Theme.colors[field.key], color_flags)
            if changed then
                Theme.colors[field.key] = value
                state.theme_preset = Theme.set_colors(Theme.colors, "Unsaved Custom")
                sync_theme_colors()
            end
        end
        r.ImGui_EndChild(ctx)
    end
    local name_changed, custom_name = r.ImGui_InputTextWithHint(ctx, "##project_clips_custom_theme_name", "Custom theme name", project_clips_settings.custom_theme_name or "My Theme")
    if name_changed then project_clips_settings.custom_theme_name = custom_name end
    local theme_name = trim_text(project_clips_settings.custom_theme_name)
    local theme_exists = project_clips_settings.custom_themes[theme_name] ~= nil
    if r.ImGui_Button(ctx, theme_exists and "Update Custom" or "Save Custom", rounded(110), rounded(24)) then
        if theme_name == "" then
            state.status = "Custom theme name required"
        elseif is_reserved_theme_name(theme_name) then
            state.status = "Reserved theme names cannot be overwritten"
        else
            project_clips_settings.custom_themes[theme_name] = Theme.copy_current_colors()
            state.theme_preset = Theme.set_preset(theme_name, project_clips_settings.custom_themes)
            project_clips_settings.theme_preset = state.theme_preset
            sync_theme_colors()
            state.status = (theme_exists and "Updated custom theme: " or "Saved custom theme: ") .. theme_name
            if not save_config(project_clips_settings) then state.status = "Could not save theme settings" end
        end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Delete Custom", rounded(110), rounded(24)) then
        if theme_name == "" then
            state.status = "Custom theme name required"
        elseif is_reserved_theme_name(theme_name) then
            state.status = "Reserved themes cannot be deleted"
        elseif project_clips_settings.custom_themes[theme_name] then
            project_clips_settings.custom_themes[theme_name] = nil
            if state.theme_preset == theme_name then apply_theme("Graphite") else save_config(project_clips_settings) end
            state.status = "Deleted custom theme: " .. theme_name
        else
            state.status = "Custom theme not found: " .. theme_name
        end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Reset", rounded(90), rounded(24)) then
        apply_theme("Graphite")
        state.status = "Theme preset reset"
    end
end

local function draw_theme_settings()
    if not state.theme_settings_open then return end
    r.ImGui_SetNextWindowSize(ctx, rounded(360), rounded(720), r.ImGui_Cond_Always())
    local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    local visible, open = r.ImGui_Begin(ctx, "Settings##project_clips", state.theme_settings_open, window_flags)
    state.theme_settings_open = open
    if visible then
        r.ImGui_TextColored(ctx, COLORS.accent, "Settings")
        local close_size = rounded(14)
        r.ImGui_SameLine(ctx, math.max(rounded(140), r.ImGui_GetWindowWidth(ctx) - close_size - rounded(16)))
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
        local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
        local hovered = r.ImGui_IsMouseHoveringRect(ctx, close_x, close_y, close_x + close_size, close_y + close_size)
        r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, hovered and 0xFF879AFF or 0xF7768EFF)
        r.ImGui_DrawList_AddCircle(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, 0x3A1018FF, 16, scaled(1))
        if r.ImGui_InvisibleButton(ctx, "##project_clips_settings_close", close_size, close_size) then state.theme_settings_open = false end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
        r.ImGui_Separator(ctx)
        draw_theme_settings_body()
    end
    r.ImGui_End(ctx)
end

local function draw_all_tracks_button()
    local expand = all_tracks_collapsed()
    local size = rounded(26)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##toggle_all_tracks", size, size) then
        set_all_tracks_collapsed(not expand)
    end
    local hovered = r.ImGui_IsItemHovered(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + size, y + size, hovered and COLORS.card_hover or COLORS.card_bg, scaled(4))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + size, y + size, hovered and COLORS.accent or COLORS.border, scaled(4), 0, scaled(1))
    local center_x = x + size * 0.5
    local triangle = scaled(3)
    for offset = -1, 1, 2 do
        local center_y = y + size * 0.5 + offset * scaled(4)
        if expand then
            r.ImGui_DrawList_AddTriangleFilled(draw_list, center_x - triangle, center_y - triangle * 0.6, center_x + triangle, center_y - triangle * 0.6, center_x, center_y + triangle, hovered and COLORS.accent or COLORS.text_dim)
        else
            r.ImGui_DrawList_AddTriangleFilled(draw_list, center_x - triangle * 0.6, center_y - triangle, center_x - triangle * 0.6, center_y + triangle, center_x + triangle, center_y, hovered and COLORS.accent or COLORS.text_dim)
        end
    end
    if hovered then r.ImGui_SetTooltip(ctx, expand and "Expand all tracks" or "Collapse all tracks") end
end

local function draw_toolbar()
    if state.view_mode == "launcher" then
        Launcher.draw_toolbar()
        return
    end
    local available = r.ImGui_GetContentRegionAvail(ctx)
    local gap = rounded(8)
    local frame_height = r.ImGui_GetFrameHeight(ctx)
    local checkbox_width = r.ImGui_CalcTextSize(ctx, "Selected track") + r.ImGui_CalcTextSize(ctx, "Snap") + frame_height * 2
    local color_width = rounded(112)
    local position_width = rounded(74)
    local status_width = rounded(92)
    local sort_width = rounded(92)
    local group_buttons_width = state.view_mode == "items" and rounded(26) or 0
    local filter_sort_width = sort_width + rounded(52) + (state.view_mode == "items" and status_width + gap or 0)
    local desired_width = rounded(150 + 64 * 3) + checkbox_width + color_width + position_width + filter_sort_width + group_buttons_width + gap * 13
    local compact = available < desired_width
    local single_control_row = compact and available >= rounded(380)
    local type_button_width = compact and math.floor((available - (single_control_row and checkbox_width + gap * 4 or gap * 2)) / 3) or rounded(64)
    local direction_width = rounded(52)
    local compact_group_width = state.view_mode == "items" and rounded(26) or 0
    local compact_combo_width = math.max(rounded(72), math.floor((available - direction_width - compact_group_width - gap * (state.view_mode == "items" and 4 or 1)) / (state.view_mode == "items" and 2 or 1)))
    r.ImGui_SetNextItemWidth(ctx, compact and available or math.max(rounded(150), math.min(rounded(320), available * 0.35)))
    local search_hint = state.view_mode == "sources" and "Search source name, path or type" or "Search clips or tracks"
    local changed, search = r.ImGui_InputTextWithHint(ctx, "##search", search_hint, state.search)
    if changed then state.search = search; state.signature = "" end
    if not compact then r.ImGui_SameLine(ctx) end
    filter_button("All", "all", type_button_width)
    r.ImGui_SameLine(ctx, 0, gap)
    filter_button("Audio", "audio", type_button_width)
    r.ImGui_SameLine(ctx, 0, gap)
    filter_button("MIDI", "midi", type_button_width)
    if not compact or single_control_row then r.ImGui_SameLine(ctx, 0, gap) end
    local selected_changed, selected_only = r.ImGui_Checkbox(ctx, "Selected track", state.selected_track_only)
    if selected_changed then state.selected_track_only = selected_only; state.signature = "" end
    r.ImGui_SameLine(ctx)
    local snap_changed, snap = r.ImGui_Checkbox(ctx, "Snap", state.snap)
    if snap_changed then state.snap = snap end
    if not compact then r.ImGui_SameLine(ctx) end
    if state.view_mode == "items" then
        r.ImGui_SetNextItemWidth(ctx, compact and compact_combo_width or status_width)
        local status_labels = { all = "All states", pooled = "Pooled", looped = "Looped", muted = "Muted", locked = "Locked" }
        if r.ImGui_BeginCombo(ctx, "##clip_status_filter", status_labels[state.status_filter]) then
            for _, option in ipairs({ { "All states", "all" }, { "Pooled", "pooled" }, { "Looped", "looped" }, { "Muted", "muted" }, { "Locked", "locked" } }) do
                local selected = state.status_filter == option[2]
                if r.ImGui_Selectable(ctx, option[1], selected) then
                    state.status_filter = option[2]
                    state.signature = ""
                    r.SetExtState(EXT_SECTION, "status_filter", state.status_filter, true)
                end
                if selected then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clip state filter") end
        r.ImGui_SameLine(ctx, 0, gap)
    end
    local active_sort_width = compact and (state.view_mode == "items" and compact_combo_width or available - direction_width - gap) or sort_width
    r.ImGui_SetNextItemWidth(ctx, active_sort_width)
    local sort_options = state.view_mode == "items" and { { "Position", "position" }, { "Name", "name" }, { "Length", "length" } }
        or { { "Name", "name" }, { "Uses", "uses" }, { "Length", "length" }, { "Type", "type" } }
    local sort_key = state.view_mode == "items" and state.item_sort or state.source_sort
    local sort_label = "Sort"
    for _, option in ipairs(sort_options) do if option[2] == sort_key then sort_label = option[1]; break end end
    if r.ImGui_BeginCombo(ctx, "##project_clips_sort", sort_label) then
        for _, option in ipairs(sort_options) do
            local selected = sort_key == option[2]
            if r.ImGui_Selectable(ctx, option[1], selected) then
                if state.view_mode == "items" then state.item_sort = option[2] else state.source_sort = option[2] end
                state.signature = ""
                r.SetExtState(EXT_SECTION, state.view_mode == "items" and "item_sort" or "source_sort", option[2], true)
            end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Sort order") end
    r.ImGui_SameLine(ctx, 0, gap)
    if r.ImGui_Button(ctx, state.sort_descending and "Desc" or "Asc", direction_width, rounded(26)) then
        state.sort_descending = not state.sort_descending
        state.signature = ""
        r.SetExtState(EXT_SECTION, "sort_descending", state.sort_descending and "1" or "0", true)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, state.sort_descending and "Descending" or "Ascending") end
    if compact and state.view_mode == "items" then
        r.ImGui_SameLine(ctx, 0, gap)
        draw_all_tracks_button()
    end
    if state.view_mode == "items" and not compact then
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, color_width)
        local color_labels = { type = "Type", peaks = "Track peaks", tiles = "Track tiles" }
        if r.ImGui_BeginCombo(ctx, "##clip_color_mode", color_labels[state.color_mode] or "Track peaks") then
            for _, option in ipairs({ { "Type", "type" }, { "Track peaks", "peaks" }, { "Track tiles", "tiles" } }) do
                local selected = state.color_mode == option[2]
                if r.ImGui_Selectable(ctx, option[1], selected) then
                    state.color_mode = option[2]
                    r.SetExtState(EXT_SECTION, "color_mode", state.color_mode, true)
                end
                if selected then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clip color mode") end
        r.ImGui_SameLine(ctx, 0, gap)
        r.ImGui_SetNextItemWidth(ctx, position_width)
        local position_label = state.position_mode == "time" and "Time" or "Bars"
        if r.ImGui_BeginCombo(ctx, "##clip_position_mode", position_label) then
            for _, option in ipairs({ { "Bars", "bars" }, { "Time", "time" } }) do
                local selected = state.position_mode == option[2]
                if r.ImGui_Selectable(ctx, option[1], selected) then
                    state.position_mode = option[2]
                    r.SetExtState(EXT_SECTION, "position_mode", state.position_mode, true)
                end
                if selected then r.ImGui_SetItemDefaultFocus(ctx) end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Position display") end
        r.ImGui_SameLine(ctx, 0, gap)
        draw_all_tracks_button()
    end
end

local function clip_metadata(entry)
    local parts = { format_position(entry.position), format_length(entry.length) }
    if entry.take_count > 1 then parts[#parts + 1] = tostring(entry.active_take) .. "/" .. tostring(entry.take_count) end
    return table.concat(parts, "  |  ")
end

local function draw_playback_progress(entry, draw_list, x, y, width, height)
    if state.preview_guid ~= entry.guid or not state.preview_start or not state.preview_end then return end
    local duration = state.preview_end - state.preview_start
    if duration <= 0 then return end
    local play_position = r.GetPlayPosition and r.GetPlayPosition() or state.preview_start
    local progress = clamp((play_position - state.preview_start) / duration, 0, 1)
    local playhead_x = x + width * progress
    local color = inverse_tiles_active(entry) and contrast_color(entry.track_color, false) or COLORS.accent
    local wash = (color & 0xFFFFFF00) | 0x24
    local glow = (color & 0xFFFFFF00) | 0x52
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, playhead_x, y + height, wash)
    r.ImGui_DrawList_AddRectFilled(draw_list, playhead_x - scaled(4), y, playhead_x + scaled(4), y + height, glow)
    r.ImGui_DrawList_AddLine(draw_list, playhead_x, y, playhead_x, y + height, color, scaled(2))
    local bar_y = y + height - scaled(3)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, bar_y, x + width, y + height, 0x00000066, scaled(1.5))
    r.ImGui_DrawList_AddRectFilled(draw_list, x, bar_y, playhead_x, y + height, color, scaled(1.5))
    r.ImGui_DrawList_AddCircleFilled(draw_list, playhead_x, bar_y + scaled(1.5), scaled(3), color)
end

local function draw_play_button(entry, cursor_x, cursor_y)
    local size = rounded(22)
    local x = cursor_x + scaled(9)
    local y = cursor_y + scaled(8)
    local hovered = r.ImGui_IsMouseHoveringRect(ctx, x, y, x + size, y + size)
    local active = state.preview_guid == entry.guid
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local background = (COLORS.card_bg & 0xFFFFFF00) | (hovered and 0xEE or 0xBB)
    r.ImGui_DrawList_AddCircleFilled(draw_list, x + size * 0.5, y + size * 0.5, size * 0.5, background)
    r.ImGui_DrawList_AddCircle(draw_list, x + size * 0.5, y + size * 0.5, size * 0.5, active and COLORS.danger or hovered and COLORS.accent or COLORS.text, 16, scaled(1))
    if active then
        local inset = scaled(7)
        r.ImGui_DrawList_AddRectFilled(draw_list, x + inset, y + inset, x + size - inset, y + size - inset, COLORS.danger, scaled(1))
    else
        local center_x = x + size * 0.5
        local center_y = y + size * 0.5
        local triangle = scaled(4.5)
        r.ImGui_DrawList_AddTriangleFilled(draw_list, center_x - triangle * 0.65, center_y - triangle, center_x - triangle * 0.65, center_y + triangle, center_x + triangle, center_y, hovered and COLORS.accent or COLORS.text)
    end
    if hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        state.suppress_drag_guid = entry.guid
        toggle_item_preview(entry)
        return true
    end
    if hovered then r.ImGui_SetTooltip(ctx, active and "Stop item" or "Play item") end
    return hovered
end

local function draw_delete_button(entry, cursor_x, cursor_y)
    local size = rounded(22)
    local x = cursor_x + scaled(36)
    local y = cursor_y + scaled(8)
    local hovered = r.ImGui_IsMouseHoveringRect(ctx, x, y, x + size, y + size)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local background = (COLORS.card_bg & 0xFFFFFF00) | (hovered and 0xEE or 0xBB)
    local color = hovered and COLORS.danger or COLORS.text
    r.ImGui_DrawList_AddCircleFilled(draw_list, x + size * 0.5, y + size * 0.5, size * 0.5, background)
    r.ImGui_DrawList_AddCircle(draw_list, x + size * 0.5, y + size * 0.5, size * 0.5, hovered and COLORS.danger or COLORS.text, 16, scaled(1))
    local left = x + scaled(7)
    local right = x + size - scaled(7)
    local top = y + scaled(8)
    local bottom = y + size - scaled(6)
    r.ImGui_DrawList_AddRect(draw_list, left, top, right, bottom, color, scaled(1), 0, scaled(1.5))
    r.ImGui_DrawList_AddLine(draw_list, left - scaled(1), top - scaled(3), right + scaled(1), top - scaled(3), color, scaled(1.5))
    r.ImGui_DrawList_AddLine(draw_list, x + scaled(9), top - scaled(5), x + size - scaled(9), top - scaled(5), color, scaled(1.5))
    if hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        state.suppress_drag_guid = entry.guid
        delete_item(entry)
        return true
    end
    if hovered then r.ImGui_SetTooltip(ctx, "Delete item") end
    return hovered
end

local function draw_item_toggle(entry, label, active, x, y, width)
    local height = rounded(20)
    local hovered = r.ImGui_IsMouseHoveringRect(ctx, x, y, x + width, y + height)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local color = COLORS.audio
    local background = active and ((color & 0xFFFFFF00) | (hovered and 0xDD or 0xB8)) or ((COLORS.card_bg & 0xFFFFFF00) | (hovered and 0xDD or 0x99))
    local border = active and color or hovered and COLORS.text or COLORS.text_dim
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, background, scaled(3))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, border, scaled(3), 0, scaled(1))
    local text_width, text_height = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(draw_list, x + (width - text_width) * 0.5, y + (height - text_height) * 0.5, active and COLORS.badge_text or COLORS.text, label)
    if hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        state.suppress_drag_guid = entry.guid
        toggle_item_loop(entry)
        return true
    end
    if hovered then
        r.ImGui_SetTooltip(ctx, active and "Disable source loop" or "Enable source loop")
    end
    return hovered
end

local function draw_pool_status(entry, x, y, width)
    local height = rounded(20)
    local hovered = r.ImGui_IsMouseHoveringRect(ctx, x, y, x + width, y + height)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local color = COLORS.midi
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, (color & 0xFFFFFF00) | (hovered and 0xDD or 0xB8), scaled(3))
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, hovered and COLORS.text or color, scaled(3), 0, scaled(1))
    local text_width, text_height = r.ImGui_CalcTextSize(ctx, "POOL")
    r.ImGui_DrawList_AddText(draw_list, x + (width - text_width) * 0.5, y + (height - text_height) * 0.5, COLORS.badge_text, "POOL")
    if hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        state.suppress_drag_guid = entry.guid
        unpool_item(entry)
        return true
    end
    if hovered then r.ImGui_SetTooltip(ctx, "Make MIDI item unique") end
    return hovered
end

local function draw_item_toggles(entry, cursor_x, cursor_y, card_width)
    local gap = rounded(5)
    local pool_width = rounded(38)
    local loop_width = rounded(40)
    local y = cursor_y + scaled(8)
    local loop_x = cursor_x + card_width - scaled(9) - loop_width
    local hovered = draw_item_toggle(entry, "LOOP", entry.looped, loop_x, y, loop_width)
    if entry.is_midi and entry.pooled then
        local pool_x = loop_x - gap - pool_width
        hovered = draw_pool_status(entry, pool_x, y, pool_width) or hovered
    end
    return hovered
end

local function draw_card_context(entry)
    if not r.ImGui_BeginPopupContextItem(ctx, "##project_clip_context_" .. entry.guid) then return false end
    local entries = selected_entries()
    if #entries == 0 then entries = { entry } end
    r.ImGui_TextColored(ctx, COLORS.text_dim, tostring(#entries) .. " selected")
    if r.ImGui_MenuItem(ctx, entry.is_midi and "Open in MIDI editor" or "Open item properties") then open_item_editor(entry) end
    if r.ImGui_MenuItem(ctx, "Select and reveal") then select_and_reveal(entry) end
    r.ImGui_Separator(ctx)
    local all_midi = #entries >= 2 and entry.is_midi
    local has_pooled = false
    for _, selected in ipairs(entries) do
        all_midi = all_midi and selected.is_midi
        has_pooled = has_pooled or selected.is_midi and selected.pooled
    end
    if all_midi then
        if r.ImGui_MenuItem(ctx, "Pool selected MIDI to this item") then batch_pool_to_source(entry, entries) end
    else
        r.ImGui_TextDisabled(ctx, "Pool selected MIDI to this item")
    end
    if has_pooled then
        if r.ImGui_MenuItem(ctx, "Unpool selected MIDI") then batch_unpool(entries) end
    else
        r.ImGui_TextDisabled(ctx, "Unpool selected MIDI")
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Enable loop for selected") then batch_set_loop(entries, "enable") end
    if r.ImGui_MenuItem(ctx, "Disable loop for selected") then batch_set_loop(entries, "disable") end
    if r.ImGui_MenuItem(ctx, "Toggle loop for selected") then batch_set_loop(entries, "toggle") end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Mute selected") then batch_set_item_flag(entries, "B_MUTE", true, "Mute selected project clips") end
    if r.ImGui_MenuItem(ctx, "Unmute selected") then batch_set_item_flag(entries, "B_MUTE", false, "Unmute selected project clips") end
    if r.ImGui_MenuItem(ctx, "Lock selected") then batch_set_item_flag(entries, "C_LOCK", true, "Lock selected project clips") end
    if r.ImGui_MenuItem(ctx, "Unlock selected") then batch_set_item_flag(entries, "C_LOCK", false, "Unlock selected project clips") end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Rename selected...") then batch_rename(entries) end
    local has_missing = false
    for _, selected in ipairs(entries) do has_missing = has_missing or selected.missing end
    if has_missing then
        if r.ImGui_MenuItem(ctx, "Relink missing selected...") then relink_missing_selected(entries) end
    else
        r.ImGui_TextDisabled(ctx, "Relink missing selected...")
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Select all visible") then
        r.SelectAllMediaItems(0, false)
        for _, current in ipairs(state.items) do
            local item = item_from_guid(current.guid)
            current.selected = item ~= nil
            if item then r.SetMediaItemSelected(item, true) end
        end
        r.UpdateArrange()
    end
    if r.ImGui_MenuItem(ctx, "Clear selection") then
        r.SelectAllMediaItems(0, false)
        for _, current in ipairs(state.items) do current.selected = false end
        r.UpdateArrange()
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Delete selected") then batch_delete(entries) end
    r.ImGui_EndPopup(ctx)
    return true
end

local function draw_card(entry)
    local card_width = rounded(CARD_WIDTH)
    local card_height = rounded(CARD_HEIGHT)
    local preview_height = rounded(PREVIEW_HEIGHT)
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_InvisibleButton(ctx, "##clip_" .. entry.guid, card_width, card_height)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local selected = entry.selected
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local inverse = inverse_tiles_active(entry)
    local background = selected and COLORS.card_selected or hovered and COLORS.card_hover or COLORS.card_bg
    local border = entry.missing and COLORS.danger or selected and COLORS.accent or hovered and entry.track_color or COLORS.border
    if inverse then
        background = selected and mix_color(entry.track_color, 0xFFFFFFFF, 0.2) or hovered and mix_color(entry.track_color, 0xFFFFFFFF, 0.1) or entry.track_color
        border = selected and contrast_color(background, false) or mix_color(entry.track_color, 0x000000FF, 0.35)
    end
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + card_width, cursor_y + card_height, background, scaled(5))
    r.ImGui_DrawList_AddRect(draw_list, cursor_x, cursor_y, cursor_x + card_width, cursor_y + card_height, border, scaled(5), 0, selected and scaled(2) or scaled(1))
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + scaled(4), cursor_y + card_height, inverse and 0x101216FF or entry.track_color, scaled(5))
    local preview_x = cursor_x + scaled(10)
    local preview_y = cursor_y + scaled(7)
    local preview_width = card_width - scaled(18)
    if entry.is_midi then
        draw_midi_preview(draw_list, entry, preview_x, preview_y, preview_width, preview_height)
    else
        draw_audio_preview(draw_list, entry, preview_x, preview_y, preview_width, preview_height)
    end
    draw_playback_progress(entry, draw_list, preview_x, preview_y, preview_width, preview_height)
    local play_button_hovered = draw_play_button(entry, cursor_x, cursor_y)
    local delete_button_hovered = draw_delete_button(entry, cursor_x, cursor_y)
    local toggles_hovered = draw_item_toggles(entry, cursor_x, cursor_y, card_width)
    r.ImGui_DrawList_AddLine(draw_list, cursor_x + scaled(8), cursor_y + scaled(94), cursor_x + card_width - scaled(8), cursor_y + scaled(94), clip_grid_color(entry), scaled(1))
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(99), clip_text_color(entry, false), truncate_text(entry.name, card_width - scaled(72)))
    local type_label = entry.is_midi and "MIDI" or "AUDIO"
    local type_color = clip_color(entry, entry.is_midi and COLORS.midi or COLORS.audio)
    local type_width = r.ImGui_CalcTextSize(ctx, type_label)
    r.ImGui_DrawList_AddText(draw_list, cursor_x + card_width - type_width - scaled(10), cursor_y + scaled(99), type_color, type_label)
    local metadata = entry.missing and "MISSING  |  " .. clip_metadata(entry) or clip_metadata(entry)
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(116), entry.missing and COLORS.danger or clip_text_color(entry, true), truncate_text(metadata, card_width - scaled(20)))
    local controls_hovered = play_button_hovered or delete_button_hovered or toggles_hovered
    if not controls_hovered and hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
        open_item_editor(entry)
    elseif not controls_hovered and r.ImGui_IsItemClicked(ctx, 0) then
        select_card(entry, r.JS_Mouse_GetState(4) == 4)
    elseif not controls_hovered and r.ImGui_IsItemClicked(ctx, 1) and not entry.selected then
        select_card(entry, false)
    end
    local context_open = draw_card_context(entry)
    if not context_open and state.suppress_drag_guid ~= entry.guid then begin_item_drag(entry) end
end

local function draw_source_card(entry)
    local card_width = rounded(CARD_WIDTH)
    local card_height = rounded(CARD_HEIGHT)
    local preview_height = rounded(PREVIEW_HEIGHT)
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_InvisibleButton(ctx, "##source_" .. entry.source_key, card_width, card_height)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local background = hovered and COLORS.card_hover or COLORS.card_bg
    local border = entry.missing and COLORS.danger or hovered and entry.track_color or COLORS.border
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + card_width, cursor_y + card_height, background, scaled(5))
    r.ImGui_DrawList_AddRect(draw_list, cursor_x, cursor_y, cursor_x + card_width, cursor_y + card_height, border, scaled(5), 0, scaled(1))
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + scaled(4), cursor_y + card_height, entry.track_color, scaled(5))
    local preview_x = cursor_x + scaled(10)
    local preview_y = cursor_y + scaled(7)
    local preview_width = card_width - scaled(18)
    if entry.is_midi then
        draw_midi_preview(draw_list, entry, preview_x, preview_y, preview_width, preview_height)
    else
        draw_audio_preview(draw_list, entry, preview_x, preview_y, preview_width, preview_height)
    end
    draw_playback_progress(entry, draw_list, preview_x, preview_y, preview_width, preview_height)
    local play_button_hovered = draw_play_button(entry, cursor_x, cursor_y)
    r.ImGui_DrawList_AddLine(draw_list, cursor_x + scaled(8), cursor_y + scaled(94), cursor_x + card_width - scaled(8), cursor_y + scaled(94), COLORS.grid, scaled(1))
    local type_label = entry.is_midi and "MIDI" or "AUDIO"
    local type_width = r.ImGui_CalcTextSize(ctx, type_label)
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(99), COLORS.text, truncate_text(entry.name, card_width - type_width - scaled(34)))
    r.ImGui_DrawList_AddText(draw_list, cursor_x + card_width - type_width - scaled(10), cursor_y + scaled(99), entry.track_color, type_label)
    local usage_label = tostring(entry.usage_count) .. (entry.usage_count == 1 and " use" or " uses")
    local metadata = (entry.missing and "MISSING  |  " or "") .. usage_label .. "  |  " .. format_length(entry.length) .. "  |  " .. entry.source_type
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(116), entry.missing and COLORS.danger or COLORS.text_dim, truncate_text(metadata, card_width - scaled(20)))
    if hovered and not play_button_hovered and entry.path ~= "" then r.ImGui_SetTooltip(ctx, entry.path) end
    if not play_button_hovered and r.ImGui_IsItemClicked(ctx, 0) then select_and_reveal(entry) end
    local context_open = r.ImGui_BeginPopupContextItem(ctx, "##source_context_" .. entry.source_key)
    if context_open then
        if r.ImGui_MenuItem(ctx, "Select all uses") then select_all_source_uses(entry) end
        if r.ImGui_MenuItem(ctx, "Select first and reveal") then select_and_reveal(entry) end
        if entry.missing then
            if r.ImGui_MenuItem(ctx, "Relink missing source...") then relink_source(entry) end
        else
            r.ImGui_TextDisabled(ctx, "Relink missing source...")
        end
        r.ImGui_EndPopup(ctx)
    end
    if not context_open and state.suppress_drag_guid ~= entry.guid then begin_item_drag(entry) end
end

local function draw_sources()
    local available = r.ImGui_GetContentRegionAvail(ctx)
    local card_width = rounded(CARD_WIDTH)
    local card_height = rounded(CARD_HEIGHT)
    local gap = rounded(8)
    local columns = math.max(1, math.floor((available + gap) / (card_width + gap)))
    if r.ImGui_BeginTable(ctx, "source_media", columns, r.ImGui_TableFlags_SizingFixedFit()) then
        for entry_index, entry in ipairs(state.sources) do
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_PushID(ctx, entry_index)
            if r.ImGui_IsRectVisible(ctx, card_width, card_height) then
                draw_source_card(entry)
            else
                r.ImGui_Dummy(ctx, card_width, card_height)
            end
            r.ImGui_PopID(ctx)
        end
        r.ImGui_EndTable(ctx)
    end
end

local function draw_group(group)
    local collapsed = state.collapsed_tracks[group.guid] == true
    local button_size = rounded(16)
    local button_x, button_y = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##collapse_track_" .. group.guid, button_size, button_size) then
        state.collapsed_tracks[group.guid] = not collapsed
        collapsed = not collapsed
        save_collapsed_tracks()
    end
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local center_x = button_x + button_size * 0.5
    local center_y = button_y + button_size * 0.5
    local triangle = scaled(3.5)
    if collapsed then
        r.ImGui_DrawList_AddTriangleFilled(draw_list, center_x - triangle * 0.6, center_y - triangle, center_x - triangle * 0.6, center_y + triangle, center_x + triangle, center_y, group.color)
    else
        r.ImGui_DrawList_AddTriangleFilled(draw_list, center_x - triangle, center_y - triangle * 0.6, center_x + triangle, center_y - triangle * 0.6, center_x, center_y + triangle, group.color)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, collapsed and "Expand track" or "Collapse track") end
    r.ImGui_SameLine(ctx, 0, rounded(4))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), group.color)
    r.ImGui_Text(ctx, tostring(group.index + 1) .. "  " .. group.name)
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, COLORS.text_dim, tostring(#group.items) .. (#group.items == 1 and " clip" or " clips"))
    if collapsed then
        r.ImGui_Spacing(ctx)
        return
    end
    local available = r.ImGui_GetContentRegionAvail(ctx)
    local card_width = rounded(CARD_WIDTH)
    local card_height = rounded(CARD_HEIGHT)
    local gap = rounded(8)
    local columns = math.max(1, math.floor((available + gap) / (card_width + gap)))
    if r.ImGui_BeginTable(ctx, "clips_" .. tostring(group.index), columns, r.ImGui_TableFlags_SizingFixedFit()) then
        for entry_index, entry in ipairs(group.items) do
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_PushID(ctx, entry_index)
            if r.ImGui_IsRectVisible(ctx, card_width, card_height) then
                draw_card(entry)
            else
                r.ImGui_Dummy(ctx, card_width, card_height)
            end
            r.ImGui_PopID(ctx)
        end
        r.ImGui_EndTable(ctx)
    end
    r.ImGui_Spacing(ctx)
end

local function push_theme()
    UIScale.set(state.ui_scale)
    local theme_stack = Theme.push(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), COLORS.text_dim)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COLORS.accent)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), scaled(1))
    return theme_stack
end

local function pop_theme(theme_stack)
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 2)
    Theme.pop(ctx, theme_stack)
end

local function draw_window()
    state.cache_budget = 4
    local scaled_font_pushed = push_scaled_font()
    local theme_stack = push_theme()
    r.ImGui_SetNextWindowSize(ctx, rounded(760), rounded(520), r.ImGui_Cond_FirstUseEver())
    local visible
    visible, state.open = r.ImGui_Begin(ctx, SCRIPT_NAME, state.open, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse())
    if visible then
        draw_header()
        r.ImGui_Separator(ctx)
        draw_toolbar()
        r.ImGui_Separator(ctx)
        local launcher_mode = state.view_mode == "launcher"
        local status_text = launcher_mode and Launcher.status() or state.status
        local empty = not launcher_mode and (state.view_mode == "sources" and #state.sources == 0 or #state.groups == 0)
        if empty then
            local empty_label = state.view_mode == "sources" and "No matching source media" or "No matching project clips"
            local message = state.selected_track_only and not r.GetSelectedTrack(0, 0) and "Select a track to show its media" or empty_label
            r.ImGui_TextColored(ctx, COLORS.text_dim, message)
        else
            local scroll_flags = state.hide_content_scrollbar and r.ImGui_WindowFlags_NoScrollbar() or 0
            if launcher_mode then
                scroll_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
            end
            if r.ImGui_BeginChild(ctx, "clip_scroll", 0, status_text ~= "" and -rounded(28) or 0, 0, scroll_flags) then
                if launcher_mode then
                    Launcher.draw()
                elseif state.view_mode == "sources" then
                    draw_sources()
                else
                    for _, group in ipairs(state.groups) do draw_group(group) end
                end
                r.ImGui_EndChild(ctx)
            end
        end
        if status_text ~= "" then r.ImGui_TextColored(ctx, COLORS.accent, status_text) end
        r.ImGui_End(ctx)
    end
    draw_theme_settings()
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        if state.theme_settings_open then
            state.theme_settings_open = false
        else
            state.open = false
        end
    end
    pop_theme(theme_stack)
    if scaled_font_pushed then r.ImGui_PopFont(ctx) end
end

local function cleanup()
    if state.preview_guid then stop_item_preview() end
    Launcher.shutdown()
    set_action_state(false)
end

local function loop()
    Launcher.set_active(state.view_mode == "launcher")
    if state.view_mode ~= "launcher" then refresh_if_needed() end
    update_item_preview()
    update_drag()
    Launcher.update()
    draw_window()
    if state.open then r.defer(loop) end
end

set_action_state(true)
r.atexit(cleanup)
scan_project()
r.defer(loop)