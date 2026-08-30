-- Ordering for the Browser's sample list.
--
-- UI-independent and fully testable without a window: the sort takes a list of
-- paths and a way to look up a length, and hands back a new list. Nothing here
-- touches REAPER.
--
-- This deliberately does NOT reorder anything the rest of the program reads.
-- The scan order is load-bearing -- seeds pick by position, so the same seed
-- over the same pack has to build the same kit on someone else's machine. If a
-- display preference leaked into that, two people with the same seed and the
-- same samples would get different kits, and nothing on screen would explain
-- why. So this returns a copy, and only the list draws from it.

local M = {}

M.MODES = {
  { id = "name",      label = "Name" },
  { id = "length",    label = "Length" },
  { id = "transient", label = "Transient" },
  { id = "frequency", label = "Frequency" },
}

local NUMERIC_MODES = { length = true, transient = true, frequency = true }

-- A key that sorts "Kick 2" before "Kick 10".
--
-- Plain alphabetical puts 10 before 2, which in a folder of numbered samples
-- looks like the sort is broken. Each run of digits becomes a fixed-width
-- number so the comparison is by value, and the whole thing is lower-cased
-- because Windows and macOS disagree about where uppercase belongs -- and the
-- point of sorting is that it looks the same everywhere.
--
-- Runs too long to be a number are left as text: a 30-digit string is not a
-- quantity anyone is sorting by, and tonumber would turn it into a float and
-- lose the difference between two of them.
local MAX_DIGITS = 15

function M.natural_key(name)
  return (tostring(name or ""):lower():gsub("%d+", function(run)
    if #run > MAX_DIGITS then return run end
    return string.format("%0" .. MAX_DIGITS .. "d", tonumber(run))
  end))
end

local function leaf_of(path)
  local p = tostring(path or "")
  return p:match("([^/\\]+)$") or p
end
M.leaf_of = leaf_of

-- Sorts a copy of `files`.
--
-- `duration_of` is called at most once per file and may return nil for a length
-- that is not known yet -- the cache fills in the background, and a file whose
-- length has not been read cannot be placed. Those go last in BOTH directions:
-- treating "not known" as zero would park every unmeasured file at the top the
-- moment you sorted longest-first, which reads as the sort having failed.
function M.apply(files, mode, descending, value_of)
  local out = {}
  for i = 1, #(files or {}) do out[i] = files[i] end
  if mode ~= "name" and not NUMERIC_MODES[mode] then return out end

  -- Keys are worked out once per file rather than inside the comparator, which
  -- runs it O(n log n) times -- on a pack of ten thousand that is the
  -- difference between instant and a visible stall.
  local key, values = {}, {}
  for i = 1, #out do
    local f = out[i]
    key[f] = M.natural_key(leaf_of(f))
    if NUMERIC_MODES[mode] and value_of then
      values[f] = value_of(f)
    end
  end

  -- The full path is always the last tie-break. table.sort is not stable, so
  -- without it two files with the same name -- or the same length -- could
  -- swap places between frames, and the list would flicker while it sat there.
  local function fallback(a, b)
    local ka, kb = key[a], key[b]
    if ka ~= kb then return ka < kb end
    return a < b
  end

  local cmp
  if NUMERIC_MODES[mode] then
    cmp = function(a, b)
      local sa, sb = values[a], values[b]
      if sa == nil or sb == nil then
        if sa == sb then return fallback(a, b) end
        return sb == nil          -- a known length always beats an unknown one
      end
      if sa ~= sb then
        if descending then return sa > sb end
        return sa < sb
      end
      return fallback(a, b)
    end
  else
    cmp = function(a, b)
      local ka, kb = key[a], key[b]
      if ka ~= kb then
        if descending then return ka > kb end
        return ka < kb
      end
      if a ~= b then
        if descending then return a > b end
        return a < b
      end
      return false
    end
  end

  table.sort(out, cmp)
  return out
end

-- What the sort button says. Short enough to sit in a crowded toolbar, and
-- specific enough to read as a state rather than as a command -- the button
-- shows what you are looking at, not what pressing it will do.
function M.button_label(mode, descending)
  if mode == "length" then
    return descending and "Long-Short" or "Short-Long"
  end
  if mode == "transient" then
    return descending and "Hard-Soft" or "Soft-Hard"
  end
  if mode == "frequency" then
    return descending and "High-Low" or "Low-High"
  end
  return descending and "Z-A" or "A-Z"
end

return M
