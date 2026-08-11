-- Building a container rack.
--
-- The interesting part is not the happy path. It is that adding an FX at an
-- address REAPER does not understand can SUCCEED at the wrong place -- landing
-- on the track instead of inside the container and returning a valid index for
-- it. The spike behind this feature was fooled exactly that way and reported
-- success while both its writes had gone nowhere.
--
-- So the fake REAPER below is deliberately as forgiving as the real one: an
-- unrecognised container address appends to the track rather than failing. If
-- build_container ever stops checking, this test fails.
--
-- The address arithmetic itself is not re-derived here -- test_lane.lua checks
-- it against the numbers REAPER 7.75 actually returned. This checks the build
-- sequence and what it does when the ground moves.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

local BASE = 0x2000000

local tracks, track_ext, params = {}, {}, {}
local guid_n = 0
local refuse_container = false
local sabotage_pad = nil   -- pad number whose insert should miss the container

local function new_guid()
  guid_n = guid_n + 1
  return string.format("{GUID-%03d}", guid_n)
end

local function fx_of(track)
  tracks[track] = tracks[track] or { top = {} }
  return tracks[track]
end

-- The same expression core/lane.lua uses. Mirrored rather than imported so the
-- stub is a model of REAPER, not a restatement of the code under test.
local function child_addr(track, ci, j)
  return BASE + (ci + 1) + (#fx_of(track).top + 1) * j
end

local function find_child_slot(track, addr)
  local t = fx_of(track)
  for i, fx in ipairs(t.top) do
    if fx.children then
      local ci = i - 1
      for j = 1, #fx.children + 1 do
        if child_addr(track, ci, j) == addr then return fx, j end
      end
    end
  end
  return nil
end

local function fx_at(track, addr)
  local t = fx_of(track)
  if addr < BASE then return t.top[addr + 1] end
  for i, fx in ipairs(t.top) do
    if fx.children then
      local ci = i - 1
      for j = 1, #fx.children do
        if child_addr(track, ci, j) == addr then return fx.children[j] end
      end
    end
  end
  return nil
end

reaper = {
  CountTracks = function() return #tracks end,
  GetTrack = function(_, i) return "track" .. i end,
  InsertTrackAtIndex = function(i) tracks["track" .. i] = { top = {} } tracks[#tracks + 1] = true end,
  GetMediaTrackInfo_Value = function() return 0 end,
  GetSetMediaTrackInfo_String = function(track, key, value, set)
    track_ext[track] = track_ext[track] or {}
    if set then track_ext[track][key] = value return true end
    return true, track_ext[track][key] or ""
  end,
  TrackFX_GetCount = function(track) return #fx_of(track).top end,
  TrackFX_GetFXGUID = function(track, addr)
    local fx = fx_at(track, addr)
    return fx and fx.guid or nil
  end,
  TrackFX_SetParamNormalized = function(track, addr, p, v)
    params[track] = params[track] or {}
    params[track][tostring(addr) .. "#" .. p] = v
  end,
  TrackFX_GetNamedConfigParm = function(track, addr, key)
    if key == "container_count" then
      -- addr is BASE + ci + 1
      local ci = addr - BASE - 1
      local fx = fx_of(track).top[ci + 1]
      if fx and fx.children then return true, tostring(#fx.children) end
      return false, ""
    end
    if key == "fx_type" then
      local fx = fx_at(track, addr)
      return true, (fx and fx.children) and "Container" or "VST"
    end
    return false, ""
  end,
  TrackFX_AddByName = function(track, name, _, pos)
    local t = fx_of(track)
    if name == "Container" then
      if refuse_container then return -1 end
      t.top[#t.top + 1] = { name = "Container", guid = new_guid(), children = {} }
      return #t.top - 1
    end
    if pos == -1 then
      t.top[#t.top + 1] = { name = name, guid = new_guid() }
      return #t.top - 1
    end
    -- an insert position: -1000 - address
    local addr = -1000 - pos
    local container, slot = find_child_slot(track, addr)
    if container and slot and (sabotage_pad == nil or slot ~= sabotage_pad) then
      container.children[slot] = { name = name, guid = new_guid() }
      return 0
    end
    -- REAPER's forgiving behaviour, and the whole reason for the checks:
    -- it lands on the track and still reports a valid index.
    t.top[#t.top + 1] = { name = name, guid = new_guid() }
    return #t.top - 1
  end,
}

local Rack = require("core.rack")
local Lane = require("core.lane")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function reset()
  tracks, track_ext, params = {}, {}, {}
  guid_n = 0
  refuse_container = false
  sabotage_pad = nil
end

-- 1. The happy path.
print("building a 16-pad container rack")
reset()
local track, ci = Rack.build_container({ name = "Test Kit", pads = 16, base_note = 36 })
check("a track came back", track ~= nil, tostring(track))
check("and a container index", ci == 0, tostring(ci))
check("the track is named", track_ext[track]["P_NAME"] == "Test Kit", track_ext[track]["P_NAME"])
check("sixteen pads went in", Lane.container_count(track, ci) == 16, Lane.container_count(track, ci))
check("and nothing landed on the track", reaper.TrackFX_GetCount(track) == 1,
  reaper.TrackFX_GetCount(track))

-- The marker, and that it resolves back to the container.
check("the rack marker is written", track_ext[track][Rack.MARKER] ~= "", "empty")
check("and finds the container again", Rack.container_fx(track) == 0, Rack.container_fx(track))
check("of() calls it a container rack", Rack.of(track).style == "container", Rack.of(track).style)

-- Notes: one per pad, ascending from base_note, on both range parameters.
local a1 = Lane.container_child_address(track, ci, 1)
local a16 = Lane.container_child_address(track, ci, 16)
check("pad 1 sits on note 36", math.abs(params[track][a1 .. "#3"] - 36 / 127) < 1e-9,
  params[track][a1 .. "#3"])
check("its range is closed on itself", params[track][a1 .. "#3"] == params[track][a1 .. "#4"],
  params[track][a1 .. "#4"])
check("pad 16 sits on note 51", math.abs(params[track][a16 .. "#3"] - 51 / 127) < 1e-9,
  params[track][a16 .. "#3"])

-- 2. Pad GUIDs, which is what pad names hang off.
print("pad guids")
local guids = Rack.pad_guids(track, ci)
check("one per pad", #guids == 16, #guids)
check("all distinct", guids[1] ~= guids[2], guids[1])
check("and they are real", type(guids[1]) == "string" and guids[1] ~= "", tostring(guids[1]))

-- 2b. The pad order is written down while the rack is still exactly as it was
--     built -- the one moment position and identity are certainly the same
--     thing. Without it a pad is only "the Nth child", and an FX dropped into
--     the container makes every pad address its neighbour.
print("recorded pad order")
local order = Rack.pad_order(track)
check("one entry per pad", #order == 16, #order)
check("in pad order", order[1] == guids[1] and order[16] == guids[16], tostring(order[1]))
check("and they are real guids", type(order[8]) == "string" and order[8] ~= "", tostring(order[8]))

-- A track that was never built as a container rack has no order, and callers
-- read that as "fall back to position".
check("an unbuilt track has none", #Rack.pad_order("track-nowhere") == 0,
  #Rack.pad_order("track-nowhere"))

-- 3. No container available: refuse, do not half-build.
print("when the container cannot be made")
reset()
refuse_container = true
local t2, err = Rack.build_container({ name = "Nope", pads = 4 })
check("nothing comes back", t2 == nil, tostring(t2))
check("with a reason", type(err) == "string" and err ~= "", tostring(err))

-- 4. The failure this exists for: a pad lands on the track instead of in the
--    container. The build must notice and stop, not carry on and report a rack.
print("when a pad misses the container")
reset()
sabotage_pad = 3
local t3, err3 = Rack.build_container({ name = "Broken", pads = 8 })
check("the build refuses", t3 == nil, tostring(t3))
check("and says which pad", type(err3) == "string" and err3:find("3", 1, true) ~= nil, tostring(err3))

if fail == 0 then print("\nALL CHECKS PASSED") end
TEST_FAILED = fail
