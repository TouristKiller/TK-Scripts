-- Tag vocabulary on top of core/analyzer.lua, following the 9-axes tag system.
--
-- The analyser only produces raw measurements; every threshold that turns a
-- measurement into a label lives here, and the cache stores the raw numbers --
-- so the vocabulary can be retuned without re-analysing a library.
--
-- Axes and how they are derived:
--   FREQUENCY   dominant band + log-frequency centroid   -- measured, reliable
--   TRANSIENT   attack time                              -- measured, reliable
--   DECAY       peak to -40 dB                           -- measured, reliable
--   TONALITY    spectral flatness (+ centroid, decay)    -- measured, fair
--   SPATIALITY  post-direct energy + stereo width        -- measured, rough
--   TEXTURE     HF content + crest factor                -- measured, rough
--   FUNCTION    filename, via core/categories.lua
--   SOURCE      filename keywords
--   PERFORMANCE not derived: velocity layers and round robins are properties
--               of a GROUP of files, not of a single sample.
--
-- Confidence is carried per axis so the UI can be honest about which labels are
-- a measurement and which are an educated guess.
--
-- Analysis is never automatic for a whole library: callers drive M.new_job()
-- explicitly. Results are cached per path and persisted, so stopping a job
-- costs nothing -- it resumes exactly where it left off.

local r = reaper
local Analyzer = require("core.analyzer")
local Categories = require("core.categories")
local Bias = require("core.bias")

local M = {}

local CACHE_DIR   = r.GetResourcePath() .. "/TK_Kit_Maker"
local CACHE_PATH  = CACHE_DIR .. "/tag_cache.tsv"
local CACHE_TAG   = "TKKM-TAGS-2"
local MAX_ENTRIES = 200000
local FLUSH_EVERY = 200
local FIELDS      = 23
-- Byte size, written after the bands so caches from before it existed still
-- load -- they simply carry no stamp, and nothing claims to know whether they
-- are stale.
local SIZE_FIELD  = 24

-- Time budget per UI frame, in milliseconds.
--
-- Read this together with step() below, which always measures at least one file
-- before it looks at the clock -- it has to, or a file more expensive than the
-- budget would never be started at all. So the budget does not cap a frame, it
-- decides whether a SECOND file is begun. Anything below the cost of one file
-- (around 45 ms) therefore behaves identically to any other such value.
--
-- Nobody analyses a library while they are working, so idle is set to fit two
-- ordinary files, roughly halving the wall clock. It is not set higher because
-- a defer script runs on REAPER's main thread: a long frame freezes the whole
-- program, not just this window.
local BUDGET_IDLE_MS = 60
local BUDGET_PLAY_MS = 1
-- ...and during playback, for the same reason, easing off cannot be done by
-- asking for fewer milliseconds. One file would still be measured every frame.
-- It has to be done by skipping frames outright.
local PLAY_EVERY_N = 6
local play_tick = 0

M.BANDS = Analyzer.BANDS

M.TRANSIENTS = { "SOFT", "MEDIUM", "HARD", "IMPACT" }
M.DECAYS     = { "SHORT", "MEDIUM", "LONG", "LEGATO" }
-- Not a judgement about the sound, but about the file: hardware samplers and
-- grooveboxes that only play mono either refuse a stereo file or sum it, and
-- summing is where the phase problems come from.
M.CHANNELS   = { "MONO", "STEREO" }
M.TONALITIES = { "NOISE", "PITCHED", "DEFINED", "CHROMATIC" }
M.SPACES     = { "DRY", "ROOM", "HALL", "WET" }
M.SOURCES    = { "ACOUSTIC", "ELECTRONIC", "FOLEY" }
M.FUNCTIONS  = { "KICK", "SNARE", "HAT", "PERC", "FX", "AMB" }

-- Vocabulary for the TEXTURE axis. NOT derived automatically: every cheap
-- measure of "processing" (HF content, crest factor) turns out to track
-- brightness rather than distortion, so a clean hi-hat reads as FILTHY. The raw
-- numbers it would need (hf_ratio, crest_db) are cached anyway, so a better
-- mapping -- or manual tagging -- can be added without re-analysing anything.
M.TEXTURES = { "CLEAN", "WARM", "CRUNCHY", "FILTHY" }

-- The continuous axes, in the order the UI shows them.
M.AXES = {
  { id = "transient", label = "Transient", key = "att01",   lo = "soft",  hi = "impact", conf = "high" },
  { id = "decay",     label = "Decay",     key = "dec01",   lo = "short", hi = "legato", conf = "high" },
  { id = "tone",      label = "Frequency", key = "tone01",  lo = "sub",   hi = "air",    conf = "high" },
  { id = "space",     label = "Space",     key = "space01", lo = "dry",   hi = "wet",    conf = "low"  },
}

