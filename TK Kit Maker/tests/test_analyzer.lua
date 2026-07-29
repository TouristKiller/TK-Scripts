-- Standalone harness: stubs the bits of the REAPER API core/analyzer.lua uses
-- and feeds it synthetic one-shots, so the DSP can be checked without REAPER.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. KIT .. "?\\init.lua;" .. package.path

----------------------------------------------------------------------
-- synthetic sources
----------------------------------------------------------------------
local SR = 44100
local sources = {}

local function make(name, len, nch, fn)
  local n = math.floor(len * SR)
  local data = {}
  for ch = 1, nch do data[ch] = {} end
  for i = 1, n do
    local t = (i - 1) / SR
    local l, rr = fn(t, i)
    data[1][i] = l
    if nch >= 2 then data[2][i] = rr or l end
  end
  sources[name] = { name = name, sr = SR, nch = nch, len = len, n = n, data = data }
  return sources[name]
end

local function env(t, attack, tau)
  local a = attack > 0 and math.min(1, t / attack) or 1
  if t < 0 then return 0 end
  return a * math.exp(-math.max(0, t - attack) / tau)
end

-- round 55 Hz kick, no beater click at all: nothing above 400 Hz to measure an
-- attack on, so this must take the full-band fallback path
make("kick", 0.6, 1, function(t)
  return math.sin(2 * math.pi * 55 * t) * env(t, 0.002, 0.09) * 0.9
end)

-- closed hat: pure noise, very fast attack, ~30 ms
make("hat_closed", 0.15, 1, function(t)
  return (math.random() * 2 - 1) * env(t, 0.0003, 0.012)
end)

-- open hat / short cymbal: noise, 1.2 s
make("hat_open", 1.6, 1, function(t)
  return (math.random() * 2 - 1) * env(t, 0.0005, 0.30)
end)

-- snare: 200 Hz tone + noise, 150 ms
make("snare", 0.5, 1, function(t)
  local e = env(t, 0.002, 0.07)
  return (math.sin(2 * math.pi * 200 * t) * 0.5 + (math.random() * 2 - 1) * 0.5) * e
end)

-- soft mallet: 20 ms attack, long tonal tail at 900 Hz
make("soft_mallet", 2.0, 1, function(t)
  return math.sin(2 * math.pi * 900 * t) * env(t, 0.020, 0.55)
end)

-- 808: deep sine, very long
make("808", 3.0, 1, function(t)
  return math.sin(2 * math.pi * 42 * t) * env(t, 0.002, 0.9)
end)

-- reverbed snare: same hit plus a decorrelated stereo tail
make("snare_hall", 2.0, 2, function(t)
  local dry = (math.sin(2 * math.pi * 200 * t) * 0.5 + (math.random() * 2 - 1) * 0.5) * env(t, 0.002, 0.07)
  local tail = (math.random() * 2 - 1) * env(t, 0.001, 0.6) * 0.30
  local tail2 = (math.random() * 2 - 1) * env(t, 0.001, 0.6) * 0.30
  return dry + tail, dry + tail2
end)

-- clicky kick: the beater dominates, so the transient is genuinely fast even
-- though the body is a slow 55 Hz sine
make("kick_clicky", 0.6, 1, function(t)
  local e = env(t, 0.001, 0.07)
  local click = math.exp(-t / 0.0015) * 1.0 * (math.random() * 2 - 1)
  return math.sin(2 * math.pi * 55 * t) * e * 0.6 + click
end)

-- crushed/distorted kick: hard clipped, so crest collapses and HF blooms
make("kick_filthy", 0.6, 1, function(t)
  local v = math.sin(2 * math.pi * 55 * t) * env(t, 0.001, 0.09) * 6
  if v > 0.9 then v = 0.9 elseif v < -0.9 then v = -0.9 end
  return v
end)

-- silence, to check the "unreadable" path
make("silence", 0.5, 1, function() return 0 end)

