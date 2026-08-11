-- Taking a slot number off a name before Save kit puts a fresh one on.
--
-- Saving a kit twice used to give 010_010_Cymbal, and a sample dragged in from
-- another kit arrived as 010_013_Cymbal. Both are technically correct and both
-- are ugly.
--
-- The trap is that plenty of drum samples begin with a number that is not a
-- slot at all -- 808, 909, 606, 707 -- and stripping those would be a worse bug
-- than the one being fixed. The test is whether the number could have been one
-- of ours: Save kit writes slots 1..16, so anything above that was never a
-- prefix.
--
-- Mirrors strip_slot_prefix in ui/rs5k_manager_view.lua, which cannot be
-- required here: that file needs ReaImGui to load.

local GRID_SLOTS = 16

local function strip_slot_prefix(name)
  local digits, rest = tostring(name or ""):match("^(%d+)_(.*)$")
  if not digits or rest == "" then return name end
  local n = tonumber(digits)
  if not n or n < 1 or n > GRID_SLOTS then return name end
  return rest
end

local fail = 0
local function check(label, got, want)
  if got ~= want then
    fail = fail + 1
    print(string.format("FAIL: %s  (got %q, wanted %q)", label, tostring(got), tostring(want)))
  end
end

print("prefixes this kit wrote")
check("a saved kit's own prefix", strip_slot_prefix("010_Cymbal"), "Cymbal")
check("slot 1", strip_slot_prefix("001_Kick"), "Kick")
check("slot 16, the last one", strip_slot_prefix("016_Ride"), "Ride")
check("a prefix from another kit", strip_slot_prefix("013_Snare"), "Snare")
check("unpadded, as a hand-named file might be", strip_slot_prefix("7_Clap"), "Clap")

print("numbers that are part of the name")
check("an 808", strip_slot_prefix("808_kick"), "808_kick")
check("a 909", strip_slot_prefix("909_snare"), "909_snare")
check("a 606", strip_slot_prefix("606_hat"), "606_hat")
check("101, above the slots but a real machine", strip_slot_prefix("101_bass"), "101_bass")
check("slot zero is not a slot", strip_slot_prefix("000_thing"), "000_thing")

print("names with nothing to take off")
check("no number at all", strip_slot_prefix("Cymbal"), "Cymbal")
check("a number with no underscore", strip_slot_prefix("808kick"), "808kick")
check("a number in the middle", strip_slot_prefix("Kick_010"), "Kick_010")
check("a space instead of an underscore", strip_slot_prefix("010 Cymbal"), "010 Cymbal")
check("empty", strip_slot_prefix(""), "")

print("what must never be stripped to nothing")
-- A file called 010_.wav has a prefix and no name. Taking it off would leave the
-- pad with an empty filename, which is worse than an ugly one.
check("a prefix with nothing after it", strip_slot_prefix("010_"), "010_")

print("stripping happens once, not repeatedly")
-- One pass only: 010_013_Cymbal came from a kit that was already double
-- prefixed, and taking both off would guess at which number the user meant.
check("only the outer prefix goes", strip_slot_prefix("010_013_Cymbal"), "013_Cymbal")

if fail == 0 then print("\nALL CHECKS PASSED") end
TEST_FAILED = fail
