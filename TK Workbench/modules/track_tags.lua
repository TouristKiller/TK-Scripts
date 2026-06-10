local r = reaper
local json = require("core.json")
local UI = require("core.ui")
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")

local M = {
  id = "track_tags",
  title = "Tags",
  icon = "TAG",
  version = "0.1.1"
}

local resource_path = r.GetResourcePath()
local fx_root = resource_path .. "/Scripts/TK Scripts/FX/"
local workbench_store_path = resource_path .. "/Scripts/TK Scripts/TK Workbench/track_tags.json"
local fx_store_path = fx_root .. "track_tags.json"
local fx_folder_store_path = fx_root .. "TK FX BROWSER/track_tags.json"

local defaults = {
  store_mode = "auto",
  preferred_store = "fx_browser",
  auto_reload = true,
  reload_interval = 2.0,
  last_store_path = "",
  show_empty_tracks = true,
  show_tag_colors = true,
  sync_strategy = "manual",
  search_term = "",
  filter_tag = "",
  selected_tags = {}
}

local state = {
  data = { tracks = {}, colors = {}, filters = {}, available = {} },
  store_path = "",
  store_label = "Workbench",
  load_error = nil,
  last_load_time = 0,
  new_tag_text = "",
  new_tag_color = 0x7AA2F7FF,
  edit_color_tag = "",
  edit_color_value = 0x7AA2F7FF,
  rename_tag = "",
  rename_tag_text = "",
  pending_remove_tag = "",
  pending_remove_open = false,
  filtered_tracks = {},
  available_sorted = {},
  last_filter_key = nil,
  visibility_snapshot = nil
}

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local target = {}
  for key, child in pairs(value) do target[key] = copy_default(child) end
  return target
end

local function configure_paths(app)
  local path = app and app.script_path
  if type(path) == "string" and path ~= "" then workbench_store_path = path .. "track_tags.json" end
end

local function ensure_settings(app)
  configure_paths(app)
  app.settings.track_tags = app.settings.track_tags or {}
  local settings = app.settings.track_tags
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

