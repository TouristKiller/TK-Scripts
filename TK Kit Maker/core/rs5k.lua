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
