-- Reading cue points, and slicing on them.
--
-- This exists because equal division is wrong for the case Kit Maker creates
-- most often. A stitched kit is sixteen one-shots end to end -- a 400 ms kick
-- beside an 80 ms hat -- and cutting it into sixteen equal parts puts not one
-- boundary in the right place. Every pad plays the tail of one sound and the
-- head of the next, and it sounds like the slicer is broken rather than the
-- assumption.
--
-- The boundaries are in the file. The WAVs here are written byte by byte,
-- because the thing under test is the byte reading.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local WavCues = require("core.wavcues")
local Slice = require("core.slice")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end
local function near(a, b, tol)
  return a and math.abs(a - b) <= (tol or 1e-6)
end

local TMP = (os.getenv("TEMP") or "."):gsub("\\", "/") .. "/tkkm_wavcues"
os.execute('mkdir "' .. TMP:gsub("/", "\\") .. '" 2>nul')

local function le32(n) return string.pack("<I4", n) end
local function le16(n) return string.pack("<I2", n) end

-- rate 48000, mono, 16-bit. cues: { {frame, label}, ... }
local function write_wav(path, frames, cues, opts)
  opts = opts or {}
  local fmt = "fmt " .. le32(16) .. le16(1) .. le16(1) .. le32(48000)
    .. le32(48000 * 2) .. le16(2) .. le16(16)
  local data = "data" .. le32(frames * 2) .. string.rep("\0", frames * 2)

  local cue_body = le32(#cues)
  for i, c in ipairs(cues) do
    cue_body = cue_body .. le32(i) .. le32(c[1]) .. "data" .. le32(0) .. le32(0) .. le32(c[1])
  end
  local cue_chunk = "cue " .. le32(#cue_body) .. cue_body

  local adtl = "adtl"
  for i, c in ipairs(cues) do
    if c[2] then
      local text = c[2] .. "\0"
      local body = le32(i) .. text
      if #body % 2 == 1 then body = body .. "\0" end
      adtl = adtl .. "labl" .. le32(4 + #text) .. body
    end
  end
  local list_chunk = "LIST" .. le32(#adtl) .. adtl

  -- A chunk the reader has never heard of, of odd length, placed before the
  -- cues. Skipping it by its declared size without the pad byte would leave
  -- every later chunk one byte out and the cues unreadable.
  local junk = opts.no_junk and "" or ("JUNK" .. le32(5) .. "hello\0")

  local body = "WAVE" .. fmt .. junk ..
    (opts.cues_first and (cue_chunk .. list_chunk .. data) or (data .. cue_chunk .. list_chunk))
  local f = assert(io.open(path, "wb"))
  f:write("RIFF" .. le32(#body) .. body)
  f:close()
end

-- A stitched kit: four one-shots of very different lengths, which is exactly
-- what equal division gets wrong.
local RATE = 48000
local LENGTHS = { 0.40, 0.08, 0.25, 0.60 }   -- kick, hat, snare, crash
local starts, acc = {}, 0
for _, len in ipairs(LENGTHS) do
  starts[#starts + 1] = math.floor(acc * RATE)
  acc = acc + len
end
local TOTAL_FRAMES = math.floor(acc * RATE)
local DUR = acc

print("reading")
local path = TMP .. "/stitched.wav"
write_wav(path, TOTAL_FRAMES, {
  { starts[1], "Kick" }, { starts[2], "Hat" }, { starts[3], "Snare" }, { starts[4], "Crash" },
})
local info, err = WavCues.read(path)
check("the file reads", info ~= nil, err)
check("four cues", info and #info.cues == 4, info and #info.cues)
check("the rate is right", info.rate == RATE, info.rate)
check("the length is right", near(info.duration, DUR, 0.001), info.duration)
check("labels come through", info.cues[1].label == "Kick" and info.cues[4].label == "Crash",
  info.cues[1].label)
print(string.format("  %.2f s, %d cues: %s", info.duration, #info.cues,
  table.concat({ info.cues[1].label, info.cues[2].label, info.cues[3].label, info.cues[4].label }, ", ")))

-- Chunk order is not fixed in the wild, and neither is the presence of chunks
-- nobody has heard of.
write_wav(TMP .. "/cuesfirst.wav", TOTAL_FRAMES, { { starts[1], "A" }, { starts[2], "B" } },
  { cues_first = true })
local other = WavCues.read(TMP .. "/cuesfirst.wav")
check("cues before the audio are found", other and #other.cues == 2, other and #other.cues)

print("slicing on cues")
local plan = Slice.from_cues(info.cues, info.frames, { pads = 16, duration = info.duration })
check("four slices", plan and plan.used == 4, plan and plan.used)
for i, sl in ipairs(plan.slices) do
  local want = LENGTHS[i]
  local got = (sl.stop01 - sl.start01) * DUR
  print(string.format("  %-6s %.3f s   (the file says %.2f s)", tostring(sl.label), got, want))
  check(tostring(sl.label) .. " is its own length", near(got, want, 0.002), got)
end
check("the first starts at zero", plan.slices[1].start01 == 0, plan.slices[1].start01)
check("the last runs to the end", plan.slices[4].stop01 == 1, plan.slices[4].stop01)

-- The point of the whole exercise: equal division would be wrong here, and by
-- a lot. If this ever stops being true the file is a plain loop and cue slicing
-- was never needed for it.
local equal = Slice.plan(DUR, { parts = 4, pads = 16 })
local worst = 0
for i = 1, 4 do
  worst = math.max(worst, math.abs(equal.slices[i].start01 - plan.slices[i].start01) * DUR)
end
print(string.format("  equal division would miss a boundary by up to %.0f ms", worst * 1000))
check("equal division really is wrong here", worst > 0.05, worst)

print("edges")
-- Two cues on the same frame would give a pad with nothing to play.
local same = Slice.from_cues({ { frame = 0 }, { frame = 100 }, { frame = 100 } }, 1000,
  { pads = 16, duration = 1 })
local empty = 0
for _, sl in ipairs(same.slices) do
  if sl.stop01 <= sl.start01 then empty = empty + 1 end
end
check("no slice is empty", empty == 0, empty)

-- Cues out of order in the file must not give slices that run backwards.
local jumbled = Slice.from_cues({ { frame = 800 }, { frame = 0 }, { frame = 400 } }, 1000,
  { pads = 16, duration = 1 })
check("they come back in order",
  jumbled.slices[1].start01 < jumbled.slices[2].start01
    and jumbled.slices[2].start01 < jumbled.slices[3].start01,
  jumbled.slices[1].start01)

print("refusals")
local none = TMP .. "/nocues.wav"
write_wav(none, 1000, {}, { no_junk = true })
local bad, err2 = WavCues.read(none)
check("a file without cues says so", bad == nil, bad)
print("  " .. tostring(err2))

local f = assert(io.open(TMP .. "/notawav.wav", "wb"))
f:write("this is not a RIFF file at all")
f:close()
local bad2, err3 = WavCues.read(TMP .. "/notawav.wav")
check("junk is refused", bad2 == nil, bad2)
print("  " .. tostring(err3))
check("a missing file is refused", WavCues.read(TMP .. "/nope.wav") == nil)

os.remove(path)
os.remove(TMP .. "/cuesfirst.wav")
os.remove(none)
os.remove(TMP .. "/notawav.wav")

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
