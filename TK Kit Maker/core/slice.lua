-- Cutting a loop into pads.
--
-- Nothing is written to disk. One file goes onto every pad and each RS5K gets
-- its own start and end offset, which is how a hardware sampler has always done
-- it and buys three things at once:
--
--   * it is instant, and costs no disk
--   * the slice points stay adjustable afterwards, because they are parameters
--     rather than files
--   * "sample offset per pad" is not a second feature -- it is the same knob,
--     which matters because a loop with swing never slices exactly on the grid
--
-- Two ways to say how many pieces, and they end up in the same place. "16 equal
-- parts" ignores how long the loop is, so a one-bar and a four-bar loop both
-- come out in sixteen; saying "4 bars at 1/16" gives sixty-four and means
-- something musical. The second is the same arithmetic with the bar count put
-- back in.

local M = {}

M.MAX_SLICES = 128

-- The divisions a bar can be cut into, as steps per bar.
M.DIVISIONS = {
  { label = "1/4",  per_bar = 4 },
  { label = "1/8",  per_bar = 8 },
  { label = "1/8T", per_bar = 12 },
  { label = "1/16", per_bar = 16 },
  { label = "1/16T", per_bar = 24 },
  { label = "1/32", per_bar = 32 },
}

function M.division_by_label(label)
  for _, d in ipairs(M.DIVISIONS) do
    if d.label == label then return d end
  end
  return nil
end

-- How many pieces a set of options asks for, before anything is clamped to the
-- number of pads there are.
function M.count(opts)
  opts = opts or {}
  if opts.mode == "grid" then
    local bars = math.max(1, math.floor(tonumber(opts.bars) or 1))
    local div = M.division_by_label(opts.division) or M.DIVISIONS[4]
    return bars * div.per_bar
  end
  return math.max(2, math.floor(tonumber(opts.parts) or 16))
end

-- The tempo the loop must be at for the bar count to be true.
--
-- Worth showing rather than hiding: it is the one number that says whether the
-- bar count is right. Ask for 2 bars and see 174 BPM on something that is
-- plainly 87, and the loop is one bar, or it has silence on the end.
function M.implied_bpm(duration, bars)
  duration = tonumber(duration) or 0
  bars = math.floor(tonumber(bars) or 0)
  if duration <= 0 or bars < 1 then return nil end
  return (bars * 4 * 60) / duration
end

-- The slices themselves.
--
-- `pads` clamps to what the rack can hold. It is reported rather than silently
-- applied, because "4 bars at 1/16" asks for 64 pieces and a rack has 16 -- the
-- user has to know they are getting the first quarter of the loop, not all of
-- it in miniature.
--
-- `from` starts at a later slice, which is what makes the rest of that loop
-- reachable: the same call with from=17 fills the pads with the second bar.
function M.plan(duration, opts)
  duration = tonumber(duration) or 0
  if duration <= 0 then return nil, "the sample has no length" end

  opts = opts or {}
  local total = math.min(M.count(opts), M.MAX_SLICES)
  local pads = math.max(1, math.floor(tonumber(opts.pads) or 16))
  local from = math.max(1, math.floor(tonumber(opts.from) or 1))
  if from > total then return nil, "starting past the end of the loop" end

  local n = math.min(pads, total - from + 1)
  local width = 1 / total

  local slices = {}
  for i = 1, n do
    local idx = from + i - 1
    local a = (idx - 1) * width
    local b = idx * width
    -- The last slice ends exactly at 1 rather than at 15 times a rounded
    -- width, so nothing of the tail is lost to arithmetic.
    if idx == total then b = 1 end
    slices[i] = {
      pad = i,
      index = idx,
      start01 = a,
      stop01 = b,
      start_time = a * duration,
      stop_time = b * duration,
    }
  end

  return {
    slices = slices,
    total = total,
    used = n,
    from = from,
    truncated = total > (from - 1 + n),
    slice_seconds = width * duration,
    bpm = (opts.mode == "grid") and M.implied_bpm(duration, opts.bars) or nil,
  }
end

