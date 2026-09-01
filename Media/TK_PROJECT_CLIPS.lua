-- @description TK Project Clips
-- @author TouristKiller
-- @version 0.6.1
-- @changelog:
--   + Launcher: A Launchpad is taken over in DAW mode now, the way Ableton and PlayTime do it: the board keeps its own Session and Custom buttons and its second port stays free for playing. Reported by AndreiMir
--   + Launcher: Programmer mode is still on offer for a board that will not talk in DAW mode
--   + Launcher: In DAW mode the scene strip on the right works as control changes, lit and read
--   + Launcher: On the RGB boards a clip waiting for its bar line flashes and the playing clip pulses in hardware, instead of being blinked from the script
--   + Launcher: Configurable MIDI control with Keyboard, Pads and Custom Grid layouts, banking and scene launching
--   + Launcher: MIDI Learn for notes and commands, with reusable MIDI setup presets
--   + Launcher: Launchpad layout - the 8 x 8 note grid of a Mini MK3, X, Pro MK3, MK2, S or Mini MK1, with the right hand strip launching scenes
--   + Launcher: The pads light up with the grid - filled, playing, waiting and armed - in the clip's own colour where the board has one
--   + Launcher: Faster scene switching with fewer project-state writes and a shorter retrigger horizon
--   + Launcher: Automation lanes follow their Arrange envelope heights and can follow, pause or resume independently
--   + Launcher: Import a selected Arrange automation item into the matching automation clip lane
--   + Launcher: Automation clips - a clip that is a curve instead of a sound, played as an automation item on the track's own envelope, on the same bar line as everything else
--   + Launcher: Automation clips sit in a lane of their own under the track lane, one per parameter, so a curve runs while the track's clip keeps playing
--   + Launcher: A clip takes the curves in its row with it, a curve can be fired on its own, and stopping a track stops its curves
--   + Launcher: Draw a curve in the arrange from the clip's own menu and take it back into the clip, its length with it
--   + Launcher: Load and save REAPER's own automation items, the AutomationItems folder and everything under it
--   + Launcher: Hold to play works for a curve as well, with no gate effect involved
--   + Launcher: When it has played reads Next scene literally, with Next scene with a clip for skipping the empty rows
--   + Launcher: The FX button lists the FX already on the track - click opens one floating, right-click bypasses it
--   + Launcher: A stop-all square beside the bar count and the time signature
--   + Launcher: The play triangle leads the scene number
--   + Items and Source Media can include open project tabs and loaded subprojects
--   + Filter Items and Source Media by project, tab or subproject
--   + Insert or drag clips from another project into the active project
--   + Added separate tile scaling for Items, Source Media and Automation
--   + Fixed project-aware GUID handling and track collapse controls
--   + Launcher: MIDI clips can follow chord roots or scale degrees from a guide track
--   + Launcher: Session Key Off plus Fit every clip now restores original pitches
--   + Launcher: Captured, fitted and followed MIDI clips keep independent sources
--   + Launcher: Lane headers can rename and colour their linked project tracks
--   + Launcher: Retriggered one-shots keep playing across transport loops
--   + Launcher: Recording, MIDI editor updates and clip indicators are more reliable
--   + Launcher: Record what you play into an empty slot, one button, on the launch quantize
--   + Launcher: Clips can click-stop, click-restart, or play only while held
--   + Launcher: Hold-to-play uses a small gate effect the script writes and installs itself
--   + Launcher: A clip can be played at 0.25x to 2x, pitch preserved
--   + Launcher: An empty slot can make a blank MIDI clip of 1 to 8 bars
--   + Launcher: A MIDI clip opens in the MIDI editor from its own menu, and its picture follows the notes
--   + Launcher: An FX button per lane header - your TK FX Browser folders, then Category, Developer, Folders, All plugins, Favorites, Recent and FX chains
--   + Launcher: The fader and FX button show in the upright layout too
--   + Launcher: Envelope lanes under a track keep the rows below them level
--   + Launcher: Launch quantize counts real bar lines, so a meter change cannot drift off them
--   + Launcher: Clip menu regrouped, launch mode is now Trigger
--   + Automation tab: the project's automation items, one card per pool, with a curve and where it is used
--   + Automation: go to any instance, insert pooled or unpooled on any envelope, rename a pool, select every instance
--   + Automation: take envelopes included, sorting by name, uses or length, positions in bars
--   + Launcher: Every track is a lane, in track order
--   + Launcher: Lane tracks made with the first clip, removed with the last
--   + Launcher: Bitwig layout - scenes as columns, rows at track height
--   + Launcher: Lanes and arrange scroll in step
--   + Launcher: Volume fader and solo in the lane headers
--   + Launcher: Session key and mode, with scale-degree or root fitting
--   + Launcher: Clip key read from metadata, file name, folder or notes
--   + Launcher: Transposed clips marked, chord names in the clip menu
--   + Launcher: Tempo and Key submenus in the clip menu
--   + Launcher: Bar and time signature in the grid corner, odd meters supported
--   + Launcher: Clip sets saved to file and loaded by track name
--   + Launcher: Clip set library with a folder per production
--   + Launcher: Sync BPM reads ACID beat counts
--   + Launcher: Toolbar grouped, with an overflow menu
--   + Launcher: Title bar and toolbar fold away from the grid corner
--   + Launcher: Coloured lane headers and a theme colour for empty clip tiles
--   + Settings window sizes itself
--   + Launcher: Files dropped from REAPER's Media Explorer and the Windows Explorer
--   + Launcher: Clips taken from the TK browsers, files, and arrange items
--   + Launcher: Audio stretched to the project tempo, read from metadata or file name
--   + Launcher: Retrigger every 1/16 to 2 bars, on chosen steps of the bar
--   + Launcher: A clip from a trimmed arrange item loops the trimmed length
--   + Launcher: Cells draw the clip, with a Compact name-only toggle
--   + Launcher: Clips renamed and coloured, freely or from twelve swatches
--   + Launcher: Grid scrolls both ways, shift or ctrl plus the wheel for sideways
--   + Launcher: Play position bar along the bottom of a playing cell
--   + Launcher: Clip lengths read live, so a tempo change is followed
--   + Launcher: Clips dragged onto the arrange with Alt, the cursor marking the landing
--   + Launcher: Alt-drag between slots to move, ctrl to copy
--   + Launcher: Clips keep playing across an arrangement loop
--   + Launcher: Scenes and clips written back to the arrangement at the edit cursor
--   + Launcher: Write scene chain follows the follow actions without playing them
--   + Launcher: Scene rows show their length in bars
--   + Launcher: Recording of a live performance, kept or discarded afterwards
--   + Launcher: Recording finishes the bar and captures the clips still playing
--   + Launcher: Record button and lane headers count what has been gathered
--   + Launcher: Follow actions per scene and per clip, with a Follow switch
--   + Launcher: Gain slider per clip
--   + Launcher: A scene stops the lanes with no clip in that row
--   + Launcher: Launch quantize, clip run-up and media buffer behind one Timing button
--   + Launcher: Clip run-up defaults to Auto, from REAPER's media buffer size
--   + Launcher: Grid played from the keyboard, Delete clears a slot, Ctrl+Z passed through
--   + Launcher: "+ Scene" takes a slice of the arrangement into a scene row
--   + Launcher: Mute song toggle, on by default and remembered per project
--   + Launcher: Per lane "A" button mutes that track's arrangement only
--   + Launcher: Reset puts everything the launcher touched back
--   + Launcher: Dead lanes and missing clips are marked and refuse to launch
--   + Launcher: Lane tracks gathered in a hidden TK LAUNCHER folder, with a Show tracks toggle
--   + Launcher: Mute states mirrored into the project, so an interrupted session recovers
--   + Launcher: Clips scheduled onto the timeline ahead of the cursor, landing on the bar
--   + Launcher: Lanes are hidden tracks feeding the real track, keeping its FX and routing
--   + Added a Launcher view that plays clips as a quantized clip grid
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
local TILE_SCALE_OPTIONS = {
    { label = "60%", value = 0.6 },
    { label = "70%", value = 0.7 },
    { label = "80%", value = 0.8 },
    { label = "90%", value = 0.9 },
    { label = "100%", value = 1.0 },
    { label = "115%", value = 1.15 },
    { label = "130%", value = 1.3 },
}
-- The settings window lays out to this width and sizes itself to it. Nothing
-- inside may ask the window how wide it is: an auto-fitting window whose
-- content stretches to the window can never shrink, it can only creep.
-- The widest row is the two columns of launcher switches, about 490.
local SETTINGS_WIDTH = 500

