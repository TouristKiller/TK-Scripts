local r = reaper
local Chords = require("core.chord_engine")

local Timeline = {}
local cache = {}

local function number(value, fallback)
  value = tonumber(value)
  if value == nil then return fallback end
  return value
end

local function rounded(value)
  return string.format("%.9f", number(value, 0))
end

local function valid_track(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") == true end
  return true
end

local function track_guid(track)
  if not valid_track(track) or not r.GetTrackGUID then return nil end
  local ok, guid = pcall(r.GetTrackGUID, track)
  if not ok or not guid or guid == "" then return nil end
  return guid
end

local function find_track(guid)
  if not guid or guid == "" then return nil end
  if r.BR_GetMediaTrackByGUID then
    local track = r.BR_GetMediaTrackByGUID(0, guid)
    if valid_track(track) then return track end
  end
  for index = 0, (r.CountTracks and r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if track_guid(track) == guid then return track end
  end
  return nil
end

local function resolve_track(reference)
  if type(reference) == "string" then return find_track(reference) end
  if valid_track(reference) then return reference end
  return nil
end

local function take_guid(take)
  if not take or not r.GetSetMediaItemTakeInfo_String then return tostring(take or "") end
  local ok, guid = r.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
  return ok and tostring(guid or "") or tostring(take)
end

local function source_length_qn(take)
  if not r.GetMediaItemTake_Source or not r.GetMediaSourceLength then return 0 end
  local source = r.GetMediaItemTake_Source(take)
  if not source then return 0 end
  local length, is_qn = r.GetMediaSourceLength(source)
  length = number(length, 0)
  if is_qn == true or is_qn == 1 then return length end
  local start_qn = r.MIDI_GetProjQNFromPPQPos(take, 0)
  local end_ppq = r.MIDI_GetPPQPosFromProjTime(take, r.MIDI_GetProjTimeFromPPQPos(take, 0) + length)
  return r.MIDI_GetProjQNFromPPQPos(take, end_ppq) - start_qn
end

local function item_signature(item, take)
  local values = {
    tostring(item), take_guid(take),
    rounded(r.GetMediaItemInfo_Value(item, "D_POSITION")),
    rounded(r.GetMediaItemInfo_Value(item, "D_LENGTH")),
    rounded(r.GetMediaItemInfo_Value(item, "B_MUTE")),
    rounded(r.GetMediaItemInfo_Value(item, "C_LANEPLAYS")),
    rounded(r.GetMediaItemInfo_Value(item, "B_LOOPSRC")),
    rounded(r.GetMediaItemTakeInfo_Value(take, "D_PITCH")),
    rounded(r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")),
    rounded(r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS"))
  }
  return table.concat(values, ":")
end

local function track_signature(track)
  local parts = {}
  if r.MIDI_GetTrackHash then
    local ok, hash = r.MIDI_GetTrackHash(track, false, "")
    parts[#parts + 1] = ok and tostring(hash or "") or ""
  end
  local count = r.CountTrackMediaItems(track)
  parts[#parts + 1] = tostring(count)
  for index = 0, count - 1 do
    local item = r.GetTrackMediaItem(track, index)
    local take = item and r.GetActiveTake(item) or nil
    if take and r.TakeIsMIDI(take) then
      parts[#parts + 1] = item_signature(item, take)
    else
      parts[#parts + 1] = tostring(item)
    end
  end
  return table.concat(parts, "|")
end

local function option_signature(options)
  options = options or {}
  local chord_options = options.chord_options or {}
  return table.concat({
    rounded(options.minimum_duration or 0.05),
    rounded(options.attack_tolerance or 0),
    tostring(chord_options.prefer_flats == true),
    tostring(chord_options.include_bass ~= false),
    tostring(chord_options.allow_rootless == true),
    tostring(chord_options.root_hint or ""),
    tostring(chord_options.minimum_confidence or ""),
    tostring(chord_options.key_mode or "off"),
    tostring(chord_options.key_root or "")
  }, "|")
end

local function append_span(spans, pitch, start_time, stop_time)
  if stop_time <= start_time then return end
  spans[#spans + 1] = { pitch = pitch, start = start_time, stop = stop_time }
end

local function override_name(text)
  local key, value = tostring(text or ""):match("^%s*([^:]+)%s*:%s*(.-)%s*$")
  key = key and key:match("^%s*(.-)%s*$") or nil
  if not key or key:lower() ~= "chord" or value == "" then return nil end
  return value
end

local function append_override(overrides, name, start_time, stop_time)
  if not name or stop_time <= start_time then return end
  overrides[#overrides + 1] = { name = name, start = start_time, stop = stop_time }
end

local function read_take_content(item, take, spans, overrides)
  if r.GetMediaItemInfo_Value(item, "B_MUTE") == 1 then return end
  if r.GetMediaItemInfo_Value(item, "C_LANEPLAYS") <= 0 then return end
  local item_start = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local item_stop = item_start + r.GetMediaItemInfo_Value(item, "D_LENGTH")
  if item_stop <= item_start then return end
  local item_start_qn = r.TimeMap2_timeToQN(0, item_start)
  local item_stop_qn = r.TimeMap2_timeToQN(0, item_stop)
  local transpose = math.floor(number(r.GetMediaItemTakeInfo_Value(take, "D_PITCH"), 0) + 0.5)
  local looped = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") == 1
  local playrate = math.max(0.000001, number(r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE"), 1))
  local cycle_qn = looped and source_length_qn(take) / playrate or 0
  local repetitions = cycle_qn > 0 and math.max(1, math.ceil((item_stop_qn - item_start_qn) / cycle_qn) + 1) or 1
  local _, note_count, _, text_count = r.MIDI_CountEvts(take)
  local text_events = {}
  if r.MIDI_GetTextSysexEvt then
    for text_index = 0, text_count - 1 do
      local ok, _, muted, ppq, _, text = r.MIDI_GetTextSysexEvt(take, text_index)
      local name = ok and not muted and override_name(text) or nil
      if name then text_events[#text_events + 1] = { ppq = ppq, name = name } end
    end
    table.sort(text_events, function(left, right) return left.ppq < right.ppq end)
  end
  for repetition = 0, repetitions - 1 do
    local shift_qn = repetition * cycle_qn
    for note_index = 0, note_count - 1 do
      local ok, _, muted, start_ppq, stop_ppq, _, pitch = r.MIDI_GetNote(take, note_index)
      if ok and not muted then
        local start_qn = r.MIDI_GetProjQNFromPPQPos(take, start_ppq) + shift_qn
        local stop_qn = r.MIDI_GetProjQNFromPPQPos(take, stop_ppq) + shift_qn
        start_qn = math.max(item_start_qn, start_qn)
        stop_qn = math.min(item_stop_qn, stop_qn)
        if stop_qn > start_qn then
          append_span(spans, pitch + transpose,
            r.TimeMap2_QNToTime(0, start_qn), r.TimeMap2_QNToTime(0, stop_qn))
        end
      end
    end
    for text_index, event in ipairs(text_events) do
      local start_qn = r.MIDI_GetProjQNFromPPQPos(take, event.ppq) + shift_qn
      local next_event = text_events[text_index + 1]
      local stop_qn = next_event and (r.MIDI_GetProjQNFromPPQPos(take, next_event.ppq) + shift_qn)
        or (cycle_qn > 0 and (r.MIDI_GetProjQNFromPPQPos(take, 0) + shift_qn + cycle_qn) or item_stop_qn)
      start_qn = math.max(item_start_qn, start_qn)
      stop_qn = math.min(item_stop_qn, stop_qn)
      if stop_qn > start_qn then
        append_override(overrides, event.name,
          r.TimeMap2_QNToTime(0, start_qn), r.TimeMap2_QNToTime(0, stop_qn))
      end
    end
  end
end

local function collect_content(track)
  local spans, overrides = {}, {}
  for index = 0, r.CountTrackMediaItems(track) - 1 do
    local item = r.GetTrackMediaItem(track, index)
    local take = item and r.GetActiveTake(item) or nil
    if take and r.TakeIsMIDI(take) then read_take_content(item, take, spans, overrides) end
  end
  table.sort(spans, function(left, right)
    if left.start ~= right.start then return left.start < right.start end
    if left.stop ~= right.stop then return left.stop < right.stop end
    return left.pitch < right.pitch
  end)
  table.sort(overrides, function(left, right)
    if left.start ~= right.start then return left.start < right.start end
    return left.stop < right.stop
  end)
  return spans, overrides
end

local function unique_points(spans, overrides)
  local points, seen = {}, {}
  for _, entries in ipairs({ spans or {}, overrides or {} }) do
    for _, entry in ipairs(entries) do
      for _, value in ipairs({ entry.start, entry.stop }) do
      local key = rounded(value)
      if not seen[key] then
        seen[key] = true
        points[#points + 1] = value
      end
      end
    end
  end
  table.sort(points)
  return points
end

local function active_pitches(spans, start_time, stop_time)
  local pitches = {}
  for _, span in ipairs(spans) do
    if span.start < stop_time and span.stop > start_time then pitches[#pitches + 1] = span.pitch end
  end
  return pitches
end

local function clustered_spans(spans, tolerance)
  tolerance = math.max(0, number(tolerance, 0))
  if tolerance == 0 then return spans or {} end
  local ordered = {}
  for _, span in ipairs(spans or {}) do
    ordered[#ordered + 1] = { pitch = span.pitch, start = span.start, stop = span.stop }
  end
  table.sort(ordered, function(left, right)
    if left.start ~= right.start then return left.start < right.start end
    return left.pitch < right.pitch
  end)
  local cluster_start = nil
  for _, span in ipairs(ordered) do
    if cluster_start == nil or span.start - cluster_start > tolerance then cluster_start = span.start end
    span.start = cluster_start
  end
  return ordered
end

local function inferred_key(spans)
  local duration = {}
  for class = 0, 11 do duration[class] = 0 end
  for _, span in ipairs(spans or {}) do
    local class = span.pitch % 12
    duration[class] = duration[class] + math.max(0, span.stop - span.start)
  end
  local best_root, best_mode, best_score = 0, "major", -math.huge
  for root = 0, 11 do
    for _, mode in ipairs({ "major", "minor" }) do
      local scale = mode == "major" and { 0, 2, 4, 5, 7, 9, 11 } or { 0, 2, 3, 5, 7, 8, 10 }
      local present, score = {}, 0
      for _, interval in ipairs(scale) do present[(root + interval) % 12] = true end
      for class = 0, 11 do
        score = score + duration[class] * (present[class] and 1 or -2)
      end
      score = score + duration[root] * 0.1 + duration[(root + 7) % 12] * 0.05
      if score > best_score then best_root, best_mode, best_score = root, mode, score end
    end
  end
  return best_root, best_mode
end

local function same_chord(left, right)
  return left and right and left.name == right.name and left.root == right.root and left.bass == right.bass
    and left.manual == right.manual
end

local function manual_chord(overrides, start_time, stop_time)
  local selected = nil
  for _, entry in ipairs(overrides or {}) do
    if entry.start <= start_time and entry.stop >= stop_time then selected = entry end
  end
  if not selected then return nil end
  return {
    name = selected.name,
    quality = "manual",
    confidence = 1,
    exact = true,
    manual = true,
    missing = 0,
    extra = 0
  }
end

function Timeline.compose(spans, options, overrides)
  options = options or {}
  local minimum_duration = math.max(0, number(options.minimum_duration, 0.05))
  local prepared_spans = clustered_spans(spans, options.attack_tolerance)
  local chord_options = {}
  for key, value in pairs(options.chord_options or {}) do chord_options[key] = value end
  if chord_options.key_mode == "auto" then
    chord_options.key_root, chord_options.key_mode = inferred_key(prepared_spans)
  end
  local points = unique_points(prepared_spans, overrides)
  local events = {}
  for index = 1, #points - 1 do
    local start_time, stop_time = points[index], points[index + 1]
    if stop_time - start_time >= minimum_duration then
      local chord = manual_chord(overrides, start_time, stop_time)
        or Chords.resolve(active_pitches(prepared_spans, start_time, stop_time), chord_options)
      if chord then
        local previous = events[#events]
        if previous and same_chord(previous, chord) and math.abs(previous.stop - start_time) < 0.000001 then
          previous.stop = stop_time
        else
          chord.start = start_time
          chord.stop = stop_time
          events[#events + 1] = chord
        end
      end
    end
  end
  for index, event in ipairs(events) do event.index = index end
  return events
end

function Timeline.build(reference, options, force)
  local track = resolve_track(reference)
  if not track then return {}, "track_not_found" end
  local guid = track_guid(track) or tostring(track)
  local project = r.EnumProjects and r.EnumProjects(-1, "") or 0
  local signature = track_signature(track) .. "|" .. option_signature(options)
  local stored = cache[guid]
  if not force and stored and stored.project == project and stored.signature == signature then
    return stored.events
  end
  local spans, overrides = collect_content(track)
  local events = Timeline.compose(spans, options, overrides)
  cache[guid] = { project = project, signature = signature, events = events }
  return events
end

function Timeline.at(events, position)
  position = number(position, 0)
  local current, next_event = nil, nil
  for _, event in ipairs(events or {}) do
    if position >= event.start and position < event.stop then current = event end
    if event.start > position then
      next_event = event
      break
    end
  end
  return current, next_event
end

function Timeline.track(reference)
  return resolve_track(reference)
end

function Timeline.invalidate(reference)
  if reference == nil then
    cache = {}
    return
  end
  local track = resolve_track(reference)
  local guid = track and track_guid(track) or tostring(reference)
  cache[guid] = nil
end

return Timeline