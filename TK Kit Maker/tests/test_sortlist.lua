-- Ordering the Browser's sample list.
--
-- Two failures worth guarding against, neither of which looks like a bug.
--
-- The first: the sort leaking into what seeds pick from. Positions in the scan
-- order decide which sample a seed chooses, so if sorting reordered that list
-- in place, the same seed over the same pack would build a different kit
-- depending on how the browser happened to be sorted -- on your machine and on
-- someone else's, with nothing on screen to explain it.
--
-- The second: an unstable order. table.sort is not stable, so two files that
-- compare equal can swap places on every frame. The list sits there flickering
-- and the rows move out from under the mouse.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Sort = require("core.sortlist")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function leaves(list)
  local out = {}
  for i, f in ipairs(list) do out[i] = Sort.leaf_of(f) end
  return table.concat(out, ", ")
end

-- --------------------------------------------------------------------------
-- 1. Numbers in names. This is the one people notice immediately.
-- --------------------------------------------------------------------------
print("numbered names")
local numbered = {
  "D:/P/Kick 10.wav", "D:/P/Kick 2.wav", "D:/P/Kick 1.wav",
  "D:/P/Kick 20.wav", "D:/P/Kick 3.wav",
}
local by_name = Sort.apply(numbered, "name", false)
check("counted, not spelled", leaves(by_name) ==
  "Kick 1.wav, Kick 2.wav, Kick 3.wav, Kick 10.wav, Kick 20.wav", leaves(by_name))
print("  " .. leaves(by_name))

-- Plain alphabetical is what this replaces, and it is wrong in a way that reads
-- as the sort having given up.
local naive = { table.unpack(numbered) }
table.sort(naive)
print("  alphabetical would give: " .. leaves(naive))

-- 808 and 909 are the folders Sebastian named, and the digits are the whole
-- name there.
local machines = { "/x/909.wav", "/x/808.wav", "/x/1000.wav", "/x/99.wav" }
check("bare numbers too", leaves(Sort.apply(machines, "name", false)) ==
  "99.wav, 808.wav, 909.wav, 1000.wav", leaves(Sort.apply(machines, "name", false)))

-- Leading zeros name the same number. They must not split the order.
local padded = { "/x/Snare 007.wav", "/x/Snare 8.wav", "/x/Snare 06.wav" }
check("leading zeros sort by value", leaves(Sort.apply(padded, "name", false)) ==
  "Snare 06.wav, Snare 007.wav, Snare 8.wav", leaves(Sort.apply(padded, "name", false)))

