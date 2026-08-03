-- The shared-memory map, which lives in two files at once.
--
-- ui/sequencer_view.lua writes gmem and data/seq_engine_jsfx.lua reads it, and
-- nothing has ever checked that the two agree. They are plain numbers typed out
-- twice. Move one and the engine reads velocity where the Lua side wrote gate:
-- no error, no crash, just a sequencer that plays the wrong thing.
--
-- This reads the constants straight out of both sources rather than requiring
-- the modules, because the UI module cannot load without ReaImGui and the JSFX
-- is not Lua at all.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function slurp(rel)
  local f = assert(io.open(KIT .. rel, "rb"), "cannot read " .. rel)
  local s = f:read("*a")
  f:close()
  return s
end

local lua = slurp("ui/sequencer_view.lua")
local jsfx = slurp("data/seq_engine_jsfx.lua")

-- Pulls a constant out of either source. Two shapes have to be handled, and
-- getting this wrong is quiet: the Lua side declares several at once
--
--   local L_ON, L_VEL, L_GATE = 16, 32, 48
--
-- so a naive "L_GATE%s*=%s*(%d+)" matches the 16 that belongs to L_ON. The
-- JSFX side writes them one per statement. Both are read here, multi-assignment
-- first, because that is the one that silently returns a wrong number rather
-- than nothing at all.
local function const(src, name)
  for names, values in src:gmatch("local ([%w_%s,]-)%s*=%s*([%-%d%s,]+)") do
    local list, vals = {}, {}
    for n in names:gmatch("[%w_]+") do list[#list + 1] = n end
    for v in values:gmatch("%-?%d+") do vals[#vals + 1] = tonumber(v) end
    if #list > 1 then
      for i, n in ipairs(list) do
        if n == name then return vals[i] end
      end
    end
  end
  local v = src:match("[^%w_]" .. name .. "%s*=%s*(%-?%d+)")
  return tonumber(v)
end

print("lane block")
for _, name in ipairs({ "LANE_BASE", "LANE_STRIDE" }) do
  local a = const(lua, name)
  local b = const(jsfx, name)
  print(string.format("  %-12s lua %s   jsfx %s", name, tostring(a), tostring(b)))
  check(name .. " is defined in both", a ~= nil and b ~= nil, tostring(a) .. "/" .. tostring(b))
  check(name .. " agrees", a == b, tostring(a) .. " vs " .. tostring(b))
end

-- The per-step blocks. If one of these moves in only one file, the sequencer
-- plays the wrong parameter for every step of every lane.
print("per-step blocks")
for _, name in ipairs({ "L_ON", "L_VEL", "L_GATE", "L_LEN", "L_SUB", "L_PROB", "L_PITCH" }) do
  local a = const(lua, name)
  local b = const(jsfx, name)
  check(name .. " agrees", a ~= nil and a == b, tostring(a) .. " vs " .. tostring(b))
end

local base = const(lua, "LANE_BASE")
local stride = const(lua, "LANE_STRIDE")
local pitch = const(lua, "L_PITCH")
local steps = 16

-- The lane block is exactly full, which is why the groove data had to go
-- somewhere else. If this ever stops being true, say so -- it means either
-- there is room after all, or something has overflowed into the next lane.
print("occupancy")
local used = pitch + steps
print(string.format("  %d of %d slots used per lane", used, stride))
check("nothing overflows the lane stride", used <= stride, used)
check("the block really is full", used == stride, used)

-- Groove sits above every lane. Getting this wrong would have the groove
-- tables writing over lane 14's step data.
-- Groove is now written on one side and read on the other too, so the same
-- two-files-one-map problem applies to it. The names differ by prefix: the Lua
-- side keeps them in a table (HDR), the JSFX in flat globals (GRV_HDR).
print("groove region")
for _, pair in ipairs({
  { "HDR", "GRV_HDR" }, { "HDR_STRIDE", "GRV_HDR_STRIDE" },
  { "BASE", "GRV_BASE" }, { "STRIDE", "GRV_STRIDE" }, { "MAX_STEPS", "GRV_STEPS" },
}) do
  local a2 = const(lua, pair[1])
  local b2 = const(jsfx, pair[2])
  check(pair[1] .. " agrees with " .. pair[2], a2 ~= nil and a2 == b2,
    tostring(a2) .. " vs " .. tostring(b2))
end

local lanes_end = base + 16 * stride
local ghdr = const(lua, "HDR")
local gbase = const(lua, "BASE")
local gstride = const(lua, "STRIDE")
local gsteps = const(lua, "MAX_STEPS")
print(string.format("  lanes end at %d | header %d | tables %d..%d",
  lanes_end, ghdr, gbase, gbase + 16 * gstride))
check("the header clears the lanes", ghdr >= lanes_end, ghdr)
check("the tables clear the header", gbase >= ghdr + 16 * 4, gbase)
check("a groove table holds offsets and velocities", gstride >= gsteps * 2, gstride)
check("and covers a 16-step bar", gsteps >= 16, gsteps)

-- The engine is reinstalled when its version changes, so a memory map that
-- moved without a version bump would leave old engines reading the new layout.
print("engine version")
local ver = const(jsfx, "M.version") or tonumber(jsfx:match("M%.version%s*=%s*(%d+)"))
local stamped = tonumber(jsfx:match("TK_ENGINE_VERSION:(%d+)"))
print(string.format("  module %s | stamped in the source %s", tostring(ver), tostring(stamped)))
check("the version is stamped in the JSFX too", ver ~= nil and ver == stamped,
  tostring(ver) .. " vs " .. tostring(stamped))

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
