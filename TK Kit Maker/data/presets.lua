-- KitDef + pools serialization for the Kit Builder (milestone 2).
-- Presets live under reaper.GetResourcePath() .. "/TK_Kit_Maker/presets/*.json"

local r = reaper
local Json = require("core.json")

local M = {}

local function presets_dir()
  return r.GetResourcePath() .. "/TK_Kit_Maker/presets"
end

local function sanitize_name(name)
  return (tostring(name or ""):gsub("[\\/:%*%?\"<>|]", "_"))
end

function M.list()
  r.RecursiveCreateDirectory(presets_dir(), 0)
  local names = {}
  local i = 0
  while true do
    local fn = r.EnumerateFiles(presets_dir(), i)
    if not fn then break end
    local name = fn:match("^(.*)%.json$")
    if name then names[#names + 1] = name end
    i = i + 1
  end
  table.sort(names)
  return names
end

-- Saves a full preset: kitdef + pools, stripped of runtime-only fields
-- (pool.files cache, pool._bag) so presets stay small and are rescanned fresh.
function M.save(name, kitdef, pools)
  r.RecursiveCreateDirectory(presets_dir(), 0)

  local pools_out = {}
  for id, pool in pairs(pools) do
    pools_out[id] = {
      id = pool.id,
      alias = pool.alias,
      folders = pool.folders,
      recursive = pool.recursive,
      mode = pool.mode,
      shape_mode = pool.shape_mode,
      folder_bias = pool.folder_bias,
      -- A fixed pool's file list is not a cache: it *is* the pool. It was cut
      -- out of a heatmap cell, so there is no folder to rebuild it from and it
      -- is the one list that has to travel with the preset.
      fixed = pool.fixed,
      fixed_origin = pool.fixed_origin,
      files = pool.fixed and pool.files or nil,
    }
  end

  local data = { kitdef = kitdef, pools = pools_out }
  local ok, encoded = pcall(Json.encode, data)
  if not ok then return false, "cannot serialize preset: " .. tostring(encoded) end

  local path = presets_dir() .. "/" .. sanitize_name(name) .. ".json"
  local f = io.open(path, "w")
  if not f then return false, "cannot write preset: " .. path end
  f:write(encoded)
  f:close()
  return true
end

function M.load(name)
  local path = presets_dir() .. "/" .. sanitize_name(name) .. ".json"
  local f = io.open(path, "r")
  if not f then return nil, "preset not found: " .. name end
  local content = f:read("*a")
  f:close()

  local ok, data = pcall(Json.decode, content)
  if not ok or type(data) ~= "table" then return nil, "invalid preset file" end

  local pools = {}
  for id, pool in pairs(data.pools or {}) do
    -- Everything else is rescanned fresh off disk; a fixed pool keeps the list
    -- it was saved with, because nothing would rescan it back.
    if not pool.fixed then pool.files = {} end
    pool.files = pool.files or {}
    pool.shape_mode = (pool.shape_mode == "loop" or pool.shape_mode == "oneshot") and pool.shape_mode or "all"
    pool._bag = {}
    pools[id] = pool
  end

  return data.kitdef, pools
end

function M.delete(name)
  return os.remove(M.path(name))
end

function M.path(name)
  return presets_dir() .. "/" .. sanitize_name(name) .. ".json"
end

-- The file as it stands, and putting one back byte for byte.
--
-- Deleting a preset removes a file, which no amount of snapshotting the pools
-- in memory can undo -- so the undo history keeps the bytes instead and writes
-- them back. Raw rather than decoded and re-encoded: a preset written by a
-- newer version may hold fields this one does not know, and re-saving through
-- the loader would quietly drop them.
function M.read_raw(name)
  local f = io.open(M.path(name), "rb")
  if not f then return nil end
  local data = f:read("*a")
  f:close()
  return data
end

function M.write_raw(name, data)
  if not data then return false end
  r.RecursiveCreateDirectory(presets_dir(), 0)
  local f = io.open(M.path(name), "wb")
  if not f then return false end
  f:write(data)
  f:close()
  return true
end

return M
