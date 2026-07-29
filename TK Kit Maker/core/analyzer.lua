-- Sample analysis: amplitude envelope + frequency spectrum, so every sample can
-- be tagged automatically (core/tags.lua turns these raw numbers into labels).
--
-- Audio is read straight from the file through PCM_Source_GetPeaks -- no item,
-- take or track needed -- and the FFT is REAPER's native fft_real.
--
-- A one-shot is read ONCE, at its own samplerate, and the 1 ms envelope is
-- folded out of those samples here. The obvious split -- a cheap coarse pass
-- for the envelope plus a sample block at the onset -- decodes a short file
-- very nearly twice, because the second read still has to work its way from the
-- start of the file to the onset. Longer material keeps the two-pass route,
-- where holding every sample in memory would cost more than the extra decode:
--   1. coarse envelope, 1 ms grid over the whole file -> peak, decay, tail
--   2. sample block at the onset, ~8k @ samplerate    -> attack, spectrum, width
--
-- Only RAW measurements are returned (and cached); every threshold that turns
-- them into a label lives in core/tags.lua, so the vocabulary can be retuned
-- without re-analysing a library.
--
-- All buffers are module-level and reused: analysing 10k files must not
-- allocate 10k arrays.

local r = reaper
local M = {}

local ENV_RATE     = 1000   -- coarse envelope resolution (Hz) = 1 ms per point
local ENV_MAX_SEC  = 12     -- cap for very long files; longer tails read as "legato"
local FFT_SIZE     = 4096   -- 10.8 Hz per bin @ 44.1k -- enough to split SUB from LOW
local FFT_FRAMES   = 3
local FFT_HOP      = 2048
local PRE_ROLL_S   = 0.005  -- read a little before the onset so the attack is complete
-- Up to this length a file is read in one go. 5 s at 48 kHz stereo is about
-- 960k array entries -- fine to hold, and it covers nearly every one-shot.
local SINGLE_READ_MAX_SEC = 5

-- Band edges follow the 9-axes tag system (SUB .. AIR).
M.BANDS = {
  { id = "sub",  label = "SUB",  lo = 20,    hi = 60 },
  { id = "low",  label = "LOW",  lo = 60,    hi = 120 },
  { id = "lmid", label = "LMID", lo = 120,   hi = 400 },
  { id = "mid",  label = "MID",  lo = 400,   hi = 2000 },
  { id = "hmid", label = "HMID", lo = 2000,  hi = 6000 },
  { id = "high", label = "HIGH", lo = 6000,  hi = 12000 },
  { id = "air",  label = "AIR",  lo = 12000, hi = 20000 },
}
M.BAND_COUNT = #M.BANDS

local ONSET_FLOOR  = 0.08   -- fraction of peak that counts as "the hit started"
local DECAY_FLOOR  = 0.01   -- -40 dB below peak
local EARLY_FLOOR  = 0.3162 -- -10 dB below peak
local DIRECT_MS    = 50     -- window that counts as the direct hit, not the room

-- Attack is measured on a high-passed copy of the onset. A 50 Hz sine cannot
-- physically reach its first peak in under 4 ms, so measuring the raw waveform
-- would call every sub-heavy kick "slow"; what we hear as the transient sits
-- well above that. Two cascaded one-poles (12 dB/oct) keep a pure sub out of
-- the measurement while a broadband click passes untouched -- sources with
-- nothing up there fall back to the full-band envelope, which is right: they
-- have no transient to measure.
local ATTACK_HP_HZ     = 400
local ATTACK_WINDOW_MS = 90
local ATTACK_HOLD_S    = 0.002
local ATTACK_MIN_HP    = 0.05 -- HP peak below this fraction of the full peak = fall back
-- Rise measured between these two fractions of the peak, then scaled back up to
-- a full 0..100% attack. Using the FIRST crossing of each makes it robust on
-- noisy sources, where the single loudest sample lands at a random spot.
local ATTACK_LO_FRAC   = 0.10
local ATTACK_HI_FRAC   = 0.80
local ATTACK_SCALE     = 1 / (ATTACK_HI_FRAC - ATTACK_LO_FRAC)
-- Floor for the fallback. A source with nothing above 400 Hz cannot sound
-- spiky, so its quarter-period (4-5 ms for a 55 Hz kick) must not masquerade as
-- a hard transient -- without this every clickless sub kick reads as HARD.
local ATTACK_BANDLIMIT_MS = 6

-- Reused buffers ------------------------------------------------------------

local arrays = {}
local function scratch_array(name, need)
  local slot = arrays[name]
  if not slot or slot.cap < need then
    if not r.new_array then return nil end
    slot = { buf = r.new_array(need), cap = need }
    arrays[name] = slot
  end
  return slot.buf
