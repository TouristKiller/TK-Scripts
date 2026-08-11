-- What a lane IS, in one place.
--
-- A lane is a pad: a sampler, and somewhere for its MIDI to arrive. Today that
-- is one track per pad under a folder, and the code says so everywhere -- about
-- a hundred places in ui/sequencer_view.lua alone read a lane as a track and
-- then go looking for the RS5K on it:
--
--     local lane_track = lane_tracks[lane]
--     local lane_fx = lane_track and find_rs5k_fx(lane_track) or -1
--     set_rs5k_volume_db(lane_track, lane_fx, db)
--
-- That is not really a track dependency. It is a (track, fx) pair with a lookup
-- in the middle, and core/rs5k.lua already speaks exactly that language. This
-- module is that lookup, named and kept in one place -- so a rack whose pads are
-- sixteen FX inside one container is a change here rather than a change there.
--
-- Nothing about containers is switched on yet. The arithmetic is here and
-- tested because it is the part that is easy to get wrong quietly, and because
-- having it written down is what makes the next step small.
--
-- ---------------------------------------------------------------------------
-- THE RULE THAT MATTERS: an fx index is never stored.
--
-- Ask for it, use it, drop it. In a container the index is not an identity at
-- all -- it is an expression over the track's whole FX chain, and it moves the
-- moment anything is added to or removed from that chain. A cached one still
-- looks like a number; it just points somewhere else, silently.
--
-- That is not a hypothetical. The spike that proved containers work was itself
-- caught by it: it worked out two child addresses, added one more FX to the
-- track, wrote to the stored addresses, and reported success while both writes
-- had gone nowhere. If a probe of forty lines can be fooled, so can a rack of
-- sixteen pads -- so this module hands out fx indices and never keeps one, and
-- callers should do the same.
-- ---------------------------------------------------------------------------

local r = reaper
local RS5K = require("core.rs5k")

local M = {}

-- REAPER addresses an FX inside a container with this base plus an offset
-- worked out from the chain around it.
M.CONTAINER_BASE = 0x2000000

-- The address of child `child_index` (1-based) of a top-level container.
--
--     base + (container_index + 1) + (top_level_count + 1) * child_index
--
-- The top-level count is read live, every call, and deliberately not passed in:
-- a caller holding a stale one is exactly the bug this exists to prevent, so
-- there is no way to supply it.
function M.container_child_address(track, container_fx, child_index)
  if not track or not container_fx or not child_index then return -1 end
  local top = r.TrackFX_GetCount and r.TrackFX_GetCount(track) or 0
  return M.CONTAINER_BASE + (container_fx + 1) + (top + 1) * child_index
end

-- Where a plugin is now, given the one thing about it that does not move.
--
-- An FX GUID is issued once and stays with the plugin; its index is a position
-- and positions shift whenever the chain changes. Anything that has to survive
-- a chain edit is written down as a GUID and turned back into an index here, on
-- use.
function M.fx_index_by_guid(track, guid)
  if not track or not guid or guid == "" or not r.TrackFX_GetFXGUID then return -1 end
  local count = r.TrackFX_GetCount and r.TrackFX_GetCount(track) or 0
  for i = 0, count - 1 do
    if r.TrackFX_GetFXGUID(track, i) == guid then return i end
  end
  return -1
end

-- How many FX a container holds.
function M.container_count(track, container_fx)
  if not track or not container_fx or not r.TrackFX_GetNamedConfigParm then return 0 end
  local ok, v = r.TrackFX_GetNamedConfigParm(track, M.CONTAINER_BASE + container_fx + 1, "container_count")
  if not ok then return 0 end
  return math.floor(tonumber(v) or 0)
end

-- ---------------------------------------------------------------------------
-- Lane sets
--
-- A lane set is an ARRAY of tracks, indexed by lane, exactly as
-- collect_lane_tracks has always returned -- so every `#lanes` and `lanes[i]`
-- already in the program keeps working untouched. What is new is a `rack` field
-- beside them saying how to find the sampler, which is the one question that
-- differs between the two shapes.
--
-- In container style every entry is the SAME track, because it is: sixteen pads
-- on one track. That is what lets the iteration code stay as it is.
-- ---------------------------------------------------------------------------

-- Today's rack: one track per pad.
function M.track_rack(tracks, parent)
  tracks = tracks or {}
  tracks.rack = { style = "tracks", parent = parent }
  return tracks
end