local function file_exists(path)
  if not path or path == "" then return false end
  if r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function read_text(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
end

local function write_text(path, content)
  local file = io.open(path, "w")
  if not file then return false end
  file:write(content or "")
  file:close()
  return true
end

local function read_json(path)
  local content = read_text(path)
  if not content or content == "" then return {} end
  local ok, decoded = pcall(json.decode, content)
  if ok and type(decoded) == "table" then return decoded end
  return {}
end

local function write_json(path, value)
  local ok, encoded = pcall(json.encode, value)
  if not ok or not encoded then return false end
  return write_text(path, encoded)
end

local function valid_guid(value)
  return type(value) == "string" and value ~= "" and value ~= "{}"
end

local function track_guid(track)
  if not track then return nil end
  if r.GetTrackGUID then
    local ok, guid = pcall(r.GetTrackGUID, track)
    if ok and valid_guid(guid) then return guid end
  end
  if r.GetSetMediaTrackInfo_String then
    for _, key in ipairs({ "GUID", "P_GUID" }) do
      local ok, retval, guid = pcall(r.GetSetMediaTrackInfo_String, track, key, "", false)
      if ok and retval and valid_guid(guid) then return guid end
    end
  end
  if r.GetTrackStateChunk then
    local ok, retval, chunk = pcall(r.GetTrackStateChunk, track, "", false)
    if ok and retval and type(chunk) == "string" then
      local guid = chunk:match("TRACKID%s+({[^%s]+})") or chunk:match("TRACKID%s+([^%s]+)")
      if valid_guid(guid) then return guid end
    end
  end
  return nil
end

local function fx_browser_available()
  return file_exists(fx_store_path) or file_exists(fx_folder_store_path) or file_exists(fx_root .. "TK_FX_BROWSER.lua") or file_exists(fx_root .. "TK_FX_BROWSER Mini.lua")
end

local function detect_store(settings)
  local mode = settings.store_mode or "auto"
  if mode == "workbench" then return workbench_store_path, "Workbench" end
  if mode == "fx_browser" then
    if file_exists(fx_folder_store_path) then return fx_folder_store_path, "TK FX Browser" end
    return fx_store_path, "TK FX Browser"
  end
  if file_exists(fx_folder_store_path) then return fx_folder_store_path, "TK FX Browser" end
  if fx_browser_available() then return fx_store_path, "TK FX Browser" end
  return workbench_store_path, "Workbench"
end

local function normalize_tag_array(value)
  local result = {}
  local seen = {}
  if type(value) ~= "table" then return result end
  for _, tag in ipairs(value) do
    local text = tostring(tag or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text ~= "" and not seen[text] then
      result[#result + 1] = text
      seen[text] = true
    end
  end
  table.sort(result, function(a, b) return a:lower() < b:lower() end)
  return result
end

local function normalize_data(data)
  data = type(data) == "table" and data or {}
  data.tracks = type(data.tracks) == "table" and data.tracks or {}
  data.colors = type(data.colors) == "table" and data.colors or {}
  data.filters = type(data.filters) == "table" and data.filters or {}
  data.available = type(data.available) == "table" and data.available or {}
  for guid, tags in pairs(data.tracks) do
    data.tracks[guid] = normalize_tag_array(tags)
  end
  for tag, color in pairs(data.colors) do
    local numeric = tonumber(color)
    if numeric then data.colors[tag] = numeric else data.colors[tag] = nil end
  end
  for tag, value in pairs(data.available) do
    if value == false then data.available[tag] = nil end
  end
  return data
end

local function refresh_available_sorted()
  local result = {}
  for tag in pairs(state.data.available or {}) do result[#result + 1] = tag end
  table.sort(result, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
  state.available_sorted = result
end

local function load_store(settings, force)
  local path, label = detect_store(settings)
  local now = r.time_precise and r.time_precise() or os.time()
  if not force and path == state.store_path and settings.auto_reload ~= false and now - state.last_load_time < (settings.reload_interval or defaults.reload_interval) then return end
  if not force and path == state.store_path and settings.auto_reload == false and state.last_load_time > 0 then return end
  state.store_path = path
  state.store_label = label
  settings.last_store_path = path
  state.data = normalize_data(read_json(path))
  state.load_error = nil
  state.last_load_time = now
  refresh_available_sorted()
end

local function save_store(app)
  state.data = normalize_data(state.data)
  refresh_available_sorted()
  if write_json(state.store_path, state.data) then
    state.load_error = nil
    state.last_load_time = r.time_precise and r.time_precise() or os.time()
    state.last_filter_key = nil
    return true
  end
  state.load_error = "Could not write " .. tostring(state.store_path)
  if app then app.status = state.load_error end
  return false
end

local function backup_file(path)
  if not file_exists(path) then return true end
  local content = read_text(path)
  if not content then return false end
  local backup = path .. ".bak." .. tostring(os.time())
  return write_text(backup, content)
end

local function merge_data(primary, secondary)
  primary = normalize_data(primary)
  secondary = normalize_data(secondary)
  for tag in pairs(secondary.available or {}) do primary.available[tag] = true end
  for tag, color in pairs(secondary.colors or {}) do
    if primary.colors[tag] == nil then primary.colors[tag] = color end
  end
  for key, value in pairs(secondary.filters or {}) do
    if primary.filters[key] == nil then primary.filters[key] = value end
  end
  for guid, tags in pairs(secondary.tracks or {}) do
    local target = primary.tracks[guid] or {}
    local seen = {}
    for _, tag in ipairs(target) do seen[tag] = true end
    for _, tag in ipairs(tags) do
      if not seen[tag] then
        target[#target + 1] = tag
        seen[tag] = true
      end
    end
    primary.tracks[guid] = normalize_tag_array(target)
  end
  return normalize_data(primary)
end

local function sync_with_fx_browser(app, settings)
  local active_path = state.store_path ~= "" and state.store_path or select(1, detect_store(settings))
  local target_path = file_exists(fx_folder_store_path) and fx_folder_store_path or fx_store_path
  if active_path == target_path and not file_exists(workbench_store_path) then
    app.status = "Tags already uses TK FX Browser tags"
    return
  end
  backup_file(target_path)
  backup_file(workbench_store_path)
  local target_data = read_json(target_path)
  local own_data = read_json(workbench_store_path)
  local merged = merge_data(target_data, own_data)
  if active_path ~= target_path then merged = merge_data(merged, state.data) end
  if write_json(target_path, merged) then
    settings.store_mode = "fx_browser"
    settings.last_store_path = target_path
    if app.save_settings then app.save_settings() end
    state.store_path = target_path
    state.store_label = "TK FX Browser"
    state.data = normalize_data(merged)
    refresh_available_sorted()
    app.status = "Tags synced with TK FX Browser"
  else
    app.status = "Tags sync failed"
  end
end

local function track_name(track, index)
  local ok, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if ok and name and name ~= "" then return name end
  return "Track " .. tostring(index + 1)
end

local function collect_tracks(settings)
  local result = {}
  local search = tostring(settings.search_term or ""):lower()
  local selected_tags = settings.selected_tags
  local selected_lookup = {}
  local selected_count = 0
  if type(selected_tags) == "table" then
    for _, tag in ipairs(selected_tags) do
      tag = tostring(tag or "")
      if tag ~= "" and not selected_lookup[tag] then
        selected_lookup[tag] = true
        selected_count = selected_count + 1
      end
    end
  end
  if selected_count == 0 and tostring(settings.filter_tag or "") ~= "" then
    selected_lookup[tostring(settings.filter_tag)] = true
    selected_count = 1
  end
  local count = r.CountTracks(0)
  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    if guid then
      local tags = state.data.tracks[guid] or {}
      local name = track_name(track, index)
      local include = settings.show_empty_tracks == true or #tags > 0
      local matches_selected_tags = false
      if selected_count > 0 then
        for _, tag in ipairs(tags) do if selected_lookup[tag] then matches_selected_tags = true break end end
      end
      if include and search ~= "" then
        local haystack = name:lower()
        for _, tag in ipairs(tags) do haystack = haystack .. " " .. tag:lower() end
        include = haystack:find(search, 1, true) ~= nil
      end
      if include then result[#result + 1] = { track = track, guid = guid, index = index, name = name, tags = tags, matches_selected_tags = matches_selected_tags } end
    end
  end
  state.filtered_tracks = result
end

local function normalize_selected_tags(settings)
  local selected = {}
  local seen = {}
  if type(settings.selected_tags) == "table" then
    for _, tag in ipairs(settings.selected_tags) do
      tag = tostring(tag or "")
      if tag ~= "" and not seen[tag] then
        selected[#selected + 1] = tag
        seen[tag] = true
      end
    end
  end
  if #selected == 0 and tostring(settings.filter_tag or "") ~= "" then
    local tag = tostring(settings.filter_tag)
    selected[1] = tag
    seen[tag] = true
  end
  settings.selected_tags = selected
  settings.filter_tag = selected[1] or ""
  return selected, seen
end

local function tag_is_selected(settings, tag)
  local selected = normalize_selected_tags(settings)
  for _, current in ipairs(selected) do if current == tag then return true end end
  return false
end

local function selected_tag_tracks(settings)
  local selected = normalize_selected_tags(settings)
  local selected_lookup = {}
  for _, tag in ipairs(selected) do selected_lookup[tag] = true end
  local result = {}
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    if guid then
      local tags = state.data.tracks[guid]
      if type(tags) == "table" then
        for _, tag in ipairs(tags) do
          if selected_lookup[tag] then result[#result + 1] = track break end
        end
      end
    end
  end
  return result
end

local function selected_track_guids()
  local result = {}
  local count = r.CountSelectedTracks(0)
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    local guid = track_guid(track)
    if guid then result[#result + 1] = guid end
  end
  return result
end

local function clean_tag(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local set_selected_tags_visibility
local show_all_tracks
local restore_previous_visibility

local function clear_visibility_snapshot()
  state.visibility_snapshot = nil
end

local function snapshot_visibility()
  local tracks = {}
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    if guid then
      tracks[guid] = {
        tcp = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") or 0,
        mixer = r.GetMediaTrackInfo_Value(track, "B_SHOWINMIXER") or 0
      }
    end
  end
  state.visibility_snapshot = { tracks = tracks }
end

local function ensure_visibility_snapshot()
  if state.visibility_snapshot == nil then snapshot_visibility() end
end

local function add_tag_to_guids(app, guids, tag)
  tag = clean_tag(tag)
  if tag == "" then app.status = "Tags: tag is empty"; return false end
  if #guids == 0 then app.status = "Tags: no selected tracks"; return false end
  local changed = false
  for _, guid in ipairs(guids) do
    state.data.tracks[guid] = state.data.tracks[guid] or {}
    local exists = false
    for _, current in ipairs(state.data.tracks[guid]) do if current == tag then exists = true break end end
    if not exists then
      state.data.tracks[guid][#state.data.tracks[guid] + 1] = tag
      changed = true
    end
  end
  state.data.available[tag] = true
  if changed and save_store(app) then app.status = "Tags added tag: " .. tag end
  return changed
end

local function create_tag(app, tag, color)
  tag = clean_tag(tag)
  if tag == "" then app.status = "Tags: tag is empty"; return false end
  local guids = selected_track_guids()
  state.data.available[tag] = true
  if color then state.data.colors[tag] = color end
  if #guids > 0 then
    for _, guid in ipairs(guids) do
      state.data.tracks[guid] = state.data.tracks[guid] or {}
      local exists = false
      for _, current in ipairs(state.data.tracks[guid]) do if current == tag then exists = true break end end
      if not exists then state.data.tracks[guid][#state.data.tracks[guid] + 1] = tag end
    end
  end
  if save_store(app) then
    app.status = #guids > 0 and ("Tags added tag: " .. tag) or ("Tags created tag: " .. tag)
    return true
  end
  return false
end

local function remove_tag_from_guid(app, guid, tag)
  local tags = state.data.tracks[guid]
  if type(tags) ~= "table" then return end
  local changed = false
  for index = #tags, 1, -1 do
    if tags[index] == tag then table.remove(tags, index); changed = true end
  end
  if #tags == 0 then state.data.tracks[guid] = nil end
  if changed and save_store(app) then app.status = "Tags removed tag: " .. tag end
end

local function remove_tag_from_selected(app, tag)
  local guids = selected_track_guids()
  if #guids == 0 then app.status = "Tags: no selected tracks"; return end
  local changed = false
  for _, guid in ipairs(guids) do
    local tags = state.data.tracks[guid]
    if type(tags) == "table" then
      for index = #tags, 1, -1 do
        if tags[index] == tag then table.remove(tags, index); changed = true end
      end
      if #tags == 0 then state.data.tracks[guid] = nil end
    end
  end
  if changed and save_store(app) then app.status = "Tags removed tag from selected tracks" end
end

local function update_selected_tag_name(app, settings, old_tag, new_tag)
  local selected = normalize_selected_tags(settings)
  local next_tags = {}
  local seen = {}
  local changed = false
  for _, tag in ipairs(selected) do
    local value = tag == old_tag and new_tag or tag
    if value ~= tag then changed = true end
    if value ~= "" and not seen[value] then
      next_tags[#next_tags + 1] = value
      seen[value] = true
    end
  end
  if changed then
    settings.selected_tags = next_tags
    settings.filter_tag = next_tags[1] or ""
    state.last_filter_key = nil
    if app.save_settings then app.save_settings() end
  end
  return changed
end

local function remove_selected_tag_name(app, settings, removed_tag)
  local selected = normalize_selected_tags(settings)
  local next_tags = {}
  local changed = false
  for _, tag in ipairs(selected) do
    if tag == removed_tag then changed = true else next_tags[#next_tags + 1] = tag end
  end
  if changed then
    settings.selected_tags = next_tags
    settings.filter_tag = next_tags[1] or ""
    state.last_filter_key = nil
    if app.save_settings then app.save_settings() end
    if #next_tags > 0 then set_selected_tags_visibility(app, settings) else restore_previous_visibility(app) end
  end
end

local function rename_tag_everywhere(app, settings, old_tag, new_tag)
  old_tag = clean_tag(old_tag)
  new_tag = clean_tag(new_tag)
  if old_tag == "" or new_tag == "" then app.status = "Tags: tag is empty"; return false end
  if old_tag == new_tag then return false end
  local changed = false
  state.data.available[old_tag] = nil
  state.data.available[new_tag] = true
  changed = true
  if state.data.colors[old_tag] ~= nil then
    if state.data.colors[new_tag] == nil then state.data.colors[new_tag] = state.data.colors[old_tag] end
    state.data.colors[old_tag] = nil
    changed = true
  end
  if state.data.filters[old_tag] ~= nil then
    if state.data.filters[new_tag] == nil then state.data.filters[new_tag] = state.data.filters[old_tag] end
    state.data.filters[old_tag] = nil
    changed = true
  end
  for guid, tags in pairs(state.data.tracks) do
    if type(tags) == "table" then
      for index, tag in ipairs(tags) do
        if tag == old_tag then tags[index] = new_tag; changed = true end
      end
      state.data.tracks[guid] = normalize_tag_array(tags)
    end
  end
  if update_selected_tag_name(app, settings, old_tag, new_tag) then set_selected_tags_visibility(app, settings) end
  if changed and save_store(app) then
    app.status = "Tags renamed " .. old_tag .. " to " .. new_tag
    return true
  end
  return false
end

local function remove_tag_completely(app, settings, tag)
  tag = clean_tag(tag)
  if tag == "" then return false end
  local changed = false
  if state.data.available[tag] ~= nil then state.data.available[tag] = nil; changed = true end
  if state.data.colors[tag] ~= nil then state.data.colors[tag] = nil; changed = true end
  if state.data.filters[tag] ~= nil then state.data.filters[tag] = nil; changed = true end
  for guid, tags in pairs(state.data.tracks) do
    if type(tags) == "table" then
      for index = #tags, 1, -1 do
        if tags[index] == tag then table.remove(tags, index); changed = true end
      end
      if #tags == 0 then state.data.tracks[guid] = nil end
    end
  end
  remove_selected_tag_name(app, settings, tag)
  if changed and save_store(app) then
    app.status = "Tags completely removed tag: " .. tag
    return true
  end
  app.status = "Tags tag was not found"
  return false
end

local function remove_tag_from_all_tracks(app, tag)
  tag = clean_tag(tag)
  if tag == "" then return false end
  local changed = false
  for guid, tags in pairs(state.data.tracks) do
    if type(tags) == "table" then
      for index = #tags, 1, -1 do
        if tags[index] == tag then table.remove(tags, index); changed = true end
      end
      if #tags == 0 then state.data.tracks[guid] = nil end
    end
  end
  if changed and save_store(app) then
    app.status = "Tags removed tag from all tracks: " .. tag
    return true
  end
  app.status = "Tags tag was not assigned to tracks"
  return false
end

local function tracks_with_tag(tag)
  local result = {}
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    if guid then
      local tags = state.data.tracks[guid]
      if type(tags) == "table" then
        for _, current in ipairs(tags) do
          if current == tag then result[#result + 1] = track break end
        end
      end
    end
  end
  return result
end

local function select_tracks_with_tag(app, tag)
  local tracks = tracks_with_tag(tag)
  r.Undo_BeginBlock()
  r.Main_OnCommand(40297, 0)
  for _, track in ipairs(tracks) do r.SetTrackSelected(track, true) end
  r.Undo_EndBlock("Select tracks by tag", -1)
  app.status = "Tags selected " .. tostring(#tracks) .. " tracks"
end

local function tagged_tracks_all_state(tag, field, value)
  local tracks = tracks_with_tag(tag)
  if #tracks == 0 then return false end
  for _, track in ipairs(tracks) do
    local current = r.GetMediaTrackInfo_Value(track, field)
    if field == "I_SOLO" then
      if value == 1 and current <= 0 then return false end
      if value == 0 and current > 0 then return false end
    elseif current ~= value then
      return false
    end
  end
  return true
end

local function set_tagged_track_state(app, tag, field, value, label)
  local tracks = tracks_with_tag(tag)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, track in ipairs(tracks) do r.SetMediaTrackInfo_Value(track, field, value) end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock(label, -1)
  app.status = "Tags " .. label:lower() .. ": " .. tostring(#tracks) .. " tracks"
end

local function solo_select_tracks_with_tag(app, tag)
  local tracks = tracks_with_tag(tag)
  local tagged = {}
  for _, track in ipairs(tracks) do
    local guid = track_guid(track)
    if guid then tagged[guid] = true end
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.Main_OnCommand(40297, 0)
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    local active = guid and tagged[guid] == true
    r.SetTrackSelected(track, active)
    r.SetMediaTrackInfo_Value(track, "I_SOLO", active and 1 or 0)
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Solo select tracks by tag", -1)
  app.status = "Tags solo selected " .. tostring(#tracks) .. " tracks"
end

function set_selected_tags_visibility(app, settings)
  ensure_visibility_snapshot()
  local tracks = selected_tag_tracks(settings)
  local tagged = {}
  for _, track in ipairs(tracks) do
    local guid = track_guid(track)
    if guid then tagged[guid] = true end
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.Main_OnCommand(40297, 0)
  for _, track in ipairs(tracks) do r.SetTrackSelected(track, true) end
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    local visible = guid and tagged[guid] == true
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", visible and 1 or 0)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", visible and 1 or 0)
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Set tagged track visibility", -1)
  app.status = "Tags selected " .. tostring(#tracks) .. " tracks"
end

function restore_previous_visibility(app)
  local snapshot = state.visibility_snapshot
  if type(snapshot) ~= "table" or type(snapshot.tracks) ~= "table" then
    app.status = "Tags: no previous visibility snapshot"
    return false
  end
  local restored = 0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    local guid = track_guid(track)
    local values = guid and snapshot.tracks[guid]
    if values then
      r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", (tonumber(values.tcp) or 0) > 0 and 1 or 0)
      r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", (tonumber(values.mixer) or 0) > 0 and 1 or 0)
      restored = restored + 1
    end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Restore tagged track visibility", -1)
  clear_visibility_snapshot()
  app.status = "Tags restored previous visibility: " .. tostring(restored) .. " tracks"
  return true
end

function show_all_tracks(app)
  clear_visibility_snapshot()
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
    r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Show all tracks", -1)
  app.status = "Tags showed all tracks"
end

local function color_text_for_bg(color)
  local red = (color >> 24) & 0xFF
  local green = (color >> 16) & 0xFF
  local blue = (color >> 8) & 0xFF
  local luminance = red * 0.299 + green * 0.587 + blue * 0.114
  return luminance > 150 and 0x111111FF or 0xFFFFFFFF
end

local function color_luminance(color)
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = color + 0x100000000 end
  local red = (color >> 24) & 0xFF
  local green = (color >> 16) & 0xFF
  local blue = (color >> 8) & 0xFF
  return (red * 0.299 + green * 0.587 + blue * 0.114) / 255
end

local function blend_channel(first, second, amount)
  return math.floor(first + (second - first) * amount + 0.5)
end

local function contrast_color(background, amount)
  background = math.floor(tonumber(background) or 0)
  if background < 0 then background = background + 0x100000000 end
  local target = color_luminance(background) > 0.5 and 0x000000FF or 0xFFFFFFFF
  local br = (background >> 24) & 0xFF
  local bg = (background >> 16) & 0xFF
  local bb = (background >> 8) & 0xFF
  local tr = (target >> 24) & 0xFF
  local tg = (target >> 16) & 0xFF
  local tb = (target >> 8) & 0xFF
  local alpha = math.floor(0x55 + 0xAA * math.max(0, math.min(1, amount or 0.3)) + 0.5)
  return blend_channel(br, tr, amount or 0.3) * 0x1000000 + blend_channel(bg, tg, amount or 0.3) * 0x10000 + blend_channel(bb, tb, amount or 0.3) * 0x100 + alpha
end

local function draw_divider(ctx, width)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local line_y = y + UIScale.round(4)
  local bg = Theme.colors.child_bg or Theme.colors.window_bg or 0x202020FF
  local line_color = contrast_color(bg, 0.32)
  r.ImGui_DrawList_AddLine(draw_list, x, line_y, x + math.max(UIScale.round(20), width or UIScale.round(100)), line_y, line_color, UIScale.px(1.4))
  r.ImGui_Dummy(ctx, width or 1, UIScale.round(9))
end

local function draw_remove_tag_confirm_popup(app, settings)
  local ctx = app.ctx
  local tag = clean_tag(state.pending_remove_tag)
  if tag == "" then return end
  if state.pending_remove_open then
    r.ImGui_OpenPopup(ctx, "Remove tag completely##tag_context_remove_complete_popup")
    state.pending_remove_open = false
  end
  local flags = r.ImGui_WindowFlags_AlwaysAutoResize and r.ImGui_WindowFlags_AlwaysAutoResize() or 0
  if r.ImGui_BeginPopupModal(ctx, "Remove tag completely##tag_context_remove_complete_popup", true, flags) then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Remove tag completely")
    r.ImGui_Separator(ctx)
    r.ImGui_TextWrapped(ctx, "This removes the tag globally and removes it from all track assignments. This can affect other projects that use this tag.")
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, tag)
    if r.ImGui_Button(ctx, "Remove##tag_context_remove_complete_confirm", UIScale.text_button_w(ctx, "Remove", 100), 0) then
      if remove_tag_completely(app, settings, tag) then
        state.pending_remove_tag = ""
        state.pending_remove_open = false
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Cancel##tag_context_remove_complete_cancel", UIScale.text_button_w(ctx, "Cancel", 90), 0) then
      state.pending_remove_tag = ""
      state.pending_remove_open = false
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_tag_chip(ctx, app, settings, tag, suffix, removable_guid)
  local color = state.data.colors[tag]
  local selected = tag_is_selected(settings, tag)
  local pushed = 0
  if settings.show_tag_colors ~= false and color then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), color_text_for_bg(color))
    pushed = 3
  end
  if r.ImGui_Button(ctx, tostring(tag) .. "##tag_chip_" .. tostring(suffix)) then
    local ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
    local selected_tags = normalize_selected_tags(settings)
    if ctrl then
      local next_tags = {}
      local removed = false
      for _, current in ipairs(selected_tags) do
        if current == tag then removed = true else next_tags[#next_tags + 1] = current end
      end
      if not removed then next_tags[#next_tags + 1] = tag end
      settings.selected_tags = next_tags
      settings.filter_tag = next_tags[1] or ""
      state.last_filter_key = nil
      if app.save_settings then app.save_settings() end
      if #next_tags > 0 then set_selected_tags_visibility(app, settings) else restore_previous_visibility(app) end
    else
      if #selected_tags == 1 and selected_tags[1] == tag then
        settings.selected_tags = {}
        settings.filter_tag = ""
        state.last_filter_key = nil
        if app.save_settings then app.save_settings() end
        restore_previous_visibility(app)
      else
        settings.selected_tags = { tag }
        settings.filter_tag = tag
        state.last_filter_key = nil
        if app.save_settings then app.save_settings() end
        set_selected_tags_visibility(app, settings)
      end
    end
  end
  if selected then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
    local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
    r.ImGui_DrawList_AddRect(draw_list, min_x - UIScale.round(1), min_y - UIScale.round(1), max_x + UIScale.round(1), max_y + UIScale.round(1), Theme.colors.accent, UIScale.px(4), 0, UIScale.px(2))
    r.ImGui_DrawList_AddCircleFilled(draw_list, max_x - UIScale.round(6), min_y + UIScale.round(6), UIScale.px(3), Theme.colors.accent, 12)
  end
  if pushed > 0 then r.ImGui_PopStyleColor(ctx, pushed) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Filter by " .. tostring(tag)) end
  if r.ImGui_BeginPopupContextItem(ctx, "##tag_context_" .. tostring(suffix)) then
    if state.edit_color_tag ~= tag then
      state.edit_color_tag = tag
      state.edit_color_value = state.data.colors[tag] or state.edit_color_value
    end
    if r.ImGui_MenuItem(ctx, "Add to selected tracks") then add_tag_to_guids(app, selected_track_guids(), tag) end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Select tracks with tag") then select_tracks_with_tag(app, tag) end
    local muted = tagged_tracks_all_state(tag, "B_MUTE", 1)
    if r.ImGui_MenuItem(ctx, muted and "Unmute tracks with tag" or "Mute tracks with tag") then set_tagged_track_state(app, tag, "B_MUTE", muted and 0 or 1, muted and "Unmute tracks by tag" or "Mute tracks by tag") end
    local armed = tagged_tracks_all_state(tag, "I_RECARM", 1)
    if r.ImGui_MenuItem(ctx, armed and "Disarm tracks with tag" or "Arm tracks with tag") then set_tagged_track_state(app, tag, "I_RECARM", armed and 0 or 1, armed and "Disarm tracks by tag" or "Arm tracks by tag") end
    local soloed = tagged_tracks_all_state(tag, "I_SOLO", 1)
    if r.ImGui_MenuItem(ctx, soloed and "Unsolo tracks with tag" or "Solo tracks with tag") then set_tagged_track_state(app, tag, "I_SOLO", soloed and 0 or 1, soloed and "Unsolo tracks by tag" or "Solo tracks by tag") end
    if r.ImGui_MenuItem(ctx, "Solo select tracks with tag") then solo_select_tracks_with_tag(app, tag) end
    r.ImGui_Separator(ctx)
    if removable_guid then
      if r.ImGui_MenuItem(ctx, "Remove from this track") then remove_tag_from_guid(app, removable_guid, tag) end
    end
    if r.ImGui_MenuItem(ctx, "Remove from selected tracks") then remove_tag_from_selected(app, tag) end
    if r.ImGui_MenuItem(ctx, "Remove from all tracks") then remove_tag_from_all_tracks(app, tag) end
      if r.ImGui_MenuItem(ctx, "Remove tag completely") then
        state.pending_remove_tag = tag
        state.pending_remove_open = true
        r.ImGui_CloseCurrentPopup(ctx)
      end
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginMenu(ctx, "Rename tag...") then
      if state.rename_tag ~= tag then
        state.rename_tag = tag
        state.rename_tag_text = tag
      end
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
      local rename_changed, rename_value = r.ImGui_InputTextWithHint(ctx, "##tag_context_rename", "Tag name", state.rename_tag_text or tag)
      if rename_changed then state.rename_tag_text = rename_value end
      if r.ImGui_Button(ctx, "Apply##tag_context_rename_apply") then
        if rename_tag_everywhere(app, settings, tag, state.rename_tag_text) then r.ImGui_CloseCurrentPopup(ctx) end
      end
      r.ImGui_EndMenu(ctx)
    end
    if r.ImGui_BeginMenu(ctx, "Set color...") then
      local changed, value = r.ImGui_ColorEdit4(ctx, "##tag_context_color", state.edit_color_value, r.ImGui_ColorEditFlags_NoInputs())
      if changed then state.edit_color_value = value end
      if r.ImGui_Button(ctx, "Apply##tag_context_color_apply") then
        state.data.colors[tag] = state.edit_color_value
        if save_store(app) then app.status = "Tags color updated" end
        r.ImGui_CloseCurrentPopup(ctx)
      end
      if state.data.colors[tag] then
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Remove##tag_context_color_remove") then
          state.data.colors[tag] = nil
          if save_store(app) then app.status = "Tags color removed" end
          r.ImGui_CloseCurrentPopup(ctx)
        end
      end
      r.ImGui_EndMenu(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_settings_popup(app, settings)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup(ctx, "##track_atlas_settings") then return end
  local changed = false
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Tags")
  r.ImGui_Separator(ctx)
  if r.ImGui_BeginCombo(ctx, "Store##track_atlas_store", settings.store_mode or "auto") then
    for _, option in ipairs({ "auto", "fx_browser", "workbench" }) do
      if r.ImGui_Selectable(ctx, option, settings.store_mode == option) then
        settings.store_mode = option
        changed = true
        load_store(settings, true)
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  local c, v = r.ImGui_Checkbox(ctx, "Auto reload", settings.auto_reload ~= false)
  if c then settings.auto_reload = v; changed = true end
  c, v = r.ImGui_Checkbox(ctx, "Show empty tracks", settings.show_empty_tracks == true)
  if c then settings.show_empty_tracks = v; changed = true end
  c, v = r.ImGui_Checkbox(ctx, "Show tag colors", settings.show_tag_colors ~= false)
  if c then settings.show_tag_colors = v; changed = true end
  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, state.store_label)
  r.ImGui_TextWrapped(ctx, state.store_path ~= "" and state.store_path or "No store selected")
  if r.ImGui_Button(ctx, "Reload##track_atlas_reload") then load_store(settings, true); app.status = "Tags reloaded" end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Sync with TK FX Browser##track_atlas_sync") then sync_with_fx_browser(app, settings) end
  if changed then
    state.last_filter_key = nil
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_EndPopup(ctx)
end

local function draw_new_tag_popup(app)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup(ctx, "##track_atlas_new_tag_popup") then return end
  r.ImGui_TextColored(ctx, Theme.colors.accent, "New tag")
  r.ImGui_Separator(ctx)
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(180))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "Name##track_atlas_new_tag_name", "Tag name", state.new_tag_text or "")
  if changed then state.new_tag_text = value end
  local color_changed, color_value = r.ImGui_ColorEdit4(ctx, "Color##track_atlas_new_tag_color", state.new_tag_color, r.ImGui_ColorEditFlags_NoInputs())
  if color_changed then state.new_tag_color = color_value end
  if r.ImGui_Button(ctx, "Add to selected tracks##track_atlas_new_tag_add", UIScale.text_button_w(ctx, "Add to selected tracks", 150), 0) then
    if create_tag(app, state.new_tag_text, state.new_tag_color) then
      state.new_tag_text = ""
      r.ImGui_CloseCurrentPopup(ctx)
    end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Create only##track_atlas_new_tag_create", UIScale.text_button_w(ctx, "Create only", 95), 0) then
    local tag = clean_tag(state.new_tag_text)
    if tag ~= "" then
      state.data.available[tag] = true
      state.data.colors[tag] = state.new_tag_color
      if save_store(app) then
        app.status = "Tags created tag: " .. tag
        state.new_tag_text = ""
        r.ImGui_CloseCurrentPopup(ctx)
      end
    else
      app.status = "Tags: tag is empty"
    end
  end
  r.ImGui_EndPopup(ctx)
end

local function draw_toolbar(app, settings, width)
  local ctx = app.ctx
  local button_h = UIScale.button_h(ctx)
  local settings_w = button_h
  local add_w = button_h
  local search_w = math.max(UIScale.round(82), width - settings_w - add_w - UIScale.round(18))
  local search_changed, search = UI.search_input(ctx, "##track_atlas_search", "Search tracks or tags", settings.search_term or "", search_w)
  if search_changed then settings.search_term = search; state.last_filter_key = nil; if app.save_settings then app.save_settings() end end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+##track_atlas_add", add_w, button_h) then r.ImGui_OpenPopup(ctx, "##track_atlas_new_tag_popup") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add new tag") end
  draw_new_tag_popup(app)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "...##track_atlas_settings_button", settings_w, button_h) then r.ImGui_OpenPopup(ctx, "##track_atlas_settings") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Tags settings") end
  draw_settings_popup(app, settings)
end

local function draw_available_tags(app, settings, width)
  local ctx = app.ctx
  if #state.available_sorted == 0 then return end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Tags")
  local line_w = 0
  local max_w = math.max(UIScale.round(80), width - UIScale.round(2))
  for index, tag in ipairs(state.available_sorted) do
    local tag_w = r.ImGui_CalcTextSize(ctx, tag) + UIScale.round(14)
    if line_w > 0 and line_w + tag_w > max_w then
      line_w = 0
    elseif line_w > 0 then
      r.ImGui_SameLine(ctx)
    end
    draw_tag_chip(ctx, app, settings, tag, "available_" .. tostring(index), nil)
    line_w = line_w + tag_w + UIScale.gap(6)
  end
  draw_divider(ctx, width)
end

local function tag_chip_width(ctx, tag)
  return r.ImGui_CalcTextSize(ctx, tag) + UIScale.round(14)
end

local function draw_track_row(app, settings, item, width)
  local ctx = app.ctx
  r.ImGui_PushID(ctx, item.guid)
  local selected = r.IsTrackSelected and r.IsTrackSelected(item.track) or false
  local label = string.format("%02d  %s##track_atlas_row", item.index + 1, item.name)
  local row_x = r.ImGui_GetCursorPosX(ctx)
  local row_screen_x, row_screen_y = r.ImGui_GetCursorScreenPos(ctx)
  local gap = UIScale.gap(6)
  local min_track_w = math.min(width, math.max(UIScale.round(90), width * 0.32))
  local tag_total_w = 0
  for index, tag in ipairs(item.tags) do
    tag_total_w = tag_total_w + tag_chip_width(ctx, tag)
    if index > 1 then tag_total_w = tag_total_w + gap end
  end
  local tag_start = row_x + width - tag_total_w
  local track_w = width
  if #item.tags > 0 then
    tag_start = math.max(row_x + min_track_w + gap, tag_start)
    track_w = math.max(UIScale.round(40), tag_start - row_x - gap)
  end
  local row_selected = selected or item.matches_selected_tags
  if row_selected then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local row_h = math.max(UIScale.round(24), UIScale.button_h(ctx)) + UIScale.round(4)
    r.ImGui_DrawList_AddRectFilled(draw_list, row_screen_x, row_screen_y - UIScale.round(5), row_screen_x + width, row_screen_y + row_h, Theme.colors.accent_soft, 0)
  end
  if r.ImGui_Selectable(ctx, label, false, 0, track_w, UIScale.round(24)) then
    if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) then
      r.SetTrackSelected(item.track, not selected)
    else
      r.SetOnlyTrackSelected(item.track)
    end
    r.TrackList_AdjustWindows(false)
  end
  if r.ImGui_BeginPopupContextItem(ctx, "##track_atlas_track_context") then
    if r.ImGui_MenuItem(ctx, "Show all tracks") then show_all_tracks(app) end
    if r.ImGui_MenuItem(ctx, "Restore previous visibility") then restore_previous_visibility(app) end
    r.ImGui_EndPopup(ctx)
  end
  if #item.tags > 0 then
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, tag_start)
    for index, tag in ipairs(item.tags) do
      if index > 1 then r.ImGui_SameLine(ctx) end
      draw_tag_chip(ctx, app, settings, tag, tostring(item.guid) .. "_" .. tostring(index), item.guid)
    end
  else
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, math.max(row_x + UIScale.round(40), row_x + width - UIScale.round(48)))
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No tags")
  end
  draw_divider(ctx, width)
  r.ImGui_PopID(ctx)
end

function M.init(app)
  local settings = ensure_settings(app)
  load_store(settings, true)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  load_store(settings, false)
  local width, height = r.ImGui_GetContentRegionAvail(ctx)
  width = math.max(UIScale.round(140), width or UIScale.round(320))
  height = math.max(UIScale.round(120), (height or UIScale.round(320)) - UI.info_line_height(ctx))
  draw_toolbar(app, settings, width)
  draw_available_tags(app, settings, width)
  local selected_tags = normalize_selected_tags(settings)
  local filter_key = tostring(settings.search_term or "") .. "\31" .. table.concat(selected_tags, "\30") .. "\31" .. tostring(settings.show_empty_tracks)
  if filter_key ~= state.last_filter_key then
    collect_tracks(settings)
    state.last_filter_key = filter_key
  end
  if r.ImGui_BeginChild(ctx, "##track_atlas_tracks", 0, math.max(UIScale.round(40), height - UIScale.round(118)), 0) then
    for _, item in ipairs(state.filtered_tracks) do draw_track_row(app, settings, item, width - UIScale.round(10)) end
    if #state.filtered_tracks == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No tracks match") end
    r.ImGui_EndChild(ctx)
  end
  draw_remove_tag_confirm_popup(app, settings)
  local tag_count = #state.available_sorted
  UI.draw_info_line(ctx, "Tags | " .. state.store_label .. " | " .. tostring(tag_count) .. " tags | " .. tostring(#state.filtered_tracks) .. " tracks")
end

return M