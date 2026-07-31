-- Seeded generation: the same seed over the same samples must give the same
-- kit, on any machine.
--
-- Everything here is a property that fails silently. A seed that is nearly
-- reproducible looks fine in testing and then hands two people different kits,
-- and the only symptom is someone saying "that's not what I got".

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

-- core.engine pulls in the duration cache and the exporter, which read these
-- at load time.
reaper = {
  GetResourcePath = function() return (os.getenv("TEMP") or "."):gsub("\\", "/") end,
  RecursiveCreateDirectory = function() end,
  EnumerateFiles = function() return nil end,
}

local Rng = require("core.rng")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- 1. The whole point: same seed, same sequence.
print("reproducibility")
local function take(seed, n)
  local g = Rng.new(seed)
  local out = {}
  for i = 1, n do out[i] = g:random(1, 1000) end
  return table.concat(out, ",")
end
check("the same seed repeats", take(84213, 20) == take(84213, 20))
check("a different seed does not", take(84213, 20) ~= take(84214, 20))

-- These are the literal numbers this generator produces. If a change to the
-- arithmetic ever alters them, every seed anyone has written down stops meaning
-- what it meant -- so this is here to make that break loudly rather than
-- quietly. Change it only when you intend to invalidate every shared seed.
local FROZEN = take(84213, 8)
print("  seed 84213 -> " .. FROZEN)
check("the sequence is frozen", FROZEN == "753,861,18,69,256,510,677,27", FROZEN)

-- 2. Consecutive seeds must be unrelated to each other. This is the common
-- case, not an edge case: a batch is seeded 84213, 84214, 84215...
--
-- Measuring the average distance between neighbours is NOT enough, and this
-- caught nothing when the generator was genuinely broken. An LCG step is
-- linear, so seeds one apart stayed a fixed distance apart no matter how long
-- the generator was spun: the openings ran 936, 445, 953, 462, 971 -- two
-- bands, alternating, with a healthy-looking average gap of 500. So what is
-- checked here is that the gaps *differ from each other*. Structure of that
-- kind would mean every kit in a batch drawing its first slot from one of two
-- corners of the pool.
print("neighbouring seeds")
local firsts = {}
for s = 84213, 84292 do
  firsts[#firsts + 1] = Rng.new(s):random(1, 1000)
end
local total, gaps, distinct = 0, {}, 0
for i = 2, #firsts do
  local d = math.abs(firsts[i] - firsts[i - 1])
  total = total + d
  if not gaps[d] then gaps[d] = true distinct = distinct + 1 end
end
local mean = total / (#firsts - 1)
print(string.format("  80 consecutive seeds: mean gap %.0f (random would be 333), %d distinct gaps of %d",
  mean, distinct, #firsts - 1))
check("neighbours are not correlated", mean > 250 and mean < 420, mean)
check("the gaps are not a repeating pattern", distinct > 50, distinct)

-- 3. Spread. A generator that leans is a generator that picks the same corner
-- of a pool over and over.
print("distribution")
local buckets = { 0, 0, 0, 0, 0, 0, 0, 0, 0, 0 }
local g = Rng.new(7)
for _ = 1, 20000 do
  local b = g:random(1, 10)
  buckets[b] = buckets[b] + 1
end
local lo, hi = math.huge, 0
for _, v in ipairs(buckets) do
  lo = math.min(lo, v)
  hi = math.max(hi, v)
end
print(string.format("  20000 draws over 10 buckets: %d..%d (even would be 2000)", lo, hi))
check("no bucket is starved", lo > 1700, lo)
check("no bucket is favoured", hi < 2300, hi)

-- random(n) must be able to return both ends; an off-by-one here quietly makes
-- the first or last sample of every pool unreachable.
local seen_lo, seen_hi = false, false
local g3 = Rng.new(11)
for _ = 1, 500 do
  local v = g3:random(3)
  if v == 1 then seen_lo = true end
  if v == 3 then seen_hi = true end
  if v < 1 or v > 3 then check("random(3) stays in range", false, v) end
end
check("random(n) reaches 1", seen_lo, seen_lo)
check("random(n) reaches n", seen_hi, seen_hi)

-- 4. Unseeded runs must stay unseeded. Kit Maker's default is a different kit
-- every time; the seed is opt-in.
print("opt-in")
Rng.clear()
check("nothing is installed by default", Rng.active() == nil, Rng.active())
Rng.use(5)
check("a seed installs one", Rng.active() ~= nil)
Rng.clear()
check("and clearing removes it", Rng.active() == nil)
check("Rng.use(nil) means unseeded", Rng.use(nil) == nil)

-- 5. Fingerprints, the other half of a shared seed.
print("fingerprints")
local pack_a = { "D:/P/kick.wav", "D:/P/snare.wav", "D:/P/hat.wav" }
local pack_b = { "E:/Elsewhere/kick.wav", "E:/Elsewhere/snare.wav", "E:/Elsewhere/hat.wav" }
check("the same names anywhere match", Rng.fingerprint(pack_a) == Rng.fingerprint(pack_b),
  Rng.fingerprint(pack_b))

local extra = { "D:/P/kick.wav", "D:/P/snare.wav", "D:/P/hat.wav", "D:/P/ride.wav" }
check("one extra sample shows up", Rng.fingerprint(pack_a) ~= Rng.fingerprint(extra))

local renamed = { "D:/P/kick.wav", "D:/P/snare.wav", "D:/P/hats.wav" }
check("a renamed sample shows up", Rng.fingerprint(pack_a) ~= Rng.fingerprint(renamed))
print("  " .. Rng.fingerprint(pack_a) .. "  vs  " .. Rng.fingerprint(extra))

-- 6. The batch mapping, which is what makes one kit out of a batch shareable.
print("batches")
local Engine = require("core.engine")
check("kit 1 is the seed itself", Engine.seed_for({ seed = 84213 }, 1) == 84213)
check("kit 34 is seed + 33", Engine.seed_for({ seed = 84213 }, 34) == 84246)
check("no seed means no seed", Engine.seed_for({}, 3) == nil)

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