-- Tonality boundaries on spectral flatness. Above NOISE_FLATNESS there is no
-- pitch left (hats, snares); below PURE_FLATNESS the spectrum is essentially a
-- single partial (808, synth bass); in between sits a clear pitch carried by a
-- lot of overtone and skin content.
--
-- The lower line is deliberately low. At 0.12 -- checked against a real library
-- -- bongos, congas and deep toms all read as DEFINED, because acoustically
-- they sit close to a tuned sine; the tag system puts every hand drum under
-- PITCHED and reserves DEFINED for synthetic material. The upper line is left
-- where it is on purpose: dropping it would drag metallic and high-tuned toms
-- into NOISE, and those are already landing correctly.
local NOISE_FLATNESS = 0.30
local PURE_FLATNESS  = 0.05

M.CONFIDENCE = {
  band = "high", transient = "high", decay = "high",
  tonality = "fair", space = "low",
  ["function"] = "fair", source = "low",
}

local axis_by_id = {}
for _, a in ipairs(M.AXES) do axis_by_id[a.id] = a end

function M.axis(id)
  return axis_by_id[id]
end

-- Kit Maker's own categories mapped onto the six coarse FUNCTION groups.
local FUNCTION_OF_CATEGORY = {
  kick = "KICK", ["808"] = "KICK",
  snare = "SNARE", clap = "SNARE", rim = "SNARE",
  hihat = "HAT", hihat_open = "HAT", hihat_closed = "HAT",
  tom = "PERC", perc = "PERC", shaker = "PERC",
  cymbal = "PERC", crash = "PERC", ride = "PERC",
  fx = "FX", vocal = "FX",
}

-- Keyword lists for the SOURCE axis, split the way core/categories.lua splits
-- its own: `subs` are matched as substrings against the path with every
-- non-alphanumeric removed (so "BD-808" still contains "808"), `toks` have to
-- be a whole word. Short or common fragments belong in `toks` -- "fm" as a
-- substring also fires on "confirm", "live" on "delivery".
--
-- No two entries in one list may be a prefix of another ("synth"/"synthetic"),
-- or a single word would score twice and skew the comparison below.
-- Only words that are almost always a DESCRIPTION of the material, never
-- decoration. Ordinary English -- field, wood, nature, live, skin, digital,
-- ambient -- was pulled out: those turn up in kit names for the sound of them,
-- including in Kit Maker's own name generator, which has "Wooden" and "Field"
-- in its word lists. A pack called "Wooden Field Machine" tells you nothing
-- about what is inside it.
--
-- Brand names only earn a place when the brand makes one kind of thing. Ludwig,
-- Gretsch and Sonor make drums; Yamaha makes drums AND the DX7, so it says
-- nothing on its own.
local SOURCE_HINTS = {
  { source = "FOLEY",
    subs = { "foley", "fieldrecording", "fieldrec", "footstep", "handling" },
    toks = {} },
  { source = "ELECTRONIC",
    subs = { "808", "909", "707", "606", "cr78", "linn", "synth", "drummachine" },
    toks = { "fm", "dmx" } },
  { source = "ACOUSTIC",
    subs = { "acoustic", "brush", "ludwig", "gretsch", "sonor" },
    toks = { "stick", "sticks" } },
}

-- Cache ---------------------------------------------------------------------

local cache = {}
local entries = 0
local loaded = false
local dirty = false

-- Derived axes are memoised separately: picking a kit runs derive() over a
-- whole pool, and doing the logarithms again for every slot of every kit in a
-- 200-kit batch adds up. Invalidated whenever the measurement behind it changes.
local derived = {}

local function key_of(path)
  return (tostring(path or ""):gsub("\\", "/"))
end

local function parse_line(line, fields, size_field)
  local path = line:match("([^\t]*)$")
  if not path or path == "" then return nil end

  local nums, n = {}, 0
  for f in line:gmatch("([^\t]*)\t") do
    n = n + 1
    nums[n] = f
  end
  if n == 0 then return nil end
  if n == 1 and nums[1] == "-" then return path, false end
  if n < fields then return nil end

  local v = {}
  for i = 1, fields do
    v[i] = tonumber(nums[i])
    if not v[i] then return nil end
  end
  local value = {
    dur = v[1], nch = v[2], attack_ms = v[3], decay_ms = v[4], decay10_ms = v[5],
    crest_db = v[6], centroid = v[7], flat = v[8], pitch = v[9],
    tail_ratio = v[10], hf_ratio = v[11], width = v[12],
    bands = { v[13], v[14], v[15], v[16], v[17], v[18], v[19] },
    size = tonumber(nums[size_field]),
  }
  if fields >= FIELDS then
    value.shape = { onsets = v[20], spread = v[21] ~= 0, regular = v[22] ~= 0, sustain = v[23] }
  end
  return path, value
end

