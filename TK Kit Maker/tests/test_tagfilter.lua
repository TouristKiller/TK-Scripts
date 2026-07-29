-- Tag filtering for the sample list. This is a REAL filter, unlike the
-- character bias, so the tests pin the hard-edged behaviour: OR within an axis,
-- AND across axes, and unmeasured samples excluded once a filter is on.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {
  GetResourcePath = function() return (os.getenv("TEMP") or ".") .. "/tkkm_tftest" end,
  RecursiveCreateDirectory = function(d) os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end,
  time_precise = os.clock,
  GetPlayState = function() return 0 end,
  new_array = function(n) local a = {} for i = 1, n do a[i] = 0 end a.clear = function() end return a end,
}

local Analyzer = require("core.analyzer")
local synth = {}
Analyzer.analyze = function(path) return synth[path] end

local Tags = require("core.tags")
Tags.clear_cache()

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function put(path, centroid, decay_ms, attack_ms, flat, bands)
  synth[path] = {
    dur = 1, nch = 1, attack_ms = attack_ms, decay_ms = decay_ms, decay10_ms = decay_ms * 0.25,
    crest_db = 9, centroid = centroid, flat = flat, pitch = 60,
    tail_ratio = 0.5, hf_ratio = 0.2, width = 0, bands = bands,
  }
  Tags.ensure(path)
  return path
end

local KICK  = { 1.0, 0.6, 0.2, 0.1, 0.05, 0.02, 0.01 }
local HAT   = { 0.02, 0.03, 0.05, 0.2, 0.5, 0.9, 1.0 }

-- Two short sub kicks, one long sub kick, two noisy hats.
local k1 = put("k1.wav", 50, 90, 3, 0.02, KICK)
local k2 = put("k2.wav", 52, 100, 3, 0.02, KICK)
local k3 = put("k3.wav", 48, 2500, 3, 0.02, KICK)
local h1 = put("h1.wav", 9000, 50, 0.5, 0.7, HAT)
local h2 = put("h2.wav", 9500, 60, 0.5, 0.7, HAT)
local unknown = "never_analysed.wav"
local files = { k1, k2, k3, h1, h2, unknown }

local function labels_of(path)
  local a = Tags.axes(path)
  return Tags.label_of(a, "band"), Tags.label_of(a, "decay"), Tags.label_of(a, "tonality")
end
print("sample labels")
for _, f in ipairs({ k1, k3, h1 }) do
  print(string.format("  %-8s %s / %s / %s", f, labels_of(f)))
end

local function count(filter)
  local n = 0
  for _, f in ipairs(files) do
    if Tags.matches_filter(f, filter) then n = n + 1 end
  end
  return n
end

