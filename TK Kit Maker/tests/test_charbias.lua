-- Character bias: it must STEER the pick without narrowing the pool, and it
-- must degrade sanely when the material was never analysed.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {
  GetResourcePath = function() return (os.getenv("TEMP") or ".") .. "/tkkm_cbtest" end,
  RecursiveCreateDirectory = function(d) os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end,
  time_precise = os.clock,
  GetPlayState = function() return 0 end,
  new_array = function(n) local a = {} for i = 1, n do a[i] = 0 end a.clear = function() end return a end,
  EnumerateFiles = function() return nil end,
  EnumerateSubdirectories = function() return nil end,
}

local Analyzer = require("core.analyzer")
local synth = {}
Analyzer.analyze = function(path) return synth[path] end

local Tags = require("core.tags")
Tags.clear_cache()

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function put(path, centroid, decay_ms, attack_ms)
  synth[path] = {
    dur = 1, nch = 1, attack_ms = attack_ms, decay_ms = decay_ms, decay10_ms = decay_ms * 0.25,
    crest_db = 9, centroid = centroid, flat = 0.05, pitch = 60,
    tail_ratio = 0.5, hf_ratio = 0.2, width = 0,
    bands = { 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01 },
  }
  Tags.ensure(path)
  return path
end

local dark_short  = put("dark_short.wav",  55,   90,  3)
local dark_long   = put("dark_long.wav",   55,  2500, 3)
local bright_short= put("bright_short.wav", 8000, 90,  0.6)
local bright_long = put("bright_long.wav",  8000, 2500, 0.6)
local unmeasured  = "never_analysed.wav"

-- 1. an inactive config changes nothing
local cfg = Tags.new_bias_config()
check("a fresh config is inactive", Tags.bias_active(cfg) == false, "active")
check("inactive key is empty", Tags.bias_key(cfg) == "", Tags.bias_key(cfg))
check("inactive weight is 1", Tags.bias_weight(cfg, dark_short) == 1, Tags.bias_weight(cfg, dark_short))

-- an enabled axis with zero focus still counts as off: no steering was asked for
cfg.tone.enabled = true
cfg.tone.focus = 0
check("focus 0 counts as off", Tags.bias_active(cfg) == false, "active")

-- 2. steering towards the dark end
cfg.tone.focus = 0.7
cfg.tone.center = 0.0
local w_dark = Tags.bias_weight(cfg, dark_short)
local w_bright = Tags.bias_weight(cfg, bright_short)
print(string.format("tone->SUB   dark %.4f   bright %.4f   ratio %.1fx", w_dark, w_bright, w_dark / w_bright))
check("dark outweighs bright", w_dark > w_bright, w_dark)
check("bright is still possible, not excluded", w_bright > 0, w_bright)

-- 3. THE property: weighting, never filtering. Nothing may reach zero.
cfg.tone.focus = 1.0
check("even at maximum focus nothing is excluded", Tags.bias_weight(cfg, bright_short) > 0,
  Tags.bias_weight(cfg, bright_short))

-- 4. axes combine
cfg.tone.focus, cfg.tone.center = 0.7, 0.0
cfg.decay.enabled, cfg.decay.center, cfg.decay.focus = true, 0.0, 0.7
local w_ds = Tags.bias_weight(cfg, dark_short)
local w_dl = Tags.bias_weight(cfg, dark_long)
local w_bl = Tags.bias_weight(cfg, bright_long)
print(string.format("dark+short  ds %.4f   dl %.4f   bl %.4f", w_ds, w_dl, w_bl))
check("both axes matching beats one axis matching", w_ds > w_dl, w_ds)
check("one axis matching beats neither", w_dl > w_bl, w_dl)

-- 5. unmeasured material counts as average: not favoured, not excluded
local w_un = Tags.bias_weight(cfg, unmeasured)
print(string.format("unmeasured  %.4f   (dark+short %.4f, bright+long %.4f)", w_un, w_ds, w_bl))
check("unmeasured does not beat a real match", w_un < w_ds, w_un)
check("unmeasured is not excluded", w_un > 0, w_un)
check("unmeasured is not treated as a perfect match", w_un < w_ds, w_un)

-- 6. with NOTHING analysed every weight is equal, so picking stays random
--    rather than the bias silently becoming a filter
local all_unknown = { "a.wav", "b.wav", "c.wav" }
local w1 = Tags.bias_weight(cfg, all_unknown[1])
for _, p in ipairs(all_unknown) do
  check("unanalysed pool weights are all equal", math.abs(Tags.bias_weight(cfg, p) - w1) < 1e-12, p)
