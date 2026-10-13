-- Putting parts of an older saved version back into the open project.
--
-- Everything here takes a parsed old version (core/rpp_diff.lua) and changes
-- the live project to match it for one thing: a track, a part of a track, one
-- plugin, one envelope, a marker. Tracks and plugins are found by their GUID
-- (TRACKID, FXID), never by position, so a restore still lands on the right
-- track after tracks were reordered or renamed.
--
-- Old blocks are cut out of the .rpp text by the byte ranges the parser
-- recorded and dedented into the shape GetTrackStateChunk uses. Plugins are
-- restored as whole chain entries (BYPASS line through FXID, preset name and
-- automation), which is also how REAPER copies an FX between tracks.
--
-- Every public action runs inside one undo block via M.run.

local r = reaper
local TrackChunk = require("core.track_chunk")
local Diff = require("core.rpp_diff")

local M = {}

-- Undo --------------------------------------------------------------------------

-- Runs fn inside one undo point; fn returns ok, message.
function M.run(label, fn)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local call_ok, ok, message = pcall(fn)
  r.PreventUIRefresh(-1)
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  r.UpdateArrange()
  r.Undo_EndBlock("Time Machine: " .. tostring(label), -1)
  if not call_ok then return false, tostring(ok) end
  return ok, message
end

-- Finding things ----------------------------------------------------------------

local function same_guid(a, b)
  return tostring(a or ""):upper() == tostring(b or ""):upper()
end

function M.find_track(guid)
  if not guid then return nil end
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    if same_guid(r.GetTrackGUID(track), guid) then return track end
  end
  return nil
end

local function live_chunk(track)
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok or not chunk or chunk == "" then return nil end
  return chunk
end

local function set_chunk(track, chunk)
  return r.SetTrackStateChunk(track, chunk, false) == true
end

-- The old version's track as a chunk the API accepts.
function M.old_track_chunk(old_project, id)
  local track = old_project.tracks[id]
  if not track or not track.block_start or not track.block_end then return nil end
  return TrackChunk.dedent(old_project.text:sub(track.block_start, track.block_end))
end

local function old_chain(old_project, track_id, chain_name)
  if chain_name == "Master" then return old_project.master_fx end
  local track = old_project.tracks[track_id]
  if not track then return nil end
  if chain_name == "Input FX" then return track.input_fx end
  return track.fx
end

local function live_chain(parsed, chain_name)
  if chain_name == "Input FX" then return parsed.input_fx end
  return parsed.fx
end

local function find_entry(chain, fx_id)
  for index, fx in ipairs(chain and chain.list or {}) do
    if fx_id and same_guid(fx.id, fx_id) then return fx, index end
  end
  return nil
end

-- Lines of a track chunk ---------------------------------------------------------

