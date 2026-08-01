-- A pocket random generator, so that a seed means the same thing everywhere.
--
-- Lua's own math.random cannot do this job. Up to Lua 5.3 it hands the work to
-- the C library, whose sequence differs between Windows and macOS -- so the
-- same seed would build one kit on your machine and a different one on someone
-- else's, which is the exact thing a shared seed exists to rule out. Even
-- within one platform the sequence is a promise nobody made.
--
-- So: a plain linear congruential generator. Eleven lines of arithmetic that
-- behave identically on every platform and every Lua version from 5.1 up. No
-- bitwise operators (Lua 5.2 and earlier have none), no integer division, and
-- deliberately no multiplier large enough to push a product past 2^53, where a
-- double stops being exact and the results would start depending on the
-- hardware again. A * MOD is about 2^52.7, which is the reason A is this
-- number and not a fancier one.

local M = {}

local A, C, MOD = 1664525, 1013904223, 4294967296

local Gen = {}
Gen.__index = Gen

function M.new(seed)
  local s = math.floor(math.abs(tonumber(seed) or 0)) % MOD
  local g = setmetatable({ s = s }, Gen)
  -- A batch is seeded with consecutive numbers, so what neighbouring seeds do
  -- is not a detail: it is the common case.
  --
  -- Spinning the generator is not enough on its own, and the way it fails is
  -- worth spelling out, because it looks fine. A step is linear, so two states
  -- one apart stay a *fixed* distance apart however many times you step them.
  -- Seeds 84213, 84214, 84215... opened on 936, 445, 953, 462, 971 -- two bands
  -- with everything alternating between them. Every kit in a batch would have
  -- drawn its first slot from one of two corners of the pool, and the numbers
  -- would have looked random enough in isolation to never be questioned.
  --
  -- Swapping the halves of the state between steps breaks it, being a
  -- permutation that is not linear in the arithmetic the step is linear in.
  for _ = 1, 6 do
    g:number()
    g.s = (g.s % 65536) * 65536 + math.floor(g.s / 65536)
  end
  return g
end

-- A float in [0,1), built from the high bits. The low bits of an LCG cycle
-- with very short periods -- the lowest alternates 0,1,0,1 forever -- so
-- reading the whole state as a fraction would give a visibly poor pick. The
-- top 24 bits are plenty: a pool would need 16 million samples to notice.
function Gen:number()
  self.s = (A * self.s + C) % MOD
  return math.floor(self.s / 256) / 16777216
end

-- math.random's contract, minus the float-range form Kit Maker never uses.
function Gen:random(m, n)
  if not m then return self:number() end
  if not n then m, n = 1, m end
  if n < m then return m end
  return m + math.floor(self:number() * (n - m + 1))
end

-- The generator a run is currently using.
--
-- Rendering a kit is one synchronous pass, so rather than threading a
-- generator object through the picker, the bias and the engine -- a dozen
-- signatures, every one of them somewhere to forget it and silently fall back
-- to unseeded picks -- a run installs one here and takes it away afterwards.
-- With nothing installed this is math.random verbatim, which is what every
-- unseeded run gets and what the sequencer keeps using regardless.
local active = nil

function M.use(seed)
  active = seed and M.new(seed) or nil
  return active
end

function M.clear()
  active = nil
end

function M.active()
  return active
end

function M.random(m, n)
  if active then return active:random(m, n) end
  if not m then return math.random() end
  if not n then return math.random(m) end
  return math.random(m, n)
end

-- What to show someone who wants to write a seed down. Six digits: long enough
-- that two kits are unlikely to collide, short enough to read over the phone.
function M.new_seed()
  return math.random(100000, 999999)
end

-- A pack's fingerprint. A seed alone does not describe a kit -- the same seed
-- over a different set of samples gives a different kit, correctly but
-- confusingly. This is the other half of the answer: cheap, and good enough to
-- say "we are not looking at the same pack" rather than to prove that we are.
--
-- Sorted here rather than trusting the caller, because the callers differ: a
-- folder scan arrives in order, but a Builder's pools are walked with pairs()
-- and come out in whatever order the hash table gives, which is not even stable
-- between two runs of the same script.
function M.fingerprint(files)
  local names = {}
  for i = 1, #files do
    names[i] = files[i]:match("([^/\\]+)$") or files[i]
  end
  table.sort(names)

  local h = 5381
  for i = 1, #names do
    local name = names[i]
    for j = 1, #name do
      -- Kept under 2^53 by folding at every step, for the same reason as above.
      h = (h * 33 + name:byte(j)) % 16777216
    end
  end
  return string.format("%d-%06X", #names, h)
end

return M
