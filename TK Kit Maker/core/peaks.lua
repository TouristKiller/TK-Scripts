-- Reading a file's shape: an outline to draw, and where the hits are.
--
-- Two jobs that both start from PCM_Source_GetPeaks, kept in one place because
-- they want the same cache. Drawing a waveform and finding transients are the
-- same read at different resolutions.
--
-- The detector is the one from TK Media Browser, deliberately. It has been
-- tuned by use, and more to the point a sensitivity slider that behaves
-- differently in two of the same author's scripts is worse than one that is
-- slightly off in both.
--
-- The decision that matters here is the split: `detect` is pure arithmetic over
-- an array of amplitudes and can be tested against a signal built by hand,
-- while the reading around it cannot be tested at all outside REAPER. Keeping
-- the logic on the testable side of that line is the whole point.

local r = reaper
local M = {}

M.PEAK_RATE = 200          -- peaks per second, as in TK Media Browser
M.MAX_PEAKS = 200000

local outline_cache = {}
local amp_cache = {}

-- Amplitudes at PEAK_RATE, one per peak, as max(|high|, |low|).
local function read_amps(path)
  local hit = amp_cache[path]
  if hit then return hit.amps, hit.rate, hit.length end
  if not r.PCM_Source_CreateFromFile or not r.PCM_Source_GetPeaks then return nil end

  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return nil end
  local length = r.GetMediaSourceLength(source) or 0
  if length <= 0 then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    return nil
  end

  local rate = M.PEAK_RATE
  local count = math.floor(length * rate)
  if count > M.MAX_PEAKS then
    rate = math.max(50, math.floor(M.MAX_PEAKS / length))
    count = math.floor(length * rate)
  end
  if count < 4 then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    return nil
  end

  local buf = r.new_array(count * 2)
  buf.clear()
  local ok = r.PCM_Source_GetPeaks(source, rate, 0, 1, count, 0, buf)
  if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
  if not ok then return nil end

  local amps = {}
  for i = 1, count do
    local hi = math.abs(buf[i] or 0)
    local lo = math.abs(buf[count + i] or 0)
    amps[i] = (hi > lo) and hi or lo
  end

  amp_cache[path] = { amps = amps, rate = rate, length = length }
  return amps, rate, length
end

-- Where the hits are, in seconds.
--
-- A peak counts as an onset when it stands out from the recent average rather
-- than when it passes a fixed level, which is what lets one setting work on a
-- quiet loop and a loud one. The retrigger gap stops a single hit being
-- reported several times as it decays.
--
-- Pure: hand it an array and it does not care where the array came from.
function M.detect(amps, rate, sensitivity)
  local total = #amps
  if total < 4 or not rate or rate <= 0 then return {} end

  local sens = math.max(0, math.min(1, tonumber(sensitivity) or 0.5))
  local thresh_factor = 0.05 + (1 - sens) * 2.4
  local abs_floor = 0.005 + (1 - sens) * 0.08

  local avg_window = math.max(5, math.floor(rate * 0.05))

  -- The retrigger gap scales with the setting, and this is what actually makes
  -- the low end usable. TK Media Browser holds it at 50 ms, which caps nothing:
  -- twenty slices a second is still eighty on a four-second loop, so turning
  -- the sensitivity down changed which hits were found but hardly how many. A
  -- threshold cannot fix that on dense material, because the rolling average
  -- falls away between hits and makes every one of them look enormous.
  --
  -- Widening the gap does fix it: at 0 nothing lands within 250 ms of the last,
  -- so a four-second loop yields about sixteen -- which is the number of pads,
  -- and no accident.
  local retrigger_sec = 0.05 + (1 - sens) * 0.20
  local retrigger = math.max(4, math.floor(rate * retrigger_sec))

  -- The file always starts a slice, whether or not it opens on a transient.
  --
  -- And that boundary counts towards the spacing, which it did not before: a
  -- loop opening with a hit at 100 ms would get its own slice regardless of the
  -- gap, leaving a stub of a first pad next to fifteen full-length ones. It is
  -- a boundary like any other and has to hold the next one off just the same.
  local out = { 0 }
  local last = 1
  local sum, n = 0, 0

  for i = 1, total do
    local cur = amps[i]
    if i > avg_window then
      sum = sum - (amps[i - avg_window] or 0)
      n = n - 1
    end
    sum = sum + cur
    n = n + 1
    local avg = (n > 0) and (sum / n) or 0

    if (i - last) >= retrigger and cur > abs_floor and cur > avg * (1 + thresh_factor) then
      local t = (i - 1) / rate
      -- Anything in the first 20 ms is the same attack the file opens with.
      if t > 0.02 then
        out[#out + 1] = t
        last = i
      end
    end
  end
  return out
end

-- Transients of a file, in seconds. Nil when the file cannot be read at all,
-- which is different from a file with no transients in it.
function M.transients(path, sensitivity)
  local amps, rate, length = read_amps(path)
  if not amps then return nil end
  return M.detect(amps, rate, sensitivity), length
end

-- A drawable outline: `buckets` pairs of min/max, already scaled to 0..1.
--
-- Built at the width it will be drawn at and cached on that width, because a
-- waveform resampled from the wrong number of buckets either loses its peaks or
-- wastes the work.
-- `from01`/`to01` narrow it to part of the file, which is what makes a long
-- loop readable: sixty-four slices across one window are a picket fence, while
-- the same sixteen across the same window are pads you can aim at.
function M.outline(path, buckets, from01, to01)
  buckets = math.max(8, math.floor(tonumber(buckets) or 256))
  from01 = math.max(0, math.min(1, tonumber(from01) or 0))
  to01 = math.max(from01 + 0.0001, math.min(1, tonumber(to01) or 1))
  local key = string.format("%s|%d|%.5f|%.5f", path, buckets, from01, to01)
  local hit = outline_cache[key]
  if hit then return hit end

  local amps, _, length = read_amps(path)
  if not amps then return nil end

  local all = #amps
  local lo = math.floor(from01 * all)
  local hi = math.ceil(to01 * all)
  local total = math.max(1, hi - lo)

  local out = { n = buckets, length = length, peak = 0 }
  for b = 1, buckets do
    local from = lo + math.floor((b - 1) * total / buckets) + 1
    local to = math.max(from, lo + math.floor(b * total / buckets))
    local hi = 0
    for i = from, to do
      local a = amps[i] or 0
      if a > hi then hi = a end
    end
    out[b] = hi
    if hi > out.peak then out.peak = hi end
  end

  -- Normalised against the WHOLE file, not against the window.
  --
  -- Scaling is worth doing at all because a quiet file should still fill the
  -- box rather than look like silence with the markers floating in it. But
  -- scaling each window to its own peak makes the same audio change height
  -- depending on how far you are zoomed in, so a quiet passage would look loud
  -- the moment you looked at it closely -- which is the opposite of what a
  -- waveform is for.
  local file_peak = 0
  for i = 1, all do
    local a = amps[i] or 0
    if a > file_peak then file_peak = a end
  end
  if file_peak > 0 then
    for b = 1, buckets do out[b] = out[b] / file_peak end
  end
  out.peak = file_peak

  outline_cache[key] = out
  return out
end

function M.forget(path)
  amp_cache[path] = nil
  for key in pairs(outline_cache) do
    if key:sub(1, #path) == path then outline_cache[key] = nil end
  end
end

function M.clear()
  outline_cache = {}
  amp_cache = {}
end

return M
