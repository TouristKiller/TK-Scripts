-- Walks exactly the data path ui/browser_view.lua's tag panel uses, for an
-- analysed file, an unanalysed one and one that failed analysis.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

local store = {}
reaper = {
  GetResourcePath = function() return (os.getenv("TEMP") or ".") .. "/tkkm_uitest" end,
  RecursiveCreateDirectory = function(d) os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end,
  time_precise = os.clock,
  GetPlayState = function() return 0 end,
  new_array = function(n) local a = {} for i = 1, n do a[i] = 0 end a.clear = function() end return a end,
  PCM_Source_CreateFromFile = function(p) return store[p] end,
  PCM_Source_Destroy = function() end,
  PCM_Source_GetPeaks = function() return false end,
  GetMediaSourceSampleRate = function() return 44100 end,
  GetMediaSourceNumChannels = function() return 1 end,
  GetMediaSourceLength = function() return 1, false end,
}

local Analyzer = require("core.analyzer")
local Tags = require("core.tags")
Tags.clear_cache()

-- Hand-built metrics standing in for a measured stereo snare.
local metrics = {
  dur = 0.8, nch = 2, attack_ms = 3.1, decay_ms = 420, decay10_ms = 40,
  crest_db = 9.2, centroid = 2400, flat = 0.42, pitch = 210,
  tail_ratio = 2.1, hf_ratio = 0.22, width = 0.38,
  bands = { 0.10, 0.22, 0.51, 1.00, 0.74, 0.31, 0.08 },
}

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- 1. the fully measured case
local d = Tags.derive(metrics)
local L = Tags.derive_labels(d)
print("labels:", L.band, L.transient, L.decay, L.tonality, L.space)

check("every AXES entry resolves a value and a label", (function()
  for _, axis in ipairs(Tags.AXES) do
    local v = d[axis.key]
    local lab = L[axis.id]
    if axis.id == "tone" then lab = L.band end
    if axis.id ~= "space" and (v == nil or lab == nil) then return false end
  end
  return true
end)(), "mismatch")

check("dominant band is in range", d.band >= 1 and d.band <= Analyzer.BAND_COUNT, d.band)
check("dominant band is the loudest one", d.band == 4, d.band)
check("stereo file gets a space label", L.space ~= nil, "nil")

-- 2. never analysed: the panel must survive nil metrics
local t = Tags.tags("Drums/Kicks/BD_808_deep.wav")
check("unanalysed file yields no axes", t.axes == nil, "axes present")
check("unanalysed file yields no labels", t.labels == nil, "labels present")
check("filename still gives a category", t.category == "Kick", t.category)
check("filename still gives a function", t["function"] == "KICK", t["function"])
check("filename still gives a source", t.source == "ELECTRONIC", tostring(t.source))
check("bands access is nil-safe", (t.metrics and t.metrics.bands or nil) == nil, "not nil")

-- 3. analysis attempted and failed (unreadable file)
Tags.ensure("does/not/exist.wav")
check("failed file stays cached as failed", Tags.is_analyzed("does/not/exist.wav"), false)
check("failed file returns no metrics", Tags.get("does/not/exist.wav") == nil, "metrics")
local tf = Tags.tags("does/not/exist.wav")
check("failed file yields no labels", tf.labels == nil, "labels")

-- 4. a mono file reports no spatiality rather than guessing
local mono = {}
for k, v in pairs(metrics) do mono[k] = v end
mono.nch = 1
local dm = Tags.derive(mono)
check("mono has no space value", dm.space01 == nil, dm.space01)
check("mono has no space bucket", dm.space == nil, dm.space)
check("mono space label is nil", Tags.derive_labels(dm).space == nil, "label")

-- 5. the tone axis must SPREAD real drum material, not heap it at the top.
-- Centroids below are what a real library measures (verified on 213 samples):
-- kicks sit at the bottom, toms low-mid, claps and snares mid-high, hats top.
local function tone_of(centroid)
  local mm = {}
  for k, v in pairs(metrics) do mm[k] = v end
  mm.centroid = centroid
  return Tags.derive(mm).tone01
end

local spread = {
  { name = "kick", hz = 70,   lo = 0.00, hi = 0.25 },
  { name = "tom",  hz = 220,  lo = 0.25, hi = 0.50 },
  { name = "clap", hz = 2500, lo = 0.50, hi = 0.72 },
  { name = "snare", hz = 3200, lo = 0.50, hi = 0.72 },
  { name = "hat",  hz = 8000, lo = 0.72, hi = 1.00 },
}
print()
print("tone axis placement")
local prev = -1
for _, s in ipairs(spread) do
  local v = tone_of(s.hz)
  print(string.format("  %-6s %5d Hz -> %.3f", s.name, s.hz, v))
  check(s.name .. " lands in its part of the axis", v >= s.lo and v <= s.hi, v)
  check(s.name .. " stays above the one below it", v >= prev, v)
  prev = v
end
check("a sub-only sample pins to the bottom", tone_of(25) < 0.15, tone_of(25))
check("a very bright sample stays inside the axis", tone_of(19000) <= 1.0, tone_of(19000))

-- 6. tonality boundaries, pinned against what a real library reports.
local function tonality_of(flat, centroid, decay_ms)
  local mm = {}
  for k, v in pairs(metrics) do mm[k] = v end
  mm.flat, mm.centroid, mm.decay_ms = flat, centroid, decay_ms
  return Tags.derive_labels(Tags.derive(mm)).tonality
end

print()
print("tonality boundaries")
local tonal = {
  { name = "hi-hat",       flat = 0.55, hz = 8000, dec = 60,   want = "NOISE" },
  { name = "snare",        flat = 0.38, hz = 3200, dec = 300,  want = "NOISE" },
  { name = "metal tom",    flat = 0.18, hz = 900,  dec = 700,  want = "PITCHED" },
  { name = "vinyl scratch",flat = 0.15, hz = 2200, dec = 400,  want = "PITCHED" },
  -- The reason the lower boundary moved from 0.12 to 0.05:
  { name = "bongo",        flat = 0.09, hz = 320,  dec = 250,  want = "PITCHED" },
  { name = "low tom",      flat = 0.07, hz = 180,  dec = 600,  want = "PITCHED" },
  -- ...without letting the synthetic material follow it across.
  { name = "808",          flat = 0.01, hz = 55,   dec = 1800, want = "DEFINED" },
  { name = "synth bass",   flat = 0.02, hz = 90,   dec = 900,  want = "DEFINED" },
  { name = "glockenspiel", flat = 0.01, hz = 3000, dec = 1500, want = "CHROMATIC" },
}
for _, s in ipairs(tonal) do
  local got = tonality_of(s.flat, s.hz, s.dec)
  print(string.format("  %-14s flat %.2f -> %s", s.name, s.flat, got))
  check(s.name .. " reads " .. s.want, got == s.want, got)
end

-- 7. category names used for the chip exist for every mapped function
for cat_id in pairs({ kick = 1, snare = 1, hihat = 1, perc = 1, fx = 1 }) do
  local Categories = require("core.categories")
  check("category " .. cat_id .. " still exists", Categories.by_id(cat_id) ~= nil, "missing")
end

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