-- 1. no filter lets everything through, including the unmeasured file
local f = Tags.new_filter()
check("a fresh filter is inactive", Tags.filter_active(f) == false, "active")
check("no filter keeps everything", count(f) == #files, count(f))
check("no filter has an empty key", Tags.filter_key(f) == "", Tags.filter_key(f))

-- 2. one label: hard, not soft. Non-matching samples are GONE, which is the
-- whole difference from the character bias.
local kb = select(1, labels_of(k1))
f[ "band" ][kb] = true
check("filter is now active", Tags.filter_active(f) == true, "inactive")
check("only the kicks survive", count(f) == 3, count(f))
check("a hat is excluded outright", Tags.matches_filter(h1, f) == false, "included")
check("the unmeasured file is excluded too", Tags.matches_filter(unknown, f) == false, "included")

-- 3. within an axis the labels are OR'd
local hb = select(1, labels_of(h1))
f["band"][hb] = true
check("two bands accept both groups", count(f) == 5, count(f))

-- 4. across axes they are AND'ed
f["band"] = { [kb] = true }
local short_label = select(2, labels_of(k1))
f["decay"] = { [short_label] = true }
check("band AND decay narrows further", count(f) == 2, count(f))
check("the long kick is dropped by the decay axis", Tags.matches_filter(k3, f) == false, "kept")

-- 5. skip_axis is what faceted counting needs
check("skipping the decay axis lets the long kick back in",
  Tags.matches_filter(k3, f, "decay") == true, "still out")

-- 6. facets offer only what occurs, and count with the other axes applied
local facets, unmeasured = Tags.filter_facets(files, Tags.new_filter())
local band_labels = {}
for _, e in ipairs(facets.band) do band_labels[#band_labels + 1] = e.label .. "=" .. e.n end
print("band facets (no filter): " .. table.concat(band_labels, "  "))
check("unmeasured files are counted separately", unmeasured == 1, unmeasured)
check("only occurring bands are offered", #facets.band == 2, #facets.band)
check("a pack of these never offers every band", #facets.band < 7, #facets.band)

local narrowed = Tags.new_filter()
narrowed.decay = { [short_label] = true }
local f2 = Tags.filter_facets(files, narrowed)
local kick_n
for _, e in ipairs(f2.band) do if e.label == kb then kick_n = e.n end end
check("band counts respect the decay filter", kick_n == 2, kick_n)

-- 7. a selected label must stay on offer even when nothing else allows it
local impossible = Tags.new_filter()
impossible.band = { [kb] = true }
impossible.tonality = { NOISE = true } -- kicks are not noise
local f3 = Tags.filter_facets(files, impossible)
local still_there = false
for _, e in ipairs(f3.tonality) do
  if e.label == "NOISE" then still_there = true end
end
check("a selected label with no matches stays clickable", still_there, "vanished")

-- 8. the key must track every change, or the caller's cache goes stale
local k_before = Tags.filter_key(f)
f["decay"] = {}
check("key follows a cleared axis", Tags.filter_key(f) ~= k_before, "unchanged")
f["decay"] = { [short_label] = true }
check("key is stable for the same selection", Tags.filter_key(f) == k_before, "unstable")
check("filter_count counts every picked label", Tags.filter_count(f) == 2, Tags.filter_count(f))

-- 9. Source is the odd one out: it comes from the FILENAME, so it must work on
-- material nobody has analysed. If it needed a measurement it would be useless
-- exactly when it is most useful -- on a pack you have not scanned yet.
local e1 = put("Packs/808 Machine/BD_808_01.wav", 50, 90, 3, 0.02, KICK)
local a1 = put("Packs/Live Kit/acoustic_snare.wav", 3000, 300, 3, 0.4, HAT)
local e_unscanned = "Packs/909 Machine/never_scanned_909.wav"
local src_files = { e1, a1, e_unscanned }

check("source is read off the name", Tags.source_of(e1) == "ELECTRONIC", Tags.source_of(e1))

-- 8b. The whole path is searched, not just parent + filename. What marks a pack
-- as acoustic sits in the PACK folder, while the files are all called SN_01 --
-- looking only at the parent is why nothing but the 808 packs ever matched.
local deep = "D:/Samples/Vintage Acoustic Kit/Snares/SN_01.wav"
check("a keyword in the pack folder is found", Tags.source_of(deep) == "ACOUSTIC",
  tostring(Tags.source_of(deep)))
check("a keyword deep in the path still counts",
  Tags.source_of("D:/Foley Library/Doors/hit_04.wav") == "FOLEY",
  tostring(Tags.source_of("D:/Foley Library/Doors/hit_04.wav")))
-- A word from one source inside a word from another must not score: "acoustic"
-- contains "stick", which is why that one is matched as a whole word.
check("'stick' does not fire inside 'acoustic'",
  Tags.source_of("D:/Acoustic Kit/sn_01.wav") == "ACOUSTIC",
  tostring(Tags.source_of("D:/Acoustic Kit/sn_01.wav")))

-- Kit Maker's own name generator has "Wooden" and "Field" in its word lists, so
-- a generated kit could be called "Wooden Field Machine". Ordinary English must
-- not tag a pack, or every such kit comes out ACOUSTIC.
for _, name in ipairs({
  "D:/Kits/Wooden Field Machine/kick_01.wav",
  "D:/Kits/Live Nature Punch/snare_02.wav",
  "D:/Kits/Digital Ambient Skin/hat_03.wav",
}) do
  check("decorative name '" .. name:match("Kits/([^/]+)") .. "' stays untagged",
    Tags.source_of(name) == nil, tostring(Tags.source_of(name)))
end

-- Brands only count when the brand makes one kind of thing.
check("Ludwig means drums", Tags.source_of("D:/Ludwig Kit/sn.wav") == "ACOUSTIC",
  tostring(Tags.source_of("D:/Ludwig Kit/sn.wav")))
check("Yamaha means nothing on its own -- drums and the DX7",
  Tags.source_of("D:/Yamaha Kit/sn.wav") == nil,
  tostring(Tags.source_of("D:/Yamaha Kit/sn.wav")))

-- The filename outranks the folder: a word in the file is about that sample.
local _, from_file = Tags.source_of("D:/Acoustic Kit/sn_01.wav")
check("a folder match is reported as not from the file", from_file == false, from_file)
local src2, from_file2 = Tags.source_of("D:/Acoustic Kit/BD_808_01.wav")
check("a filename match wins over the folder", src2 == "ELECTRONIC", tostring(src2))
check("and is reported as coming from the file", from_file2 == true, from_file2)

-- Short fragments must match as whole words only, or they fire inside others.
check("'fm' does not fire on 'confirm'",
  Tags.source_of("D:/Samples/Confirmed Hits/kick_01.wav") == nil,
  tostring(Tags.source_of("D:/Samples/Confirmed Hits/kick_01.wav")))
check("'fm' does fire as its own word",
  Tags.source_of("D:/Samples/FM Drums/kick_01.wav") == "ELECTRONIC",
  tostring(Tags.source_of("D:/Samples/FM Drums/kick_01.wav")))
check("'live' does not fire on 'delivery'",
  Tags.source_of("D:/Delivery/kick_01.wav") == nil,
  tostring(Tags.source_of("D:/Delivery/kick_01.wav")))

-- The strongest match wins within one scope, instead of whichever row came
-- first in the table.
check("more keywords wins",
  Tags.source_of("D:/Kits/acoustic_brush_808.wav") == "ACOUSTIC",
  tostring(Tags.source_of("D:/Kits/acoustic_brush_808.wav")))
check("an even match in one name says nothing rather than guessing",
  Tags.source_of("D:/Kits/acoustic_808.wav") == nil,
  tostring(Tags.source_of("D:/Kits/acoustic_808.wav")))
-- ...but a file that names itself beats the folder outright, however many
-- keywords the folder has: "808_style.wav" is about that sample.
check("the file beats the folder even when the folder says more",
  Tags.source_of("D:/Acoustic Brush Kit/Ludwig/808_style.wav") == "ELECTRONIC",
  tostring(Tags.source_of("D:/Acoustic Brush Kit/Ludwig/808_style.wav")))
check("nothing recognisable stays untagged",
  Tags.source_of("D:/Packs/Pack 12/bd_003.wav") == nil,
  tostring(Tags.source_of("D:/Packs/Pack 12/bd_003.wav")))
check("source works with no measurement at all",
  Tags.source_of(e_unscanned) == "ELECTRONIC", tostring(Tags.source_of(e_unscanned)))

local sf = Tags.new_filter()
sf.source = { ELECTRONIC = true }
check("a source filter does not need analysis",
  Tags.matches_filter(e_unscanned, sf) == true, "excluded")
check("a source filter still excludes the wrong source",
  Tags.matches_filter(a1, sf) == false, "included")
check("a source-only filter is not flagged as needing analysis",
  Tags.filter_needs_analysis(sf) == false, "flagged")

local mixed = Tags.new_filter()
mixed.source = { ELECTRONIC = true }
mixed.band = { SUB = true }
check("adding a measured axis does flag it",
  Tags.filter_needs_analysis(mixed) == true, "not flagged")
check("and then the unanalysed file drops out",
  Tags.matches_filter(e_unscanned, mixed) == false, "kept")

-- Facets must offer source for unanalysed material too.
local sfacets = Tags.filter_facets(src_files, Tags.new_filter())
local elec_n
for _, e in ipairs(sfacets.source) do
  if e.label == "ELECTRONIC" then elec_n = e.n end
end
check("source facets count unanalysed files as well", elec_n == 2, elec_n)
check("only occurring sources are offered", #sfacets.source == 2, #sfacets.source)

-- 10. Category is the multi-label axis: an open hihat is also a hihat, on
-- purpose, so filtering on Hihat has to return it. Every other axis assigns
-- exactly one label.
local cat_files = {
  "Pack/BD_kick_01.wav",
  "Pack/SD_snare_01.wav",
  "Pack/OHH_01.wav",
  "Pack/CHH_01.wav",
  "Pack/zzz_9912.wav",   -- nothing in the naming rules recognises this
}

local cf = Tags.new_filter()
cf.category = { Hihat = true }
local hats = 0
for _, f in ipairs(cat_files) do
  if Tags.matches_filter(f, cf) then hats = hats + 1 end
end
check("Hihat returns open and closed alike", hats == 2, hats)

cf.category = { ["Open hihat"] = true }
check("Open hihat returns only the open one",
  Tags.matches_filter("Pack/OHH_01.wav", cf) == true
  and Tags.matches_filter("Pack/CHH_01.wav", cf) == false, "wrong")

cf.category = { Kick = true, Snare = true }
local ks = 0
for _, f in ipairs(cat_files) do
  if Tags.matches_filter(f, cf) then ks = ks + 1 end
end
check("two categories are OR'd", ks == 2, ks)

check("category needs no analysis",
  Tags.matches_filter("Pack/BD_kick_01.wav", Tags.new_filter()) == true, "excluded")
local cat_only = Tags.new_filter()
cat_only.category = { Kick = true }
check("a category-only filter is not flagged as needing analysis",
  Tags.filter_needs_analysis(cat_only) == false, "flagged")
check("an unanalysed file passes a category filter",
  Tags.matches_filter("Pack/BD_kick_01.wav", cat_only) == true, "excluded")

-- Facets: only categories that occur, and a sample counted under each of its
-- own -- so the totals exceed the file count.
local cfacets = Tags.filter_facets(cat_files, Tags.new_filter())
local offered, total = {}, 0
for _, e in ipairs(cfacets.category) do
  offered[e.label] = e.n
  total = total + e.n
end
local names = {}
for _, e in ipairs(cfacets.category) do names[#names + 1] = e.label .. "=" .. e.n end
print()
print("category facets: " .. table.concat(names, "  "))
check("only occurring categories are offered", offered.Tom == nil and offered.Vocal == nil, "extra")
check("kick is counted", offered.Kick == 1, offered.Kick)
check("hihat counts both variants", offered.Hihat == 2, offered.Hihat)
check("open hihat is counted separately", offered["Open hihat"] == 1, offered["Open hihat"])
check("overlapping labels push the total past the file count", total > #cat_files, total)

-- Files the naming rules do not recognise must be reachable, or there is no way
-- to find out what Kit Maker cannot read -- and those same files will not work
-- in Builder slot filters or Explosion patterns either.
check("unrecognised files are offered as Uncategorised",
  offered[Tags.UNCATEGORISED] == 1, tostring(offered[Tags.UNCATEGORISED]))
check("Uncategorised comes last, after the real categories",
  cfacets.category[#cfacets.category].label == Tags.UNCATEGORISED,
  cfacets.category[#cfacets.category].label)

local uf = Tags.new_filter()
uf.category = { [Tags.UNCATEGORISED] = true }
check("selecting it returns exactly the unrecognised file",
  Tags.matches_filter("Pack/zzz_9912.wav", uf) == true
  and Tags.matches_filter("Pack/BD_kick_01.wav", uf) == false, "wrong")

uf.category[Tags.UNCATEGORISED] = true
uf.category.Kick = true
local both = 0
for _, f in ipairs(cat_files) do
  if Tags.matches_filter(f, uf) then both = both + 1 end
end
check("it OR's with a real category like any other label", both == 2, both)

check("a fully recognised pack offers no Uncategorised chip", (function()
  local clean = Tags.filter_facets({ "Pack/BD_kick_01.wav" }, Tags.new_filter())
  for _, e in ipairs(clean.category) do
    if e.label == Tags.UNCATEGORISED then return false end
  end
  return true
end)(), "offered anyway")

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
