-- Media duration lookup (seconds) via REAPER's PCM source API, so every
-- format REAPER can read is supported without decoding. Results are cached
-- per path and persisted to disk so length-based sorting stays instant.

local r = reaper
local M = {}

local CACHE_DIR   = r.GetResourcePath() .. "/TK_Kit_Maker"
local CACHE_PATH  = CACHE_DIR .. "/duration_cache.txt"
local CACHE_TAG   = "TKKM-DURCACHE-1"
local MAX_ENTRIES = 200000

local cache = {}
local entries = 0
local loaded = false
local dirty = false

local function key_of(path)
  return (tostring(path or ""):gsub("\\", "/"))
end

local function load_cache()
  loaded = true
  local f = io.open(CACHE_PATH, "r")
  if not f then return end
  local first = f:read("*l")
  if first ~= CACHE_TAG then
    f:close()
    return
  end
  for line in f:lines() do
    local secs, path = line:match("^([^\t]*)\t(.+)$")
    if path then
      local n = tonumber(secs)
      cache[path] = (n and n >= 0) and n or false
      entries = entries + 1
    end
  end
  f:close()
end

local function ensure_loaded()
  if not loaded then load_cache() end
end

function M.flush()
  if not dirty then return end
  dirty = false
  r.RecursiveCreateDirectory(CACHE_DIR, 0)
  local f = io.open(CACHE_PATH, "w")
  if not f then return end
  f:write(CACHE_TAG, "\n")
  local written = 0
  for path, value in pairs(cache) do
    f:write(value and string.format("%.6f", value) or "-1", "\t", path, "\n")
    written = written + 1
    if written >= MAX_ENTRIES then break end
  end
  f:close()
end

-- Returns the duration in seconds, or nil when the file can't be read.
function M.seconds(path)
  ensure_loaded()
  local k = key_of(path)
  local hit = cache[k]
  if hit ~= nil then
    return hit ~= false and hit or nil
  end

  local len
  local src = r.PCM_Source_CreateFromFile(path)
  if src then
    local length, is_qn = r.GetMediaSourceLength(src)
    if not is_qn then len = length end
    r.PCM_Source_Destroy(src)
  end

  cache[k] = len or false
  entries = entries + 1
  dirty = true
  return len
end

function M.is_cached(path)
  ensure_loaded()
  return cache[key_of(path)] ~= nil
end

-- Stateful pre-scan so a big pool can be measured across UI frames instead of
-- blocking the defer loop on the first pick.
function M.new_prefetch(files)
  ensure_loaded()
  local todo = {}
  local seen = {}
  for _, f in ipairs(files or {}) do
    local k = key_of(f)
    if cache[k] == nil and not seen[k] then
      seen[k] = true
      todo[#todo + 1] = f
    end
  end
  return {
    files = todo,
    index = 0,
    total = #todo,
    step = function(self, budget)
      budget = budget or 64
      local n = 0
      while self.index < self.total and n < budget do
        self.index = self.index + 1
        M.seconds(self.files[self.index])
        n = n + 1
      end
      if self.index >= self.total then
        M.flush()
        return false
      end
      return true
    end,
  }
end

function M.clear_cache()
  cache = {}
  entries = 0
  loaded = false
  dirty = false
  os.remove(CACHE_PATH)
end

function M.cache_size()
  ensure_loaded()
  return entries
end

return M
