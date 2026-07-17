-- Cross-session used-samples log (milestone 3).
-- When a KitDef has export.write_usedlog enabled, the engine prefers samples
-- that were not yet used in a *previous* generation (persists across REAPER
-- restarts). Once a pool's samples are all used up, its history resets.

local r = reaper
local Json = require("core.json")

local M = {}

local cache = nil
local dirty = false

local function log_path()
  return r.GetResourcePath() .. "/TK_Kit_Maker/used_samples.json"
end

local function load()
  if cache then return cache end
  local f = io.open(log_path(), "r")
  if not f then cache = {}; return cache end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(Json.decode, content)
  cache = (ok and type(data) == "table") and data or {}
  return cache
end

function M.is_used(sample_path)
  local data = load()
  return data[sample_path] == true
end

-- Marks a sample as used in memory; call M.flush() to persist to disk.
function M.mark_used(sample_path)
  local data = load()
  data[sample_path] = true
  dirty = true
end

function M.clear_used(sample_path)
  local data = load()
  if data[sample_path] ~= nil then
    data[sample_path] = nil
    dirty = true
  end
end

-- Writes the in-memory log to disk. Call once per batch to avoid excessive IO.
function M.flush()
  if not dirty then return end
  local dir = r.GetResourcePath() .. "/TK_Kit_Maker"
  r.RecursiveCreateDirectory(dir, 0)
  local f = io.open(log_path(), "w")
  if not f then return end
  -- json.lua encodes an empty table as "[]"; that decodes back to a table
  -- either way, so is_used()/mark_used() still work correctly next load.
  f:write(Json.encode(cache or {}))
  f:close()
  dirty = false
end

function M.reset()
  cache = {}
  dirty = true
  M.flush()
end

return M
