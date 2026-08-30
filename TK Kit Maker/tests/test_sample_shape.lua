local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Shape = require("core.sample_shape")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local kind = Shape.from_text("Kick 01.wav", "Drums")
check("one instrument is a one-shot", kind == "oneshot", kind)
kind = Shape.from_text("Kick Snare Loop.wav", "Drums")
check("multiple instruments are a loop", kind == "loop", kind)
kind = Shape.from_text("Mystery.wav", "Bass Loops")
check("folder names are used", kind == "loop", kind)
kind = Shape.from_bars(2, 120)
check("four beats make a loop", kind == "loop", kind)
check("off-grid length stays unknown", Shape.from_bars(2.31, 120) == nil)

local shot = {}
for i = 1, 400 do shot[i] = i <= 20 and (1 - (i - 1) / 20) or 0 end
local shot_shape = Shape.measure_envelope(shot, 200, 2)
kind = Shape.from_shape(shot_shape)
check("one decaying attack is a one-shot", kind == "oneshot", kind)
for i = 401, 800 do shot[i] = 1 end
local bounded_shape = Shape.measure_envelope(shot, 200, 2, {}, 400)
kind = Shape.from_shape(bounded_shape)
check("used length ignores stale buffer tail", kind == "oneshot", kind)

local loop = {}
for i = 1, 800 do
  local phase = (i - 1) % 100
  loop[i] = phase < 12 and (1 - phase / 12) or 0.08
end
local loop_shape = Shape.measure_envelope(loop, 200, 4)
kind = Shape.from_shape(loop_shape)
check("regular spread attacks make a loop", kind == "loop", kind)

local metrics = { dur = 4, bpm = 120, shape = loop_shape }
kind = Shape.classify("Kick.wav", metrics)
check("decisive shape outranks the filename", kind == "loop", kind)
check("strict filtering excludes unknown", not Shape.matches("Mystery.wav", "oneshot", nil, false))
check("browser filtering may retain unknown", Shape.matches("Mystery.wav", "oneshot", nil, true))

print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))
TEST_FAILED = fail
