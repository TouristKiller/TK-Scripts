-- Recognising a ReaSamplOmatic instance on a track.
--
-- This used to live in two places with two different rules: the Kit Manager
-- matched the plugin name, probed FILE0 to catch renamed instances, and also
-- scanned record-input FX; the Browser matched the name and nothing else. A pad
-- whose RS5K had been renamed was therefore invisible to the Browser, which
-- responded by adding a SECOND instance beside it -- and still reported the pad
-- as filled, because loading into the fresh instance succeeded.
--
-- One rule, one place. Both views call this.

local r = reaper
local M = {}

-- Record-input FX live in their own index space.
local REC_FX_BASE = 0x1000000

local function fx_name(track, fx)
  local a, b = r.TrackFX_GetFXName(track, fx, "")
  -- Older bindings return just the name, newer ones return retval + buffer.
  if type(a) == "string" then return a end
  if a and type(b) == "string" then return b end
  return nil
end
M.fx_name = fx_name

function M.looks_like(track, fx)
  if not track or fx == nil or fx < 0 then return false end

  local name = fx_name(track, fx)
  local lower = name and name:lower() or ""
  if lower:find("reasamplomatic", 1, true) or lower:find("rs5k", 1, true) then
    return true
  end

  -- Renamed instances keep answering to FILE0, which nothing else does.
  if r.TrackFX_GetNamedConfigParm then
    local ok, path = r.TrackFX_GetNamedConfigParm(track, fx, "FILE0")
    if ok and path ~= nil then return true end
  end
  return false
end

-- Names a note on the track that carries the rack's MIDI, so the piano roll
-- reads "Kick" rather than C2. Only called with a role we actually know: with
-- no name set REAPER keeps showing the pad track's own name, which is the
-- sample filename -- a better fallback than anything we could invent.
function M.set_note_name(track, note, name)
  if not track or not name or name == "" then return false end
  if not r.SetTrackMIDINoteNameEx then return false end
  return r.SetTrackMIDINoteNameEx(0, track, math.floor(note), -1, name) == true
end

-- FX index of the first RS5K on the track, or -1. Record-input FX are searched
-- too, since a rack pad may carry its sampler there.
-- Parameter lookup by name, cached per instance.
--
-- RS5K's parameter numbers are not a promise, so they are found by name and
-- remembered. The names are matched loosely because they have been spelled
-- differently across versions, and a wrong index would set some other control
-- entirely -- pitch, or volume -- with no error to show for it.
local param_cache = {}

-- Exact name first, and only then a loose match -- because RS5K has more than
-- one parameter whose name ends in "start offset":
--
--     Sample start offset    0.000        <- a fraction of the file
--     Loop start offset      0.00 ms      <- a time
--
-- A loose search for "start offs" matches both, and today it happens to find
-- the right one only because that one is listed first. Setting the other would
-- put a fraction into a millisecond field and leave the slice where it was,
-- with nothing to show that anything went wrong.
function M.param_index(track, fx, exact, loose)
  if not track or not fx or fx < 0 then return -1 end
  if not r.TrackFX_GetNumParams or not r.TrackFX_GetParamName then return -1 end
  local key = tostring(track) .. "#" .. tostring(fx) .. "#" .. exact
  local hit = param_cache[key]
  if hit ~= nil then return hit end

  local names = {}
  local count = r.TrackFX_GetNumParams(track, fx) or 0
  for i = 0, count - 1 do
    local ok, name = r.TrackFX_GetParamName(track, fx, i, "")
    names[i] = ok and tostring(name):lower() or ""
  end

  local found = -1
  for i = 0, count - 1 do
    if names[i] == exact then found = i break end
  end
  if found < 0 and loose then
    -- The fallback still refuses anything about looping, which is the one
    -- family of names this could collide with.
    for i = 0, count - 1 do
      if names[i]:find(loose, 1, true) and not names[i]:find("loop", 1, true) then
        found = i
        break
      end
    end
  end

  param_cache[key] = found
  return found
end

-- Where in the file a pad starts and stops, as 0..1.
--
-- This is what makes slicing a loop cost nothing: the same file goes on every
-- pad and only these two numbers differ. They stay adjustable afterwards, which
-- is the point -- a loop with swing never lands on an even division, so the
-- slice has to be movable by hand after the fact.
function M.set_range(track, fx, start01, stop01)
  local a = M.param_index(track, fx, "sample start offset", "start offs")
  local b = M.param_index(track, fx, "sample end offset", "end offs")
  if a < 0 or b < 0 then return false, "this RS5K has no start/end offset parameters" end
  if not r.TrackFX_SetParamNormalized then return false, "cannot set FX parameters" end

  start01 = math.max(0, math.min(1, tonumber(start01) or 0))
  stop01 = math.max(0, math.min(1, tonumber(stop01) or 1))
  if stop01 <= start01 then return false, "the slice has no length" end

  -- End first. Moving the start past the old end would be rejected or clamped
  -- by the plugin, and the pad would come out silent.
  r.TrackFX_SetParamNormalized(track, fx, b, stop01)
  r.TrackFX_SetParamNormalized(track, fx, a, start01)
  return true
end

function M.get_range(track, fx)
  local a = M.param_index(track, fx, "sample start offset", "start offs")
  local b = M.param_index(track, fx, "sample end offset", "end offs")
  if a < 0 or b < 0 or not r.TrackFX_GetParamNormalized then return nil end
  return r.TrackFX_GetParamNormalized(track, fx, a),
         r.TrackFX_GetParamNormalized(track, fx, b)
end

function M.find(track)
  if not track then return -1 end

  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    if M.looks_like(track, i) then return i end
  end

  if r.TrackFX_GetRecCount then
    local rec_count = r.TrackFX_GetRecCount(track)
    for i = 0, rec_count - 1 do
      local fx = REC_FX_BASE + i
      if M.looks_like(track, fx) then return fx end
    end
  end
  return -1
end

return M
