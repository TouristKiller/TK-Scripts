-- Note names and export filenames.
--
-- The octave numbering has already drifted once: Kit Maker followed Yamaha
-- (middle C = C3) while REAPER's editor uses C4, so note 36 was called C1 in
-- one half of the program and C2 in the other. Nothing caught it, because
-- nothing tested it. This does.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Naming = require("core.naming")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- 1. the convention itself: REAPER's, so 60 is C4
print("note names")
for _, case in ipairs({
  { note = 36, want = "C2" },   -- the kit base note
  { note = 60, want = "C4" },   -- middle C
  { note = 0,  want = "C-1" },
  { note = 127, want = "G9" },
}) do
  local got = Naming.note_name(case.note)
  print(string.format("  %3d -> %-4s", case.note, got))
  check(case.note .. " is " .. case.want, got == case.want, got)
end

-- 2. every pitch class, in order, within one octave
local expect = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
for i, name in ipairs(expect) do
  local got = Naming.note_name(36 + i - 1)
  check("note " .. (36 + i - 1) .. " starts with " .. name,
    got:sub(1, #name) == name and got:sub(#name + 1) == "2", got)
end

-- 3. an octave up is the same letter, one number higher
check("36 and 48 are both C", Naming.note_name(48) == "C3", Naming.note_name(48))
check("36 and 24 differ by one octave", Naming.note_name(24) == "C1", Naming.note_name(24))

-- 4. filenames, since the note name goes into them
local slot = { number = 1, midi_note = 36, type_label = "Kick" }
local pool = { alias = "Kicks" }
local naming = { prefix_style = "001", include_type = true, note_style = "name", separator = "_" }
local built = Naming.build(slot, "D:/Samples/BD_808_01.wav", pool, naming)
print("filename: " .. built)
check("the filename carries the note name", built:find("C2", 1, true) ~= nil, built)
check("it keeps the extension", built:sub(-4) == ".wav", built)
check("it starts with the padded number", built:sub(1, 3) == "001", built)

-- The pool alias and the slot label both go in, deduped when they are the same
-- word -- so "Kicks" and "Kick" both appear, but "Kick" twice would not.
check("alias and label both appear", built:find("Kicks", 1, true) and built:find("Kick_", 1, true), built)
local same = Naming.build({ number = 2, midi_note = 38, type_label = "Snare" },
  "D:/x/sn.wav", { alias = "Snare" }, naming)
check("a repeated word is not doubled", select(2, same:gsub("Snare", "")) == 1, same)

-- 5. note_style controls whether it is there at all
local by_number = Naming.build(slot, "D:/x/bd.wav", pool,
  { prefix_style = "001", note_style = "number", separator = "_" })
check("note_style=number uses the figure", by_number:find("36", 1, true) ~= nil, by_number)
local without = Naming.build(slot, "D:/x/bd.wav", pool,
  { prefix_style = "001", note_style = "none", separator = "_" })
check("note_style=none leaves it out", without:find("C2", 1, true) == nil, without)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