-- Replaces every line directly inside the track whose key is in keys with the
-- matching lines from source_chunk (all of them, so several AUXRECV lines
-- come back as several lines). Lines the source does not have are dropped.
function M.replace_key_lines(chunk, source_chunk, keys)
  local wanted = {}
  for _, key in ipairs(keys) do wanted[key] = true end
  local function key_of(line) return line:match("^([%w_]+)") end
  local incoming = {}
  local depth = 0
  for _, line in ipairs(TrackChunk.split_lines(source_chunk)) do
    if depth == 1 and wanted[key_of(line) or ""] then incoming[#incoming + 1] = line end
    local first = line:sub(1, 1)
    if first == "<" then depth = depth + 1 elseif first == ">" then depth = depth - 1 end
  end
  local result = {}
  local insert_at = nil
  local first_block = nil
  depth = 0
  for _, line in ipairs(TrackChunk.split_lines(chunk)) do
    local first = line:sub(1, 1)
    if depth == 1 and wanted[key_of(line) or ""] then
      insert_at = insert_at or (#result + 1)
    else
      if depth == 1 and first == "<" and not first_block then first_block = #result + 1 end
      result[#result + 1] = line
    end
    if first == "<" then depth = depth + 1 elseif first == ">" then depth = depth - 1 end
  end
  insert_at = insert_at or first_block or #result
  for offset, line in ipairs(incoming) do table.insert(result, insert_at + offset - 1, line) end
  return TrackChunk.join_lines(result)
end

-- Tracks ------------------------------------------------------------------------

function M.whole_track(old_project, id)
  local track = M.find_track(id)
  if not track then return false, "That track is no longer in the project" end
  local source = M.old_track_chunk(old_project, id)
  local current = live_chunk(track)
  if not source or not current then return false, "Could not read the track" end
  return set_chunk(track, TrackChunk.keep_target_track_identity(source, current)), "Track restored"
end

-- parts: { fx = bool, items = bool, envelopes = bool, misc = bool }
function M.track_parts(old_project, id, parts)
  local track = M.find_track(id)
  if not track then return false, "That track is no longer in the project" end
  local source = M.old_track_chunk(old_project, id)
  local current = live_chunk(track)
  if not source or not current then return false, "Could not read the track" end
  local options = { fx = parts.fx, items = parts.items, envelopes = parts.envelopes, misc = parts.misc, empty_missing_fx = true }
  return set_chunk(track, TrackChunk.build_partial(current, source, options)), "Restored"
end

-- Puts a deleted track back after the track that preceded it in the old
-- version (or at the top). It keeps its old GUID, so later comparisons
-- recognise it as the same track.
function M.bring_back_track(old_project, id)
  local source = M.old_track_chunk(old_project, id)
  if not source then return false, "That track is not in the old version" end
  if M.find_track(id) then return false, "That track is already in the project" end
  local old_track = old_project.tracks[id]
  local insert_index = 0
  for position = (old_track.index or 1) - 1, 1, -1 do
    local before = M.find_track(old_project.track_order[position])
    if before then
      insert_index = math.floor(r.GetMediaTrackInfo_Value(before, "IP_TRACKNUMBER"))
      break
    end
  end
  r.InsertTrackAtIndex(insert_index, false)
  local track = r.GetTrack(0, insert_index)
  if not track then return false, "Could not insert a track" end
  return set_chunk(track, source), "Track brought back"
end

function M.remove_track(id)
  local track = M.find_track(id)
  if not track then return false, "That track is not in the project" end
  r.DeleteTrack(track)
  return true, "Track removed"
end

function M.track_lines(old_project, id, keys)
  local track = M.find_track(id)
  if not track then return false, "That track is no longer in the project" end
  local source = M.old_track_chunk(old_project, id)
  local current = live_chunk(track)
  if not source or not current then return false, "Could not read the track" end
  return set_chunk(track, M.replace_key_lines(current, source, keys)), "Restored"
end

-- id nil means the master track.
function M.track_value(id, param, value)
  local track = id and M.find_track(id) or (not id and r.GetMasterTrack(0)) or nil
  if not track then return false, "That track is no longer in the project" end
  if value == nil then return false, "No value to restore" end
  r.SetMediaTrackInfo_Value(track, param, value)
  return true, "Restored"
end

function M.envelope(old_project, id, key)
  local track = M.find_track(id)
  if not track then return false, "That track is no longer in the project" end
  local source = M.old_track_chunk(old_project, id)
  local current = live_chunk(track)
  if not source or not current then return false, "Could not read the track" end
  local sections = TrackChunk.section_list_chunks(TrackChunk.extract_sections(source, { [key] = true }))
  return set_chunk(track, TrackChunk.replace_sections(current, { [key] = sections })), "Envelope restored"
end

-- Plugins -----------------------------------------------------------------------

local function chain_tag(chain_name)
  return chain_name == "Input FX" and "FXCHAIN_REC" or "FXCHAIN"
end

-- Puts one plugin back as it was in the old version (fx_id names it). When
-- the old version did not have it, it is removed instead. A plugin that is
-- gone from the live chain is reinserted after the plugin that preceded it
-- back then. track_id nil means the master track.
function M.fx(old_project, track_id, chain_name, fx_id)
  local track = track_id and M.find_track(track_id) or (not track_id and r.GetMasterTrack(0)) or nil
  if not track then return false, "That track is no longer in the project" end
  local current = live_chunk(track)
  local parsed = current and Diff.parse_track_chunk(current)
  if not parsed then return false, "Could not read the track" end
  local live = live_chain(parsed, chain_name)
  local live_fx = find_entry(live, fx_id)
  local before_chain = old_chain(old_project, track_id, chain_name)
  local old_fx, old_index = find_entry(before_chain, fx_id)

  if not old_fx then
    if not live_fx then return false, "That plugin is not on the track" end
    return set_chunk(track, current:sub(1, live_fx.entry_start - 1) .. current:sub(live_fx.entry_end + 1)), "Plugin removed"
  end

  local entry = TrackChunk.dedent(old_project.text:sub(old_fx.entry_start, old_fx.entry_end))
  if entry:sub(-1) ~= "\n" then entry = entry .. "\n" end
  local new_chunk
  if live_fx then
    new_chunk = current:sub(1, live_fx.entry_start - 1) .. entry .. current:sub(live_fx.entry_end + 1)
  elseif live and live.close_start then
    local insert_at = nil
    for index = old_index - 1, 1, -1 do
      local anchor = find_entry(live, before_chain.list[index].id)
      if anchor then
        insert_at = anchor.entry_end + 1
        break
      end
    end
    insert_at = insert_at or (live.list[1] and live.list[1].entry_start) or live.close_start
    new_chunk = current:sub(1, insert_at - 1) .. entry .. current:sub(insert_at)
  else
    -- No chain at all on the track yet: give it one just before its end.
    local close = current:match(".*()\n>")
    if not close then return false, "Could not read the track" end
    local chain = "<" .. chain_tag(chain_name) .. "\nSHOW 0\nLASTSEL 0\nDOCKED 0\n" .. entry .. ">\n"
    new_chunk = current:sub(1, close) .. chain .. current:sub(close + 1)
  end
  return set_chunk(track, new_chunk), live_fx and "Plugin restored" or "Plugin brought back"
end

-- Borrowing a track from another project ------------------------------------------

local FRESH_GUID_KEYS = { IGUID = true, GUID = true, FXID = true, EGUID = true, POOLEDEVTS = true }

-- A copy of a track that can live next to the original: every item, take,
-- plugin, envelope and MIDI pool id is replaced, consistently, so two items
-- that shared a MIDI pool still share one. Relative media paths are made
-- absolute against source_folder, the project the track came from. Receives
-- are dropped: they name tracks of the other project by position.
function M.portable_track_chunk(chunk, source_folder)
  local mapping = {}
  local function fresh(guid)
    mapping[guid] = mapping[guid] or r.genGuid("")
    return mapping[guid]
  end
  local sep = package.config:sub(1, 1)
  local lines = {}
  for _, line in ipairs(TrackChunk.split_lines(chunk)) do
    local key = line:match("^[ \t]*([%u_]+)")
    if key == "AUXRECV" then
      line = nil
    elseif key and FRESH_GUID_KEYS[key] then
      line = line:gsub("%b{}", fresh)
    elseif key == "FILE" and source_folder and source_folder ~= "" then
      local head, quoted, rest = line:match('^([ \t]*FILE[ \t]+)"([^"]*)"(.*)$')
      if not head then head, quoted, rest = line:match("^([ \t]*FILE[ \t]+)([^ \t]+)(.*)$") end
      if quoted and quoted ~= "" and not quoted:match("^%a:[\\/]") and not quoted:match("^[\\/]") then
        line = head .. '"' .. source_folder:gsub("[\\/]+$", "") .. sep .. quoted .. '"' .. rest
      end
    end
    if line then lines[#lines + 1] = line end
  end
  return TrackChunk.join_lines(lines)
end

-- Inserts the track at insert_index (0-based) as a new track of its own.
function M.borrow_track(source_project, track_id, source_folder, insert_index)
  local source = M.old_track_chunk(source_project, track_id)
  if not source then return false, "That track is not in the chosen version" end
  local portable = M.portable_track_chunk(source, source_folder)
  insert_index = math.max(0, math.min(insert_index or r.CountTracks(0), r.CountTracks(0)))
  r.InsertTrackAtIndex(insert_index, false)
  local track = r.GetTrack(0, insert_index)
  if not track then return false, "Could not insert a track" end
  local blank = live_chunk(track)
  if not blank then return false, "Could not read the new track" end
  return set_chunk(track, TrackChunk.keep_target_track_identity(portable, blank)), "Track added"
end

-- The project as it is right now --------------------------------------------------

-- Builds the open project, unsaved changes included, in the same parsed form
-- as a saved version, so the ordinary comparison can run against it. There
-- is no API that returns a whole project, so it is assembled: every track's
-- state chunk, the master's FX chain as <MASTERFXLIST>, master volume and
-- pan, tempo and time signature at the start, project notes and markers.
--
-- Two things are taken over from the version it will be compared with
-- (reference) instead of being read live: master mute/solo and the tempo
-- map, whose file format the API has no way to reproduce. Comparing against
-- "now" therefore never reports those two.
function M.capture_live(reference)
  reference = reference or { lines = {}, blocks = {} }
  local lines = { '<REAPER_PROJECT 0.1 "live" ' .. tostring(os.time()) }
  local numerator, denominator, tempo = r.TimeMap_GetTimeSigAtTime(0, 0)
  lines[#lines + 1] = string.format("TEMPO %s %d %d", (string.format("%.10g", tempo)), numerator, denominator)
  local master = r.GetMasterTrack(0)
  -- Every saved project has these; a reference without them (a hand-made
  -- test file) should not make them look added.
  if reference.lines.MASTER_VOLUME then
    lines[#lines + 1] = string.format("MASTER_VOLUME %.14g %.14g -1 -1 1", r.GetMediaTrackInfo_Value(master, "D_VOL"), r.GetMediaTrackInfo_Value(master, "D_PAN"))
  end
  if reference.lines.MASTERMUTESOLO then lines[#lines + 1] = "MASTERMUTESOLO " .. reference.lines.MASTERMUTESOLO end
  if reference.blocks.TEMPOENVEX then lines[#lines + 1] = reference.blocks.TEMPOENVEX end

  local notes = r.GetSetProjectNotes(0, false, "")
  if reference.blocks.NOTES or notes ~= "" then
    local notes_header = reference.blocks.NOTES and reference.blocks.NOTES:match("^[ \t]*(<NOTES[^\r\n]*)") or "<NOTES 0 2"
    lines[#lines + 1] = notes_header
    if notes ~= "" then
      for line in (notes:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = "|" .. line end
    end
    lines[#lines + 1] = ">"
  end

  local master_chunk = live_chunk(master)
  local master_fx = master_chunk and TrackChunk.extract_first_section(master_chunk, "FXCHAIN")
  if master_fx then lines[#lines + 1] = (master_fx:gsub("^<FXCHAIN", "<MASTERFXLIST")) end

  local bytes = 0
  for index = 0, r.CountTracks(0) - 1 do
    local chunk = live_chunk(r.GetTrack(0, index))
    if chunk then
      lines[#lines + 1] = chunk
      bytes = bytes + #chunk
    end
  end
  lines[#lines + 1] = ">"
  local project = assert(Diff.parse(table.concat(lines, "\n") .. "\n"))

  -- Markers straight from the API rather than through MARKER lines, so names
  -- with quotes in them need no escaping.
  project.markers = {}
  local position = 0
  while true do
    local ok, is_region, start, region_end, name, number, color = r.EnumProjectMarkers3(0, position)
    if not ok or ok == 0 then break end
    local id = (is_region and "R" or "M") .. tostring(number)
    project.markers[id] = {
      id = id,
      index = tostring(number),
      region = is_region == true,
      position = start,
      region_end = is_region and region_end or nil,
      name = name or "",
      color = tostring(math.floor(color or 0))
    }
    position = position + 1
  end
  project.live = true
  project.bytes = bytes
  return project
end

-- Naming what changed inside a plugin -------------------------------------------

-- A VST, VST3 or CLAP keeps its settings as an opaque blob, so the file alone
-- cannot say which knob moved. The plugin itself can: both versions of it are
-- loaded side by side on a hidden temporary track, every parameter is read,
-- and the track is deleted again. old_block and new_block are the <VST ...>
-- blocks as they appear in the two versions.
--
-- Returns a list of "Name: old -> new" lines (empty when no parameter differs,
-- which means only the plugin's private data changed), or nil and a message.
local SKIP_PARAM = { "^MIDI CC", "^CC%d", "^Bypass$", "^Wet$", "^Delta$" }

function M.compare_plugin_params(old_block, new_block)
  local index = r.CountTracks(0)
  r.InsertTrackAtIndex(index, false)
  local track = r.GetTrack(0, index)
  if not track then return nil, "Could not create a temporary track" end
  local result, problem
  local ok, err = pcall(function()
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 0)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
    local function entry(block)
      block = TrackChunk.dedent(block)
      if block:sub(-1) ~= "\n" then block = block .. "\n" end
      return "BYPASS 0 0 0\n" .. block
    end
    local chunk = "<TRACK\nNAME \"Time Machine compare\"\n<FXCHAIN\nSHOW 0\nLASTSEL 0\nDOCKED 0\n"
      .. entry(old_block) .. entry(new_block) .. ">\n>\n"
    if not set_chunk(track, chunk) or r.TrackFX_GetCount(track) < 2 then
      problem = "The plugin could not be loaded"
      return
    end
    local count = math.min(r.TrackFX_GetNumParams(track, 0), r.TrackFX_GetNumParams(track, 1))
    if count <= 0 then
      problem = "The plugin could not be loaded (is it installed?)"
      return
    end
    result = {}
    for param = 0, count - 1 do
      local a = r.TrackFX_GetParamNormalized(track, 0, param)
      local b = r.TrackFX_GetParamNormalized(track, 1, param)
      if math.abs(a - b) > 0.000001 then
        local _, name = r.TrackFX_GetParamName(track, 0, param, "")
        local skip = false
        for _, pattern in ipairs(SKIP_PARAM) do if tostring(name):match(pattern) then skip = true end end
        if not skip then
          local _, before = r.TrackFX_GetFormattedParamValue(track, 0, param, "")
          local _, after = r.TrackFX_GetFormattedParamValue(track, 1, param, "")
          if before == "" then before = string.format("%.3f", a) end
          if after == "" then after = string.format("%.3f", b) end
          result[#result + 1] = tostring(name) .. ": " .. tostring(before) .. " -> " .. tostring(after)
        end
      end
    end
  end)
  r.DeleteTrack(track)
  if not ok then return nil, tostring(err) end
  if problem then return nil, problem end
  return result
end

-- Markers and regions -----------------------------------------------------------

local function find_live_marker(index, is_region)
  local count = r.CountProjectMarkers(0)
  for position = 0, count - 1 do
    local _, region, _, _, _, number = r.EnumProjectMarkers3(0, position)
    if number == index and (region == true) == is_region then return true end
  end
  return false
end

function M.marker(old_project, marker_id, new_project)
  local old_marker = old_project.markers[marker_id]
  local any_marker = old_marker or (new_project and new_project.markers[marker_id])
  if not any_marker then return false, "Marker not found" end
  local index = tonumber(any_marker.index)
  local is_region = any_marker.region == true
  if not old_marker then
    r.DeleteProjectMarker(0, index, is_region)
    return true, (is_region and "Region" or "Marker") .. " removed"
  end
  local color = tonumber(old_marker.color) or 0
  local region_end = old_marker.region_end or old_marker.position
  if find_live_marker(index, is_region) then
    r.SetProjectMarker3(0, index, is_region, old_marker.position, region_end, old_marker.name, color)
  else
    r.AddProjectMarker2(0, is_region, old_marker.position, region_end, old_marker.name, index, color)
  end
  return true, (is_region and "Region" or "Marker") .. " restored"
end

return M
