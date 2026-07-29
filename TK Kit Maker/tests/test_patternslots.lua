-- "Slots from a pattern": the parsing and the pool matching behind it. The
-- matching is what makes the feature worth having -- without it you still have
-- to link sixteen slots by hand, which was the whole problem.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Categories = require("core.categories")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- Mirrors ui/builder_view.lua: exact alias first, then a loose match so
-- "Kicks" still answers to "Kick".
local function pool_for_word(pools, order, word)
  word = (word or ""):lower()
  if word == "" then return nil end
  for _, id in ipairs(order) do
    if (pools[id].alias or ""):lower() == word then return id end
  end
  for _, id in ipairs(order) do
    local alias = (pools[id].alias or ""):lower()
    if alias ~= "" and (alias:find(word, 1, true) or word:find(alias, 1, true)) then return id end
  end
  return nil
end

local function spec_word(spec, label)
  if spec.keyword and spec.keyword ~= "" then return spec.keyword end
  return (label or ""):gsub('"', "")
end

local pools = {
  p1 = { alias = "Kick" },
  p2 = { alias = "Snares" },      -- plural, must still match "Snare"
  p3 = { alias = "Hihat" },
  p4 = { alias = "Vinyl bits" },
}
local order = { "p1", "p2", "p3", "p4" }

-- 1. the pattern parses into specs and labels
local specs, labels = Categories.parse_pattern("Kick, Snare, Hihat, Clap")
check("four entries parsed", #specs == 4 and #labels == 4, #specs)
check("known words become categories", specs[1].category == "kick", tostring(specs[1].category))
check("labels come back readable", labels[2] == "Snare", labels[2])

-- 2. pool matching, which is the point
print("pattern word -> pool")
local resolved = {}
for i = 1, #specs do
  local id = pool_for_word(pools, order, spec_word(specs[i], labels[i]))
  resolved[i] = id
  print(string.format("  %-8s -> %s", labels[i], id and pools[id].alias or "(none)"))
end
check("exact alias matches", resolved[1] == "p1", tostring(resolved[1]))
check("a plural alias still matches", resolved[2] == "p2", tostring(resolved[2]))
check("third matches too", resolved[3] == "p3", tostring(resolved[3]))
check("a word with no pool stays unmatched", resolved[4] == nil, tostring(resolved[4]))

-- 3. unknown words become keyword filters, and match a pool by that keyword
local kspecs, klabels = Categories.parse_pattern("vinyl")
check("unknown word becomes a keyword", kspecs[1].keyword == "vinyl", tostring(kspecs[1].keyword))
check("keyword strips its quotes for matching",
  spec_word(kspecs[1], klabels[1]) == "vinyl", spec_word(kspecs[1], klabels[1]))
check("keyword finds a loosely named pool",
  pool_for_word(pools, order, "vinyl") == "p4",
  tostring(pool_for_word(pools, order, "vinyl")))

-- 4. the cycle that fills the slots
local function build(count)
  local out = {}
  for i = 1, count do
    local idx = ((i - 1) % #specs) + 1
    out[i] = {
      number = i,
      pool_id = pool_for_word(pools, order, spec_word(specs[idx], labels[idx])),
      midi_note = math.min(127, 35 + i),
      pad = i,
      category = specs[idx].category,
      type_label = Categories.spec_label(specs[idx]),
    }
  end
  return out
end

local slots = build(16)
check("sixteen slots created", #slots == 16, #slots)
check("the pattern repeats", slots[1].category == slots[5].category
  and slots[5].category == slots[9].category, slots[5].category)
check("notes run from 36 upward", slots[1].midi_note == 36 and slots[16].midi_note == 51,
  slots[16].midi_note)
check("pads are numbered with the slots", slots[16].pad == 16, slots[16].pad)
check("every slot carries its filter", (function()
  for _, s in ipairs(slots) do
    if not s.category then return false end
  end
  return true
end)(), "missing")
check("three of four words wired a pool", (function()
  local linked = 0
  for _, s in ipairs(slots) do if s.pool_id then linked = linked + 1 end end
  return linked == 12 -- Clap has no pool, so 4 of 16 stay unlinked
end)(), "wrong count")
-- type_label ends up in the exported filename (core/naming.lua), so a generated
-- slot must carry it just like one filled in by hand.
check("slots carry the label used for filenames", slots[1].type_label == "Kick", slots[1].type_label)

-- 5. a count that is not a multiple of the pattern still fills exactly
local odd = build(6)
check("six slots from four words", #odd == 6, #odd)
check("the fifth wraps to the first", odd[5].category == odd[1].category, odd[5].category)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