end

-- 7. the cache key must track every setting, or engine views go stale
local k1 = Tags.bias_key(cfg)
cfg.tone.center = 1.0
check("key follows centre", Tags.bias_key(cfg) ~= k1, "unchanged")
cfg.tone.center = 0.0
check("key is stable for the same settings", Tags.bias_key(cfg) == k1, "unstable")
cfg.decay.enabled = false
check("key follows enable", Tags.bias_key(cfg) ~= k1, "unchanged")

-- 8. summary reads in the tag vocabulary
cfg.decay.enabled = true
print("summary: " .. Tags.bias_summary(cfg))
check("summary mentions both axes", Tags.bias_summary(cfg):find(",") ~= nil, Tags.bias_summary(cfg))
check("summary of an off config says so", Tags.bias_summary(Tags.new_bias_config()) == "off", "?")

-- 9. the focus slider must stay useful over its WHOLE travel. Sigma halves
-- every quarter turn, so no stretch of the slider is dead and none of it is a
-- cliff -- the failure the old (rank-tuned) curve had on a measured axis.
print()
print("focus response (sigma, and weight for a sample this far along the axis)")
print("focus  sigma |    d=0.14    d=0.25     d=0.5     d=1.0")
local prev_sigma, ratios = nil, {}
for _, f in ipairs({ 0, 0.25, 0.5, 0.75, 1.0 }) do
  local s = Tags.focus_sigma(f)
  local row = ""
  for _, d in ipairs({ 0.14, 0.25, 0.5, 1.0 }) do
    row = row .. string.format("%10.3g", math.exp(-(d * d) / (2 * s * s)))
  end
  print(string.format("%5.2f %6.3f |%s", f, s, row))
  if prev_sigma then ratios[#ratios + 1] = s / prev_sigma end
  prev_sigma = s
end

check("focus narrows monotonically", (function()
  for _, r in ipairs(ratios) do if r >= 1 then return false end end
  return true
end)(), "not monotonic")
check("each quarter turn changes sigma by the same factor", (function()
  for _, r in ipairs(ratios) do if math.abs(r - ratios[1]) > 1e-9 then return false end end
  return true
end)(), ratios[1])

local function weight_at(f, d)
  local s = Tags.focus_sigma(f)
  return math.exp(-(d * d) / (2 * s * s))
end
-- No dead stretch: even the gentle settings must visibly deprioritise the far
-- end of the axis.
check("focus 0.25 already leans", weight_at(0.25, 1.0) < 0.4, weight_at(0.25, 1.0))
-- ...and no cliff: mid focus must not already behave like a filter one band out.
check("focus 0.5 keeps a neighbouring band in play", weight_at(0.5, 0.14) > 0.5, weight_at(0.5, 0.14))
check("focus 0.75 still keeps a neighbouring band possible", weight_at(0.75, 0.14) > 0.25, weight_at(0.75, 0.14))
-- The top of the slider stays as absolute as it was: that is a legitimate ask.
check("focus 1.0 is effectively a filter", weight_at(1.0, 0.25) < 0.01, weight_at(1.0, 0.25))
-- Every quarter turn must be an audible step, not a rounding difference. Only
-- checked at real distances: a gaussian is flat around its peak, so a sample
-- sitting almost on the target keeps a high weight at any focus, which is the
-- point rather than a defect.
for _, d in ipairs({ 0.5, 1.0 }) do
  for _, f in ipairs({ 0.25, 0.5, 0.75 }) do
    check(string.format("d=%.2f: focus %.2f differs from the step below", d, f),
      weight_at(f, d) < weight_at(f - 0.25, d) * 0.85, weight_at(f, d))
  end
end

-- 10. sanitize repairs partial and missing configs
local Character = dofile(KIT .. "ui/character.lua")
local repaired = Character.sanitize(nil)
check("sanitize(nil) yields a full config", repaired.tone and repaired.decay and repaired.transient, "incomplete")
check("sanitize(nil) is inactive", Tags.bias_active(repaired) == false, "active")
local partial = Character.sanitize({ tone = { enabled = true, center = 5, focus = -2 } })
check("sanitize clamps centre", partial.tone.center == 1, partial.tone.center)
check("sanitize clamps focus", partial.tone.focus == 0, partial.tone.focus)
check("sanitize fills missing axes", partial.transient ~= nil, "missing")

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
