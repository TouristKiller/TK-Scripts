-- Cue presets: what the cue display should do for this song, and how to keep
-- that around.
--
-- Two storages, because there are two questions. What belongs to *this song*
-- lives in the project itself through ProjExtState: it travels with the .RPP,
-- survives "save as", and there is no loose file beside the project that can go
-- missing. What you want to use *again* is exported to a .tkcue file, so a
-- setup made for one song can be dropped onto the next.
--
-- No ImGui in here. The module edits the table this hands back and asks for it
-- to be written; everything below can be tested with a stubbed REAPER.

local r = reaper
local json = require("core.json")

local Presets = {}

Presets.SCHEMA = 1
Presets.EXT = ".tkcue"

local EXT_SECTION = "TK_CUE"
local EXT_KEY = "preset"

--------------------------------------------------------------------------------
-- shape
--------------------------------------------------------------------------------

local function clamp_int(value, low, high, fallback)
  local number = math.floor(tonumber(value) or fallback)
  if number < low then number = low end
  if number > high then number = high end
  return number
end

local function copy(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for key, entry in pairs(value) do out[key] = copy(entry) end
  return out
end

Presets.copy = copy

-- The audio and chord fields are written from the first version on, empty and
-- unused. They cost nothing now and mean the preset a user saves today still
-- opens once the cues can be heard and the chords are in - which is the whole
-- reason the sidecar in Idea Vault could grow a rating without a migration.
function Presets.defaults()
  return {
    schema = Presets.SCHEMA,
    name = "",
    display = {
      beats = true,
      details = true,
      progress = true,
      section_color = false,
      end_of_song = true,
      details_columns = 1,
      chord_countdown = false,
      chord_remaining = false,
      roman_degree = false,
      record_status = false,
      midi_feedback = false
    },
    cues = { warn_bars = 2, flash_on_change = true, count_in_last_bar = true },
    -- Which cues are heard, not which sounds they use: the sounds come in the
    -- next step, and land in a "sounds" table beside this one.
    audio = {
      enabled = false, volume = 0.7,
      beat_click = false, accent = true, warn = true, count_in = true, go = true
    },
    -- Which file plays which cue, by name. Empty means the tone the effect
    -- makes itself, which is also what a name that no longer exists falls back
    -- to: a preset that travels to another machine must not go silent.
    sounds = { warn = "", count_in = "", go = "", beat = "", accent = "" },
    sections = {},
    chord_source = "auto",
    chords = {
      enabled = true,
      show_current = true,
      show_next = true,
      prefer_flats = false,
      include_bass = true,
      minimum_confidence = 0.55,
      minimum_duration = 0.05,
      attack_tolerance = 0.1,
      key_mode = "off",
      key_root = 0
    }
  }
end

-- Anything missing is filled in and anything out of range is pulled back in.
-- A preset comes off disk or out of somebody's project file, so it is never
-- trusted to be the shape this code last wrote.
function Presets.normalize(preset)
  local out = Presets.defaults()
  if type(preset) ~= "table" then return out end
  out.name = tostring(preset.name or "")
  out.chord_source = tostring(preset.chord_source or "auto")
  if out.chord_source == "none" then out.chord_source = "auto" end

  local chords = type(preset.chords) == "table" and preset.chords or {}
  out.chords.enabled = chords.enabled ~= false
  out.chords.show_current = chords.show_current ~= false
  out.chords.show_next = chords.show_next ~= false
  out.chords.prefer_flats = chords.prefer_flats == true
  out.chords.include_bass = chords.include_bass ~= false
  out.chords.minimum_confidence = math.max(0.35, math.min(0.9, tonumber(chords.minimum_confidence) or 0.55))
  out.chords.minimum_duration = math.max(0, math.min(0.5, tonumber(chords.minimum_duration) or 0.05))
  out.chords.attack_tolerance = math.max(0, math.min(0.25, tonumber(chords.attack_tolerance) or 0.1))
  local key_mode = tostring(chords.key_mode or "off")
  out.chords.key_mode = (key_mode == "auto" or key_mode == "major" or key_mode == "minor") and key_mode or "off"
  out.chords.key_root = clamp_int(chords.key_root, 0, 11, 0)

  local display = type(preset.display) == "table" and preset.display or {}
  out.display.beats = display.beats ~= false
  out.display.details = display.details ~= false
  out.display.progress = display.progress ~= false
  out.display.end_of_song = display.end_of_song ~= false
  out.display.details_columns = clamp_int(display.details_columns, 1, 2, 1)
  out.display.chord_countdown = display.chord_countdown == true
  out.display.chord_remaining = display.chord_remaining == true
  out.display.roman_degree = display.roman_degree == true
  out.display.record_status = display.record_status == true
  out.display.midi_feedback = display.midi_feedback == true
  -- Off unless asked for: region colours are chosen for the arrange view, and
  -- not every project has ones that mean anything on a dark panel.
  out.display.section_color = display.section_color == true

  local cues = type(preset.cues) == "table" and preset.cues or {}
  out.cues.warn_bars = clamp_int(cues.warn_bars, 1, 8, 2)
  out.cues.flash_on_change = cues.flash_on_change ~= false
  out.cues.count_in_last_bar = cues.count_in_last_bar ~= false

  local audio = type(preset.audio) == "table" and preset.audio or {}
  out.audio.enabled = audio.enabled == true
  out.audio.volume = math.max(0, math.min(1, tonumber(audio.volume) or 0.7))
  -- The plain beat click is the one that defaults off: REAPER already has a
  -- metronome, and two of them disagreeing is worse than neither.
  out.audio.beat_click = audio.beat_click == true
  out.audio.accent = audio.accent ~= false
  out.audio.warn = audio.warn ~= false
  out.audio.count_in = audio.count_in ~= false
  out.audio.go = audio.go ~= false

  local sounds = type(preset.sounds) == "table" and preset.sounds or {}
  for _, key in ipairs({ "warn", "count_in", "go", "beat", "accent" }) do
    out.sounds[key] = tostring(sounds[key] or "")
  end

  if type(preset.sections) == "table" then
    for _, entry in ipairs(preset.sections) do
      if type(entry) == "table" and tostring(entry.match or "") ~= "" then
        out.sections[#out.sections + 1] = {
          match = tostring(entry.match),
          label = tostring(entry.label or ""),
          warn_bars = entry.warn_bars and clamp_int(entry.warn_bars, 1, 8, out.cues.warn_bars) or nil,
          chords = type(entry.chords) == "table" and entry.chords or {}
        }
      end
    end
  end
  return out
end

--------------------------------------------------------------------------------
-- per section
--------------------------------------------------------------------------------

-- Sections are matched on their name, not their position: someone who inserts
-- an intro halfway through arranging should not lose the setup for everything
-- that follows it.
local function find_entry(preset, name)
  name = tostring(name or ""):lower()
  if name == "" then return nil end
  for _, entry in ipairs(preset.sections or {}) do
    if tostring(entry.match):lower() == name then return entry end
  end
  return nil
end

Presets.find_section = find_entry

-- What actually applies to a section: its own overrides where it has them, the
-- preset's values where it does not.
function Presets.section(preset, name)
  local entry = find_entry(preset, name)
  return {
    match = tostring(name or ""),
    label = (entry and entry.label ~= "" and entry.label) or tostring(name or ""),
    warn_bars = (entry and entry.warn_bars) or preset.cues.warn_bars,
    chords = (entry and entry.chords) or {},
    overridden = entry ~= nil
  }
end

-- Passing nil for a field clears that override. An entry that overrides nothing
-- any more is dropped rather than left behind as an empty row that still claims
-- the section is special.
function Presets.set_section(preset, name, fields)
  name = tostring(name or "")
  if name == "" then return preset end
  fields = fields or {}
  local entry = find_entry(preset, name)
  if not entry then
    entry = { match = name, label = "", chords = {} }
    preset.sections[#preset.sections + 1] = entry
  end
  if fields.label ~= nil then entry.label = tostring(fields.label) end
  if fields.warn_bars ~= nil then
    entry.warn_bars = fields.warn_bars and clamp_int(fields.warn_bars, 1, 8, preset.cues.warn_bars) or nil
  end
  if fields.chords ~= nil then entry.chords = fields.chords end
  local empty = (entry.label == "" or entry.label == entry.match)
    and entry.warn_bars == nil and #(entry.chords or {}) == 0
  if empty then
    for index, candidate in ipairs(preset.sections) do
      if candidate == entry then table.remove(preset.sections, index); break end
    end
  end
  return preset
end

--------------------------------------------------------------------------------
-- the project it belongs to
--------------------------------------------------------------------------------

function Presets.load(project)
  if not r.GetProjExtState then return nil end
  local _, blob = r.GetProjExtState(project or 0, EXT_SECTION, EXT_KEY)
  if not blob or blob == "" then return nil end
  local ok, decoded = pcall(json.decode, blob)
  if not ok or type(decoded) ~= "table" then return nil end
  return Presets.normalize(decoded)
end

function Presets.save(preset, project)
  if not r.SetProjExtState then return false, "This REAPER cannot store project data" end
  local ok, blob = pcall(json.encode, Presets.normalize(preset))
  if not ok then return false, "Could not encode the preset" end
  r.SetProjExtState(project or 0, EXT_SECTION, EXT_KEY, blob)
  return true
end

-- Clearing is writing an empty string: REAPER drops the key, and the project
-- goes back to whatever the user's own defaults are.
function Presets.clear(project)
  if not r.SetProjExtState then return false end
  r.SetProjExtState(project or 0, EXT_SECTION, EXT_KEY, "")
  return true
end

--------------------------------------------------------------------------------
-- the ones you keep
--------------------------------------------------------------------------------

local function sep()
  return package.config:sub(1, 1)
end

function Presets.root()
  local base = r.GetResourcePath and r.GetResourcePath() or ""
  return base .. sep() .. "TK Cue Presets" .. sep()
end

local function sanitize(name)
  name = tostring(name or ""):gsub("[%c]", " ")
  name = name:gsub('[<>:"/\\|%?%*]', "-")
  name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("%.+$", "")
  if name == "" then name = "Cue preset" end
  return name:sub(1, 80)
end

Presets.sanitize = sanitize

function Presets.list()
  local root = Presets.root()
  local out = {}
  if not r.EnumerateFiles then return out end
  r.EnumerateFiles(root, -1)
  local index = 0
  while true do
    local filename = r.EnumerateFiles(root, index)
    if not filename then break end
    local stem = filename:match("^(.*)%" .. Presets.EXT .. "$")
    if stem then out[#out + 1] = { name = stem, path = root .. filename } end
    index = index + 1
  end
  table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
  return out
end

function Presets.export(preset, name)
  local root = Presets.root()
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(root, 0) end
  local base = sanitize(name ~= "" and name or preset.name)
  local portable = Presets.normalize(preset)
  portable.chord_source = "auto"
  local ok, blob = pcall(json.encode, portable)
  if not ok then return false, "Could not encode the preset" end
  local path = root .. base .. Presets.EXT
  local file = io.open(path, "wb")
  if not file then return false, "Could not write " .. path end
  file:write(blob)
  file:close()
  return true, path
end

function Presets.import(path)
  local file = io.open(path, "rb")
  if not file then return nil, "Could not read " .. tostring(path) end
  local body = file:read("*a")
  file:close()
  local ok, decoded = pcall(json.decode, body)
  if not ok or type(decoded) ~= "table" then return nil, "That file is not a cue preset" end
  return Presets.normalize(decoded)
end

return Presets
