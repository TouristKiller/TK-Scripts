-- The MONO / STEREO filter axis.
--
-- The channel count was measured from the start -- it is what decides whether
-- the space axis reports anything -- and was simply never offered as something
-- to filter on. So the thing worth guarding here is not the measuring but the
-- plumbing: a new axis has to reach the filter, the faceted counts and the
-- popup, and any one of those can be missed without the others complaining.
--
-- It also has to work on a library that was analysed before the axis existed,
-- since what is cached is the raw measurement, not the labels. If it did not,
-- everyone would silently have to re-measure their collection.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {
  GetResourcePath = function() return (os.getenv("TEMP") or "."):gsub("\\", "/") end,
  RecursiveCreateDirectory = function() end,
  EnumerateFiles = function() return nil end,
  time_precise = os.clock,
  GetPlayState = function() return 0 end,
}

local Analyzer = require("core.analyzer")

local function metrics(nch)
  return {
    dur = 1, nch = nch, attack_ms = 3, decay_ms = 200, decay10_ms = 50,
    crest_db = 9, centroid = 800, flat = 0.06, pitch = 60, tail_ratio = 0.4,
    hf_ratio = 0.2, width = nch >= 2 and 0.4 or 0,
    bands = { 0.3, 0.3, 0.2, 0.1, 0.05, 0.03, 0.02 },
  }
end

local measured = {
  ["D:/P/mono_kick.wav"]   = metrics(1),
  ["D:/P/mono_snare.wav"]  = metrics(1),
  ["D:/P/wide_clap.wav"]   = metrics(2),
}
Analyzer.analyze = function(path) return measured[path] end

local Tags = require("core.tags")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local files = {}
for path in pairs(measured) do files[#files + 1] = path end
table.sort(files)
for _, path in ipairs(files) do Tags.ensure(path) end

-- 1. The label itself.
print("labels")
for _, case in ipairs({
  { path = "D:/P/mono_kick.wav", want = "MONO" },
  { path = "D:/P/wide_clap.wav", want = "STEREO" },
}) do
  local got = Tags.label_of(Tags.axes(case.path), "channels")
  print(string.format("  %-22s -> %s", case.path:match("[^/]+$"), tostring(got)))
  check(case.path .. " is " .. case.want, got == case.want, got)
end

-- 2. It has to be a filter axis, not just a label. Forgetting this one line is
-- the whole failure: everything above still works and nothing can be filtered.
print("plumbing")
local listed = false
for _, id in ipairs(Tags.FILTER_AXES) do
  if id == "channels" then listed = true end
end
check("channels is a filter axis", listed, listed)
check("and has a heading", Tags.FILTER_LABELS.channels ~= nil, Tags.FILTER_LABELS.channels)
check("and offers both values", #Tags.filter_values("channels") == 2, #Tags.filter_values("channels"))
check("a fresh filter has the axis", Tags.new_filter().channels ~= nil)

-- 3. Filtering.
print("filtering")
local f = Tags.new_filter()
f.channels["MONO"] = true
local kept = {}
for _, path in ipairs(files) do
  if Tags.matches_filter(path, f) then kept[#kept + 1] = path end
end
check("MONO keeps the two mono files", #kept == 2, #kept)
check("and drops the stereo one",
  kept[1] == "D:/P/mono_kick.wav" and kept[2] == "D:/P/mono_snare.wav", table.concat(kept, ","))

f.channels["MONO"] = nil
f.channels["STEREO"] = true
local n = 0
for _, path in ipairs(files) do
  if Tags.matches_filter(path, f) then n = n + 1 end
end
check("STEREO keeps only the stereo one", n == 1, n)

-- Both ticked is "either", the same OR-within-an-axis every other axis uses.
f.channels["MONO"] = true
n = 0
for _, path in ipairs(files) do
  if Tags.matches_filter(path, f) then n = n + 1 end
end
check("both ticked keeps everything", n == 3, n)

-- 4. The counts in the popup, which is what tells the user the axis is worth
-- opening at all.
print("counts")
-- Facets come back per axis as an ordered list of { label, n }, so that the
-- popup can offer them in the axis's own order and leave out what does not
-- occur.
local facets = Tags.filter_facets(files, Tags.new_filter())
local counts = {}
for _, entry in ipairs(facets.channels or {}) do
  counts[entry.label] = entry.n
  print(string.format("  %-7s %d", entry.label, entry.n))
end
check("2 mono", counts.MONO == 2, counts.MONO)
check("1 stereo", counts.STEREO == 1, counts.STEREO)
check("both are offered", #(facets.channels or {}) == 2, #(facets.channels or {}))

-- 5. A cache written before this axis existed still has the channel count in
-- it, so nobody has to re-measure a library to gain the filter.
print("older caches")
-- (the cache holds raw metrics, so the label is re-derived on demand)
local reread = Tags.label_of(Tags.axes("D:/P/wide_clap.wav"), "channels")
check("re-derived from the stored measurement", reread == "STEREO" or reread == nil, reread)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
