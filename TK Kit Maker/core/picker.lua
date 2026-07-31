-- Random sample selection for a Pool.
-- Sample lock (a Slot's fixed file) is resolved by the engine before this is
-- ever called -- this module only implements the two Pool.mode behaviours.

local Bias = require("core.bias")
local Rng  = require("core.rng")

local M = {}

local function shuffle_indices(list)
  for i = #list, 2, -1 do
    local j = Rng.random(i)
    list[i], list[j] = list[j], list[i]
  end
  return list
end

local function fresh_bag(n)
  local bag = {}
  for i = 1, n do bag[i] = i end
  return shuffle_indices(bag)
end

local function bias_key(weights)
  if not weights then return "" end
  return weights.key or "w"
end

-- "repeat"  -- plain random pick, the same file may repeat across slots/kits
-- "use_up"  -- draws from a shuffled bag without repeats; once the bag runs
--              out it reshuffles a fresh bag from pool.files
function M.pick(pool, weights)
  if not pool or not pool.files or #pool.files == 0 then
    return nil
  end

  local n = #pool.files

  if pool.mode == "use_up" then
    local key = bias_key(weights)
    local bag = pool._bag
    if not bag or #bag == 0 then
      bag = fresh_bag(n)
      if weights then bag = Bias.order_indices(bag, weights) end
    elseif key ~= pool._bag_key then
      bag = weights and Bias.order_indices(bag, weights) or shuffle_indices(bag)
    end
    pool._bag = bag
    pool._bag_key = key
    local idx = table.remove(bag)
    return pool.files[idx]
  end

  if weights then
    return pool.files[Bias.pick_weighted(weights)]
  end

  return pool.files[Rng.random(n)]
end

return M
