-- Folder creation, binary file copy and log writing for kit export.
-- Lua has no native file-copy, so copy() reads/writes in chunks via io.open
-- in binary mode -- cross-platform, no shell required.

local r = reaper
local Stitcher = require("core.stitcher")

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

-- Like copy(), but writes out only the part of the file the pad actually plays.
--
-- A sliced pad is two RS5K offsets, which live in the REAPER project. A kit
-- folder has nowhere to put them: it is a folder of samples, and whatever loads
-- it next -- a hardware sampler, another DAW, someone else's session -- sees
-- files only. So for a trimmed pad the trim has to be baked in, or sixteen pads
-- chopped out of one break all export as sixteen copies of the whole break.
--
-- Returns nil and a reason rather than half a file, so the caller can fall back
-- to copying whole: an untrimmed sample is a nuisance, a truncated one is a
-- broken kit.
--
-- On success the second return describes what was written, for the sources log.
function M.copy_slice(src, dest_dir, filename, start01, stop01)
  local final_name = unique_filename(dest_dir, filename)
  local ok, info = Stitcher.write_slice(src, dest_dir .. "/" .. final_name, start01, stop01)
  if not ok then return nil, info or "could not write the slice" end
  return final_name, info
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

-- recipe (optional): { seed = n, pack = "404-3A9C21" }. Written into the log so
-- the kit carries the two numbers that rebuild it. The sample paths below are
-- only meaningful on the machine that made the kit; the recipe is the part that
-- travels, and this is the file it belongs in.
function M.write_sourcelog(dest_dir, kit_name, results, recipe)
  local path = dest_dir .. "/" .. kit_name .. " - Sources.txt"
  local f = io.open(path, "w")
  if not f then return end
  f:write("Kit: " .. kit_name .. "\n")
  if recipe and recipe.seed then
    f:write("Seed: " .. tostring(recipe.seed) .. "\n")
    if recipe.pack then
      f:write("Pack: " .. tostring(recipe.pack) .. "\n")
    end
    f:write("\nThe same seed over a pack with the same code rebuilds this kit.\n")
  end
  f:write("\n")
  for _, res in ipairs(results) do
    f:write(res.out_name .. "\n    " .. res.sample .. "\n")
    -- Without this line the entry reads as "this file came from that file",
    -- which for a sliced pad is not true: only part of it did, and the log is
    -- the only place left that knows which part.
    local t = res.trim
    if t and t.seconds and t.start_seconds and t.source_seconds then
      f:write(string.format("    trimmed: %.3f s starting at %.3f s (source is %.3f s)\n",
        t.seconds, t.start_seconds, t.source_seconds))
    end
  end
  f:close()
end

return M