-- Slices taken from cue points instead of from arithmetic.
--
-- Equal division assumes the pieces are equal. A stitched kit is the case where
-- that is plainly false -- sixteen one-shots of wildly different lengths -- and
-- there the boundaries are not a guess but a fact written into the file.
--
-- Each cue starts a slice; the slice ends where the next one begins, and the
-- last runs to the end of the file. A cue at frame 0 is the first slice rather
-- than an empty one before it.
function M.from_cues(cues, frames, opts)
  if not cues or #cues == 0 then return nil, "no cue points" end
  frames = tonumber(frames) or 0
  if frames <= 0 then return nil, "the file has no length" end

  opts = opts or {}
  local pads = math.max(1, math.floor(tonumber(opts.pads) or 16))
  local from = math.max(1, math.floor(tonumber(opts.from) or 1))
  local duration = tonumber(opts.duration) or 0

  -- Not rounded. A cue's position happens to be a whole number of frames, but
  -- from_times feeds this the same thing measured in seconds, where 0.25 is a
  -- quarter of the way in and flooring it makes it the very start. Every
  -- boundary in a file under a second long collapsed onto zero, so every pad
  -- played the whole thing -- and the dialog, quite correctly, said there was
  -- nothing to slice.
  local points = {}
  for _, c in ipairs(cues) do
    local f = math.max(0, math.min(frames, tonumber(c.frame) or 0))
    points[#points + 1] = { frame = f, label = c.label }
  end
  table.sort(points, function(a, b) return a.frame < b.frame end)

  local total = #points
  if from > total then return nil, "starting past the last cue" end
  local n = math.min(pads, total - from + 1)

  local slices = {}
  for i = 1, n do
    local idx = from + i - 1
    local a = points[idx].frame / frames
    local b = (idx < total) and (points[idx + 1].frame / frames) or 1
    -- A cue sitting on top of the next one would give a silent pad. Better to
    -- keep the file's own boundary and let it be short than to hand back
    -- nothing playable.
    if b <= a then b = math.min(1, a + (1 / frames)) end
    slices[i] = {
      pad = i,
      index = idx,
      label = points[idx].label,
      start01 = a,
      stop01 = b,
      start_time = a * duration,
      stop_time = b * duration,
    }
  end

  return {
    slices = slices,
    total = total,
    used = n,
    from = from,
    truncated = total > (from - 1 + n),
    from_cues = true,
    slice_seconds = (duration > 0) and (duration / total) or 0,
  }
end

-- Slices from a list of times in seconds, which is what transient detection
-- hands back. The same shape as cue slices, because that is what they are: a
-- set of boundaries the file itself suggested rather than arithmetic.
function M.from_times(times, duration, opts)
  if not times or #times == 0 then return nil, "nothing detected" end
  duration = tonumber(duration) or 0
  if duration <= 0 then return nil, "the file has no length" end
  local cues = {}
  for i, t in ipairs(times) do cues[i] = { frame = t } end
  opts = opts or {}
  opts.duration = duration
  local plan, err = M.from_cues(cues, duration, opts)
  if plan then plan.from_cues = nil plan.from_times = true end
  return plan, err
end

-- A nudge on one pad, in milliseconds, kept inside the file.
--
-- This is the part a grid can never get right on its own: a loop played with
-- swing does not put its hits on even divisions, so a slice lands a little
-- before or after the sound it was meant to catch. Moving the start is the
-- repair, and it has to stay ahead of the end or the pad falls silent with no
-- clue why.
function M.nudge(slice, ms, duration)
  duration = tonumber(duration) or 0
  if not slice or duration <= 0 then return slice end
  local delta = (tonumber(ms) or 0) / 1000 / duration
  local start01 = slice.start01 + delta
  if start01 < 0 then start01 = 0 end
  local limit = slice.stop01 - (0.001 / duration)
  if start01 > limit then start01 = math.max(0, limit) end
  slice.start01 = start01
  slice.start_time = start01 * duration
  return slice
end

function M.summary(plan)
  if not plan then return "" end
  local out
  if plan.from_times then
    out = string.format("%d slices at the transients found", plan.used)
  elseif plan.from_cues then
    -- No average length quoted here: the whole point of cue slicing is that the
    -- pieces are not the same length, and one number would misrepresent it.
    out = string.format("%d slices at the file's own cue points", plan.used)
  else
    out = string.format("%d slices of %.0f ms", plan.used, plan.slice_seconds * 1000)
  end
  if plan.truncated then
    out = out .. string.format(" -- %d of %d, the rest does not fit", plan.used, plan.total)
  end
  if plan.bpm then
    out = out .. string.format("  |  %.1f BPM", plan.bpm)
  end
  return out
end

return M
