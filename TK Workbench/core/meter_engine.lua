local r = reaper

local M = {}

local fx_cache = {}
local info_cache = {}
local source_uses_engine

M.plugin_name = "JS: TK Control Room Meter"
M.plugin_match = "TK Control Room Meter"
M.plugin_names = {
  "JS: TK Control Room Meter",
  "JS: TK Scripts/Mixer/TK_Control_Room_Meter.jsfx",
  "JS: TK_Control_Room_Meter"
}

M.default_display_items = { "momentary", "short_term", "integrated", "target_delta", "estimated_true_peak", "headroom" }
M.default_target_lufs = -14
M.max_display_items = 6

M.available_items = {
  { id = "momentary", label = "Momentary" },
  { id = "momentary_max", label = "Momentary Max" },
  { id = "short_term", label = "Short-Term" },
  { id = "integrated", label = "Integrated" },
  { id = "range", label = "Range" },
  { id = "estimated_true_peak", label = "Est. True Peak" },
  { id = "sample_peak", label = "Sample Peak" },
  { id = "time", label = "Time" },
  { id = "headroom", label = "Headroom" },
  { id = "target_delta", label = "Target Delta" },
  { id = "plr", label = "PLR" },
  { id = "isp_delta", label = "ISP Delta" }
}

M.sliders = {
  momentary_max = { index = 4, min = -100, max = 12 },
  short_term = { index = 5, min = -100, max = 12 },
  integrated = { index = 6, min = -100, max = 12 },
  range = { index = 7, min = 0, max = 60 },
  true_peak = { index = 8, min = -100, max = 12 },
  time = { index = 9, min = 0, max = 86400 },
  momentary = { index = 10, min = -100, max = 12 },
  sample_peak = { index = 11, min = -100, max = 12 }
}

local function valid_track(track)
  return track and r.ValidatePtr2(0, track, "MediaTrack*") == true
end

local function track_guid(track)
  if not valid_track(track) or not r.GetTrackGUID then return "" end
  local ok, guid = pcall(r.GetTrackGUID, track)
  return ok and guid or ""
end

local function fx_name_matches(name)
  name = tostring(name or "")
  return name:find(M.plugin_match, 1, true) ~= nil
end

local function cache_key(track)
  local guid = track_guid(track)
  return guid ~= "" and guid or nil
end

local function valid_cached_fx(track, fx_index)
  if not valid_track(track) or not fx_index or not r.TrackFX_GetCount or not r.TrackFX_GetFXName then return false end
  local count = r.TrackFX_GetCount(track) or 0
  if fx_index < 0 or fx_index >= count then return false end
  local ok, name = r.TrackFX_GetFXName(track, fx_index, "")
  return ok and fx_name_matches(name)
end

local function remember_fx(track, fx_index)
  local key = cache_key(track)
  if key and fx_index then fx_cache[key] = fx_index end
end

local function cached_fx(track)
  local key = cache_key(track)
  if not key then return nil end
  local fx_index = fx_cache[key]
  if valid_cached_fx(track, fx_index) then return fx_index end
  fx_cache[key] = nil
  return nil
end

local function now()
  return r.time_precise and r.time_precise() or os.clock()
end

local function source_key(source)
  if not source then return "none" end
  return tostring(source.id or "none") .. ":" .. tostring(track_guid(source.track))
end

function M.find_meter_fx(track)
  if not valid_track(track) or not r.TrackFX_GetCount or not r.TrackFX_GetFXName then return nil end
  local cached = cached_fx(track)
  if cached then return cached end
  local count = r.TrackFX_GetCount(track) or 0
  for index = 0, count - 1 do
    local ok, name = r.TrackFX_GetFXName(track, index, "")
    if ok and fx_name_matches(name) then
      remember_fx(track, index)
      return index
    end
  end
  return nil
end

function M.ensure_meter_fx(track, auto_install)
  if not valid_track(track) then return nil, "No valid meter track" end
  local existing = M.find_meter_fx(track)
  if existing then return existing, nil end
  if not auto_install or not r.TrackFX_AddByName then return nil, "Meter FX not installed" end
  for _, name in ipairs(M.plugin_names) do
    local index = r.TrackFX_AddByName(track, name, false, -1)
    if index and index >= 0 then
      remember_fx(track, index)
      return index, nil
    end
  end
  return nil, "Meter JSFX not found"
end

function M.reset(track, options)
  options = type(options) == "table" and options or {}
  local fx_index, status = M.ensure_meter_fx(track, options.auto_install == true)
  if not fx_index or not r.TrackFX_GetParam or not r.TrackFX_SetParam then return false, status or "Meter unavailable" end
  r.TrackFX_SetParam(track, fx_index, 1, 1)
  if r.TrackFX_SetParamNormalized then r.TrackFX_SetParamNormalized(track, fx_index, 1, 1) end
  r.TrackFX_SetParam(track, fx_index, M.sliders.momentary_max.index, -100)
  r.TrackFX_SetParam(track, fx_index, M.sliders.short_term.index, -100)
  r.TrackFX_SetParam(track, fx_index, M.sliders.integrated.index, -100)
  r.TrackFX_SetParam(track, fx_index, M.sliders.range.index, 0)
  r.TrackFX_SetParam(track, fx_index, M.sliders.true_peak.index, -100)
  r.TrackFX_SetParam(track, fx_index, M.sliders.time.index, 0)
  r.TrackFX_SetParam(track, fx_index, M.sliders.momentary.index, -100)
  r.TrackFX_SetParam(track, fx_index, M.sliders.sample_peak.index, -100)
  info_cache = {}
  return true, nil
end

function M.reset_source(source, settings)
  settings = type(settings) == "table" and settings or {}
  if not source_uses_engine(source) then return false, "Peak only" end
  return M.reset(source.track, { auto_install = settings.meter_fx_auto_install ~= false })
