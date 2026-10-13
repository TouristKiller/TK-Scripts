-- Where Time Machine keeps its versions, and the slow jobs that fill it.
--
-- Layout under the chosen location:
--
--   <location>/TK Time Machine/<history id>/manifest.json
--   <location>/TK Time Machine/<history id>/20261013-143205.rpp
--
-- One folder per history, named by an id that is also written into the
-- project itself (project ExtState "TK_TIME_MACHINE" / "id"). The id travels
-- with the .rpp, so a project that was moved or renamed finds its history
-- again on its first save; the path in the manifest is only the fallback for
-- projects saved before they had an id.
--
-- Nothing is kept inside the project: a history stored in the .rpp would make
-- every version contain all the versions before it.
--
-- Copying and moving run as jobs that do a slice of work per call, so a
-- 64 MB project never stalls the Workbench frame. Each job's step(budget)
-- returns true while it has more to do.

local r = reaper
local json = require("core.json")

local M = {}

M.FOLDER_NAME = "TK Time Machine"
M.EXT_SECTION = "TK_TIME_MACHINE"
M.EXT_KEY = "id"
M.CHUNK_BYTES = 2 * 1024 * 1024

local sep = package.config:sub(1, 1)

-- Paths -----------------------------------------------------------------------

function M.join(...)
  local parts = { ... }
  local result = ""
  for index, part in ipairs(parts) do
    part = tostring(part or "")
    if index == 1 then
      result = part:gsub("[\\/]+$", "")
    elseif part ~= "" then
      result = result .. sep .. part:gsub("^[\\/]+", "")
    end
  end
  return result
end

function M.default_location()
  return r.GetResourcePath()
end

function M.root_for(location)
  location = tostring(location or "")
  if location == "" then location = M.default_location() end
  location = location:gsub("[\\/]+$", "")
  -- Picking the Time Machine folder itself instead of its parent is an easy
  -- slip; do not nest a second one inside it.
  if location:match("[\\/]" .. M.FOLDER_NAME:gsub("%p", "%%%0") .. "$") then return location end
  return M.join(location, M.FOLDER_NAME)
end

function M.normalize_path(path)
  return tostring(path or ""):gsub("/", "\\"):lower()
end

function M.file_size(path)
  local handle = path and io.open(path, "rb")
  if not handle then return nil end
  local size = handle:seek("end")
  handle:close()
  return size
end

function M.file_exists(path)
  local handle = path and path ~= "" and io.open(path, "rb")
  if handle then handle:close(); return true end
  return false
end

function M.ensure_dir(path)
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path, 0) end
end

