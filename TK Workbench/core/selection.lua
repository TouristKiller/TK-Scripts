local r = reaper
local M = {}

local function file_name(path)
  if not path or path == "" then return "Untitled" end
  return path:match("([^\\/]+)$") or path
end

local function track_name(track)
  if not track then return nil end
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  return "Track"
end

local function active_take_name(item)
  if not item then return nil end
  local take = r.GetActiveTake(item)
  if not take then return nil end
  local ok, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if ok and name and name ~= "" then return name end
  return r.TakeIsMIDI(take) and "MIDI take" or "Audio take"
end

local function parent_path(path)
  if not path or path == "" then return "" end
  return path:match("^(.*)[\\/][^\\/]+$") or ""
end

local function project_string(project, key)
  local ok, _, value = pcall(r.GetSetProjectInfo_String, project, key, "", false)
  if ok and value and value ~= "" then return value end
  return ""
end

local function collect_track_stats()
  local stats = { muted = 0, solo = 0, armed = 0, folders = 0 }
  local track_count = r.CountTracks(0) or 0
  for index = 0, track_count - 1 do
    local track = r.GetTrack(0, index)
    if track then
      if (r.GetMediaTrackInfo_Value(track, "B_MUTE") or 0) > 0 then stats.muted = stats.muted + 1 end
      if (r.GetMediaTrackInfo_Value(track, "I_SOLO") or 0) > 0 then stats.solo = stats.solo + 1 end
      if (r.GetMediaTrackInfo_Value(track, "I_RECARM") or 0) > 0 then stats.armed = stats.armed + 1 end
      if (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0) > 0 then stats.folders = stats.folders + 1 end
    end
  end
  return stats
end

local function current_frame_rate(project)
  local ok, frame_rate, drop_frame = pcall(r.TimeMap_curFrameRate, project)
  if ok then return frame_rate or 0, drop_frame and true or false end
  return 0, false
end

function M.scan()
  local snapshot = {}
  local project, project_path = r.EnumProjects(-1, "")
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  local tempo, time_sig_num, time_sig_denom = r.GetProjectTimeSignature2(0)
  local frame_rate, drop_frame = current_frame_rate(project)
  local track_stats = collect_track_stats()
  local tempo_marker_count = r.CountTempoTimeSigMarkers(0) or 0
  local time_sel_start, time_sel_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local loop_start, loop_end = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
  local dirty_ok, dirty = pcall(r.IsProjectDirty, project)
  local sample_rate = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 0
  local project_start_time = r.GetSetProjectInfo(0, "PROJECT_START_TIME", 0, false) or 0

  snapshot.project = {
    pointer = project,
    path = project_path or "",
    name = file_name(project_path),
    directory = parent_path(project_path),
    dirty = dirty_ok and dirty and dirty ~= 0,
    length = r.GetProjectLength(0) or 0,
    start_time = project_start_time,
    tempo = tempo or r.Master_GetTempo() or 120,
    time_sig = math.floor((tonumber(time_sig_num) or 4) + 0.5),
    time_sig_denom = math.floor((tonumber(time_sig_denom) or 4) + 0.5),
    sample_rate = sample_rate,
    frame_rate = frame_rate,
    drop_frame = drop_frame,
    tracks = r.CountTracks(0) or 0,
    items = r.CountMediaItems(0) or 0,
    muted_tracks = track_stats.muted,
    solo_tracks = track_stats.solo,
    armed_tracks = track_stats.armed,
    folder_tracks = track_stats.folders,
    markers = marker_count or 0,
    regions = region_count or 0,
    tempo_markers = tempo_marker_count,
    cursor = r.GetCursorPosition() or 0,
    play_position = r.GetPlayPosition() or 0,
    play_state = r.GetPlayState() or 0,
    time_selection_start = time_sel_start or 0,
    time_selection_end = time_sel_end or 0,
    loop_start = loop_start or 0,
    loop_end = loop_end or 0,
    record_path = project_string(project, "RECORD_PATH")
  }

  local selected_track_count = r.CountSelectedTracks(0) or 0
  snapshot.selected_track_count = selected_track_count
  if selected_track_count > 0 then
    local track = r.GetSelectedTrack(0, 0)
    snapshot.track = {
      pointer = track,
      name = track_name(track),
      index = track and math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0) or 0
    }
  end

  local selected_item_count = r.CountSelectedMediaItems(0) or 0
  snapshot.selected_item_count = selected_item_count
  snapshot.selected_item_total_length = 0
  for index = 0, selected_item_count - 1 do
    local selected_item = r.GetSelectedMediaItem(0, index)
    if selected_item then snapshot.selected_item_total_length = snapshot.selected_item_total_length + (r.GetMediaItemInfo_Value(selected_item, "D_LENGTH") or 0) end
  end
  if selected_item_count > 0 then
    local item = r.GetSelectedMediaItem(0, 0)
    snapshot.item = {
      pointer = item,
      take_name = active_take_name(item),
      position = item and r.GetMediaItemInfo_Value(item, "D_POSITION") or 0,
      length = item and r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0
    }
  end

  return snapshot
end

return M