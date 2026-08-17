local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local Text = require("core.text")
local json = require("core.json")

local M = {
  id = "render_hub",
  title = "Render Hub",
  icon = "RND",
  version = "0.1.0"
}

-- Command IDs are verified against their action names at init (see verify_commands).
-- Firing a wrong ID here would render or queue something the user never asked for.
local COMMANDS = {
  dialog    = 40015, -- File: Render project to disk...
  render    = 42230, -- File: Render project, using the most recent render settings, auto-close render window
  queue_add = 41823, -- File: Add project to render queue, using the most recent render settings
  queue_run = 41207  -- File: Render all queued renders
}

-- Everything the render dialog writes into the project. Presets are captured
-- from a configured project instead of being constructed by hand: RENDER_FORMAT
-- is an opaque base64 sink config that cannot be authored safely from a script.
local STRING_KEYS = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT", "RENDER_FORMAT2", "RENDER_METADATA" }

-- Missing from a stored preset means "leave the project's value alone", so a
-- preset captured before metadata was tracked does not wipe the metadata of the
-- project it is applied to. The other keys always carry a value.
local OPTIONAL_STRING_KEYS = { RENDER_METADATA = true }

local NUMBER_KEYS = {
  "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_CHANNELS", "RENDER_SRATE",
  "RENDER_STARTPOS", "RENDER_ENDPOS", "RENDER_TAILFLAG", "RENDER_TAILMS",
  "RENDER_ADDTOPROJ", "RENDER_DITHER", "RENDER_NORMALIZE", "RENDER_NORMALIZE_TARGET",
  "RENDER_BRICKWALL", "RENDER_FADEIN", "RENDER_FADEOUT", "RENDER_FADEINSHAPE",
  "RENDER_FADEOUTSHAPE"
}

-- Captured and restored like everything else, but kept out of the "is this
-- preset live" comparison: REAPER moves these with the time selection, and the
-- badge should not blink off every time the edit cursor area changes.
local COMPARE_SKIP = { RENDER_STARTPOS = true, RENDER_ENDPOS = true }

local BOUNDS_LABELS = {
  [0] = "Custom range",
  [1] = "Entire project",
  [2] = "Time selection",
  [3] = "Project regions",
  [4] = "Selected items",
  [5] = "Selected regions"
}

-- REAPER stores the sink type as a little-endian fourcc, so the decoded config
-- starts with the code spelled backwards.
local FORMAT_NAMES = {
  evaw = "WAV",
  ffia = "AIFF",
  l3pm = "MP3",
  calf = "FLAC",
  vggo = "OGG",
  supO = "Opus",
  supo = "Opus",
  kpvw = "WavPack",
  PMFF = "Video"
}

local PROFILES = {
  { name = "No target" },
  { name = "Streaming -14 LUFS", lufs = -14.0, tp = -1.0 },
  { name = "Apple Music -16 LUFS", lufs = -16.0, tp = -1.0 },
  { name = "Broadcast R128 -23 LUFS", lufs = -23.0, tp = -1.0 },
  { name = "Club master -9 LUFS", lufs = -9.0, tp = -0.3 }
}

-- REAPER's own wildcard set, grouped the way its help window groups it. Bare
-- tokens only: the (name) and {lane} forms need a value the user has to supply,
-- and pasting a half-finished form into the pattern only makes a mess. The
-- casing, <replacement> and [<N] modifiers are documented above the menu instead.
local WILDCARDS = {
  { group = "Project", items = {
    { "$project", "Project name" },
    { "$title", "Project title" },
    { "$author", "Project author" },
    { "$projectnotes", "Project notes" },
    { "$projectdirectory", "Project directory on disk" },
    { "$tempo", "Project tempo" },
    { "$timesignature", "Time signature as 4-4" },
    { "$timesignum", "Time signature numerator" },
    { "$timesigdenom", "Time signature denominator" },
    { "$playrate", "Project play rate" },
    { "$fx", "FX list" }
  } },
  { group = "Track", items = {
    { "$track", "Track name" },
    { "$trackslashes", "Track name, slashes make directories" },
    { "$tracknumber", "1 for the first track" },
    { "$tracknameornumber", "Name, or Track N when unnamed" },
    { "$seltrack", "First selected unmuted track" },
    { "$parent", "Parent track name" },
    { "$folders", "Track folder structure as directories" }
  } },
  { group = "Regions and markers", items = {
    { "$region", "Region name or ID number" },
    { "$regionname", "Region name" },
    { "$regionnumber", "Region ID number" },
    { "$marker", "Marker name or ID number" },
    { "$markername", "Marker name" },
    { "$markernumber", "Marker ID number" }
  } },
  { group = "Media items", items = {
    { "$item", "Media item take name" },
    { "$itemnumber", "1 for the first item on a track" },
    { "$itemnotes", "Media item notes" },
    { "$takemarker", "First take marker in the item" },
    { "$lane", "Media item lane number" }
  } },
  { group = "Position and length", items = {
    { "$start", "Start time as M-SS.TTT" },
    { "$end", "End time as M-SS.TTT" },
    { "$length", "Length as M-SS.TTT" },
    { "$startbeats", "Start as measures.beats" },
    { "$endbeats", "End as measures.beats" },
    { "$lengthbeats", "Length as measures.beats" },
    { "$starttc", "Start as HH.MM.SS.FF" },
    { "$endtc", "End as HH.MM.SS.FF" },
    { "$startframes", "Start as absolute frames" },
    { "$endframes", "End as absolute frames" },
    { "$lengthframes", "Length as absolute frames" },
    { "$startseconds", "Start as total seconds" },
    { "$endseconds", "End as total seconds" },
    { "$lengthseconds", "Length as total seconds" },
    { "$lenhh", "Length, hours" },
    { "$lenmm", "Length, minutes modulo hours" },
    { "$lenss", "Length, seconds modulo minutes" },
    { "$lentt", "Length, milliseconds modulo seconds" }
  } },
  { group = "Counters", items = {
    { "$filenumber", "1 for the first file rendered" },
    { "$filenumber[01]", "Zero padded file counter" },
    { "$filecount", "Total number of rendered files" },
    { "$namenumber", "1 for the first region or item with this name" },
    { "$timelineorder", "1 for the first item or region on the timeline" },
    { "$timelineorder_track", "Timeline order within the track" },
    { "$note", "C0 for the first file, C#0 for the second" },
    { "$natural", "C0 for the first file, D0 for the second" }
  } },
  { group = "Format", items = {
    { "$format", "Render format, e.g. wav" },
    { "$samplerate", "Sample rate in Hz" },
    { "$sampleratek", "Sample rate in kHz" },
    { "$bitdepth", "Bit depth, if available" },
    { "$channels", "Number of render channels" },
    { "$chid", "Render channel number" }
  } },
  { group = "Date and time", items = {
    { "$date", "2026-08-13" },
    { "$time", "19:38:03" },
    { "$datetime", "Date and time" },
    { "$localtime", "Thu, Aug 13 2026 19:38" },
    { "$year", "2026" },
    { "$year2", "26" },
    { "$month", "08" },
    { "$monthname", "aug" },
    { "$day", "13" },
    { "$dayname", "thu" },
    { "$hour", "19, 24-hour" },
    { "$hour12", "07, 12-hour" },
    { "$ampm", "am or pm" },
    { "$minute", "38" },
    { "$second", "03" },
    { "$uniqueid[8]", "Random hex string, 8 to 16 characters" }
  } },
  { group = "Computer", items = {
    { "$user", "User name" },
    { "$computer", "Computer name" }
  } }
}

local PREVIEW_INTERVAL = 0.8
local HISTORY_LIMIT = 24

local defaults = {
  profile_index = 2,
  auto_measure = true,
  show_check = true,
  show_projects = false,
  preview_rows = 5
}

local state = {
  loaded = false,
  data_path = nil,
  data = nil,
  checked = {},
  targets = {},
  targets_error = nil,
  targets_unresolved = false,
  targets_at = 0,
  bottom_fixed_h = nil,
  current = nil,
  live_id = nil,
  applied_id = nil,
  dir = "",
  pattern = "",
  dir_project = nil,
  pattern_project = nil,
  dir_active = false,
  pattern_active = false,
  preview_dirty = true,
  rename_id = nil,
  rename_text = "",
  rename_open = false,
  capture_name = "",
  capture_open = false,
  measure_queue = {},
  projects = {},
  projects_busy = false,
  batch_checked = {},
  batch_count = 1,
  queue = {},
  queue_at = 0,
  queued_expected = nil,
  queue_clear_armed = false,
  recheck_at = 0,
  mix_summary = {},
  region_summary = {},
  region_targets = nil,
  region_preset = nil,
  regions_open = false,
  regions_id = nil,
  regions_pick = {},
  tags_map = {},
  tags_list = {},
  tags_here = {},
  tags_at = nil,
  commands = {},
  commands_checked = false,
  last_error = nil
}

local EXT_SECTION = "TK_WORKBENCH_RENDER_HUB"

local util = {}
local tags = {}
local mixstate = {}
local regionset = {}
local store = {}
local proj = {}
local fmt = {}
local loud = {}
local view = {}

--------------------------------------------------------------------------------
-- util
--------------------------------------------------------------------------------

function util.now()
  return os.time()
end

function util.precise_now()
  if r.time_precise then return r.time_precise() end
  return os.clock()
end

function util.clean(value, fallback)
  value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  if value == "" then return fallback end
  return value
end

