local r = reaper

local M = {}

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  return (path:gsub("/+$", ""))
end
M.normalize = normalize

local function file_exists(path)
  if not path or path == "" then return false end
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end
M.file_exists = file_exists

local function dir_exists(path)
  if not path or path == "" then return false end
  local clean = path:gsub("[/\\]+$", "")
  local ok, _, code = os.rename(clean, clean)
  if ok then return true end
  if code == 13 then return true end
  if r.EnumerateFiles and r.EnumerateFiles(clean, 0) ~= nil then return true end
  if r.EnumerateSubdirectories and r.EnumerateSubdirectories(clean, 0) ~= nil then return true end
  return false
end
M.dir_exists = dir_exists

local function path_exists(path)
  return file_exists(path) or dir_exists(path)
end
M.path_exists = path_exists

function M.basename(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

function M.dirname(path)
  local p = normalize(path)
  return p:match("^(.*)/[^/]+$") or ""
end

-- Splits a full path into { prefix, suffix } around the last N path segments,
-- so that two paths sharing the same tail can be diffed at the differing root.
local function segments(path)
  local out = {}
  for seg in normalize(path):gmatch("[^/]+") do
    out[#out + 1] = seg
  end
  return out
end

-- Given an old path and the new (found) path, derive the differing prefix pair.
-- The longest common trailing run of segments is treated as the shared suffix;
-- everything before it is the prefix that changed (drive letter / moved root).
function M.derive_prefix_pair(old_path, new_path)
  local a = segments(old_path)
  local b = segments(new_path)
  local ai, bi = #a, #b
  local shared = 0
  while ai >= 1 and bi >= 1 and a[ai]:lower() == b[bi]:lower() do
    shared = shared + 1
    ai = ai - 1
    bi = bi - 1
  end
  if shared == 0 then return nil end
  local old_prefix = table.concat(a, "/", 1, ai)
  local new_prefix = table.concat(b, "/", 1, bi)
  if old_prefix == "" or new_prefix == "" then return nil end
  if old_prefix:lower() == new_prefix:lower() then return nil end
  return { old = old_prefix, new = new_prefix }
end

-- Applies remembered prefix remaps to a broken path. Returns the first
-- remapped path that actually exists on disk, or nil.
function M.apply_prefix_map(path, prefix_map)
  if type(prefix_map) ~= "table" then return nil end
  local target = normalize(path)
  local lower = target:lower()
  for _, entry in ipairs(prefix_map) do
    local old_prefix = normalize(entry.old or "")
    local new_prefix = normalize(entry.new or "")
    if old_prefix ~= "" and new_prefix ~= "" then
      local ol = old_prefix:lower()
      if lower:sub(1, #ol) == ol then
        local candidate = new_prefix .. target:sub(#old_prefix + 1)
        if file_exists(candidate) then
          return candidate
        end
      end
    end
  end
  return nil
end

-- Adds/updates a prefix mapping in place (most recent first, deduped).
function M.remember_prefix(prefix_map, old_prefix, new_prefix)
  if type(prefix_map) ~= "table" then return end
  old_prefix = normalize(old_prefix)
  new_prefix = normalize(new_prefix)
  if old_prefix == "" or new_prefix == "" then return end
  if old_prefix:lower() == new_prefix:lower() then return end
  for i = #prefix_map, 1, -1 do
    local e = prefix_map[i]
    if normalize(e.old):lower() == old_prefix:lower() then
      table.remove(prefix_map, i)
    end
  end
  table.insert(prefix_map, 1, { old = old_prefix, new = new_prefix })
  while #prefix_map > 24 do
    table.remove(prefix_map)
  end
end

local AUDIO_EXT = {
  wav = true, wave = true, aif = true, aiff = true, flac = true,
  mp3 = true, ogg = true, opus = true, m4a = true, wv = true,
}

local function has_audio_ext(name)
  local ext = tostring(name or ""):match("%.([%w]+)$")
  return ext and AUDIO_EXT[ext:lower()] == true
end

-- Recursively searches root for a file whose name matches basename
-- (case-insensitive). Bounded by max_dirs to stay responsive on huge trees.
-- Returns the full path of the first match, or nil.
function M.search_recursive(root, basename, max_dirs)
  root = normalize(root)
  if root == "" or not dir_exists(root) then return nil end
  local target = tostring(basename or ""):lower()
  if target == "" then return nil end
  max_dirs = tonumber(max_dirs) or 4000
  local queue = { root }
  local visited = 0
  while #queue > 0 and visited < max_dirs do
    local dir = table.remove(queue, 1)
    visited = visited + 1
    local i = 0
    while true do
      local fn = r.EnumerateFiles(dir, i)
      if not fn then break end
      if fn:lower() == target then
        return dir .. "/" .. fn
      end
      i = i + 1
    end
    local j = 0
    while true do
      local sub = r.EnumerateSubdirectories(dir, j)
      if not sub then break end
      queue[#queue + 1] = dir .. "/" .. sub
      j = j + 1
    end
  end
  return nil
end
M.has_audio_ext = has_audio_ext

return M
