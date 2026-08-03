-- Transient detection.
--
-- The reading around it needs REAPER and cannot run here, which is exactly why
-- the detector was split off as arithmetic over an array: the part that decides
-- where a slice goes is the part worth testing, and this is the only way to
-- test it at all.
--
-- The signals below are built by hand, so what a hit looks like is written down
-- rather than assumed.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Peaks = require("core.peaks")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local RATE = 200   -- peaks per second, so one peak is 5 ms

-- A hit: a sharp attack then an exponential tail, which is what a drum looks
-- like to a peak reader.
local function add_hit(amps, at_sec, level, decay_sec)
  local start = math.floor(at_sec * RATE) + 1
  local len = math.floor(decay_sec * RATE)
  for i = 0, len do
    local v = level * math.exp(-3 * (i / math.max(1, len)))
    local idx = start + i
    amps[idx] = math.max(amps[idx] or 0, v)
  end
end

local function silence(seconds)
  local amps = {}
  for i = 1, math.floor(seconds * RATE) do amps[i] = 0.0005 end
  return amps
end

local function times(list)
  local out = {}
  for i, t in ipairs(list) do out[i] = string.format("%.2f", t) end
  return table.concat(out, " ")
end

-- 1. Four evenly spaced hits. The detector must find four, and the first entry
-- is always the start of the file rather than a hit.
print("four hits")
local amps = silence(2.0)
for _, t in ipairs({ 0.0, 0.5, 1.0, 1.5 }) do add_hit(amps, t, 0.9, 0.2) end
local found = Peaks.detect(amps, RATE, 0.5)
print("  " .. times(found))
check("the file start is included", found[1] == 0, found[1])
check("four slices in total", #found == 4, #found)
for i, want in ipairs({ 0.5, 1.0, 1.5 }) do
  check(string.format("hit at %.1f s", want),
    found[i + 1] and math.abs(found[i + 1] - want) < 0.03, found[i + 1])
end

-- 2. One hit is one slice. A decaying tail must not be reported again and
-- again, which is what the retrigger gap is for -- without it a single kick
-- becomes a dozen pads.
print("no retriggering on a tail")
local one = silence(1.0)
add_hit(one, 0.2, 1.0, 0.6)
local single = Peaks.detect(one, RATE, 0.5)
print("  " .. times(single))
check("start plus one hit, no more", #single == 2, #single)

-- 3. The sensitivity slider has to actually do something, in the direction the
-- label implies: more sensitive finds more.
print("sensitivity")
local mixed = silence(2.0)
add_hit(mixed, 0.2, 1.0, 0.15)    -- loud
add_hit(mixed, 0.6, 0.08, 0.15)   -- quiet ghost note
add_hit(mixed, 1.0, 1.0, 0.15)
add_hit(mixed, 1.4, 0.05, 0.15)   -- quieter still
local low = #Peaks.detect(mixed, RATE, 0.1)
local mid = #Peaks.detect(mixed, RATE, 0.5)
local high = #Peaks.detect(mixed, RATE, 0.95)
print(string.format("  sensitivity 0.1 -> %d   0.5 -> %d   0.95 -> %d", low, mid, high))
check("low sensitivity finds the loud ones", low >= 2, low)
check("high sensitivity finds more than low", high > low, high .. " vs " .. low)
check("it never goes backwards", high >= mid and mid >= low, mid)

-- 4. Silence has nothing in it. Reporting hits in an empty file would fill a
-- rack with pads that play nothing.
print("silence")
local quiet = Peaks.detect(silence(2.0), RATE, 0.95)
check("only the file start", #quiet == 1, #quiet)

-- 5. A steady tone is not a series of transients. This is the failure that
-- makes a detector useless on sustained material: it slices a pad into fifty
-- pieces because the level never drops.
print("a steady tone")
local tone = {}
for i = 1, 2 * RATE do tone[i] = 0.5 end
local steady = Peaks.detect(tone, RATE, 0.5)
print(string.format("  %d slices in 2 s of constant level", #steady))
check("almost nothing is found", #steady <= 2, #steady)

-- 6. Loud and quiet versions of the same performance must slice the same way.
-- A fixed threshold would fail this, and it is why the detector compares each
-- peak with its recent average instead.
print("level independence")
local loud = silence(2.0)
local soft = silence(2.0)
for _, t in ipairs({ 0.3, 0.8, 1.3 }) do
  add_hit(loud, t, 0.9, 0.15)
  add_hit(soft, t, 0.12, 0.15)
end
local a, b = Peaks.detect(loud, RATE, 0.6), Peaks.detect(soft, RATE, 0.6)
print(string.format("  loud -> %d   quiet -> %d", #a, #b))
check("the same number of slices", #a == #b, #a .. " vs " .. #b)
if #a == #b then
  local drift = 0
  for i = 1, #a do drift = math.max(drift, math.abs(a[i] - b[i])) end
  check("and in the same places", drift < 0.03, drift)
end

-- 7. Too little to work with must give an answer, not an error.
print("degenerate input")
check("an empty array is handled", #Peaks.detect({}, RATE, 0.5) == 0)
check("a rate of zero is handled", #Peaks.detect({ 1, 1, 1, 1, 1 }, 0, 0.5) == 0)

-- 8. Dense material at the low end, which is the case that made the slider feel
-- broken: a busy break gave dozens of slices even at zero.
--
-- A threshold alone cannot cap it. Between hits the rolling average falls away,
-- so the next hit stands out hugely however strict the ratio is. What bounds
-- the count is the minimum gap between slices, and at zero it has to be wide
-- enough that a four-second loop lands near the sixteen pads a rack has.
print("dense material")
local busy = silence(4.0)
for i = 0, 39 do add_hit(busy, i * 0.1, 0.6 + (i % 3) * 0.15, 0.08) end
local at0 = #Peaks.detect(busy, RATE, 0.0)
local at50 = #Peaks.detect(busy, RATE, 0.5)
local at100 = #Peaks.detect(busy, RATE, 1.0)
print(string.format("  40 hits in 4 s -> sensitivity 0: %d   0.5: %d   1.0: %d", at0, at50, at100))
check("zero gives about a rack's worth, not dozens", at0 <= 20, at0)
check("and still finds something", at0 >= 3, at0)
check("full sensitivity finds most of them", at100 >= 30, at100)
check("the middle sits between the two", at50 >= at0 and at50 <= at100,
  at0 .. "/" .. at50 .. "/" .. at100)

-- The gap has to be a real minimum, or "fewer slices" is only an average and a
-- busy passage still floods the pads.
local low = Peaks.detect(busy, RATE, 0.0)
local closest = math.huge
for i = 2, #low do closest = math.min(closest, low[i] - low[i - 1]) end
print(string.format("  closest two slices at sensitivity 0: %.0f ms", closest * 1000))
check("nothing lands on top of anything else", closest >= 0.2, closest)

-- 9. The outline over part of the file, which is what lets a long loop be read
-- at all: sixty-four slices across one window is a picket fence, sixteen is a
-- row of pads. The range has to actually narrow, or zooming shows the same
-- picture at a different label.
print("windowed outline")
reaper.PCM_Source_CreateFromFile = function() return {} end
reaper.GetMediaSourceLength = function() return 4.0 end
reaper.PCM_Source_Destroy = function() end
reaper.new_array = function(n)
  local a = {}
  for i = 1, n do a[i] = 0 end
  a.clear = function() end
  return a
end
-- A file that is loud only in its second half, so a window over each half must
-- come back different.
reaper.PCM_Source_GetPeaks = function(_, rate, _, _, count, _, buf)
  for i = 1, count do
    local loud = (i > count / 2) and 0.9 or 0.05
    buf[i] = loud
    buf[count + i] = -loud
  end
  return true
end

Peaks.clear()
local whole = Peaks.outline("fake.wav", 32, 0, 1)
local first = Peaks.outline("fake.wav", 32, 0, 0.5)
local second = Peaks.outline("fake.wav", 32, 0.5, 1)
check("all three read", whole and first and second, nil)
if whole and first and second then
  local function mean(o)
    local sum = 0
    for i = 1, o.n do sum = sum + o[i] end
    return sum / o.n
  end
  print(string.format("  whole %.2f | first half %.2f | second half %.2f",
    mean(whole), mean(first), mean(second)))
  check("the quiet half reads quiet", mean(first) < mean(second), mean(first))
  check("the loud half is full scale", mean(second) > 0.9, mean(second))
  check("a window is not the whole file", mean(first) ~= mean(whole), mean(first))
end
Peaks.clear()

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
