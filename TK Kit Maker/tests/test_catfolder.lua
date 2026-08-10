-- Which name a category filter is allowed to read.
--
-- The filename first, and the parent folder only when the filename names no
-- category at all. A folder called "WA Snares & Claps" says two things at once,
-- and reading it always meant a slot asking for snares also got the claps --
-- while a numbered pack, "Kicks/001.wav", has nothing but the folder to go on
-- and has to keep working. Both cases live here, next to each other, because
-- the rule only earns its keep if it serves both.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Categories = require("core.categories")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function matches(path, cat)
  return Categories.matches(path, { category = cat })
end

-- 1. The case that was wrong: a folder naming two instruments
print("folder \"WA Snares & Claps\"")
local FOLDER = "D:/Packs/WA Snares & Claps/"
for _, e in ipairs({
  { file = "wa_snare_01.wav", is = "snare", isnt = "clap" },
  { file = "wa_clap_01.wav",  is = "clap",  isnt = "snare" },
  { file = "wa_rim_03.wav",   is = "rim",   isnt = "snare" },
}) do
  local path = FOLDER .. e.file
  local hit_is = matches(path, e.is)
  local hit_isnt = matches(path, e.isnt)
  print(string.format("  %-18s %s=%s  %s=%s", e.file,
    e.is, tostring(hit_is), e.isnt, tostring(hit_isnt)))
  check(e.file .. " answers " .. e.is, hit_is, hit_is)
  check(e.file .. " does not answer " .. e.isnt, not hit_isnt, hit_isnt)
end

-- 2. The case that must not break: the file names nothing, so the folder is all
--    there is. This is why the folder was read in the first place.
print("numbered files under a named folder")
check("Kicks/001.wav is a kick", matches("D:/Packs/Kicks/001.wav", "kick"), false)
check("Kicks/001.wav is not a snare", not matches("D:/Packs/Kicks/001.wav", "snare"), true)
-- Plural folders, which is how everyone names them. "clap" and "rim" are short
-- enough to have to match a whole token, so without the plural rule these two
-- failed while Kicks and Snares worked -- the same question answered
-- differently depending on which category you asked about.
check("Claps/07.wav is a clap", matches("D:/Packs/Claps/07.wav", "clap"), false)
check("Rims/07.wav is a rim", matches("D:/Packs/Rims/07.wav", "rim"), false)
check("Toms/07.wav is a tom", matches("D:/Packs/Toms/07.wav", "tom"), false)
check("a plural does not make a clap a snare",
  not matches("D:/Packs/Claps/07.wav", "snare"), true)
check("bass survives the plural rule",
  matches("D:/Packs/Bass/07.wav", "bass"), false)

-- 3. The test is "does the filename name ANY category", not the one being
--    asked for. Otherwise a clap in a Snares folder still answers Snare.
check("Snares/clap_02.wav is a clap", matches("D:/Packs/Snares/clap_02.wav", "clap"), false)
check("Snares/clap_02.wav is not a snare", not matches("D:/Packs/Snares/clap_02.wav", "snare"), true)

-- 4. A keyword is free text and deliberately still reads the path: what it
--    looks for is routinely only in the folder name.
check("keyword vinyl finds Vinyl Drums/kick.wav",
  Categories.matches("D:/Vinyl Drums/kick.wav", { keyword = "vinyl" }), false)
check("keyword still matches the filename",
  Categories.matches("D:/Vinyl Drums/kick.wav", { keyword = "kick" }), false)

-- 5. count_all and matches_none follow the same rule, or the Browser's facet
--    counts would disagree with what a slot actually picks.
local files = {
  FOLDER .. "wa_snare_01.wav",
  FOLDER .. "wa_snare_02.wav",
  FOLDER .. "wa_clap_01.wav",
  "D:/Packs/Kicks/001.wav",
  "D:/Packs/Misc/blorp.wav",
}
local counts, none = Categories.count_all(files)
print(string.format("counts: snare=%d clap=%d kick=%d uncategorised=%d",
  counts.snare, counts.clap, counts.kick, none))
check("two snares, not three", counts.snare == 2, counts.snare)
check("one clap", counts.clap == 1, counts.clap)
check("the numbered kick is counted", counts.kick == 1, counts.kick)
check("blorp is uncategorised", none == 1, none)
check("matches_none agrees", Categories.matches_none("D:/Packs/Misc/blorp.wav"), false)
check("matches_none says no for the numbered kick",
  not Categories.matches_none("D:/Packs/Kicks/001.wav"), true)

-- 6. match_count is what the Builder's Filter column shows, so it has to agree.
check("match_count sees two snares",
  Categories.match_count(files, { category = "snare" }) == 2,
  Categories.match_count(files, { category = "snare" }))

if fail == 0 then print("\nALL CHECKS PASSED") end
TEST_FAILED = fail