function util.read_text(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read("*all")
  file:close()
  return content
end

function util.write_json(path, value)
  local ok, encoded = pcall(json.encode, value)
  if not ok or not encoded then return false end
  local file = io.open(path, "w")
  if not file then return false end
  file:write(encoded)
  file:close()
  return true
end

function util.file_size(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local size = file:seek("end")
  file:close()
  return size
end

function util.human_size(bytes)
  bytes = tonumber(bytes)
  if not bytes then return "" end
  if bytes < 1024 then return string.format("%d B", bytes) end
  if bytes < 1024 * 1024 then return string.format("%.0f kB", bytes / 1024) end
  if bytes < 1024 * 1024 * 1024 then return string.format("%.1f MB", bytes / (1024 * 1024)) end
  return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
end

function util.fit(ctx, value, max_width)
  value = tostring(value or "")
  if max_width <= 0 then return "" end
  if UIScale.text_width(ctx, value) <= max_width then return value end
  -- Drop whole characters: cutting bytes halves an accented letter.
  while #value > 1 and UIScale.text_width(ctx, value .. "...") > max_width do
    value = value:sub(1, Text.char_start(value, #value) - 1)
  end
  return value .. "..."
end

function util.basename(path)
  return tostring(path or ""):match("[^\\/]+$") or tostring(path or "")
end

function util.dirname(path)
  return tostring(path or ""):match("^(.*)[\\/][^\\/]*$") or ""
end

function util.is_windows()
  local os_name = r.GetOS and r.GetOS() or ""
  return os_name:match("^Win") ~= nil
end

function util.open_folder(path)
  path = tostring(path or "")
  if path == "" then return false end
  local os_name = r.GetOS and r.GetOS() or ""
  if os_name:match("^Win") then
    os.execute('explorer /e,"' .. path:gsub("/", "\\") .. '"')
  elseif os_name:match("^OSX") or os_name:match("^macOS") then
    os.execute('open "' .. path .. '"')
  else
    os.execute('xdg-open "' .. path .. '"')
  end
  return true
end

function util.show_file(path)
  path = tostring(path or "")
  if path == "" then return false end
  local os_name = r.GetOS and r.GetOS() or ""
  if os_name:match("^Win") then
    os.execute('explorer /select,"' .. path:gsub("/", "\\") .. '"')
  elseif os_name:match("^OSX") or os_name:match("^macOS") then
    os.execute('open -R "' .. path .. '"')
  else
    util.open_folder(util.dirname(path))
  end
  return true
end

local B64_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function util.b64decode(data)
  data = tostring(data or ""):gsub("[^" .. B64_CHARS .. "=]", "")
  if data == "" then return "" end
  local bits = ""
  local out = {}
  for char in data:gmatch("[^=]") do
    local index = B64_CHARS:find(char, 1, true)
    if index then
      local value = index - 1
      local chunk = ""
      for bit = 5, 0, -1 do
        chunk = chunk .. ((value >> bit) & 1)
      end
      bits = bits .. chunk
    end
  end
  for byte = 1, #bits - 7, 8 do
    local value = 0
    for offset = 0, 7 do
      value = value * 2 + tonumber(bits:sub(byte + offset, byte + offset)) end
    out[#out + 1] = string.char(value)
  end
  return table.concat(out)
end

function util.copy(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = util.copy(child) end
  return result
end

function util.ensure_settings(app)
  app.settings.render_hub = app.settings.render_hub or {}
  local settings = app.settings.render_hub
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

function util.verify_commands()
  if state.commands_checked then return end
  state.commands_checked = true
  for key, id in pairs(COMMANDS) do
    local name = nil
    if r.CF_GetCommandText then
      local ok, text = pcall(r.CF_GetCommandText, 0, id)
      if ok then name = text end
    end
    -- Without SWS there is nothing to check against, so the constant is trusted.
    if not name or name == "" then
      state.commands[key] = true
    else
      state.commands[key] = name:lower():find("render", 1, true) ~= nil
      if not state.commands[key] then
        state.last_error = "Action " .. tostring(id) .. " is not a render action (" .. name .. ")"
      end
    end
  end
end

--------------------------------------------------------------------------------
-- tags: read-only view of the Tags module's store
--------------------------------------------------------------------------------

-- The Tags module writes the store it settled on into its own settings, so that
-- is the one source that is always right. The known locations are only a fallback
-- for when Tags has not run yet this session.
function tags.store_path(app)
  local settings = app and app.settings and app.settings.track_tags or {}
  local last = tostring(settings.last_store_path or "")
  if last ~= "" then return last end
  local resource = r.GetResourcePath()
  local candidates = {
    resource .. "/Scripts/TK Scripts/FX/TK FX BROWSER/track_tags.json",
    resource .. "/Scripts/TK Scripts/FX/track_tags.json",
    resource .. "/Scripts/TK Scripts/TK Workbench/track_tags.json"
  }
  for _, path in ipairs(candidates) do
    if util.read_text(path) then return path end
  end
  return nil
end

function tags.load(app, force)
  local now = util.precise_now()
  if not force and state.tags_at and (now - state.tags_at) < 2.0 then return state.tags_map end
  state.tags_at = now
  state.tags_map = {}
  state.tags_list = {}
  local path = tags.store_path(app)
  local content = path and util.read_text(path)
  if not content or content == "" then return state.tags_map end
  local ok, decoded = pcall(json.decode, content)
  if not ok or type(decoded) ~= "table" or type(decoded.tracks) ~= "table" then return state.tags_map end
  for guid, list in pairs(decoded.tracks) do
    for _, tag in ipairs(type(list) == "table" and list or {}) do
      local name = util.clean(tag, "")
      if name ~= "" then
        state.tags_map[name] = state.tags_map[name] or {}
        state.tags_map[name][tostring(guid)] = true
      end
    end
  end
  for name in pairs(state.tags_map) do state.tags_list[#state.tags_list + 1] = name end
  table.sort(state.tags_list, function(left, right) return left:lower() < right:lower() end)
  tags.count_here()
  return state.tags_map
end

-- The store is one flat file of track GUID to tags, shared by every project the
-- user has ever tagged in, so the number of GUIDs carrying a tag says nothing
-- about the project that is open. Only the tracks actually present here count.
function tags.count_here()
  local present = {}
  local total = r.CountTracks(0) or 0
  for index = 0, total - 1 do
    local track = r.GetTrack(0, index)
    local guid = track and r.GetTrackGUID and r.GetTrackGUID(track) or nil
    if guid then present[guid] = true end
  end
  state.tags_here = {}
  for name, guids in pairs(state.tags_map or {}) do
    local count = 0
    for guid in pairs(guids) do
      if present[guid] then count = count + 1 end
    end
    state.tags_here[name] = count
  end
end

-- Stem renders take their source from the track selection, so applying a tag
-- means selecting exactly those tracks before the settings are read back.
function tags.select_tracks(app, name)
  local map = tags.load(app)
  local wanted = map and map[name]
  if not wanted then return 0 end
  local count = r.CountTracks(0) or 0
  local selected = 0
  r.PreventUIRefresh(1)
  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    if track then
      local guid = r.GetTrackGUID and r.GetTrackGUID(track) or nil
      local hit = guid ~= nil and wanted[guid] == true
      r.SetTrackSelected(track, hit)
      if hit then selected = selected + 1 end
    end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  return selected
end

--------------------------------------------------------------------------------
-- mixstate: the mute and solo a preset wants, remembered per project
--
-- Presets themselves are a global library, but track GUIDs are not: a preset
-- captured in one project would mute nothing at all in the next, and render a
-- full mix under the name "Instrumental" without a word of complaint. So this
-- half lives in the project, keyed by preset id. A preset used in a project that
-- has no mix state for it simply renders without touching anything, which is
-- exactly what it did before this existed.
--
-- It is applied for the duration of a render and put back afterwards. Clicking a
-- preset to look at it never moves a fader: there would be no moment to undo it.
--------------------------------------------------------------------------------

function mixstate.key(preset_id)
  return "MIX:" .. tostring(preset_id or "")
end

function mixstate.read(preset_id)
  if not preset_id then return nil end
  local ok, raw = r.GetProjExtState(0, EXT_SECTION, mixstate.key(preset_id))
  if ok ~= 1 or not raw or raw == "" then return nil end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok or type(decoded) ~= "table" or type(decoded.tracks) ~= "table" then return nil end
  return decoded.tracks
end

function mixstate.write(preset_id, tracks)
  if not preset_id then return false end
  if not tracks then
    r.SetProjExtState(0, EXT_SECTION, mixstate.key(preset_id), "")
    return true
  end
  local ok, encoded = pcall(json.encode, { tracks = tracks })
  if not ok then return false end
  r.SetProjExtState(0, EXT_SECTION, mixstate.key(preset_id), encoded)
  return true
end

function mixstate.snapshot()
  local tracks = {}
  local count = r.CountTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    local guid = track and r.GetTrackGUID and r.GetTrackGUID(track) or nil
    if guid then
      tracks[guid] = {
        mute = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "B_MUTE")) or 0),
        solo = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "I_SOLO")) or 0)
      }
    end
  end
  return tracks
end

-- Tracks added since the capture are not in the map and are left alone rather
-- than being unmuted on a guess.
function mixstate.put(tracks)
  if not tracks then return end
  local count = r.CountTracks(0) or 0
  r.PreventUIRefresh(1)
  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    local guid = track and r.GetTrackGUID and r.GetTrackGUID(track) or nil
    local wanted = guid and tracks[guid] or nil
    if wanted then
      r.SetMediaTrackInfo_Value(track, "B_MUTE", tonumber(wanted.mute) or 0)
      r.SetMediaTrackInfo_Value(track, "I_SOLO", tonumber(wanted.solo) or 0)
    end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
end

function mixstate.capture(preset_id)
  local tracks = mixstate.snapshot()
  mixstate.write(preset_id, tracks)
  return mixstate.summary_of(tracks)
end

function mixstate.summary_of(tracks)
  local muted, soloed, total = 0, 0, 0
  for _, entry in pairs(tracks or {}) do
    total = total + 1
    if (tonumber(entry.mute) or 0) ~= 0 then muted = muted + 1 end
    if (tonumber(entry.solo) or 0) ~= 0 then soloed = soloed + 1 end
  end
  return { muted = muted, soloed = soloed, total = total }
end

-- Applies the stored state and hands back what was there, for putting back.
function mixstate.engage(preset_id)
  local wanted = mixstate.read(preset_id)
  if not wanted then return nil end
  local before = mixstate.snapshot()
  mixstate.put(wanted)
  return before
end

function mixstate.release(before)
  if before then mixstate.put(before) end
end

--------------------------------------------------------------------------------
-- regionset: which regions a preset renders, remembered per project
--
-- BogdanS asked for the selected regions to be captured. REAPER's region info
-- API has no documented key for selection, its published signature disagrees
-- with what this build accepts, and unknown keys answer 0 rather than failing -
-- so a selection cannot be read without guessing. The regions are picked here
-- instead, which also survives closing the project and shows in the preset which
-- regions belong to it, rather than depending on what happened to be selected.
--
-- Stored by region id, not by position: regions move. Positions are read fresh
-- at render time. Measured first: $region and $regionnumber do resolve under a
-- custom range, so each region still gets its own file name.
--------------------------------------------------------------------------------

function regionset.key(preset_id)
  return "RGN:" .. tostring(preset_id or "")
end

function regionset.read(preset_id)
  if not preset_id then return nil end
  local ok, raw = r.GetProjExtState(0, EXT_SECTION, regionset.key(preset_id))
  if ok ~= 1 or not raw or raw == "" then return nil end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok or type(decoded) ~= "table" or type(decoded.ids) ~= "table" then return nil end
  local ids = {}
  for _, id in ipairs(decoded.ids) do
    if tonumber(id) then ids[#ids + 1] = math.floor(tonumber(id)) end
  end
  if #ids == 0 then return nil end
  return ids
end

function regionset.write(preset_id, ids)
  if not preset_id then return false end
  if not ids or #ids == 0 then
    r.SetProjExtState(0, EXT_SECTION, regionset.key(preset_id), "")
    return true
  end
  local ok, encoded = pcall(json.encode, { ids = ids })
  if not ok then return false end
  r.SetProjExtState(0, EXT_SECTION, regionset.key(preset_id), encoded)
  return true
end

-- Every region in the project, in timeline order, from the old and documented
-- call rather than the one whose keys are anybody's guess.
function regionset.all()
  local list = {}
  local _, markers, regions = r.CountProjectMarkers(0)
  for index = 0, (markers or 0) + (regions or 0) - 1 do
    local ok, is_region, pos, rgn_end, name, id = r.EnumProjectMarkers3(0, index)
    if ok and ok ~= 0 and is_region then
      list[#list + 1] = {
        id = math.floor(tonumber(id) or 0),
        name = util.clean(name, nil) or ("Region " .. tostring(id)),
        pos = tonumber(pos) or 0,
        stop = tonumber(rgn_end) or 0
      }
    end
  end
  return list
end

-- What to render for this preset: the stored ids resolved against the project as
-- it stands now. An id that no longer exists is dropped rather than rendered at
-- whatever position it used to sit.
function regionset.slices(preset_id)
  local ids = regionset.read(preset_id)
  if not ids then return nil end
  local wanted = {}
  for _, id in ipairs(ids) do wanted[id] = true end
  local slices = {}
  for _, region in ipairs(regionset.all()) do
    if wanted[region.id] and region.stop > region.pos then slices[#slices + 1] = region end
  end
  if #slices == 0 then return nil end
  return slices
end

function regionset.summary(preset_id)
  local ids = regionset.read(preset_id)
  if not ids then return nil end
  local slices = regionset.slices(preset_id) or {}
  return { stored = #ids, found = #slices }
end

--------------------------------------------------------------------------------
-- store: presets and render history live next to config.json
--------------------------------------------------------------------------------

function store.new_data()
  return { schema_version = 1, presets = {}, history = {} }
end

function store.normalize(value)
  if type(value) ~= "table" then return store.new_data() end
  local data = store.new_data()
  data.schema_version = tonumber(value.schema_version) or 1
  for index, preset in ipairs(type(value.presets) == "table" and value.presets or {}) do
    if type(preset) == "table" and type(preset.settings) == "table" then
      local settings = { strings = {}, numbers = {} }
      for _, key in ipairs(STRING_KEYS) do
        local stored = preset.settings.strings and preset.settings.strings[key]
        if stored ~= nil then
          settings.strings[key] = tostring(stored)
        elseif not OPTIONAL_STRING_KEYS[key] then
          settings.strings[key] = ""
        end
      end
      for _, key in ipairs(NUMBER_KEYS) do
        settings.numbers[key] = tonumber(preset.settings.numbers and preset.settings.numbers[key]) or 0
      end
      local created = tonumber(preset.created_at) or util.now()
      data.presets[#data.presets + 1] = {
        id = tostring(preset.id or ("preset_" .. tostring(created) .. "_" .. tostring(index))),
        name = util.clean(preset.name, "Preset " .. tostring(index)),
        tag = util.clean(preset.tag, nil),
        created_at = created,
        updated_at = tonumber(preset.updated_at) or created,
        settings = settings
      }
    end
  end
  for _, entry in ipairs(type(value.history) == "table" and value.history or {}) do
    if type(entry) == "table" and entry.path then
      data.history[#data.history + 1] = {
        path = tostring(entry.path),
        at = tonumber(entry.at) or util.now(),
        size = tonumber(entry.size),
        preset = tostring(entry.preset or ""),
        lufs = tonumber(entry.lufs),
        tp = tonumber(entry.tp),
        clip = tonumber(entry.clip),
        missing = entry.missing == true
      }
    end
  end
  return data
end

function store.load(app)
  state.data_path = (app.script_path or "") .. "render_hub.json"
  local content = util.read_text(state.data_path)
  if content and content ~= "" then
    local ok, decoded = pcall(json.decode, content)
    state.data = store.normalize(ok and decoded or nil)
  else
    state.data = store.new_data()
  end
  state.loaded = true
end

function store.save()
  if not state.data_path or not state.data then return false end
  return util.write_json(state.data_path, state.data)
end

function store.find(id)
  for index, preset in ipairs(state.data and state.data.presets or {}) do
    if preset.id == id then return preset, index end
  end
  return nil, nil
end

function store.add(name, snapshot)
  local timestamp = util.now()
  local preset = {
    id = "preset_" .. tostring(timestamp) .. "_" .. tostring(#state.data.presets + 1),
    name = util.clean(name, "Preset " .. tostring(#state.data.presets + 1)),
    created_at = timestamp,
    updated_at = timestamp,
    settings = snapshot
  }
  state.data.presets[#state.data.presets + 1] = preset
  store.save()
  return preset
end

function store.remove(id)
  local _, index = store.find(id)
  if not index then return false end
  table.remove(state.data.presets, index)
  state.checked[id] = nil
  store.save()
  return true
end

function store.move(id, delta)
  local _, index = store.find(id)
  if not index then return false end
  local target = index + delta
  if target < 1 or target > #state.data.presets then return false end
  local preset = table.remove(state.data.presets, index)
  table.insert(state.data.presets, target, preset)
  store.save()
  return true
end

function store.checked_presets()
  local result = {}
  for _, preset in ipairs(state.data and state.data.presets or {}) do
    if state.checked[preset.id] then result[#result + 1] = preset end
  end
  return result
end

function store.find_history(path)
  for _, entry in ipairs(state.data and state.data.history or {}) do
    if entry.path == path then return entry end
  end
  return nil
end

function store.record_render(paths, preset_name, auto_measure)
  local written = 0
  local stats = loud.read_render_stats()
  for _, path in ipairs(paths or {}) do
    local size = util.file_size(path)
    local existing = store.find_history(path)
    local entry = existing or { path = path }
    local measured = stats[path]
    entry.at = util.now()
    entry.size = size
    entry.preset = tostring(preset_name or "")
    entry.missing = size == nil
    entry.lufs = measured and measured.lufs or nil
    entry.tp = measured and (measured.tp or measured.peak) or nil
    entry.clip = measured and measured.clip or nil
    if not existing then table.insert(state.data.history, 1, entry) end
    if size then written = written + 1 end
    -- Only decode the file when REAPER did not already hand over the numbers.
    if size and not entry.lufs and auto_measure and loud.available() then
      state.measure_queue[#state.measure_queue + 1] = { path = path }
    end
  end
  -- Keep the newest first and trim, so the panel never grows without bound.
  table.sort(state.data.history, function(left, right) return (left.at or 0) > (right.at or 0) end)
  while #state.data.history > HISTORY_LIMIT do table.remove(state.data.history) end
  store.save()
  return written
end

--------------------------------------------------------------------------------
-- proj: read and write the project render settings
--------------------------------------------------------------------------------

function proj.get_string(key)
  local ok, value = r.GetSetProjectInfo_String(0, key, "", false)
  if not ok then return "" end
  return tostring(value or "")
end

function proj.set_string(key, value)
  r.GetSetProjectInfo_String(0, key, tostring(value or ""), true)
end

function proj.get_number(key)
  return tonumber(r.GetSetProjectInfo(0, key, 0, false)) or 0
end

function proj.set_number(key, value)
  r.GetSetProjectInfo(0, key, tonumber(value) or 0, true)
end

function proj.snapshot()
  local snapshot = { strings = {}, numbers = {} }
  for _, key in ipairs(STRING_KEYS) do snapshot.strings[key] = proj.get_string(key) end
  for _, key in ipairs(NUMBER_KEYS) do snapshot.numbers[key] = proj.get_number(key) end
  return snapshot
end

function proj.apply(snapshot)
  if type(snapshot) ~= "table" then return false end
  for _, key in ipairs(STRING_KEYS) do
    if snapshot.strings and snapshot.strings[key] ~= nil then proj.set_string(key, snapshot.strings[key]) end
  end
  for _, key in ipairs(NUMBER_KEYS) do
    if snapshot.numbers and snapshot.numbers[key] ~= nil then proj.set_number(key, snapshot.numbers[key]) end
  end
  if r.MarkProjectDirty then r.MarkProjectDirty(0) end
  return true
end

function proj.same(left, right)
  if type(left) ~= "table" or type(right) ~= "table" then return false end
  for _, key in ipairs(STRING_KEYS) do
    -- An absent optional key is not a difference: it means the preset does not
    -- speak about that setting at all.
    local a = left.strings and left.strings[key]
    local b = right.strings and right.strings[key]
    if not (OPTIONAL_STRING_KEYS[key] and (a == nil or b == nil)) then
      if tostring(a or "") ~= tostring(b or "") then return false end
    end
  end
  for _, key in ipairs(NUMBER_KEYS) do
    if not COMPARE_SKIP[key] then
      local a = tonumber(left.numbers and left.numbers[key]) or 0
      local b = tonumber(right.numbers and right.numbers[key]) or 0
      if math.abs(a - b) > 0.000001 then return false end
    end
  end
  return true
end

-- REAPER resolves the wildcards itself, so the preview is the real file list
-- rather than a reimplementation of the pattern syntax.
--
-- A false retval is not a version problem: REAPER also declines when the current
-- settings cannot produce a file name at all (bounds with nothing in them, an
-- unusable pattern). Only a missing entry point is worth calling out as such.
function proj.read_targets()
  if not r.GetSetProjectInfo_String then return {}, "This REAPER build has no GetSetProjectInfo_String", true end
  local ok, value = r.GetSetProjectInfo_String(0, "RENDER_TARGETS", "", false)
  local targets = {}
  if ok then
    for entry in tostring(value or ""):gmatch("[^;]+") do
      local path = entry:match("^%s*(.-)%s*$") or ""
      if path ~= "" then targets[#targets + 1] = path end
    end
  end
  return targets, nil, not ok
end

function proj.project_name()
  local name = util.clean(r.GetProjectName(0, ""), "")
  if name == "" then return "Unsaved project" end
  return name
end

function proj.render_dir()
  local dir = proj.get_string("RENDER_FILE")
  if dir ~= "" then return dir end
  local path = r.GetProjectPath and r.GetProjectPath("") or ""
  return path
end

--------------------------------------------------------------------------------
-- fmt: human readable labels for a captured snapshot
--------------------------------------------------------------------------------

function fmt.format_label(snapshot)
  local cfg = util.b64decode(snapshot and snapshot.strings and snapshot.strings.RENDER_FORMAT or "")
  if #cfg < 4 then return "Format ?" end
  local code = cfg:sub(1, 4)
  local name = FORMAT_NAMES[code]
  if not name then return "Custom (" .. code:gsub("%c", "?") .. ")" end
  if name == "WAV" and #cfg >= 5 then
    local bits = cfg:byte(5)
    -- Only trust the byte when it reads as a real bit depth.
    if bits == 8 or bits == 16 or bits == 24 or bits == 32 then name = name .. " " .. tostring(bits) end
  end
  return name
end

function fmt.rate_label(snapshot)
  local rate = tonumber(snapshot and snapshot.numbers and snapshot.numbers.RENDER_SRATE) or 0
  if rate <= 0 then return "project rate" end
  if rate % 1000 == 0 then return string.format("%d kHz", rate / 1000) end
  return string.format("%.1f kHz", rate / 1000)
end

function fmt.channel_label(snapshot)
  local channels = math.floor(tonumber(snapshot and snapshot.numbers and snapshot.numbers.RENDER_CHANNELS) or 0)
  if channels <= 0 then return "" end
  if channels == 1 then return "mono" end
  if channels == 2 then return "stereo" end
  return tostring(channels) .. " ch"
end

function fmt.bounds_label(snapshot)
  local bounds = math.floor(tonumber(snapshot and snapshot.numbers and snapshot.numbers.RENDER_BOUNDSFLAG) or 0)
  return BOUNDS_LABELS[bounds] or ("Bounds " .. tostring(bounds))
end

-- The RENDER_SETTINGS bitmask carries more than these two flags, so anything
-- unrecognised stays "Custom" instead of being guessed at.
function fmt.source_label(snapshot)
  local settings = math.floor(tonumber(snapshot and snapshot.numbers and snapshot.numbers.RENDER_SETTINGS) or 0)
  local label
  if settings & 2 ~= 0 then
    label = "Stems"
  elseif settings & 1 ~= 0 then
    label = "Master"
  else
    label = "Custom"
  end
  if settings & 4 ~= 0 then label = label .. " multi" end
  return label
end

function fmt.summary(snapshot)
  local parts = { fmt.format_label(snapshot), fmt.rate_label(snapshot) }
  local channels = fmt.channel_label(snapshot)
  if channels ~= "" then parts[#parts + 1] = channels end
  return table.concat(parts, " | ")
end

function fmt.details(snapshot)
  local lines = {
    "Source: " .. fmt.source_label(snapshot),
    "Bounds: " .. fmt.bounds_label(snapshot),
    "Format: " .. fmt.summary(snapshot),
    "Directory: " .. util.clean(snapshot.strings.RENDER_FILE, "(project folder)"),
    "Pattern: " .. util.clean(snapshot.strings.RENDER_PATTERN, "(default)"),
    "",
    "RENDER_SETTINGS = " .. tostring(math.floor(snapshot.numbers.RENDER_SETTINGS or 0))
  }
  return table.concat(lines, "\n")
end

function fmt.date(value)
  local number = tonumber(value) or 0
  if number <= 0 then return "" end
  return os.date("%d-%m %H:%M", number)
end

function fmt.db(value)
  if not value then return "--" end
  return string.format("%.1f", value)
end

--------------------------------------------------------------------------------
-- loud: loudness of a rendered file, measured from the file itself
--------------------------------------------------------------------------------

function loud.available()
  return r.CalculateNormalization ~= nil and r.PCM_Source_CreateFromFile ~= nil
end

-- CalculateNormalization returns the linear gain needed to hit the target, so
-- with a 0 dB target the measured level is simply the inverse of that gain.
function loud.measure_one(source, mode)
  local ok, adjust = pcall(r.CalculateNormalization, source, mode, 1.0, 0, 0)
  if not ok then return nil end
  adjust = tonumber(adjust)
  if not adjust or adjust <= 0 then return nil end
  return -20 * math.log(adjust, 10)
end

function loud.measure(path)
  if not loud.available() then return nil, nil end
  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return nil, nil end
  local lufs = loud.measure_one(source, 0)
  local peak = loud.measure_one(source, 3)
  r.PCM_Source_Destroy(source)
  return lufs, peak
end

-- REAPER measures during the render pass, so its own numbers are free and more
-- accurate than decoding the file again afterwards. The format is a flat list of
-- KEY:value pairs where FILE starts a new record; parsing it this loosely means
-- an unexpected key or order costs nothing and simply yields no record, which
-- falls back to measuring.
function loud.read_render_stats()
  if not r.GetSetProjectInfo_String then return {} end
  local ok, raw = r.GetSetProjectInfo_String(0, "RENDER_STATS", "", false)
  if not ok or not raw or raw == "" then return {} end
  local records = {}
  local current = nil
  for field in tostring(raw):gmatch("[^;]+") do
    local key, value = field:match("^%s*(%u[%u%d_]*)%s*:%s*(.*)$")
    if key == "FILE" then
      current = { path = value }
      records[#records + 1] = current
    elseif key and current then
      local number = tonumber(value)
      if key == "LUFSI" then current.lufs = number
      elseif key == "TRUEPEAK" then current.tp = number
      elseif key == "PEAK" then current.peak = number
      elseif key == "CLIP" then current.clip = number end
    end
  end
  local by_path = {}
  for _, record in ipairs(records) do
    if record.path and record.path ~= "" then by_path[record.path] = record end
  end
  return by_path
end

function loud.profile(settings)
  local index = math.floor(tonumber(settings.profile_index) or 1)
  return PROFILES[index] or PROFILES[1], index
end

-- "warn" is a level that is in range but off target; "fail" is over the ceiling.
function loud.verdict(entry, profile)
  -- Clipping is a defect regardless of which delivery target is selected.
  if entry.clip and entry.clip > 0 then return "fail", tostring(math.floor(entry.clip)) .. " clipped samples" end
  if not profile or not profile.lufs then return nil end
  if not entry.lufs then return nil end
  if entry.tp and entry.tp > profile.tp then return "fail", "True peak over " .. fmt.db(profile.tp) .. " dBTP" end
  local delta = entry.lufs - profile.lufs
  if math.abs(delta) <= 1.0 then return "pass", "Within 1 LU of target" end
  return "warn", string.format("%+.1f LU vs target", delta)
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

-- The real file names for a preset's region list, by asking REAPER the same
-- question the render will ask: each region as its own range. That means writing
-- the bounds and putting them back, so it is done only when something actually
-- changed - never on the periodic tick, which would mark the project modified
-- twice a second for a preview nobody asked to refresh.
function view.region_targets(preset)
  local slices = preset and regionset.slices(preset.id)
  if not slices then return nil end
  local bounds = proj.get_number("RENDER_BOUNDSFLAG")
  local from = proj.get_number("RENDER_STARTPOS")
  local to = proj.get_number("RENDER_ENDPOS")
  local names = {}
  for _, slice in ipairs(slices) do
    proj.set_number("RENDER_BOUNDSFLAG", 0)
    proj.set_number("RENDER_STARTPOS", slice.pos)
    proj.set_number("RENDER_ENDPOS", slice.stop)
    for _, path in ipairs(proj.read_targets() or {}) do names[#names + 1] = path end
  end
  proj.set_number("RENDER_BOUNDSFLAG", bounds)
  proj.set_number("RENDER_STARTPOS", from)
  proj.set_number("RENDER_ENDPOS", to)
  if #names == 0 then return nil end
  return names
end

function view.refresh(force)
  local now = util.precise_now()
  if not force and not state.preview_dirty and (now - state.targets_at) < PREVIEW_INTERVAL then return end
  local changed = force or state.preview_dirty
  state.targets_at = now
  state.preview_dirty = false
  state.current = proj.snapshot()
  state.targets, state.targets_error, state.targets_unresolved = proj.read_targets()
  state.targets = state.targets or {}
  -- Two presets can hold identical settings, and then "which one is live" has no
  -- single answer. The one the user last applied wins as long as it still
  -- matches, so clicking a row always moves the badge to that row instead of
  -- leaving it on whichever twin happens to come first in the list.
  -- Which presets carry a mix state for this project, worked out here rather than
  -- per row per frame: each answer costs a project ext state read and a decode.
  state.mix_summary = {}
  state.region_summary = {}
  for _, preset in ipairs(state.data and state.data.presets or {}) do
    local tracks = mixstate.read(preset.id)
    if tracks then state.mix_summary[preset.id] = mixstate.summary_of(tracks) end
    local regions = regionset.summary(preset.id)
    if regions then state.region_summary[preset.id] = regions end
  end
  -- Recomputed only on a real change: it costs two project writes per region.
  if changed then
    state.region_targets = nil
    state.region_preset = nil
    for _, preset in ipairs(store.checked_presets()) do
      local names = view.region_targets(preset)
      if names then
        state.region_targets = names
        state.region_preset = preset
        break
      end
    end
  end
  state.live_id = nil
  local applied = state.applied_id and store.find(state.applied_id) or nil
  if applied and proj.same(applied.settings, state.current) then
    state.live_id = applied.id
  else
    for _, preset in ipairs(state.data and state.data.presets or {}) do
      if proj.same(preset.settings, state.current) then
        state.live_id = preset.id
        break
      end
    end
  end
end

-- Read on every frame rather than on the preview throttle. REAPER's own render
-- dialog edits the same two settings and can be open at the same time, so a copy
-- of mine that is up to a second old must never be handed back to the project on
-- top of what the user just typed over there.
function view.sync_fields()
  local dir = proj.get_string("RENDER_FILE")
  if dir ~= state.dir_project then
    state.dir_project = dir
    if not state.dir_active then state.dir = dir end
  end
  local pattern = proj.get_string("RENDER_PATTERN")
  if pattern ~= state.pattern_project then
    state.pattern_project = pattern
    if not state.pattern_active then state.pattern = pattern end
  end
end

-- Single point where a preset becomes the project's live render setup: the tag
-- has to select its tracks before the settings are read back, because a stem
-- render takes its source from the track selection.
function view.activate(app, preset)
  local selected = nil
  if preset.tag and preset.tag ~= "" then selected = tags.select_tracks(app, preset.tag) end
  proj.apply(preset.settings)
  state.applied_id = preset.id
  state.preview_dirty = true
  return selected
end

function view.apply(app, preset)
  local selected = view.activate(app, preset)
  if selected == nil then
    app.status = "Render settings applied: " .. preset.name
  elseif selected == 0 then
    app.status = "Applied " .. preset.name .. ", but no track carries the tag " .. preset.tag
  else
    app.status = string.format("Applied %s | %d track%s tagged %s", preset.name, selected, selected == 1 and "" or "s", preset.tag)
  end
end

function view.run_command(app, key)
  if state.commands[key] == false then
    app.status = "Render action unavailable (" .. tostring(COMMANDS[key]) .. ")"
    return false
  end
  r.Main_OnCommand(COMMANDS[key], 0)
  return true
end

function view.render_now(app, settings)
  view.refresh(true)
  local expected = {}
  for _, path in ipairs(state.targets) do expected[#expected + 1] = path end
  if #expected == 0 then
    app.status = "Nothing to render with the current settings"
    return
  end
  local preset = nil
  if state.live_id then preset = store.find(state.live_id) end
  if not view.run_command(app, "render") then return end
  local written = store.record_render(expected, preset and preset.name or "Project settings", settings.auto_measure ~= false)
  state.preview_dirty = true
  if written == 0 then
    app.status = "Render finished but no files were found"
  else
    app.status = "Rendered " .. tostring(written) .. " file" .. (written == 1 and "" or "s")
  end
end

-- Queued entries carry their own settings, so the project is put back the way
-- the user left it once everything is in the queue.
function view.queue_presets(app, presets)
  local before = proj.snapshot()
  local expected = {}
  local names = {}
  local queued = 0
  for _, preset in ipairs(presets) do
    view.activate(app, preset)
    local targets = proj.read_targets() or {}
    if #targets > 0 and view.run_command(app, "queue_add") then
      for _, path in ipairs(targets) do expected[#expected + 1] = path end
      names[#names + 1] = preset.name
      queued = queued + 1
    end
  end
  proj.apply(before)
  state.preview_dirty = true
  return queued, expected, table.concat(names, " + ")
end

-- The single place the queue is emptied. Everything that was queued since the
-- last run is recorded here, whether it came from presets, from this project or
-- from a batch of others - REAPER renders the whole queue in one go, so treating
-- it as one event is the only way the bookkeeping can match what happened.
function view.flush_queue(app, settings)
  local pending = state.queued_expected
  if not view.run_command(app, "queue_run") then return false end
  view.scan_queue(true)
  state.preview_dirty = true
  state.queued_expected = nil
  if pending and #pending.paths > 0 then
    local written = store.record_render(pending.paths, table.concat(pending.labels, " + "), settings.auto_measure ~= false)
    app.status = string.format("Queue finished: %d of %d files written", written, #pending.paths)
  else
    app.status = "Render queue finished"
  end
  return true
end

-- Several presets over the project that is already open, rendered one after the
-- other in place. This used to go through the render queue, which meant REAPER
-- reloading its own copy of the project once per preset - all of it work to
-- arrive back at the project that was open the whole time. The queue is still
-- what makes "set it up now, render later" possible; it is just no longer in the
-- way of "render these three formats now". Reported by BogdanS.
function view.render_presets_now(app, settings, presets)
  local before = proj.snapshot()
  local expected = {}
  local names = {}
  for _, preset in ipairs(presets) do names[#names + 1] = preset.name end
  local rendered = view.presets_on_current(app, presets, expected, true, "render")
  proj.apply(before)
  state.preview_dirty = true
  if rendered == 0 then
    app.status = "The ticked presets produce no files"
    return
  end
  local written = store.record_render(expected, table.concat(names, " + "), settings.auto_measure ~= false)
  local skipped = #presets - rendered
  app.status = string.format("Rendered %d preset%s, %d of %d files written%s",
    rendered, rendered == 1 and "" or "s", written, #expected,
    skipped > 0 and (" (" .. tostring(skipped) .. " produced nothing)") or "")
end

--------------------------------------------------------------------------------
-- batching whole projects
--
-- Nothing is ever saved. The render queue keeps its own copy of every job, so
-- the settings only have to be right at the moment a project is queued - they do
-- not have to survive in the file. That is what makes this safe to point at a
-- folder of someone's work: it reads the projects, queues the jobs, and leaves
-- every .rpp on disk exactly as it found it.
--------------------------------------------------------------------------------

-- REAPER keeps every queued render as a project file of its own, so the queue
-- can be read off disk without asking REAPER anything. Worth showing: "Run"
-- empties the whole queue, including jobs put there in an earlier session, and
-- there is otherwise no way to see that from here.
function view.scan_queue(force)
  local now = util.precise_now()
  if not force and (now - (state.queue_at or 0)) < 2.0 then return state.queue end
  state.queue_at = now
  state.queue = {}
  local folder = (r.GetResourcePath and r.GetResourcePath() or "") .. package.config:sub(1, 1) .. "QueuedRenders"
  if not r.EnumerateFiles then return state.queue end
  local index = 0
  while true do
    local name = r.EnumerateFiles(folder, index)
    if not name then break end
    if name:lower():match("%.rpp$") then
      local path = folder .. package.config:sub(1, 1) .. name
      local entry = { path = path, name = name:gsub("%.[Rr][Pp][Pp]$", "") }
      -- The render lines sit near the top of a project file, so a few kilobytes
      -- is enough and a queue of twenty does not mean reading twenty projects.
      local file = io.open(path, "rb")
      if file then
        local head = file:read(8192) or ""
        file:close()
        entry.pattern = head:match("RENDER_PATTERN%s+([^\r\n]+)")
        entry.dir = head:match("RENDER_FILE%s+([^\r\n]+)")
      end
      state.queue[#state.queue + 1] = entry
    end
    index = index + 1
  end
  return state.queue
end

-- Files are checked the moment the render command returns, and a queue of
-- several does not necessarily have the last one finished by then - it shows up
-- as missing and never gets measured. Rather than guess at a delay, anything
-- marked missing is looked at again now and then: a file that turns up heals
-- itself, and one that never does stays flagged, which is the honest outcome.
function view.recheck_missing()
  local now = util.precise_now()
  if (now - (state.recheck_at or 0)) < 0.5 then return end
  state.recheck_at = now
  for _, entry in ipairs(state.data and state.data.history or {}) do
    if entry.missing then
      local size = util.file_size(entry.path)
      if size then
        entry.missing = false
        entry.size = size
        if not entry.lufs and loud.available() then
          state.measure_queue[#state.measure_queue + 1] = { path = entry.path }
        end
        store.save()
        return
      end
    end
  end
end

-- What the queue is expected to write, gathered while jobs are added. The queued
-- project files hold unresolved wildcards, so the only moment the real output
-- names are known is when they are queued - remembering them here is what lets
-- CHECK pick the files up later, whichever route put them in the queue.
function view.remember_queued(paths, label)
  if not paths or #paths == 0 then return end
  local pending = state.queued_expected or { paths = {}, labels = {} }
  for _, path in ipairs(paths) do pending.paths[#pending.paths + 1] = path end
  if label and label ~= "" then pending.labels[#pending.labels + 1] = label end
  state.queued_expected = pending
end

-- A queued job is a project file of REAPER's own making, so dropping one is
-- deleting that copy. The project it came from is not touched, which is what
-- makes this safe to offer without a modal asking twice.
function view.drop_queue_job(app, entry)
  if not entry or not entry.path then return false end
  local ok = os.remove(entry.path)
  view.scan_queue(true)
  -- What the queue was expected to write no longer matches what is in it, and
  -- the wildcards in a queued file cannot be resolved back to file names, so the
  -- honest move is to stop claiming to know.
  state.queued_expected = nil
  app.status = ok and ("Removed from the queue: " .. entry.name) or ("Could not remove " .. entry.name)
  return ok == true
end

function view.draw_queue_popup(app)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup(ctx, "render_hub_queue_popup") then return end
  local jobs = view.scan_queue(false) or {}
  if #jobs == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "The render queue is empty.")
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(#jobs) .. " job(s) waiting. Removing one deletes only its")
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "queued copy - the project it came from is untouched.")
    r.ImGui_Separator(ctx)
    for index, entry in ipairs(jobs) do
      r.ImGui_PushID(ctx, entry.path)
      local shown = util.clean(entry.pattern, nil) or entry.name
      shown = shown:gsub('^"', ""):gsub('"$', "")
      r.ImGui_Text(ctx, string.format("%2d. %s", index, shown))
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, entry.path .. (entry.dir and ("\n\nInto: " .. entry.dir) or ""))
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton and r.ImGui_SmallButton(ctx, "x") then view.drop_queue_job(app, entry) end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_Separator(ctx)
    -- Two steps, because emptying a queue someone spent time filling should not
    -- be one stray click.
    if state.queue_clear_armed then
      r.ImGui_TextColored(ctx, Theme.colors.warning, "Remove all " .. tostring(#jobs) .. " jobs?")
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "Yes") then
        local removed = 0
        for _, entry in ipairs(jobs) do
          if os.remove(entry.path) then removed = removed + 1 end
        end
        view.scan_queue(true)
        state.queued_expected = nil
        state.queue_clear_armed = false
        app.status = "Cleared " .. tostring(removed) .. " job(s) from the queue"
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "No") then state.queue_clear_armed = false end
    elseif r.ImGui_SmallButton(ctx, "Clear all") then
      state.queue_clear_armed = true
    end
  end
  r.ImGui_EndPopup(ctx)
end

function view.queue_tooltip()
  local jobs = state.queue or {}
  if #jobs == 0 then return "The render queue is empty" end
  local lines = { tostring(#jobs) .. " job" .. (#jobs == 1 and "" or "s") .. " waiting:" }
  for index, entry in ipairs(jobs) do
    if index > 8 then
      lines[#lines + 1] = "and " .. tostring(#jobs - 8) .. " more"
      break
    end
    local shown = util.clean(entry.pattern, nil) or entry.name
    lines[#lines + 1] = "  " .. shown:gsub('^"', ""):gsub('"$', "")
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Running the queue renders all of them, including any put"
  lines[#lines + 1] = "there before, and empties it."
  lines[#lines + 1] = "Right-click to open the queue and remove a job."
  return table.concat(lines, "\n")
end

function view.project_name(path)
  local name = util.basename(path):gsub("%.[Rr][Pp][Pp]$", "")
  if name == "" then return "Untitled" end
  return name
end

-- Two kinds of entry in one list. An open tab is reached by switching to it,
-- which costs nothing and cannot lose work; a file has to be opened over the top
-- of whatever is in front. They behave differently enough that the list says
-- which is which, and the same enough that they queue side by side.
function view.batch_entries()
  local entries = {}
  local index = 0
  while true do
    local project, path = r.EnumProjects(index, "")
    if not project then break end
    entries[#entries + 1] = {
      kind = "tab",
      key = "tab:" .. tostring(project),
      project = project,
      path = tostring(path or ""),
      name = view.project_name(tostring(path or ""))
    }
    index = index + 1
  end
  for _, path in ipairs(state.projects) do
    entries[#entries + 1] = { kind = "file", key = "file:" .. path, path = path, name = view.project_name(path) }
  end
  -- The layout needs the row count before the list is drawn, and open tabs are
  -- part of it: sizing on the file list alone would size for half the rows.
  state.batch_count = #entries
  return entries
end

function view.checked_entries(entries)
  local result = {}
  for _, entry in ipairs(entries) do
    if state.batch_checked[entry.key] then result[#result + 1] = entry end
  end
  return result
end

function view.add_projects(app)
  local start = state.projects[1] and util.dirname(state.projects[1]) or (r.GetProjectPath and r.GetProjectPath("") or "")
  local paths = {}
  if r.JS_Dialog_BrowseForOpenFiles then
    local ok, files = r.JS_Dialog_BrowseForOpenFiles("Add projects to the batch", start, "", "REAPER project (*.RPP)\0*.RPP\0All Files (*.*)\0*.*\0", true)
    if not ok or not files or files == "" then return end
    -- Multi-select comes back as a folder followed by the file names, all
    -- separated by nulls; a single pick comes back as one full path.
    local parts = {}
    for part in tostring(files):gmatch("[^%z]+") do parts[#parts + 1] = part end
    if #parts == 1 then
      paths[1] = parts[1]
    else
      local folder = parts[1]
      for index = 2, #parts do paths[#paths + 1] = folder .. package.config:sub(1, 1) .. parts[index] end
    end
  else
    local ok, value = r.GetUserFileNameForRead("", "Add a project to the batch", ".rpp")
    if not ok or not value or value == "" then return end
    paths[1] = value
  end
  local added = 0
  for _, path in ipairs(paths) do
    local seen = false
    for _, existing in ipairs(state.projects) do
      if existing:lower() == path:lower() then seen = true; break end
    end
    if not seen and util.read_text(path) then
      state.projects[#state.projects + 1] = path
      state.batch_checked["file:" .. path] = true
      added = added + 1
    end
  end
  app.status = added > 0 and ("Added " .. tostring(added) .. " project" .. (added == 1 and "" or "s") .. " to the batch") or "Nothing added"
end

-- Only the file half is dangerous, and only to unsaved work in the tab it opens
-- over. Ticking open tabs alone needs no such promise.
function view.batch_blocker(presets, entries)
  local checked = view.checked_entries(entries)
  if #checked == 0 then return "Tick a project" end
  if #presets == 0 then return "Tick at least one preset" end
  local has_file = false
  for _, entry in ipairs(checked) do
    if entry.kind == "file" then has_file = true; break end
  end
  if has_file and r.IsProjectDirty and r.IsProjectDirty(0) ~= 0 then
    return "Save this project first: files open over the front tab"
  end
  return nil
end

-- Apply each preset to whatever project is in front and either queue it or
-- render it there and then. Queueing and rendering differ by this one word, so
-- they share everything else and cannot drift apart.
-- One pass: read what it would write, do it, and note the files. Kept apart so
-- that a preset with a region list can run it several times without the rest of
-- the bookkeeping being written twice.
function view.one_pass(app, expected, predictable, action)
  local targets = proj.read_targets() or {}
  if #targets == 0 then return 0, true end
  if not view.run_command(app, action) then return 0, false end
  if predictable then
    for _, target in ipairs(targets) do expected[#expected + 1] = target end
  end
  return 1, true
end

function view.presets_on_current(app, presets, expected, predictable, action)
  local done = 0
  for _, preset in ipairs(presets) do
    view.activate(app, preset)
    -- Queueing copies the project as it stands, so the mute and solo have to be
    -- in place for that too, not only for a direct render.
    local before = mixstate.engage(preset.id)
    local slices = regionset.slices(preset.id)
    local carry_on = true
    if not slices then
      local count
      count, carry_on = view.one_pass(app, expected, predictable, action)
      done = done + count
    else
      -- A region list means one pass per region, each as its own custom range.
      -- The bounds are left as the last region set them; the caller restores the
      -- whole snapshot afterwards, and the next preset applies its own anyway.
      for _, slice in ipairs(slices) do
        proj.set_number("RENDER_BOUNDSFLAG", 0)
        proj.set_number("RENDER_STARTPOS", slice.pos)
        proj.set_number("RENDER_ENDPOS", slice.stop)
        local count
        count, carry_on = view.one_pass(app, expected, predictable, action)
        done = done + count
        if not carry_on then break end
      end
    end
    mixstate.release(before)
    if not carry_on then break end
  end
  return done
end

-- Switching to a tab loads nothing, so what is worked on is what is in that tab
-- right now, edits and all - and its render settings are put back afterwards,
-- leaving the tab as it was found.
function view.visit_tab(app, entry, presets, expected, action)
  r.SelectProjectInstance(entry.project)
  local before = proj.snapshot()
  -- For a project that has never been saved, $project resolves to one thing now
  -- and another when the file appears, so no claim is made about its name and
  -- CHECK says nothing rather than something wrong.
  local done = view.presets_on_current(app, presets, expected, entry.path ~= "", action)
  proj.apply(before)
  return done
end

function view.visit_file(app, entry, presets, expected, action)
  -- "noprompt:" is what makes this unattended: it drops the render settings
  -- written into the previous project without asking, which is the whole reason
  -- nothing here has to be saved.
  r.Main_openProject("noprompt:" .. entry.path)
  local _, current = r.EnumProjects(-1, "")
  if tostring(current or ""):lower() ~= entry.path:lower() then return nil end
  return view.presets_on_current(app, presets, expected, true, action)
end

-- Walks the ticked projects once, doing `action` to each. Tabs first, files
-- after: a file opens over the front tab, which must not happen while tabs are
-- still being visited.
function view.visit_projects(app, presets, action)
  local entries = view.batch_entries()
  local home_project, home_path = r.EnumProjects(-1, "")
  local expected, names = {}, {}
  local done, failed = 0, 0
  state.projects_busy = true
  for _, pass in ipairs({ "tab", "file" }) do
    for _, entry in ipairs(view.checked_entries(entries)) do
      if entry.kind == pass then
        local count = pass == "tab" and view.visit_tab(app, entry, presets, expected, action)
          or view.visit_file(app, entry, presets, expected, action)
        if count then
          done = done + count
          names[#names + 1] = entry.name
        else
          failed = failed + 1
        end
      end
    end
  end
  if home_project then r.SelectProjectInstance(home_project) end
  local _, now_path = r.EnumProjects(-1, "")
  if tostring(now_path or "") ~= tostring(home_path or "") and tostring(home_path or "") ~= "" then
    r.Main_openProject("noprompt:" .. tostring(home_path))
  end
  state.projects_busy = false
  state.preview_dirty = true
  return done, failed, expected, names
end

-- Render the ticked projects where they stand: no queue, so no copy of a project
-- that is already open is written out and read back again.
function view.render_projects_now(app, settings, presets)
  local blocker = view.batch_blocker(presets, view.batch_entries())
  if blocker then
    app.status = blocker
    return
  end
  local done, failed, expected, names = view.visit_projects(app, presets, "render")
  if done == 0 then
    app.status = "Nothing was rendered" .. (failed > 0 and (", " .. tostring(failed) .. " project(s) would not open") or "")
    return
  end
  local written = store.record_render(expected, table.concat(names, " + "), settings.auto_measure ~= false)
  app.status = string.format("Rendered %d job(s) from %d project(s), %d file(s) written", done, #names, written)
end

function view.run_projects(app, settings, presets)
  local entries = view.batch_entries()
  local blocker = view.batch_blocker(presets, entries)
  if blocker then
    app.status = blocker
    return
  end
  local queued, failed, expected, names = view.visit_projects(app, presets, "queue_add")
  view.scan_queue(true)
  if queued == 0 then
    app.status = "Nothing was queued" .. (failed > 0 and (", " .. tostring(failed) .. " project(s) would not open") or "")
    return
  end
  view.remember_queued(expected, table.concat(names, " + "))
  app.status = string.format("Queued %d job(s) from %d project(s) - press Run to render", queued, #names)
end

function view.browse_dir(app)
  local start = state.dir ~= "" and state.dir or proj.render_dir()
  if r.JS_Dialog_BrowseForFolder then
    local ok, folder = r.JS_Dialog_BrowseForFolder("Select render directory", start)
    if ok and folder and folder ~= "" then return folder end
    return nil
  end
  local ok, value = r.GetUserInputs("Render directory", 1, "Folder:,extrawidth=280", start)
  if ok and value and value ~= "" then return value end
  return nil
end

function view.measure_all(app, settings)
  if not loud.available() then
    app.status = "Loudness measurement needs REAPER 6.62 or newer"
    return
  end
  local queued = 0
  for _, entry in ipairs(state.data.history) do
    if not entry.missing then
      state.measure_queue[#state.measure_queue + 1] = { path = entry.path }
      queued = queued + 1
    end
  end
  app.status = queued > 0 and ("Measuring " .. tostring(queued) .. " file" .. (queued == 1 and "" or "s")) or "Nothing to measure"
end

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

-- The module canvas does not scroll, so nothing may overflow: the three lists
-- (presets, preview, check) share whatever is left after the fixed rows.
--
-- Only child heights are varied here, never whether a row is drawn at all -
-- showing or hiding a row would change the measured fixed height, which would
-- change the allocation, which would show or hide the row again.
function view.layout(ctx, settings, rest_h, info_h)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local frame_h = r.ImGui_GetFrameHeight(ctx)
  local entry_h = frame_h + line_h
  local checking = settings.show_check ~= false
  local min_presets = line_h * 3
  local min_preview = line_h * 2 + UIScale.round(10)
  local min_check = checking and (entry_h + UIScale.round(6)) or 0
  local preview_h = line_h * math.max(2, math.floor(tonumber(settings.preview_rows) or 5)) + UIScale.round(10)
  local shown = math.max(1, math.min(6, #(state.data and state.data.history or {})))
  local check_h = checking and (entry_h * shown + UIScale.round(6)) or 0
  local batching = settings.show_projects == true
  -- A batch row is a checkbox with a label beside it, so one frame high.
  local min_projects = batching and (frame_h + UIScale.round(6)) or 0
  local projects_h = batching and (frame_h * math.max(1, math.min(5, state.batch_count or 1)) + UIScale.round(6)) or 0
  local flex = (rest_h or UIScale.round(360)) - info_h - (state.bottom_fixed_h or UIScale.round(150))
  local presets_h = flex - preview_h - check_h - projects_h
  if presets_h < min_presets then
    -- Take the shortfall from the flexible lists before the preset list starves,
    -- newest section first: the batch list is the one most likely to be open
    -- only while it is being used.
    local short = min_presets - presets_h
    local from_projects = math.min(short, projects_h - min_projects)
    projects_h = projects_h - from_projects
    short = short - from_projects
    local from_check = math.min(short, check_h - min_check)
    check_h = check_h - from_check
    short = short - from_check
    preview_h = preview_h - math.min(short, preview_h - min_preview)
    presets_h = math.max(min_presets, flex - preview_h - check_h - projects_h)
  end
  -- Everything is at its floor and it still does not fit. Nothing can be shrunk
  -- further, and the canvas will not scroll, so the only way out is the user
  -- collapsing a section - which is worth saying rather than quietly clipping.
  local cramped = (presets_h + preview_h + check_h + projects_h) > flex + 1
  return presets_h, preview_h, check_h, projects_h, cramped
end

function view.section(ctx, label)
  r.ImGui_Dummy(ctx, 1, UIScale.round(2))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, label)
  r.ImGui_Separator(ctx)
end

function view.badge(ctx, draw_list, x, y, text, color)
  local pad = UIScale.round(5)
  local width = UIScale.text_width(ctx, text) + pad * 2
  local height = r.ImGui_GetTextLineHeight(ctx) + UIScale.round(3)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, UIScale.px(3))
  r.ImGui_DrawList_AddText(draw_list, x + pad, y + UIScale.px(1), color or Theme.colors.text_dim, text)
  return width
end

function view.draw_preset_row(app, preset, index, total)
  local ctx = app.ctx
  local live = state.live_id == preset.id
  r.ImGui_PushID(ctx, preset.id)
  local box_changed, box_value = r.ImGui_Checkbox(ctx, "##pick", state.checked[preset.id] == true)
  if box_changed then state.checked[preset.id] = box_value or nil end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Include in batch render") end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(160)
  local row_w = math.max(UIScale.round(100), avail_w)
  local row_h = r.ImGui_GetTextLineHeight(ctx) * 2 + UIScale.round(12)
  local clicked = r.ImGui_InvisibleButton(ctx, "##row", row_w, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local bg = live and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + row_w, y + row_h, bg, UIScale.px(5))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + row_w, y + row_h, live and Theme.colors.accent or Theme.colors.border, UIScale.px(5), 0, live and UIScale.px(1.4) or UIScale.px(0.7))
  local text_color = Theme.text_for_background(bg, Theme.colors.text, nil, 4.5)
  local dim_color = Theme.dim_text_for_background(bg)
  local text_x = x + UIScale.round(8)
  local text_right = x + row_w - (live and UIScale.round(52) or UIScale.round(6))
  r.ImGui_DrawList_PushClipRect(draw_list, text_x, y, text_right, y + row_h, true)
  r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(5), text_color, preset.name)
  local meta = fmt.summary(preset.settings) .. " | " .. fmt.bounds_label(preset.settings)
  if preset.tag then meta = "#" .. preset.tag .. " | " .. meta end
  local mix = (state.mix_summary or {})[preset.id]
  local rgn = (state.region_summary or {})[preset.id]
  local extras = {}
  if rgn then
    extras[#extras + 1] = rgn.found == rgn.stored
      and (tostring(rgn.found) .. " regions")
      or string.format("%d of %d regions", rgn.found, rgn.stored)
  end
  if mix then
    if mix.muted > 0 then extras[#extras + 1] = "mutes " .. tostring(mix.muted) end
    if mix.soloed > 0 then extras[#extras + 1] = "solos " .. tostring(mix.soloed) end
    if mix.muted == 0 and mix.soloed == 0 then extras[#extras + 1] = "mix stored" end
  end
  if extras[1] then meta = table.concat(extras, ", ") .. " | " .. meta end
  r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(6) + r.ImGui_GetTextLineHeight(ctx), dim_color, meta)
  r.ImGui_DrawList_PopClipRect(draw_list)
  if live then
    view.badge(ctx, draw_list, x + row_w - UIScale.round(46), y + UIScale.round(5), "LIVE", Theme.colors.accent)
  end
  if clicked then view.apply(app, preset) end
  if hovered then
    local tag_line = preset.tag and ("\nSource tag: " .. preset.tag) or ""
    r.ImGui_SetTooltip(ctx, preset.name .. "\n\n" .. fmt.details(preset.settings) .. tag_line .. "\n\nClick to load these settings into the project.")
  end
  if r.ImGui_BeginPopupContextItem(ctx, "##preset_menu") then
    if r.ImGui_MenuItem(ctx, "Apply to project") then view.apply(app, preset) end
    local mix = (state.mix_summary or {})[preset.id]
    if r.ImGui_MenuItem(ctx, mix and "Recapture mute and solo" or "Capture mute and solo") then
      local summary = mixstate.capture(preset.id)
      state.mix_summary = state.mix_summary or {}
      state.mix_summary[preset.id] = summary
      app.status = string.format("%s remembers %d muted and %d soloed track(s) in this project",
        preset.name, summary.muted, summary.soloed)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx,
        "Store the mute and solo of every track as they stand now, for this\n" ..
        "preset in this project. They are set while it renders and put back\n" ..
        "afterwards; clicking the preset never changes them.\n\n" ..
        "Kept with the project, not with the preset: track identities do not\n" ..
        "carry over, and a preset that muted nothing would quietly render a\n" ..
        "full mix under the wrong name.")
    end
    if r.ImGui_MenuItem(ctx, "Regions...") then
      state.regions_id = preset.id
      state.regions_pick = {}
      for _, id in ipairs(regionset.read(preset.id) or {}) do state.regions_pick[id] = true end
      state.regions_open = true
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx,
        "Pick which regions this preset renders in this project. Each one is\n" ..
        "rendered as its own range, so $region and $regionnumber name the files.\n\n" ..
        "Kept with the project, like the mute and solo: region ids mean nothing\n" ..
        "in another project. Stored by id, so moving a region is fine.")
    end
    if mix and r.ImGui_MenuItem(ctx, "Forget mute and solo") then
      mixstate.write(preset.id, nil)
      if state.mix_summary then state.mix_summary[preset.id] = nil end
      app.status = preset.name .. " no longer changes mute or solo"
    end
    if r.ImGui_BeginMenu(ctx, "Source tag") then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Selects these tracks before rendering")
      tags.load(app)
      if r.ImGui_MenuItem(ctx, "(none)", nil, preset.tag == nil) then
        preset.tag = nil
        preset.updated_at = util.now()
        store.save()
      end
      if #(state.tags_list or {}) == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No tags found.")
      end
      for _, name in ipairs(state.tags_list or {}) do
        local count = (state.tags_here or {})[name] or 0
        local label = count == 1 and "1 track here" or (tostring(count) .. " tracks here")
        if count == 0 then label = "not in this project" end
        if r.ImGui_MenuItem(ctx, name, label, preset.tag == name) then
          preset.tag = name
          preset.updated_at = util.now()
          store.save()
          view.apply(app, preset)
        end
      end
      r.ImGui_EndMenu(ctx)
    end
    local update_clicked = r.ImGui_MenuItem(ctx, "Update from project")
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Close REAPER's render window first, or press Save settings there.\nOnly then do its settings reach the project.")
    end
    if update_clicked then
      preset.settings = proj.snapshot()
      preset.updated_at = util.now()
      store.save()
      state.preview_dirty = true
      app.status = "Preset updated from the current render settings: " .. preset.name
    end
    if r.ImGui_MenuItem(ctx, "Rename") then
      state.rename_id = preset.id
      state.rename_text = preset.name
      state.rename_open = true
    end
    if r.ImGui_MenuItem(ctx, "Duplicate") then
      local copy = store.add(preset.name .. " Copy", util.copy(preset.settings))
      copy.tag = preset.tag
      store.save()
      app.status = "Duplicated preset: " .. copy.name
    end
    r.ImGui_Separator(ctx)
    if index > 1 and r.ImGui_MenuItem(ctx, "Move up") then store.move(preset.id, -1) end
    if index < total and r.ImGui_MenuItem(ctx, "Move down") then store.move(preset.id, 1) end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Delete") then
      store.remove(preset.id)
      app.status = "Deleted preset: " .. preset.name
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopID(ctx)
end

function view.draw_presets(app, height)
  local ctx = app.ctx
  local presets = state.data.presets
  if r.ImGui_BeginChild(ctx, "##render_hub_presets", 0, height, 0) then
    local ok, err = pcall(function()
      if #presets == 0 then
        r.ImGui_TextWrapped(ctx, "No presets yet.")
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Set up the REAPER render window the way you want it, then capture it here.")
      else
        for index, preset in ipairs(presets) do view.draw_preset_row(app, preset, index, #presets) end
      end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
  end
end

-- Which context the bounds hand to the wildcards. Only what BOUNDSFLAG settles
-- is claimed here: whether stems are on lives in a bit of RENDER_SETTINGS whose
-- meaning is not documented well enough to warn about, so $track is left alone
-- rather than warned about wrongly.
function view.bounds_context(bounds)
  if bounds == 3 or bounds == 5 then return "regions" end
  if bounds == 4 then return "items" end
  if bounds == 0 then return "range" end
  return "whole"
end

local CONTEXT_WILDCARDS = {
  regions = { "$region", "$regionname", "$regionnumber" },
  items = { "$item", "$itemnumber", "$itemnotes", "$takemarker", "$lane" }
}

-- A wildcard that cannot resolve does not just come out empty: REAPER also eats
-- the space, hyphen, underscore or dot next to it. So the name silently stays as
-- it was and adding the wildcard appears to do nothing at all.
function view.empty_wildcards()
  local pattern = tostring(state.pattern or "")
  if pattern == "" then return nil end
  local bounds = math.floor(tonumber(state.current and state.current.numbers and state.current.numbers.RENDER_BOUNDSFLAG) or 1)
  local context = view.bounds_context(bounds)
  local stale = {}
  for needed, tokens in pairs(CONTEXT_WILDCARDS) do
    if context ~= needed and not (needed == "regions" and context == "range") then
      for _, token in ipairs(tokens) do
        if pattern:find(token, 1, true) then stale[#stale + 1] = token end
      end
    end
  end
  if #stale == 0 then return nil end
  table.sort(stale)
  return table.concat(stale, ", ")
end

-- Why REAPER refuses to name any output. The generic three-way guess was not
-- enough to act on; each of these is checkable.
-- With the source set to the region render matrix, regions alone are not enough:
-- every region needs tracks assigned to it in the matrix, and until then REAPER
-- reports 0 files however many regions exist. Returns nil when it cannot tell,
-- so silence means "no opinion" rather than "empty".
function view.region_matrix_empty()
  if not r.EnumRegionRenderMatrix then return nil end
  local _, markers, regions = r.CountProjectMarkers(0)
  local total = (markers or 0) + (regions or 0)
  -- The region index of the matrix is not documented clearly enough to be sure
  -- whether it counts regions only or every marker, so both are covered by
  -- simply asking about every index. Only "is anything assigned" is needed.
  for index = 0, math.max(0, total - 1) do
    local ok, track = pcall(r.EnumRegionRenderMatrix, 0, index, 0)
    if ok and track then return false end
  end
  return true
end

function view.unresolved_reason()
  local numbers = state.current and state.current.numbers or {}
  local bounds = math.floor(tonumber(numbers.RENDER_BOUNDSFLAG) or 1)
  local label = fmt.bounds_label(state.current or {})
  if bounds == 2 then
    local from, to = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if ((to or 0) - (from or 0)) <= 0 then return label .. ", but there is no time selection" end
  elseif bounds == 3 then
    local _, _, regions = r.CountProjectMarkers(0)
    if (regions or 0) == 0 then return label .. ", but this project has no regions" end
    if view.region_matrix_empty() == true then
      return label .. ", but the region render matrix has no tracks assigned - assign them in Region Matrix, or set Source to Master mix"
    end
  elseif bounds == 5 then
    local _, _, regions = r.CountProjectMarkers(0)
    if (regions or 0) == 0 then return label .. ", but this project has no regions" end
    return label .. ", and no region seems to be selected - REAPER does not let a script read that, so this one is a guess"
  elseif bounds == 4 then
    if (r.CountSelectedMediaItems(0) or 0) == 0 then return label .. ", but no items are selected" end
  elseif bounds == 0 then
    local from = tonumber(numbers.RENDER_STARTPOS) or 0
    local to = tonumber(numbers.RENDER_ENDPOS) or 0
    if (to - from) <= 0 then return label .. ", but the range is empty" end
  end
  return label .. ": REAPER reports no output for these settings"
end

function view.draw_preview(app, settings, height)
  local ctx = app.ctx
  if r.ImGui_BeginChild(ctx, "##render_hub_preview", 0, height, 0) then
    local ok, err = pcall(function()
      if state.targets_error then
        r.ImGui_TextColored(ctx, Theme.colors.warning, state.targets_error)
        return
      end
      -- A ticked preset with a region list writes those files, not the ones the
      -- project's own bounds would give, so that is the list worth showing.
      local list = state.region_targets or state.targets
      if state.region_targets then
        r.ImGui_TextColored(ctx, Theme.colors.accent,
          state.region_preset.name .. ": one file per region")
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx,
            "Each region is rendered as its own range, which is what lets $region\n" ..
            "and $regionnumber name the files. The preset's own bounds are not\n" ..
            "used while it has a region list.\n\n" ..
            "These names come from REAPER, asked the same way the render asks.")
        end
      end
      if #list == 0 then
        if state.targets_unresolved then
          r.ImGui_TextColored(ctx, Theme.colors.warning, "REAPER names no output:")
          r.ImGui_TextWrapped(ctx, view.unresolved_reason())
        else
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No output files with these settings.")
        end
        return
      end
      for index, path in ipairs(list) do
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, string.format("%2d.", index))
        r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
        r.ImGui_Text(ctx, util.basename(path))
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, path) end
      end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
  end
  -- The region list is applied while rendering, not to the project, so the list
  -- above cannot show it: it is REAPER's answer about the settings as they stand.
  -- Simulating it would mean writing bounds into the project on every refresh and
  -- marking it modified twice a second, which is a worse trade than saying so.
  local stale = view.empty_wildcards()
  if stale then
    r.ImGui_TextColored(ctx, Theme.colors.warning, stale .. ": nothing to resolve to")
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx,
        "These need a context the current bounds do not give: region wildcards\n" ..
        "want region bounds (or a range inside a region), item wildcards want\n" ..
        "\"selected media items\".\n\n" ..
        "REAPER drops an empty wildcard and the space, hyphen, underscore or dot\n" ..
        "beside it as well - so the name comes out unchanged and adding the\n" ..
        "wildcard looks like it did nothing.")
    end
  end
  -- After EndChild the child counts as an item, so the row count sits on the
  -- right-click of the list it applies to instead of in a settings panel.
  if r.ImGui_BeginPopupContextItem(ctx, "##render_hub_preview_menu") then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preview height")
    for _, rows in ipairs({ 3, 5, 8, 12 }) do
      if r.ImGui_MenuItem(ctx, tostring(rows) .. " rows", nil, (tonumber(settings.preview_rows) or 5) == rows) then
        settings.preview_rows = rows
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

function view.draw_output(app, settings)
  local ctx = app.ctx
  local button_w = UIScale.round(26)
  local gap = UIScale.gap(4)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  r.ImGui_SetNextItemWidth(ctx, math.max(UIScale.round(60), avail_w - button_w - gap))
  local dir_changed, dir_value = r.ImGui_InputTextWithHint(ctx, "##render_hub_dir", "Project folder", state.dir)
  state.dir_active = r.ImGui_IsItemActive(ctx) == true
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Render directory. Empty renders next to the project.") end
  -- Commit only what was typed into this field while it had the keyboard. A
  -- change reported without focus is the widget echoing back the value we just
  -- handed it, and writing that would overwrite a newer one from elsewhere.
  if dir_changed and state.dir_active and dir_value ~= state.dir_project then
    state.dir = dir_value
    state.dir_project = dir_value
    proj.set_string("RENDER_FILE", dir_value)
    state.preview_dirty = true
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "...##render_hub_browse", button_w, 0) then
    local folder = view.browse_dir(app)
    if folder then
      state.dir = folder
      state.dir_project = folder
      proj.set_string("RENDER_FILE", folder)
      state.preview_dirty = true
    end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Browse for a render directory") end

  avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  r.ImGui_SetNextItemWidth(ctx, math.max(UIScale.round(60), avail_w - button_w - gap))
  local pattern_changed, pattern_value = r.ImGui_InputTextWithHint(ctx, "##render_hub_pattern", "$project", state.pattern)
  state.pattern_active = r.ImGui_IsItemActive(ctx) == true
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "File name pattern. The list below is REAPER's own resolved output.") end
  if pattern_changed and state.pattern_active and pattern_value ~= state.pattern_project then
    state.pattern = pattern_value
    state.pattern_project = pattern_value
    proj.set_string("RENDER_PATTERN", pattern_value)
    state.preview_dirty = true
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "$##render_hub_wildcards", button_w, 0) then r.ImGui_OpenPopup(ctx, "render_hub_wildcards") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Append a wildcard to the pattern") end
  if r.ImGui_BeginPopup(ctx, "render_hub_wildcards") then
    -- The modifiers are worth stating here: they are the part of the syntax that
    -- nobody guesses, and they apply to every token in the submenus below.
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "$Track capitalises  |  $TRack UPPER  |  $tRack lower")
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "$track< > drops spaces  |  $track< _> swaps them  |  $region[<4] truncates")
    r.ImGui_Separator(ctx)
    for _, group in ipairs(WILDCARDS) do
      if r.ImGui_BeginMenu(ctx, group.group) then
        for _, item in ipairs(group.items) do
          if r.ImGui_MenuItem(ctx, item[1], item[2]) then
            -- Append to what the project holds right now, not to a copy that
            -- may have been overtaken by REAPER's own render dialog.
            state.pattern = tostring(state.pattern_project or state.pattern or "") .. item[1]
            state.pattern_project = state.pattern
            proj.set_string("RENDER_PATTERN", state.pattern)
            state.preview_dirty = true
          end
        end
        r.ImGui_EndMenu(ctx)
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

function view.draw_render_row(app, settings)
  local ctx = app.ctx
  local picked = store.checked_presets()
  local gap = UIScale.gap(6)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  local button_h = UIScale.button_h(ctx, 26)
  local queue_w = UIScale.text_button_w(ctx, "Queue", 56)
  local main_w = math.max(UIScale.round(70), avail_w - queue_w * 2 - gap * 2)
  -- Render follows the ticks the same way Queue does: two buttons side by side
  -- that answered a tick differently was the confusing part, not the count.
  local entries = view.batch_entries()
  local projects = #view.checked_entries(entries)
  local main_label = "Render"
  if projects > 0 then main_label = "Render " .. tostring(projects)
  elseif #picked > 1 then main_label = "Render " .. tostring(#picked) .. " presets" end
  local blocked = projects > 0 and view.batch_blocker(picked, entries) ~= nil
    or (projects == 0 and #state.targets == 0 and #picked == 0)
  if blocked and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
  local render_clicked = r.ImGui_Button(ctx, main_label .. "##render_hub_render", main_w, button_h)
  r.ImGui_PopStyleColor(ctx, 2)
  if render_clicked then
    -- One ticked preset goes the same way as several. It used to be applied and
    -- then rendered raw, which skipped anything else a preset carries - its mix
    -- state, for one - so a single tick behaved differently from two.
    if projects > 0 then view.render_projects_now(app, settings, picked)
    elseif #picked > 0 then view.render_presets_now(app, settings, picked)
    else view.render_now(app, settings) end
  end
  if r.ImGui_IsItemHovered(ctx) then
    if projects > 0 then
      r.ImGui_SetTooltip(ctx, string.format(
        "Render the %d ticked project(s) now, once per ticked preset.\n\n" ..
        "Straight into each project where it stands - no queue, so a project you\n" ..
        "already have open is not written out and read back again. Open tabs are\n" ..
        "put back the way they were and files are left untouched on disk.\n\n" ..
        "This runs until it is done. Use Queue if you would rather start it later.", projects))
    elseif #picked > 1 then
      r.ImGui_SetTooltip(ctx, "Render this project once per ticked preset, one after the other.\n\n" ..
        "Straight into this project - the render queue is not involved, so nothing\n" ..
        "waiting there is touched and the project is not reloaded per preset.\n" ..
        "Your render settings are put back afterwards.")
    else
      r.ImGui_SetTooltip(ctx, "Render this project with the current settings.\n\nProjects ticked under PROJECTS are not included - use Queue for those.")
    end
  end
  if blocked and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  -- One Queue button, and what it queues follows the ticks - the same way the
  -- Render button already follows the ticked presets. The current project is an
  -- open tab in that list too, so a second button for "this one" would only be
  -- the same work by another route.
  r.ImGui_SameLine(ctx, 0, gap)
  local queue_label = projects > 0 and ("Queue " .. tostring(projects)) or "Queue"
  if r.ImGui_Button(ctx, queue_label .. "##render_hub_queue", queue_w, button_h) then
    if projects > 0 then
      view.run_projects(app, settings, picked)
    elseif #picked > 0 then
      local queued, expected, label = view.queue_presets(app, picked)
      view.remember_queued(expected, label)
      view.scan_queue(true)
      app.status = "Queued " .. tostring(queued) .. " preset" .. (queued == 1 and "" or "s") .. " - press Run to render"
    elseif view.run_command(app, "queue_add") then
      view.remember_queued(state.targets, proj.project_name())
      view.scan_queue(true)
      app.status = "Added the current settings to the render queue"
    end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, projects > 0
      and ("Add the " .. tostring(projects) .. " ticked project(s) under PROJECTS to the queue,\nwith the ticked presets. Press Run when you want them rendered.")
      or "Add this project to the render queue without rendering.\nTick projects under PROJECTS to queue those instead.")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  local waiting = #(view.scan_queue(false) or {})
  local run_label = waiting > 0 and ("Run " .. tostring(waiting)) or "Run"
  if waiting > 0 then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
  end
  local run_clicked = r.ImGui_Button(ctx, run_label .. "##render_hub_run_queue", queue_w, button_h)
  if waiting > 0 then r.ImGui_PopStyleColor(ctx, 2) end
  if run_clicked then view.flush_queue(app, settings) end
  if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1) then
    state.queue_clear_armed = false
    r.ImGui_OpenPopup(ctx, "render_hub_queue_popup")
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, view.queue_tooltip()) end
  view.draw_queue_popup(app)
end

function view.draw_check_row(app, entry, profile)
  local ctx = app.ctx
  local verdict, reason = loud.verdict(entry, profile)
  local color = Theme.colors.text_dim
  if verdict == "pass" then color = Theme.colors.accent
  elseif verdict == "warn" then color = Theme.colors.warning
  elseif verdict == "fail" then color = Theme.colors.danger end
  r.ImGui_PushID(ctx, entry.path)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), entry.missing and Theme.colors.danger or Theme.colors.text)
  local clicked = r.ImGui_Selectable(ctx, util.basename(entry.path), false)
  r.ImGui_PopStyleColor(ctx)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, entry.path .. "\n" .. fmt.date(entry.at) .. (reason and ("\n" .. reason) or "") .. "\n\nClick to show in the file browser.")
  end
  if clicked then util.show_file(entry.path) end
  local detail
  if entry.missing then
    detail = "file not found"
  elseif entry.lufs then
    detail = string.format("%s LUFS | %s dBTP | %s", fmt.db(entry.lufs), fmt.db(entry.tp), util.human_size(entry.size))
    if entry.clip and entry.clip > 0 then detail = detail .. " | " .. tostring(math.floor(entry.clip)) .. " clipped" end
  else
    detail = util.human_size(entry.size) .. " | not measured"
  end
  if r.ImGui_BeginPopupContextItem(ctx, "##history_menu") then
    if r.ImGui_MenuItem(ctx, "Show in folder") then util.show_file(entry.path) end
    if r.ImGui_MenuItem(ctx, "Measure loudness") then
      state.measure_queue[#state.measure_queue + 1] = { path = entry.path }
    end
    if r.ImGui_MenuItem(ctx, "Insert into project") then
      r.InsertMedia(entry.path, 1)
      app.status = "Inserted " .. util.basename(entry.path)
    end
    if r.ImGui_MenuItem(ctx, "Remove from list") then
      for index, candidate in ipairs(state.data.history) do
        if candidate.path == entry.path then table.remove(state.data.history, index); break end
      end
      store.save()
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopID(ctx)
end

function view.draw_check(app, settings, list_h)
  local ctx = app.ctx
  local profile, profile_index = loud.profile(settings)
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##render_hub_profile", profile.name) then
    for index, candidate in ipairs(PROFILES) do
      if r.ImGui_Selectable(ctx, candidate.name, index == profile_index) then
        settings.profile_index = index
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  local history = state.data.history
  -- Fixed height with its own scrollbar: the render history must never push the
  -- rest of the panel past the bottom of the canvas.
  if r.ImGui_BeginChild(ctx, "##render_hub_history", 0, math.max(UIScale.round(20), list_h or UIScale.round(80)), 0) then
    local ok, err = pcall(function()
      if #history == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Nothing rendered yet.")
        return
      end
      for _, entry in ipairs(history) do view.draw_check_row(app, entry, profile) end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
  end
  local gap = UIScale.gap(6)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  local half = math.max(UIScale.round(60), (avail_w - gap) * 0.5)
  if r.ImGui_Button(ctx, "Measure##render_hub_measure", half, 0) then view.measure_all(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, loud.available() and "Measure LUFS-I and true peak of the rendered files" or "Needs REAPER 6.62 or newer")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Open folder##render_hub_open", half, 0) then
    -- Falls back to the configured render directory before anything was rendered.
    local folder = history[1] and util.dirname(history[1].path) or proj.render_dir()
    if folder ~= "" then util.open_folder(folder) else app.status = "No render folder to open" end
  end
end

function view.draw_projects(app, settings, list_h)
  local ctx = app.ctx
  local picked = store.checked_presets()
  local entries = view.batch_entries()
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Renders other projects with the ticked presets. Nothing is saved.")
  if r.ImGui_BeginChild(ctx, "##render_hub_projects", 0, math.max(UIScale.round(20), list_h or UIScale.round(70)), 0) then
    local ok, err = pcall(function()
      for index, entry in ipairs(entries) do
        r.ImGui_PushID(ctx, entry.key)
        local changed, value = r.ImGui_Checkbox(ctx, "##pick", state.batch_checked[entry.key] == true)
        if changed then state.batch_checked[entry.key] = value or nil end
        r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
        local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)
        local button_w = entry.kind == "file" and UIScale.round(22) or 0
        local start_x = r.ImGui_GetCursorPosX(ctx)
        local unsaved = entry.kind == "tab" and entry.path == ""
        local label = entry.name
        if unsaved then label = label .. "  (open, never saved)"
        elseif entry.kind == "tab" then label = label .. "  (open)" end
        r.ImGui_TextColored(ctx, unsaved and Theme.colors.warning or (entry.kind == "tab" and Theme.colors.text or Theme.colors.text_dim),
          util.fit(ctx, label, avail_w - button_w - UIScale.gap(6)))
        if r.ImGui_IsItemHovered(ctx) then
          local body = entry.kind == "tab"
            and "An open tab: rendered as it stands right now, including edits you have not saved.\nSwitching to it loses nothing and its render settings are put back afterwards."
            or "A file on disk: opened over the front tab and left untouched.\nWhat gets rendered is what was last saved to it."
          if unsaved then
            body = body .. "\n\nThis one has no file yet, so $project has no settled value: the render\nworks, but its file name cannot be known in advance and it will not\nappear under CHECK. Save the project to get both."
          end
          r.ImGui_SetTooltip(ctx, (entry.path ~= "" and entry.path or "Never saved") .. "\n\n" .. body)
        end
        if entry.kind == "file" then
          r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
          r.ImGui_SetCursorPosX(ctx, start_x + avail_w - button_w)
          if r.ImGui_Button(ctx, "x", button_w, 0) then
            for position, path in ipairs(state.projects) do
              if path == entry.path then table.remove(state.projects, position); break end
            end
            state.batch_checked[entry.key] = nil
          end
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove from the batch") end
        end
        r.ImGui_PopID(ctx)
      end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
  end
  local gap = UIScale.gap(6)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  -- No buttons of its own beyond adding files: this section decides *what* is
  -- queued, the RENDER row decides *when*.
  if r.ImGui_Button(ctx, "Add...##render_hub_add_projects", avail_w, 0) then view.add_projects(app) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "Add .rpp files that are not open. Projects you already have open are\n" ..
      "listed above on their own.\n\n" ..
      "An open tab is read as it stands and put back the way it was. A file is\n" ..
      "opened over the front tab and left untouched on disk. Nothing is saved: the\n" ..
      "queue keeps its own copy of every job, which is what makes that safe.")
  end
  local blocker = view.batch_blocker(picked, entries)
  if blocker and #view.checked_entries(entries) > 0 then
    r.ImGui_TextColored(ctx, Theme.colors.warning, blocker)
  end
  if blocker then
    r.ImGui_TextColored(ctx, Theme.colors.warning, blocker)
  end
end

function view.draw_regions_popup(app)
  local ctx = app.ctx
  if state.regions_open then
    r.ImGui_OpenPopup(ctx, "Preset Regions")
    state.regions_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Preset Regions") then return end
  local preset = state.regions_id and store.find(state.regions_id) or nil
  if not preset then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "That preset is gone.")
    r.ImGui_EndPopup(ctx)
    return
  end
  local all = regionset.all()
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Regions " .. preset.name .. " renders in this project:")
  if #all == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "This project has no regions.")
  end
  state.regions_pick = state.regions_pick or {}
  for _, region in ipairs(all) do
    r.ImGui_PushID(ctx, region.id)
    local changed, value = r.ImGui_Checkbox(ctx, region.name .. "##rgn", state.regions_pick[region.id] == true)
    if changed then state.regions_pick[region.id] = value or nil end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, string.format("id %d  |  %.3f to %.3f", region.id, region.pos, region.stop))
    end
    r.ImGui_PopID(ctx)
  end
  if #all > 0 then
    local small_ok = r.ImGui_SmallButton ~= nil
    if small_ok and r.ImGui_SmallButton(ctx, "All") then
      for _, region in ipairs(all) do state.regions_pick[region.id] = true end
    end
    if small_ok then r.ImGui_SameLine(ctx) end
    if small_ok and r.ImGui_SmallButton(ctx, "None") then state.regions_pick = {} end
  end
  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Nothing ticked means the preset's own bounds are used.")
  local button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  if r.ImGui_Button(ctx, "Save", button_w, 0) then
    local ids = {}
    for _, region in ipairs(all) do
      if state.regions_pick[region.id] then ids[#ids + 1] = region.id end
    end
    regionset.write(preset.id, ids)
    state.mix_summary = state.mix_summary or {}
    state.region_summary = state.region_summary or {}
    state.region_summary[preset.id] = regionset.summary(preset.id)
    app.status = #ids > 0
      and string.format("%s renders %d region(s) in this project", preset.name, #ids)
      or (preset.name .. " uses its own bounds again")
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

function view.draw_capture_popup(app)
  local ctx = app.ctx
  if state.capture_open then
    r.ImGui_OpenPopup(ctx, "Capture Render Preset")
    state.capture_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Capture Render Preset") then return end
  -- Shown rather than described: REAPER writes the render window's settings into
  -- the project only when that window is closed or its Save settings button is
  -- pressed, so capturing while it is open stores the previous state. Seeing the
  -- source and bounds about to be saved catches that at the moment it matters.
  local snapshot = proj.snapshot()
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "About to store:")
  r.ImGui_Text(ctx, fmt.source_label(snapshot) .. "  |  " .. fmt.bounds_label(snapshot))
  r.ImGui_Text(ctx, fmt.summary(snapshot))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, util.clean(snapshot.strings.RENDER_PATTERN, "(default pattern)"))
  -- An exact twin of an existing preset is the shape this mistake takes, so the
  -- warning is raised on that rather than on every capture.
  local twin = nil
  for _, preset in ipairs(state.data.presets) do
    if proj.same(preset.settings, snapshot) then twin = preset; break end
  end
  if twin then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Identical to \"" .. twin.name .. "\".")
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Close REAPER's render window first, or press Save")
    r.ImGui_TextColored(ctx, Theme.colors.warning, "settings there: only then does it reach the project.")
  end
  r.ImGui_Separator(ctx)
  local changed, value = r.ImGui_InputText(ctx, "Name", state.capture_name or "")
  if changed then state.capture_name = value end
  local can_save = util.clean(state.capture_name, "") ~= ""
  local button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  if not can_save and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Save", button_w, 0) and can_save then
    local preset = store.add(state.capture_name, proj.snapshot())
    state.preview_dirty = true
    app.status = "Captured render preset: " .. preset.name
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

function view.draw_rename_popup(app)
  local ctx = app.ctx
  if state.rename_open then
    r.ImGui_OpenPopup(ctx, "Rename Render Preset")
    state.rename_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Rename Render Preset") then return end
  local changed, value = r.ImGui_InputText(ctx, "Name", state.rename_text or "")
  if changed then state.rename_text = value end
  local preset = store.find(state.rename_id)
  local can_save = preset ~= nil and util.clean(state.rename_text, "") ~= ""
  local button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  if not can_save and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Save", button_w, 0) and can_save then
    preset.name = util.clean(state.rename_text, preset.name)
    preset.updated_at = util.now()
    store.save()
    app.status = "Renamed preset"
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

function view.draw_header(app)
  local ctx = app.ctx
  local button_w = UIScale.round(26)
  local gap = UIScale.gap(4)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  local start_x = r.ImGui_GetCursorPosX(ctx)
  local name_w = math.max(UIScale.round(30), avail_w - button_w * 2 - gap * 3)
  local name = proj.project_name()
  local fitted = util.fit(ctx, name, name_w)
  r.ImGui_TextColored(ctx, Theme.colors.accent, fitted)
  if fitted ~= name and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, name) end
  r.ImGui_SameLine(ctx, 0, gap)
  r.ImGui_SetCursorPosX(ctx, math.max(r.ImGui_GetCursorPosX(ctx), start_x + avail_w - button_w * 2 - gap))
  if r.ImGui_Button(ctx, "+##render_hub_capture", button_w, 0) then
    state.capture_name = "Preset " .. tostring(#state.data.presets + 1)
    state.capture_open = true
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Capture the current render settings as a preset") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "D##render_hub_dialog", button_w, 0) then view.run_command(app, "dialog") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Open REAPER's render window to set things up") end
end

--------------------------------------------------------------------------------
-- module contract
--------------------------------------------------------------------------------

function M.init(app)
  util.ensure_settings(app)
  util.verify_commands()
  store.load(app)
  state.preview_dirty = true
end

-- Runs for every module each frame, so this only drains the measure queue:
-- one file per frame keeps a long master from stalling the whole window.
function M.update(app)
  if not state.loaded then return end
  view.recheck_missing()
  local job = table.remove(state.measure_queue, 1)
  if not job then return end
  local lufs, peak = loud.measure(job.path)
  local entry = store.find_history(job.path)
  if entry then
    entry.lufs = lufs
    entry.tp = peak
    entry.missing = util.file_size(job.path) == nil
    store.save()
  end
end

function M.draw(app)
  local ctx = app.ctx
  local settings = util.ensure_settings(app)
  if not state.loaded then store.load(app) end
  view.refresh(false)
  view.sync_fields()

  view.draw_header(app)
  view.draw_capture_popup(app)
  view.draw_rename_popup(app)
  view.draw_regions_popup(app)

  local info_h = UI.info_line_height(ctx)

  view.section(ctx, "PRESETS")
  -- The fixed rows below the list are measured while they are drawn and reused on
  -- the next frame, so the layout adapts to the real content instead of to a
  -- formula's guess about it. One frame of lag on a resize, which is invisible.
  local _, rest_h = r.ImGui_GetContentRegionAvail(ctx)
  local presets_h, preview_h, check_list_h, projects_list_h, cramped = view.layout(ctx, settings, rest_h, info_h)
  view.draw_presets(app, presets_h)

  local bottom_start = r.ImGui_GetCursorPosY(ctx)

  view.section(ctx, "OUTPUT")
  view.draw_output(app, settings)
  view.draw_preview(app, settings, preview_h)

  view.section(ctx, "RENDER")
  view.draw_render_row(app, settings)

  if r.ImGui_CollapsingHeader then
    -- DefaultOpen only applies the first time the id is seen, so the stored
    -- preference decides the initial state and the user's toggle wins after that.
    local flags = 0
    if settings.show_check ~= false and r.ImGui_TreeNodeFlags_DefaultOpen then flags = r.ImGui_TreeNodeFlags_DefaultOpen() end
    local open = r.ImGui_CollapsingHeader(ctx, "CHECK##render_hub_check", nil, flags) == true
    if open ~= (settings.show_check ~= false) then
      settings.show_check = open
      if app.save_settings then app.save_settings() end
    end
    if open then view.draw_check(app, settings, check_list_h) end

    local project_flags = 0
    if settings.show_projects == true and r.ImGui_TreeNodeFlags_DefaultOpen then project_flags = r.ImGui_TreeNodeFlags_DefaultOpen() end
    local projects_open = r.ImGui_CollapsingHeader(ctx, "PROJECTS##render_hub_projects_header", nil, project_flags) == true
    if projects_open ~= (settings.show_projects == true) then
      settings.show_projects = projects_open
      if app.save_settings then app.save_settings() end
    end
    if projects_open then view.draw_projects(app, settings, projects_list_h) end
  end

  -- What the fixed rows cost, with the flexible list heights taken back out.
  local bottom_h = math.max(0, r.ImGui_GetCursorPosY(ctx) - bottom_start)
  state.bottom_fixed_h = math.max(0, bottom_h - preview_h
    - (settings.show_check ~= false and check_list_h or 0)
    - (settings.show_projects == true and projects_list_h or 0))

  local status = string.format("%d file%s | %s", #state.targets, #state.targets == 1 and "" or "s", fmt.summary(state.current or {}))
  local severity = nil
  if state.last_error then
    status = state.last_error
    severity = "warning"
  elseif state.targets_error then
    status = state.targets_error
    severity = "warning"
  elseif state.targets_unresolved then
    status = "No resolvable output | " .. fmt.bounds_label(state.current or {})
    severity = "warning"
  elseif cramped then
    status = "Panel too short - collapse CHECK or PROJECTS"
    severity = "warning"
  end
  UI.draw_info_line(ctx, status, { severity = severity, details = state.current and fmt.details(state.current) or nil })
end

return M