-- Tomorrow's: one track, one container, a pad per child.
--
-- The container is remembered by GUID rather than by index, and that is not
-- belt and braces. The sequencer puts its engine JSFX at the TOP of this same
-- chain so its MIDI reaches the pads -- which moves the container down one and
-- changes every child address with it. A lane set built a moment earlier would
-- still hold the old index and would quietly address nothing at all.
-- `pad_guids` is the rack's own record of which plugin is which pad, in pad
-- order. Optional: a rack built before that was recorded falls back to position,
-- which is what it has always done.
function M.container_rack(track, container_guid, pad_guids, count)
  local lanes = {
    rack = { style = "container", track = track, guid = container_guid, pads = pad_guids },
  }
  for i = 1, math.max(0, math.floor(tonumber(count) or 0)) do
    lanes[i] = track
  end
  return lanes
end

function M.style(lanes)
  local rack = lanes and lanes.rack
  return (rack and rack.style) or "tracks"
end

-- The sampler for lane `index`, resolved now. -1 when there is not one.
function M.fx(lanes, index)
  if not lanes or not index then return -1 end
  local track = lanes[index]
  if not track then return -1 end

  local rack = lanes.rack
  if rack and rack.style == "container" then
    -- Both halves resolved here and neither kept: where the container is now,
    -- and where its child sits given the chain as it is now.
    local ci = M.fx_index_by_guid(track, rack.guid)
    if ci < 0 then return -1 end

    local want = rack.pads and rack.pads[index]
    local addr = M.container_child_address(track, ci, index)
    if not want or want == "" or not r.TrackFX_GetFXGUID then
      -- No record of which plugin this pad is. A rack built before the order
      -- was written down has only its position to go on, which is what every
      -- container rack used until now.
      return addr
    end

    -- Position is a hint, the GUID is the answer. Pad N is child N in a rack
    -- nobody has rearranged, so the hint is right almost always and this costs
    -- one read. When it is wrong -- an FX added inside the container, a pad
    -- moved or replaced -- every pad after it has shifted, and following the
    -- position would silently address the neighbour.
    if r.TrackFX_GetFXGUID(track, addr) == want then return addr end

    for j = 1, M.container_count(track, ci) do
      local a = M.container_child_address(track, ci, j)
      if r.TrackFX_GetFXGUID(track, a) == want then return a end
    end
    -- The plugin this pad was is gone. An empty pad, not someone else's.
    return -1
  end
  return RS5K.find(track)
end

-- ---------------------------------------------------------------------------
-- Notes on one lane must not touch at the same pitch
-- ---------------------------------------------------------------------------

-- Shortens every note so it ends a hair before the next note of the SAME pitch
-- begins. Returns the same list, sorted by start.
--
-- Playback and export articulate a repeated hit in two different ways, and only
-- one of them works. The engine sends a note-off and then a note-on for every
-- hit (see trigger_lane_note), so the sampler is struck again each time. The
-- export writes note rectangles into an item, and two rectangles of the same
-- pitch that touch cannot both be struck: the note-off of the first lands on or
-- after the note-on of the second, and the second is swallowed.
--
-- The export made touching notes in three different ways -- a gate of 100% over
-- a length of one fills its step exactly and meets the next; a groove that
-- pulls a note early makes it start inside the one before it; and the one-shot
-- path stitches every note to the start of the next by design. All three came
-- out as one long note or one missing hit, and all three are this one rule.
--
-- Only notes of the same pitch are compared. A lane whose steps carry pitch
-- offsets plays different notes, and those do not fight.
--
-- It lives here rather than in the sequencer because it is arithmetic over a
-- list and can be tested; ui/sequencer_view.lua cannot even be loaded without
-- ReaImGui, and it sits exactly on Lua's 200-local ceiling so it cannot afford
-- to require a module of its own for it.
function M.separate_notes(events, gap)
  if type(events) ~= "table" or #events < 2 then return events end
  local g = tonumber(gap) or 0
  if g <= 0 then return events end

  table.sort(events, function(a, b)
    if a.start_steps == b.start_steps then
      return (a.pitch or 0) < (b.pitch or 0)
    end
    return a.start_steps < b.start_steps
  end)

  -- Backwards, remembering where the next note of each pitch begins. One pass,
  -- and no need to search ahead for the neighbour that matters.
  local next_start = {}
  for i = #events, 1, -1 do
    local ev = events[i]
    local pitch = ev.pitch or 0
    local nxt = next_start[pitch]
    if nxt and ev.end_steps and ev.end_steps > (nxt - g) then
      ev.end_steps = nxt - g
    end
    -- Never leave a note with no length at all: two hits landing on the same
    -- tick is degenerate, but a zero-length note is worse than a short one.
    if ev.end_steps and ev.end_steps <= ev.start_steps then
      ev.end_steps = ev.start_steps + (g * 0.5)
    end
    next_start[pitch] = ev.start_steps
  end
  return events
end

-- Both halves at once, which is how nearly every caller wants them.
function M.resolve(lanes, index)
  local track = lanes and lanes[index] or nil
  if not track then return nil, -1 end
  return track, M.fx(lanes, index)
end

return M