end

local env_amp, hull, mag, mono, hp_env = {}, {}, {}, {}, {}

local hann = {}
for i = 1, FFT_SIZE do
  hann[i] = 0.5 - 0.5 * math.cos(2 * math.pi * (i - 1) / (FFT_SIZE - 1))
end

local function clamp01(v)
  if v ~= v then return 0 end -- NaN
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

-- Reading -------------------------------------------------------------------

-- Fills `out` with `count` mono peak-amplitude values (max of |max| and |min|
-- across channels). Returns the number of points, or nil when the block is
-- unreadable or digital silence.
local function read_envelope(src, rate, start_time, nch, count, out, name)
  local buf = scratch_array(name, count * nch * 2)
  if not buf then return nil end
  buf.clear()
  if not r.PCM_Source_GetPeaks(src, rate, start_time, nch, count, 0, buf) then return nil end

  local base = count * nch
  local any = false
  for i = 1, count do
    local hi = 0
    for ch = 1, nch do
      local idx = (i - 1) * nch + ch
      local a = math.abs(buf[idx] or 0)
      local b = math.abs(buf[base + idx] or 0)
      if b > a then a = b end
      if a > hi then hi = a end
    end
    out[i] = hi
    if hi > 0 then any = true end
  end
  if not any then return nil end
  return count
end

-- Reads `count` real samples at the source's own rate (peakrate == samplerate
-- makes GetPeaks hand back the samples themselves). Fills `mono` and returns
-- the mid/side energy split, which is our stereo-width measure.
--
-- Pass `env_out` to have the 1 ms envelope built in the same sweep. Doing it
-- afterwards meant walking every sample of the file a second time, and once the
-- double decode was gone that second walk was a good share of what was left.
--
-- Mono and stereo are handled without the per-channel loop for the same reason:
-- between them they are practically every sample anyone owns.
local function read_samples(src, sr, start_time, nch, count, env_out)
  local buf = scratch_array("blk", count * nch * 2)
  if not buf then return nil end
  buf.clear()
  if not r.PCM_Source_GetPeaks(src, sr, start_time, nch, count, 0, buf) then return nil end

  local mid_e, side_e = 0, 0
  local env_step = env_out and (sr / ENV_RATE) or 0
  local env_n, env_hi, env_edge, env_any = 0, 0, env_step, false

  for i = 1, count do
    local v
    if nch == 1 then
      v = buf[i] or 0
    elseif nch == 2 then
      local j = (i - 1) * 2
      local l = buf[j + 1] or 0
      local rt = buf[j + 2] or 0
      local m = (l + rt) * 0.5
      local s = (l - rt) * 0.5
      mid_e = mid_e + m * m
      side_e = side_e + s * s
      v = m
    else
      local j = (i - 1) * nch
      local sum = 0
      for ch = 1, nch do sum = sum + (buf[j + ch] or 0) end
      v = sum / nch
      local l = buf[j + 1] or 0
      local rt = buf[j + 2] or 0
      local m = (l + rt) * 0.5
      local s = (l - rt) * 0.5
      mid_e = mid_e + m * m
      side_e = side_e + s * s
    end
    mono[i] = v

    if env_out then
      local a = v < 0 and -v or v
      if a > env_hi then env_hi = a end
      if i >= env_edge then
        env_n = env_n + 1
        env_out[env_n] = env_hi
        if env_hi > 0 then env_any = true end
        env_hi = 0
        env_edge = env_edge + env_step
      end
    end
  end

  if env_out and not env_any then return nil end
  return count, mid_e, side_e, env_n
end

-- Measuring -----------------------------------------------------------------

-- Attack time in milliseconds from the high-passed onset, plus the level that
-- measurement was taken at (so the caller can reject it as too quiet).
-- `from` is where in `mono` to start, 1-based.
local function attack_from_block(from, n, sr)
  local win = math.min(n - from + 1, math.floor(ATTACK_WINDOW_MS * sr / 1000))
  if win < 64 then return nil, 0 end

  local coef = 1 / (1 + 2 * math.pi * ATTACK_HP_HZ / sr)
  local hold = math.exp(-1 / (sr * ATTACK_HOLD_S))
  local in1, out1, in2, out2, level = 0, 0, 0, 0, 0
  local peak = 0

  for i = 1, win do
    local x = mono[from + i - 1] or 0
    local y1 = coef * (out1 + x - in1)
    in1, out1 = x, y1
    local y2 = coef * (out2 + y1 - in2)
    in2, out2 = y1, y2
    local m = y2 < 0 and -y2 or y2
    level = m > level and m or level * hold
    hp_env[i] = level
    if level > peak then peak = level end
  end
  if peak <= 0 then return nil, 0 end

  local lo, hi = peak * ATTACK_LO_FRAC, peak * ATTACK_HI_FRAC
  local lo_i, hi_i
  for i = 1, win do
    if not lo_i and hp_env[i] >= lo then lo_i = i end
    if hp_env[i] >= hi then hi_i = i break end
  end
  if not lo_i or not hi_i then return nil, peak end
  return (hi_i - lo_i) * ATTACK_SCALE * 1000 / sr, peak
