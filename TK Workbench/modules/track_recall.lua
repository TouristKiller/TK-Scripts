local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local json = require("core.json")

local M = {
  id = "track_recall",
  title = "Track Recall",
  icon = "RCL",
  version = "0.1.0"
}

local EXT_SECTION = "TK_WORKBENCH_TRACK_RECALL_V2"
local EXT_DATA_PREFIX = "DATA:"
local EXT_INDEX_PREFIX = "INDEX:"

local defaults = {
  custom_fx = true,
  custom_items = true,
  custom_envelopes = true,
  custom_misc = true
}

local part_descriptions = {
  fx = "FX chain and plugin states.",
  items = "Media items on the track.",
  envelopes = "Track envelope lanes such as volume, pan, mute and width envelopes.",
  misc = "Mixer and track settings such as volume, pan, mute, solo, phase, record/monitor, automation mode, name and color."
}

local envelope_keys = {
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

local envelope_order = {
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

local misc_keys = {
  NAME = true,
  VOLPAN = true,
  MUTESOLO = true,
  IPHASE = true,
  REC = true,
  AUTOMODE = true,
  PEAKCOL = true
}

local state = {
  track_guid = nil,
  data = nil,
  full_loaded = false,
  has_index = false,
  cache = {},
  filtered = {},
  dirty_filter = true,
  create_name = "",
  create_open = false,
  rename_id = nil,
  rename_text = "",
  rename_open = false,
  error = nil
}

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy_default(child) end
  return result
end

local function ensure_settings(app)
  app.settings.track_recall = app.settings.track_recall or {}
  local settings = app.settings.track_recall
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function now()
  return os.time()
end

local function clean_name(value, fallback)
  value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  if value == "" then return fallback end
  return value
end

local function selected_track(app)
  local track = app.selection and app.selection.track and app.selection.track.pointer
  if track and r.ValidatePtr2(0, track, "MediaTrack*") then return track end
  return nil
end

local function track_guid(track)
  if not track then return nil end
  if r.GetTrackGUID then return r.GetTrackGUID(track) end
  return tostring(track)
end

local function project_ext_key(track, prefix)
  local guid = track_guid(track)
  if not guid then return nil end
  return prefix .. guid
end

local function track_name(track)
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  return "Track"
end

local function native_color_to_u32(native, alpha)
  native = tonumber(native) or 0
  if native == 0 then return nil end
  alpha = alpha or 0xCC
  if r.ColorFromNative then
    local ok, red, green, blue = pcall(r.ColorFromNative, native & 0xFFFFFF)
    if ok and red and green and blue then return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | (alpha & 0xFF) end
  end
  local red = native & 0xFF
  local green = (native >> 8) & 0xFF
  local blue = (native >> 16) & 0xFF
  return (red << 24) | (green << 16) | (blue << 8) | (alpha & 0xFF)
end

local function selected_track_label(app, track)
  local index = app.selection and app.selection.track and tonumber(app.selection.track.index) or nil
  local name = track_name(track)
  if index and index > 0 then return string.format("%02d - %s", index, name) end
  return name
end

local function starts_with(value, prefix)
  return value:sub(1, #prefix) == prefix
end

local function split_lines(chunk)
  local lines = {}
  chunk = tostring(chunk or "")
  for line in (chunk .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
  if lines[#lines] == "" then table.remove(lines) end
  return lines
end

local function join_lines(lines)
  return table.concat(lines or {}, "\n") .. "\n"
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

local function extract_sections(chunk, wanted)
  local lines = split_lines(chunk)
  local sections = {}
  local depth = 0
  local index = 1
  while index <= #lines do
    local line = lines[index]
    local key = line_section_key(line)
    if key and depth == 1 and wanted[key] then
      local end_index = find_section_end(lines, index)
      sections[#sections + 1] = { key = key, chunk = join_lines(line_range(lines, index, end_index)) }
      index = end_index + 1
    else
      if starts_with(line, "<") then depth = depth + 1 elseif starts_with(line, ">") then depth = math.max(0, depth - 1) end
      index = index + 1
    end
  end
  return sections
end

local function extract_first_section(chunk, key)
  local sections = extract_sections(chunk, { [key] = true })
  return sections[1] and sections[1].chunk or nil
end

local function extract_root_lines(chunk, wanted)
  local result = {}
  local lines = split_lines(chunk)
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

local function section_list_chunks(sections)
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
    for _, line in ipairs(split_lines(chunk)) do
      table.insert(lines, index, line)
      index = index + 1
    end
  end
  return lines
end

local function replace_sections(chunk, replacement)
  local lines = split_lines(chunk)
  local wanted = {}
  local chunks = {}
  replacement = replacement or {}
  local order = { "FXCHAIN", "ITEM" }
  for _, key in ipairs(envelope_order) do order[#order + 1] = key end
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
  return join_lines(cleaned)
end

local function replace_root_lines(chunk, values)
  local lines = split_lines(chunk)
  local depth = 0
  for index, line in ipairs(lines) do
    if depth == 1 then
      local key = root_line_key(line)
      if key and values and values[key] then lines[index] = values[key] end
    end
    if starts_with(line, "<") then depth = depth + 1 elseif starts_with(line, ">") then depth = math.max(0, depth - 1) end
  end
  return join_lines(lines)
end

local function keep_target_track_identity(source_chunk, target_chunk)
  local source_lines = split_lines(source_chunk)
  local target_lines = split_lines(target_chunk)
  if #source_lines == 0 then return nil end
  if target_lines[1] and starts_with(target_lines[1], "<TRACK") then source_lines[1] = target_lines[1] end
  return replace_root_lines(join_lines(source_lines), extract_root_lines(target_chunk, { TRACKID = true }))
end

local function new_data()
  return { schema_version = 1, selected_state_id = nil, states = {} }
end

local function normalize_data(value)
  if type(value) ~= "table" then return new_data() end
  value.schema_version = tonumber(value.schema_version) or 1
  if type(value.states) ~= "table" then value.states = {} end
  local states = {}
  for _, recall in ipairs(value.states) do
    if type(recall) == "table" and recall.id and recall.sections then
      local full_chunk = type(recall.sections) == "table" and recall.sections.full_chunk or nil
      recall.name = tostring(recall.name or "Recall")
      recall.created_at = tonumber(recall.created_at) or now()
      recall.updated_at = tonumber(recall.updated_at) or recall.created_at
      recall.summary = type(recall.summary) == "table" and recall.summary or {}
      if type(full_chunk) == "string" and full_chunk ~= "" then
        recall.sections = { full_chunk = full_chunk }
        states[#states + 1] = recall
      end
    end
  end
  value.states = states
  return value
end

local function normalize_index_data(value)
  if type(value) ~= "table" then return new_data() end
  value.schema_version = tonumber(value.schema_version) or 1
  if type(value.states) ~= "table" then value.states = {} end
  local states = {}
  for _, recall in ipairs(value.states) do
    if type(recall) == "table" and recall.id then
      states[#states + 1] = {
        id = recall.id,
        name = tostring(recall.name or "Recall"),
        created_at = tonumber(recall.created_at) or now(),
        updated_at = tonumber(recall.updated_at) or recall.created_at,
        track_name = tostring(recall.track_name or ""),
        track_color = tonumber(recall.track_color) or 0,
        summary = type(recall.summary) == "table" and recall.summary or {}
      }
    end
  end
  value.states = states
  return value
end

local function build_index_data(data)
  local index = { schema_version = 1, selected_state_id = data and data.selected_state_id or nil, states = {} }
  for _, recall in ipairs(data and data.states or {}) do
    if type(recall) == "table" and recall.id then
      index.states[#index.states + 1] = {
        id = recall.id,
        name = tostring(recall.name or "Recall"),
        created_at = tonumber(recall.created_at) or now(),
        updated_at = tonumber(recall.updated_at) or recall.created_at,
        track_name = tostring(recall.track_name or ""),
        track_color = tonumber(recall.track_color) or 0,
        summary = type(recall.summary) == "table" and recall.summary or {}
      }
    end
  end
  return index
end

local function read_track_index(track)
  local key = project_ext_key(track, EXT_INDEX_PREFIX)
  if not key then return new_data(), nil, false end
  local ok, raw = r.GetProjExtState(0, EXT_SECTION, key)
  if ok ~= 1 or not raw or raw == "" then return new_data(), nil, false end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok or type(decoded) ~= "table" then return new_data(), "Could not read Track Recall index", false end
  return normalize_index_data(decoded), nil, true
end

local function read_track_data(track)
  local key = project_ext_key(track, EXT_DATA_PREFIX)
  if not key then return new_data(), nil end
  local ok, raw = r.GetProjExtState(0, EXT_SECTION, key)
  if ok ~= 1 or not raw or raw == "" then return new_data(), nil end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok or type(decoded) ~= "table" then return new_data(), "Could not read Track Recall data" end
  return normalize_data(decoded), nil
end

local function write_track_index(track, data)
  local key = project_ext_key(track, EXT_INDEX_PREFIX)
  if not key then return false end
  local ok, encoded = pcall(json.encode, build_index_data(data))
  if not ok or not encoded then return false end
  return r.SetProjExtState(0, EXT_SECTION, key, encoded) == 1
end

local function write_track_data(track, data)
  local key = project_ext_key(track, EXT_DATA_PREFIX)
  if not key then return false end
  local ok, encoded = pcall(json.encode, data)
  if not ok or not encoded then return false end
  return r.SetProjExtState(0, EXT_SECTION, key, encoded) == 1
end

local function clear_track_index(track)
  local key = project_ext_key(track, EXT_INDEX_PREFIX)
  if not key then return false end
  return r.SetProjExtState(0, EXT_SECTION, key, "") == 1
end

local function clear_track_data(track)
  local key = project_ext_key(track, EXT_DATA_PREFIX)
  if not key then return false end
  return r.SetProjExtState(0, EXT_SECTION, key, "") == 1
end

local function cache_current_track()
  if not state.track_guid or not state.data then return end
  state.cache[state.track_guid] = {
    data = state.data,
    full_loaded = state.full_loaded == true,
    has_index = state.has_index == true,
    error = state.error
  }
end

local function use_cached_track(guid)
  local cached = guid and state.cache[guid]
  if not cached then return false end
  state.track_guid = guid
  state.data = cached.data
  state.full_loaded = cached.full_loaded == true
  state.has_index = cached.has_index == true
  state.error = cached.error
  state.dirty_filter = true
  return true
end

local function load_for_track(track)
  local guid = track_guid(track)
  if state.track_guid == guid and state.data then return end
  if use_cached_track(guid) then return end
  state.track_guid = guid
  state.data, state.error, state.has_index = read_track_index(track)
  state.full_loaded = false
  cache_current_track()
  state.dirty_filter = true
end

local function ensure_full_data(app, track)
  if state.full_loaded then return true end
  local guid = track_guid(track)
  if state.track_guid ~= guid then load_for_track(track) end
  if state.full_loaded then return true end
  local selected_state_id = state.data and state.data.selected_state_id or nil
  state.data, state.error = read_track_data(track)
  state.dirty_filter = true
  if state.error then
    state.full_loaded = false
    if app then app.status = state.error end
    return false
  end
  if selected_state_id then state.data.selected_state_id = selected_state_id end
  state.full_loaded = true
  if #(state.data.states or {}) == 0 then
    clear_track_index(track)
    state.has_index = false
  else
    state.has_index = write_track_index(track, state.data) == true
  end
  cache_current_track()
  return true
end

local function save_for_track(track)
  if not track or not state.data or not state.full_loaded then return false end
  if #(state.data.states or {}) == 0 then
    local data_ok = clear_track_data(track)
    local index_ok = clear_track_index(track)
    state.has_index = false
    cache_current_track()
    return data_ok and index_ok
  end
  local ok = write_track_data(track, state.data)
  if ok then state.has_index = write_track_index(track, state.data) == true end
  cache_current_track()
  return ok
end

local function capture_track_state(track)
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok or not chunk or chunk == "" then return nil end
  local item_sections = extract_sections(chunk, { ITEM = true })
  local envelope_sections = extract_sections(chunk, envelope_keys)
  local fx_count = r.TrackFX_GetCount(track) or 0
  return {
    full_chunk = chunk,
    summary = {
      fx = fx_count,
      items = #item_sections,
      envelopes = #envelope_sections
    }
  }
end

local function add_recall(app, track, name)
  if not ensure_full_data(app, track) then return end
  local captured = capture_track_state(track)
  if not captured then app.status = "Could not capture selected track"; return end
  local timestamp = now()
  name = clean_name(name, "Recall " .. tostring(#state.data.states + 1))
  state.data.states[#state.data.states + 1] = {
    id = "recall_" .. tostring(timestamp) .. "_" .. tostring(#state.data.states + 1),
    name = name,
    created_at = timestamp,
    updated_at = timestamp,
    track_name = track_name(track),
    track_color = r.GetTrackColor(track) or 0,
    summary = captured.summary,
    sections = captured
  }
  state.data.selected_state_id = state.data.states[#state.data.states].id
  save_for_track(track)
  state.dirty_filter = true
  app.status = "Saved Track Recall: " .. name
end

local function find_recall(id)
  for index, recall in ipairs(state.data and state.data.states or {}) do
    if recall.id == id then return recall, index end
  end
  return nil, nil
end

local function overwrite_recall(app, track, id)
  if not ensure_full_data(app, track) then return end
  local recall = find_recall(id)
  if not recall then return end
  local captured = capture_track_state(track)
  if not captured then app.status = "Could not capture selected track"; return end
  recall.updated_at = now()
  recall.track_name = track_name(track)
  recall.track_color = r.GetTrackColor(track) or 0
  recall.summary = captured.summary
  recall.sections = captured
  state.data.selected_state_id = id
  save_for_track(track)
  state.dirty_filter = true
  app.status = "Overwritten Track Recall: " .. recall.name
end

local function delete_recall(app, track, id)
  if not ensure_full_data(app, track) then return end
  local recall, index = find_recall(id)
  if not recall then return end
  table.remove(state.data.states, index)
  if state.data.selected_state_id == id then state.data.selected_state_id = state.data.states[1] and state.data.states[1].id or nil end
  save_for_track(track)
  state.dirty_filter = true
  app.status = "Deleted Track Recall: " .. recall.name
end

local function duplicate_recall(app, track, id)
  if not ensure_full_data(app, track) then return end
  local recall = find_recall(id)
  if not recall then return end
  local duplicate = copy_default(recall)
  duplicate.id = "recall_" .. tostring(now()) .. "_" .. tostring(#state.data.states + 1)
  duplicate.name = tostring(duplicate.name or "Recall") .. " Copy"
  duplicate.created_at = now()
  duplicate.updated_at = duplicate.created_at
  state.data.states[#state.data.states + 1] = duplicate
  state.data.selected_state_id = duplicate.id
  save_for_track(track)
  state.dirty_filter = true
  app.status = "Duplicated Track Recall: " .. duplicate.name
end

local function begin_create_recall(track)
  state.create_name = track_name(track) .. " Recall"
end

local function restore_options(settings)
  local fx = settings.custom_fx == true
  local items = settings.custom_items == true
  local envelopes = settings.custom_envelopes == true
  local misc = settings.custom_misc == true
  if fx and items and envelopes and misc then return { full = true } end
  return { fx = fx, items = items, envelopes = envelopes, misc = misc }
end

local function enabled_parts_text(settings)
  local parts = {}
  if settings.custom_fx == true then parts[#parts + 1] = "FX" end
  if settings.custom_items == true then parts[#parts + 1] = "Items" end
  if settings.custom_envelopes == true then parts[#parts + 1] = "Envelopes" end
  if settings.custom_misc == true then parts[#parts + 1] = "Mixer" end
  if #parts == 0 then return "nothing selected" end
  return table.concat(parts, ", ")
end

local function build_partial_chunk(current_chunk, recall, options)
  local sections = recall.sections or {}
  local source_chunk = sections.full_chunk or ""
  if source_chunk == "" then return nil end
  local replacement = {}
  if options.fx then
    local fx_chain = extract_first_section(source_chunk, "FXCHAIN")
    if fx_chain then replacement.FXCHAIN = { fx_chain } end
  end
  if options.items then replacement.ITEM = section_list_chunks(extract_sections(source_chunk, { ITEM = true })) end
  if options.envelopes then
    for key in pairs(envelope_keys) do replacement[key] = {} end
    for _, section in ipairs(extract_sections(source_chunk, envelope_keys)) do
      replacement[section.key] = replacement[section.key] or {}
      table.insert(replacement[section.key], section.chunk)
    end
  end
  local chunk = replace_sections(current_chunk, replacement)
  if options.misc then chunk = replace_root_lines(chunk, extract_root_lines(source_chunk, misc_keys)) end
  return chunk
end

local function restore_recall(app, track, recall, settings)
  local recall_id = recall and recall.id or nil
  if not ensure_full_data(app, track) then return end
  recall = recall_id and find_recall(recall_id) or recall
  if not recall or not recall.sections then app.status = "Could not load Track Recall data"; return end
  local options = restore_options(settings)
  local ok_current, current_chunk = r.GetTrackStateChunk(track, "", false)
  if not ok_current or not current_chunk then app.status = "Could not read selected track"; return end
  local target_chunk = nil
  if options.full then
    target_chunk = keep_target_track_identity(recall.sections.full_chunk, current_chunk)
  else
    target_chunk = build_partial_chunk(current_chunk, recall, options)
  end
  if not target_chunk or target_chunk == "" then app.status = "Recall is empty"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok_restore = r.SetTrackStateChunk(track, target_chunk, false)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Track Recall: " .. tostring(recall.name or "Recall"), -1)
  if ok_restore then
    state.data.selected_state_id = recall.id
    state.has_index = write_track_index(track, state.data) == true
    cache_current_track()
    app.status = "Recalled: " .. tostring(recall.name or "Recall") .. " (" .. enabled_parts_text(settings) .. ")"
  else
    app.status = "Could not restore Track Recall"
  end
end

local function add_recall_as_track(app, track, recall)
  local recall_id = recall and recall.id or nil
  if not ensure_full_data(app, track) then return end
  recall = recall_id and find_recall(recall_id) or recall
  local source_chunk = recall and recall.sections and recall.sections.full_chunk or nil
  if not source_chunk or source_chunk == "" then app.status = "Could not load Track Recall data"; return end
  local track_number = tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or r.CountTracks(0)
  local insert_index = math.max(0, math.floor(track_number))
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.InsertTrackAtIndex(insert_index, false)
  local new_track = r.GetTrack(0, insert_index)
  local ok_restore = false
  if new_track then
    local ok_current, current_chunk = r.GetTrackStateChunk(new_track, "", false)
    local target_chunk = ok_current and keep_target_track_identity(source_chunk, current_chunk) or source_chunk
    ok_restore = target_chunk and r.SetTrackStateChunk(new_track, target_chunk, false) == true
    if ok_restore then
      local new_guid = track_guid(new_track)
      local copied_data = copy_default(state.data)
      write_track_data(new_track, copied_data)
      local has_index = write_track_index(new_track, copied_data) == true
      if new_guid then state.cache[new_guid] = { data = copied_data, full_loaded = true, has_index = has_index, error = nil } end
      if r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(new_track) end
    end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Track Recall: Add as new track", -1)
  app.status = ok_restore and "Added Track Recall as new track: " .. tostring(recall.name or "Recall") or "Could not add Track Recall as new track"
end

local function format_date(value)
  local number = tonumber(value) or 0
  if number <= 0 then return "" end
  return os.date("%Y-%m-%d %H:%M", number)
end

local function refresh_filter()
  if not state.dirty_filter then return end
  local filtered = {}
  for _, recall in ipairs(state.data and state.data.states or {}) do filtered[#filtered + 1] = recall end
  table.sort(filtered, function(left, right) return (tonumber(left.updated_at) or 0) > (tonumber(right.updated_at) or 0) end)
  state.filtered = filtered
  state.dirty_filter = false
end

local function begin_rename(recall)
  state.rename_id = recall.id
  state.rename_text = tostring(recall.name or "")
  state.rename_open = true
end

local function draw_rename_popup(app, track)
  local ctx = app.ctx
  if state.rename_open then
    r.ImGui_OpenPopup(ctx, "Rename Recall")
    state.rename_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Rename Recall") then return end
  local changed, value = r.ImGui_InputText(ctx, "Name", state.rename_text or "")
  if changed then state.rename_text = value end
  local recall = find_recall(state.rename_id)
  local can_save = recall and tostring(state.rename_text or "") ~= ""
  if not can_save and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Save", 70, 0) and can_save then
    if ensure_full_data(app, track) then
      recall = find_recall(state.rename_id)
      if recall then
        recall.name = tostring(state.rename_text or "Recall")
        recall.updated_at = now()
        save_for_track(track)
        state.dirty_filter = true
        app.status = "Renamed Track Recall"
      end
    end
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", 70, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

local function draw_create_popup(app, track)
  local ctx = app.ctx
  if state.create_open then
    r.ImGui_OpenPopup(ctx, "Create Recall")
    state.create_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Create Recall") then return end
  local changed, value = r.ImGui_InputText(ctx, "Name", state.create_name or "")
  if changed then state.create_name = value end
  local can_save = clean_name(state.create_name, "") ~= ""
  if not can_save and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Save", 70, 0) and can_save then
    add_recall(app, track, state.create_name)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", 70, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

local function visible_parts(settings)
  return { fx = settings.custom_fx == true, items = settings.custom_items == true, envelopes = settings.custom_envelopes == true, misc = settings.custom_misc == true }
end

local function apply_custom_parts(settings, parts)
  settings.custom_fx = parts.fx == true
  settings.custom_items = parts.items == true
  settings.custom_envelopes = parts.envelopes == true
  settings.custom_misc = parts.misc == true
end

local function draw_part_toggle(app, settings, parts, key, label, width)
  local ctx = app.ctx
  local enabled = parts[key] == true
  local button_color = enabled and Theme.colors.accent_soft or Theme.colors.frame_bg
  local hover_color = enabled and Theme.colors.accent or Theme.colors.frame_hover
  local text_color = enabled and Theme.colors.text or Theme.colors.text_dim
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), button_color)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover_color)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
  local clicked = r.ImGui_Button(ctx, label, width, 0)
  r.ImGui_PopStyleColor(ctx, 4)
  if clicked then
    parts[key] = not enabled
    apply_custom_parts(settings, parts)
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, part_descriptions[key] or "") end
end

local function draw_recall_parts(app, settings)
  local ctx = app.ctx
  local parts = visible_parts(settings)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local spacing = 8
  if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then spacing = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing()) or spacing end
  local width = math.max(42, ((avail_w or 240) - spacing * 3) * 0.25)
  draw_part_toggle(app, settings, parts, "fx", "FX", width)
  r.ImGui_SameLine(ctx)
  draw_part_toggle(app, settings, parts, "items", "Items", width)
  r.ImGui_SameLine(ctx)
  draw_part_toggle(app, settings, parts, "envelopes", "Envelopes", width)
  r.ImGui_SameLine(ctx)
  draw_part_toggle(app, settings, parts, "misc", "Mixer", width)
end

local function draw_add_recall_button(app, track, size, centered)
  local ctx = app.ctx
  size = size or r.ImGui_GetFrameHeight(ctx)
  if centered then
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, ((avail_w or size) - size) * 0.5))
  end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_InvisibleButton(ctx, "##track_recall_add", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  local cx = (min_x + max_x) * 0.5
  local cy = (min_y + max_y) * 0.5
  local color = hovered and Theme.colors.accent or Theme.colors.border
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, size * 0.5, Theme.colors.frame_bg, 32)
  r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.5 - 1, color, 32, hovered and 2 or 1)
  r.ImGui_DrawList_AddLine(draw_list, cx - 6, cy, cx + 6, cy, Theme.colors.text, 2)
  r.ImGui_DrawList_AddLine(draw_list, cx, cy - 6, cx, cy + 6, Theme.colors.text, 2)
  if hovered then r.ImGui_SetTooltip(ctx, "Save Track Recall") end
  if clicked then begin_create_recall(track); state.create_open = true end
end

local function draw_recall_row(app, track, recall, settings)
  local ctx = app.ctx
  local selected = state.data and state.data.selected_state_id == recall.id
  local summary = recall.summary or {}
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(120, avail_w or 120)
  local row_h = 52
  r.ImGui_PushID(ctx, recall.id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##recall_card", width, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local bg = selected and 0x7AA2F730 or (hovered and 0xFFFFFF12 or 0x00000000)
  if bg ~= 0x00000000 then r.ImGui_DrawList_AddRectFilled(draw_list, x, y + 2, x + width, y + row_h - 2, bg, 5) end
  r.ImGui_DrawList_AddRect(draw_list, x, y + 2, x + width, y + row_h - 2, selected and Theme.colors.accent or Theme.colors.border, 5, 0, selected and 1.4 or 0.7)
  r.ImGui_DrawList_AddRectFilled(draw_list, x + 7, y + 11, x + 23, y + 27, Theme.colors.accent, 3)
  r.ImGui_DrawList_AddText(draw_list, x + 11, y + 12, 0x111111FF, "R")
  r.ImGui_DrawList_PushClipRect(draw_list, x + 32, y + 4, x + width - 8, y + row_h - 4, true)
  r.ImGui_DrawList_AddText(draw_list, x + 32, y + 8, Theme.colors.text, tostring(recall.name or "Recall"))
  local details = string.format("FX %d | Items %d | Env %d | %s", tonumber(summary.fx) or 0, tonumber(summary.items) or 0, tonumber(summary.envelopes) or 0, format_date(recall.updated_at))
  r.ImGui_DrawList_AddText(draw_list, x + 32, y + 29, Theme.colors.text_dim, details)
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked then restore_recall(app, track, recall, settings) end
  if hovered then r.ImGui_SetTooltip(ctx, "Click to recall the enabled parts") end
  if r.ImGui_BeginPopupContextItem(ctx, "##recall_context") then
    if r.ImGui_MenuItem(ctx, "Recall") then restore_recall(app, track, recall, settings) end
    if r.ImGui_MenuItem(ctx, "Add as New Track") then add_recall_as_track(app, track, recall) end
    if r.ImGui_MenuItem(ctx, "Resave") then overwrite_recall(app, track, recall.id) end
    if r.ImGui_MenuItem(ctx, "Rename") then begin_rename(recall) end
    if r.ImGui_MenuItem(ctx, "Duplicate") then duplicate_recall(app, track, recall.id) end
    if r.ImGui_MenuItem(ctx, "Delete") then delete_recall(app, track, recall.id) end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopID(ctx)
end

local function draw_recall_list(app, track, settings, height)
  local ctx = app.ctx
  local child_visible = r.ImGui_BeginChild(ctx, "##track_recall_list", 0, height, 0)
  local ok = true
  local err = nil
  if child_visible then
    ok, err = pcall(function()
      if #state.filtered == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, #state.data.states == 0 and "No recalls saved for this track." or "No matching recalls.")
      else
        for _, recall in ipairs(state.filtered) do draw_recall_row(app, track, recall, settings) end
      end
      draw_add_recall_button(app, track, 34, true)
    end)
    r.ImGui_EndChild(ctx)
  end
  if not ok then error(err) end
end

function M.init(app)
  ensure_settings(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local track = selected_track(app)
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  if not track then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select a track to use Track Recall.")
    UI.draw_info_line(ctx, "No selected track")
    return
  end
  load_for_track(track)
  refresh_filter()
  local name = selected_track_label(app, track)
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local color = r.GetTrackColor(track) or 0
  local native_color = native_color_to_u32(color, 0xCC) or Theme.colors.accent
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y + 2, x + 6, y + r.ImGui_GetTextLineHeight(ctx) + 2, native_color)
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + 12)
  r.ImGui_TextColored(ctx, Theme.colors.accent, name)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(#state.data.states) .. " recalls")
  r.ImGui_SameLine(ctx)
  local reload_x = math.max(r.ImGui_GetCursorPosX(ctx), (avail_w or 320) - button_h)
  r.ImGui_SetCursorPosX(ctx, reload_x)
  if r.ImGui_Button(ctx, "R##track_recall_reload", button_h, button_h) then
    local guid = track_guid(track)
    if guid then state.cache[guid] = nil end
    state.track_guid = nil
    load_for_track(track)
    if state.has_index then
      app.status = "Track Recall index reloaded"
    elseif ensure_full_data(app, track) then
      app.status = "Track Recall loaded"
    end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Reload or load recalls") end
  if state.error then r.ImGui_TextColored(ctx, Theme.colors.warning, state.error) end
  draw_recall_parts(app, settings)
  draw_create_popup(app, track)
  draw_rename_popup(app, track)
  local _, remaining_h = r.ImGui_GetContentRegionAvail(ctx)
  local info_h = UI.info_line_height(ctx)
  local list_h = math.max(80, (remaining_h or avail_h or 300) - info_h)
  draw_recall_list(app, track, settings, list_h)
  UI.draw_info_line(ctx, tostring(#state.data.states) .. " recalls | " .. enabled_parts_text(settings))
end

return M