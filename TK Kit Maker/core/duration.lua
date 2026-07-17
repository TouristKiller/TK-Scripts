-- Media duration lookup (seconds) via REAPER's PCM source API, so every
-- format REAPER can read is supported without decoding. Results are cached
-- per path for the session.

local r = reaper
local M = {}

local cache = {}

-- Returns the duration in seconds, or nil when the file can't be read.
function M.seconds(path)
  local hit = cache[path]
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

  cache[path] = len or false
  return len
end

function M.clear_cache()
  cache = {}
end

return M