end

local function analyze_source(src)
  local sr = r.GetMediaSourceSampleRate(src) or 0
  if sr <= 0 then sr = 44100 end
  local nch = r.GetMediaSourceNumChannels(src) or 1
  if nch < 1 then nch = 1 end
  local len, is_qn = r.GetMediaSourceLength(src)
  if is_qn or not len or len <= 0 then return nil end

  -- 1. The envelope. Short files hand over every sample in one read and the
  --    envelope is folded out of them; long ones get the cheap coarse pass.
  local single = len <= SINGLE_READ_MAX_SEC
  local total_samples = math.floor(len * sr)
  if total_samples < 256 then single = false end

  local env_n, mid_e, side_e
  if single then
    local got, me, se, en = read_samples(src, sr, 0, nch, total_samples, env_amp)
    if got and en and en >= 4 then
      mid_e, side_e, env_n = me, se, en
    else
      -- Unreadable, silent, or too short to make an envelope worth the name.
      single = false
    end
  end

  if not single then
    env_n = math.floor(math.min(len, ENV_MAX_SEC) * ENV_RATE)
    if env_n < 8 then env_n = 8 end
    if not read_envelope(src, ENV_RATE, 0, nch, env_n, env_amp, "env") then return nil end
  end

  local peak, peak_i = 0, 1
  for i = 1, env_n do
    if env_amp[i] > peak then peak, peak_i = env_amp[i], i end
  end
  if peak <= 1e-6 then return nil end

  local onset_i = peak_i
  for i = 1, peak_i do
    if env_amp[i] >= peak * ONSET_FLOOR then onset_i = i break end
  end
  local onset_t = (onset_i - 1) / ENV_RATE

  -- Decay measured on a monotone hull, so a dip inside a still-ringing tail
  -- (tremolo, a modulated 808) does not end the decay early.
  hull[env_n] = env_amp[env_n]
  for i = env_n - 1, 1, -1 do
    local a, b = env_amp[i], hull[i + 1]
    hull[i] = a > b and a or b
  end

  local decay_i, early_i = env_n, env_n
  local floor_level, early_level = peak * DECAY_FLOOR, peak * EARLY_FLOOR
  local got_early = false
  for i = peak_i, env_n do
    if not got_early and hull[i] < early_level then
      early_i = i
      got_early = true
    end
    if hull[i] < floor_level then decay_i = i break end
  end
  local decay_ms = (decay_i - peak_i) * 1000 / ENV_RATE
  -- Time to -10 dB. Against the -40 dB decay this gives the SHAPE of the tail:
  -- a plain exponential always lands on 0.25, while a reverberant sample drops
  -- fast and then lingers, pushing the ratio down. That is the one dry/wet cue
  -- that also works on mono material.
  local decay10_ms = (early_i - peak_i) * 1000 / ENV_RATE

  -- Crest factor over the first 200 ms: distorted/limited material sits low.
  local rms_end = math.min(env_n, onset_i + 200)
  local acc, n_acc = 0, 0
  for i = onset_i, rms_end do
    acc = acc + env_amp[i] * env_amp[i]
    n_acc = n_acc + 1
  end
  local rms = n_acc > 0 and math.sqrt(acc / n_acc) or 0
  local crest_db = rms > 1e-9 and (20 * math.log(peak / rms) / math.log(10)) or 24

  -- Energy arriving after the direct hit, relative to the hit itself.
  local direct_end = math.min(env_n, peak_i + math.floor(DIRECT_MS * ENV_RATE / 1000))
  local direct, tail = 0, 0
  for i = peak_i, direct_end do direct = direct + env_amp[i] * env_amp[i] end
  for i = direct_end + 1, math.min(env_n, decay_i) do tail = tail + env_amp[i] * env_amp[i] end
  local tail_ratio = direct > 1e-12 and (tail / direct) or 0

  -- 2. Samples around the onset, for attack, spectrum and width. Already in
  --    hand on the single-read path; otherwise one more read.
  local base, avail
  if single then
    base = math.floor(onset_t * sr)
    avail = total_samples
  else
    local block_t = math.max(0, onset_t - PRE_ROLL_S)
    base = math.floor((onset_t - block_t) * sr)
    avail = base + FFT_SIZE + FFT_HOP * (FFT_FRAMES - 1)
    local got, me, se = read_samples(src, sr, block_t, nch, avail)
    if not got then return nil end
    mid_e, side_e = me, se
  end

  local attack_from = math.max(1, base + 1 - math.floor(PRE_ROLL_S * sr))
  local attack_ms, hp_peak = attack_from_block(attack_from, avail, sr)
  if not attack_ms or hp_peak < peak * ATTACK_MIN_HP then
    -- Nothing meaningful above 400 Hz: fall back to the full-band envelope,
    -- floored, because what it measures there is bandwidth, not attack.
    attack_ms = math.max(peak_i - onset_i, ATTACK_BANDLIMIT_MS)
  end

  local half = math.floor(FFT_SIZE / 2)
  for b = 1, half do mag[b] = 0 end
  local fft = scratch_array("fft", FFT_SIZE)
  if not fft then return nil end

  local frames = 0
  for f = 0, FFT_FRAMES - 1 do
    local off = base + f * FFT_HOP
    local energy = 0
    for i = 1, FFT_SIZE do
      local v = (mono[off + i] or 0) * hann[i]
      fft[i] = v
      energy = energy + v * v
    end
    if energy > 1e-10 then
      fft.fft_real(FFT_SIZE, true)
      for b = 1, half - 1 do
        local re = fft[b * 2] or 0
        local im = fft[b * 2 + 1] or 0
        mag[b] = mag[b] + math.sqrt(re * re + im * im)
      end
      frames = frames + 1
    end
  end
  if frames == 0 then return nil end

  local bin_hz = sr / FFT_SIZE
  local bands = {}
  for i = 1, M.BAND_COUNT do bands[i] = 0 end

  local total, log_sum, log_w = 0, 0, 0
  local geo_sum, arith_sum, flat_n = 0, 0, 0
  local pitch_mag, pitch_hz = 0, 0
  local hf = 0

  for b = 1, half - 1 do
    local freq = b * bin_hz
    local m = mag[b]
    total = total + m

    for i = 1, M.BAND_COUNT do
      local band = M.BANDS[i]
      if freq >= band.lo and freq < band.hi then
        bands[i] = bands[i] + m
        break
      end
    end

    -- Centroid in log-frequency: an octave counts the same everywhere, which
    -- is what makes it usable as an evenly spread SUB..AIR axis.
    if freq >= 30 and freq <= 18000 then
      log_sum = log_sum + m * math.log(freq)
      log_w = log_w + m
    end
    if freq >= 50 and freq <= 16000 then
      geo_sum = geo_sum + math.log(m + 1e-9)
      arith_sum = arith_sum + m
      flat_n = flat_n + 1
    end
    if freq >= 40 and freq <= 2000 and m > pitch_mag then
      pitch_mag, pitch_hz = m, freq
    end
    if freq >= 4000 then hf = hf + m end
  end

  if total <= 0 or log_w <= 0 then return nil end

  local centroid = math.exp(log_sum / log_w)
  local flatness = 0
  if flat_n > 0 and arith_sum > 0 then
    flatness = clamp01(math.exp(geo_sum / flat_n) / (arith_sum / flat_n))
  end

  local band_max = 0
  for i = 1, M.BAND_COUNT do
    bands[i] = bands[i] / total
    if bands[i] > band_max then band_max = bands[i] end
  end
  if band_max > 0 then
    for i = 1, M.BAND_COUNT do bands[i] = bands[i] / band_max end
  end

  local width = 0
  if nch >= 2 and (mid_e + side_e) > 1e-12 then
    width = clamp01(side_e / (mid_e + side_e) * 2)
  end

  return {
    dur        = len,
    nch        = nch,
    attack_ms  = attack_ms,
    decay_ms   = decay_ms,
    decay10_ms = decay10_ms,
    crest_db   = crest_db,
    centroid   = centroid,
    flat       = flatness,
    pitch      = pitch_hz,
    tail_ratio = tail_ratio,
    hf_ratio   = hf / total,
    width      = width,
    bands      = bands,
  }
end

-- Measures one file. Returns a metrics table, or nil when the file cannot be
-- read or holds no signal. Never raises: one broken file must not stop a
-- 10,000 file batch.
function M.analyze(path)
  if not r.PCM_Source_CreateFromFile or not r.PCM_Source_GetPeaks or not r.new_array then
    return nil
  end
  local src = r.PCM_Source_CreateFromFile(path)
  if not src then return nil end
  local ok, res = pcall(analyze_source, src)
  r.PCM_Source_Destroy(src)
  if not ok then return nil end
  return res
end

-- True when the running REAPER build has everything the analyser needs.
function M.available()
  return r.PCM_Source_CreateFromFile ~= nil
    and r.PCM_Source_GetPeaks ~= nil
    and r.new_array ~= nil
end

return M
