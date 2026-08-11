-- Finding the rack you are pointing at.
--
-- Two things are worth pinning down here. One is that the container is found by
-- GUID rather than by index, so a plugin dropped in front of it does not
-- repoint the marker -- the same class of bug as a cached fx address, one level
-- up. The other is that the two folder walks really do differ, and differ only
-- where the plan says they do: a rack with folders nested inside it.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

-- A tiny project: tracks are strings, with tables saying who is whose parent,
-- which ones are folders, and what FX each carries.
local folders, parents, fx_guids, track_ext, selected = {}, {}, {}, {}, nil

reaper = {
  GetMediaTrackInfo_Value = function(track, key)
    if key == "I_FOLDERDEPTH" then return folders[track] and 1 or 0 end
    return 0
  end,
  GetParentTrack = function(track) return parents[track] end,
  GetSelectedTrack = function() return selected end,
  TrackFX_GetCount = function(track) return #(fx_guids[track] or {}) end,
  TrackFX_GetFXGUID = function(track, i) return (fx_guids[track] or {})[i + 1] end,
  GetSetMediaTrackInfo_String = function(track, key, value, set)
    track_ext[track] = track_ext[track] or {}
    if set then
      track_ext[track][key] = value
      return true
    end
    return true, track_ext[track][key] or ""
  end,
}

local Rack = require("core.rack")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- An ordinary rack: a folder with pads under it.
folders = { ["kit"] = true }
parents = { ["pad1"] = "kit", ["pad2"] = "kit" }

print("folder racks")
check("the folder is its own rack", Rack.folder_parent("kit") == "kit", Rack.folder_parent("kit"))
check("a pad finds its folder", Rack.folder_parent("pad1") == "kit", Rack.folder_parent("pad1"))
check("a loose track finds nothing", Rack.folder_parent("stray") == nil, Rack.folder_parent("stray"))
check("of() calls it a track rack", Rack.of("pad1").style == "tracks", Rack.of("pad1").style)
check("and hands back the parent", Rack.of("pad1").parent == "kit", Rack.of("pad1").parent)

-- Nesting. The Browser used to stop after one level while the other two views
-- walked all the way up, and that looked like a difference worth keeping. It is
-- not one: GetParentTrack returns the enclosing FOLDER, so every parent is a
-- folder and the short check can never fail where the walk would succeed. The
-- nearest enclosing folder is the answer at any depth.
print("nesting")
folders = { ["kit"] = true, ["sub"] = true }
parents = { ["sub"] = "kit", ["deep"] = "sub" }
check("a pad in a nested folder finds the inner one", Rack.folder_parent("deep") == "sub",
  Rack.folder_parent("deep"))
check("the inner folder is its own rack", Rack.folder_parent("sub") == "sub",
  Rack.folder_parent("sub"))
check("the outer folder is still itself", Rack.folder_parent("kit") == "kit",
  Rack.folder_parent("kit"))

-- Container racks.
print("container racks")
folders, parents, track_ext = {}, {}, {}
fx_guids = { ["one"] = { "{GUID-CONTAINER}", "{GUID-RS5K}" } }

check("no marker, no container", Rack.container_fx("one") == -1, Rack.container_fx("one"))
check("of() finds nothing at all", Rack.of("one") == nil, tostring(Rack.of("one")))

check("marking works", Rack.mark_container("one", 0), false)
check("and it is found again", Rack.container_fx("one") == 0, Rack.container_fx("one"))
check("of() calls it a container rack", Rack.of("one").style == "container", Rack.of("one").style)
check("with the resolved index", Rack.of("one").container == 0, Rack.of("one").container)

-- The point of using a GUID: something is inserted in front of the container
-- and the marker still finds it, at its NEW index.
fx_guids["one"] = { "{GUID-EQ}", "{GUID-CONTAINER}", "{GUID-RS5K}" }
check("an FX in front does not break the marker", Rack.container_fx("one") == 1,
  Rack.container_fx("one"))

-- And the honest failure: the user deleted the container by hand.
fx_guids["one"] = { "{GUID-EQ}" }
check("a deleted container is simply not a rack", Rack.container_fx("one") == -1,
  Rack.container_fx("one"))
check("of() says so too", Rack.of("one") == nil, tostring(Rack.of("one")))

-- A container rack sitting inside a folder is still a container rack: the
-- folder is tidying, not the rack.
print("a container rack inside a folder")
fx_guids["one"] = { "{GUID-CONTAINER}" }
Rack.mark_container("one", 0)
folders = { ["tidy"] = true }
parents = { ["one"] = "tidy" }
check("container wins over the folder", Rack.of("one").style == "container", Rack.of("one").style)

-- Selection helpers.
print("selection")
selected = "one"
check("selected() follows the selected track", Rack.selected().style == "container",
  Rack.selected().style)
selected = nil
check("nothing selected is nil", Rack.selected() == nil, tostring(Rack.selected()))
check("and so is the parent helper", Rack.selected_parent() == nil, tostring(Rack.selected_parent()))

if fail == 0 then print("\nALL CHECKS PASSED") end
TEST_FAILED = fail
