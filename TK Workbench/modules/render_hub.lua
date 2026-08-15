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
  tags_map = {},
  tags_list = {},
  tags_here = {},
  tags_at = nil,
  commands = {},
  commands_checked = false,
  last_error = nil
}

local util = {}
local tags = {}
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

function view.refresh(force)
  local now = util.precise_now()
  if not force and not state.preview_dirty and (now - state.targets_at) < PREVIEW_INTERVAL then return end
  state.targets_at = now
  state.preview_dirty = false
  state.current = proj.snapshot()
  state.targets, state.targets_error, state.targets_unresolved = proj.read_targets()
  state.targets = state.targets or {}
  -- Two presets can hold identical settings, and then "which one is live" has no
  -- single answer. The one the user last applied wins as long as it still
  -- matches, so clicking a row always moves the badge to that row instead of
  -- leaving it on whichever twin happens to come first in the list.
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

function view.render_batch(app, settings, presets)
  local queued, expected, label = view.queue_presets(app, presets)
  if queued == 0 then
    app.status = "The ticked presets produce no files"
    return
  end
  if not view.run_command(app, "queue_run") then return end
  local written = store.record_render(expected, label, settings.auto_measure ~= false)
  state.preview_dirty = true
  app.status = string.format("Batch render: %d of %d files written", written, #expected)
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
  local entry_h = r.ImGui_GetFrameHeight(ctx) + line_h
  local checking = settings.show_check ~= false
  local min_presets = line_h * 3
  local min_preview = line_h * 2 + UIScale.round(10)
  local min_check = checking and (entry_h + UIScale.round(6)) or 0
  local preview_h = line_h * math.max(2, math.floor(tonumber(settings.preview_rows) or 5)) + UIScale.round(10)
  local shown = math.max(1, math.min(6, #(state.data and state.data.history or {})))
  local check_h = checking and (entry_h * shown + UIScale.round(6)) or 0
  local flex = (rest_h or UIScale.round(360)) - info_h - (state.bottom_fixed_h or UIScale.round(150))
  local presets_h = flex - preview_h - check_h
  if presets_h < min_presets then
    -- Take the shortfall from the two lists before the preset list starves.
    local short = min_presets - presets_h
    local from_check = math.min(short, check_h - min_check)
    check_h = check_h - from_check
    short = short - from_check
    preview_h = preview_h - math.min(short, preview_h - min_preview)
    presets_h = math.max(min_presets, flex - preview_h - check_h)
  end
  return presets_h, preview_h, check_h
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

function view.draw_preview(app, settings, height)
  local ctx = app.ctx
  if r.ImGui_BeginChild(ctx, "##render_hub_preview", 0, height, 0) then
    local ok, err = pcall(function()
      if state.targets_error then
        r.ImGui_TextColored(ctx, Theme.colors.warning, state.targets_error)
        return
      end
      if #state.targets == 0 then
        if state.targets_unresolved then
          r.ImGui_TextColored(ctx, Theme.colors.warning, "REAPER cannot resolve output names.")
          r.ImGui_TextWrapped(ctx, "The bounds may select nothing (regions or a time selection that do not exist), or the pattern cannot form a file name. Open the render window to check.")
        else
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No output files with these settings.")
        end
        return
      end
      for index, path in ipairs(state.targets) do
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, string.format("%2d.", index))
        r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
        r.ImGui_Text(ctx, util.basename(path))
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, path) end
      end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
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
  local main_label = #picked > 1 and ("Render " .. tostring(#picked) .. " presets") or "Render"
  local blocked = #state.targets == 0 and #picked == 0
  if blocked and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
  local render_clicked = r.ImGui_Button(ctx, main_label .. "##render_hub_render", main_w, button_h)
  r.ImGui_PopStyleColor(ctx, 2)
  if render_clicked then
    if #picked > 1 then view.render_batch(app, settings, picked) else
      if #picked == 1 then view.apply(app, picked[1]) end
      view.render_now(app, settings)
    end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, #picked > 1 and "Queue every ticked preset and render the queue" or "Render with the current settings")
  end
  if blocked and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Queue##render_hub_queue", queue_w, button_h) then
    if #picked > 0 then
      local queued = view.queue_presets(app, picked)
      app.status = "Queued " .. tostring(queued) .. " preset" .. (queued == 1 and "" or "s")
    elseif view.run_command(app, "queue_add") then
      app.status = "Added the current settings to the render queue"
    end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add to REAPER's render queue without rendering") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Run##render_hub_run_queue", queue_w, button_h) then
    if view.run_command(app, "queue_run") then
      state.preview_dirty = true
      app.status = "Render queue finished"
    end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Render everything that is queued") end
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

  local info_h = UI.info_line_height(ctx)

  view.section(ctx, "PRESETS")
  -- The fixed rows below the list are measured while they are drawn and reused on
  -- the next frame, so the layout adapts to the real content instead of to a
  -- formula's guess about it. One frame of lag on a resize, which is invisible.
  local _, rest_h = r.ImGui_GetContentRegionAvail(ctx)
  local presets_h, preview_h, check_list_h = view.layout(ctx, settings, rest_h, info_h)
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
  end

  -- What the fixed rows cost, with the flexible list heights taken back out.
  local bottom_h = math.max(0, r.ImGui_GetCursorPosY(ctx) - bottom_start)
  state.bottom_fixed_h = math.max(0, bottom_h - preview_h - (settings.show_check ~= false and check_list_h or 0))

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
  end
  UI.draw_info_line(ctx, status, { severity = severity, details = state.current and fmt.details(state.current) or nil })
end

return M
