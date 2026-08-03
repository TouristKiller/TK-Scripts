-- Finding RS5K's parameters by name.
--
-- The list below is ReaSamplOmatic5000's real one, in order. It matters that it
-- is the real one, because it contains the trap:
--
--     Sample start offset    a fraction of the file, 0.000
--     Loop start offset      a time, 0.00 ms
--
-- Both end in "start offset". A loose search finds whichever comes first, and
-- today that is the right one -- by luck, not by design. Were the order ever to
-- change, slicing would write a fraction into a millisecond field: the slice
-- would not move, no error would be raised, and the loop point would quietly
-- shift instead.
--
-- Setting the wrong parameter is the whole failure mode here, so the test feeds
-- in the real names and insists on the right index.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

local PARAMS = {
  "Volume", "Pan", "Gain for minimum velocity",
  "Note range start", "Note range end",
  "Pitch for start note", "Pitch for end note",
  "MIDI channel", "Max voices", "Attack", "Release",
  "Obey note-offs", "Loop (requires note-offs)",
  "Sample start offset", "Sample end offset",
  "Pitch adjust", "Pitchbend range",
  "Minimum velocity", "Maximum velocity", "Probability of hitting",
  "Round-robin mode", "Filter played notes",
  "Crossfade loop length", "Loop start offset",
  "Decay", "Sustain", "Release (note-off)",
  "Use note-off release override", "Legacy voice re-use mode", "Portamento",
}

local set = {}
reaper = {
  TrackFX_GetNumParams = function() return #PARAMS end,
  TrackFX_GetParamName = function(_, _, i) return true, PARAMS[i + 1] end,
  TrackFX_SetParamNormalized = function(_, _, idx, v) set[#set + 1] = { idx = idx, v = v } end,
  TrackFX_GetParamNormalized = function(_, _, idx) return idx == 14 and 0.25 or 0.75 end,
  TrackFX_GetCount = function() return 0 end,
  TrackFX_GetFXName = function() return "VSTi: ReaSamplOmatic5000 (Cockos)" end,
}

local RS5K = require("core.rs5k")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- Indices are 0-based. Counting the list above: "Sample start offset" is the
-- fourteenth name, so index 13, and "Loop start offset" the twenty-fourth.
local WANT_START, WANT_END, LOOP_START = 13, 14, 23

print("names to indices")
print(string.format("  Sample start offset = %d | Sample end offset = %d | Loop start offset = %d",
  WANT_START, WANT_END, LOOP_START))
check("sample start is found",
  RS5K.param_index({}, 0, "sample start offset", "start offs") == WANT_START,
  RS5K.param_index({}, 0, "sample start offset", "start offs"))
check("sample end is found",
  RS5K.param_index({}, 1, "sample end offset", "end offs") == WANT_END,
  RS5K.param_index({}, 1, "sample end offset", "end offs"))

-- The trap, and it has to be set up deliberately. In RS5K's real order the
-- sample parameter already comes first, so a plain search finds the right one
-- by accident and proves nothing. Swapping the two is what a future version
-- could do, and only then does it become clear what is actually protecting us.
local shuffled = {}
for i, n in ipairs(PARAMS) do shuffled[i] = n end
shuffled[24], shuffled[14] = shuffled[14], shuffled[24]  -- loop start now comes first
reaper.TrackFX_GetParamName = function(_, _, i) return true, shuffled[i + 1] end

-- With the exact name available, the order must not matter at all.
check("the exact name wins over position",
  RS5K.param_index({}, 3, "sample start offset", "start offs") == 23,
  RS5K.param_index({}, 3, "sample start offset", "start offs"))

-- And with only the loose term to go on -- a renamed or older RS5K -- it must
-- still refuse the loop parameter rather than take the first thing that
-- matches. This is the check the "loop" exclusion exists for; without it the
-- answer here is 13, the loop parameter, and a fraction goes into a field
-- measured in milliseconds.
check("a loose search still refuses the loop parameter",
  RS5K.param_index({}, 4, "no such name", "start offs") ~= 13,
  RS5K.param_index({}, 4, "no such name", "start offs"))

reaper.TrackFX_GetParamName = function(_, _, i) return true, PARAMS[i + 1] end

print("setting a range")
set = {}
local ok, err = RS5K.set_range({}, 10, 0.25, 0.5)
check("it succeeds", ok == true, err)
check("two parameters were set", #set == 2, #set)
-- End before start: moving the start past the old end would be clamped by the
-- plugin and the pad would come out silent.
check("the end is set first", set[1].idx == WANT_END, set[1].idx)
check("then the start", set[2].idx == WANT_START, set[2].idx)
check("with the values asked for", set[1].v == 0.5 and set[2].v == 0.25,
  tostring(set[1].v) .. "/" .. tostring(set[2].v))

print("refusals")
local ok2, err2 = RS5K.set_range({}, 11, 0.6, 0.6)
check("a zero-length slice is refused", ok2 == false, ok2)
print("  " .. tostring(err2))
local ok3, err3 = RS5K.set_range({}, 12, 0.8, 0.2)
check("a backwards slice is refused", ok3 == false, ok3)

-- A plugin without these parameters must say so rather than half-work.
reaper.TrackFX_GetNumParams = function() return 2 end
reaper.TrackFX_GetParamName = function(_, _, i) return true, ({ "Volume", "Pan" })[i + 1] end
local ok4, err4 = RS5K.set_range({}, 99, 0, 1)
check("a sampler without the parameters is refused", ok4 == false, ok4)
print("  " .. tostring(err4))

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