----------------------------------------------------------------------
-- reaper stub
----------------------------------------------------------------------
local function bit_reverse_fft(re, im, n)
  local j = 0
  for i = 0, n - 2 do
    if i < j then
      re[i], re[j] = re[j], re[i]
      im[i], im[j] = im[j], im[i]
    end
    local m = n // 2
    while m >= 1 and j >= m do
      j = j - m
      m = m // 2
    end
    j = j + m
  end
  local len = 2
  while len <= n do
    local ang = -2 * math.pi / len
    local half = len // 2
    for i = 0, n - 1, len do
      for k = 0, half - 1 do
        local wr = math.cos(ang * k)
        local wi = math.sin(ang * k)
        local a = i + k
        local b = a + half
        local tr = re[b] * wr - im[b] * wi
        local ti = re[b] * wi + im[b] * wr
        re[b] = re[a] - tr
        im[b] = im[a] - ti
        re[a] = re[a] + tr
        im[a] = im[a] + ti
      end
    end
    len = len * 2
  end
end

local function new_array(size)
  local a = {}
  for i = 1, size do a[i] = 0 end
  a.clear = function() for i = 1, size do a[i] = 0 end end
  -- Mimics REAPER's packing as the existing TK scripts read it: bin b at
  -- indices 2b (real) and 2b+1 (imag), 1-based.
  a.fft_real = function(n)
    local re, im = {}, {}
    for i = 0, n - 1 do re[i] = a[i + 1]; im[i] = 0 end
    bit_reverse_fft(re, im, n)
    for i = 1, n do a[i] = 0 end
    a[1] = re[0]
    for b = 1, n // 2 - 1 do
      a[b * 2] = re[b]
      a[b * 2 + 1] = im[b]
    end
    a[n] = re[n // 2]
  end
  return a
end

reaper = {
  new_array = new_array,
  time_precise = function() return os.clock() end,
  GetResourcePath = function() return os.getenv("TEMP") or "." end,
  RecursiveCreateDirectory = function(dir)
    os.execute('mkdir "' .. dir:gsub("/", "\\") .. '" 2>nul')
  end,
  GetPlayState = function() return 0 end,
  PCM_Source_CreateFromFile = function(path) return sources[path] end,
  PCM_Source_Destroy = function() end,
  GetMediaSourceSampleRate = function(s) return s.sr end,
  GetMediaSourceNumChannels = function(s) return s.nch end,
  GetMediaSourceLength = function(s) return s.len, false end,
  PCM_Source_GetPeaks = function(src, peakrate, start_time, nch, count, _, buf)
    local base = count * nch
    local step = src.sr / peakrate
    local start = math.floor(start_time * src.sr)
    for i = 1, count do
      local a = start + math.floor((i - 1) * step) + 1
      local b = start + math.floor(i * step)
      if b < a then b = a end
      for ch = 1, nch do
        local d = src.data[math.min(ch, src.nch)]
        local mx, mn = 0, 0
        local seen = false
        for k = a, math.min(b, src.n) do
          local v = d[k]
          if not seen then mx, mn, seen = v, v, true end
          if v > mx then mx = v end
          if v < mn then mn = v end
        end
        buf[(i - 1) * nch + ch] = mx
        buf[base + (i - 1) * nch + ch] = mn
      end
    end
    return true
  end,
}

----------------------------------------------------------------------
-- run
----------------------------------------------------------------------
math.randomseed(1)

local Analyzer = require("core.analyzer")
local Tags = require("core.tags")

local order = { "kick", "kick_clicky", "808", "kick_filthy", "snare", "snare_hall",
                "hat_closed", "hat_open", "soft_mallet", "silence" }

print(string.format("%-13s %7s %8s %7s %8s %7s %6s %6s   %s",
  "sample", "atk_ms", "decay_ms", "d10/d40", "centroid", "crest", "flat", "width", "tags"))
print(string.rep("-", 112))

local fail = 0
for _, name in ipairs(order) do
  local m = Analyzer.analyze(name)
  if not m then
    print(string.format("%-13s %s", name, "(no signal / unreadable)"))
  else
    local d = Tags.derive(m)
    local L = Tags.derive_labels(d)
    print(string.format("%-13s %7.2f %8.1f %7.3f %8.0f %7.1f %6.3f %6.2f   %s / %s / %s / %s / %s",
      name, m.attack_ms, m.decay_ms, m.decay10_ms / math.max(1, m.decay_ms),
      m.centroid, m.crest_db, m.flat, m.width,
      L.band, L.transient, L.decay, L.tonality, L.space or "-"))
  end
end

print()
print("axes 0..1 (heatmap coordinates)")
print(string.format("%-13s %7s %7s %7s %8s", "sample", "att01", "dec01", "tone01", "space01"))
for _, name in ipairs(order) do
  local d = Tags.derive(Analyzer.analyze(name))
  if d then
    print(string.format("%-13s %7.3f %7.3f %7.3f %8s",
      name, d.att01, d.dec01, d.tone01,
      d.space01 and string.format("%.3f", d.space01) or "- (mono)"))
  end
end

----------------------------------------------------------------------
-- expectations
----------------------------------------------------------------------
local function check(label, ok, got)
  if not ok then
    fail = fail + 1
    print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")")
  end