end

local function read_slider(track, fx_index, spec)
  if not valid_track(track) or not fx_index or not spec or not r.TrackFX_GetParam then return nil end
  local value = r.TrackFX_GetParam(track, fx_index, spec.index)
  value = tonumber(value)
  if not value then return nil end
  if spec.min and value < spec.min then value = spec.min end
  if spec.max and value > spec.max then value = spec.max end
  return value
end

source_uses_engine = function(source)
  if not source or not source.id then return false end
  return source.id == "master" or tostring(source.id):match("^cue:") ~= nil
end

local function format_meter_value(value)
  if type(value) ~= "number" then return "--" end
  if value <= -99.95 then return "-inf" end
  return string.format("%.1f", value)
end

local function format_meter_range(value)
  if type(value) ~= "number" then return "--" end
  return string.format("%.1f", math.max(0, value))
end

local function format_meter_time(value)
  if type(value) ~= "number" then return "--:--:--" end
  local seconds = math.max(0, math.floor(value + 0.5))
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  seconds = seconds % 60
  return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

local function format_signed(value)
  if type(value) ~= "number" then return "--" end
  return string.format("%+.1f", value)
end

local function format_positive(value)
  if type(value) ~= "number" then return "--" end
  return string.format("%.1f", math.max(0, value))
end

local function metric(label, value, unit, ready, color)
  if ready == false then return { label = label, value = "Warming", unit = "", color = color } end
  return { label = label, value = format_meter_value(value), unit = unit, color = color }
end

local function selected_items(settings)
  local selected = {}
  local seen = {}
  local source = type(settings.meter_display_items) == "table" and settings.meter_display_items or M.default_display_items
  for _, id in ipairs(source) do
    if type(id) == "string" and not seen[id] and #selected < M.max_display_items then
      seen[id] = true
      selected[#selected + 1] = id
    end
  end
  return selected
end

function M.read(track, options)
  options = type(options) == "table" and options or {}
  local fx_index, status = M.ensure_meter_fx(track, options.auto_install == true)
  if not fx_index then return { available = false, status = status or "Meter unavailable" } end
  return {
    available = true,
    status = nil,
    track_guid = track_guid(track),
    fx_index = fx_index,
    momentary_max = read_slider(track, fx_index, M.sliders.momentary_max),
    short_term = read_slider(track, fx_index, M.sliders.short_term),
    integrated = read_slider(track, fx_index, M.sliders.integrated),
    range = read_slider(track, fx_index, M.sliders.range),
    true_peak = read_slider(track, fx_index, M.sliders.true_peak),
    time = read_slider(track, fx_index, M.sliders.time),
    momentary = read_slider(track, fx_index, M.sliders.momentary),
    sample_peak = read_slider(track, fx_index, M.sliders.sample_peak)
  }
end

function M.info_items(settings, source, colors)
  settings = type(settings) == "table" and settings or {}
  colors = type(colors) == "table" and colors or {}
  local key = source_key(source)
  local timestamp = now()
  local read_hz = math.max(1, tonumber(settings.meter_read_hz) or 20)
  local cached = info_cache[key]
  if cached and timestamp - cached.timestamp < 1 / read_hz then return cached.items end
  local data = source_uses_engine(source) and M.read(source.track, { auto_install = settings.meter_fx_auto_install ~= false }) or { available = false, status = "Peak only" }
  local true_peak_color = data.true_peak and data.true_peak >= 0 and colors.danger or nil
  local elapsed = tonumber(data.time) or 0
  local available = data.available == true
  local target = tonumber(settings.meter_target_lufs) or M.default_target_lufs
  local true_peak = type(data.true_peak) == "number" and data.true_peak or data.sample_peak
  local all_items = {
    momentary = metric("Momentary", data.momentary, "LUFS", not available or elapsed >= 0.4),
    momentary_max = metric("Momentary Max", data.momentary_max, "LUFS", not available or elapsed >= 0.4),
    short_term = metric("Short-Term", data.short_term, "LUFS", not available or elapsed >= 3),
    integrated = metric("Integrated", data.integrated, "LUFS", not available or elapsed >= 0.4),
    range = { label = "Range", value = not available and "--" or (elapsed >= 5 and format_meter_range(data.range) or "Warming"), unit = available and elapsed >= 5 and "LU" or "" },
    estimated_true_peak = metric("Est. True Peak", true_peak, "dBTP", true, true_peak_color),
    sample_peak = metric("Sample Peak", data.sample_peak, "dB", true),
    time = { label = "Time", value = available and format_meter_time(data.time) or tostring(data.status or "Waiting"), unit = "" },
    headroom = { label = "Headroom", value = available and format_positive(0 - (true_peak or 0)) or "--", unit = available and "dB" or "" },
    target_delta = { label = "Target Delta", value = available and elapsed >= 0.4 and type(data.integrated) == "number" and format_signed(data.integrated - target) or (available and "Warming" or "--"), unit = available and elapsed >= 0.4 and "LU" or "" },
    plr = { label = "PLR", value = available and elapsed >= 0.4 and type(data.integrated) == "number" and type(true_peak) == "number" and format_positive(true_peak - data.integrated) or (available and "Warming" or "--"), unit = available and elapsed >= 0.4 and "LU" or "" },
    isp_delta = { label = "ISP Delta", value = available and type(true_peak) == "number" and type(data.sample_peak) == "number" and format_positive(true_peak - data.sample_peak) or "--", unit = available and "dB" or "" }
  }
  local items = {}
  for _, id in ipairs(selected_items(settings)) do
    if all_items[id] then items[#items + 1] = all_items[id] end
  end
  info_cache[key] = { timestamp = timestamp, items = items }
  return items
end

return M