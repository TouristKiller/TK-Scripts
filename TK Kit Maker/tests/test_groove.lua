-- Reading a groove out of a MIDI file.
--
-- The MIDI files here are built byte by byte rather than stubbed, because the
-- thing under test IS the byte reading. A parser checked against a fake parser
-- proves nothing.
--
-- What makes this worth guarding: a groove that loads but is subtly wrong has
-- no symptom. The kit simply feels off, and nobody suspects the file reader.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Groove = require("core.groove")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end
local function near(a, b, tol)
  return a and math.abs(a - b) <= (tol or 0.005)
end

-- Building MIDI ------------------------------------------------------------

local function be(n, bytes)
  local out = {}
  for i = bytes, 1, -1 do
    out[i] = string.char(n % 256)
    n = math.floor(n / 256)
  end
  return table.concat(out)
end

local function vlq(n)
  local out = string.char(n % 128)
  n = math.floor(n / 128)
  while n > 0 do
    out = string.char(128 + (n % 128)) .. out
    n = math.floor(n / 128)
  end
  return out
end

-- notes: { {tick, note, vel}, ... }.  running=true writes the status byte once,
-- which is what real files do and what a naive parser gets wrong.
local function midi_file(ppq, notes, running)
  local body, last, status_written = {}, 0, false
  for _, n in ipairs(notes) do
    body[#body + 1] = vlq(n[1] - last)
    if not (running and status_written) then
      body[#body + 1] = string.char(0x99) -- note on, channel 10
      status_written = true
    end
    body[#body + 1] = string.char(n[2]) .. string.char(n[3])
    last = n[1]
  end
  body[#body + 1] = vlq(0) .. "\255\47\0" -- end of track
  local track = table.concat(body)
  return "MThd" .. be(6, 4) .. be(0, 2) .. be(1, 2) .. be(ppq, 2)
      .. "MTrk" .. be(#track, 4) .. track
end

local PPQ = 480
local STEP = PPQ / 4          -- a 16th note = 120 ticks

-- 1. A dead-straight pattern must read as no groove at all. If this drifts,
-- every groove picks up a bias that nobody asked for.
print("straight")
local straight = {}
for i = 0, 15 do straight[#straight + 1] = { i * STEP, 36, 100 } end
local g = Groove.from_midi(midi_file(PPQ, straight), 16, "straight")
check("it loads", g ~= nil, g)
check("all sixteen steps", g and g.filled == 16, g and g.filled)
local worst = 0
for i = 1, 16 do worst = math.max(worst, math.abs(g.offset[i] or 0)) end
print(string.format("  largest offset on a straight pattern: %.4f of a step", worst))
check("no offset anywhere", worst < 0.0001, worst)

-- 2. Classic swing: every second 16th dragged late. This is the shape the whole
-- feature exists for.
print("swing")
local swung = {}
for i = 0, 15 do
  local drag = (i % 2 == 1) and math.floor(STEP * 0.3) or 0
  swung[#swung + 1] = { i * STEP + drag, 36, 100 }
end
g = Groove.from_midi(midi_file(PPQ, swung), 16, "swing")
print(string.format("  step 1 %+.2f   step 2 %+.2f   step 3 %+.2f   step 4 %+.2f",
  g.offset[1], g.offset[2], g.offset[3], g.offset[4]))
check("downbeats stay put", near(g.offset[1], 0) and near(g.offset[3], 0), g.offset[1])
check("offbeats are late", near(g.offset[2], 0.3) and near(g.offset[4], 0.3), g.offset[2])

-- Offsets are a fraction of a step, so the SAME groove must come out of a file
-- written at a different resolution. Storing ticks would have broken this, and
-- it is why a groove survives a tempo change and a half-speed lane.
local swung_hi = {}
for i = 0, 15 do
  local drag = (i % 2 == 1) and math.floor((PPQ * 2 / 4) * 0.3) or 0
  swung_hi[#swung_hi + 1] = { i * (PPQ * 2 / 4) + drag, 36, 100 }
end
local g2 = Groove.from_midi(midi_file(PPQ * 2, swung_hi), 16, "swing960")
check("resolution does not change the feel", near(g2.offset[2], g.offset[2], 0.01),
  g2 and g2.offset[2])

-- 3. Notes early, which is the case that forces the engine to look ahead.
print("pushed")
local pushed = {}
for i = 0, 15 do
  pushed[#pushed + 1] = { math.max(0, i * STEP - math.floor(STEP * 0.2)), 36, 100 }
end
g = Groove.from_midi(midi_file(PPQ, pushed), 16, "pushed")
check("steps read early", g.offset[5] < -0.15, g.offset[5])
local lead = Groove.max_lead(g, 1.0)
print(string.format("  lead needed at amount 1.0: %.2f of a step", lead))
check("the lead is reported", lead > 0.15, lead)
check("and scales with amount", near(Groove.max_lead(g, 0.5), lead / 2, 0.01),
  Groove.max_lead(g, 0.5))
check("no amount, no lead", Groove.max_lead(g, 0) == 0)

-- 4. The amount knob.
print("amount")
g = Groove.from_midi(midi_file(PPQ, swung), 16, "swing")
check("amount 0 is dead straight", Groove.step_offset(g, 2, 0) == 0)
check("amount 1 is the groove", near(Groove.step_offset(g, 2, 1), 0.3), Groove.step_offset(g, 2, 1))
check("amount 0.5 is half of it", near(Groove.step_offset(g, 2, 0.5), 0.15),
  Groove.step_offset(g, 2, 0.5))
-- A 16-step groove has to drive a 32-step lane, or an 8th groove on 16ths is
-- unusable -- which is most of what these libraries ship.
check("it repeats past its length", near(Groove.step_offset(g, 18, 1), Groove.step_offset(g, 2, 1)),
  Groove.step_offset(g, 18, 1))

-- 5. Velocity travels with the timing: that is half of what makes a groove a
-- groove rather than a delay.
print("velocity")
local dynamic = {}
for i = 0, 15 do
  dynamic[#dynamic + 1] = { i * STEP, 36, (i % 4 == 0) and 120 or 60 }
end
g = Groove.from_midi(midi_file(PPQ, dynamic), 16, "dynamic")
print(string.format("  accent %.2f   ghost %.2f", g.velocity[1], g.velocity[2]))
check("accents read loud", near(g.velocity[1], 1.0, 0.01), g.velocity[1])
check("ghosts read quiet", near(g.velocity[2], 0.5, 0.01), g.velocity[2])
check("amount 0 leaves velocity alone", Groove.step_velocity(g, 2, 0) == 1)
check("amount 1 applies it", near(Groove.step_velocity(g, 2, 1), 0.5), Groove.step_velocity(g, 2, 1))
check("half way is half way", near(Groove.step_velocity(g, 2, 0.5), 0.75),
  Groove.step_velocity(g, 2, 0.5))

-- 6. Real files, and the shapes that break naive parsers.
print("real-world files")
-- Running status: the status byte written once and implied thereafter. Every
-- exporter does it and a parser that assumes one byte per event desynchronises
-- on the second note and reads garbage for the rest of the file.
g = Groove.from_midi(midi_file(PPQ, swung, true), 16, "running")
check("running status parses", g ~= nil and g.filled == 16, g and g.filled)
check("and gives the same groove", near(g.offset[2], 0.3), g and g.offset[2])

-- Note-on at velocity 0 is a note-off. Counted as a hit it would add a phantom
-- note at the end of every sustained one.
local with_offs = {}
for i = 0, 15 do
  with_offs[#with_offs + 1] = { i * STEP, 36, 100 }
  with_offs[#with_offs + 1] = { i * STEP + 60, 36, 0 }
end
g = Groove.from_midi(midi_file(PPQ, with_offs), 16, "withoffs")
check("velocity-0 note-ons are ignored", g.filled == 16, g.filled)
worst = 0
for i = 1, 16 do worst = math.max(worst, math.abs(g.offset[i] or 0)) end
check("and do not drag the feel", worst < 0.0001, worst)

-- Only the first bar. Groove files are often several bars and the later ones
-- are fills, which would average the life out of the groove.
local two_bars = {}
for i = 0, 15 do two_bars[#two_bars + 1] = { i * STEP, 36, 100 } end
for i = 16, 31 do two_bars[#two_bars + 1] = { i * STEP + 90, 36, 100 } end
g = Groove.from_midi(midi_file(PPQ, two_bars), 16, "twobars")
worst = 0
for i = 1, 16 do worst = math.max(worst, math.abs(g.offset[i] or 0)) end
check("the second bar is left out", worst < 0.0001, worst)

-- A sparse groove says nothing about the steps it has no note on, and those
-- must stay silent rather than defaulting to something.
local sparse = { { 0, 36, 100 }, { 4 * STEP, 38, 100 } }
g = Groove.from_midi(midi_file(PPQ, sparse), 16, "sparse")
check("empty steps stay empty", g.filled == 2 and g.offset[2] == nil, g.filled)
check("and read as no offset", Groove.step_offset(g, 2, 1) == 0)

-- 7. Refusing is better than guessing: a groove that loads wrong has no symptom
-- beyond the kit feeling off.
print("refusals")
local bad, err = Groove.from_midi("this is not a MIDI file at all", 16)
check("junk is refused", bad == nil, bad)
print("  " .. tostring(err))
bad, err = Groove.from_midi("MThd" .. be(6, 4) .. be(2, 2) .. be(1, 2) .. be(PPQ, 2), 16)
check("format 2 is refused", bad == nil, bad)
print("  " .. tostring(err))
bad, err = Groove.from_midi(midi_file(PPQ, {}), 16)
check("an empty file is refused", bad == nil, bad)
print("  " .. tostring(err))

-- 8. The built-in grooves. These ship with the script and are the only ones a
-- fresh install has, so "Swing 58" had better mean what an MPC means by it.
print("built-ins")
local names = Groove.builtin_names()
check("there are some", #names >= 5, #names)
check("they load", Groove.builtin(names[1]) ~= nil)
check("an unknown name gives nothing", Groove.builtin("nope") == nil)

-- Swing is a percentage of the 8th-note pair: at S% the second 16th sits S/100
-- of the way through it, so the delay in steps is (S/100)*2-1. Anything else is
-- a made-up number wearing an MPC label.
for _, case in ipairs({
  { name = "Swing 54 (+8%)", want = 0.08 },
  { name = "Swing 58 (+16%)", want = 0.16 },
  { name = "Swing 62 (+24%)", want = 0.24 },
  { name = "Swing 66 (+32%)", want = 0.32 },
}) do
  local b = Groove.builtin(case.name)
  print(string.format("  %-14s offbeat %+.2f of a step", case.name, b.offset[2]))
  check(case.name .. " matches the swing formula", near(b.offset[2], case.want), b.offset[2])
  check(case.name .. " leaves downbeats alone", b.offset[1] == 0 and b.offset[3] == 0, b.offset[1])
end

-- 66% is the triplet feel, which is the whole reason that number is the classic
-- one. If this drifts, the label stops being true.
check("66% is a triplet", near(Groove.builtin("Swing 66 (+32%)").offset[2], 1/3, 0.02),
  Groove.builtin("Swing 66 (+32%)").offset[2])

-- Shuffled 8ths must leave the 16ths straight, or it is just 16th swing again.
local sh = Groove.builtin("Shuffle 8ths (+32%)")
check("8th shuffle moves the off-beat", sh.offset[3] > 0.2, sh.offset[3])
check("and leaves the 16ths alone", sh.offset[2] == 0 and sh.offset[4] == 0, sh.offset[2])

-- Laid back and pushed lean the whole bar, and must lean opposite ways.
local back, fwd = Groove.builtin("Laid back (+6%)"), Groove.builtin("Pushed (-6%)")
check("laid back is behind", back.offset[1] > 0 and back.offset[8] > 0, back.offset[1])
check("pushed is ahead", fwd.offset[1] < 0 and fwd.offset[8] < 0, fwd.offset[1])
check("pushed needs lookahead", Groove.max_lead(fwd, 1) > 0, Groove.max_lead(fwd, 1))
check("laid back needs none", Groove.max_lead(back, 1) == 0, Groove.max_lead(back, 1))

-- The label is generated from the offset, so it cannot describe a feel the
-- groove does not have. A percentage on its own is ambiguous -- 50-75 in Akai
-- and Cubase, 0-100 in Ableton and Reason -- and the shift resolves it.
for _, n in ipairs(Groove.builtin_names()) do
  local b = Groove.builtin(n)
  local stated = tonumber(n:match("([%+%-]?%d+)%%%)$"))
  local peak = 0
  for i = 1, b.steps do
    if math.abs(b.offset[i]) > math.abs(peak) then peak = b.offset[i] end
  end
  check(n .. " says what it does", stated and math.abs(stated - peak * 100) <= 1,
    string.format("label %s, actual %+.0f%%", tostring(stated), peak * 100))
end

-- Built-ins are timing only. Velocity belongs to grooves someone played, and
-- claiming dynamics we did not measure would blur that line.
check("built-ins carry no dynamics", Groove.step_velocity(back, 1, 1) == 1,
  Groove.step_velocity(back, 1, 1))

-- The shape readout, which is what tells a user why a groove appears to do
-- nothing on their pattern. If it disagrees with the offsets it is worse than
-- absent: it would confirm the wrong explanation.
print("shape")
local sw = Groove.builtin("Swing 66 (+32%)")
local shape = Groove.shape(sw)
print("  " .. shape)
check("swing marks the off-beats late", shape:sub(1, 4) == ".>.>", shape:sub(1, 4))
check("laid back marks everything late", Groove.shape(Groove.builtin("Laid back (+6%)")):sub(1, 4) == ">>>>")
check("pushed marks everything early", Groove.shape(Groove.builtin("Pushed (-6%)")):sub(1, 4) == "<<<<")
check("a groove with no offsets shows only dots",
  Groove.shape({ steps = 4, offset = { 0, 0, 0, 0 } }) == "....", Groove.shape({ steps = 4, offset = { 0, 0, 0, 0 } }))

-- Every mark must match the sign of its own offset, or the picture lies.
local marks = shape:gsub(" ", "")
local wrong = 0
for i = 1, sw.steps do
  local m = marks:sub(i, i)
  local o = sw.offset[i] or 0
  local want = (o > 0.001 and ">") or (o < -0.001 and "<") or "."
  if m ~= want then wrong = wrong + 1 end
end
check("every mark matches its offset", wrong == 0, wrong)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