end

local function labels(name)
  return Tags.derive_labels(Tags.derive(Analyzer.analyze(name)))
end

print()
local k = labels("kick")
check("kick is SUB or LOW", k.band == "SUB" or k.band == "LOW", k.band)
check("round kick decay MEDIUM", k.decay == "MEDIUM", k.decay)
-- A clickless 55 Hz sine has no fast transient to measure, and must not claim
-- one just because its quarter-period is short.
check("round kick transient MEDIUM/SOFT", k.transient == "MEDIUM" or k.transient == "SOFT", k.transient)

local kc = labels("kick_clicky")
check("clicky kick transient HARD/IMPACT", kc.transient == "HARD" or kc.transient == "IMPACT", kc.transient)
check("clicky kick still reads SUB/LOW", kc.band == "SUB" or kc.band == "LOW", kc.band)

local h = labels("hat_closed")
check("closed hat is noise", h.tonality == "NOISE", h.tonality)
check("closed hat decay SHORT", h.decay == "SHORT", h.decay)
check("closed hat is bright", h.band == "HIGH" or h.band == "AIR" or h.band == "HMID", h.band)
check("closed hat transient HARD/IMPACT", h.transient == "HARD" or h.transient == "IMPACT", h.transient)

local ho = labels("hat_open")
check("open hat decay LONG/LEGATO", ho.decay == "LONG" or ho.decay == "LEGATO", ho.decay)

local e = labels("808")
check("808 is SUB", e.band == "SUB", e.band)
check("808 decay LEGATO", e.decay == "LEGATO", e.decay)
check("808 is tonal", e.tonality == "DEFINED" or e.tonality == "PITCHED", e.tonality)

local sm = labels("soft_mallet")
check("mallet transient SOFT", sm.transient == "SOFT", sm.transient)

local sn, sh = labels("snare"), labels("snare_hall")
check("stereo hall snare reads ROOM/HALL/WET", sh.space == "ROOM" or sh.space == "HALL" or sh.space == "WET", sh.space)
check("mono file reports no spatiality at all", sn.space == nil, sn.space)
check("mono file flags space as unknown",
  Tags.derive(Analyzer.analyze("snare")).space_known == false, "known")
check("stereo file flags space as measured",
  Tags.derive(Analyzer.analyze("snare_hall")).space_known == true, "unknown")

check("silence returns nil", Analyzer.analyze("silence") == nil, "not nil")

----------------------------------------------------------------------
-- cache round-trip + job
----------------------------------------------------------------------
Tags.clear_cache()
for _, name in ipairs(order) do Tags.ensure(name) end
Tags.flush()

local before = Tags.get("kick")
Tags.clear_cache()
local job = Tags.new_job(order)
check("job queues every uncached file", job.total == #order, job.total)
while job:step(1000) do end
check("job completes", job.done == true, job.done)
check("job counts the silent file as failed", job.failed == 1, job.failed)
Tags.flush()

-- drop the in-memory copy and read it back from disk
Tags.reload()
local after = Tags.get("kick")
check("cache survives a reload", after ~= nil, "nil")
if after and before then
  check("decay round-trips", math.abs(after.decay_ms - before.decay_ms) < 0.5, after.decay_ms)
  check("bands round-trip", math.abs((after.bands[1] or 0) - (before.bands[1] or 0)) < 0.001, after.bands[1])
  check("7 bands stored", #after.bands == 7, #after.bands)
end
check("analysed count", Tags.count_analyzed(order) == #order, Tags.count_analyzed(order))

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
