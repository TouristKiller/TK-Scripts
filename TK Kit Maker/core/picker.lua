-- Random sample selection for a Pool.
-- Sample lock (a Slot's fixed file) is resolved by the engine before this is
-- ever called -- this module only implements the two Pool.mode behaviours.

local M = {}

local function shuffle(list)
  local copy = {}
  for i, v in ipairs(list) do copy[i] = v end
  for i = #copy, 2, -1 do
    local j = math.random(i)
    copy[i], copy[j] = copy[j], copy[i]
  end
  return copy
end

-- "repeat"  -- plain random pick, the same file may repeat across slots/kits
-- "use_up"  -- draws from a shuffled bag without repeats; once the bag runs
--              out it reshuffles a fresh bag from pool.files
function M.pick(pool)
  if not pool or not pool.files or #pool.files == 0 then
    return nil
  end

  if pool.mode == "use_up" then
    if not pool._bag or #pool._bag == 0 then
      pool._bag = shuffle(pool.files)
    end
    return table.remove(pool._bag)
  end

  return pool.files[math.random(#pool.files)]
end

return M