-- Byte size of a file, or nil. Used as the "has this changed" stamp: cheap,
-- and in practice a re-rendered or edited sample is a different size.
--
-- Never called while reading the cache. Doing it for every entry would mean
-- opening tens of thousands of files at start-up to answer a question nobody
-- asked; it is asked per file, when there is a reason to.
local function file_size(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local n = f:seek("end")
  f:close()
  return n
end
M.file_size = file_size

local function load_cache()
  loaded = true
  local f = io.open(CACHE_PATH, "r")
  if not f then return end
  local tag = f:read("*l")
  local fields, size_field
  if tag == CACHE_TAG then
    fields, size_field = FIELDS, SIZE_FIELD
  elseif tag == "TKKM-TAGS-1" then
    fields, size_field = 19, 20
  else
    f:close()
    return
  end
  for line in f:lines() do
    local path, value = parse_line(line, fields, size_field)
    if path then
      cache[path] = value
      entries = entries + 1
    end
  end
  f:close()
end

local function ensure_loaded()
  if not loaded then load_cache() end
end

local function serialize(m)
  local b = m.bands or {}
  local s = m.shape or {}
  return string.format(
    "%.5g\t%d\t%.5g\t%.5g\t%.5g\t%.5g\t%.5g\t%.5g\t%.5g\t%.5g\t%.5g\t%.5g"
      .. "\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%.4f\t%d\t%d\t%d\t%.5g\t%d",
    m.dur or 0, m.nch or 1, m.attack_ms or 0, m.decay_ms or 0, m.decay10_ms or 0,
    m.crest_db or 0, m.centroid or 0, m.flat or 0, m.pitch or 0,
    m.tail_ratio or 0, m.hf_ratio or 0, m.width or 0,
    b[1] or 0, b[2] or 0, b[3] or 0, b[4] or 0, b[5] or 0, b[6] or 0, b[7] or 0,
    s.onsets or 0, s.spread and 1 or 0, s.regular and 1 or 0, s.sustain or 0,
    m.size or 0)
end

function M.flush()
  if not dirty then return end
  dirty = false
  r.RecursiveCreateDirectory(CACHE_DIR, 0)
  local f = io.open(CACHE_PATH, "w")
  if not f then return end
  f:write(CACHE_TAG, "\n")
  local written = 0
  for path, value in pairs(cache) do
    if value then
      f:write(serialize(value), "\t", path, "\n")
    else
      f:write("-\t", path, "\n")
    end
    written = written + 1
    if written >= MAX_ENTRIES then break end
  end
  f:close()
end

function M.clear_cache()
  cache = {}
  derived = {}
  entries = 0
  loaded = false
  dirty = false
  os.remove(CACHE_PATH)
end

-- Drops the in-memory copy but keeps the file, so the next lookup reads it back
-- from disk. Used after an external edit -- and by the test harness.
function M.reload()
  M.flush()
  cache = {}
  derived = {}
  entries = 0
  loaded = false
end

function M.cache_size()
  ensure_loaded()
  return entries
end

-- Measurements --------------------------------------------------------------

-- Cached metrics for a path, or nil when the file was never analysed (or could
-- not be read). Never analyses -- use M.ensure() for that.
function M.get(path)
  ensure_loaded()
  local hit = cache[key_of(path)]
  if hit == nil or hit == false then return nil end
  return hit
end

function M.is_analyzed(path)
  ensure_loaded()
  return cache[key_of(path)] ~= nil
end

-- Analyses one file if it is not cached yet and returns its metrics. Cheap
-- enough (a few ms) to call for a single file the user just clicked on.
function M.ensure(path, force)
  ensure_loaded()
  local k = key_of(path)
  if not force and cache[k] ~= nil then
    return cache[k] or nil
  end
  local m = Analyzer.analyze(path)
  if m then m.size = file_size(path) end
  if cache[k] == nil then entries = entries + 1 end
  cache[k] = m or false
  derived[k] = nil
  dirty = true
  return m
end

-- True when the file on disk is not the one that was measured. Costs one file
-- open, so it is asked deliberately -- never in a loop over a whole library
-- unless the user pressed something that means "check them all".
--
-- A measurement from before the stamp existed answers false: unknown is not the
-- same as changed, and re-measuring a whole library on a maybe is worse than
-- leaving it.
function M.is_stale(path)
  ensure_loaded()
  local m = cache[key_of(path)]
  if type(m) ~= "table" or not m.size or m.size == 0 then return false end
  local now = file_size(path)
  return now ~= nil and now ~= m.size
end

-- Drops the measurement for a file that has changed, so the next look at it
-- measures again. Returns true when something was actually dropped.
function M.forget_if_stale(path)
  if not M.is_stale(path) then return false end
  local k = key_of(path)
  cache[k] = nil
  derived[k] = nil
  entries = math.max(0, entries - 1)
  dirty = true
  return true
end

-- Every file in `files` whose measurement no longer matches what is on disk.
-- One file open each, so this belongs behind an explicit action.
function M.stale_files(files)
  ensure_loaded()
  local out, seen = {}, {}
  for _, f in ipairs(files or {}) do
    local k = key_of(f)
    if not seen[k] then
      seen[k] = true
      if M.is_stale(f) then out[#out + 1] = f end
    end
  end
  return out
end

-- How many of `files` already carry a measurement.
function M.count_analyzed(files)
  ensure_loaded()
  local n, seen = 0, {}
  for _, f in ipairs(files or {}) do
    local k = key_of(f)
    if not seen[k] then
      seen[k] = true
      if cache[k] ~= nil then n = n + 1 end
    end
  end
  return n
end

-- Derivation ----------------------------------------------------------------

local function clamp01(v)
  if not v or v ~= v then return 0 end
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end

-- Normalised position of `v` between `lo` and `hi` on a log scale, so that
-- doubling counts the same everywhere -- how we hear time and pitch.
local function log_norm(v, lo, hi)
  v = math.max(lo, math.min(hi, tonumber(v) or lo))
  return clamp01((math.log(v) - math.log(lo)) / (math.log(hi) - math.log(lo)))
end

local function bucket(v, edges)
  for i = 1, #edges do
    if v < edges[i] then return i end
  end
  return #edges + 1
end

-- Position of a frequency on the SUB..AIR axis: spread evenly across the seven
-- bands, not evenly across log frequency.
--
-- A plain log scale from 30 Hz to 18 kHz spends its bottom third on 20-400 Hz,
-- where only kicks and toms live, and crams every clap, snare and hat into the
-- top quarter -- measured on a real library, hats all pile up against the end
-- of the axis. Stretching each of Sebastian's bands to an equal slice puts the
-- material where the vocabulary says it is, and leaves the axis usable as a
-- coordinate rather than a heap.
local function band_position(hz)
  local n = Analyzer.BAND_COUNT
  if not hz or hz <= Analyzer.BANDS[1].lo then return 0 end
  if hz >= Analyzer.BANDS[n].hi then return 1 end
  for i = 1, n do
    local b = Analyzer.BANDS[i]
    if hz < b.hi then
      local frac = (math.log(hz) - math.log(b.lo)) / (math.log(b.hi) - math.log(b.lo))
      return (i - 1 + clamp01(frac)) / n
    end
  end
  return 1
end

-- Turns raw metrics into the labelled axes. Pure and cheap: the UI may call
-- this every frame for the selected sample.
function M.derive(m)
  if not m then return nil end

  local att01 = 1 - log_norm(m.attack_ms, 0.2, 60)
  local dec01 = log_norm(m.decay_ms, 5, 4000)
  local tone01 = band_position(m.centroid)

  -- Dry/wet needs stereo. The decay SHAPE alone (a plain exponential spends a
  -- quarter of its -40 dB time reaching -10 dB; a reverberant tail drops fast
  -- then lingers, pushing that fraction down) cannot tell a room apart from a
  -- kick whose click decays faster than its body -- both are two-stage decays.
  -- Stereo decorrelation is the cue that actually separates them, so on mono
  -- material this axis reports nothing rather than guessing.
  local space01, space_known = nil, false
  if (m.nch or 1) >= 2 then
    local shape = m.decay_ms > 0 and (m.decay10_ms / m.decay_ms) or 0.25
    local diffuse = clamp01((0.25 - shape) / 0.15)
    space01 = clamp01(0.55 * clamp01(m.width) + 0.45 * diffuse)
    space_known = true
  end

  -- Dominant band, not the centroid: a kick's centroid is dragged upward by its
  -- click, but its energy -- and what we call it -- sits in SUB/LOW.
  local band, band_max = 1, -1
  for i = 1, Analyzer.BAND_COUNT do
    local e = (m.bands and m.bands[i]) or 0
    if e > band_max then band_max, band = e, i end
  end

  local tonality
  if m.flat > NOISE_FLATNESS then
    tonality = 1 -- NOISE
  elseif m.flat > PURE_FLATNESS then
    tonality = 2 -- PITCHED
  elseif m.centroid > 800 and m.decay_ms > 300 then
    tonality = 4 -- CHROMATIC
  else
    tonality = 3 -- DEFINED
  end

  return {
    att01 = att01, dec01 = dec01, tone01 = tone01, space01 = space01,
    space_known = space_known,

    band = band,
    band_label = Analyzer.BANDS[band].label,
    -- Attack buckets are read off the high-passed onset; SOFT..IMPACT runs the
    -- opposite way to the millisecond scale, hence the flip. Decay buckets use
    -- the -40 dB time, which runs longer than the "perceived" length in the tag
    -- system table -- a closed hat lands near 60 ms, not under 50.
    transient = 5 - bucket(m.attack_ms, { 1.5, 5, 15 }),
    decay = bucket(m.decay_ms, { 120, 450, 1500 }),
    tonality = tonality,
    space = space01 and bucket(space01, { 0.18, 0.38, 0.62 }) or nil,
    -- Measured all along -- it is what decides whether the space axis reports
    -- anything -- and simply never offered as something to filter on.
    channels = ((m.nch or 1) >= 2) and 2 or 1,
  }
end

function M.derive_labels(d)
  if not d then return nil end
  return {
    band = d.band_label,
    transient = M.TRANSIENTS[d.transient],
    decay = M.DECAYS[d.decay],
    tonality = M.TONALITIES[d.tonality],
    space = d.space and M.SPACES[d.space] or nil,
    channels = M.CHANNELS[d.channels],
  }
end

-- Name-derived axes ---------------------------------------------------------

local function haystack_of(path)
  path = tostring(path or ""):gsub("\\", "/"):lower()
  local parent, name = path:match("([^/]+)/([^/]+)$")
  if not name then name = path:match("([^/]+)$") or path end
  name = name:gsub("%.[%w]+$", "")
  return ((parent and (parent .. "/") or "") .. name):gsub("[^%w]", "")
end

-- Source is read from the WHOLE path, unlike every other name-derived tag.
--
-- What marks material as acoustic or foley almost always sits in the pack
-- folder name ("Vintage Acoustic Kit"), not in the file, which is called
-- SN_01.wav like everything else. The parent-and-filename rule that
-- core/categories.lua uses on purpose -- so a folder called "Kicks" cannot tag
-- everything inside it -- looks in exactly the wrong place for this axis, and
-- that is why nothing but the 808 packs ever came up ELECTRONIC.
local function source_haystack(path)
  local p = tostring(path or ""):gsub("\\", "/"):lower():gsub("%.[%w]+$", "")
  local tokens = {}
  for token in p:gmatch("[%w]+") do
    tokens[token] = true
    local stripped = token:gsub("^%d+", ""):gsub("%d+$", "")
    if stripped ~= "" then tokens[stripped] = true end
  end
  return (p:gsub("[^%w]", "")), tokens
end

-- The strongest match wins and a tie yields nothing. "Acoustic Kit/kick_808" is
-- genuinely ambiguous, and answering with whichever row happens to sit first in
-- the table is worse than admitting as much.
local function best_source(text)
  local collapsed, tokens = source_haystack(text)
  local best, best_score, tied = nil, 0, false

  for _, hint in ipairs(SOURCE_HINTS) do
    local score = 0
    for _, w in ipairs(hint.subs) do
      if collapsed:find(w, 1, true) then score = score + 1 end
    end
    for _, w in ipairs(hint.toks) do
      if tokens[w] then score = score + 1 end
    end

    if score > best_score then
      best, best_score, tied = hint.source, score, false
    elseif score == best_score and score > 0 then
      tied = true
    end
  end

  if best_score == 0 or tied then return nil end
  return best
end

-- FOLEY / ELECTRONIC / ACOUSTIC from the path. Returns the source and whether
-- it came from the FILENAME; nil when nothing says anything.
--
-- The filename is asked first and wins outright. A word in the file is evidence
-- about that sample; the same word in a folder is one clue smeared over
-- everything inside it, and there is no way to tell a description ("Acoustic
-- Kit") from decoration ("Acoustic Death Punch"). Folder matches are still used
-- -- for acoustic and foley material the folder is usually the only place it is
-- written down -- but the caller is told, so it can show a weak guess weakly.
function M.source_of(path)
  local leaf = tostring(path or ""):match("([^/\\]+)$") or ""
  local from_file = best_source(leaf)
  if from_file then return from_file, true end
  local from_path = best_source(path)
  if from_path then return from_path, false end
  return nil
end

-- The Kit Maker category (18 values, used everywhere else in the app) plus the
-- coarse FUNCTION group from the tag system.
function M.function_of(path)
  for _, cat in ipairs(Categories.list) do
    if Categories.matches(path, { category = cat.id }) then
      return FUNCTION_OF_CATEGORY[cat.id], cat.label
    end
  end
  return nil, nil
end

-- Everything the UI needs for one sample. Returns nil when it has no
-- measurement yet; name-derived tags are still filled in.
function M.tags(path)
  local m = M.get(path)
  local d = M.derive(m)
  local group, category = M.function_of(path)
  local source, source_from_file = M.source_of(path)
  return {
    metrics = m,
    axes = d,
    labels = M.derive_labels(d),
    ["function"] = group,
    category = category,
    source = source,
    source_from_file = source_from_file,
  }
end

-- Character bias ------------------------------------------------------------
--
-- A gaussian per measured axis, multiplied together, used to WEIGHT a pool
-- rather than filter it -- the same distinction as the heatmap slider. A batch
-- of 50 kits still comes out as 50 different kits; they just all lean the same
-- way. Filtering would instead hand you the same handful of samples every time.

M.BIAS_AXES = { "tone", "decay", "transient" }

-- Word scale per axis, so a slider can read "HARD" instead of "0.78".
M.BIAS_LABELS = {
  decay = M.DECAYS,
  transient = M.TRANSIENTS,
  tone = (function()
    local out = {}
    for i, band in ipairs(Analyzer.BANDS) do out[i] = band.label end
    return out
  end)(),
}

function M.new_bias_config()
  local cfg = {}
  for _, id in ipairs(M.BIAS_AXES) do
    cfg[id] = { enabled = false, center = 0.5, focus = 0.6 }
  end
  return cfg
end

-- Focus response for the tag axes.
--
-- core/bias.lua's own curve is tuned for RANK positions in a sorted list, where
-- it behaves; spread over a measured 0..1 axis it wastes the bottom half of the
-- slider on almost no effect and turns the top fifth into a hard filter. Sigma
-- halving every quarter turn keeps every step of the slider worth making, while
-- focus 1 stays every bit as absolute as it was.
local SIGMA_WIDE, SIGMA_TIGHT = 1.2, 0.07

local function focus_sigma(focus)
  local f = tonumber(focus) or 0
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  return SIGMA_WIDE * (SIGMA_TIGHT / SIGMA_WIDE) ^ f
end
M.focus_sigma = focus_sigma

local function axis_active(a)
  return type(a) == "table" and a.enabled == true and (tonumber(a.focus) or 0) > 0
end

function M.bias_active(cfg)
  if type(cfg) ~= "table" then return false end
  for _, id in ipairs(M.BIAS_AXES) do
    if axis_active(cfg[id]) then return true end
  end
  return false
end

-- Stable string for the pick-view weight caches in core/engine.lua.
function M.bias_key(cfg)
  if not M.bias_active(cfg) then return "" end
  local parts = {}
  for _, id in ipairs(M.BIAS_AXES) do
    local a = cfg[id]
    if axis_active(a) then
      parts[#parts + 1] = string.format("%s%.3f,%.3f", id:sub(1, 1),
        tonumber(a.center) or 0.5, tonumber(a.focus) or 0.6)
    end
  end
  return table.concat(parts, ";")
end

-- Cached axis values for one path, or nil when it was never measured.
function M.axes(path)
  ensure_loaded()
  local k = key_of(path)
  local hit = derived[k]
  if hit ~= nil then return hit or nil end
  local d = M.derive(cache[k] or nil)
  derived[k] = d or false
  return d
end

-- Weight for one file under a character bias.
--
-- A file that was never analysed counts as average on every axis: it stays
-- eligible, but an extreme setting will not favour it. That degrades the right
-- way -- with nothing analysed every weight is equal and picking falls back to
-- plain random, instead of the bias quietly turning into a filter that only
-- ever returns the measured handful.
function M.bias_weight(cfg, path)
  local axes = M.axes(path)
  local w = 1
  for _, id in ipairs(M.BIAS_AXES) do
    local a = cfg[id]
    if axis_active(a) then
      local axis = M.axis(id)
      local value = (axes and axis and axes[axis.key]) or 0.5
      w = w * Bias.weight_with_sigma(value, a.center, focus_sigma(a.focus))
    end
  end
  return w
end

-- Short human summary for the UI ("dark, punchy" style).
function M.bias_summary(cfg)
  if not M.bias_active(cfg) then return "off" end
  local parts = {}
  for _, id in ipairs(M.BIAS_AXES) do
    local a = cfg[id]
    if axis_active(a) then
      local axis = M.axis(id)
      local center = tonumber(a.center) or 0.5
      local word
      if center < 0.25 then word = axis.lo
      elseif center > 0.75 then word = axis.hi
      else word = "mid " .. axis.label:lower() end
      parts[#parts + 1] = word
    end
  end
  return table.concat(parts, ", ")
end

-- Filtering -----------------------------------------------------------------
--
-- Real filtering, and deliberately NOT the same mechanism as the character bias
-- above. Searching is a different job from generating:
--
--   Searching wants a hard answer. "Show me the noise hats" means the noise
--   hats; a sample either carries the tag or it is not in the list.
--
--   Generating wants a soft one. A hard threshold there would collapse a batch
--   of 50 kits onto the same handful of samples, put an arbitrary cliff between
--   0.49 and 0.51, and turn every measurement error into a sample you can never
--   hear again. Hence M.bias_weight.
--
-- A filter is a set of accepted labels per axis. Within an axis the labels are
-- OR'd (SUB or LOW), across axes they are AND'ed (SUB/LOW *and* SHORT).
-- Unmeasured samples carry no labels, so an active filter excludes them --
-- correct here, where the bias treats them as average instead.

M.FILTER_AXES = { "category", "band", "transient", "decay", "tonality", "space", "channels", "source" }

M.FILTER_LABELS = {
  category = "Category", band = "Frequency", transient = "Transient",
  decay = "Decay", tonality = "Tonality", space = "Space", channels = "Channels",
  source = "Source",
}

-- Category and source are read from the path rather than the audio, so those
-- two filter a pack nobody has analysed yet. Everything else needs a
-- measurement.
local NAME_DERIVED = { source = true, category = true }

-- Category is the one axis where a sample can carry SEVERAL labels at once:
-- "OHH_01" is an Open hihat and a Hihat, on purpose, so that filtering on Hihat
-- returns it. The other axes assign exactly one label.
local MULTI_LABEL = { category = true }

-- A pseudo-category for everything the naming rules do not recognise. Without
-- it those files are unreachable: they sit in the list but belong to no chip,
-- so there is no way to ask "what does Kit Maker not understand here?" -- which
-- is exactly the set worth looking at, because it is the set that will not work
-- in Builder slot filters or Explosion patterns either.
M.UNCATEGORISED = "Uncategorised"

local category_id_by_label = {}
for _, cat in ipairs(Categories.list) do
  category_id_by_label[cat.label] = cat.id
end

local function matches_any_category(path, wanted)
  -- Only the selected categories are tested, not all seventeen: with one or two
  -- ticked this stays a couple of string matches per file.
  for label in pairs(wanted) do
    if label == M.UNCATEGORISED then
      if Categories.matches_none(path) then return true end
    else
      local id = category_id_by_label[label]
      if id and Categories.matches(path, { category = id }) then return true end
    end
  end
  return false
end

function M.filter_needs_analysis(filter)
  if type(filter) ~= "table" then return false end
  for _, id in ipairs(M.FILTER_AXES) do
    if not NAME_DERIVED[id] and next(filter[id] or {}) ~= nil then return true end
  end
  return false
end

local function axis_values(axis_id)
  if axis_id == "band" then
    local out = {}
    for i, b in ipairs(Analyzer.BANDS) do out[i] = b.label end
    return out
  elseif axis_id == "transient" then return M.TRANSIENTS
  elseif axis_id == "decay" then return M.DECAYS
  elseif axis_id == "tonality" then return M.TONALITIES
  elseif axis_id == "channels" then return M.CHANNELS
  elseif axis_id == "space" then return M.SPACES
  elseif axis_id == "source" then return M.SOURCES
  elseif axis_id == "category" then
    local out = {}
    for i, cat in ipairs(Categories.list) do out[i] = cat.label end
    out[#out + 1] = M.UNCATEGORISED -- always last: it is not a kind of drum
    return out
  end
  return {}
end
M.filter_values = axis_values

-- The label a measured sample carries on one axis, or nil.
local function label_of(axes, axis_id)
  if not axes then return nil end
  local index = axes[axis_id]
  if not index then return nil end
  return axis_values(axis_id)[index]
end
M.label_of = label_of

-- Label on any filter axis, measured or name-derived.
local function filter_label(path, axes, axis_id)
  if axis_id == "source" then return M.source_of(path) end
  return label_of(axes, axis_id)
end
M.filter_label = filter_label

function M.new_filter()
  local f = {}
  for _, id in ipairs(M.FILTER_AXES) do f[id] = {} end
  return f
end

function M.filter_active(filter)
  if type(filter) ~= "table" then return false end
  for _, id in ipairs(M.FILTER_AXES) do
    if next(filter[id] or {}) ~= nil then return true end
  end
  return false
end

function M.filter_count(filter)
  local n = 0
  for _, id in ipairs(M.FILTER_AXES) do
    for _ in pairs(filter and filter[id] or {}) do n = n + 1 end
  end
  return n
end

-- Stable string for the caller's result cache.
function M.filter_key(filter)
  if not M.filter_active(filter) then return "" end
  local parts = {}
  for _, id in ipairs(M.FILTER_AXES) do
    local picked = {}
    for label in pairs(filter[id] or {}) do picked[#picked + 1] = label end
    if #picked > 0 then
      table.sort(picked)
      parts[#parts + 1] = id .. ":" .. table.concat(picked, ",")
    end
  end
  return table.concat(parts, ";")
end

-- `skip_axis` lets the caller ask "would this pass if I ignored that axis",
-- which is what faceted counts need.
function M.matches_filter(path, filter, skip_axis)
  if not M.filter_active(filter) then return true end
  -- Looked up only when a measured axis actually asks for it, so filtering on
  -- source alone stays a filename test and works on unanalysed material.
  local axes, axes_read = nil, false
  for _, id in ipairs(M.FILTER_AXES) do
    local wanted = filter[id]
    if id ~= skip_axis and wanted and next(wanted) ~= nil then
      if MULTI_LABEL[id] then
        if not matches_any_category(path, wanted) then return false end
      else
        local label
        if NAME_DERIVED[id] then
          label = filter_label(path, nil, id)
        else
          if not axes_read then axes, axes_read = M.axes(path), true end
          label = label_of(axes, id)
        end
        if not label or not wanted[label] then return false end
      end
    end
  end
  return true
end

-- Which labels actually occur in `files`, and how often, per axis. Counts are
-- faceted: each axis is counted over the files that pass every OTHER axis, so
-- a chip showing 12 really does leave 12 when you click it.
--
-- Returns axis -> ordered list of { label, n }, plus how many files carry no
-- measurement at all.
function M.filter_facets(files, filter)
  local facets, unmeasured = {}, 0
  local seen = {}
  -- Categories are counted in one pass at the end: core/categories.lua can
  -- score all eighteen for a file at once, which beats asking eighteen times.
  local category_candidates = {}

  for _, id in ipairs(M.FILTER_AXES) do facets[id] = {} end

  for _, path in ipairs(files or {}) do
    local k = key_of(path)
    if not seen[k] then
      seen[k] = true
      local axes = M.axes(path)
      if not axes then unmeasured = unmeasured + 1 end
      -- Unanalysed files still count towards the name-derived axes, which is
      -- the point of having them: category and source work before anything is
      -- measured.
      for _, id in ipairs(M.FILTER_AXES) do
        if axes or NAME_DERIVED[id] then
          if M.matches_filter(path, filter, id) then
            if MULTI_LABEL[id] then
              category_candidates[#category_candidates + 1] = path
            else
              local label = filter_label(path, axes, id)
              if label then facets[id][label] = (facets[id][label] or 0) + 1 end
            end
          end
        end
      end
    end
  end

  -- A sample counts towards every category it belongs to, so these totals add
  -- up to more than the number of files. That is what an open hihat also being
  -- a hihat looks like in a count.
  local counts, uncategorised = Categories.count_all(category_candidates)
  for _, cat in ipairs(Categories.list) do
    local n = counts[cat.id] or 0
    if n > 0 then facets.category[cat.label] = n end
  end
  if uncategorised > 0 then facets.category[M.UNCATEGORISED] = uncategorised end

  -- Emit in the axis's own order (SUB..AIR, SOFT..IMPACT), skipping labels that
  -- do not occur -- a pack of kicks should not offer AIR.
  local out = {}
  for _, id in ipairs(M.FILTER_AXES) do
    local list = {}
    for _, label in ipairs(axis_values(id)) do
      local n = facets[id][label]
      -- A label stays on offer while it is selected, even at zero, or it would
      -- vanish under the click that selected it.
      if n or (filter and filter[id] and filter[id][label]) then
        list[#list + 1] = { label = label, n = n or 0 }
      end
    end
    out[id] = list
  end
  return out, unmeasured
end

-- Batch job -----------------------------------------------------------------

-- Milliseconds of analysis this frame may cost. Recording wins outright:
-- Kit Maker must never steal CPU during a take.
function M.frame_budget()
  local state = r.GetPlayState and r.GetPlayState() or 0
  if state & 4 == 4 then
    play_tick = 0
    return 0
  end
  if state & 1 == 1 then
    play_tick = (play_tick + 1) % PLAY_EVERY_N
    return play_tick == 0 and BUDGET_PLAY_MS or 0
  end
  play_tick = 0
  return BUDGET_IDLE_MS
end

-- An interruptible analysis pass over `files`. Because every result is cached
-- the moment it is measured, stopping loses nothing: a new job simply picks up
-- the files that are still missing.
function M.new_job(files, force)
  ensure_loaded()
  local todo, seen = {}, {}
  for _, f in ipairs(files or {}) do
    local k = key_of(f)
    if not seen[k] then
      seen[k] = true
      if force or cache[k] == nil then todo[#todo + 1] = f end
    end
  end

  return {
    files = todo,
    total = #todo,
    index = 0,
    failed = 0,
    elapsed = 0,
    cancelled = false,
    done = #todo == 0,
    since_flush = 0,

    -- Returns true while there is work left. `budget_ms` of 0 keeps the job
    -- alive without doing anything, so it resumes once the transport stops.
    step = function(self, budget_ms)
      if self.done or self.cancelled then return false end
      local limit = (budget_ms or BUDGET_IDLE_MS) / 1000
      if limit <= 0 then return true end

      local t0 = r.time_precise()
      repeat
        self.index = self.index + 1
        if not M.ensure(self.files[self.index], force) then
          self.failed = self.failed + 1
        end
        self.since_flush = self.since_flush + 1
        if self.since_flush >= FLUSH_EVERY then
          M.flush()
          self.since_flush = 0
        end
      until self.index >= self.total or (r.time_precise() - t0) >= limit

      self.elapsed = self.elapsed + (r.time_precise() - t0)

      if self.index >= self.total then
        self.done = true
        M.flush()
        return false
      end
      return true
    end,

    cancel = function(self)
      self.cancelled = true
      M.flush()
    end,

    -- Seconds left at the rate measured so far, or nil while there is no rate.
    eta = function(self)
      if self.index <= 0 or self.elapsed <= 0 then return nil end
      return (self.total - self.index) * (self.elapsed / self.index)
    end,
  }
end

return M
