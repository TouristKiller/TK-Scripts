-- Reading and writing a single FX block inside a track's state chunk.
--
-- There is no API to hand a plugin a saved state, so storing "this plugin,
-- configured like this" means instantiating it by name and then writing the
-- saved block over the one REAPER just made. The block finder is the same walk
-- over angle brackets that modules/fx_chain_builder.lua does; that module still
-- has its own copy, which is worth folding into this one on a release that is
-- not already changing three other things.

local r = reaper

local M = {}

-- Byte range of the fx_index'th block inside <chain_tag ...>, zero based.
function M.find_block_bounds(chunk, chain_tag, fx_index)
  local chain_start = chunk and chunk:find("<" .. chain_tag .. "\n")
  if not chain_start then return nil end
  local depth = 0
  local count = -1
  local target_start, target_depth
  for index = chain_start, #chunk do
    local char = chunk:sub(index, index)
    if char == "<" then
      depth = depth + 1
      if depth == 2 and not target_start then
        count = count + 1
        if count == fx_index then
          target_start = index
          target_depth = depth
        end
      end
    elseif char == ">" then
      if target_start and depth == target_depth then return target_start, index end
      depth = depth - 1
      if depth == 0 then break end
    end
  end
  return nil
end

function M.get_block(track, fx_index)
  if not track or not r.GetTrackStateChunk then return nil end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok or not chunk then return nil end
  local block_start, block_end = M.find_block_bounds(chunk, "FXCHAIN", fx_index)
  if not block_start then return nil end
  return chunk:sub(block_start, block_end)
end

function M.replace_block(track, fx_index, block)
  if not track or not block or fx_index < 0 then return false end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok or not chunk then return false end
  local block_start, block_end = M.find_block_bounds(chunk, "FXCHAIN", fx_index)
  if not block_start or not block_end then return false end
  local new_chunk = chunk:sub(1, block_start - 1) .. block .. chunk:sub(block_end + 1)
  return r.SetTrackStateChunk(track, new_chunk, false) == true
end

-- The name TrackFX_AddByName needs to make this plugin again.
function M.plugin_name(track, fx_index)
  if not r.TrackFX_GetFXName then return nil end
  local ok, name = r.TrackFX_GetFXName(track, fx_index, "")
  if ok == false then return nil end
  name = tostring(name or "")
  if name == "" then return nil end
  return name
end

return M
