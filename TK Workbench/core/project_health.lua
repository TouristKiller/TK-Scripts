local r = reaper

local M = {}

local CUE_TRACK_EXT_KEY = "P_EXT:TK_CONTROL_ROOM_CUE"
local HIGH_PDC_SAMPLES = 2048
local HOT_PEAK = 10 ^ (-1 / 20)

local function normalize_path(path)
  if not path or path == "" then return "" end
  path = tostring(path):gsub("/", "\\"):gsub("\\+", "\\"):lower()
  if path:sub(-1) == "\\" then path = path:sub(1, -2) end
  return path
end

local function path_is_under(path, root)
  path = normalize_path(path)
  root = normalize_path(root)
  if path == "" or root == "" then return false end
  return path == root or path:sub(1, #root + 1) == root .. "\\"
end

local function file_exists(path)
  if not path or path == "" then return false end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function valid_track(track)
  return track and (not r.ValidatePtr2 or r.ValidatePtr2(0, track, "MediaTrack*"))
end

local function valid_item(item)
  return item and (not r.ValidatePtr2 or r.ValidatePtr2(0, item, "MediaItem*"))
end

local function track_guid(track)
  if not valid_track(track) or not r.GetTrackGUID then return nil end
  local ok, guid = pcall(r.GetTrackGUID, track)
  return ok and guid and guid ~= "" and guid or nil
end

local function track_by_guid(guid)
  if not guid or guid == "" or not r.CountTracks then return nil end
  local count = r.CountTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetTrack(0, index)
    if track_guid(track) == guid then return track end
  end
  return nil
end

local function cue_guid_lookup(settings)
  local lookup = {}
  for _, record in ipairs(type(settings and settings.cue_outputs) == "table" and settings.cue_outputs or {}) do
    if record.guid then lookup[record.guid] = true end
  end
  return lookup
end

local function cue_track_marked(track)
  if not valid_track(track) or not r.GetSetMediaTrackInfo_String then return false end
  local ok, _, value = pcall(r.GetSetMediaTrackInfo_String, track, CUE_TRACK_EXT_KEY, "", false)
  return ok and tostring(value or "") == "1"
end

local function issue(list, severity, category, title, detail, count, action_label, action, repair_label, repair)
  list[#list + 1] = {
    severity = severity,
    category = category,
    title = title,
    detail = detail,
    count = count or 0,
    action_label = action_label,
    action = action,
    repair_label = repair_label,
    repair = repair
  }
end

local function with_undo(label, callback)
  return function()
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local ok, result = pcall(callback)
    r.PreventUIRefresh(-1)
    if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
    r.UpdateArrange()
    r.Undo_EndBlock(label, -1)
    if not ok then error(result) end
    return result
  end
end

local function select_tracks(tracks)
  return function()
    r.Main_OnCommand(40297, 0)
    for _, track in ipairs(tracks or {}) do
      if valid_track(track) then r.SetTrackSelected(track, true) end
    end
    r.UpdateArrange()
  end
end

local function select_items(items)
  return function()
    r.Main_OnCommand(40289, 0)
    for _, item in ipairs(items or {}) do
      if valid_item(item) then r.SetMediaItemSelected(item, true) end
    end
    r.UpdateArrange()
  end
end

local function project_settings_action()
  return function() r.Main_OnCommand(40021, 0) end
end

local function save_project_action()
  return function() r.Main_OnCommand(40026, 0) end
end

local function disarm_tracks(tracks)
  return with_undo("Disarm health tracks", function()
    for _, track in ipairs(tracks or {}) do
      if valid_track(track) then r.SetMediaTrackInfo_Value(track, "I_RECARM", 0) end
    end
  end)
end

local function enable_master_send(tracks)
  return with_undo("Enable master send", function()
    for _, track in ipairs(tracks or {}) do
      if valid_track(track) and not cue_track_marked(track) then r.SetMediaTrackInfo_Value(track, "B_MAINSEND", 1) end
    end
  end)
end

local function disable_master_send(tracks)
  return with_undo("Disable cue master send", function()
    for _, track in ipairs(tracks or {}) do
      if valid_track(track) and cue_track_marked(track) then r.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0) end
    end
  end)
end

local function show_tracks(tracks)
  return with_undo("Show health tracks", function()
    for _, track in ipairs(tracks or {}) do
      if valid_track(track) then
        r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
        r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 1)
      end
    end
  end)
end

