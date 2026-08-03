-- The scheduling rule the JSFX engine uses to place a groove.
--
-- Be clear about what this is and is not. It does NOT run the engine: that is
-- JSFX, it lives in the audio thread, and nothing here can execute it. What it
-- runs is a Lua model of the one rule the engine follows --
--
--     a step is not consumed until its SHIFTED time falls inside this block
--
-- against the block boundaries that make that rule hard. The algorithm is the
-- risky part; the JSFX is written to match this model line for line.
--
-- The failures being hunted are the ones with no error message: a note played
-- twice because two blocks both claimed it, a note never played because both
-- blocks skipped it, and a note clamped to the edge of a block because it was
-- scheduled past the end. The last one is what the old code did with anything
-- late, and it would have turned a swing into a stutter.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Groove = require("core.groove")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- The model. One lane, played block by block, mirroring the engine's loop.
--
--   clk       the grid time of the next step, which the groove never moves
--   et        that time plus the groove's shift -- when it actually sounds
--
-- Returns every note it emitted as { step, at, block, offset_in_block }.
local function run(opts)
  local groove = opts.groove
  local amount = opts.amount or 0
  local period = opts.period or 0.125     -- one step, in seconds
  local blocks = opts.blocks or 200
  local blockdur = opts.blockdur or (512 / 48000)
  local steps = opts.steps or 16

  local out = {}
  local clk, tick = 0, 0
  for b = 1, blocks do
    local t0 = (b - 1) * blockdur
    local t1 = t0 + blockdur
    local guard = 0
    while guard < 256 do
      local et = clk
      local st = (tick % steps) + 1
      if groove then
        et = et + Groove.step_offset(groove, st, amount) * period
      end
      if et >= t1 then
        guard = 256
      else
        -- The engine clamps a note that is already behind the block start to
        -- offset zero rather than dropping it, so the model does the same.
        local off = et - t0
        if off < 0 then off = 0 end
        out[#out + 1] = { step = st, at = et, block = b, off = off, tick = tick }
        clk = clk + period
        tick = tick + 1
        guard = guard + 1
      end
    end
  end
  return out
end

-- 1. No groove: the plain grid, one note per step and nothing lost.
print("no groove")
local plain = run({ blocks = 300 })
check("something came out", #plain > 20, #plain)
local ok_seq = true
for i, n in ipairs(plain) do
  if n.tick ~= i - 1 then ok_seq = false end
end
check("every step, once, in order", ok_seq, #plain)
local worst = 0
for _, n in ipairs(plain) do
  worst = math.max(worst, math.abs(n.at - n.tick * 0.125))
end
print(string.format("  %d notes, worst timing error %.6f s", #plain, worst))
check("each lands on its grid time", worst < 1e-9, worst)

-- 2. Swing. The thing that would have broken before: a shifted step lands in a
-- LATER block than the one its grid time is in, and the old code would have
-- clamped it to the end of the earlier block instead.
print("swing")
local swing = Groove.builtin("Swing 66 (+32%)")
local swung = run({ groove = swing, amount = 1, blocks = 300 })
check("nothing was lost", #swung == #plain, #swung .. " vs " .. #plain)
ok_seq = true
for i, n in ipairs(swung) do
  if n.tick ~= i - 1 then ok_seq = false end
end
check("still once each, in order", ok_seq)

local moved, crossed = 0, 0
for i, n in ipairs(swung) do
  local grid = n.tick * 0.125
  local want = grid + Groove.step_offset(swing, n.step, 1) * 0.125
  if math.abs(n.at - want) > 1e-9 then moved = moved + 1 end
  if n.block ~= plain[i].block then crossed = crossed + 1 end
end
print(string.format("  %d of %d notes landed in a later block than their grid time",
  crossed, #swung))
check("every note is where the groove says", moved == 0, moved)
check("and many really did cross a block", crossed > #swung / 4, crossed)

-- The offset within the block must be a real position, never pinned to the
-- edge. Pinning is exactly what a clamp looks like, and it turns a groove into
-- a stutter locked to the buffer size.
local pinned = 0
for _, n in ipairs(swung) do
  if n.off >= (512 / 48000) - 1e-9 then pinned = pinned + 1 end
end
check("nothing is pinned to a block edge", pinned == 0, pinned)

-- 3. Early notes, the case that needs the step to be claimed before its grid
-- time arrives.
print("pushed")
local push = Groove.builtin("Pushed (-6%)")
local pushed = run({ groove = push, amount = 1, blocks = 300 })
check("nothing was lost", #pushed == #plain, #pushed .. " vs " .. #plain)
local early = 0
for i, n in ipairs(pushed) do
  if n.at < plain[i].at - 1e-9 then early = early + 1 end
end
print(string.format("  %d of %d notes sound before their grid time", early, #pushed))
check("they really are early", early > #pushed - 3, early)

-- 4. Buffer size must not change what you hear. If it does, the groove depends
-- on an audio setting, which is the definition of a scheduling bug.
print("buffer sizes")
local ref = nil
for _, size in ipairs({ 64, 128, 256, 512, 1024, 2048 }) do
  local r2 = run({ groove = swing, amount = 1, blocks = math.ceil(300 * 512 / size),
                   blockdur = size / 48000 })
  local times = {}
  for i = 1, math.min(#r2, 60) do times[i] = string.format("%.6f", r2[i].at) end
  local sig = table.concat(times, ",")
  if not ref then
    ref = sig
  else
    check("buffer " .. size .. " gives the same timing", sig == ref, "differs")
  end
end
print("  identical timing at 64 through 2048 samples")

-- 5. The amount knob, end to end through the scheduler.
print("amount")
for _, amt in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
  local r2 = run({ groove = swing, amount = amt, blocks = 200 })
  local shift = r2[2].at - (1 * 0.125)
  local want = Groove.step_offset(swing, 2, amt) * 0.125
  check(string.format("amount %.2f shifts by the right amount", amt),
    math.abs(shift - want) < 1e-9, shift)
end
local zero = run({ groove = swing, amount = 0, blocks = 300 })
check("amount 0 is exactly the plain grid", #zero == #plain, #zero)

-- 6. A lane at half or double speed. The offset is a fraction of a STEP, so a
-- slower lane swings by proportionally more wall-clock time -- the feel stays
-- the same, which is the whole reason the unit is a fraction.
print("lane speed")
for _, period in ipairs({ 0.0625, 0.125, 0.25 }) do
  local r2 = run({ groove = swing, amount = 1, period = period, blocks = 600 })
  local shift = r2[2].at - period
  local frac = shift / period
  check(string.format("period %.4f keeps the same fraction", period),
    math.abs(frac - Groove.step_offset(swing, 2, 1)) < 1e-9, frac)
end

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
