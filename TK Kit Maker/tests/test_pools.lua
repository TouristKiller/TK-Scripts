-- Pool id allocation. Loading a preset brings its own pool_1, pool_2... while
-- the counter stays where it was, so "+ Pool" used to land on top of a pool the
-- preset had filled.

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

-- Mirrors ui/builder_view.lua.
local function add_pool(builder, pools, alias)
  local id
  repeat
    id = "pool_" .. tostring(builder.next_pool_n)
    builder.next_pool_n = builder.next_pool_n + 1
  until not pools[id]
  pools[id] = { id = id, alias = alias or ("Pool " .. id:gsub("pool_", "")), folders = {} }
  builder.pool_order[#builder.pool_order + 1] = id
  return id
end

local function pool_order_from(pools)
  local order = {}
  for id in pairs(pools) do order[#order + 1] = id end
  table.sort(order, function(a, b)
    local na = tonumber(a:match("^pool_(%d+)$"))
    local nb = tonumber(b:match("^pool_(%d+)$"))
    if na and nb then return na < nb end
    return a < b
  end)
  return order
end

local function count(t)
  local n = 0
  for _ in pairs(t) do n = n + 1 end
  return n
end

-- 1. a fresh session numbers them in order
local builder = { next_pool_n = 1, pool_order = {} }
local pools = {}
check("first pool is pool_1", add_pool(builder, pools) == "pool_1", "?")
check("second is pool_2", add_pool(builder, pools) == "pool_2", "?")

-- 2. THE bug: load a preset (which resets pools but not the counter) and add one
builder = { next_pool_n = 1, pool_order = {} }   -- counter as a fresh session has it
pools = {
  pool_1 = { id = "pool_1", alias = "Kick", folders = { "D:/Kicks" } },
  pool_2 = { id = "pool_2", alias = "Snare", folders = { "D:/Snares" } },
}
builder.pool_order = pool_order_from(pools)

local new_id = add_pool(builder, pools)
check("the new pool does not reuse a loaded id", new_id == "pool_3", new_id)
check("the loaded pool is untouched", pools.pool_1.alias == "Kick", pools.pool_1.alias)
check("its folders are still there", #pools.pool_1.folders == 1, #pools.pool_1.folders)
check("there are three pools now", count(pools) == 3, count(pools))

local seen = {}
for _, id in ipairs(builder.pool_order) do
  check("no id appears twice in the order", not seen[id], id)
  seen[id] = true
end
check("the order lists all three", #builder.pool_order == 3, #builder.pool_order)

-- 3. gaps are filled rather than skipped past, and never collide
builder = { next_pool_n = 1, pool_order = {} }
pools = { pool_1 = {}, pool_3 = {} }
check("the gap is used", add_pool(builder, pools) == "pool_2", "?")
check("then it carries on past the highest", add_pool(builder, pools) == "pool_4", "?")

-- 4. natural ordering: a plain sort puts pool_10 between pool_1 and pool_2
pools = {}
for i = 1, 12 do pools["pool_" .. i] = {} end
local order = pool_order_from(pools)
check("pool_2 comes second, not pool_10", order[2] == "pool_2", order[2])
check("pool_10 comes tenth", order[10] == "pool_10", order[10])

print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
