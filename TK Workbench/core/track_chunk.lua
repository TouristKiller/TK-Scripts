-- Taking a track's state chunk apart and putting pieces of another one in.
--
-- Shared by Track Recall (which stores whole track chunks and restores some
-- or all of their parts) and Time Machine (which restores parts of a track
-- from an older saved version of the project). The functions work on chunks
-- as GetTrackStateChunk returns them: one item per line, no indentation.
-- A track cut out of a .rpp file is indented, so it goes through dedent()
-- first.

local M = {}

M.envelope_keys = {
  VOLENV = true,
  VOLENV2 = true,
  VOLENV3 = true,
  PANENV = true,
  PANENV2 = true,
  MUTEENV = true,
  WIDTHENV = true,
  WIDTHENV2 = true,
  AUXVOLENV = true,
  AUXPANENV = true,
  AUXMUTEENV = true
}

M.envelope_order = {
  "VOLENV",
  "VOLENV2",
  "VOLENV3",
  "PANENV",
  "PANENV2",
  "MUTEENV",
  "WIDTHENV",
  "WIDTHENV2",
  "AUXVOLENV",
  "AUXPANENV",
  "AUXMUTEENV"
}

-- The track's own lines that "Mixer" restores.
M.misc_keys = {
  NAME = true,
  VOLPAN = true,
  MUTESOLO = true,
  IPHASE = true,
  REC = true,
  AUTOMODE = true,
  PEAKCOL = true
}

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

