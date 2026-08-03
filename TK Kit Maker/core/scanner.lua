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

-- Names sort case-insensitively, by the lower-cased name with the raw one as
-- tie-break. Windows and macOS disagree about where uppercase belongs, and the
-- point of sorting at all is that the order is the same everywhere.
local function by_name(a, b)
  local la, lb = a:lower(), b:lower()
  if la ~= lb then return la < lb end
  return a < b
end

-- Sorted, not in the order the filesystem happens to hand things back.
--
-- That order is nobody's promise: it varies between filesystems, and copying a
-- pack to another drive can change it. Every position downstream is built on
-- this list -- which sample a seed picks, which one a "use up" bag hands out
-- next -- so an unsorted scan would mean the same seed over the same samples
-- building a different kit on someone else's machine, with nothing on screen
-- to explain why.
local function scan_dir(path, recursive, results)
  path = normalize(path)
  local prefix = path .. "/"

  local files = {}
  local i = 0
  while true do
    local fn = r.EnumerateFiles(path, i)
    if not fn then break end
    if is_audio_file(fn) then
      files[#files + 1] = fn
    end
    i = i + 1
  end
  table.sort(files, by_name)
  for k = 1, #files do
    results[#results + 1] = prefix .. files[k]
  end

  if recursive then
    local dirs = {}
    local j = 0
    while true do
      local dn = r.EnumerateSubdirectories(path, j)
      if not dn then break end
      dirs[#dirs + 1] = dn
      j = j + 1
    end
    table.sort(dirs, by_name)
    for k = 1, #dirs do
      scan_dir(prefix .. dirs[k], recursive, results)
    end
  end
end

-- The direct subfolders of `root` that are worth adding as collections.
--
-- One level, deliberately. Working out by itself which folder in a tree is "a
-- pack" cannot be done: one library keeps them two deep, the next puts the
-- audio another two levels down under WAV/Kicks, and a rule that fits one is
-- wrong for the other. The person who owns the library is the only one who
-- knows, and picking the folder whose children are the packs IS them saying so.
-- So this asks no questions of the tree beyond "is there audio under here".
--
-- The enumerators are passed in, so this knows nothing about REAPER.
--
--   files(dir) -> array of filenames
--   dirs(dir)  -> array of subfolder names
--
-- Returns an array of { path, name, count }, sorted by name. `opts.skip` is a
-- set of already-taken paths, lower-cased, so a second run over the same parent
-- offers only what is new.
function M.subfolder_packs(root, files, dirs, opts)
  opts = opts or {}
  local skip = opts.skip or {}
  -- Deep enough for a pack that buries its audio under WAV/24bit/Kicks, and
  -- short of walking somebody's whole drive.
  local max_depth = opts.max_depth or 6
  root = normalize(root)

  local function count_audio(dir, depth)
    local n = 0
    for _, fn in ipairs(files(dir) or {}) do
      if is_audio_file(fn) then n = n + 1 end
    end
    if depth < max_depth then
      for _, dn in ipairs(dirs(dir) or {}) do
        n = n + count_audio(dir .. "/" .. dn, depth + 1)
      end
    end
    return n
  end

  local out = {}
  for _, dn in ipairs(dirs(root) or {}) do
    local path = root .. "/" .. dn
    -- Counted through the whole subtree, not just the top: a pack whose samples
    -- sit in a WAV folder would otherwise look empty and be skipped.
    --
    -- Folders with no audio at all are left out on purpose. Packs routinely
    -- ship a Documentation or MIDI folder beside the samples, and those are
    -- subfolders too -- adding them would mean a handful of empty collections
    -- to delete by hand every time.
    if not skip[path:lower()] then
      local n = count_audio(path, 1)
      if n > 0 then
        out[#out + 1] = { path = path, name = dn, count = n }
      end
    end
  end

  table.sort(out, function(a, b)
    local la, lb = a.name:lower(), b.name:lower()
    if la ~= lb then return la < lb end
    return a.name < b.name
  end)
  return out
end

-- Scans all folders configured on the pool and refreshes pool.files in place.
-- Returns the file list (also stored on pool.files).
function M.scan_pool(pool)
  -- A fixed pool carries its own file list -- picked out of a heatmap cell
  -- rather than read off a folder -- so there is nothing to rebuild it from and
  -- a scan would simply empty it. Guarding here rather than at the call sites
  -- because there are eight of them, including two that scan everything.
  if pool.fixed then return pool.files or {} end

  local results = {}
  local folder_of = {}
  local index = 0
  for _, folder in ipairs(pool.folders or {}) do
    index = index + 1
    if folder and folder ~= "" then
      local before = #results
      scan_dir(folder, pool.recursive ~= false, results)
      for i = before + 1, #results do folder_of[i] = index end
    end
  end
  pool.files = results
  pool.file_folder = folder_of
  pool.folder_count = index
  pool._bag = {} -- invalidate use_up bag; it gets rebuilt from the fresh file list on next pick
  pool._views = nil -- invalidate the filtered pick views for the same reason
  pool._w = nil
  pool._w_key = nil
  return results
end

return M