local function scan_media(issues, project)
  local missing_items = {}
  local external_items = {}
  local seen_paths = {}
  local seen_external_paths = {}
  local missing_paths = 0
  local external_paths = 0
  local project_dir = project and project.directory or ""
  local item_count = r.CountMediaItems(0) or 0
  for item_index = 0, item_count - 1 do
    local item = r.GetMediaItem(0, item_index)
    local take_count = item and (r.CountTakes(item) or 0) or 0
    for take_index = 0, take_count - 1 do
      local take = r.GetTake(item, take_index)
      if take and not r.TakeIsMIDI(take) then
        local source = r.GetMediaItemTake_Source(take)
        local ok, path = source and pcall(r.GetMediaSourceFileName, source, "")
        if ok and path and path ~= "" and path:sub(1, 1) ~= "<" then
          if not file_exists(path) then
            missing_items[#missing_items + 1] = item
            if not seen_paths[path] then
              seen_paths[path] = true
              missing_paths = missing_paths + 1
            end
            break
          elseif project_dir ~= "" and not path_is_under(path, project_dir) then
            external_items[#external_items + 1] = item
            if not seen_external_paths[path] then
              seen_external_paths[path] = true
              external_paths = external_paths + 1
            end
            break
          end
        end
      end
    end
  end
  if #missing_items > 0 then
    issue(issues, "critical", "Media", "Missing media", tostring(missing_paths) .. " missing files in " .. tostring(#missing_items) .. " items", #missing_items, "Select", select_items(missing_items))
  end
  if #external_items > 0 then
    issue(issues, "warning", "Media", "External media", tostring(external_paths) .. " files are outside the project folder", #external_items, "Select", select_items(external_items))
  end
end

local function scan_master(issues)
  local master = r.GetMasterTrack and r.GetMasterTrack(0) or nil
  if not master or not r.Track_GetPeakInfo then return end
  local peak = math.max(math.abs(r.Track_GetPeakInfo(master, 0) or 0), math.abs(r.Track_GetPeakInfo(master, 1) or 0))
  if peak >= 1 then
    issue(issues, "critical", "Levels", "Master clipping", "Master peak is at or above 0 dBFS", 1)
  elseif peak >= HOT_PEAK then
    issue(issues, "warning", "Levels", "Master hot", "Master peak is above -1 dBFS", 1)
  end
end

local function track_has_output(track)
  if (r.GetMediaTrackInfo_Value(track, "B_MAINSEND") or 0) > 0 then return true end
  if r.GetTrackNumSends and (r.GetTrackNumSends(track, 0) or 0) > 0 then return true end
  if r.GetTrackNumSends and (r.GetTrackNumSends(track, 1) or 0) > 0 then return true end
  return false
end

local function scan_tracks(issues, control_room_settings)
  local muted = {}
  local hidden = {}
  local clipped = {}
  local hot = {}
  local armed = {}
  local no_output = {}
  local repairable_no_output = {}
  local high_pdc = {}
  local orphan_cue_tracks = {}
  local cue_main_send = {}
  local cue_no_output = {}
  local missing_cue_records = 0
  local managed_cues = cue_guid_lookup(control_room_settings)
  local track_count = r.CountTracks(0) or 0
  for index = 0, track_count - 1 do
    local track = r.GetTrack(0, index)
    if track then
      if (r.GetMediaTrackInfo_Value(track, "B_MUTE") or 0) > 0 then muted[#muted + 1] = track end
      if (r.GetMediaTrackInfo_Value(track, "I_RECARM") or 0) > 0 then armed[#armed + 1] = track end
      local show_tcp = (r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") or 0) > 0
      local show_mixer = (r.GetMediaTrackInfo_Value(track, "B_SHOWINMIXER") or 0) > 0
      if not show_tcp and not show_mixer then hidden[#hidden + 1] = track end
      local marked_cue = cue_track_marked(track)
      if marked_cue and r.GetTrackNumSends and (r.GetTrackNumSends(track, 1) or 0) == 0 then cue_no_output[#cue_no_output + 1] = track end
      if not track_has_output(track) then
        if not marked_cue then
          no_output[#no_output + 1] = track
          if (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0) == 0 then repairable_no_output[#repairable_no_output + 1] = track end
        end
      end
      local peak = math.max(math.abs(r.Track_GetPeakInfo(track, 0) or 0), math.abs(r.Track_GetPeakInfo(track, 1) or 0))
      if peak >= 1 then clipped[#clipped + 1] = track elseif peak >= HOT_PEAK then hot[#hot + 1] = track end
      local fx_count = r.TrackFX_GetCount and (r.TrackFX_GetCount(track) or 0) or 0
      for fx_index = 0, fx_count - 1 do
        local latency = r.TrackFX_GetLatency and (r.TrackFX_GetLatency(track, fx_index) or 0) or 0
        if latency >= HIGH_PDC_SAMPLES then
          high_pdc[#high_pdc + 1] = track
          break
        end
      end
      local guid = track_guid(track)
      if marked_cue and (r.GetMediaTrackInfo_Value(track, "B_MAINSEND") or 0) > 0 then cue_main_send[#cue_main_send + 1] = track end
      if marked_cue and (not guid or not managed_cues[guid]) then orphan_cue_tracks[#orphan_cue_tracks + 1] = track end
    end
  end
  for _, record in ipairs(type(control_room_settings and control_room_settings.cue_outputs) == "table" and control_room_settings.cue_outputs or {}) do
    if record.guid and not track_by_guid(record.guid) then missing_cue_records = missing_cue_records + 1 end
  end
  if #muted > 0 then issue(issues, "info", "Tracks", "Muted tracks", tostring(#muted) .. " tracks are muted", #muted, "Select", select_tracks(muted)) end
  if #armed > 0 then issue(issues, "warning", "Tracks", "Armed tracks", tostring(#armed) .. " tracks are record-armed", #armed, "Select", select_tracks(armed), "Disarm", disarm_tracks(armed)) end
  if #hidden > 0 then issue(issues, "info", "Tracks", "Hidden tracks", tostring(#hidden) .. " tracks are hidden in TCP and mixer", #hidden, "Select", select_tracks(hidden), "Show", show_tracks(hidden)) end
  if #clipped > 0 then issue(issues, "critical", "Levels", "Clipping tracks", tostring(#clipped) .. " tracks are at or above 0 dBFS", #clipped, "Select", select_tracks(clipped)) end
  if #hot > 0 then issue(issues, "warning", "Levels", "Hot track peaks", tostring(#hot) .. " tracks are above -1 dBFS", #hot, "Select", select_tracks(hot)) end
  if #no_output > 0 then issue(issues, "warning", "Routing", "Tracks without output", tostring(#no_output) .. " tracks have no master, send, or hardware output", #no_output, "Select", select_tracks(no_output), #repairable_no_output > 0 and "Enable Send" or nil, #repairable_no_output > 0 and enable_master_send(repairable_no_output) or nil) end
  if #high_pdc > 0 then issue(issues, "warning", "FX", "High FX latency", tostring(#high_pdc) .. " tracks have FX latency above " .. tostring(HIGH_PDC_SAMPLES) .. " samples", #high_pdc, "Select", select_tracks(high_pdc)) end
  if #cue_no_output > 0 then issue(issues, "warning", "Control Room", "Cue tracks without output", tostring(#cue_no_output) .. " cue tracks have no hardware output", #cue_no_output, "Select", select_tracks(cue_no_output)) end
  if #cue_main_send > 0 then issue(issues, "warning", "Control Room", "Cue main send enabled", tostring(#cue_main_send) .. " cue tracks still send to master", #cue_main_send, "Select", select_tracks(cue_main_send), "Disable Main", disable_master_send(cue_main_send)) end
  if #orphan_cue_tracks > 0 then issue(issues, "warning", "Control Room", "Orphan cue tracks", tostring(#orphan_cue_tracks) .. " cue tracks are no longer in Control Room settings", #orphan_cue_tracks, "Select", select_tracks(orphan_cue_tracks)) end
  if missing_cue_records > 0 then issue(issues, "warning", "Control Room", "Missing cue tracks", tostring(missing_cue_records) .. " Control Room cue records point to missing tracks", missing_cue_records) end
end

local function scan_project(issues, project)
  project = project or {}
  if project.dirty then issue(issues, "warning", "Project", "Unsaved changes", "Project has unsaved changes", 1, "Save", save_project_action()) end
  if not project.path or project.path == "" then issue(issues, "warning", "Project", "Project not saved", "Save the project to establish a project folder", 1, "Save As", function() r.Main_OnCommand(40022, 0) end) end
  local sample_rate = tonumber(project.sample_rate) or 0
  local detail = sample_rate > 0 and (tostring(math.floor(sample_rate + 0.5)) .. " Hz") or "Using audio device/project default"
  issue(issues, "info", "Project", "Sample rate", detail, 0, "Settings", project_settings_action())
end

local function summarize(issues)
  local summary = { critical = 0, warning = 0, info = 0 }
  for _, entry in ipairs(issues or {}) do
    if entry.severity == "critical" then summary.critical = summary.critical + 1 elseif entry.severity == "warning" then summary.warning = summary.warning + 1 else summary.info = summary.info + 1 end
  end
  return summary
end

function M.scan(project, control_room_settings)
  local issues = {}
  scan_project(issues, project)
  scan_master(issues)
  scan_tracks(issues, control_room_settings)
  scan_media(issues, project)
  table.sort(issues, function(left, right)
    local order = { critical = 1, warning = 2, info = 3 }
    return (order[left.severity] or 4) < (order[right.severity] or 4)
  end)
  return {
    issues = issues,
    summary = summarize(issues),
    scanned_at = r.time_precise and r.time_precise() or os.clock(),
    state_count = r.GetProjectStateChangeCount and (r.GetProjectStateChangeCount(0) or 0) or 0
  }
end

return M
