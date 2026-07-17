-- Builds export filenames and converts MIDI note numbers to note names.

local M = {}

local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

-- MIDI note 36 -> "C1" (matches the architecture doc's default: note 36 = C1).
function M.note_name(midi_note)
  midi_note = math.floor(midi_note)
  local name = NOTE_NAMES[(midi_note % 12) + 1]
  local octave = math.floor(midi_note / 12) - 2
  return name .. tostring(octave)
end

local function pad_number(n, style)
  if style == "1" then return tostring(n) end
  if style == "01" then return string.format("%02d", n) end
  return string.format("%03d", n) -- "001" default
end

local function file_stub(path)
  local name = path:match("([^/\\]+)$") or path
  return (name:gsub("%.[%w]+$", ""))
end

local function file_ext(path)
  return path:match("%.([%w]+)$") or "wav"
end

-- slot: Slot table, sample_path: source file path, pool: the Slot's Pool
-- (may be nil), naming_opts: KitDef.naming table.
function M.build(slot, sample_path, pool, naming_opts)
  naming_opts = naming_opts or {}
  local parts = {}
  parts[#parts + 1] = pad_number(slot.number, naming_opts.prefix_style or "001")

  if naming_opts.include_type then
    -- Both the pool alias / explosion name and the slot filter label ("Kick")
    -- go into the filename, deduped when they are the same word.
    local alias = pool and pool.alias
    local type_label = slot.type_label
    if alias and alias ~= "" then
      parts[#parts + 1] = alias
    end
    if type_label and type_label ~= ""
      and (not alias or alias:lower() ~= type_label:lower()) then
      parts[#parts + 1] = type_label
    end
  end

  if naming_opts.note_style == "name" then
    parts[#parts + 1] = M.note_name(slot.midi_note)
  elseif naming_opts.note_style == "number" then
    parts[#parts + 1] = tostring(slot.midi_note)
  end

  parts[#parts + 1] = file_stub(sample_path)

  local sep = naming_opts.separator or "_"
  return table.concat(parts, sep) .. "." .. file_ext(sample_path)
end

return M
