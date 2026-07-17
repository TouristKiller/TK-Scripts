-- Recursively scans a Pool's source folders for audio files.
-- UI-independent and fully testable without a window (see architecture doc, section 3).

local r = reaper
local M = {}

local AUDIO_EXTENSIONS = {
  wav = true, aif = true, aiff = true, flac = true, mp3 = true, ogg = true,
}

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  return (path:gsub("/+$", ""))
end
M.normalize = normalize

local function is_audio_file(name)
  local ext = name:match("%.([%w]+)$")
  return ext ~= nil and AUDIO_EXTENSIONS[ext:lower()] == true
end
M.is_audio_file = is_audio_file

local function scan_dir(path, recursive, results)
  path = normalize(path)
  local prefix = path .. "/"

  local i = 0
  while true do
    local fn = r.EnumerateFiles(path, i)
    if not fn then break end
    if is_audio_file(fn) then
      results[#results + 1] = prefix .. fn
    end
    i = i + 1
  end

  if recursive then
    local j = 0
    while true do
      local dn = r.EnumerateSubdirectories(path, j)
      if not dn then break end
      scan_dir(prefix .. dn, recursive, results)
      j = j + 1
    end
  end
end

-- Scans all folders configured on the pool and refreshes pool.files in place.
-- Returns the file list (also stored on pool.files).
function M.scan_pool(pool)
  local results = {}
  for _, folder in ipairs(pool.folders or {}) do
    if folder and folder ~= "" then
      scan_dir(folder, pool.recursive ~= false, results)
    end
  end
  pool.files = results
  pool._bag = {} -- invalidate use_up bag; it gets rebuilt from the fresh file list on next pick
  pool._views = nil -- invalidate the filtered pick views for the same reason
  return results
end

return M
