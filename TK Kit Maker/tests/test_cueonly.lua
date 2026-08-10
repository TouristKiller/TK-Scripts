-- "Cue file only": the export that keeps the stitched WAV and removes the
-- one-shots that went into it.
--
-- This is the one thing in Kit Maker that deletes files, so what is worth
-- testing is not that it deletes -- it is that it refuses to delete anything
-- the stitcher did not report taking in. A sample the stitcher skipped is not
-- in the stitched WAV, so removing it would be the single case where this
-- destroys audio that has no other copy.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

local TMP = (os.getenv("TEMP") or "."):gsub("\\", "/") .. "/tkkm_cueonlytest"
os.execute('mkdir "' .. TMP:gsub("/", "\\") .. '" 2>nul')

reaper = {
  GetResourcePath = function() return TMP end,
  RecursiveCreateDirectory = function(d) os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end,
  time_precise = os.clock,
  GetPlayState = function() return 0 end,
  EnumerateFiles = function() return nil end,
  EnumerateSubdirectories = function() return nil end,
  new_array = function(n) local a = {} for i = 1, n do a[i] = 0 end a.clear = function() end return a end,
}

local Engine = require("core.engine")

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function write_file(name)
  local f = assert(io.open(TMP .. "/" .. name, "wb"))
  f:write("not really audio")
  f:close()
end

local function exists(name)
  local f = io.open(TMP .. "/" .. name, "rb")
  if f then f:close() return true end
  return false
end

local NAMES = {
  "001_kick_C1.wav",
  "002_snare_D1.wav",
  "003_vox_E1.mp3",       -- the stitcher cannot read this one
  "004_loop_F1.wav",      -- over the length limit, so it was skipped too
}
for _, n in ipairs(NAMES) do write_file(n) end

local results = {}
for i, n in ipairs(NAMES) do results[i] = { out_name = n } end

-- What the stitcher reports: the two it actually took in.
local included = { "001_kick_C1.wav", "002_snare_D1.wav" }

local kept, removed = Engine.reduce_to_stitched(TMP, results, included)

print("after the reduction")
for _, n in ipairs(NAMES) do
  print(string.format("  %-20s %s", n, exists(n) and "kept" or "removed"))
end

check("the two stitched files are gone",
  not exists(NAMES[1]) and not exists(NAMES[2]), exists(NAMES[1]))
check("the skipped mp3 survives", exists(NAMES[3]), false)
check("the too-long sample survives", exists(NAMES[4]), false)
check("it reports two removed", removed == 2, removed)
check("it names both survivors", #kept == 2, #kept)
check("and names them correctly",
  (kept[1] == NAMES[3] and kept[2] == NAMES[4]), table.concat(kept, ", "))

-- Nothing reported as included means nothing is deleted. A stitch that failed
-- must never be able to take the kit with it.
for _, n in ipairs(NAMES) do write_file(n) end
local kept2, removed2 = Engine.reduce_to_stitched(TMP, results, nil)
check("no included list deletes nothing", removed2 == 0, removed2)
check("and everything is reported kept", #kept2 == #NAMES, #kept2)
check("the files are all still there",
  exists(NAMES[1]) and exists(NAMES[2]) and exists(NAMES[3]) and exists(NAMES[4]), false)

for _, n in ipairs(NAMES) do os.remove(TMP .. "/" .. n) end

if fail == 0 then print("\nALL CHECKS PASSED") end
TEST_FAILED = fail
