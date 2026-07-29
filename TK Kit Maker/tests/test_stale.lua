-- Staleness detection, and the thing that would hurt most if it broke: a cache
-- written before the size stamp existed must still load. Discarding it would
-- mean re-measuring an entire library over a field that was only added.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

local TMP = (os.getenv("TEMP") or "."):gsub("\\", "/") .. "/tkkm_staletest"
os.execute('mkdir "' .. TMP:gsub("/", "\\") .. '" 2>nul')

reaper = {
  GetResourcePath = function() return TMP end,
  RecursiveCreateDirectory = function(d) os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end,
  time_precise = os.clock,
  GetPlayState = function() return 0 end,
  new_array = function(n) local a = {} for i = 1, n do a[i] = 0 end a.clear = function() end return a end,
}

local Analyzer = require("core.analyzer")
local synth = {}
Analyzer.analyze = function(path) return synth[path] end

local Tags = require("core.tags")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function write_file(path, bytes)
  local f = io.open(path, "wb")
  f:write(string.rep("x", bytes))
  f:close()
end

local function metrics()
  return {
    dur = 1, nch = 1, attack_ms = 3, decay_ms = 200, decay10_ms = 50, crest_db = 9,
    centroid = 100, flat = 0.05, pitch = 60, tail_ratio = 0.5, hf_ratio = 0.2, width = 0,
    bands = { 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01 },
  }
end

Tags.clear_cache()

local sample = TMP .. "/kick.wav"
write_file(sample, 1000)
synth[sample] = metrics()

-- 1. a fresh measurement records the size
local m = Tags.ensure(sample)
check("the measurement stores a size", m and m.size == 1000, m and m.size)
check("an untouched file is not stale", Tags.is_stale(sample) == false, "stale")

-- 2. change the file, and it must notice
write_file(sample, 2000)
check("a changed file reads as stale", Tags.is_stale(sample) == true, "not stale")
check("forgetting it reports that it did", Tags.forget_if_stale(sample) == true, "false")
check("and the measurement is gone", Tags.get(sample) == nil, "still cached")
check("asking twice does not re-report", Tags.forget_if_stale(sample) == false, "true")

-- 3. it survives a round trip through the cache file
synth[sample] = metrics()
Tags.ensure(sample)
Tags.flush()
Tags.reload()
check("the size survives a reload", Tags.get(sample).size == 2000, Tags.get(sample).size)
check("still not stale after reloading", Tags.is_stale(sample) == false, "stale")

-- 4. stale_files picks out only what changed
local a, b = TMP .. "/a.wav", TMP .. "/b.wav"
write_file(a, 500); write_file(b, 600)
synth[a] = metrics(); synth[b] = metrics()
Tags.ensure(a); Tags.ensure(b)
write_file(b, 900)
local stale = Tags.stale_files({ sample, a, b })
check("exactly one file is reported", #stale == 1, #stale)
check("and it is the one that changed", stale[1] == b, tostring(stale[1]))

-- 5. THE compatibility case: a cache line from before the stamp existed
Tags.clear_cache()
local old_line = table.concat({
  "1", "1", "3", "200", "50", "9", "100", "0.05", "60", "0.5", "0.2", "0",
  "1", "0.5", "0.2", "0.1", "0.05", "0.02", "0.01",
}, "\t") .. "\t" .. sample
local f = io.open(TMP .. "/TK_Kit_Maker/tag_cache.tsv", "w")
f:write("TKKM-TAGS-1\n" .. old_line .. "\n")
f:close()
Tags.reload()

local old = Tags.get(sample)
check("a stamp-less cache line still loads", old ~= nil, "discarded")
check("its measurements are intact", old and old.decay_ms == 200, old and old.decay_ms)
check("it carries no size", old and old.size == nil, old and old.size)
check("and is never called stale on a guess", Tags.is_stale(sample) == false, "stale")
check("so it is not silently thrown away", Tags.forget_if_stale(sample) == false, "forgotten")

print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