local function list_entries(enumerate, path)
  local result = {}
  if not enumerate then return result end
  enumerate(path, -1)
  local index = 0
  while true do
    local name = enumerate(path, index)
    if not name or name == "" then break end
    result[#result + 1] = name
    index = index + 1
  end
  return result
end

function M.list_files(path) return list_entries(r.EnumerateFiles, path) end
function M.list_dirs(path) return list_entries(r.EnumerateSubdirectories, path) end

function M.read_file(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local text = handle:read("a")
  handle:close()
  return text
end

-- Write beside the target and swap, so a crash never leaves half a manifest.
-- Windows will not rename onto an existing file, hence the remove first.
function M.write_file(path, text)
  local temp = path .. ".tmp"
  local handle = io.open(temp, "wb")
  if not handle then return false end
  handle:write(text)
  handle:close()
  os.remove(path)
  local ok = os.rename(temp, path)
  if not ok then os.remove(temp) end
  return ok and true or false
end

-- Ids -------------------------------------------------------------------------

function M.new_id()
  local guid = r.genGuid and r.genGuid("") or ""
  guid = guid:gsub("[{}]", "")
  if guid == "" then guid = string.format("%08x%04x", os.time(), math.random(0, 0xFFFF)) end
  return guid
end

function M.project_id(project)
  local ok, value = r.GetProjExtState(project, M.EXT_SECTION, M.EXT_KEY)
  if ok and ok > 0 and value and value ~= "" then return value end
  return nil
end

function M.set_project_id(project, id)
  r.SetProjExtState(project, M.EXT_SECTION, M.EXT_KEY, id or "")
end

-- Manifests ---------------------------------------------------------------------

-- Oldest first. Two saves in the same second are told apart by the "-2"
-- suffix, which a plain string compare would put before the first one.
function M.sort_snapshots(snapshots)
  table.sort(snapshots, function(a, b)
    if (a.time or 0) ~= (b.time or 0) then return (a.time or 0) < (b.time or 0) end
    local a_file, b_file = tostring(a.file or ""), tostring(b.file or "")
    if #a_file ~= #b_file then return #a_file < #b_file end
    return a_file < b_file
  end)
end

local function manifest_path(root, id)
  return M.join(root, id, "manifest.json")
end

function M.load_manifest(root, id)
  local text = M.read_file(manifest_path(root, id))
  if not text then return nil end
  local ok, data = pcall(json.decode, text)
  if not ok or type(data) ~= "table" then return nil end
  data.id = data.id or id
  data.snapshots = type(data.snapshots) == "table" and data.snapshots or {}
  M.sort_snapshots(data.snapshots)
  return data
end

function M.save_manifest(root, manifest)
  M.ensure_dir(M.join(root, manifest.id))
  return M.write_file(manifest_path(root, manifest.id), json.encode(manifest))
end

function M.new_manifest(id, project_path, parent)
  return {
    schema = 1,
    id = id,
    name = (tostring(project_path or ""):match("([^\\/]+)%.[Rr][Pp][Pp]$")) or "Project",
    path = project_path,
    parent = parent,
    created = os.time(),
    snapshots = {}
  }
end

function M.snapshot_path(root, manifest, snapshot)
  return M.join(root, manifest.id, snapshot.file)
end

function M.total_bytes(manifest)
  local total = 0
  for _, snapshot in ipairs(manifest and manifest.snapshots or {}) do total = total + (snapshot.size or 0) end
  return total
end

-- Every history under root, newest activity first.
function M.scan(root)
  local result = {}
  for _, id in ipairs(M.list_dirs(root)) do
    local manifest = M.load_manifest(root, id)
    if manifest then result[#result + 1] = manifest end
  end
  table.sort(result, function(a, b)
    local la = a.snapshots[#a.snapshots]
    local lb = b.snapshots[#b.snapshots]
    return (la and la.time or a.created or 0) > (lb and lb.time or b.created or 0)
  end)
  return result
end

-- Capturing ---------------------------------------------------------------------

local function unique_file(root, manifest, time)
  local base = os.date("%Y%m%d-%H%M%S", time)
  local name = base .. ".rpp"
  local counter = 1
  while M.file_exists(M.join(root, manifest.id, name)) do
    counter = counter + 1
    name = base .. "-" .. tostring(counter) .. ".rpp"
  end
  return name
end

-- Copies the saved project into the history, comparing against the newest
-- version on the way: a save that changed nothing (Ctrl+S on a clean project,
-- or undoing back to the saved state) leaves no new file behind.
function M.begin_capture(root, manifest, source_path)
  M.ensure_dir(M.join(root, manifest.id))
  local now = os.time()
  local job = {
    kind = "capture",
    root = root,
    manifest = manifest,
    source_path = source_path,
    time = now,
    file = unique_file(root, manifest, now),
    bytes = 0
  }
  job.source = io.open(source_path, "rb")
  if not job.source then
    job.error = "Could not read " .. tostring(source_path)
    return job
  end
  job.size = job.source:seek("end")
  job.source:seek("set", 0)
  job.target_path = M.join(root, manifest.id, job.file)
  job.temp_path = job.target_path .. ".part"
  job.target = io.open(job.temp_path, "wb")
  if not job.target then
    job.source:close()
    job.error = "Could not write to " .. tostring(root)
    return job
  end
  local latest = manifest.snapshots[#manifest.snapshots]
  if latest and latest.size == job.size then
    job.previous = io.open(M.snapshot_path(root, manifest, latest), "rb")
  end
  return job
end

local function close_capture(job)
  if job.source then job.source:close(); job.source = nil end
  if job.target then job.target:close(); job.target = nil end
  if job.previous then job.previous:close(); job.previous = nil end
end

function M.step_capture(job, budget)
  if job.error or job.done then return false end
  local started = os.clock()
  repeat
    local chunk = job.source:read(M.CHUNK_BYTES)
    if not chunk then
      local identical = job.previous and job.previous:read(1) == nil
      close_capture(job)
      if identical then
        os.remove(job.temp_path)
        job.result = "unchanged"
      else
        os.remove(job.target_path)
        if not os.rename(job.temp_path, job.target_path) then
          os.remove(job.temp_path)
          job.error = "Could not store the version"
          return false
        end
        local snapshot = { file = job.file, time = job.time, size = job.bytes, path = job.source_path }
        job.manifest.snapshots[#job.manifest.snapshots + 1] = snapshot
        job.manifest.path = job.source_path
        job.manifest.name = M.new_manifest(nil, job.source_path).name
        job.snapshot = snapshot
        M.save_manifest(job.root, job.manifest)
        job.result = "saved"
      end
      job.done = true
      return false
    end
    job.target:write(chunk)
    job.bytes = job.bytes + #chunk
    if job.previous and job.previous:read(#chunk) ~= chunk then
      job.previous:close()
      job.previous = nil
    end
  until os.clock() - started >= budget
  return true
end

function M.cancel(job)
  if job and job.kind == "capture" then
    close_capture(job)
    if job.temp_path then os.remove(job.temp_path) end
  elseif job and (job.kind == "migrate" or job.kind == "import") and job.copy then
    if job.copy.source then job.copy.source:close() end
    if job.copy.target then job.copy.target:close() end
    if job.copy.temp_path then os.remove(job.copy.temp_path) end
  end
end

-- Removes a whole history: its versions and its manifest. The empty folder
-- stays behind (plain Lua cannot remove directories); scan() skips folders
-- without a manifest, so it no longer shows up anywhere.
function M.delete_history(root, id)
  local folder = M.join(root, id)
  local removed = 0
  for _, name in ipairs(M.list_files(folder)) do
    if name:match("%.rpp$") or name:match("%.part$") or name:match("%.tmp$") or name == "manifest.json" then
      if os.remove(M.join(folder, name)) then removed = removed + 1 end
    end
  end
  return removed
end

-- Importing REAPER's own backups -------------------------------------------------

-- REAPER writes the save time into the first line of every project:
-- <REAPER_PROJECT 0.1 "7.20/win64" 1700000000
function M.header_time(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local head = handle:read(256) or ""
  handle:close()
  return tonumber(head:match('^<REAPER_PROJECT%s+%S+%s+"[^"]*"%s+(%d+)'))
end

-- The .rpp-bak files REAPER made for this project: the single backup beside
-- it and the timestamped ones ("<name>-2026-10-13_193825.rpp-bak"), either
-- beside it or in a Backups folder. Newest first.
function M.find_backups(project_path)
  local folder, file = tostring(project_path or ""):match("^(.*)[\\/]([^\\/]+)$")
  if not folder then return {} end
  local name = file:gsub("%.[Rr][Pp][Pp]$", "")
  local lower_name = name:lower()
  local result = {}
  local function consider(dir, entry)
    local lower = entry:lower()
    if not lower:match("%.rpp%-bak$") then return end
    local stem = lower:gsub("%.rpp%-bak$", "")
    if stem ~= lower_name and stem:sub(1, #lower_name + 1) ~= lower_name .. "-" then return end
    local path = M.join(dir, entry)
    local time = M.header_time(path)
    if time then result[#result + 1] = { path = path, time = time, size = M.file_size(path) or 0 } end
  end
  for _, entry in ipairs(M.list_files(folder)) do consider(folder, entry) end
  for _, sub in ipairs(M.list_dirs(folder)) do
    if sub:lower():match("^backup") then
      for _, entry in ipairs(M.list_files(M.join(folder, sub))) do consider(M.join(folder, sub), entry) end
    end
  end
  table.sort(result, function(a, b) return a.time > b.time end)
  return result
end

local function same_file_content(path_a, path_b)
  local a, b = io.open(path_a, "rb"), io.open(path_b, "rb")
  local same = a and b and true or false
  while same do
    local chunk_a, chunk_b = a:read(M.CHUNK_BYTES), b:read(M.CHUNK_BYTES)
    if chunk_a ~= chunk_b then same = false end
    if not chunk_a then break end
  end
  if a then a:close() end
  if b then b:close() end
  return same
end

-- Copies backups into a history as versions dated by their save time.
-- Backups that duplicate a version the history already has are skipped.
function M.begin_import(root, manifest, backups)
  M.ensure_dir(M.join(root, manifest.id))
  local queue = {}
  for _, backup in ipairs(backups) do queue[#queue + 1] = backup end
  table.sort(queue, function(a, b) return a.time < b.time end)
  return { kind = "import", root = root, manifest = manifest, queue = queue, imported = 0, skipped = 0, total = #queue }
end

local function import_is_duplicate(job, backup)
  for _, snapshot in ipairs(job.manifest.snapshots) do
    if snapshot.size == backup.size then
      if snapshot.time == backup.time then return true end
      if same_file_content(M.snapshot_path(job.root, job.manifest, snapshot), backup.path) then return true end
    end
  end
  return false
end

function M.step_import(job, budget)
  if job.error or job.done then return false end
  local started = os.clock()
  repeat
    local copy = job.copy
    if copy then
      local chunk = copy.source:read(M.CHUNK_BYTES)
      if chunk then
        copy.target:write(chunk)
        copy.bytes = copy.bytes + #chunk
      else
        copy.source:close()
        copy.target:close()
        os.remove(copy.target_path)
        if os.rename(copy.temp_path, copy.target_path) then
          job.manifest.snapshots[#job.manifest.snapshots + 1] = {
            file = copy.file, time = copy.backup.time, size = copy.bytes, path = copy.backup.path, imported = true
          }
          M.sort_snapshots(job.manifest.snapshots)
          job.imported = job.imported + 1
        else
          os.remove(copy.temp_path)
        end
        job.copy = nil
      end
    else
      local backup = table.remove(job.queue, 1)
      if not backup then
        M.save_manifest(job.root, job.manifest)
        job.done = true
        return false
      end
      if import_is_duplicate(job, backup) then
        job.skipped = job.skipped + 1
      else
        local file = unique_file(job.root, job.manifest, backup.time)
        local target_path = M.join(job.root, job.manifest.id, file)
        local source = io.open(backup.path, "rb")
        local target = source and io.open(target_path .. ".part", "wb")
        if source and target then
          job.copy = { source = source, target = target, file = file, target_path = target_path, temp_path = target_path .. ".part", backup = backup, bytes = 0 }
        else
          if source then source:close() end
          job.skipped = job.skipped + 1
        end
      end
    end
  until os.clock() - started >= budget
  return true
end

-- Pruning -----------------------------------------------------------------------

-- Keeps every version for keep_all_hours, then the newest one per hour for
-- keep_hourly_days, then the newest one per day; finally drops the oldest
-- until the history fits max_bytes. The newest version always stays, and so
-- does every labelled one: a label is how a person says "keep this". Labelled
-- versions still count towards max_bytes but are never what gets dropped.
-- Returns the removed snapshots.
function M.is_labelled(snapshot)
  return type(snapshot.label) == "string" and snapshot.label ~= ""
end

function M.prune(root, manifest, options)
  local snapshots = manifest.snapshots
  if #snapshots <= 1 then return {} end
  local now = os.time()
  local keep_all = (options.keep_all_hours or 24) * 3600
  local keep_hourly = (options.keep_hourly_days or 7) * 86400
  local keep = {}
  local seen = {}
  for index = #snapshots, 1, -1 do
    local snapshot = snapshots[index]
    local age = now - (snapshot.time or 0)
    local bucket
    if index == #snapshots or age <= keep_all or M.is_labelled(snapshot) then
      bucket = "all:" .. tostring(index)
    elseif age <= keep_hourly then
      bucket = "h:" .. tostring((snapshot.time or 0) // 3600)
    else
      bucket = "d:" .. os.date("%Y%m%d", snapshot.time or 0)
    end
    if not seen[bucket] then
      seen[bucket] = true
      keep[index] = true
    end
  end
  local max_bytes = options.max_bytes
  if max_bytes and max_bytes > 0 then
    local total = 0
    for index = #snapshots, 1, -1 do
      if keep[index] then
        total = total + (snapshots[index].size or 0)
        if total > max_bytes and index < #snapshots and not M.is_labelled(snapshots[index]) then keep[index] = nil end
      end
    end
  end
  local kept, removed = {}, {}
  local lost_previous = false
  for index, snapshot in ipairs(snapshots) do
    if keep[index] then
      -- Its summary described the change since a version that is now gone.
      if lost_previous then snapshot.summary = nil; snapshot.counts = nil; snapshot.summary_base = nil; snapshot.summary_version = nil end
      lost_previous = false
      kept[#kept + 1] = snapshot
    else
      os.remove(M.snapshot_path(root, manifest, snapshot))
      removed[#removed + 1] = snapshot
      lost_previous = true
    end
  end
  if #removed > 0 then
    manifest.snapshots = kept
    M.save_manifest(root, manifest)
  end
  return removed
end

-- Moving to a new location ------------------------------------------------------

-- Moves every history from old_root to new_root. A history the new location
-- already has (both places were used at some point) is merged rather than
-- replaced. Same-drive moves are a rename per folder; across drives the files
-- are copied in chunks and the originals removed once their copy is complete.
function M.begin_migration(old_root, new_root)
  M.ensure_dir(new_root)
  local job = { kind = "migrate", old_root = old_root, new_root = new_root, queue = {}, moved = 0, copied_files = 0 }
  for _, id in ipairs(M.list_dirs(old_root)) do
    if M.file_exists(manifest_path(old_root, id)) then job.queue[#job.queue + 1] = id end
  end
  job.total = #job.queue
  return job
end

local function start_history_copy(job, id)
  local source_manifest = M.load_manifest(job.old_root, id)
  local target_manifest = M.load_manifest(job.new_root, id)
  if not source_manifest then return nil end
  local merged = target_manifest or source_manifest
  local files = {}
  local have = {}
  for _, snapshot in ipairs(merged.snapshots) do have[snapshot.file] = true end
  if target_manifest then
    for _, snapshot in ipairs(source_manifest.snapshots) do
      if not have[snapshot.file] then
        merged.snapshots[#merged.snapshots + 1] = snapshot
        have[snapshot.file] = true
      end
    end
    M.sort_snapshots(merged.snapshots)
  end
  for _, name in ipairs(M.list_files(M.join(job.old_root, id))) do
    if name:match("%.rpp$") and not M.file_exists(M.join(job.new_root, id, name)) then files[#files + 1] = name end
  end
  M.ensure_dir(M.join(job.new_root, id))
  return { id = id, manifest = merged, files = files, index = 0, source_manifest = source_manifest }
end

local function finish_history(job, history)
  M.save_manifest(job.new_root, history.manifest)
  for _, name in ipairs(M.list_files(M.join(job.old_root, history.id))) do
    if name:match("%.rpp$") or name == "manifest.json" then
      if name == "manifest.json" or M.file_size(M.join(job.new_root, history.id, name)) == M.file_size(M.join(job.old_root, history.id, name)) then
        os.remove(M.join(job.old_root, history.id, name))
      end
    end
  end
  job.moved = job.moved + 1
end

function M.step_migration(job, budget)
  if job.error or job.done then return false end
  local started = os.clock()
  repeat
    local history = job.history
    if not history then
      local id = table.remove(job.queue, 1)
      if not id then
        job.done = true
        return false
      end
      -- Same drive and nothing to merge: one rename moves the whole folder.
      if not M.file_exists(manifest_path(job.new_root, id)) and os.rename(M.join(job.old_root, id), M.join(job.new_root, id)) then
        job.moved = job.moved + 1
      else
        job.history = start_history_copy(job, id)
      end
    elseif job.copy then
      local copy = job.copy
      local chunk = copy.source:read(M.CHUNK_BYTES)
      if chunk then
        copy.target:write(chunk)
      else
        copy.source:close()
        copy.target:close()
        os.remove(copy.target_path)
        os.rename(copy.temp_path, copy.target_path)
        job.copy = nil
        job.copied_files = job.copied_files + 1
      end
    else
      history.index = history.index + 1
      local name = history.files[history.index]
      if not name then
        finish_history(job, history)
        job.history = nil
      else
        local source_path = M.join(job.old_root, history.id, name)
        local target_path = M.join(job.new_root, history.id, name)
        local source = io.open(source_path, "rb")
        local target = source and io.open(target_path .. ".part", "wb")
        if source and target then
          job.copy = { source = source, target = target, target_path = target_path, temp_path = target_path .. ".part" }
        else
          if source then source:close() end
          job.error = "Could not copy " .. name .. " to " .. job.new_root
          return false
        end
      end
    end
  until os.clock() - started >= budget
  return true
end

return M
