-- Writing a pad's trimmed region out as its own WAV.
--
-- The failure this guards against is a kit that is right in REAPER and wrong
-- everywhere else. On a pad a slice is two RS5K offsets, so a sixteen-pad
-- chop of one loop plays perfectly -- and "Save kit" used to copy the whole
-- loop sixteen times. Nothing warns you. You find out when the kit is loaded
-- somewhere that has no offsets to read, and every pad plays the whole break.
--
-- The other failure is subtler and worse: a cut that lands mid-frame. The file
-- still opens, still plays, and from that byte onward the channels are swapped
-- and the samples are shredded.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {}

local Stitcher = require("core.stitcher")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local TMP = (os.getenv("TEMP") or os.getenv("TMP") or "."):gsub("\\", "/") .. "/tk_kitmaker_slicetest"
os.execute('mkdir "' .. TMP:gsub("/", "\\") .. '" 2>nul')

-- --------------------------------------------------------------------------
-- Building files to slice, and reading back what came out
-- --------------------------------------------------------------------------

-- Every frame is filled with its own frame number, so a misaligned or
-- misplaced cut is visible as a wrong number rather than as vague noise.
local function make_wav(name, channels, bits, rate, frames, format)
  format = format or 1
  local bytes = math.floor(bits / 8)
  local out = {}
  for i = 0, frames - 1 do
    for c = 1, channels do
      out[#out + 1] = string.pack("<I" .. bytes, (i * 10 + c) % (256 ^ bytes))
    end
  end
  local data = table.concat(out)
  local block = channels * bytes
  local fmt = string.pack("<I2I2I4I4I2I2", format, channels, rate, rate * block, block, bits)
  local body = "WAVE" .. "fmt " .. string.pack("<I4", #fmt) .. fmt
             .. "data" .. string.pack("<I4", #data) .. data
  if #data % 2 == 1 then body = body .. "\0" end
  local path = TMP .. "/" .. name
  local f = assert(io.open(path, "wb"))
  f:write("RIFF" .. string.pack("<I4", #body) .. body)
  f:close()
  return path, data
end

-- Deliberately not the stitcher's own reader: a header this parses is a header
-- something else can parse too.
local function parse(path)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open" end
  local all = f:read("a")
  f:close()
  if all:sub(1, 4) ~= "RIFF" or all:sub(9, 12) ~= "WAVE" then return nil, "not a WAV" end
  local declared = string.unpack("<I4", all, 5)
  local out = { size_field = declared, file_bytes = #all }
  local pos = 13
  while pos + 8 <= #all + 1 do
    local id = all:sub(pos, pos + 3)
    local size = string.unpack("<I4", all, pos + 4)
    local body = all:sub(pos + 8, pos + 7 + size)
    if id == "fmt " then
      out.format, out.channels, out.rate, _, out.block, out.bits =
        string.unpack("<I2I2I4I4I2I2", body)
      out.fmt_bytes = size
    elseif id == "data" then
      out.data = body
    end
    pos = pos + 8 + size + (size % 2)
  end
  return out
end

-- --------------------------------------------------------------------------
-- 1. The ordinary case: a middle slice of a stereo file
-- --------------------------------------------------------------------------
print("a slice out of the middle")
local src, whole = make_wav("stereo16.wav", 2, 16, 44100, 1000)
local dest = TMP .. "/mid.wav"
local ok, err = Stitcher.write_slice(src, dest, 0.25, 0.5)
check("it writes", ok, err)

-- What it reports back is what the sources log prints. A wrong number here is
-- the quietest failure of the lot: the audio is fine, and the log that says
-- where the slice came from is lying.
local info = ok and err or {}
check("it reports the frames written", info.frames == 250, info.frames)
check("and the duration", info.seconds and math.abs(info.seconds - 250 / 44100) < 1e-9,
  info.seconds)
check("and where in the source it started",
  info.start_seconds and math.abs(info.start_seconds - 250 / 44100) < 1e-9, info.start_seconds)
check("and how long the source was",
  info.source_seconds and math.abs(info.source_seconds - 1000 / 44100) < 1e-9,
  info.source_seconds)

local got = parse(dest)
check("and the result is a readable WAV", got ~= nil, err)
check("the sample rate is kept", got.rate == 44100, got.rate)
check("the channel count is kept", got.channels == 2, got.channels)
check("the bit depth is kept", got.bits == 16, got.bits)
check("it is still PCM", got.format == 1, got.format)
check("a quarter of the frames came through", #got.data == 250 * 4, #got.data)
check("and they are the right quarter", got.data == whole:sub(250 * 4 + 1, 500 * 4))

check("the RIFF size field matches the file", got.size_field == got.file_bytes - 8,
  got.size_field .. " vs " .. (got.file_bytes - 8))

-- Slicing what was just written proves the stitcher can read its own output --
-- otherwise a saved kit could not be stitched or re-sliced afterwards.
local again = TMP .. "/mid2.wav"
check("the stitcher can read it back", Stitcher.write_slice(dest, again, 0, 1))
check("unchanged", parse(again).data == got.data)

-- --------------------------------------------------------------------------
-- 2. Frame alignment. This is the one that corrupts audio silently.
-- --------------------------------------------------------------------------
print("cuts land on frame boundaries")
local src3, whole3 = make_wav("stereo24.wav", 2, 24, 48000, 997)
for _, at in ipairs({ 0.1, 0.333, 0.5, 0.6667, 0.9 }) do
  local d = TMP .. "/al.wav"
  assert(Stitcher.write_slice(src3, d, at, 1))
  local g = parse(d)
  check("a cut at " .. at .. " is a whole number of frames", #g.data % 6 == 0, #g.data)
  local from = math.floor(at * 997) * 6
  check("and starts where it should", g.data == whole3:sub(from + 1, #whole3), #g.data)
end

-- --------------------------------------------------------------------------
-- 3. Odd byte counts. A data chunk of odd length needs a pad byte, or every
--    chunk after it is misread -- and RIFF sizes must still add up.
-- --------------------------------------------------------------------------
print("odd lengths stay legal")
-- 8-bit mono, and a count chosen so the slice really is an odd number of
-- bytes. With an even one this whole section proves nothing.
local src8 = make_wav("mono8.wav", 1, 8, 22050, 503)
local d8 = TMP .. "/odd.wav"
assert(Stitcher.write_slice(src8, d8, 0, 0.5))
local g8 = parse(d8)
check("the slice is an odd length", #g8.data % 2 == 1, #g8.data)
check("the frames are there", #g8.data == 251, #g8.data)
check("the file is padded to an even length", g8.file_bytes % 2 == 0, g8.file_bytes)

-- The pad is a zero byte. Anything else is a stray sample at the end of the
-- file, and in 8-bit unsigned audio a space is not silence -- it is a click.
local rf = assert(io.open(d8, "rb"))
local rawbytes = rf:read("a")
rf:close()
check("padded with a zero byte, not whitespace", rawbytes:sub(-1) == string.char(0),
  string.byte(rawbytes:sub(-1)))

check("and the size field still matches", g8.size_field == g8.file_bytes - 8,
  g8.size_field .. " vs " .. (g8.file_bytes - 8))

-- --------------------------------------------------------------------------
-- 4. A full range must be a faithful copy, not a re-encode. This is the case
--    that runs for every untrimmed pad in every saved kit.
-- --------------------------------------------------------------------------
print("the whole file")
local srcf, wholef = make_wav("float32.wav", 2, 32, 96000, 300, 3)
local df = TMP .. "/full.wav"
assert(Stitcher.write_slice(srcf, df, 0, 1))
local gf = parse(df)
check("every byte survives", gf.data == wholef, #gf.data)
check("float stays float", gf.format == 3, gf.format)
check("96k stays 96k", gf.rate == 96000, gf.rate)

-- --------------------------------------------------------------------------
-- 5. Refusals. Each of these must fail loudly, because the caller falls back
--    to copying the whole file -- a wrong "true" writes a broken sample.
-- --------------------------------------------------------------------------
print("what it refuses")
local bad = TMP .. "/bad.wav"

check("an inverted range", not Stitcher.write_slice(src, bad, 0.8, 0.2))
check("an empty range", not Stitcher.write_slice(src, bad, 0.5, 0.5))
check("a missing file", not Stitcher.write_slice(TMP .. "/nope.wav", bad, 0, 1))

local nf = assert(io.open(TMP .. "/notawav.mp3", "wb"))
nf:write("ID3\4\0\0\0\0\0\0not audio this program understands")
nf:close()
check("a file that is not a WAV", not Stitcher.write_slice(TMP .. "/notawav.mp3", bad, 0, 1))

-- A range so tight it contains no whole frame. Rounding both ends down would
-- otherwise produce a 0-byte data chunk and call it a success.
local tiny = TMP .. "/tiny.wav"
check("a range shorter than one frame", not Stitcher.write_slice(src, tiny, 0.5, 0.5000001))

local _, refusal = Stitcher.write_slice(src, bad, 0.8, 0.2)
check("and it says why", type(refusal) == "string" and #refusal > 0, refusal)

-- Out-of-range numbers are clamped rather than refused: an RS5K end offset can
-- read back as a hair over 1.0, and that must not cost the pad its slice.
print("clamping")
local cl = TMP .. "/clamp.wav"
check("past the end still works", Stitcher.write_slice(src, cl, 0.5, 1.000001))
check("and stops at the end", #parse(cl).data == 500 * 4, #parse(cl).data)
check("before the start still works", Stitcher.write_slice(src, cl, -0.2, 0.5))
check("and starts at the start", #parse(cl).data == 500 * 4, #parse(cl).data)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