-- A run of digits too long to be a number must not crash or collapse.
local huge = { "/x/b" .. string.rep("9", 40) .. ".wav", "/x/a" .. string.rep("1", 40) .. ".wav" }
check("absurdly long digit runs survive", #Sort.apply(huge, "name", false) == 2)

-- --------------------------------------------------------------------------
-- 2. Case. The order has to look the same on Windows and on macOS.
-- --------------------------------------------------------------------------
print("case")
local mixed = { "/x/beta.wav", "/x/Alpha.wav", "/x/gamma.wav", "/x/BETA2.wav" }
check("case-insensitive", leaves(Sort.apply(mixed, "name", false)) ==
  "Alpha.wav, beta.wav, BETA2.wav, gamma.wav", leaves(Sort.apply(mixed, "name", false)))

-- --------------------------------------------------------------------------
-- 3. Direction
-- --------------------------------------------------------------------------
print("direction")
local down = Sort.apply(numbered, "name", true)
check("descending is the reverse", leaves(down) ==
  "Kick 20.wav, Kick 10.wav, Kick 3.wav, Kick 2.wav, Kick 1.wav", leaves(down))
check("the labels say which is which", Sort.button_label("name", false) == "A-Z"
  and Sort.button_label("name", true) == "Z-A", Sort.button_label("name", true))

-- --------------------------------------------------------------------------
-- 4. Sorting by name uses the filename, not the path. Otherwise the folder
--    decides the order and the sort looks like it did nothing.
-- --------------------------------------------------------------------------
print("names, not paths")
local across = { "D:/zzz/aaa.wav", "D:/aaa/zzz.wav" }
check("the leaf decides", leaves(Sort.apply(across, "name", false)) == "aaa.wav, zzz.wav",
  leaves(Sort.apply(across, "name", false)))

-- --------------------------------------------------------------------------
-- 5. Length, and the part that matters: lengths that are not known yet.
--    The cache fills in the background, so on a fresh pack most of them are
--    nil for a while.
-- --------------------------------------------------------------------------
print("length")
local secs = {
  ["/x/long.wav"] = 4.0, ["/x/short.wav"] = 0.2, ["/x/mid.wav"] = 1.5,
  ["/x/unknown_a.wav"] = nil, ["/x/unknown_b.wav"] = nil,
}
local by_len_files = { "/x/long.wav", "/x/unknown_b.wav", "/x/short.wav",
                       "/x/unknown_a.wav", "/x/mid.wav" }
local lookup = function(p) return secs[p] end

local up = Sort.apply(by_len_files, "length", false, lookup)
check("shortest first", leaves(up) ==
  "short.wav, mid.wav, long.wav, unknown_a.wav, unknown_b.wav", leaves(up))

local dn = Sort.apply(by_len_files, "length", true, lookup)
check("longest first", leaves(dn) ==
  "long.wav, mid.wav, short.wav, unknown_a.wav, unknown_b.wav", leaves(dn))
print("  unmeasured: " .. leaves(dn))

-- The trap. Treating an unknown length as zero would put every unmeasured file
-- at the top the moment you asked for longest-first, which reads as the sort
-- having failed on a pack that is still being measured.
check("unknown lengths stay last in both directions",
  leaves(up):match("unknown_a%.wav, unknown_b%.wav$") ~= nil and
  leaves(dn):match("unknown_a%.wav, unknown_b%.wav$") ~= nil)

local measured = { ["/x/soft.wav"] = 0.1, ["/x/mid.wav"] = 0.5, ["/x/hard.wav"] = 0.9 }
local character_files = { "/x/hard.wav", "/x/unknown.wav", "/x/soft.wav", "/x/mid.wav" }
local metric = function(path) return measured[path] end
check("transients sort soft to hard", leaves(Sort.apply(character_files, "transient", false, metric)) ==
  "soft.wav, mid.wav, hard.wav, unknown.wav", leaves(Sort.apply(character_files, "transient", false, metric)))
check("transients sort hard to soft", leaves(Sort.apply(character_files, "transient", true, metric)) ==
  "hard.wav, mid.wav, soft.wav, unknown.wav", leaves(Sort.apply(character_files, "transient", true, metric)))
check("frequency uses the same numeric ordering", leaves(Sort.apply(character_files, "frequency", false, metric)) ==
  "soft.wav, mid.wav, hard.wav, unknown.wav", leaves(Sort.apply(character_files, "frequency", false, metric)))
check("new sort labels show direction", Sort.button_label("transient", false) == "Soft-Hard"
  and Sort.button_label("transient", true) == "Hard-Soft"
  and Sort.button_label("frequency", false) == "Low-High"
  and Sort.button_label("frequency", true) == "High-Low")

-- --------------------------------------------------------------------------
-- 6. Stability. Equal keys must not swap places between calls, or the list
--    flickers and rows move out from under the pointer.
-- --------------------------------------------------------------------------
print("stability")
local same = {}
for i = 1, 60 do same[i] = string.format("D:/pack%02d/Clap.wav", i) end
local eq = function() return 1.0 end
local a1 = table.concat(Sort.apply(same, "length", false, eq), "|")
local a2 = table.concat(Sort.apply(same, "length", true, eq), "|")
local a3 = table.concat(Sort.apply(same, "length", false, eq), "|")
check("identical lengths give one fixed order", a1 == a3)
check("and reversing direction does not change it either", a1 == a2)

local dupes = { "D:/b/Hat.wav", "D:/a/Hat.wav", "D:/c/Hat.wav" }
local d1 = table.concat(Sort.apply(dupes, "name", false), "|")
local d2 = table.concat(Sort.apply(dupes, "name", false), "|")
check("same filename in three folders keeps one order", d1 == d2)
check("broken by path", d1 == "D:/a/Hat.wav|D:/b/Hat.wav|D:/c/Hat.wav", d1)

-- --------------------------------------------------------------------------
-- 7. The input is never touched. This is the seed guarantee.
-- --------------------------------------------------------------------------
print("the scan order survives")
local scan = { "D:/P/z.wav", "D:/P/a.wav", "D:/P/m.wav" }
local before = table.concat(scan, "|")
local sorted = Sort.apply(scan, "name", false)
check("a new list comes back", not rawequal(sorted, scan))
check("the original is untouched", table.concat(scan, "|") == before, table.concat(scan, "|"))
check("and it really was sorted", leaves(sorted) == "a.wav, m.wav, z.wav", leaves(sorted))

-- An unknown mode is a copy in the original order, not an error and not the
-- same table -- a caller that got the live list back could sort it in place.
local passthru = Sort.apply(scan, "whatever", false)
check("an unknown mode copies", table.concat(passthru, "|") == before, table.concat(passthru, "|"))
check("as a copy", not rawequal(passthru, scan))

check("an empty list is fine", #Sort.apply({}, "name", false) == 0)
check("and so is no list at all", #Sort.apply(nil, "name", false) == 0)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
