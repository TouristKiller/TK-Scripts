-- Musical scales for the pitch randomizer. Pure Lua (no reaper calls).
-- Offsets are semitones relative to the lane pitch, which acts as the root.

local M = {}

M.list = {
  { id = "chromatic",   label = "Chromatic",        steps = { 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 } },
  { id = "major",       label = "Major",            steps = { 0, 2, 4, 5, 7, 9, 11 } },
  { id = "minor",       label = "Minor",            steps = { 0, 2, 3, 5, 7, 8, 10 } },
  { id = "harm_minor",  label = "Harmonic minor",   steps = { 0, 2, 3, 5, 7, 8, 11 } },
  { id = "dorian",      label = "Dorian",           steps = { 0, 2, 3, 5, 7, 9, 10 } },
  { id = "phrygian",    label = "Phrygian",         steps = { 0, 1, 3, 5, 7, 8, 10 } },
  { id = "lydian",      label = "Lydian",           steps = { 0, 2, 4, 6, 7, 9, 11 } },
  { id = "mixolydian",  label = "Mixolydian",       steps = { 0, 2, 4, 5, 7, 9, 10 } },
  { id = "penta_major", label = "Major pentatonic", steps = { 0, 2, 4, 7, 9 } },
  { id = "penta_minor", label = "Minor pentatonic", steps = { 0, 3, 5, 7, 10 } },
  { id = "blues",       label = "Blues",            steps = { 0, 3, 5, 6, 7, 10 } },
  { id = "fifths",      label = "Root + fifth",     steps = { 0, 7 } },
  { id = "octaves",     label = "Octaves only",     steps = { 0 } },
}

local by_id = {}
local sets = {}
for _, s in ipairs(M.list) do
  by_id[s.id] = s
  local set = {}
  for _, v in ipairs(s.steps) do set[v] = true end
  sets[s.id] = set
end

function M.by_id(id)
  return by_id[tostring(id or "")] or by_id.chromatic
end

function M.label(id)
  return M.by_id(id).label
end

function M.normalize(id)
  return M.by_id(id).id
end

-- Every allowed semitone offset in [-down, +up], ascending, root (0) included.
function M.offsets(scale_id, down, up)
  local set = sets[M.normalize(scale_id)]
  down = math.max(0, math.floor(tonumber(down) or 0))
  up = math.max(0, math.floor(tonumber(up) or 0))

  local out = {}
  for n = -down, up do
    if set[n % 12] then out[#out + 1] = n end
  end
  if #out == 0 then out[1] = 0 end
  return out
end

-- Index of the root (offset 0) in an offsets list, or the nearest entry.
function M.root_index(offsets)
  local best, best_d = 1, math.huge
  for i, v in ipairs(offsets) do
    local d = math.abs(v)
    if d < best_d then best, best_d = i, d end
  end
  return best
end

return M
