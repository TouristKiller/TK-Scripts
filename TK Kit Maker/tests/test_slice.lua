-- Cutting a loop into pads.
--
-- The failures worth guarding are the quiet ones. A slice that runs past the
-- one before it plays the wrong sound; a start that creeps past its own end
-- gives a silent pad with nothing to explain it; and losing the last fraction
-- of the file to rounding cuts the tail off the final slice, which on a loop is
-- the part that carries it back round.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Slice = require("core.slice")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end
local function near(a, b, tol)
  return a and math.abs(a - b) <= (tol or 1e-9)
end

-- A two-bar loop at 120 BPM is four seconds.
local DUR = 4.0

-- 1. Equal parts, the plain case.
print("equal parts")
local p = Slice.plan(DUR, { mode = "parts", parts = 16, pads = 16 })
check("sixteen slices", p and p.used == 16, p and p.used)
check("each a quarter second", near(p.slice_seconds, 0.25), p.slice_seconds)
check("the first starts at zero", p.slices[1].start01 == 0, p.slices[1].start01)
check("the last ends at the end", p.slices[16].stop01 == 1, p.slices[16].stop01)

-- Back to back with no gap and no overlap. A gap drops part of the loop; an
-- overlap makes a pad play into the next slice's sound.
local seam = 0
for i = 2, #p.slices do
  if not near(p.slices[i].start01, p.slices[i - 1].stop01) then seam = seam + 1 end
end
check("the slices meet exactly", seam == 0, seam)

-- 2. Bars and a division, which is the same arithmetic with the length put
-- back in -- and the reason Sebastian asked: "16 parts" says nothing about how
-- long the loop is.
print("bars and division")
local one_bar = Slice.plan(DUR, { mode = "grid", bars = 1, division = "1/16", pads = 16 })
local four_bar = Slice.plan(DUR, { mode = "grid", bars = 4, division = "1/16", pads = 16 })
check("one bar of 16ths is 16 slices", one_bar.total == 16, one_bar.total)
check("four bars of 16ths is 64", four_bar.total == 64, four_bar.total)
print(string.format("  1 bar -> %d slices of %.0f ms | 4 bars -> %d slices of %.0f ms",
  one_bar.total, one_bar.slice_seconds * 1000, four_bar.total, four_bar.slice_seconds * 1000))
check("more bars means shorter slices", four_bar.slice_seconds < one_bar.slice_seconds)
check("a quarter-note grid gives four", Slice.count({ mode = "grid", bars = 1, division = "1/4" }) == 4)
check("triplets are offered", Slice.count({ mode = "grid", bars = 1, division = "1/8T" }) == 12)

-- 3. More slices than pads. This must be reported, not silently applied: 64
-- slices on 16 pads means you get the first quarter of the loop, and a user who
-- is not told will think the rest vanished.
print("more slices than pads")
check("only what fits is used", four_bar.used == 16, four_bar.used)
check("and it says so", four_bar.truncated == true, four_bar.truncated)
check("one bar is not truncated", one_bar.truncated == false, one_bar.truncated)
print("  " .. Slice.summary(four_bar))

-- Starting further in is what makes the rest of the loop reachable at all.
local second = Slice.plan(DUR, { mode = "grid", bars = 4, division = "1/16", pads = 16, from = 17 })
check("from 17 starts at slice 17", second.slices[1].index == 17, second.slices[1].index)
check("and a quarter of the way in", near(second.slices[1].start01, 0.25), second.slices[1].start01)
check("starting past the end is refused", Slice.plan(DUR, { parts = 8, from = 99 }) == nil)

-- 4. The implied tempo, which is the one number that says whether the bar count
-- was right.
print("implied tempo")
print(string.format("  4 s called 2 bars -> %.1f BPM", Slice.implied_bpm(DUR, 2)))
check("4 s of 2 bars is 120 BPM", near(Slice.implied_bpm(DUR, 2), 120, 0.01), Slice.implied_bpm(DUR, 2))
check("4 s of 1 bar is 60 BPM", near(Slice.implied_bpm(DUR, 1), 60, 0.01), Slice.implied_bpm(DUR, 1))
check("no bars, no tempo", Slice.implied_bpm(DUR, 0) == nil)
check("no length, no tempo", Slice.implied_bpm(0, 2) == nil)

-- 5. The nudge. A loop played with swing does not sit on even divisions, so the
-- slice point has to be movable by hand -- and it must not be movable into
-- nonsense.
print("nudge")
local s = Slice.plan(DUR, { parts = 16, pads = 16 }).slices[5]
local before = s.start01
Slice.nudge(s, -20, DUR)
print(string.format("  -20 ms moved the start from %.4f to %.4f", before, s.start01))
check("it moved earlier", s.start01 < before, s.start01)
check("by 20 ms of the file", near(s.start01, before - 0.02 / DUR, 1e-9), s.start01)

-- The two ends that would break a pad without saying anything.
local first = Slice.plan(DUR, { parts = 16, pads = 16 }).slices[1]
Slice.nudge(first, -5000, DUR)
check("it cannot go before the file", first.start01 >= 0, first.start01)

local last = Slice.plan(DUR, { parts = 16, pads = 16 }).slices[8]
Slice.nudge(last, 100000, DUR)
check("it cannot pass its own end", last.start01 < last.stop01, last.start01)
check("and leaves something to play", (last.stop01 - last.start01) > 0, last.stop01 - last.start01)

-- 6. A file with no length has nothing to cut.
print("refusals")
local bad, err = Slice.plan(0, { parts = 16 })
check("zero length is refused", bad == nil, bad)
print("  " .. tostring(err))

-- 7. Boundaries given in seconds, which is what transient detection produces.
--
-- This caught a real one. from_times hands its positions to from_cues, which
-- was written for cue points and rounded them down -- sensible for a whole
-- number of frames, fatal for 0.25 of a second. Every boundary in a file under
-- a second long collapsed onto zero, so every pad played the whole file and the
-- dialog reported there was nothing to slice.
print("boundaries in seconds")
local sub = Slice.from_times({ 0, 0.25, 0.5, 0.75 }, 1.0, { pads = 16 })
check("four slices", sub and #sub.slices == 4, sub and #sub.slices)
for i, want in ipairs({ 0, 0.25, 0.5, 0.75 }) do
  print(string.format("  slice %d starts at %.3f", i, sub.slices[i].start01))
  check(string.format("slice %d starts where it should", i),
    near(sub.slices[i].start01, want), sub.slices[i].start01)
end
check("they do not all collapse onto the file", sub.slices[2].start01 > 0, sub.slices[2].start01)
check("the last runs to the end", sub.slices[4].stop01 == 1, sub.slices[4].stop01)

-- Fractions below a second have to survive on a longer file too, which is where
-- rounding would have hidden itself: on a ten-second loop only the first slice
-- would have been wrong.
local long = Slice.from_times({ 0, 0.4, 5.0 }, 10.0, { pads = 16 })
check("a short first slice survives", near(long.slices[2].start01, 0.04), long.slices[2].start01)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
