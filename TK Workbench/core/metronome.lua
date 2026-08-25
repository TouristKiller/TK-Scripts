-- The metronome's volume, which is two numbers and not one.
--
-- REAPER keeps a primary and a secondary click level - VOL 0.25 0.125 in the
-- project file - where the first is the accented beat (A) and the second is
-- every other beat (B, C, D). Its own settings window shows the second one as a
-- level *relative* to the first.
--
-- Writing only the first, which is what a single "Volume" slider naturally maps
-- onto, therefore does something nobody asks for: the accented beat gets
-- quieter while the other beats stay exactly where they were, and the window
-- reports their relative gain climbing. Take the primary down to 0.002 and it
-- reads +54 dB, which is what it looks like from the outside - a volume control
-- that turns three of the four beats up. Reported by a user on the forum.
--
-- So a volume control moves both and keeps the balance between them.

local r = reaper

local Metro = {}

-- The primary level. Different REAPER builds have carried different names for
-- it, so the first one that answers is the one this uses.
local PRIMARY_KEYS = { "projmetrovol", "projmetrovol1", "projmetrov1", "metronomevol" }
local SECONDARY_KEYS = { "projmetrovol2", "projmetrov2" }

local DEFAULT_BALANCE = 0.5   -- REAPER ships 0.25 / 0.125
local SENTINEL = -987654.321

local cache = { checked = false, primary = nil, secondary = nil, status = nil }
local remembered_balance = nil

local function probe(keys)
  for _, key in ipairs(keys) do
    local ok, value = pcall(r.SNM_GetDoubleConfigVar, key, SENTINEL)
    if ok and type(value) == "number" and value ~= SENTINEL then return key end
  end
  return nil
end

local function detect()
  if cache.checked then return cache.primary end
  cache.checked = true
  if not r.SNM_GetDoubleConfigVar or not r.SNM_SetDoubleConfigVar then
    cache.status = "Metronome volume needs the SWS extension"
    return nil
  end
  cache.primary = probe(PRIMARY_KEYS)
  cache.secondary = probe(SECONDARY_KEYS)
  if not cache.primary then cache.status = "Metronome volume API not found" end
  return cache.primary
end

function Metro.status()
  detect()
  return cache.status
end

function Metro.available()
  return detect() ~= nil
end

local function read(key, fallback)
  if not key then return nil end
  local ok, value = pcall(r.SNM_GetDoubleConfigVar, key, fallback or 0)
  if ok and type(value) == "number" then return value end
  return nil
end

function Metro.volume()
  local key = detect()
  if not key then return nil end
  return read(key, 1)
end

function Metro.secondary()
  detect()
  if not cache.secondary then return nil end
  return read(cache.secondary, 0)
end

-- How loud the unaccented beats are next to the accented one. Remembered across
-- a trip through zero, where the ratio cannot be worked out any more: dragging
-- the slider to silence and back must not quietly flatten the two levels into
-- one.
function Metro.balance()
  local primary, secondary = Metro.volume(), Metro.secondary()
  if primary and secondary and primary > 0.0001 then
    remembered_balance = secondary / primary
    return remembered_balance
  end
  return remembered_balance or DEFAULT_BALANCE
end

function Metro.set_volume(value, max_value)
  local key = detect()
  if not key then return false end
  local ceiling = tonumber(max_value) or 2.0
  value = math.max(0.0, math.min(ceiling, tonumber(value) or 0))
  local balance = Metro.balance()
  r.SNM_SetDoubleConfigVar(key, value)
  if cache.secondary then
    r.SNM_SetDoubleConfigVar(cache.secondary, math.max(0.0, math.min(ceiling, value * balance)))
  end
  return true
end

-- Only for a control that deliberately sets the two apart, which the plain
-- volume slider is not.
function Metro.set_balance(ratio)
  local key = detect()
  if not key or not cache.secondary then return false end
  ratio = math.max(0.0, math.min(4.0, tonumber(ratio) or DEFAULT_BALANCE))
  remembered_balance = ratio
  local primary = Metro.volume() or 0
  r.SNM_SetDoubleConfigVar(cache.secondary, primary * ratio)
  return true
end

function Metro.forget()
  cache.checked, cache.primary, cache.secondary, cache.status = false, nil, nil, nil
end

return Metro
