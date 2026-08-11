-- What a lane resolves to, and the one piece of arithmetic that is easy to get
-- wrong silently.
--
-- The container address is an expression over the whole FX chain, not an
-- identity. Every check about that here exists because the spike that proved
-- containers work was itself caught by it: it stored two addresses, added one
-- FX, and then wrote to numbers that pointed nowhere -- with no error, and a
-- cheerful report of success.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

-- The FX chain this fake track is pretending to have.
local top_level_count = 1
local rs5k_on_track = {}

-- The fake track's chain: the container's GUID sits at index `container_index`,
-- and `container_children` is what is inside it, in order.
local container_index = 0
local container_children = { "{PAD-A}", "{PAD-B}" }

local function child_addr(j)
  return 0x2000000 + (container_index + 1) + (top_level_count + 1) * j
end

reaper = {
  TrackFX_GetCount = function() return top_level_count end,
  TrackFX_GetFXGUID = function(_, addr)
    if addr < 0x2000000 then
      return addr == container_index and "{GUID-CONTAINER}" or ("{GUID-TOP-" .. addr .. "}")
    end
    for j = 1, #container_children do
      if child_addr(j) == addr then return container_children[j] end
    end
    return nil
  end,
  TrackFX_GetNamedConfigParm = function(_, _, key)
    if key == "container_count" then return true, tostring(#container_children) end
    return false, ""
  end,
}

-- core.lane asks core.rs5k where the sampler is; stub it so the test is about
-- lanes rather than about plugin detection.
package.loaded["core.rs5k"] = {
  find = function(track) return rs5k_on_track[track] or -1 end,
}

local Lane = require("core.lane")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- 1. The address formula, against the numbers the real spike came back with.
--    Container at index 0. With one top-level FX (the container alone) the
--    children sit at 0x2000003 and 0x2000005; adding one more top-level FX
--    moves them to 0x2000004 and 0x2000007. Both were observed in REAPER 7.75.
print("container child addresses")
local TRACK = "fake-track"

top_level_count = 1
local a1 = Lane.container_child_address(TRACK, 0, 1)
local a2 = Lane.container_child_address(TRACK, 0, 2)
print(string.format("  1 top-level FX : 0x%X  0x%X", a1, a2))
check("child 1 with one top-level FX", a1 == 0x2000003, string.format("0x%X", a1))
check("child 2 with one top-level FX", a2 == 0x2000005, string.format("0x%X", a2))

top_level_count = 2
local b1 = Lane.container_child_address(TRACK, 0, 1)
local b2 = Lane.container_child_address(TRACK, 0, 2)
print(string.format("  2 top-level FX : 0x%X  0x%X", b1, b2))
check("child 1 with two top-level FX", b1 == 0x2000004, string.format("0x%X", b1))
check("child 2 with two top-level FX", b2 == 0x2000007, string.format("0x%X", b2))

-- 2. The whole point: the SAME lane gives a DIFFERENT address once the chain
--    around it changes. This is what makes caching one a bug.
check("the address moves when the chain does", a1 ~= b1,
  string.format("0x%X vs 0x%X", a1, b1))
check("and it moves for every child", a2 ~= b2,
  string.format("0x%X vs 0x%X", a2, b2))

-- 3. Track-style lanes: one track per pad, sampler found on the track.
print("track-style lanes")
rs5k_on_track = { ["kick-track"] = 0, ["snare-track"] = 3 }
local lanes = Lane.track_rack({ "kick-track", "snare-track" }, "parent")
check("style is tracks", Lane.style(lanes) == "tracks", Lane.style(lanes))
check("length is untouched by the rack field", #lanes == 2, #lanes)
check("lane 1 resolves to its own RS5K", Lane.fx(lanes, 1) == 0, Lane.fx(lanes, 1))
check("lane 2 resolves to its own RS5K", Lane.fx(lanes, 2) == 3, Lane.fx(lanes, 2))
local t, fx = Lane.resolve(lanes, 2)
check("resolve gives both halves", t == "snare-track" and fx == 3, tostring(t) .. "/" .. tostring(fx))

-- A pad with no sampler is -1, which is what every caller already tests for.
rs5k_on_track = {}
check("no sampler is -1", Lane.fx(lanes, 1) == -1, Lane.fx(lanes, 1))

-- 4. Container-style lanes: one track, a pad per child. Every entry is the same
--    track -- that is what lets the existing #lanes / lanes[i] code stay as it
--    is -- and the pads are told apart by the fx address, not by the track.
print("container-style lanes")
top_level_count = 1
local clanes = Lane.container_rack(TRACK, "{GUID-CONTAINER}", nil, 16)
check("style is container", Lane.style(clanes) == "container", Lane.style(clanes))
check("sixteen lanes", #clanes == 16, #clanes)
check("every lane is the same track", clanes[1] == clanes[16], tostring(clanes[16]))
check("but each has its own address", Lane.fx(clanes, 1) ~= Lane.fx(clanes, 2),
  Lane.fx(clanes, 1))
check("lane 1 matches the formula", Lane.fx(clanes, 1) == 0x2000003,
  string.format("0x%X", Lane.fx(clanes, 1)))

-- 4b. The reason the container is remembered by GUID and not by index.
--
-- The sequencer inserts its engine JSFX at the TOP of this same chain so its
-- MIDI reaches the pads. That pushes the container from index 0 to index 1 and
-- changes every child address with it. A lane set built before that moment must
-- still land on the right pads afterwards -- if it stored the index, all
-- sixteen would quietly address nothing.
print("the container moves under a live lane set")
container_index = 1
top_level_count = 2
check("lane 1 follows the container", Lane.fx(clanes, 1) == 0x2000005,
  string.format("0x%X", Lane.fx(clanes, 1)))
check("lane 2 as well", Lane.fx(clanes, 2) == 0x2000008,
  string.format("0x%X", Lane.fx(clanes, 2)))

-- And when the container is gone entirely, a lane is simply empty.
container_index = -1
check("a vanished container gives -1", Lane.fx(clanes, 1) == -1, Lane.fx(clanes, 1))
container_index = 0
top_level_count = 1

-- 4d. A pad is a plugin, not a position.
--
-- Without a recorded order, pad N is child N -- and dropping an FX inside the
-- container makes every pad address its neighbour. Silently: an address that
-- resolves to the wrong plugin looks exactly like one that resolves to the
-- right plugin. So the rack writes down which plugin each pad is, and the
-- position is only a hint.
print("pads follow their plugin, not their slot")
top_level_count = 1
container_index = 0
container_children = { "{PAD-A}", "{PAD-B}", "{PAD-C}" }
local order = { "{PAD-A}", "{PAD-B}", "{PAD-C}" }
local plt = Lane.container_rack(TRACK, "{GUID-CONTAINER}", order, 3)

check("undisturbed, pad 1 is child 1", Lane.fx(plt, 1) == child_addr(1),
  string.format("0x%X", Lane.fx(plt, 1)))
check("and pad 3 is child 3", Lane.fx(plt, 3) == child_addr(3),
  string.format("0x%X", Lane.fx(plt, 3)))

-- Somebody drops an EQ in at the top of the container. Every pad has moved
-- down one; none of them has changed identity.
container_children = { "{SOME-EQ}", "{PAD-A}", "{PAD-B}", "{PAD-C}" }
check("pad 1 follows its plugin", Lane.fx(plt, 1) == child_addr(2),
  string.format("0x%X", Lane.fx(plt, 1)))
check("pad 2 as well", Lane.fx(plt, 2) == child_addr(3),
  string.format("0x%X", Lane.fx(plt, 2)))
check("and pad 3", Lane.fx(plt, 3) == child_addr(4),
  string.format("0x%X", Lane.fx(plt, 3)))
check("nobody addresses the EQ",
  Lane.fx(plt, 1) ~= child_addr(1) and Lane.fx(plt, 2) ~= child_addr(1),
  "an EQ got played")

-- A pad whose plugin is gone is an empty pad, not the next one along.
container_children = { "{PAD-A}", "{PAD-C}" }
check("a deleted pad is -1, not its neighbour", Lane.fx(plt, 2) == -1, Lane.fx(plt, 2))
check("the survivors still resolve", Lane.fx(plt, 1) == child_addr(1), Lane.fx(plt, 1))
check("and pad 3 is found where it now sits", Lane.fx(plt, 3) == child_addr(2),
  string.format("0x%X", Lane.fx(plt, 3)))

-- A rack built before the order was recorded has only its position, which is
-- what every container rack had until now.
local legacy = Lane.container_rack(TRACK, "{GUID-CONTAINER}", nil, 3)
container_children = { "{PAD-A}", "{PAD-B}", "{PAD-C}" }
check("no recorded order falls back to position", Lane.fx(legacy, 2) == child_addr(2),
  string.format("0x%X", Lane.fx(legacy, 2)))

top_level_count = 1
container_index = 0
container_children = { "{PAD-A}", "{PAD-B}" }

-- 4c. Notes on one lane must not touch at the same pitch.
--
-- The engine strikes the sampler again for every hit -- note-off, then note-on.
-- Two note rectangles of the same pitch that touch cannot do that: the second
-- is swallowed. Four kicks came out as one long note, and a swung double kick
-- came out as one kick, both for this reason.
print("separating notes")
local function ev(s, e, pitch) return { start_steps = s, end_steps = e, pitch = pitch or 36 } end
local GAP = 1 / 64

-- Touching exactly: gate 100% over a length of one.
local touching = Lane.separate_notes({ ev(0, 1), ev(1, 2), ev(2, 3) }, GAP)
check("the first ends before the second starts", touching[1].end_steps < touching[2].start_steps,
  touching[1].end_steps)
check("and the second before the third", touching[2].end_steps < touching[3].start_steps,
  touching[2].end_steps)
check("the last one is left alone", touching[3].end_steps == 3, touching[3].end_steps)
check("starts are never moved", touching[1].start_steps == 0 and touching[2].start_steps == 1,
  touching[2].start_steps)

-- Overlapping: a groove pulled the second note early, into the first.
local swung = Lane.separate_notes({ ev(0, 1), ev(0.75, 1.75) }, GAP)
check("an overlap is removed", swung[1].end_steps < swung[2].start_steps, swung[1].end_steps)
check("the swing itself is kept", swung[2].start_steps == 0.75, swung[2].start_steps)

-- Different pitches do not fight, so they are not shortened.
local two_pitches = Lane.separate_notes({ ev(0, 2, 36), ev(1, 3, 38) }, GAP)
check("a different pitch is not clamped", two_pitches[1].end_steps == 2, two_pitches[1].end_steps)

-- Stitched end to end, as the one-shot path builds them.
local stitched = Lane.separate_notes({ ev(0, 4), ev(4, 8), ev(8, 16) }, GAP)
check("stitched notes come apart", stitched[1].end_steps < 4 and stitched[2].end_steps < 8,
  stitched[2].end_steps)

-- Out of order in, sorted out -- echoes are appended after the step they follow.
local unsorted = Lane.separate_notes({ ev(2, 3), ev(0, 1), ev(1, 2) }, GAP)
check("sorted by start", unsorted[1].start_steps == 0 and unsorted[3].start_steps == 2,
  unsorted[1].start_steps)

-- Degenerate: two hits on the same tick must still leave a playable note.
local same = Lane.separate_notes({ ev(1, 2), ev(1, 2) }, GAP)
check("no zero-length notes", same[1].end_steps > same[1].start_steps, same[1].end_steps)

-- Nothing to do, and nothing thrown.
check("one note is untouched", Lane.separate_notes({ ev(0, 1) }, GAP)[1].end_steps == 1, "changed")
check("an empty list survives", #Lane.separate_notes({}, GAP) == 0, "not empty")

-- 5. Nothing here may throw on a rack that is half built or already gone.
print("missing things")
check("no lanes at all", Lane.fx(nil, 1) == -1, Lane.fx(nil, 1))
check("index past the end", Lane.fx(lanes, 99) == -1, Lane.fx(lanes, 99))
check("no index", Lane.fx(lanes, nil) == -1, Lane.fx(lanes, nil))
local mt, mfx = Lane.resolve(lanes, 99)
check("resolve past the end", mt == nil and mfx == -1, tostring(mt))
check("an untagged array still reads as tracks", Lane.style({}) == "tracks", Lane.style({}))

if fail == 0 then print("\nALL CHECKS PASSED") end
TEST_FAILED = fail