local THEME_COLOR_FIELDS = {
    { key = "window_bg", label = "Window" },
    { key = "child_bg", label = "Panel" },
    { key = "clip_bg", label = "Clip Tile" },
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
    clip_bg = Theme.colors.clip_bg or Theme.colors.child_bg,
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
local saved_automation_sort = r.GetExtState(EXT_SECTION, "automation_sort")
if not ({ name = true, uses = true, length = true })[saved_automation_sort] then saved_automation_sort = "name" end
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
    automation_sort = saved_automation_sort,
    sort_descending = r.GetExtState(EXT_SECTION, "sort_descending") == "1",
    hide_content_scrollbar = r.GetExtState(EXT_SECTION, "hide_content_scrollbar") == "1",
    selected_track_only = false,
    include_project_tabs = r.GetExtState(EXT_SECTION, "include_project_tabs") == "1",
    include_subprojects = r.GetExtState(EXT_SECTION, "include_subprojects") == "1",
    project_filter = nil,
    snap = true,
    color_mode = saved_color_mode,
    position_mode = r.GetExtState(EXT_SECTION, "position_mode") == "time" and "time" or "bars",
    collapsed_tracks = {},
    items = {},
    groups = {},
    sources = {},
    automation = {},
    waveform_cache = {},
    midi_cache = {},
    signature = "",
    last_scan = 0,
    media_availability_signature = "",
    last_media_availability_check = 0,
    subproject_sources = {},
    subproject_sources_key = "",
    next_subproject_scan = 0,
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
    tile_scale = tonumber(r.GetExtState(EXT_SECTION, "tile_scale")) or 1.0,
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
state.tile_scale = clamp(state.tile_scale, 0.6, 1.3)
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

local function tile_scale_label()
    for _, option in ipairs(TILE_SCALE_OPTIONS) do
        if math.abs(state.tile_scale - option.value) < 0.01 then return option.label end
    end
    return tostring(math.floor(state.tile_scale * 100 + 0.5)) .. "%"
end

local function set_tile_scale(value)
    state.tile_scale = clamp(tonumber(value) or 1.0, 0.6, 1.3)
    r.SetExtState(EXT_SECTION, "tile_scale", tostring(state.tile_scale), true)
end

local function sync_theme_colors()
    COLORS.window_bg = Theme.colors.window_bg
    COLORS.child_bg = Theme.colors.child_bg
    COLORS.clip_bg = Theme.colors.clip_bg or Theme.colors.child_bg
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

local function group_collapse_key(group)
    return tostring(group.project_name or "Project") .. "::" .. tostring(group.guid or "")
end

local function set_all_tracks_collapsed(collapsed)
    state.collapsed_tracks = {}
    if collapsed then
        for _, group in ipairs(state.groups) do
            state.collapsed_tracks[group_collapse_key(group)] = true
        end
    end
    save_collapsed_tracks()
end

local function all_tracks_collapsed()
    if #state.groups == 0 then return false end
    for _, group in ipairs(state.groups) do
        local key = group_collapse_key(group)
        if not state.collapsed_tracks[key] and not state.collapsed_tracks[group.guid] then return false end
    end
    return true
end

local function get_scaled_font()
    local font_size = math.max(8, math.floor(14 * state.ui_scale + 0.5))
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

local function begin_tile_scale()
    local ui_scale = state.ui_scale
    state.ui_scale = ui_scale * state.tile_scale
    return ui_scale, push_scaled_font()
end

local function end_tile_scale(ui_scale, font_pushed)
    if font_pushed then r.ImGui_PopFont(ctx) end
    state.ui_scale = ui_scale
end

local function set_action_state(enabled)
    local _, _, section_id, command_id = r.get_action_context()
    if section_id and command_id and command_id > 0 then
        r.SetToggleCommandState(section_id, command_id, enabled and 1 or 0)
        r.RefreshToolbar2(section_id, command_id)
    end
end

local function media_item_guid(item)
    if not item then return nil end
    local ok, guid = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
    if ok and guid and guid ~= "" then return guid end
    local called, fallback = pcall(r.BR_GetMediaItemGUID, item)
    return called and fallback or nil
end

local function item_from_guid(guid, project)
    if not guid or guid == "" then return nil end
    project = project or 0
    if project == 0 or project == select(1, r.EnumProjects(-1, "")) then
        local ok, item = pcall(r.BR_GetMediaItemByGUID, project, guid)
        if ok and item then return item end
    end
    local ok, count = pcall(r.CountMediaItems, project)
    if not ok then return nil end
    for index = 0, (count or 0) - 1 do
        local called, item = pcall(r.GetMediaItem, project, index)
        if called and item and media_item_guid(item) == guid then return item end
    end
    return nil
end

local function activate_project(project)
    if not project then return false end
    local current = select(1, r.EnumProjects(-1, ""))
    if current ~= project then
        local ok = pcall(r.SelectProjectInstance, project)
        if not ok then return false end
    end
    return select(1, r.EnumProjects(-1, "")) == project
end

local function item_from_entry(entry, activate)
    if not entry then return nil end
    if activate and not activate_project(entry.project) then return nil end
    return item_from_guid(entry.guid, entry.project)
end

local function project_name(project, path)
    local called, ok, name = pcall(r.GetProjectName, project, "")
    if called and ok and name and name ~= "" then return name end
    name = tostring(path or ""):match("([^/\\]+)%.rpp$")
    return name and name ~= "" and name or "Unsaved project"
end

local function project_item_count(project)
    local ok, count = pcall(r.CountMediaItems, project)
    return ok and math.max(0, math.floor(tonumber(count) or 0)) or 0
end

local function project_state_count(project)
    local ok, count = pcall(r.GetProjectStateChangeCount, project)
    return ok and tonumber(count) or 0
end

local function project_sources()
    local current, current_path = r.EnumProjects(-1, "")
    local projects = {}
    local seen = {}
    local function add(project, path, kind)
        if not project or seen[project] then return end
        seen[project] = true
        projects[#projects + 1] = {
            project = project,
            path = path or "",
            name = project_name(project, path),
            kind = kind,
        }
    end
    add(current, current_path, "current")
    if state.include_project_tabs then
        local index = 0
        while true do
            local project, path = r.EnumProjects(index, "")
            if not project then break end
            add(project, path, "tab")
            index = index + 1
        end
    end
    if state.include_subprojects and r.GetSubProjectFromSource then
        local roots = {}
        for _, source in ipairs(projects) do roots[#roots + 1] = tostring(source.project) end
        local roots_key = table.concat(roots, "|")
        local now = r.time_precise()
        if state.subproject_sources_key == roots_key and now < state.next_subproject_scan then
            for _, source in ipairs(state.subproject_sources) do add(source.project, source.path, source.kind) end
            return projects
        end
        local function child_from_source(source)
            for _ = 1, 8 do
                if not source then return nil end
                local ok, child = pcall(r.GetSubProjectFromSource, source)
                if ok and child then return child end
                if not r.GetMediaSourceParent then return nil end
                local parent_ok, parent = pcall(r.GetMediaSourceParent, source)
                if not parent_ok or not parent or parent == source then return nil end
                source = parent
            end
            return nil
        end
        local cursor = 1
        while cursor <= #projects do
            local parent = projects[cursor].project
            for item_index = 0, project_item_count(parent) - 1 do
                local item = r.GetMediaItem(parent, item_index)
                for take_index = 0, (item and r.CountTakes(item) or 0) - 1 do
                    local take = r.GetTake(item, take_index)
                    local source = take and r.GetMediaItemTake_Source(take) or nil
                    local child = child_from_source(source)
                    if child then add(child, "", "subproject") end
                end
            end
            cursor = cursor + 1
        end
        state.subproject_sources = {}
        for _, source in ipairs(projects) do
            if source.kind == "subproject" then state.subproject_sources[#state.subproject_sources + 1] = source end
        end
        state.subproject_sources_key = roots_key
        state.next_subproject_scan = now + 1
    end
    return projects
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

local function format_position_bars(seconds, project)
    if not r.TimeMap2_timeToBeats then return format_position_time(seconds) end
    local ok, beat_position, measures, measure_length = pcall(r.TimeMap2_timeToBeats, project or 0, tonumber(seconds) or 0)
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

local function format_position(seconds, project)
    return state.position_mode == "time" and format_position_time(seconds) or format_position_bars(seconds, project)
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
    for _, source in ipairs(project_sources()) do
        for item_index = 0, project_item_count(source.project) - 1 do
            local item = r.GetMediaItem(source.project, item_index)
            local take = item and r.GetActiveTake(item) or nil
            if take and not r.TakeIsMIDI(take) then
                local _, path = source_identity(take, false)
                if path and path ~= "" then availability[#availability + 1] = path:lower() .. "=" .. (media_file_exists(path) and "1" or "0") end
            end
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
    local parts = { tostring(state.include_project_tabs), tostring(state.include_subprojects) }
    for _, source in ipairs(project_sources()) do
        parts[#parts + 1] = table.concat({
            tostring(source.project),
            tostring(source.path),
            tostring(project_state_count(source.project)),
            tostring(project_item_count(source.project)),
        }, ":")
    end
    return table.concat(parts, "|")
end

-- Automation items, gathered by pool rather than by instance. Pooling is the
-- whole point of them: ten copies of one pool are one thing used ten times,
-- the way a source file is in the Source Media view, so a row is a pool and
-- its instances hang underneath.
local function automation_pools()
    local pools, ordered = {}, {}
    if not r.CountAutomationItems then return ordered end
    local search = state.search:lower()

    local function gather(env, track, track_name, prefix)
        do
            local _, env_name = r.GetEnvelopeName(env, "")
            env_name = (prefix or "") .. (env_name or "Envelope")
            for slot = 0, (r.CountAutomationItems(env) or 0) - 1 do
                local id = math.floor(r.GetSetAutomationItemInfo(env, slot, "D_POOL_ID", 0, false) or -1)
                local ok, name = r.GetSetAutomationItemInfo_String(env, slot, "P_POOL_NAME", "", false)
                if not ok or not name or name == "" then name = "Pool " .. tostring(id) end
                local pool = pools[id]
                if not pool then
                    pool = { id = id, name = name, uses = {}, length = 0 }
                    pools[id] = pool
                    ordered[#ordered + 1] = pool
                end
                local length = r.GetSetAutomationItemInfo(env, slot, "D_LENGTH", 0, false) or 0
                if length > pool.length then pool.length = length end
                pool.uses[#pool.uses + 1] = {
                    env = env,
                    slot = slot,
                    track = track,
                    track_name = track_name,
                    env_name = env_name,
                    position = r.GetSetAutomationItemInfo(env, slot, "D_POSITION", 0, false) or 0,
                    length = length,
                    rate = r.GetSetAutomationItemInfo(env, slot, "D_PLAYRATE", 0, false) or 1,
                    loops = (r.GetSetAutomationItemInfo(env, slot, "D_LOOPSRC", 0, false) or 0) > 0.5,
                }
            end
        end
    end

    local function sweep_track(track, track_name)
        for index = 0, (r.CountTrackEnvelopes(track) or 0) - 1 do
            gather(r.GetTrackEnvelope(track, index), track, track_name)
        end
    end

    local master = r.GetMasterTrack(0)
    if master then sweep_track(master, "Master") end
    for index = 0, (r.CountTracks(0) or 0) - 1 do
        local track = r.GetTrack(0, index)
        if track and not is_launcher_track(track) then
            sweep_track(track, get_track_name(track, index))
        end
    end

    -- Take envelopes as well. Rarer than track ones, but a pool can live there
    -- and a bay that quietly leaves some out is worse than no bay.
    if r.CountTakeEnvelopes then
        for index = 0, (r.CountMediaItems(0) or 0) - 1 do
            local item = r.GetMediaItem(0, index)
            local take = item and r.GetActiveTake(item)
            local track = item and r.GetMediaItemTrack(item)
            if take and track and not is_launcher_track(track) then
                local track_index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 1) - 1
                local where = get_track_name(track, track_index)
                for slot = 0, (r.CountTakeEnvelopes(take) or 0) - 1 do
                    gather(r.GetTakeEnvelope(take, slot), track, where, "Take: ")
                end
            end
        end
    end

    -- Searched on the pool's own name and on where it is used, which is what
    -- someone actually remembers about one.
    local kept = {}
    for _, pool in ipairs(ordered) do
        local hit = search == "" or pool.name:lower():find(search, 1, true)
        if not hit then
            for _, use in ipairs(pool.uses) do
                if use.env_name:lower():find(search, 1, true)
                    or use.track_name:lower():find(search, 1, true) then hit = true break end
            end
        end
        if hit then kept[#kept + 1] = pool end
    end

    local key = state.automation_sort or "name"
    table.sort(kept, function(left, right)
        local a, b
        if key == "uses" then a, b = #left.uses, #right.uses
        elseif key == "length" then a, b = left.length, right.length
        else a, b = left.name:lower(), right.name:lower() end
        -- Ties fall back to the name, which is the order someone can follow,
        -- and then to the id, which is what keeps two pools of the same name
        -- from swapping places between frames and making the grid flicker.
        if a == b then a, b = left.name:lower(), right.name:lower() end
        if a == b then a, b = left.id, right.id end
        if state.sort_descending then return a > b end
        return a < b
    end)
    return kept
end
local function scan_project()
    local items = {}
    local groups = {}
    local sources_by_key = {}
    local current_project = select(1, r.EnumProjects(-1, ""))
    local selected_track = r.GetSelectedTrack(0, 0)
    local search = state.search:lower()
    launcher_track_cache = {}

    for project_index, project_source in ipairs(project_sources()) do
        local project = project_source.project
        local project_matches = not state.project_filter or state.project_filter == project
        for index = 0, project_item_count(project) - 1 do
            local item = r.GetMediaItem(project, index)
            local take = item and r.GetActiveTake(item) or nil
            local track = item and r.GetMediaItemTrack(item) or nil
            if take and track and not is_launcher_track(track) then
            local guid = media_item_guid(item)
            if not guid then goto continue_item end
            local is_midi = r.TakeIsMIDI(take)
            local type_matches = state.filter == "all" or (state.filter == "audio" and not is_midi) or (state.filter == "midi" and is_midi)
            local track_matches = not state.selected_track_only or project == current_project and track == selected_track
            local track_index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 1) - 1
            local name = get_take_name(take, is_midi and "MIDI item" or "Audio item")
            local track_name = get_track_name(track, track_index)
            local search_matches = search == "" or name:lower():find(search, 1, true)
                or track_name:lower():find(search, 1, true) or project_source.name:lower():find(search, 1, true)
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
            if project_matches and type_matches and track_matches then
                if source_key then
                    local grouped_source_key = is_midi and tostring(project) .. "|" .. source_key or source_key
                    local reference = { guid = guid, project = project, project_name = project_source.name }
                    local source_entry = sources_by_key[grouped_source_key]
                    if source_entry then
                        source_entry.usage_count = source_entry.usage_count + 1
                        source_entry.refs[#source_entry.refs + 1] = reference
                        source_entry.project_names[project_source.name] = true
                    else
                        local source = r.GetMediaItemTake_Source(take)
                        local source_length = source and select(1, r.GetMediaSourceLength(source)) or 0
                        local source_name = source_path ~= "" and (source_path:match("([^/\\]+)$") or name) or name
                        local track_native_color = r.GetTrackColor(track)
                        sources_by_key[grouped_source_key] = {
                            guid = guid,
                            project = project,
                            refs = { reference },
                            project_names = { [project_source.name] = true },
                            source_key = grouped_source_key,
                            name = source_name,
                            path = source_path,
                            missing = source_missing,
                            source_type = source_type,
                            usage_count = 1,
                            is_midi = is_midi,
                            track_index = track_index,
                            track_name = track_name,
                            track_color = is_midi and COLORS.midi or COLORS.audio,
                            has_track_color = false,
                            position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0,
                            length = is_midi and (r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0) or source_length,
                            take_count = 1,
                            active_take = 1,
                            looped = false,
                            pooled = pooled,
                            selected = false,
                            cache_key = "source|" .. grouped_source_key .. "|" .. item_signature(item, take),
                        }
                    end
                end
            end
            if project_matches and type_matches and track_matches and search_matches and status_matches then
                local track_guid = r.GetTrackGUID(track)
                local track_native_color = r.GetTrackColor(track)
                local track_color = native_color(track_native_color, COLORS.accent)
                local take_count = r.CountTakes(item) or 1
                local entry = {
                    guid = guid,
                    key = tostring(project) .. "|" .. guid,
                    project = project,
                    project_name = project_source.name,
                    project_kind = project_source.kind,
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
                    cache_key = tostring(project) .. "|" .. guid .. "|" .. item_signature(item, take),
                }
                items[#items + 1] = entry
                local group_key = tostring(project) .. "|" .. tostring(track_index)
                if not groups[group_key] then
                    groups[group_key] = {
                        index = track_index,
                        project_index = project_index,
                        project = project,
                        project_name = project_source.name,
                        guid = track_guid,
                        name = track_name,
                        color = track_color,
                        items = {},
                    }
                end
                groups[group_key].items[#groups[group_key].items + 1] = entry
            end
            end
            ::continue_item::
        end
    end

    local ordered_groups = {}
    for _, group in pairs(groups) do ordered_groups[#ordered_groups + 1] = group end
    table.sort(ordered_groups, function(left, right)
        if left.project_index == right.project_index then return left.index < right.index end
        return left.project_index < right.project_index
    end)
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
        local project_names = {}
        for name in pairs(source_entry.project_names) do project_names[#project_names + 1] = name end
        table.sort(project_names)
        source_entry.project_label = table.concat(project_names, ", ")
        local source_search = source_entry.name:lower() .. "\n" .. source_entry.path:lower() .. "\n"
            .. source_entry.source_type:lower() .. "\n" .. source_entry.project_label:lower()
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
    state.automation = automation_pools()
end

-- Adding or removing an automation item changes nothing the project signature
-- watches, so the tab would sit there stale. Counted only while it is the tab
-- on show, since it means walking every envelope on every track. A rename goes
-- through our own menu, which clears the signature outright.
local function automation_signature()
    if state.view_mode ~= "automation" or not r.CountAutomationItems then return "" end
    local total = 0
    local function count(track)
        for index = 0, (r.CountTrackEnvelopes(track) or 0) - 1 do
            total = total + (r.CountAutomationItems(r.GetTrackEnvelope(track, index)) or 0)
        end
    end
    local master = r.GetMasterTrack(0)
    if master then count(master) end
    for index = 0, (r.CountTracks(0) or 0) - 1 do
        local track = r.GetTrack(0, index)
        if track then count(track) end
    end
    return tostring(total)
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
    local signature = table.concat({ project_signature(), state.search, state.filter, state.status_filter, state.item_sort, state.source_sort, tostring(state.sort_descending), tostring(state.selected_track_only), automation_signature() }, "|")
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
    local item = item_from_entry(entry, false)
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
    local item = item_from_entry(entry, false)
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
    local item = item_from_entry(entry, true)
    if not item then return end
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    for _, current in ipairs(state.items) do current.selected = current.key == entry.key end
    local track = r.GetMediaItemTrack(item)
    if track then r.SetOnlyTrackSelected(track) end
    local position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0
    r.SetEditCurPos(position, true, false)
    r.UpdateArrange()
end

local function select_all_source_uses(entry)
    local selected_keys = {}
    local earliest_position = math.huge
    local selected_count = 0
    local reveal = entry.refs and entry.refs[1]
    for _, reference in ipairs(entry.refs or {}) do
        local item = item_from_guid(reference.guid, reference.project)
        if item then
            r.SetMediaItemSelected(item, true)
            selected_keys[tostring(reference.project) .. "|" .. reference.guid] = true
            if reference == reveal then earliest_position = r.GetMediaItemInfo_Value(item, "D_POSITION") or earliest_position end
            selected_count = selected_count + 1
        end
    end
    for _, current in ipairs(state.items) do current.selected = selected_keys[current.key] == true end
    if reveal and activate_project(reveal.project) and earliest_position < math.huge then r.SetEditCurPos(earliest_position, true, false) end
    state.status = "Selected " .. tostring(selected_count) .. (selected_count == 1 and " source use" or " source uses")
    r.UpdateArrange()
end

local function selected_entries()
    local entries = {}
    for _, entry in ipairs(state.items) do
        if entry.selected and item_from_entry(entry, false) then entries[#entries + 1] = entry end
    end
    return entries
end

local function insert_entry_at_cursor(entry)
    local target_project = select(1, r.EnumProjects(-1, ""))
    local target_track = target_project and r.GetSelectedTrack(target_project, 0) or nil
    if not target_track then
        state.status = "Select a target track first"
        return false
    end
    local source_item = item_from_entry(entry, false)
    if not source_item then
        state.status = "Source item is no longer available"
        return false
    end
    local ok, chunk = r.GetItemStateChunk(source_item, "", false)
    if not ok or not chunk or chunk == "" then
        state.status = "Could not read the source item"
        return false
    end
    local position = r.GetCursorPositionEx and r.GetCursorPositionEx(target_project) or r.GetCursorPosition()
    r.Undo_BeginBlock2(target_project)
    r.PreventUIRefresh(1)
    local item = r.AddMediaItemToTrack(target_track)
    local written = item and r.SetItemStateChunk(item, chunk, false)
    if written then
        r.GetSetMediaItemInfo_String(item, "GUID", r.genGuid(), true)
        for take_index = 0, (r.CountTakes(item) or 0) - 1 do
            local take = r.GetTake(item, take_index)
            if take then r.GetSetMediaItemTakeInfo_String(take, "GUID", r.genGuid(), true) end
        end
        r.SetMediaItemInfo_Value(item, "D_POSITION", position)
        r.SelectAllMediaItems(target_project, false)
        r.SetMediaItemSelected(item, true)
    elseif item then
        r.DeleteTrackMediaItem(target_track, item)
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock2(target_project, "Insert project clip at edit cursor", -1)
    r.UpdateArrange()
    state.status = written and ("Inserted " .. entry.name) or "Could not insert the source item"
    state.signature = ""
    state.last_scan = 0
    return written == true
end

local function select_card(entry, additive)
    local current_project = select(1, r.EnumProjects(-1, ""))
    local external = entry.project ~= current_project
    local item = item_from_entry(entry, false)
    if not item then return end
    if not additive then
        if not external then r.SelectAllMediaItems(0, false) end
        for _, current in ipairs(state.items) do current.selected = false end
    end
    local selected = additive and not entry.selected or true
    if not external then r.SetMediaItemSelected(item, selected) end
    entry.selected = selected
    if not additive and not external then
        local track = r.GetMediaItemTrack(item)
        if track then r.SetOnlyTrackSelected(track) end
        r.SetEditCurPos(r.GetMediaItemInfo_Value(item, "D_POSITION") or 0, true, false)
    end
    if external then
        state.status = "Selected from " .. entry.project_name
    else
        r.UpdateArrange()
    end
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
        state.preview_item_states[#state.preview_item_states + 1] = { guid = media_item_guid(current_item), muted = muted, volume = volume }
        local target_muted = current_item == item and 0 or 1
        if muted ~= target_muted then r.SetMediaItemInfo_Value(current_item, "B_MUTE", target_muted) end
    end
    r.PreventUIRefresh(-1)
    r.UpdateArrange()
    return true
end

local function restore_item_preview_isolation()
    if not state.preview_track_states and not state.preview_item_states then return end
    if state.preview_project then activate_project(state.preview_project) end
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
        local item = item_from_guid(saved.guid, state.preview_project)
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
    state.preview_project = nil
    state.preview_start = nil
    state.preview_end = nil
    state.preview_saved_cursor = nil
    state.preview_base_volume = nil
end

local function apply_preview_volume()
    local item = item_from_guid(state.preview_guid, state.preview_project)
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
    local item = item_from_entry(entry, true)
    if not item or not isolate_item_preview(item) then return end
    local play_state = r.GetPlayState and r.GetPlayState() or 0
    if (play_state & 1) == 1 or (play_state & 4) == 4 then
        if r.OnStopButton then r.OnStopButton() else r.Main_OnCommand(1016, 0) end
    end
    state.preview_saved_cursor = r.GetCursorPosition()
    state.preview_guid = entry.guid
    state.preview_project = entry.project
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
    if state.preview_guid == entry.guid and state.preview_project == entry.project then stop_item_preview() else start_item_preview(entry) end
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
    local item = item_from_entry(entry, true)
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
    local item = item_from_entry(entry, true)
    if not item then return end
    local selected_guids = {}
    for index = 0, r.CountSelectedMediaItems(0) - 1 do
        local selected_item = r.GetSelectedMediaItem(0, index)
        selected_guids[media_item_guid(selected_item)] = true
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
        if selected_guids[media_item_guid(current)] then r.SetMediaItemSelected(current, true) end
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
    local item = item_from_entry(entry, true)
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

local function entries_by_project(entries)
    local groups = {}
    for _, entry in ipairs(entries) do
        local project = entry.project or select(1, r.EnumProjects(-1, ""))
        if project then
            if not groups[project] then groups[project] = {} end
            groups[project][#groups[project] + 1] = entry
        end
    end
    return groups
end

local function batch_set_loop(entries, mode)
    if #entries == 0 then return end
    if state.preview_guid then stop_item_preview() end
    local label = mode == "toggle" and "Toggle source loop for selected items" or mode == "enable" and "Enable source loop for selected items" or "Disable source loop for selected items"
    for project, project_entries in pairs(entries_by_project(entries)) do
        r.Undo_BeginBlock2(project)
        for _, entry in ipairs(project_entries) do
            local item = item_from_entry(entry, false)
            if item then
                local current = (r.GetMediaItemInfo_Value(item, "B_LOOPSRC") or 0) > 0.5
                local looped = mode == "toggle" and not current or mode == "enable"
                r.SetMediaItemInfo_Value(item, "B_LOOPSRC", looped and 1 or 0)
                entry.looped = looped
            end
        end
        r.Undo_EndBlock2(project, label, -1)
    end
    finish_batch(label)
end

local function batch_set_item_flag(entries, property, enabled, label)
    if #entries == 0 then return end
    if state.preview_guid then stop_item_preview() end
    for project, project_entries in pairs(entries_by_project(entries)) do
        r.Undo_BeginBlock2(project)
        for _, entry in ipairs(project_entries) do
            local item = item_from_entry(entry, false)
            if item then r.SetMediaItemInfo_Value(item, property, enabled and 1 or 0) end
        end
        r.Undo_EndBlock2(project, label, -1)
    end
    finish_batch(label)
end

local function batch_rename(entries)
    if #entries == 0 then return end
    local accepted, base_name = r.GetUserInputs("Rename selected clips", 1, "Base name:,extrawidth=220", entries[1].name or "Clip")
    base_name = tostring(base_name or ""):match("^%s*(.-)%s*$") or ""
    if not accepted or base_name == "" then return end
    if state.preview_guid then stop_item_preview() end
    local digits = math.max(2, #tostring(#entries))
    local index = 0
    for project, project_entries in pairs(entries_by_project(entries)) do
        r.Undo_BeginBlock2(project)
        for _, entry in ipairs(project_entries) do
            index = index + 1
            local item = item_from_entry(entry, false)
            local take = item and r.GetActiveTake(item) or nil
            if take then
                local name = #entries == 1 and base_name or base_name .. " " .. string.format("%0" .. tostring(digits) .. "d", index)
                r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
            end
        end
        r.Undo_EndBlock2(project, "Rename selected project clips", -1)
    end
    finish_batch("Renamed " .. tostring(#entries) .. (#entries == 1 and " clip" or " clips"))
end

local function relink_entries(entries, replacement_path)
    local replaced = 0
    for _, entry in ipairs(entries) do
        local item = item_from_entry(entry, false)
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
    for _, replacement in ipairs(replacements) do
        for project, project_entries in pairs(entries_by_project(replacement.entries)) do
            r.Undo_BeginBlock2(project)
            replaced = replaced + relink_entries(project_entries, replacement.path)
            r.Undo_EndBlock2(project, "Relink missing selected media", -1)
        end
    end
    finish_batch("Relinked " .. tostring(replaced) .. (replaced == 1 and " clip" or " clips"))
end

local function relink_source(entry)
    if not entry.missing then return end
    local replacement = choose_replacement(entry.path)
    if not replacement then return end
    if state.preview_guid then stop_item_preview() end
    local entries = {}
    for _, reference in ipairs(entry.refs or {}) do
        entries[#entries + 1] = { guid = reference.guid, project = reference.project }
    end
    local replaced = 0
    for project, project_entries in pairs(entries_by_project(entries)) do
        r.Undo_BeginBlock2(project)
        replaced = replaced + relink_entries(project_entries, replacement)
        r.Undo_EndBlock2(project, "Relink missing source media", -1)
    end
    finish_batch("Relinked " .. tostring(replaced) .. (replaced == 1 and " use" or " uses"))
end

local function batch_unpool(entries)
    if state.preview_guid then stop_item_preview() end
    local eligible = {}
    for _, entry in ipairs(entries) do
        if entry.is_midi and entry.pooled then eligible[#eligible + 1] = entry end
    end
    if #eligible == 0 then return end
    for project, project_entries in pairs(entries_by_project(eligible)) do
        if activate_project(project) then
            r.Undo_BeginBlock2(project)
            r.PreventUIRefresh(1)
            for _, entry in ipairs(project_entries) do
                local item = item_from_entry(entry, false)
                if item then
                    r.SelectAllMediaItems(0, false)
                    r.SetMediaItemSelected(item, true)
                    r.Main_OnCommand(41613, 0)
                end
            end
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock2(project, "Unpool selected MIDI items", -1)
        end
    end
    finish_batch(tostring(#eligible) .. " MIDI item" .. (#eligible == 1 and "" or "s") .. " unpooled")
end

local ITEM_PROPERTIES = { "D_LENGTH", "B_MUTE", "B_LOOPSRC", "C_LOCK", "I_GROUPID", "I_CUSTOMCOLOR", "D_FADEINLEN", "D_FADEOUTLEN", "D_FADEINDIR", "D_FADEOUTDIR", "C_FADEINSHAPE", "C_FADEOUTSHAPE" }
local TAKE_PROPERTIES = { "D_PLAYRATE", "D_PITCH", "B_PPITCH", "I_CHANMODE", "D_VOL", "D_PAN", "I_CUSTOMCOLOR" }

local function snapshot_pool_target(entry)
    local item = item_from_entry(entry, false)
    local take = item and r.GetActiveTake(item) or nil
    local track = item and r.GetMediaItemTrack(item) or nil
    if not item or not take or not track then return nil end
    local snapshot = { guid = entry.guid, project = entry.project, track = track, position = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0, item_values = {}, take_values = {} }
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
    for _, entry in ipairs(entries) do
        if not entry.is_midi or entry.project ~= source_entry.project then
            state.status = "Pooling requires MIDI items from one project"
            return
        end
    end
    if state.preview_guid then stop_item_preview() end
    if not activate_project(source_entry.project) then return end
    local source_item = item_from_entry(source_entry, false)
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
        local original = item_from_guid(snapshot.guid, snapshot.project)
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
                result_guids[#result_guids + 1] = media_item_guid(pasted)
                replaced = replaced + 1
            else
                result_guids[#result_guids + 1] = snapshot.guid
            end
        end
    end
    r.SelectAllMediaItems(0, false)
    for _, guid in ipairs(result_guids) do
        local item = item_from_guid(guid, source_entry.project)
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
    for project, project_entries in pairs(entries_by_project(entries)) do
        r.Undo_BeginBlock2(project)
        for _, entry in ipairs(project_entries) do
            local item = item_from_entry(entry, false)
            local track = item and r.GetMediaItemTrack(item) or nil
            if item and track then
                r.DeleteTrackMediaItem(track, item)
                state.waveform_cache[entry.cache_key] = nil
                state.midi_cache[entry.cache_key] = nil
                deleted = deleted + 1
            end
        end
        r.Undo_EndBlock2(project, "Delete selected project clips", -1)
    end
    finish_batch(tostring(deleted) .. " item" .. (deleted == 1 and "" or "s") .. " deleted")
end

local function begin_item_drag(entry)
    if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceAllowNullID()) then
        state.drag = { guid = entry.guid, project = entry.project, is_midi = entry.is_midi, name = entry.name, source_path = entry.source_key and entry.path or nil }
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
    local source_item = drag and item_from_guid(drag.guid, drag.project) or nil
    if not drag or not track then return false end
    local target_project = select(1, r.EnumProjects(-1, ""))
    if state.preview_guid then stop_item_preview() end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    r.SetOnlyTrackSelected(track)
    r.SetEditCurPos(position, false, false)
    if source_item and drag.project ~= target_project then
        local ok, chunk = r.GetItemStateChunk(source_item, "", false)
        local item = ok and r.AddMediaItemToTrack(track) or nil
        local written = item and r.SetItemStateChunk(item, chunk, false)
        if written then
            r.GetSetMediaItemInfo_String(item, "GUID", r.genGuid(), true)
            for take_index = 0, (r.CountTakes(item) or 0) - 1 do
                local take = r.GetTake(item, take_index)
                if take then r.GetSetMediaItemTakeInfo_String(take, "GUID", r.genGuid(), true) end
            end
            r.SetMediaItemInfo_Value(item, "D_POSITION", position)
            r.SelectAllMediaItems(0, false)
            r.SetMediaItemSelected(item, true)
        else
            if item then r.DeleteTrackMediaItem(track, item) end
            r.PreventUIRefresh(-1)
            r.Undo_EndBlock("Insert project media", -1)
            return false
        end
    elseif drag.source_path and drag.source_path ~= "" and not drag.is_midi then
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

local VIEW_WIDTHS = { items = 74, sources = 112, automation = 100, launcher = 82 }

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
    local close_size = rounded(14)
    local settings_size = rounded(14)
    local gap = rounded(8)
    local items_width = rounded(VIEW_WIDTHS.items)
    local sources_width = rounded(VIEW_WIDTHS.sources)
    local launcher_width = rounded(VIEW_WIDTHS.launcher)
    local automation_width = rounded(VIEW_WIDTHS.automation)
    local tabs_width = items_width + sources_width + automation_width + launcher_width + rounded(22)
    -- Two gaps, not three: one before the settings dot and one before the close
    -- dot. The spacing inside the tabs is already part of tabs_width, and the
    -- extra gap was leaving the two dots sitting short of the right edge.
    local right_width = tabs_width + settings_size + close_size + gap * 2
    r.ImGui_TextColored(ctx, COLORS.accent, SCRIPT_NAME)
    -- Measured from the window frame rather than from the content edge: the
    -- content edge sits a whole window padding short of the border, and no
    -- offset based on the available width can reach past it. The margin is the
    -- one number to turn if the dots want to sit closer in or further out.
    local margin = rounded(4)
    local window_width = r.ImGui_GetWindowWidth(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, math.max(rounded(120), window_width - right_width - margin))
    view_button("Items", "items", #state.items)
    r.ImGui_SameLine(ctx, 0, rounded(7))
    view_button("Source Media", "sources", #state.sources)
    r.ImGui_SameLine(ctx)
    view_button("Automation", "automation", #state.automation)
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
    if r.ImGui_BeginCombo(ctx, "##settings_ui_scale", "UI " .. ui_scale_label()) then
        for _, option in ipairs(UI_SCALE_OPTIONS) do
            local selected = math.abs(state.ui_scale - option.value) < 0.01
            if r.ImGui_Selectable(ctx, option.label, selected) then set_ui_scale(option.value) end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "UI scale") end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, rounded(120))
    if r.ImGui_BeginCombo(ctx, "##settings_tile_scale", "Tiles " .. tile_scale_label()) then
        for _, option in ipairs(TILE_SCALE_OPTIONS) do
            local selected = math.abs(state.tile_scale - option.value) < 0.01
            if r.ImGui_Selectable(ctx, option.label, selected) then set_tile_scale(option.value) end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Tile size for Items, Source Media and Automation") end
    r.ImGui_SameLine(ctx)
    local scrollbar_changed, hide_scrollbar = r.ImGui_Checkbox(ctx, "Hide scrollbar", state.hide_content_scrollbar)
    if scrollbar_changed then
        state.hide_content_scrollbar = hide_scrollbar
        r.SetExtState(EXT_SECTION, "hide_content_scrollbar", hide_scrollbar and "1" or "0", true)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Keep mouse-wheel scrolling without showing the content scrollbar") end
    r.ImGui_Spacing(ctx)
    r.ImGui_TextColored(ctx, COLORS.text_dim, "Project sources")
    local tabs_changed, include_tabs = r.ImGui_Checkbox(ctx, "Include open project tabs", state.include_project_tabs)
    if tabs_changed then
        state.include_project_tabs = include_tabs
        r.SetExtState(EXT_SECTION, "include_project_tabs", include_tabs and "1" or "0", true)
        state.signature = ""
        state.last_scan = 0
        state.next_subproject_scan = 0
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Include items and source media from every open project tab") end
    r.ImGui_SameLine(ctx, 0, rounded(20))
    local subprojects_changed, include_subprojects = r.ImGui_Checkbox(ctx, "Include subprojects", state.include_subprojects)
    if subprojects_changed then
        state.include_subprojects = include_subprojects
        r.SetExtState(EXT_SECTION, "include_subprojects", include_subprojects and "1" or "0", true)
        state.signature = ""
        state.last_scan = 0
        state.next_subproject_scan = 0
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Include subprojects that REAPER has loaded for project items") end
    -- Laid out in two columns rather than one long line: these grew one at a
    -- time onto the same row until the last of them fell off the right edge.
    -- Each option opens and closes its own disabled scope, so a switch is greyed
    -- by what it actually depends on.
    r.ImGui_Spacing(ctx)
    r.ImGui_TextColored(ctx, COLORS.text_dim, "Launcher")
    local sideways = Launcher.scenes_as_columns()
    local sync = Launcher.scroll_sync()

    local function option(label, value, apply, tooltip, enabled)
        r.ImGui_TableNextColumn(ctx)
        local greyed = enabled == false
        if greyed and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
        local changed, now = r.ImGui_Checkbox(ctx, label, value)
        if changed then apply(now) end
        if greyed and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, greyed and "Needs Scenes as columns, where a lane is a row" or tooltip)
        end
    end

    -- Fixed-fit columns, so the table reports the width it needs instead of
    -- asking the window how wide it is while the window is asking the table.
    if r.ImGui_BeginTable(ctx, "##launcher_options", 2, r.ImGui_TableFlags_SizingFixedFit()) then
        r.ImGui_TableNextRow(ctx)
        option("Colour lane headers", Launcher.color_headers(),
            function(value) Launcher.set_color_headers(value) end,
            "Fill each lane header with its track's colour\ninstead of showing a stripe down its left edge")
        option("Clear the take after recording", Launcher.record_tidy(),
            function(value) Launcher.set_record_tidy(value) end,
            "Once a recorded slot has its clip, remove the take\n"
            .. "from the arrangement. The audio stays on disk.")
        option("Volume in the lane header", Launcher.lane_volume(),
            function(value) Launcher.set_lane_volume(value) end,
            "Put the track's fader at the foot of its lane header,\n"
            .. "so the track panel can be collapsed out of the way.\n"
            .. "Only where the row is tall enough to hold one.")
        option("Scenes as columns", sideways,
            function(value) Launcher.set_scenes_as_columns(value) end,
            "Turn the grid on its side, with a lane per row and a\nscene per column, the way Bitwig lays it out.\nClips keep their size.")

        r.ImGui_TableNextRow(ctx)
        option("Lane height follows the track", Launcher.lane_track_height(),
            function(value) Launcher.set_lane_track_height(value) end,
            "Give each lane row the height REAPER gives its track,\nso the grid lines up with the track panel beside it",
            sideways)
        option("Line up with the first track", Launcher.align_to_arrange(),
            function(value) Launcher.set_align_to_arrange(value) end,
            "Grow the header row until the first lane starts where its\ntrack does, so changing the ruler height above the tracks\ndoes not put the two out of step. It can only add space:\nwhere the grid starts below the track, fold this window's\nown bars away with the caret in the corner.",
            sideways)

        r.ImGui_TableNextRow(ctx)
        option("Scroll with the arrange", sync ~= "off",
            function(value) Launcher.set_scroll_sync(value and "follow" or "off") end,
            "Scrolling the arrange scrolls the grid to the same track",
            sideways)
        option("and the arrange with the grid", sync == "both",
            function(value) Launcher.set_scroll_sync(value and "both" or "follow") end,
            "Scrolling the grid scrolls the arrange as well.\nLeave it off and the launcher never moves your arrange by itself.",
            sideways and sync ~= "off")
        r.ImGui_EndTable(ctx)
    end
    r.ImGui_Spacing(ctx)
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
    local child_visible = r.ImGui_BeginChild(ctx, "##project_clips_theme_colors", rounded(SETTINGS_WIDTH - 16), rounded(282), 1)
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
    -- Auto-fit works from the size the window already had, so a smaller scale
    -- creeps towards the new width over several frames. Handing it a size of
    -- zero means "fit now", which makes the change land in one go. Only on the
    -- frame the scale actually changes, so the window is left alone otherwise.
    if state.settings_scale ~= UIScale.value() then
        state.settings_scale = UIScale.value()
        if r.ImGui_SetNextWindowSize then
            r.ImGui_SetNextWindowSize(ctx, 0, 0, r.ImGui_Cond_Always())
        end
    end
    -- The window measures its own contents instead of being given a size: a
    -- fixed number is a guess that goes stale the moment a switch is added, and
    -- that is exactly how the last two rows ended up cut off. Not resizable
    -- either - there is nothing to resize, it is always exactly as big as what
    -- is in it.
    local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse()
        | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoScrollbar()
        | r.ImGui_WindowFlags_NoScrollWithMouse() | r.ImGui_WindowFlags_AlwaysAutoResize()
    local visible, open = r.ImGui_Begin(ctx, "Settings##project_clips", state.theme_settings_open, window_flags)
    state.theme_settings_open = open
    if visible then
        r.ImGui_TextColored(ctx, COLORS.accent, "Settings")
        local close_size = rounded(14)
        r.ImGui_SameLine(ctx, rounded(SETTINGS_WIDTH) - close_size)
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

local function draw_project_filter(width)
    local projects = project_sources()
    local selected_source
    for _, source in ipairs(projects) do
        if source.project == state.project_filter then selected_source = source; break end
    end
    if state.project_filter and not selected_source then
        state.project_filter = nil
        state.signature = ""
    end
    local kind_labels = { current = "Current", tab = "Tab", subproject = "Subproject" }
    local label = selected_source and ((kind_labels[selected_source.kind] or "Project") .. ": " .. selected_source.name) or "All projects"
    r.ImGui_SetNextItemWidth(ctx, width)
    if r.ImGui_BeginCombo(ctx, "##project_source_filter", label) then
        if r.ImGui_Selectable(ctx, "All projects", state.project_filter == nil) then
            state.project_filter = nil
            state.signature = ""
        end
        r.ImGui_Separator(ctx)
        for _, source in ipairs(projects) do
            local source_label = (kind_labels[source.kind] or "Project") .. ": " .. source.name
            local selected = state.project_filter == source.project
            if r.ImGui_Selectable(ctx, source_label .. "##" .. tostring(source.project), selected) then
                state.project_filter = source.project
                state.signature = ""
            end
            if selected then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Show items and source media from one project") end
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
    local project_filter_visible = (state.view_mode == "items" or state.view_mode == "sources")
        and (state.include_project_tabs or state.include_subprojects)
    local project_filter_width = rounded(160)
    local group_buttons_width = state.view_mode == "items" and rounded(26) or 0
    local filter_sort_width = sort_width + rounded(52) + (state.view_mode == "items" and status_width + gap or 0)
    local desired_width = rounded(150 + 64 * 3) + checkbox_width + color_width + position_width + filter_sort_width
        + group_buttons_width + (project_filter_visible and project_filter_width + gap or 0) + gap * 13
    local compact = available < desired_width
    local single_control_row = compact and available >= rounded(380)
    local type_button_width = compact and math.floor((available - (single_control_row and checkbox_width + gap * 4 or gap * 2)) / 3) or rounded(64)
    local direction_width = rounded(52)
    local compact_group_width = state.view_mode == "items" and rounded(26) or 0
    local compact_combo_count = (state.view_mode == "items" and 2 or 1) + (project_filter_visible and 1 or 0)
    local compact_control_count = compact_combo_count + 1 + (state.view_mode == "items" and 1 or 0)
    local compact_combo_width = math.max(rounded(60), math.floor((available - direction_width - compact_group_width
        - gap * (compact_control_count - 1)) / compact_combo_count))
    r.ImGui_SetNextItemWidth(ctx, compact and available or math.max(rounded(150), math.min(rounded(320), available * 0.35)))
    local search_hint = state.view_mode == "sources" and "Search source name, path or type"
        or state.view_mode == "automation" and "Search pool name, track or envelope"
        or "Search clips or tracks"
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
    if project_filter_visible then
        if not compact then r.ImGui_SameLine(ctx, 0, gap) end
        draw_project_filter(compact and compact_combo_width or project_filter_width)
        if compact then r.ImGui_SameLine(ctx, 0, gap) end
    end
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
    local active_sort_width = compact and compact_combo_width or sort_width
    r.ImGui_SetNextItemWidth(ctx, active_sort_width)
    local sort_options = state.view_mode == "items" and { { "Position", "position" }, { "Name", "name" }, { "Length", "length" } }
        or state.view_mode == "automation" and { { "Name", "name" }, { "Uses", "uses" }, { "Length", "length" } }
        or { { "Name", "name" }, { "Uses", "uses" }, { "Length", "length" }, { "Type", "type" } }
    local sort_key = state.view_mode == "items" and state.item_sort
        or state.view_mode == "automation" and state.automation_sort or state.source_sort
    local sort_label = "Sort"
    for _, option in ipairs(sort_options) do if option[2] == sort_key then sort_label = option[1]; break end end
    if r.ImGui_BeginCombo(ctx, "##project_clips_sort", sort_label) then
        for _, option in ipairs(sort_options) do
            local selected = sort_key == option[2]
            if r.ImGui_Selectable(ctx, option[1], selected) then
                local field = state.view_mode == "items" and "item_sort"
                    or state.view_mode == "automation" and "automation_sort" or "source_sort"
                state[field] = option[2]
                state.signature = ""
                r.SetExtState(EXT_SECTION, field, option[2], true)
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
    local parts = { format_position(entry.position, entry.project), format_length(entry.length) }
    if entry.take_count > 1 then parts[#parts + 1] = tostring(entry.active_take) .. "/" .. tostring(entry.take_count) end
    if state.include_project_tabs or state.include_subprojects then parts[#parts + 1] = entry.project_name end
    return table.concat(parts, "  |  ")
end

local function draw_playback_progress(entry, draw_list, x, y, width, height)
    if state.preview_guid ~= entry.guid or state.preview_project ~= entry.project or not state.preview_start or not state.preview_end then return end
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
    local active = state.preview_guid == entry.guid and state.preview_project == entry.project
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
    if not r.ImGui_BeginPopupContextItem(ctx, "##project_clip_context_" .. entry.key) then return false end
    local entries = selected_entries()
    if #entries == 0 then entries = { entry } end
    r.ImGui_TextColored(ctx, COLORS.text_dim, tostring(#entries) .. " selected")
    if r.ImGui_MenuItem(ctx, "Insert at edit cursor") then insert_entry_at_cursor(entry) end
    if r.ImGui_MenuItem(ctx, entry.is_midi and "Open in MIDI editor" or "Open item properties") then open_item_editor(entry) end
    if r.ImGui_MenuItem(ctx, "Go to source item") then select_and_reveal(entry) end
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
            local item = current.project == select(1, r.EnumProjects(-1, "")) and item_from_entry(current, false) or nil
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
    r.ImGui_InvisibleButton(ctx, "##clip_" .. entry.key, card_width, card_height)
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
    if state.include_project_tabs or state.include_subprojects then metadata = metadata .. "  |  " .. entry.project_label end
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(116), entry.missing and COLORS.danger or COLORS.text_dim, truncate_text(metadata, card_width - scaled(20)))
    if hovered and not play_button_hovered and entry.path ~= "" then r.ImGui_SetTooltip(ctx, entry.path) end
    if not play_button_hovered and r.ImGui_IsItemClicked(ctx, 0) then
        local current_project = select(1, r.EnumProjects(-1, ""))
        if entry.project == current_project then
            select_and_reveal(entry)
        else
            state.status = "Source media from " .. (entry.project_label or entry.project_name or "another project")
        end
    end
    local context_open = r.ImGui_BeginPopupContextItem(ctx, "##source_context_" .. entry.source_key)
    if context_open then
        if r.ImGui_MenuItem(ctx, "Insert at edit cursor") then insert_entry_at_cursor(entry) end
        if r.ImGui_MenuItem(ctx, "Go to source project") then select_and_reveal(entry) end
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Select all uses") then select_all_source_uses(entry) end
        if entry.missing then
            if r.ImGui_MenuItem(ctx, "Relink missing source...") then relink_source(entry) end
        else
            r.ImGui_TextDisabled(ctx, "Relink missing source...")
        end
        r.ImGui_EndPopup(ctx)
    end
    if not context_open and state.suppress_drag_guid ~= entry.guid then begin_item_drag(entry) end
end

-- The shape a pool holds, read from the first place it is used. Points inside
-- an automation item are addressed with the item's index offset rather than
-- the envelope's own, which is what the 0x10000000 is for.
local function pool_points(pool)
    if pool.points then return pool.points end
    local points = {}
    local use = pool.uses and pool.uses[1]
    if use and r.CountEnvelopePointsEx then
        local slot = 0x10000000 + use.slot
        local count = r.CountEnvelopePointsEx(use.env, slot) or 0
        local low, high
        for index = 0, count - 1 do
            local ok, time, value = r.GetEnvelopePointEx(use.env, slot, index)
            if ok then
                points[#points + 1] = { time = time or 0, value = value or 0 }
                if not low or value < low then low = value end
                if not high or value > high then high = value end
            end
        end
        points.low, points.high = low or 0, high or 0
        points.span = use.length > 0 and use.length or 1
        -- Against the envelope's own range where REAPER states one, so two
        -- pools on the same envelope can be compared at a glance. Falling back
        -- to what the points themselves cover keeps a shape visible on an
        -- envelope that reports no range.
        if r.GetEnvelopeInfo_Value then
            local floor = r.GetEnvelopeInfo_Value(use.env, "D_MINVALUE")
            local ceiling = r.GetEnvelopeInfo_Value(use.env, "D_MAXVALUE")
            if floor and ceiling and ceiling > floor then
                points.low, points.high = floor, ceiling
                points.scaled_to_envelope = true
            end
        end
    end
    pool.points = points
    return points
end

-- Normalised to the points' own range rather than the envelope's, so the shape
-- reads whether it is a volume sweep or a two-value switch.
local function draw_pool_preview(draw_list, pool, x, y, width, height)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, COLORS.child_bg, scaled(3))
    local points = pool_points(pool)
    if #points == 0 then
        r.ImGui_DrawList_AddText(draw_list, x + scaled(6), y + height * 0.5 - scaled(6), COLORS.text_dim, "no points")
        return
    end
    local low, high = points.low, points.high
    local range = (high - low)
    local pad = scaled(3)
    local function place(point)
        local across = points.span > 0 and math.min(1, math.max(0, point.time / points.span)) or 0
        local up = range > 0.000001 and ((point.value - low) / range) or 0.5
        return x + across * width, y + height - pad - up * (height - pad * 2)
    end
    if #points == 1 then
        local px, py = place(points[1])
        r.ImGui_DrawList_AddCircleFilled(draw_list, x + width * 0.5, py, scaled(2), COLORS.accent)
        return
    end
    local previous_x, previous_y = place(points[1])
    for index = 2, #points do
        local px, py = place(points[index])
        r.ImGui_DrawList_AddLine(draw_list, previous_x, previous_y, px, py, COLORS.accent, scaled(1.4))
        previous_x, previous_y = px, py
    end
end
-- Where a pool is used, in a form short enough for a card. One place names it,
-- several say how many, because a pool used in twelve places is not a list.
local function pool_where(pool)
    local uses = pool.uses
    if #uses == 0 then return "unused" end
    if #uses == 1 then return uses[1].track_name .. "  |  " .. uses[1].env_name end
    local envelopes, count = {}, 0
    for _, use in ipairs(uses) do
        local key = use.track_name .. "|" .. use.env_name
        if not envelopes[key] then envelopes[key] = true count = count + 1 end
    end
    return tostring(#uses) .. " uses on " .. tostring(count) .. (count == 1 and " envelope" or " envelopes")
end

local function jump_to_use(use)
    if not use then return end
    r.SetEditCurPos(use.position, true, false)
    if use.track and r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(use.track) end
    r.UpdateArrange()
end

-- Put another instance of this pool on the envelope it came from, at the edit
-- cursor. The point of pooling: the copy is the same automation, so editing one
-- edits them all.
local function insert_pool_at_cursor(pool)
    local use = pool.uses and pool.uses[1]
    if not use or not r.InsertAutomationItem then
        state.status = "This REAPER cannot insert automation items"
        return
    end
    insert_pool_on(pool, use.env, use.length)
end

-- Every envelope in the project that could take a pool, so one can be put
-- somewhere it has never been. Pool ids are project wide, so this works across
-- tracks - but the points are read in the target envelope's own range, which is
-- why it is a menu of its own rather than something the plain insert does.
local function envelope_targets()
    local targets = {}
    local function add(track, track_name)
        for index = 0, (r.CountTrackEnvelopes(track) or 0) - 1 do
            local env = r.GetTrackEnvelope(track, index)
            local _, name = r.GetEnvelopeName(env, "")
            targets[#targets + 1] = { env = env, track = track, label = track_name .. "  |  " .. (name or "Envelope") }
        end
    end
    local master = r.GetMasterTrack(0)
    if master then add(master, "Master") end
    for index = 0, (r.CountTracks(0) or 0) - 1 do
        local track = r.GetTrack(0, index)
        if track and not is_launcher_track(track) then add(track, get_track_name(track, index)) end
    end
    return targets
end

local function insert_pool_on(pool, env, length)
    if not r.InsertAutomationItem then
        state.status = "This REAPER cannot insert automation items"
        return
    end
    r.Undo_BeginBlock()
    local at = r.GetCursorPosition() or 0
    local slot = r.InsertAutomationItem(env, pool.id, at, length)
    r.Undo_EndBlock("Insert automation item", -1)
    r.UpdateArrange()
    state.status = slot and slot >= 0 and ("Inserted " .. pool.name) or "Could not insert that pool"
    state.signature = ""
end

-- A copy that is its own pool, the way the Project Bay's Unpooled insert works.
-- There is no call to detach a pooled item, so a fresh empty pool is made and
-- the points are carried across one at a time.
local function insert_pool_unpooled(pool, env, length)
    local use = pool.uses and pool.uses[1]
    if not use or not r.InsertAutomationItem or not r.InsertEnvelopePointEx then
        state.status = "This REAPER cannot insert automation items"
        return
    end
    r.Undo_BeginBlock()
    local at = r.GetCursorPosition() or 0
    local slot = r.InsertAutomationItem(env, -1, at, length)
    if not slot or slot < 0 then
        r.Undo_EndBlock("Insert automation item", -1)
        state.status = "Could not insert that pool"
        return
    end
    local from, into = 0x10000000 + use.slot, 0x10000000 + slot
    local count = r.CountEnvelopePointsEx(use.env, from) or 0
    for index = 0, count - 1 do
        local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(use.env, from, index)
        if ok then
            r.InsertEnvelopePointEx(env, into, time, value, shape or 0, tension or 0, selected or false, true)
        end
    end
    if r.Envelope_SortPointsEx then r.Envelope_SortPointsEx(env, into) end
    r.Undo_EndBlock("Insert automation item", -1)
    r.UpdateArrange()
    state.status = "Inserted " .. pool.name .. " as its own pool"
    state.signature = ""
end

-- Every instance of this pool, selected in the arrange at once, which is what
-- the Project Bay's Usage entry is for.
local function select_pool_uses(pool)
    local touched = 0
    for _, use in ipairs(pool.uses) do
        r.GetSetAutomationItemInfo(use.env, use.slot, "D_UISEL", 1, true)
        touched = touched + 1
    end
    r.UpdateArrange()
    state.status = touched == 1 and "Selected 1 automation item"
        or ("Selected " .. tostring(touched) .. " automation items")
end

-- Bars and beats, the way the Project Bay lists them, falling back to seconds
-- on a REAPER that will not format them.
local function bars_text(position, length)
    if r.format_timestr_len then
        local span = r.format_timestr_len(length, "", position, 2)
        local at = r.format_timestr_pos and r.format_timestr_pos(position, "", 2)
        if span and at then return at .. "   " .. span end
        if span then return span end
    end
    return string.format("%.2f s", length)
end
local function rename_pool(pool, name)
    if not name or name == "" then return end
    r.Undo_BeginBlock()
    for _, use in ipairs(pool.uses) do
        r.GetSetAutomationItemInfo_String(use.env, use.slot, "P_POOL_NAME", name, true)
    end
    r.Undo_EndBlock("Rename automation pool", -1)
    pool.name = name
    state.signature = ""
end

local function draw_pool_card(pool)
    local card_width = rounded(CARD_WIDTH)
    local card_height = rounded(CARD_HEIGHT)
    local preview_height = rounded(PREVIEW_HEIGHT)
    local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_InvisibleButton(ctx, "##pool_" .. tostring(pool.id), card_width, card_height)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local background = hovered and COLORS.card_hover or COLORS.card_bg
    r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + card_width, cursor_y + card_height, background, scaled(5))
    r.ImGui_DrawList_AddRect(draw_list, cursor_x, cursor_y, cursor_x + card_width, cursor_y + card_height,
        hovered and COLORS.accent or COLORS.border, scaled(5), 0, scaled(1))
    draw_pool_preview(draw_list, pool, cursor_x + scaled(10), cursor_y + scaled(7), card_width - scaled(18), preview_height)
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(80), COLORS.text,
        truncate_text(pool.name, card_width - scaled(20)))
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(99), COLORS.text_dim,
        truncate_text(pool_where(pool), card_width - scaled(20)))
    local count = tostring(#pool.uses)
    local count_width = r.ImGui_CalcTextSize(ctx, count)
    r.ImGui_DrawList_AddText(draw_list, cursor_x + card_width - count_width - scaled(10), cursor_y + scaled(80), COLORS.accent, count)
    local first = pool.uses[1]
    r.ImGui_DrawList_AddText(draw_list, cursor_x + scaled(10), cursor_y + scaled(116), COLORS.text_dim,
        truncate_text(bars_text(first and first.position or 0, pool.length), card_width - scaled(20)))

    if hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0) then jump_to_use(pool.uses[1]) end
    if r.ImGui_BeginPopupContextItem(ctx, "##pool_ctx_" .. tostring(pool.id)) then
        r.ImGui_TextColored(ctx, COLORS.text_dim, pool.name)
        r.ImGui_Separator(ctx)
        if r.ImGui_BeginMenu(ctx, "Insert at edit cursor") then
            if r.ImGui_MenuItem(ctx, "Pooled") then insert_pool_at_cursor(pool) end
            if r.ImGui_MenuItem(ctx, "Unpooled") then
                local use = pool.uses[1]
                if use then insert_pool_unpooled(pool, use.env, use.length) end
            end
            r.ImGui_EndMenu(ctx)
        end
        if r.ImGui_BeginMenu(ctx, "Insert on another envelope") then
            for index, target in ipairs(envelope_targets()) do
                if r.ImGui_MenuItem(ctx, target.label .. "##target" .. index) then
                    insert_pool_on(pool, target.env, pool.length)
                end
            end
            r.ImGui_EndMenu(ctx)
        end
        if r.ImGui_MenuItem(ctx, "Select every instance") then select_pool_uses(pool) end
        if r.ImGui_BeginMenu(ctx, "Go to") then
            for index, use in ipairs(pool.uses) do
                local label = string.format("%s  |  %s  |  %.2f s", use.track_name, use.env_name, use.position)
                if r.ImGui_MenuItem(ctx, label .. "##go" .. index) then jump_to_use(use) end
            end
            r.ImGui_EndMenu(ctx)
        end
        r.ImGui_Separator(ctx)
        r.ImGui_SetNextItemWidth(ctx, rounded(180))
        local changed, typed = r.ImGui_InputText(ctx, "##pool_name" .. tostring(pool.id), pool.name)
        if changed then rename_pool(pool, typed) end
        r.ImGui_EndPopup(ctx)
    end
    if hovered then
        r.ImGui_SetTooltip(ctx, pool.name .. "\n" .. pool_where(pool)
            .. "\nDouble click to go there  |  right click for more")
    end
end

local function draw_automation()
    local ui_scale, font_pushed = begin_tile_scale()
    local available = r.ImGui_GetContentRegionAvail(ctx)
    local card_width = rounded(CARD_WIDTH)
    local card_height = rounded(CARD_HEIGHT)
    local gap = rounded(8)
    local columns = math.max(1, math.floor((available + gap) / (card_width + gap)))
    if r.ImGui_BeginTable(ctx, "automation_pools", columns, r.ImGui_TableFlags_SizingFixedFit()) then
        for index, pool in ipairs(state.automation) do
            r.ImGui_TableNextColumn(ctx)
            r.ImGui_PushID(ctx, index)
            if r.ImGui_IsRectVisible(ctx, card_width, card_height) then
                draw_pool_card(pool)
            else
                r.ImGui_Dummy(ctx, card_width, card_height)
            end
            r.ImGui_PopID(ctx)
        end
        r.ImGui_EndTable(ctx)
    end
    end_tile_scale(ui_scale, font_pushed)
end
local function draw_sources()
    local ui_scale, font_pushed = begin_tile_scale()
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
    end_tile_scale(ui_scale, font_pushed)
end

local function draw_group(group)
    local group_key = group_collapse_key(group)
    local collapsed = state.collapsed_tracks[group_key] == true or state.collapsed_tracks[group.guid] == true
    local button_size = rounded(16)
    local button_x, button_y = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##collapse_track_" .. group_key, button_size, button_size) then
        state.collapsed_tracks[group.guid] = nil
        state.collapsed_tracks[group_key] = not collapsed
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
    local group_label = tostring(group.index + 1) .. "  " .. group.name
    if state.include_project_tabs or state.include_subprojects then group_label = group.project_name .. "  |  " .. group_label end
    r.ImGui_Text(ctx, group_label)
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, COLORS.text_dim, tostring(#group.items) .. (#group.items == 1 and " clip" or " clips"))
    if collapsed then
        r.ImGui_Spacing(ctx)
        return
    end
    local ui_scale, font_pushed = begin_tile_scale()
    local available = r.ImGui_GetContentRegionAvail(ctx)
    local card_width = rounded(CARD_WIDTH)
    local card_height = rounded(CARD_HEIGHT)
    local gap = rounded(8)
    local columns = math.max(1, math.floor((available + gap) / (card_width + gap)))
    if r.ImGui_BeginTable(ctx, "clips_" .. group_key, columns, r.ImGui_TableFlags_SizingFixedFit()) then
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
    end_tile_scale(ui_scale, font_pushed)
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

local function draw_footer(status_text, chord_text, chord_tooltip)
    local available = r.ImGui_GetContentRegionAvail(ctx)
    local start_x = r.ImGui_GetCursorPosX(ctx)
    local gap = rounded(12)
    local chord_width = math.min(r.ImGui_CalcTextSize(ctx, chord_text), available * 0.52)
    local status_width = math.max(0, available - chord_width - (status_text ~= "" and chord_text ~= "" and gap or 0))
    local status_shown = status_text ~= "" and status_width >= rounded(18)
    if status_shown then
        local shown = truncate_text(status_text, status_width)
        r.ImGui_TextColored(ctx, COLORS.accent, shown)
        if shown ~= status_text and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, status_text) end
    end
    if chord_text ~= "" then
        local shown = truncate_text(chord_text, chord_width)
        if status_shown then r.ImGui_SameLine(ctx, 0, gap) end
        r.ImGui_SetCursorPosX(ctx, start_x + available - chord_width)
        r.ImGui_TextColored(ctx, COLORS.text, shown)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, chord_tooltip) end
    end
end

local function draw_window()
    state.cache_budget = 4
    local scaled_font_pushed = push_scaled_font()
    local theme_stack = push_theme()
    r.ImGui_SetNextWindowSize(ctx, rounded(760), rounded(520), r.ImGui_Cond_FirstUseEver())
    local visible
    visible, state.open = r.ImGui_Begin(ctx, SCRIPT_NAME, state.open, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse())
    if visible then
        -- Folded away from the caret in the grid corner, and only in the
        -- launcher view: the title bar carries the view tabs, so hiding it
        -- anywhere else would leave no way back.
        -- Asked outright rather than by comparing numbers: the states are a
        -- set of two switches, and "toolbar without title bar" does not sit
        -- anywhere on a line through the other three.
        local chrome = state.view_mode == "launcher" and Launcher.chrome() or 0
        if chrome == 0 or chrome == 1 then
            draw_header()
            r.ImGui_Separator(ctx)
        end
        if chrome == 0 or chrome == 3 then
            draw_toolbar()
            r.ImGui_Separator(ctx)
        end
        local launcher_mode = state.view_mode == "launcher"
        local status_text = launcher_mode and Launcher.status() or state.status
        local chord_text, chord_tooltip = "", ""
        if launcher_mode then chord_text, chord_tooltip = Launcher.chord_status() end
        local footer_visible = status_text ~= "" or chord_text ~= ""
        local empty = not launcher_mode and (state.view_mode == "sources" and #state.sources == 0
            or state.view_mode == "automation" and #state.automation == 0
            or state.view_mode == "items" and #state.groups == 0)
        if empty then
            local empty_label = state.view_mode == "sources" and "No matching source media"
                or state.view_mode == "automation" and "No automation items in this project"
                or "No matching project clips"
            local message = state.selected_track_only and not r.GetSelectedTrack(0, 0) and "Select a track to show its media" or empty_label
            r.ImGui_TextColored(ctx, COLORS.text_dim, message)
        else
            local scroll_flags = state.hide_content_scrollbar and r.ImGui_WindowFlags_NoScrollbar() or 0
            if launcher_mode then
                scroll_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
            end
            if r.ImGui_BeginChild(ctx, "clip_scroll", 0, footer_visible and -rounded(28) or 0, 0, scroll_flags) then
                if launcher_mode then
                    Launcher.draw()
                elseif state.view_mode == "sources" then
                    draw_sources()
                elseif state.view_mode == "automation" then
                    draw_automation()
                else
                    for _, group in ipairs(state.groups) do draw_group(group) end
                end
                r.ImGui_EndChild(ctx)
            end
        end
        if footer_visible then draw_footer(status_text, chord_text, chord_tooltip) end
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