-- Pools that hold a fixed list of files -- the ones cut out of a heatmap cell.
--
-- Every other pool is defined by its folders and its file list is a cache that
-- gets thrown away and rebuilt. A fixed pool inverts that: the list IS the
-- definition and nothing can rebuild it. Three separate places would happily
-- empty one, all of them silently, and each is checked here:
--
--   1. Scanner.scan_pool  -- eight call sites, two of them "rescan everything"
--   2. Presets.save       -- strips pool.files as a cache
--   3. Presets.load       -- blanks pool.files to force a rescan
--
-- The damage is quiet: the pool survives, keeps its name, and picks nothing.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

local TMP = (os.getenv("TEMP") or "."):gsub("\\", "/") .. "/tkkm_fixedpool"
os.execute('mkdir "' .. TMP:gsub("/", "\\") .. '" 2>nul')

reaper = {
  GetResourcePath = function() return TMP end,
  RecursiveCreateDirectory = function(d) os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end,
  EnumerateFiles = function() return nil end,
  EnumerateSubdirectories = function() return nil end,
}

local Scanner = require("core.scanner")
local Presets = require("data.presets")
local Picker = require("core.picker")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function cell_pool()
  return {
    id = "pool_1",
    alias = "Sub Legato",
    folders = {},
    recursive = false,
    files = { "D:/Samples/a.wav", "D:/Samples/deep/b.wav", "E:/Other/c.wav" },
    fixed = true,
    fixed_origin = "3 samples from the heatmap: frequency sub, decay legato",
    mode = "repeat",
    _bag = {},
  }
end

-- 1. A scan must leave it alone. Without the guard the folder loop runs over an
-- empty folder list and assigns the empty result, so the pool ends up with no
-- files at all -- from a button labelled "Scan".
print("scanning")
local pool = cell_pool()
Scanner.scan_pool(pool)
check("a fixed pool survives a scan", #pool.files == 3, #pool.files)
check("the files are unchanged", pool.files[1] == "D:/Samples/a.wav", pool.files[1])

-- The same call on an ordinary pool with no folders still empties it, which is
-- what makes the flag load-bearing rather than decorative.
local ordinary = { folders = {}, files = { "D:/x.wav" } }
Scanner.scan_pool(ordinary)
check("an ordinary folderless pool is still emptied", #ordinary.files == 0, #ordinary.files)

-- 2 and 3. Round-trip through a preset on disk.
print("preset round-trip")
local saved_ok, err = Presets.save("tkkm_fixedpool_test", { slots = {} }, { pool_1 = cell_pool() })
check("the preset saved", saved_ok == true, err)

local _, loaded = Presets.load("tkkm_fixedpool_test")
local back = loaded and loaded.pool_1
check("the pool came back", back ~= nil, back)
if back then
  check("with its files", #(back.files or {}) == 3, #(back.files or {}))
  check("still marked fixed", back.fixed == true, back.fixed)
  check("and still named", back.alias == "Sub Legato", back.alias)
  check("keeping where it came from", (back.fixed_origin or ""):find("heatmap", 1, true) ~= nil, back.fixed_origin)
end

-- An ordinary pool must NOT gain a saved file list: presets stay small and are
-- meant to rescan, so a moved sample library still resolves.
local _, plain = Presets.load("tkkm_fixedpool_test2")
Presets.save("tkkm_fixedpool_test2", { slots = {} },
  { pool_2 = { id = "pool_2", alias = "Kicks", folders = { "D:/Kicks" }, files = { "D:/Kicks/k.wav" } } })
_, plain = Presets.load("tkkm_fixedpool_test2")
check("an ordinary pool is rescanned, not restored", #((plain.pool_2 or {}).files or {}) == 0,
  #((plain.pool_2 or {}).files or {}))

-- 4. And it actually picks: a fixed pool feeds the Builder like any other, since
-- the picker only ever reads pool.files.
print("picking")
math.randomseed(1)
local drawn = {}
local from = cell_pool()
for _ = 1, 60 do
  local got = Picker.pick(from)
  if got then drawn[got] = true end
end
local n = 0
for _ in pairs(drawn) do n = n + 1 end
check("picks come out of the fixed list", n == 3, n)
for path in pairs(drawn) do
  check("nothing outside it: " .. path,
    path == "D:/Samples/a.wav" or path == "D:/Samples/deep/b.wav" or path == "E:/Other/c.wav", path)
end

os.remove(TMP .. "/TK_Kit_Maker/presets/tkkm_fixedpool_test.json")
os.remove(TMP .. "/TK_Kit_Maker/presets/tkkm_fixedpool_test2.json")

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

TEST_FAILED = fail
