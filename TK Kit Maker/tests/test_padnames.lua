-- Pad names in a container rack, and the one rule that makes them bearable:
-- a name you typed survives the next sample, a name nobody touched follows it.
--
-- That rule already exists for folder racks in maybe_auto_name_pad_track. This
-- checks the container version behaves the same way, because a pad that quietly
-- renamed itself back would be the kind of bug nobody reports and everybody
-- works around.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

local track_ext = {}

reaper = {
  GetSetMediaTrackInfo_String = function(track, key, value, set)
    track_ext[track] = track_ext[track] or {}
    if set then
      track_ext[track][key] = value
      return true
    end
    return true, track_ext[track][key] or ""
  end,
}

local Pads = require("core.padnames")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local TRACK = "rack-track"
local A, B = "{GUID-A}", "{GUID-B}"

-- 1. Nothing stored yet.
print("empty")
check("an unknown pad has no name", Pads.get(TRACK, A) == "", Pads.get(TRACK, A))
check("and no guid is not a name either", Pads.get(TRACK, "") == "", Pads.get(TRACK, ""))

-- 2. A derived name is taken when there is nothing there.
print("derived names")
check("first suggestion is taken", Pads.suggest(TRACK, A, "kick_909"), false)
check("and is what shows", Pads.get(TRACK, A) == "kick_909", Pads.get(TRACK, A))

-- Loading another sample renames it, because nobody has claimed it.
check("a later suggestion replaces it", Pads.suggest(TRACK, A, "kick_808"), false)
check("the pad follows the sample", Pads.get(TRACK, A) == "kick_808", Pads.get(TRACK, A))

-- 3. The rule that matters: once you type a name, samples stop renaming it.
print("a name you typed")
Pads.set(TRACK, A, "Kick")
check("the typed name shows", Pads.get(TRACK, A) == "Kick", Pads.get(TRACK, A))
check("a suggestion is refused", Pads.suggest(TRACK, A, "kick_606") == false, true)
check("and the typed name survives", Pads.get(TRACK, A) == "Kick", Pads.get(TRACK, A))

-- Clearing it hands the pad back to the samples.
Pads.set(TRACK, A, "")
check("clearing removes the name", Pads.get(TRACK, A) == "", Pads.get(TRACK, A))
check("and suggestions work again", Pads.suggest(TRACK, A, "kick_606"), false)
check("with the new name", Pads.get(TRACK, A) == "kick_606", Pads.get(TRACK, A))

-- 4. Pads are independent, and keyed by GUID -- so reordering the container,
--    which changes every pad's position but no pad's GUID, renames nothing.
print("pads are independent")
Pads.set(TRACK, B, "Snare")
check("pad A is untouched", Pads.get(TRACK, A) == "kick_606", Pads.get(TRACK, A))
check("pad B has its own", Pads.get(TRACK, B) == "Snare", Pads.get(TRACK, B))

-- 5. Pruning: a pad that no longer exists loses its entry, the rest do not.
print("pruning")
check("pruning reports a change", Pads.prune(TRACK, { A }), false)
check("the missing pad is gone", Pads.get(TRACK, B) == "", Pads.get(TRACK, B))
check("the live one is kept", Pads.get(TRACK, A) == "kick_606", Pads.get(TRACK, A))
check("pruning again changes nothing", Pads.prune(TRACK, { A }) == false, true)

-- 6. A blob that is damaged or written by something else must not throw, and
--    must not be able to smuggle a table in where a string belongs.
print("a damaged blob")
track_ext[TRACK][Pads.KEY] = "this is not json"
check("garbage reads as empty", next(Pads.load(TRACK)) == nil, "not empty")
check("and get() survives it", Pads.get(TRACK, A) == "", Pads.get(TRACK, A))

track_ext[TRACK][Pads.KEY] = '{"{GUID-C}":{"name":{"nested":1},"auto":"x"}}'
check("a non-string name is dropped", Pads.get(TRACK, "{GUID-C}") == "", Pads.get(TRACK, "{GUID-C}"))

if fail == 0 then print("\nALL CHECKS PASSED") end
TEST_FAILED = fail
