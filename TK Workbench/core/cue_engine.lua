-- Cue engine: answers one question per frame - where are we in the song, what
-- comes next, and how long until it gets here.
--
-- No ImGui, no app table, no drawing. The module paints what this returns and
-- does no time arithmetic of its own: if the screen shows the wrong bar, the
-- fault is in here, where a test can reproduce it without REAPER being open.

local r = reaper

local Engine = {}

local DEFAULT_WARN_BARS = 2

--------------------------------------------------------------------------------
-- sections
--------------------------------------------------------------------------------

-- Regions are what a section is: they have a start and an end, so "how far into
-- the chorus" means something. A project that only has markers still gets
-- sections, each running until the next marker - that is what a marker means to
-- someone laying out a song, even though REAPER does not say so.
local function collect_regions()
  local sections = {}
  local index = 0
  while true do
    local ok, is_region, pos, stop, name, _, color = r.EnumProjectMarkers3(0, index)
    if not ok or ok == 0 then break end
    if is_region then
      sections[#sections + 1] = {
        name = tostring(name or ""),
        start = pos,
        stop = stop,
        color = color,
        is_region = true
      }
    end
    index = index + 1
  end
  return sections
end

local function collect_markers()
  local points = {}
  local index = 0
  while true do
    local ok, is_region, pos, _, name, _, color = r.EnumProjectMarkers3(0, index)
    if not ok or ok == 0 then break end
    if not is_region then
      points[#points + 1] = { name = tostring(name or ""), start = pos, color = color }
    end
    index = index + 1
  end
  table.sort(points, function(a, b) return a.start < b.start end)
  local length = r.GetProjectLength and r.GetProjectLength(0) or 0
  local sections = {}
  for i, point in ipairs(points) do
    local stop = points[i + 1] and points[i + 1].start or math.max(length, point.start)
    sections[#sections + 1] = {
      name = point.name,
      start = point.start,
      stop = stop,
      color = point.color,
      is_region = false
    }
  end
  return sections
end

-- Rebuilt only when the project actually changed. Walking every marker on every
-- frame is cheap on a demo and not cheap on a set list, and this runs at frame
-- rate for as long as the panel is open.
local cache = { stamp = nil, project = nil, sections = nil }

local function project_stamp()
  if r.GetProjectStateChangeCount then return r.GetProjectStateChangeCount(0) end
  return nil
end

function Engine.sections(force)
  local stamp = project_stamp()
  local project = r.EnumProjects and r.EnumProjects(-1, "") or nil
  if not force and cache.sections and cache.stamp == stamp and cache.project == project then
    return cache.sections
  end
  local sections = collect_regions()
  if #sections == 0 then sections = collect_markers() end
  table.sort(sections, function(a, b)
    if a.start ~= b.start then return a.start < b.start end
    return a.stop < b.stop
  end)
  for i, section in ipairs(sections) do section.index = i end
  cache.stamp, cache.project, cache.sections = stamp, project, sections
  return sections
end

function Engine.invalidate()
  cache.stamp, cache.project, cache.sections = nil, nil, nil
end

-- The innermost section wins when regions are nested, which is the one that
-- started last. Someone who puts a "Solo" region inside "Chorus 2" means the
-- solo, or they would not have drawn it.
local function locate(sections, position)
  local current, next_one
  for _, section in ipairs(sections) do
    if position >= section.start and position < section.stop then
      if not current or section.start > current.start then current = section end
    end
    if section.start > position then
      if not next_one or section.start < next_one.start then next_one = section end
    end
  end
  return current, next_one
end

--------------------------------------------------------------------------------
-- the tempo map
--------------------------------------------------------------------------------

-- A position expressed in measures, fraction included. Measures are not all the
-- same length once a time signature changes, so counting seconds or beats and
-- dividing would drift; this counts whole measures and adds how far into the
-- current one we are, which stays true across a 4/4 to 6/8 change.
local function measure_position(time)
  local beats, measures, cml = r.TimeMap2_timeToBeats(0, time)
  beats = tonumber(beats) or 0
  measures = tonumber(measures) or 0
  cml = tonumber(cml) or 0
  if cml <= 0 then return measures end
  return measures + beats / cml
end

-- Returns num, denom, tempo. TimeMap_GetTimeSigAtTime hands those back with no
-- leading retval, unlike most of the API - assuming one shifts the tempo into
-- the denominator, which is a bug you only notice when a project is in 6/8.
local function signature_at(time)
  local num, denom, tempo = r.TimeMap_GetTimeSigAtTime(0, time)
  return tonumber(num) or 4, tonumber(denom) or 4, tonumber(tempo) or 0
end

-- The first tempo or time signature marker after this position, and whether it
-- actually changes anything: REAPER's tempo map is full of markers that only
-- restate what was already true, and announcing those would cry wolf.
local function next_change(position, tempo_now, num_now, denom_now)
  if not r.EnumTempoTimeSigMarkers then return nil end
  local index = 0
  while true do
    local ok, time, _, _, bpm, num, denom = r.EnumTempoTimeSigMarkers(0, index)
    if not ok or ok == 0 then break end
    if time and time > position then
      bpm = tonumber(bpm) or 0
      num = tonumber(num) or 0
      denom = tonumber(denom) or 0
      -- A marker can carry a tempo without carrying a signature: zeroes mean
      -- "unchanged", not "0/0".
      if num == 0 then num = num_now end
      if denom == 0 then denom = denom_now end
      local tempo_changes = bpm > 0 and math.abs(bpm - tempo_now) > 0.0001
      local sig_changes = num ~= num_now or denom ~= denom_now
      if tempo_changes or sig_changes then
        return {
          time = time,
          tempo = bpm > 0 and bpm or tempo_now,
          timesig_num = num,
          timesig_den = denom,
          tempo_changes = tempo_changes,
          timesig_changes = sig_changes
        }
      end
    end
    index = index + 1
  end
  return nil
end

-- Both directions between time and measures, for whoever needs to say "two bars
-- before that" and turn it back into a moment. Exposed because the audio side
-- schedules on bar lines and must not do this arithmetic a second way.
function Engine.measure_of(time)
  return measure_position(tonumber(time) or 0)
end

function Engine.time_of_measure(measure)
  measure = math.floor(tonumber(measure) or 0)
  if measure < 0 then measure = 0 end
  if not r.TimeMap2_beatsToTime then return nil end
  return r.TimeMap2_beatsToTime(0, 0.0, measure)
end

--------------------------------------------------------------------------------
-- reading the state
--------------------------------------------------------------------------------

local function play_state()
  local flags = r.GetPlayState and r.GetPlayState() or 0
  local playing = flags & 1 == 1
  local recording = flags & 4 == 4
  local paused = flags & 2 == 2
  return playing, recording, paused
end

-- Stopped, the edit cursor is what you are looking at: someone setting the cues
-- up drags the cursor into the chorus to see what the chorus will look like.
local function current_position(playing, recording)
  if (playing or recording) and r.GetPlayPosition then return r.GetPlayPosition() end
  return r.GetCursorPosition and r.GetCursorPosition() or 0
end

-- opts: warn_bars (default 2)
-- previous: the state from the last call, so entering a section can be reported
-- once instead of being worked out again by every caller that cares.
function Engine.read(opts, previous)
  opts = opts or {}
  local warn_bars = tonumber(opts.warn_bars) or DEFAULT_WARN_BARS
  if warn_bars < 0 then warn_bars = 0 end

  local playing, recording, paused = play_state()
  local position = tonumber(opts.position) or current_position(playing, recording)
  local sections = Engine.sections()
  local section, next_section = locate(sections, position)

  local beats, measures, cml, _, cdenom = r.TimeMap2_timeToBeats(0, position)
  beats = tonumber(beats) or 0
  local num, denom, tempo = signature_at(position)
  local beats_per_bar = tonumber(cml) or num

  local state = {
    position = position,
    playing = playing,
    recording = recording,
    paused = paused,
    sections = sections,
    section = section,
    next_section = next_section,
    section_index = section and section.index or nil,
    section_count = #sections,
    bar = (tonumber(measures) or 0) + 1,
    beat = math.floor(beats) + 1,
    beat_fraction = beats % 1,
    beats_per_bar = beats_per_bar,
    tempo = tempo,
    timesig_num = num,
    timesig_den = tonumber(cdenom) or denom,
    warn_bars = warn_bars
  }

  -- How far into the section we are, and how much of it is left. Both in
  -- measures, because that is the unit a musician counts in.
  local here = measure_position(position)
  if section then
    state.bars_into_section = here - measure_position(section.start)
    state.bars_left_in_section = measure_position(section.stop) - here
  end
  if next_section then
    state.bars_to_change = measure_position(next_section.start) - here
  elseif section then
    -- No section after this one, but the section itself still ends. Running out
    -- of song is worth counting down to as well.
    state.bars_to_change = state.bars_left_in_section
  end

  state.next_change = next_change(position, tempo, num, state.timesig_den)
  if state.next_change then
    state.bars_to_next_change = measure_position(state.next_change.time) - here
  end

  -- run -> warn -> last_bar, the three things the screen has to say without
  -- being read. A change that has just happened reports as "go" for one call,
  -- which is what a flash on the wall hangs off.
  local previous_name = previous and previous.section and previous.section.name
  local name = section and section.name
  state.entered = previous ~= nil and previous_name ~= name
  state.stage = Engine.stage(state, warn_bars)

  return state
end

-- Kept separate so a section can carry its own warning distance without the
-- whole state having to be read again: the module knows which section it is in
-- only after this has answered, which is one step too late to have passed the
-- right number in.
function Engine.stage(state, warn_bars)
  if not state then return "run" end
  if state.entered and state.section then return "go" end
  warn_bars = tonumber(warn_bars) or DEFAULT_WARN_BARS
  local left = state.bars_to_change
  if not left then return "run" end
  if left <= 1 then return "last_bar" end
  if left <= warn_bars then return "warn" end
  return "run"
end

return Engine