function M.split_lines(chunk)
  local lines = {}
  chunk = tostring(chunk or "")
  for line in (chunk .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" then table.remove(lines) end
  return lines
end

function M.join_lines(lines)
  return table.concat(lines or {}, "\n") .. "\n"
end

-- Leading whitespace off every line and Windows line ends normalised, which
-- turns a block cut out of a .rpp file into the shape the API hands out.
function M.dedent(text)
  text = tostring(text or ""):gsub("\r\n", "\n")
  text = text:gsub("^[ \t]+", ""):gsub("\n[ \t]+", "\n")
  return text
end

local function line_section_key(line)
  return tostring(line or ""):match("^<([%w_]+)")
end

local function root_line_key(line)
  return tostring(line or ""):match("^(%S+)")
end

local function find_section_end(lines, start_index)
  local depth = 0
  for index = start_index, #lines do
    local line = lines[index]
    if starts_with(line, "<") then
      depth = depth + 1
    elseif starts_with(line, ">") then
      depth = depth - 1
      if depth <= 0 then return index end
    end
  end
  return #lines
end

local function line_range(lines, start_index, end_index)
  local result = {}
  for index = start_index, end_index do result[#result + 1] = lines[index] end
  return result
end

-- Blocks directly inside the track whose tag is in wanted, in order.
function M.extract_sections(chunk, wanted)
  local lines = M.split_lines(chunk)
  local sections = {}
  local depth = 0
  local index = 1
  while index <= #lines do
    local line = lines[index]
    local key = line_section_key(line)
    if key and depth == 1 and wanted[key] then
      local end_index = find_section_end(lines, index)
      sections[#sections + 1] = { key = key, chunk = M.join_lines(line_range(lines, index, end_index)) }
      index = end_index + 1
    else
      if starts_with(line, "<") then depth = depth + 1 elseif starts_with(line, ">") then depth = math.max(0, depth - 1) end
      index = index + 1
    end
  end
  return sections
end

function M.extract_first_section(chunk, key)
  local sections = M.extract_sections(chunk, { [key] = true })
  return sections[1] and sections[1].chunk or nil
end

function M.extract_root_lines(chunk, wanted)
  local result = {}
  local lines = M.split_lines(chunk)
  local depth = 0
  for _, line in ipairs(lines) do
    if depth == 1 then
      local key = root_line_key(line)
      if key and wanted[key] then result[key] = line end
    end
    if starts_with(line, "<") then depth = depth + 1 elseif starts_with(line, ">") then depth = math.max(0, depth - 1) end
  end
  return result
end

function M.section_list_chunks(sections)
  local result = {}
  for _, section in ipairs(sections or {}) do result[#result + 1] = section.chunk end
  return result
end

local function remove_sections(lines, wanted)
  local result = {}
  local first_index = nil
  local depth = 0
  local index = 1
  while index <= #lines do
    local line = lines[index]
    local key = line_section_key(line)
    if key and depth == 1 and wanted[key] then
      first_index = first_index or (#result + 1)
      index = find_section_end(lines, index) + 1
    else
      result[#result + 1] = line
      if starts_with(line, "<") then depth = depth + 1 elseif starts_with(line, ">") then depth = math.max(0, depth - 1) end
      index = index + 1
    end
  end
  return result, first_index
end

local function insert_chunk_strings(lines, insert_index, chunks)
  local index = insert_index or #lines
  for _, chunk in ipairs(chunks or {}) do
    for _, line in ipairs(M.split_lines(chunk)) do
      table.insert(lines, index, line)
      index = index + 1
    end
  end
  return lines
end

-- replacement maps a block tag to the list of chunks that should stand in
-- for every block of that tag; an empty list removes them.
function M.replace_sections(chunk, replacement)
  local lines = M.split_lines(chunk)
  local wanted = {}
  local chunks = {}
  replacement = replacement or {}
  local order = { "FXCHAIN", "ITEM" }
  for _, key in ipairs(M.envelope_order) do order[#order + 1] = key end
  for _, key in ipairs(order) do
    local value = replacement[key]
    if value then
      wanted[key] = true
      for _, chunk_string in ipairs(value or {}) do chunks[#chunks + 1] = chunk_string end
    end
  end
  for key, value in pairs(replacement) do
    if not wanted[key] then
      wanted[key] = true
      for _, chunk_string in ipairs(value or {}) do chunks[#chunks + 1] = chunk_string end
    end
  end
  local cleaned, insert_index = remove_sections(lines, wanted)
  if not insert_index then insert_index = math.max(1, #cleaned) end
  insert_chunk_strings(cleaned, insert_index, chunks)
  return M.join_lines(cleaned)
end

function M.replace_root_lines(chunk, values)
  local lines = M.split_lines(chunk)
  local depth = 0
  for index, line in ipairs(lines) do
    if depth == 1 then
      local key = root_line_key(line)
      if key and values and values[key] then lines[index] = values[key] end
    end
    if starts_with(line, "<") then depth = depth + 1 elseif starts_with(line, ">") then depth = math.max(0, depth - 1) end
  end
  return M.join_lines(lines)
end

-- The source's content under the target's identity (its <TRACK line and
-- TRACKID), so sends and selection that point at the target keep working.
function M.keep_target_track_identity(source_chunk, target_chunk)
  local source_lines = M.split_lines(source_chunk)
  local target_lines = M.split_lines(target_chunk)
  if #source_lines == 0 then return nil end
  if target_lines[1] and starts_with(target_lines[1], "<TRACK") then source_lines[1] = target_lines[1] end
  return M.replace_root_lines(M.join_lines(source_lines), M.extract_root_lines(target_chunk, { TRACKID = true }))
end

-- current_chunk with the parts named in options (fx, items, envelopes, misc)
-- taken from source_chunk. Items and envelopes the source does not have are
-- removed. A source without an FX chain leaves the current chain alone, as
-- Track Recall always did, unless options.empty_missing_fx asks for the
-- chain to go too (Time Machine: "as it was" means no FX).
function M.build_partial(current_chunk, source_chunk, options)
  if not source_chunk or source_chunk == "" then return nil end
  local replacement = {}
  if options.fx then
    local fx_chain = M.extract_first_section(source_chunk, "FXCHAIN")
    if fx_chain then
      replacement.FXCHAIN = { fx_chain }
    elseif options.empty_missing_fx then
      replacement.FXCHAIN = {}
    end
  end
  if options.items then replacement.ITEM = M.section_list_chunks(M.extract_sections(source_chunk, { ITEM = true })) end
  if options.envelopes then
    for key in pairs(M.envelope_keys) do replacement[key] = {} end
    for _, section in ipairs(M.extract_sections(source_chunk, M.envelope_keys)) do
      replacement[section.key] = replacement[section.key] or {}
      table.insert(replacement[section.key], section.chunk)
    end
  end
  local chunk = M.replace_sections(current_chunk, replacement)
  if options.misc then chunk = M.replace_root_lines(chunk, M.extract_root_lines(source_chunk, M.misc_keys)) end
  return chunk
end

return M
