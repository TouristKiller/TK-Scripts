-- Folder creation, binary file copy and log writing for kit export.
-- Lua has no native file-copy, so copy() reads/writes in chunks via io.open
-- in binary mode -- cross-platform, no shell required.

local r = reaper

local M = {}

local CHUNK_SIZE = 1024 * 1024 -- 1 MB

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  return (path:gsub("/+$", ""))
end
M.normalize = normalize

local function file_exists(path)
  local f = io.open(path, "rb")
  if f then f:close(); return true end
  return false
end

local function subdir_names(parent)
  local names = {}
  local i = 0
  while true do
    local name = r.EnumerateSubdirectories(parent, i)
    if not name then break end
    names[name] = true
    i = i + 1
  end
  return names
end

-- Creates destination/kit_name, appending " (2)", " (3)", ... if a folder
-- with that name already exists. Returns the full path and the final name.
function M.make_folder(destination, kit_name)
  destination = normalize(destination)
  r.RecursiveCreateDirectory(destination, 0)

  local existing = subdir_names(destination)
  local final_name = kit_name
  local n = 2
  while existing[final_name] do
    final_name = kit_name .. " (" .. n .. ")"
    n = n + 1
  end

  local dest_path = destination .. "/" .. final_name
  r.RecursiveCreateDirectory(dest_path, 0)
  return dest_path, final_name
end

local function unique_filename(dest_dir, filename)
  if not file_exists(dest_dir .. "/" .. filename) then return filename end

  local stub, ext = filename:match("^(.*)%.([%w]+)$")
  stub = stub or filename
  ext = ext and ("." .. ext) or ""

  local n = 2
  local candidate
  repeat
    candidate = string.format("%s (%d)%s", stub, n, ext)
    n = n + 1
  until not file_exists(dest_dir .. "/" .. candidate)
  return candidate
end

-- Copies src into dest_dir under filename, renaming on collision.
-- Returns the final filename used, or nil + error message on failure.
function M.copy(src, dest_dir, filename)
  local final_name = unique_filename(dest_dir, filename)
  local out_path = dest_dir .. "/" .. final_name

  local infile = io.open(src, "rb")
  if not infile then return nil, "cannot open source file: " .. src end

  local outfile = io.open(out_path, "wb")
  if not outfile then
    infile:close()
    return nil, "cannot write destination file: " .. out_path
  end

  while true do
    local chunk = infile:read(CHUNK_SIZE)
    if not chunk then break end
    outfile:write(chunk)
  end

  infile:close()
  outfile:close()
  return final_name
end

-- results: array of { slot = Slot, pool = Pool, sample = "src/path.wav", out_name = "..." }

-- REAPER's note-name file format: one "<note> <name>" line per instrument, so
-- the file can be loaded straight into the MIDI editor (File -> Note names) and
-- the piano roll reads Kick / Snare instead of C2 / D2. Plain enough to read as
-- a list too, which is all it used to be.
--
-- The name is the slot's role where there is one -- the word from its filter or
-- pattern -- and the exported filename where there is not. A sample that fits
-- no category still gets a usable row rather than a blank one.
function M.write_midilog(dest_dir, kit_name, results)
  local path = dest_dir .. "/" .. kit_name .. " - MIDI.txt"
  local f = io.open(path, "w")
  if not f then return end
  for _, res in ipairs(results) do
    local role = res.slot.type_label
    if not role or role == "" then
      role = (res.out_name or ""):gsub("%.[%w]+$", "")
    end
    f:write(string.format("%d %s\n", res.slot.midi_note, role))
  end
  f:close()
end

function M.write_sourcelog(dest_dir, kit_name, results)
  local path = dest_dir .. "/" .. kit_name .. " - Sources.txt"
  local f = io.open(path, "w")
  if not f then return end
  f:write("Kit: " .. kit_name .. "\n\n")
  for _, res in ipairs(results) do
    f:write(res.out_name .. "\n    " .. res.sample .. "\n")
  end
  f:close()
end

return M
